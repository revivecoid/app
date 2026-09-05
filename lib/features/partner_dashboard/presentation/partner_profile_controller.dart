import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartnerProfileState {
  final bool isLoading;
  final bool isSaving;
  final Map<String, dynamic>? partnerData;
  final int totalJobsDone;
  final double avgRepairDays;
  final List<String> facilityPhotoUrls;
  final String? errorMessage;
  final String? successMessage;

  PartnerProfileState({
    this.isLoading = true,
    this.isSaving = false,
    this.partnerData,
    this.totalJobsDone = 0,
    this.avgRepairDays = 0.0,
    this.facilityPhotoUrls = const [],
    this.errorMessage,
    this.successMessage,
  });

  PartnerProfileState copyWith({
    bool? isLoading,
    bool? isSaving,
    Map<String, dynamic>? partnerData,
    int? totalJobsDone,
    double? avgRepairDays,
    List<String>? facilityPhotoUrls,
    String? errorMessage,
    String? successMessage,
  }) {
    return PartnerProfileState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      partnerData: partnerData ?? this.partnerData,
      totalJobsDone: totalJobsDone ?? this.totalJobsDone,
      avgRepairDays: avgRepairDays ?? this.avgRepairDays,
      facilityPhotoUrls: facilityPhotoUrls ?? this.facilityPhotoUrls,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class PartnerProfileController extends StateNotifier<PartnerProfileState> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final String _partnerId;

  PartnerProfileController() : super(PartnerProfileState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      _partnerId = user.id; // partner row is keyed by auth UID
      await Future.wait([_fetchProfile(), _fetchKpis(), _fetchFacilityPhotos()]);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> _fetchProfile() async {
    // Use maybeSingle() so we get null instead of PGRST116 if no row exists yet
    final data = await _supabase.from('partners').select().eq('id', _partnerId).maybeSingle();
    state = state.copyWith(isLoading: false, partnerData: data);
  }

  Future<void> _fetchKpis() async {
    try {
      final jobs = await _supabase
          .from('repair_jobs')
          .select('created_at, updated_at')
          .eq('partner_id', _partnerId)
          .eq('status', '9_done');
      final list = jobs as List;
      int total = list.length;
      double avgDays = 0;
      if (total > 0) {
        double sum = 0;
        for (final j in list) {
          final created = DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now();
          final updated = DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? DateTime.now();
          sum += updated.difference(created).inHours / 24.0;
        }
        avgDays = sum / total;
      }
      state = state.copyWith(totalJobsDone: total, avgRepairDays: avgDays);
    } catch (_) {}
  }

  Future<void> _fetchFacilityPhotos() async {
    try {
      final objects = await _supabase.storage
          .from('revive-photos-r2-proxy')
          .list(path: 'facility/$_partnerId/');
      final urls = objects
          .where((o) => o.name.isNotEmpty)
          .map((o) => _supabase.storage
              .from('revive-photos-r2-proxy')
              .getPublicUrl('facility/$_partnerId/${o.name}'))
          .toList();
      state = state.copyWith(facilityPhotoUrls: urls);
    } catch (_) {
      // No photos yet — silently ignore
    }
  }

  Future<void> updateProfile({
    String? address,
    String? paintBrand,
    int? throughputCapacity,
    double? serviceRadiusKm,
  }) async {
    if (state.partnerData == null) return;
    state = state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    try {
      final updates = <String, dynamic>{};
      if (address != null) updates['address'] = address;
      if (paintBrand != null) updates['paint_brand'] = paintBrand;
      if (throughputCapacity != null) updates['throughput_capacity'] = throughputCapacity;
      if (serviceRadiusKm != null) updates['service_radius_km'] = serviceRadiusKm;
      if (updates.isEmpty) {
        state = state.copyWith(isSaving: false);
        return;
      }
      await _supabase.from('partners').update(updates).eq('id', _partnerId);
      final updated = Map<String, dynamic>.from(state.partnerData!);
      updated.addAll(updates);
      state = state.copyWith(isSaving: false, partnerData: updated, successMessage: 'Profile updated successfully.');
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'Failed to save: $e');
    }
  }

  Future<void> toggleOnlineStatus(bool isActive) async {
    try {
      await _supabase.from('partners').update({'is_active': isActive}).eq('id', _partnerId);
      final updated = Map<String, dynamic>.from(state.partnerData ?? {});
      updated['is_active'] = isActive;
      state = state.copyWith(partnerData: updated);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update status: $e');
    }
  }
}

final partnerProfileProvider =
    StateNotifierProvider.autoDispose<PartnerProfileController, PartnerProfileState>(
  (ref) => PartnerProfileController(),
);
