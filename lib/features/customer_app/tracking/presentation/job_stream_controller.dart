import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      // Maps the internal R2 key to the public CDN endpoint dynamically
      publicUrl: '$bucketUrlPath/$key',
    );
  }
}

class JobStreamState {
  final String currentStatus;
  final List<RepairPhoto> photos;
  final bool isDisconnected;
  final bool isLoading;

  JobStreamState({
    this.currentStatus = '1_intake',
    this.photos = const [],
    this.isDisconnected = false,
    this.isLoading = true,
  });

  JobStreamState copyWith({
    String? currentStatus,
    List<RepairPhoto>? photos,
    bool? isDisconnected,
    bool? isLoading,
  }) {
    return JobStreamState(
      currentStatus: currentStatus ?? this.currentStatus,
      photos: photos ?? this.photos,
      isDisconnected: isDisconnected ?? this.isDisconnected,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// --- CONTROLLER IMPLEMENTATION ---

final jobStreamProvider = StateNotifierProvider.family<JobStreamController, JobStreamState, String>((ref, jobId) {
  return JobStreamController(Supabase.instance.client, jobId);
});

class JobStreamController extends StateNotifier<JobStreamState> {
  final SupabaseClient _supabase;
  final String _jobId;
  
  StreamSubscription? _jobSubscription;
  StreamSubscription? _photoSubscription;
  Timer? _reconnectTimer;
  
  // REL-04 FIX: Use unified 'revive-photos' bucket (same name used by upload paths)
  final String _cdnBucketPath = Supabase.instance.client.storage.from('revive-photos').getPublicUrl('');

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
