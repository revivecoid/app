import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('customer_intake');
      if (data != null) {
        state = CustomerIntakeState.fromJson(jsonDecode(data));
      }
    } catch (_) {}
  }

  void _saveState(CustomerIntakeState newState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('customer_intake', jsonEncode(newState.toJson()));
    } catch (_) {}
  }

  void _updateAndSave(CustomerIntakeState newState) {
    state = newState;
    _saveState(newState);
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
