import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import 'customer_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Vehicle Registration Modal
//  Shows as a bottom sheet; inserts a row into the `vehicles` table.
//  After success, invalidates the customerVehiclesProvider so the garage
//  updates immediately without a page refresh.
// ─────────────────────────────────────────────────────────────────────────────

class VehicleRegistrationModal extends ConsumerStatefulWidget {
  const VehicleRegistrationModal({super.key});

  @override
  ConsumerState<VehicleRegistrationModal> createState() =>
      _VehicleRegistrationModalState();
}

class _VehicleRegistrationModalState
    extends ConsumerState<VehicleRegistrationModal> {
  final _formKey = GlobalKey<FormState>();

  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();

  String _vehicleType = 'Car';
  bool _isInsured = false;
  final _insurerCtrl = TextEditingController();
  bool _isLoading = false;

  static const _types = [
    'Car', 'SUV', 'MPV', 'Pickup', 'Van', 'Motorcycle', 'Truck',
  ];

  @override
  void dispose() {
    for (final c in [
      _makeCtrl, _modelCtrl, _yearCtrl, _plateCtrl, _colorCtrl, _vinCtrl,
      _insurerCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      await Supabase.instance.client.from('vehicles').insert({
        'customer_id': user.id,
        'make': _makeCtrl.text.trim(),
        'model': _modelCtrl.text.trim(),
        'year': int.tryParse(_yearCtrl.text.trim()) ?? 2020,
        'license_plate': _plateCtrl.text.trim().toUpperCase(),
        'color': _colorCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        if (_vinCtrl.text.trim().isNotEmpty) 'vin': _vinCtrl.text.trim(),
        if (_isInsured && _insurerCtrl.text.trim().isNotEmpty)
          'insurance_provider': _insurerCtrl.text.trim(),
        'is_insured': _isInsured,
      });

      // Refresh garage list immediately
      ref.invalidate(customerVehiclesProvider);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                  '${_makeCtrl.text} ${_modelCtrl.text} registered to your garage!'),
            ]),
            backgroundColor: AppColors.primaryContainer,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: ${e.toString()}'),
            backgroundColor: AppColors.fireRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDec(String label, {String? hint, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      // shift content up when keyboard appears
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.directions_car,
                                color: AppColors.primaryContainer, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Register New Vehicle',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.sleekBlack)),
                              Text('Add a vehicle to your digital garage',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.daysGray)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Vehicle Type
                      const Text('Vehicle Type',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.daysGray)),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _types.map((t) {
                            final selected = _vehicleType == t;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _vehicleType = t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primaryContainer
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primaryContainer
                                          : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Text(t,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.daysGray)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Make & Model
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _makeCtrl,
                              decoration: _inputDec('Make *',
                                  hint: 'Toyota', icon: Icons.business),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _modelCtrl,
                              decoration: _inputDec('Model *',
                                  hint: 'Innova Zenix'),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Year & Plate
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _yearCtrl,
                              decoration: _inputDec('Year *',
                                  hint: '2024',
                                  icon: Icons.calendar_today),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validator: (v) {
                                if (v!.trim().isEmpty) return 'Required';
                                final y = int.tryParse(v.trim());
                                if (y == null || y < 1970 || y > 2030) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _plateCtrl,
                              decoration: _inputDec('License Plate *',
                                  hint: 'B 1234 ABC',
                                  icon: Icons.credit_card),
                              textCapitalization: TextCapitalization.characters,
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Color
                      TextFormField(
                        controller: _colorCtrl,
                        decoration: _inputDec('Color',
                            hint: 'e.g. Midnight Black Metallic',
                            icon: Icons.palette),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),

                      // VIN (optional)
                      TextFormField(
                        controller: _vinCtrl,
                        decoration: _inputDec('VIN (optional)',
                            hint: 'Vehicle Identification Number',
                            icon: Icons.numbers),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9]')),
                          LengthLimitingTextInputFormatter(17),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Insurance toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.shield,
                                color: AppColors.primaryContainer, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Vehicle is Insured',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.sleekBlack)),
                                  Text(
                                      'Enable to link an insurance provider',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.daysGray)),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isInsured,
                              onChanged: (v) =>
                                  setState(() => _isInsured = v),
                              activeThumbColor: Colors.white,
                              activeTrackColor: AppColors.primaryContainer,
                            ),
                          ],
                        ),
                      ),
                      if (_isInsured) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _insurerCtrl,
                          decoration: _inputDec('Insurance Provider',
                              hint: 'e.g. Garda Oto Comprehensive',
                              icon: Icons.verified_user),
                          textCapitalization: TextCapitalization.words,
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _submit,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.check, size: 18),
                          label: Text(
                            _isLoading
                                ? 'Registering...'
                                : 'Register Vehicle to Garage',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryContainer,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper: show the modal from any context
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showVehicleRegistrationModal(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const VehicleRegistrationModal(),
  );
}
