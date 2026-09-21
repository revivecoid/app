import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/utils/image_compressor.dart';

// --- DOMAIN MODELS ---

class PartnerJobNode {
  final String id;
  final String customerName;
  final String carMake;
  final String carModel;
  final String licensePlate;
  final String status;
  final DateTime admittedAt;
  final String? latestPhotoUrl;

  /// The number the customer booked with, snapshotted on the job. This is what
  /// the workshop rings to arrange or chase a pickup — preferred over the
  /// profile number, which may have changed since the booking was made.
  final String? contactPhone;

  /// Fallback when the job carries no number (bookings made before the snapshot
  /// column existed) and the profile has one.
  final String? profilePhone;
  final String? profileEmail;

  PartnerJobNode({
    required this.id,
    required this.customerName,
    required this.carMake,
    required this.carModel,
    required this.licensePlate,
    required this.status,
    required this.admittedAt,
    this.latestPhotoUrl,
    this.contactPhone,
    this.profilePhone,
    this.profileEmail,
  });

  PartnerJobNode copyWith({String? status, String? latestPhotoUrl}) {
    return PartnerJobNode(
      id: id,
      customerName: customerName,
      carMake: carMake,
      carModel: carModel,
      licensePlate: licensePlate,
      status: status ?? this.status,
      admittedAt: admittedAt,
      latestPhotoUrl: latestPhotoUrl ?? this.latestPhotoUrl,
      contactPhone: contactPhone,
      profilePhone: profilePhone,
      profileEmail: profileEmail,
    );
  }
}

class PartnerDashboardState {
  final String partnerId;
  final List<PartnerJobNode> activeJobs;
  final bool isLoading;
  final String? errorMessage;
  final bool isOfflineSyncing;
  final int unreadMessageCount;

  PartnerDashboardState({
    required this.partnerId,
    this.activeJobs = const [],
    this.isLoading = true,
    this.errorMessage,
    this.isOfflineSyncing = false,
    this.unreadMessageCount = 0,
  });

  PartnerDashboardState copyWith({
    List<PartnerJobNode>? activeJobs,
    bool? isLoading,
    String? errorMessage,
    bool? isOfflineSyncing,
    int? unreadMessageCount,
  }) {
    return PartnerDashboardState(
      partnerId: partnerId,
      activeJobs: activeJobs ?? this.activeJobs,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isOfflineSyncing: isOfflineSyncing ?? this.isOfflineSyncing,
      unreadMessageCount: unreadMessageCount ?? this.unreadMessageCount,
    );
  }
}

// --- STATE CONTROLLER ---

final partnerDashboardProvider = StateNotifierProvider<PartnerDashboardController, PartnerDashboardState>((ref) {
  return PartnerDashboardController(Supabase.instance.client);
});

class PartnerDashboardController extends StateNotifier<PartnerDashboardState> {
  final SupabaseClient _supabase;
  RealtimeChannel? _realtimeSub;
  Timer? _syncTimer;
  final ImagePicker _imagePicker = ImagePicker();

  // Strict 9-Stage ENUM transition mapper
  static const List<String> _stages = [
    '1_intake', '2_estimated', '3_booked', '4_paid', 
    '5_admitted', '6_in_progress', '7_finished', '8_awaiting_delivery', '9_done'
  ];

  PartnerDashboardController(this._supabase) : super(PartnerDashboardState(partnerId: '')) {
    _initializeTenantIsolation();
  }

  @override
  void dispose() {
    _realtimeSub?.unsubscribe();
    _unreadSub?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeTenantIsolation() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Unauthorized Access: Active session not found.');

      // SEC-08 FIX: Extract Tenant ID from app_metadata ONLY (set by service_role via approve-partner).
      // user_metadata is self-writable and MUST NOT be trusted for tenant isolation.
      final tenantId = user.appMetadata['partner_id'] as String?;
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('Tenant Isolation Failure: No partner_id found in app_metadata. Contact admin.');
      }

      state = PartnerDashboardState(partnerId: tenantId, isLoading: true);

      await _fetchIsolatedData();
      _subscribeToIsolatedStream();
      _subscribeToUnreadMessages();
      _startOfflineRecoverySync();

    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  StreamSubscription? _unreadSub;

  void _subscribeToUnreadMessages() {
    _unreadSub = _supabase
        .from('partner_messages')
        .stream(primaryKey: ['id'])
        .eq('partner_id', state.partnerId)
        .listen((data) {
      final currentUserId = _supabase.auth.currentUser?.id;
      int unread = 0;
      for (final row in data) {
        if (row['sender_id'] != currentUserId && row['is_read'] == false) {
          unread++;
        }
      }
      state = state.copyWith(unreadMessageCount: unread);
    });
  }

  Future<void> _fetchIsolatedData() async {
    try {
      // Server-side strict RLS ensures we only pull the tenant's exact data array
      final response = await _supabase.from('repair_jobs').select('''
        id, status, created_at, contact_phone, customer_id,
        profiles:customer_id (full_name, phone, email),
        vehicles:vehicle_id (make, model, license_plate),
        repair_photos (r2_file_key, uploaded_at)
      ''').eq('partner_id', state.partnerId).inFilter('status', [
        '3_booked', '4_paid', '5_admitted', '6_in_progress',
        '7_finished', '8_awaiting_delivery'
      ]);


      final List<PartnerJobNode> jobs = (response as List).map((job) {
        final profile = job['profiles'] as Map<String, dynamic>? ?? {};
        final vehicle = job['vehicles'] as Map<String, dynamic>? ?? {};
        
        String? latestPhotoUrl;
        final photos = job['repair_photos'] as List?;
        if (photos != null && photos.isNotEmpty) {
          photos.sort((a, b) => DateTime.parse(b['uploaded_at'].toString()).compareTo(DateTime.parse(a['uploaded_at'].toString())));
          // REL-04 FIX: Use unified 'revive-photos' bucket (same as customer upload)
          latestPhotoUrl = _supabase.storage.from('revive-photos').getPublicUrl(photos.first['r2_file_key'].toString());
        }

        return PartnerJobNode(
          id: job['id'].toString(),
          customerName: profile['full_name']?.toString() ?? 'Unknown',
          carMake: vehicle['make']?.toString() ?? 'Unknown',
          carModel: vehicle['model']?.toString() ?? 'Unknown',
          licensePlate: vehicle['license_plate']?.toString() ?? 'No Plate',
          status: job['status'].toString(),
          admittedAt: DateTime.parse(job['created_at'].toString()),
          latestPhotoUrl: latestPhotoUrl,
          contactPhone: job['contact_phone']?.toString(),
          profilePhone: profile['phone']?.toString(),
          profileEmail: profile['email']?.toString(),
        );
      }).toList();

      state = state.copyWith(activeJobs: jobs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to fetch workshop data: $e');
    }
  }

  void _subscribeToIsolatedStream() {
    _realtimeSub?.unsubscribe();
    // Subscribe exclusively to the isolated tenant's data mutations
    _realtimeSub = _supabase
        .channel('public:repair_jobs:partner_id=eq.${state.partnerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'repair_jobs',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'partner_id', value: state.partnerId),
          callback: (payload) {
            final jobId = payload.newRecord['id'].toString();
            final newStatus = payload.newRecord['status'].toString();

            final index = state.activeJobs.indexWhere((j) => j.id == jobId);
            if (index != -1) {
              if (newStatus == '9_done') {
                final updated = List<PartnerJobNode>.from(state.activeJobs)..removeAt(index);
                state = state.copyWith(activeJobs: updated);
              } else {
                final updated = List<PartnerJobNode>.from(state.activeJobs);
                updated[index] = updated[index].copyWith(status: newStatus);
                state = state.copyWith(activeJobs: updated);
              }
            } else {
              _fetchIsolatedData(); // New job entered our matrix boundaries
            }
          },
        ).subscribe();
  }

  /// Advances the vehicle to the next pipeline stage safely.
  /// NOTE: 3_inspected and 4_paid are NOT in this path — invoice issuance
  /// is done via partner_issue_invoice RPC, and payment is customer-initiated.
  Future<void> advanceJobStage(String jobId, String currentStage) async {
    // Partner cannot advance to 3_inspected (done via Issue Invoice dialog)
    // or to 4_paid (customer-only after invoice review).
    // Handled stages: 3_booked/4_paid → 5_admitted, 5_admitted → 6_in_progress,
    //                 6_in_progress → 7_finished, 7_finished → 8_awaiting_delivery
    final partnerAdvanceMap = <String, String>{
      '3_booked': '5_admitted',
      '5_admitted': '6_in_progress',
      '6_in_progress': '7_finished',
      '7_finished': '8_awaiting_delivery',
    };

    final nextStage = partnerAdvanceMap[currentStage];
    if (nextStage == null) return; // No valid advance for this status

    try {
      // Optimistic local update — move card immediately in the UI
      final jobIndex = state.activeJobs.indexWhere((j) => j.id == jobId);
      if (jobIndex != -1) {
        final updated = List<PartnerJobNode>.from(state.activeJobs);
        if (nextStage == '9_done') {
          updated.removeAt(jobIndex);
        } else {
          updated[jobIndex] = updated[jobIndex].copyWith(status: nextStage);
        }
        state = state.copyWith(activeJobs: updated, errorMessage: null);
      }

      // Server-side RPC with validated transition
      await _supabase.rpc('advance_job_status', params: {
        'p_job_id': jobId,
        'p_new_status': nextStage,
      });

      // Refresh to ensure consistency (Realtime may not catch own updates)
      await _fetchIsolatedData();

    } catch (e) {
      // Roll back optimistic update on failure
      await _fetchIsolatedData();
      final errText = e.toString()
          .replaceAll('PostgrestException', '')
          .replaceAll('Exception:', '')
          .trim();
      state = state.copyWith(
        errorMessage: 'Could not advance stage: $errText',
      );
    }
  }

  /// Executes the Mobile Client-Side Compression & Streaming Pipeline
  Future<void> captureAndUploadProgressPhoto(String jobId, String currentContext) async {
    try {
      // 1. Pick image — camera on mobile, gallery on web
      final source = kIsWeb ? ImageSource.gallery : ImageSource.camera;
      final XFile? rawImage = await _imagePicker.pickImage(source: source);
      if (rawImage == null) return; // User cancelled

      state = state.copyWith(isLoading: true, errorMessage: null);

      // 2. Client-side compression (<300KB constraint)
      final compressedBytes = await ImageCompressor.compressImage(rawImage);

      // 3. Upload to Supabase Storage (user-scoped path for RLS)
      final userId = _supabase.auth.currentUser!.id;
      final fileName = '$userId/${state.partnerId}_${jobId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await _supabase.storage.from('revive-photos').uploadBinary(
        fileName,
        compressedBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );

      // 4. Insert photo record
      await _supabase.from('repair_photos').insert({
        'job_id': jobId,
        'step_context': currentContext.replaceAll(RegExp(r'^\d+_'), ''),
        'r2_file_key': fileName,
        'uploaded_at': DateTime.now().toIso8601String(),
      });

      // 5. Immediately update the job card thumbnail in local state
      final publicUrl = _supabase.storage.from('revive-photos').getPublicUrl(fileName);
      final jobIndex = state.activeJobs.indexWhere((j) => j.id == jobId);
      if (jobIndex != -1) {
        final updated = List<PartnerJobNode>.from(state.activeJobs);
        updated[jobIndex] = updated[jobIndex].copyWith(latestPhotoUrl: publicUrl);
        state = state.copyWith(
          activeJobs: updated,
          isLoading: false,
          errorMessage: 'Photo uploaded successfully.',
        );
      } else {
        state = state.copyWith(isLoading: false, errorMessage: 'Photo uploaded successfully.');
      }

    } catch (e) {
      debugPrint('[PhotoUpload] Error: $e');
      final errText = e.toString()
          .replaceAll('PostgrestException', '')
          .replaceAll('StorageException', '')
          .replaceAll('Exception:', '')
          .trim();
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Upload failed: $errText',
      );
    }
  }

  // --- OFFLINE SYNC HARDENING PIPELINE ---

  Future<void> _queueOfflineAction(Map<String, dynamic> action) async {
    if (kIsWeb) {
      // REL-02 FIX: Web has no offline queue — be honest about failure.
      // Previously this only called debugPrint but UI said "queued for retry".
      // TODO(SEC-12): Implement IndexedDB-based queue for real offline support on Web.
      debugPrint('[OfflineQueue] Web: action NOT queued (no IndexedDB impl): ${action['type']}');
      return;
    }
    // Mobile path
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/re_v_offline_sync_queue.json');
      List<dynamic> queue = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) queue = jsonDecode(content);
      }
      queue.add(action);
      await file.writeAsString(jsonEncode(queue));
    } catch (e) {
      debugPrint('[OfflineQueue] Failed to persist action: $e');
    }
  }

  void _startOfflineRecoverySync() {
    _syncTimer?.cancel();
    if (!kIsWeb) {
      _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) => _executeSyncQueue());
    }
  }

  Future<void> _executeSyncQueue() async {
    if (kIsWeb || state.isOfflineSyncing) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/re_v_offline_sync_queue.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final List<dynamic> queue = jsonDecode(content);
      if (queue.isEmpty) return;

      state = state.copyWith(isOfflineSyncing: true);
      List<dynamic> failedItems = [];

      for (final item in queue) {
        try {
          final action = item as Map<String, dynamic>;
          if (action['type'] == 'UPDATE_STATUS') {
            // INT-02 FIX: Use RPC for server-side transition validation
            await _supabase.rpc('advance_job_status', params: {
              'p_job_id': action['job_id'],
              'p_new_status': action['payload'],
            });
          } else if (action['type'] == 'UPLOAD_PHOTO' && action['local_path'] != null) {
            final localFile = File(action['local_path'] as String);
            if (await localFile.exists()) {
              final bytes = await localFile.readAsBytes();
              await _supabase.storage.from('revive-photos').uploadBinary(
                action['r2_key'] as String, 
                bytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
              await _supabase.from('repair_photos').insert({
                'job_id': action['job_id'],
                'step_context': action['context'].toString().replaceAll(RegExp(r'^\d+_'), ''),
                'r2_file_key': action['r2_key'],
                'uploaded_at': DateTime.now().toIso8601String(),
              });
              await localFile.delete(); // Clear cache
            }
          }
        } catch (e) {
          failedItems.add(item); // Keep in queue if it fails again
        }
      }

      await file.writeAsString(jsonEncode(failedItems));
      state = state.copyWith(isOfflineSyncing: false);

    } catch (e) {
      state = state.copyWith(isOfflineSyncing: false);
    }
  }
}
