import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Version models ───────────────────────────────────────────────────────────

class PartnerDocVersion {
  final String id;
  final String fileKey;
  final String fileName;
  final int? fileSize;
  final DateTime uploadedAt;
  final bool isCurrent;

  const PartnerDocVersion({
    required this.id,
    required this.fileKey,
    required this.fileName,
    this.fileSize,
    required this.uploadedAt,
    required this.isCurrent,
  });

  factory PartnerDocVersion.fromMap(Map<String, dynamic> m) => PartnerDocVersion(
        id: m['id']?.toString() ?? '',
        fileKey: m['file_key']?.toString() ?? '',
        fileName: m['file_name']?.toString() ?? '',
        fileSize: m['file_size'] as int?,
        uploadedAt: m['uploaded_at'] != null
            ? DateTime.tryParse(m['uploaded_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isCurrent: m['is_current'] == true,
      );
}

class PartnerPhotoVersion {
  final String id;
  final int slot;
  final String? label;
  final String fileKey;
  final DateTime uploadedAt;
  final bool isCurrent;

  const PartnerPhotoVersion({
    required this.id,
    required this.slot,
    this.label,
    required this.fileKey,
    required this.uploadedAt,
    required this.isCurrent,
  });

  factory PartnerPhotoVersion.fromMap(Map<String, dynamic> m) => PartnerPhotoVersion(
        id: m['id']?.toString() ?? '',
        slot: (m['slot'] as num?)?.toInt() ?? 0,
        label: m['label']?.toString(),
        fileKey: m['file_key']?.toString() ?? '',
        uploadedAt: m['uploaded_at'] != null
            ? DateTime.tryParse(m['uploaded_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isCurrent: m['is_current'] == true,
      );
}

// ─── State ────────────────────────────────────────────────────────────────────

class PartnerProfileState {
  final bool isLoading;
  final bool isSaving;
  final Map<String, dynamic>? partnerData;
  final int totalJobsDone;
  final double avgRepairDays;
  /// doc_type → all versions, newest first. Current version is [0] when is_current=true.
  final Map<String, List<PartnerDocVersion>> documents;
  /// slot index → all versions, newest first
  final List<List<PartnerPhotoVersion>> facilityPhotos;
  /// Uploading state per doc_type or slot key ('photo_0' etc.)
  final Set<String> uploading;
  final String? errorMessage;
  final String? successMessage;
  final String ownerName;

  // Keep facilityPhotoUrls for backward compat with shell (unread count etc.)
  List<String> get facilityPhotoUrls => facilityPhotos
      .map((slot) => slot.isEmpty ? '' : slot.first.isCurrent ? slot.first.fileKey : '')
      .where((k) => k.isNotEmpty)
      .toList();

  const PartnerProfileState({
    this.isLoading = true,
    this.isSaving = false,
    this.partnerData,
    this.totalJobsDone = 0,
    this.avgRepairDays = 0.0,
    this.documents = const {},
    this.facilityPhotos = const [[], [], [], []],
    this.uploading = const {},
    this.errorMessage,
    this.successMessage,
    this.ownerName = '',
  });

  PartnerProfileState copyWith({
    bool? isLoading,
    bool? isSaving,
    Map<String, dynamic>? partnerData,
    bool clearPartnerData = false,
    int? totalJobsDone,
    double? avgRepairDays,
    Map<String, List<PartnerDocVersion>>? documents,
    List<List<PartnerPhotoVersion>>? facilityPhotos,
    Set<String>? uploading,
    String? errorMessage,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
    String? ownerName,
  }) =>
      PartnerProfileState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        partnerData: clearPartnerData ? null : (partnerData ?? this.partnerData),
        totalJobsDone: totalJobsDone ?? this.totalJobsDone,
        avgRepairDays: avgRepairDays ?? this.avgRepairDays,
        documents: documents ?? this.documents,
        facilityPhotos: facilityPhotos ?? this.facilityPhotos,
        uploading: uploading ?? this.uploading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
        ownerName: ownerName ?? this.ownerName,
      );
}

// ─── Controller ───────────────────────────────────────────────────────────────

class PartnerProfileController extends StateNotifier<PartnerProfileState> {
  final SupabaseClient _sb = Supabase.instance.client;
  static const _bucket = 'revive-photos-r2-proxy';

  String? _partnerId; // null until we find/create the partners row

  PartnerProfileController() : super(const PartnerProfileState()) {
    _init();
  }

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // Try to find partner row: first by id = auth.uid (self-registered),
      // then by user_id = auth.uid (admin-created).
      Map<String, dynamic>? partnerData = await _sb
          .from('partners')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (partnerData == null) {
        partnerData = await _sb
            .from('partners')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
      }

      _partnerId = partnerData?['id']?.toString() ?? user.id;

      // Resolve display name
      final workshopName = partnerData?['entity_name']?.toString().trim() ??
          partnerData?['shop_name']?.toString().trim() ?? '';
      String resolvedName = workshopName;
      if (resolvedName.isEmpty) {
        resolvedName = user.userMetadata?['full_name']?.toString().trim() ??
            user.userMetadata?['name']?.toString().trim() ??
            user.email ?? '';
      }

      state = state.copyWith(
        isLoading: false,
        partnerData: partnerData,  // may be null → empty form
        ownerName: resolvedName,
      );

      // Load versioned docs/photos and KPIs in parallel (non-fatal)
      await Future.wait([
        _loadDocuments(),
        _loadFacilityPhotos(),
        _loadKpis(),
      ]);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _loadDocuments() async {
    if (_partnerId == null) return;
    try {
      final rows = await _sb
          .from('partner_documents')
          .select()
          .eq('partner_id', _partnerId!)
          .order('uploaded_at', ascending: false);

      final Map<String, List<PartnerDocVersion>> grouped = {
        'nib': [], 'npwp': [], 'siup': [], 'ktp': [],
      };
      for (final row in rows as List) {
        final v = PartnerDocVersion.fromMap(row as Map<String, dynamic>);
        grouped[v.fileKey.split('/').last]?.add(v); // keyed by doc_type from DB
      }
      // Re-group properly by doc_type column
      final Map<String, List<PartnerDocVersion>> byType = {
        'nib': [], 'npwp': [], 'siup': [], 'ktp': [],
      };
      for (final row in rows as List) {
        final v = PartnerDocVersion.fromMap(row as Map<String, dynamic>);
        final type = (row as Map<String, dynamic>)['doc_type']?.toString() ?? '';
        if (byType.containsKey(type)) byType[type]!.add(v);
      }
      state = state.copyWith(documents: byType);
    } catch (_) {}
  }

  Future<void> _loadFacilityPhotos() async {
    if (_partnerId == null) return;
    try {
      final rows = await _sb
          .from('partner_facility_photos')
          .select()
          .eq('partner_id', _partnerId!)
          .order('uploaded_at', ascending: false);

      final List<List<PartnerPhotoVersion>> slots = [[], [], [], []];
      for (final row in rows as List) {
        final v = PartnerPhotoVersion.fromMap(row as Map<String, dynamic>);
        if (v.slot >= 0 && v.slot <= 3) slots[v.slot].add(v);
      }
      state = state.copyWith(facilityPhotos: slots);
    } catch (_) {}
  }

  Future<void> _loadKpis() async {
    if (_partnerId == null) return;
    try {
      final jobs = await _sb
          .from('repair_jobs')
          .select('created_at, updated_at')
          .eq('partner_id', _partnerId!)
          .eq('status', '9_done');
      final list = jobs as List;
      double sum = 0;
      for (final j in list) {
        final c = DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now();
        final u = DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? DateTime.now();
        sum += u.difference(c).inHours / 24.0;
      }
      state = state.copyWith(
        totalJobsDone: list.length,
        avgRepairDays: list.isEmpty ? 0.0 : sum / list.length,
      );
    } catch (_) {}
  }

  // ── Save partner details (text fields + selections) ───────────────────────

  Future<void> saveDetails({
    String? entityName,
    String? shopName,
    String? ownerName,
    String? phone,
    String? email,
    String? address,
    int? tier,
    String? paintBrand,
    int? throughputCapacity,
    double? serviceRadiusKm,
    int? workingBays,
    int? sprayBooths,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true, clearSuccess: true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final updates = <String, dynamic>{
        'id': user.id,        // ensures upsert key
        if (entityName != null) 'entity_name': entityName,
        if (shopName != null) 'shop_name': shopName,
        if (ownerName != null) 'owner_name': ownerName,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (address != null) 'address': address,
        if (tier != null) 'tier': tier,
        if (paintBrand != null) 'paint_brand': paintBrand,
        if (throughputCapacity != null) 'throughput_capacity': throughputCapacity,
        if (serviceRadiusKm != null) 'service_radius_km': serviceRadiusKm,
        if (workingBays != null) 'working_bays': workingBays,
        if (sprayBooths != null) 'spray_booths': sprayBooths,
      };

      final result = await _sb
          .from('partners')
          .upsert(updates, onConflict: 'id')
          .select()
          .single();

      _partnerId = result['id']?.toString() ?? user.id;

      // Also resolve new ownerName for shell display
      final resolved = entityName?.trim().isNotEmpty == true
          ? entityName!
          : shopName?.trim().isNotEmpty == true
              ? shopName!
              : state.ownerName;

      state = state.copyWith(
        isSaving: false,
        partnerData: result,
        ownerName: resolved,
        successMessage: 'Details saved successfully.',
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'Save failed: $e');
    }
  }

  // ── Toggle online status ───────────────────────────────────────────────────

  Future<void> toggleOnlineStatus(bool isActive) async {
    try {
      if (_partnerId == null) return;
      await _sb.from('partners').update({'is_active': isActive}).eq('id', _partnerId!);
      final updated = Map<String, dynamic>.from(state.partnerData ?? {});
      updated['is_active'] = isActive;
      state = state.copyWith(partnerData: updated);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update status: $e');
    }
  }

  // ── Upload document (versioned — never overwrites) ────────────────────────

  Future<void> uploadDocument(
    String docType,
    Uint8List bytes,
    String fileName,
  ) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    // Ensure partner row exists first
    if (state.partnerData == null) {
      await saveDetails(shopName: user.email?.split('@').first ?? 'Workshop');
    }
    if (_partnerId == null) return;

    final uploadKey = 'doc_$docType';
    state = state.copyWith(uploading: {...state.uploading, uploadKey});
    try {
      // Timestamped path — never collides with prior versions
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = fileName.contains('.') ? fileName.split('.').last : 'pdf';
      final storageKey =
          'partners/$_partnerId/docs/${docType}_${ts}.$ext';

      await _sb.storage.from(_bucket).uploadBinary(
        storageKey,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      // Demote prior current versions
      await _sb
          .from('partner_documents')
          .update({'is_current': false})
          .eq('partner_id', _partnerId!)
          .eq('doc_type', docType)
          .eq('is_current', true);

      // Insert new version
      await _sb.from('partner_documents').insert({
        'partner_id': _partnerId,
        'doc_type': docType,
        'file_key': storageKey,
        'file_name': fileName,
        'file_size': bytes.length,
        'uploaded_by': user.id,
        'is_current': true,
      });

      // Also update the shortcut column on partners for quick reads
      await _sb
          .from('partners')
          .update({'${docType}_file_key': storageKey}).eq('id', _partnerId!);

      // Reload docs
      await _loadDocuments();
      state = state.copyWith(
        uploading: state.uploading.difference({uploadKey}),
        successMessage: '${docType.toUpperCase()} uploaded successfully.',
      );
    } catch (e) {
      state = state.copyWith(
        uploading: state.uploading.difference({uploadKey}),
        errorMessage: 'Upload failed: $e',
      );
    }
  }

  // ── Upload facility photo (versioned) ─────────────────────────────────────

  static const _photoLabels = [
    'Workshop Facade', 'Spray Oven Booth', 'Customer Lounge', 'Mixing Station'
  ];

  Future<void> uploadFacilityPhoto(int slot, Uint8List bytes) async {
    final user = _sb.auth.currentUser;
    if (user == null || slot < 0 || slot > 3) return;

    if (state.partnerData == null) {
      await saveDetails(shopName: user.email?.split('@').first ?? 'Workshop');
    }
    if (_partnerId == null) return;

    final uploadKey = 'photo_$slot';
    state = state.copyWith(uploading: {...state.uploading, uploadKey});
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storageKey = 'partners/$_partnerId/facility/slot${slot}_$ts.jpg';

      await _sb.storage.from(_bucket).uploadBinary(
        storageKey,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600',
          upsert: false,
        ),
      );

      // Demote prior current photos in this slot
      await _sb
          .from('partner_facility_photos')
          .update({'is_current': false})
          .eq('partner_id', _partnerId!)
          .eq('slot', slot)
          .eq('is_current', true);

      // Insert new version
      await _sb.from('partner_facility_photos').insert({
        'partner_id': _partnerId,
        'slot': slot,
        'label': _photoLabels[slot],
        'file_key': storageKey,
        'uploaded_by': user.id,
        'is_current': true,
      });

      await _loadFacilityPhotos();
      state = state.copyWith(
        uploading: state.uploading.difference({uploadKey}),
        successMessage: '${_photoLabels[slot]} photo uploaded.',
      );
    } catch (e) {
      state = state.copyWith(
        uploading: state.uploading.difference({uploadKey}),
        errorMessage: 'Photo upload failed: $e',
      );
    }
  }

  // ── Public URL helper ─────────────────────────────────────────────────────

  String getPublicUrl(String fileKey) =>
      _sb.storage.from(_bucket).getPublicUrl(fileKey);
}

// ─── Provider ─────────────────────────────────────────────────────────────────

/// Not autoDispose — prevents state reset on tab switch.
final partnerProfileProvider =
    StateNotifierProvider<PartnerProfileController, PartnerProfileState>(
  (ref) => PartnerProfileController(),
);
