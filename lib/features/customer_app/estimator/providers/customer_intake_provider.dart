import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerIntakeState {
  final String name;
  final String phone;
  final String brand;
  final String model;
  final String year;
  final String licensePlate;
  final double estimatedCost;
  final String location;

  CustomerIntakeState({
    this.name = '',
    this.phone = '',
    this.brand = '',
    this.model = '',
    this.year = '',
    this.licensePlate = '',
    this.estimatedCost = 0.0,
    this.location = '',
  });

  CustomerIntakeState copyWith({
    String? name,
    String? phone,
    String? brand,
    String? model,
    String? year,
    String? licensePlate,
    double? estimatedCost,
    String? location,
  }) {
    return CustomerIntakeState(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      licensePlate: licensePlate ?? this.licensePlate,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      location: location ?? this.location,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'brand': brand,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'estimatedCost': estimatedCost,
      'location': location,
    };
  }

  factory CustomerIntakeState.fromJson(Map<String, dynamic> json) {
    return CustomerIntakeState(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      year: json['year'] ?? '',
      licensePlate: json['licensePlate'] ?? '',
      estimatedCost: (json['estimatedCost'] as num?)?.toDouble() ?? 0.0,
      location: json['location'] ?? '',
    );
  }
}

class CustomerIntakeNotifier extends StateNotifier<CustomerIntakeState> {
  CustomerIntakeNotifier() : super(CustomerIntakeState()) {
    _loadState();
    // PRIV-03 fix: clear intake on logout
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) clearIntake();
    });
  }

  Timer? _debounce; // PERF-06 fix: debounce saves

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // C-37/PRIV-03 fix: key by user_id so different users don't share intake
      final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
      final data = prefs.getString('customer_intake_$userId');
      if (data != null) {
        state = CustomerIntakeState.fromJson(jsonDecode(data));
      }
    } catch (e) { debugPrint('[IntakeProvider] load error: $e'); }
  }

  void _saveState(CustomerIntakeState newState) {
    _debounce?.cancel();
    // PERF-06 fix: debounce 400ms — avoid write per keystroke
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
        // PRIV-03 fix: only persist non-sensitive fields (not estimatedCost)
        final toSave = {
          'name': newState.name,
          'brand': newState.brand,
          'model': newState.model,
          'year': newState.year,
          'licensePlate': newState.licensePlate,
          'location': newState.location,
          // phone deliberately excluded — PII, loaded from profile on login
        };
        await prefs.setString('customer_intake_$userId', jsonEncode(toSave));
      } catch (e) { debugPrint('[IntakeProvider] save error: $e'); }
    });
  }

  void _updateAndSave(CustomerIntakeState newState) {
    state = newState;
    _saveState(newState);
  }

  /// PRIV-03/C-37 fix: clear on logout
  Future<void> clearIntake() async {
    _debounce?.cancel();
    state = CustomerIntakeState();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('customer_intake_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void updateName(String name) => _updateAndSave(state.copyWith(name: name));
  void updatePhone(String phone) => _updateAndSave(state.copyWith(phone: phone));
  void updateBrand(String brand) => _updateAndSave(state.copyWith(brand: brand));
  void updateModel(String model) => _updateAndSave(state.copyWith(model: model));
  void updateYear(String year) => _updateAndSave(state.copyWith(year: year));
  void updateLicensePlate(String plate) => _updateAndSave(state.copyWith(licensePlate: plate));
  void updateEstimatedCost(double cost) => _updateAndSave(state.copyWith(estimatedCost: cost));
  void updateLocation(String location) => _updateAndSave(state.copyWith(location: location));
}

final customerIntakeProvider = StateNotifierProvider<CustomerIntakeNotifier, CustomerIntakeState>((ref) {
  return CustomerIntakeNotifier();
});
