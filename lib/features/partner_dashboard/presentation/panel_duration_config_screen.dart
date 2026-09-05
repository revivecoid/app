import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';

// Assuming we want a fixed set of the 23 standard panels for the grid
const List<String> _standardPanels = [
  'Bumper Depan', 'Bumper Belakang', 'Kap Mesin', 'Atap',
  'Pintu Kiri Depan', 'Pintu Kiri Belakang', 'Pintu Kanan Depan', 'Pintu Kanan Belakang',
  'Fender Kiri Depan', 'Fender Kanan Depan', 'Fender Kiri Belakang', 'Fender Kanan Belakang',
  'Bagasi', 'Spoiler Bumper Depan', 'Spoiler Bumper Belakang',
  'Kaca Depan', 'Kaca Belakang', 'Kaca Pintu Kiri', 'Kaca Pintu Kanan',
  'Spion Kiri', 'Spion Kanan', 'Lampu Depan', 'Lampu Belakang'
];

class PanelDurationConfigScreen extends ConsumerStatefulWidget {
  const PanelDurationConfigScreen({super.key});

  @override
  ConsumerState<PanelDurationConfigScreen> createState() => _PanelDurationConfigScreenState();
}

class _PanelDurationConfigScreenState extends ConsumerState<PanelDurationConfigScreen> {
  bool _isLoading = true;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final panel in _standardPanels) {
      // Default to 2.0 hours
      _controllers[panel] = TextEditingController(text: '2.0');
    }
    _loadDurations();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDurations() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('partner_panel_durations')
          .select()
          .eq('partner_id', user.id);

      if (mounted) {
        setState(() {
          for (final row in response) {
            final panelName = row['panel_name'] as String;
            final duration = row['repair_duration_hours'] as num;
            if (_controllers.containsKey(panelName)) {
              _controllers[panelName]!.text = duration.toString();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading durations: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDurations() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final List<Map<String, dynamic>> payload = [];
      for (final panel in _standardPanels) {
        final text = _controllers[panel]!.text;
        final duration = double.tryParse(text) ?? 2.0;
        
        payload.add({
          'partner_id': user.id,
          'panel_name': panel,
          'repair_duration_hours': duration,
          
        });
      }

      await Supabase.instance.client
          .from('partner_panel_durations')
          .upsert(payload, onConflict: 'partner_id, panel_name');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Durations matrix saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving durations: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Panel Repair Duration Matrix',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure the standard labor hours required for each specific panel repair. This drives the availability estimator.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisExtent: 80,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _standardPanels.length,
            itemBuilder: (context, index) {
              final panel = _standardPanels[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(panel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    ),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _controllers[panel],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}')),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          suffixText: 'hrs',
                          suffixStyle: TextStyle(color: Colors.white54),
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.fireRed)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saveDurations,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.fireRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Duration Matrix', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
