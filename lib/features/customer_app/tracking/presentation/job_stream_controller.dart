import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/jobs/repair_stages.dart';

// --- STATE DEFINITIONS ---

class RepairPhoto {
  final String id;
  final String context; // 'intake', 'progress', 'finished'
  final String r2FileKey;
  final String publicUrl;

  RepairPhoto({
    required this.id,
    required this.context,
    required this.r2FileKey,
    required this.publicUrl,
  });

  factory RepairPhoto.fromMap(Map<String, dynamic> map, String bucketUrlPath) {
    final key = map['r2_file_key'] as String;
    return RepairPhoto(
      id: map['id'] as String,
      context: map['step_context'] as String,
      r2FileKey: key,
      // SEC-04: bucket private — store file key, SignedImage resolves URL
      publicUrl: key,
    );
  }
}

class JobStreamState {
  final String currentStatus;
  final List<RepairPhoto> photos;
  final bool isDisconnected;
  final bool isLoading;

  /// The six body & paint steps, keyed by `job_milestones.stage_key`.
  ///
  /// This is what turns "Pengerjaan Bodi & Pengecatan" from one opaque step into
  /// bongkar / ketok-las / dempul / cat / poles / pasang. It arrives over its own
  /// realtime subscription, so the customer sees each stage land without
  /// reloading. Empty until the floor records the first one, which is a valid
  /// state — a car in the queue has no stages yet.
  final Map<String, RepairStageProgress> stageProgress;

  JobStreamState({
    this.currentStatus = '1_intake',
    this.photos = const [],
    this.isDisconnected = false,
    this.isLoading = true,
    this.stageProgress = const {},
  });

  JobStreamState copyWith({
    String? currentStatus,
    List<RepairPhoto>? photos,
    bool? isDisconnected,
    bool? isLoading,
    Map<String, RepairStageProgress>? stageProgress,
  }) {
    return JobStreamState(
      currentStatus: currentStatus ?? this.currentStatus,
      photos: photos ?? this.photos,
      isDisconnected: isDisconnected ?? this.isDisconnected,
      isLoading: isLoading ?? this.isLoading,
      stageProgress: stageProgress ?? this.stageProgress,
    );
  }
}

// --- CONTROLLER IMPLEMENTATION ---

// C-39 fix: autoDispose so channels are cancelled when screen leaves tree
final jobStreamProvider = StateNotifierProvider.autoDispose.family<JobStreamController, JobStreamState, String>((ref, jobId) {
  final controller = JobStreamController(Supabase.instance.client, jobId);
  ref.onDispose(() => controller.dispose());
  return controller;
});

class JobStreamController extends StateNotifier<JobStreamState> {
  final SupabaseClient _supabase;
  final String _jobId;

  StreamSubscription? _jobSubscription;
  StreamSubscription? _photoSubscription;
  StreamSubscription? _milestoneSubscription;
  StreamSubscription? _milestonePhotoSubscription;
  Timer? _reconnectTimer;

  // The two milestone streams are filtered server-side by job_id, so both hold
  // only this job's rows. Rebuilt into one map on every change.
  List<Map<String, dynamic>> _milestoneRows = const [];
  List<Map<String, dynamic>> _milestonePhotoRows = const [];

  // SEC-04/PRIV-01: Bucket revive-photos kini private.
  // URL foto job dihasilkan per-foto via createSignedUrl di job photo loading.
  // Variabel ini dipertahankan untuk kompatibilitas — nilainya diabaikan.
  // TODO: Hapus setelah semua caller beralih ke signedPhotoUrl() helper.
  final String _cdnBucketPath = '';

  // REL-06 FIX: Exponential backoff state
  int _retryCount = 0;
  static const int _maxRetries = 10;
  static const List<int> _backoffSeconds = [5, 10, 20, 40, 80, 120];

  Duration get _nextBackoff {
    final index = (_retryCount - 1).clamp(0, _backoffSeconds.length - 1);
    return Duration(seconds: _backoffSeconds[index]);
  }


  JobStreamController(this._supabase, this._jobId) : super(JobStreamState()) {
    _initializeStreams();
  }

  @override
  void dispose() {
    _cancelStreams();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  void _cancelStreams() {
    _jobSubscription?.cancel();
    _photoSubscription?.cancel();
    _milestoneSubscription?.cancel();
    _milestonePhotoSubscription?.cancel();
  }

  /// Rebuilds [JobStreamState.stageProgress] from the two milestone streams.
  ///
  /// Photo counts are attached from `job_milestone_photos`. They are shown to the
  /// customer as information only — progress photos are optional, so a completed
  /// stage with no photo is normal and must not look like a failure.
  void _rebuildStageProgress() {
    final byMilestoneId = <String, int>{};
    for (final row in _milestonePhotoRows) {
      final mid = row['milestone_id']?.toString();
      if (mid == null) continue;
      byMilestoneId[mid] = (byMilestoneId[mid] ?? 0) + 1;
    }

    final progress = <String, RepairStageProgress>{};
    for (final row in _milestoneRows) {
      final key = row['stage_key']?.toString() ?? '';
      if (!kBodyPaintStageKeys.contains(key)) continue;
      final parsed = RepairStageProgress.fromRow(row);
      final count = byMilestoneId[row['id']?.toString()] ?? 0;
      progress[key] = parsed.withPhotoCount(count);
    }

    state = state.copyWith(stageProgress: progress);
  }

  /// Establishes the explicit Supabase Realtime websocket subscriptions for both the job state and the photo ledger.
  /// Wrapped in defensive try/catch architecture to trap cell-drop disconnects.
  void _initializeStreams() {
    // --- UI DEMO BYPASS FOR DUMMY IDs ---
    if (_jobId.startsWith('JB-')) {
      state = state.copyWith(
        currentStatus: '3_booked', // Mock booked status
        isDisconnected: false,
        isLoading: false,
      );
      return;
    }

    try {
      _cancelStreams();

      // 1. Subscribe to Job Status Mutations
      _jobSubscription = _supabase
          .from('repair_jobs')
          .stream(primaryKey: ['id'])
          .eq('id', _jobId)
          .listen((data) {
            if (data.isNotEmpty) {
              // REL-06: Reset backoff counter on successful data receipt
              _retryCount = 0;
              state = state.copyWith(
                currentStatus: data.first['status'] as String,
                isDisconnected: false,
                isLoading: false,
              );
            } else {
              // Handle case where job is not found
              state = state.copyWith(isLoading: false);
            }
          }, onError: (error) {
            _handleStreamDisconnect();
          });

      // 2. Subscribe to Photo Upload LEDGER Mutations
      _photoSubscription = _supabase
          .from('repair_photos')
          .stream(primaryKey: ['id'])
          .eq('job_id', _jobId)
          .order('uploaded_at', ascending: false)
          .listen((data) {
            final parsedPhotos = data.map((map) => RepairPhoto.fromMap(map, _cdnBucketPath)).toList();
            state = state.copyWith(
              photos: parsedPhotos,
              isDisconnected: false,
            );
          }, onError: (error) {
            _handleStreamDisconnect();
          });

      // 3. Subscribe to the repair STAGE milestones — this is the six-step body
      //    & paint progress the customer monitors. Published to realtime by
      //    20261126000000_body_paint_stage_tracking.sql.
      _milestoneSubscription = _supabase
          .from('job_milestones')
          .stream(primaryKey: ['id'])
          .eq('job_id', _jobId)
          .listen((data) {
            _milestoneRows = List<Map<String, dynamic>>.from(data);
            _rebuildStageProgress();
          }, onError: (error) {
            _handleStreamDisconnect();
          });

      // 4. Subscribe to the milestone photo ledger, purely for the "2 foto" note
      //    beside a completed stage.
      _milestonePhotoSubscription = _supabase
          .from('job_milestone_photos')
          .stream(primaryKey: ['id'])
          .eq('job_id', _jobId)
          .listen((data) {
            _milestonePhotoRows = List<Map<String, dynamic>>.from(data);
            _rebuildStageProgress();
          }, onError: (error) {
            _handleStreamDisconnect();
          });

    } catch (e) {
      _handleStreamDisconnect();
    }
  }

  /// REL-06 FIX: Exponential backoff reconnect instead of flat 5s retry.
  /// After [_maxRetries] attempts the controller gives up and leaves
  /// isDisconnected = true so the UI can show a "Reconnect" button.
  void _handleStreamDisconnect() {
    if (!state.isDisconnected) {
      state = state.copyWith(isDisconnected: true);
    }

    _retryCount++;

    if (_retryCount > _maxRetries) {
      // Give up — let the UI surface a manual reconnect option
      debugPrint('[JobStream] Max retries ($_maxRetries) reached. Giving up auto-reconnect.');
      return;
    }

    final backoff = _nextBackoff;
    debugPrint('[JobStream] Reconnecting in ${backoff.inSeconds}s (attempt $_retryCount/$_maxRetries)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, () {
      _initializeStreams();
    });
  }
}
