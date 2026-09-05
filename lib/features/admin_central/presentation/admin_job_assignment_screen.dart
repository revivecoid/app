import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class AdminJobAssignmentScreen extends ConsumerStatefulWidget {
  const AdminJobAssignmentScreen({super.key});

  @override
  ConsumerState<AdminJobAssignmentScreen> createState() => _AdminJobAssignmentScreenState();
}

class _AdminJobAssignmentScreenState extends ConsumerState<AdminJobAssignmentScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _unassignedJobs = [];
  List<Map<String, dynamic>> _partners = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final jobsRes = await _supabase.from('repair_jobs')
          .select('id, initial_estimation_cost, status, service_area, created_at, vehicles(make, model, license_plate), profiles(full_name)')
          .filter('partner_id', 'is', null)
          .eq('status', '2_estimated')
          .order('created_at', ascending: true);

      final partnersRes = await _supabase.from('partners')
          .select('id, shop_name, service_area')
          .eq('is_active', true);

      if (mounted) {
        setState(() {
          _unassignedJobs = List<Map<String, dynamic>>.from(jobsRes);
          _partners = List<Map<String, dynamic>>.from(partnersRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _assignJob(String jobId, String partnerId) async {
    try {
      await _supabase.from('repair_jobs').update({
        'partner_id': partnerId,
        'status': '3_booked'
      }).eq('id', jobId);
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job Assigned Successfully!'), backgroundColor: Colors.green));
      _fetchData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error assigning job'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final bgColor = isDark ? AppColors.background : Colors.grey[50];
    final surfaceColor = isDark ? AppColors.surface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: const ReVAppBar(title: Text('Repair Assignment Module'), showBackButton: true),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.fireRed))
        : _error != null 
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unassigned Jobs', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 16),
                  if (_unassignedJobs.isEmpty)
                    Text('No unassigned jobs currently pending.', style: TextStyle(color: textColor, fontSize: 16)),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _unassignedJobs.length,
                      itemBuilder: (ctx, idx) {
                        final job = _unassignedJobs[idx];
                        final v = job['vehicles'] as Map<String, dynamic>? ?? {};
                        final p = job['profiles'] as Map<String, dynamic>? ?? {};
                        final jobArea = job['service_area']?.toString() ?? 'Unknown Area';
                        final vehicleLabel = '${v['make'] ?? ''} ${v['model'] ?? ''} · ${v['license_plate'] ?? '—'}'.trim();
                        final customerLabel = p['full_name']?.toString() ?? 'Unknown Customer';

                        // Smart filter partners based on job's location
                        final recommendedPartners = _partners.where((pt) => pt['service_area'] == jobArea).toList();
                        final otherPartners = _partners.where((pt) => pt['service_area'] != jobArea).toList();

                        return Card(
                          color: surfaceColor,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(vehicleLabel.isEmpty ? 'Unknown Vehicle' : vehicleLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                                      Text(customerLabel, style: TextStyle(color: textColor, fontSize: 13)),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: AppColors.daysGray.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                        child: Text(jobArea, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 12)),
                                      )
                                    ],
                                  )
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Assign to Partner:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                                      const SizedBox(height: 8),
                                      DropdownButtonFormField<String>(
                                        decoration: const InputDecoration(labelText: 'Select Workshop'),
                                        items: [
                                          if (recommendedPartners.isNotEmpty)
                                            const DropdownMenuItem(enabled: false, child: Text('--- Recommended (Matching Area) ---')),
                                          ...recommendedPartners.map((pt) => DropdownMenuItem(value: pt['id'], child: Text(pt['shop_name'] ?? ''))),
                                          if (otherPartners.isNotEmpty)
                                            const DropdownMenuItem(enabled: false, child: Text('--- Other Workshops ---')),
                                          ...otherPartners.map((pt) => DropdownMenuItem(value: pt['id'], child: Text(pt['shop_name'] ?? ''))),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            _assignJob(job['id'], val);
                                          }
                                        },
                                      )
                                    ],
                                  )
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            )
    );
  }
}
