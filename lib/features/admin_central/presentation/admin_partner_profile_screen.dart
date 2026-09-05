import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';
import 'admin_dashboard_controller.dart';
import 'admin_partner_profile_controller.dart';

class AdminPartnerProfileScreen extends ConsumerStatefulWidget {
  final String partnerId;
  const AdminPartnerProfileScreen({super.key, required this.partnerId});

  @override
  ConsumerState<AdminPartnerProfileScreen> createState() => _AdminPartnerProfileScreenState();
}

class _AdminPartnerProfileScreenState extends ConsumerState<AdminPartnerProfileScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void dispose() {
    _msgController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomOfChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminPartnerProfileProvider(widget.partnerId));
    final controller = ref.read(adminPartnerProfileProvider(widget.partnerId).notifier);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.sleekBlack;
    final surfaceColor = isDark ? AppColors.surface : Colors.white;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    ref.listen(adminPartnerProfileProvider(widget.partnerId), (prev, next) {
      if (next.successMessage != null && next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.successMessage!), backgroundColor: Colors.green),
        );
      }
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: Colors.red),
        );
      }
      // Auto-scroll chat on new messages
      if (next.messages.length != (prev?.messages.length ?? 0)) {
        _scrollToBottomOfChat();
      }
    });

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: ReVAppBar(
          title: Text('Partner Profile', style: TextStyle(color: textColor)),
          showBackButton: true,
        ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.fireRed)),
      );
    }

    if (state.partnerData == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: ReVAppBar(
          title: Text('Partner Profile', style: TextStyle(color: textColor)),
          showBackButton: true,
        ),
        body: Center(child: Text('Partner not found or deleted.', style: TextStyle(color: textColor))),
      );
    }

    final p = state.partnerData!;
    final isActive = p['is_active'] == true;
    final shopName = p['shop_name']?.toString() ?? p['entity_name']?.toString() ?? 'Unknown Shop';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: ReVAppBar(
        showBackButton: true,
        title: Text(shopName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        actions: [
          // Suspend / Reactivate
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: isActive
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.pause_circle_outline, size: 16),
                    label: const Text('Suspend'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
                    onPressed: () => _confirmSuspend(context, controller, shopName, isActive),
                  )
                : ElevatedButton.icon(
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Reactivate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => controller.reactivatePartner(),
                  ),
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: 'Delete Partner Account',
            onPressed: () => _confirmDelete(context, ref, shopName),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: Detail Columns ─────────────────────────────────────────
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroCard(p, isActive, shopName, surfaceColor, textColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Company Data', textColor),
                  _buildCompanyCard(p, surfaceColor, textColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Document Status', textColor),
                  _buildDocumentCard(p, surfaceColor, textColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Scheduling & Quota', textColor),
                  _buildScheduleCard(state, surfaceColor, textColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Performance KPIs', textColor),
                  _buildKpiCard(state, surfaceColor, textColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Facility Photos', textColor),
                  _buildPhotosCard(state, surfaceColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Ongoing Jobs (${state.activeJobs.length})', textColor),
                  ...state.activeJobs.map((j) => _buildJobCard(j, surfaceColor, textColor)),
                  if (state.activeJobs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('No active jobs.', style: TextStyle(color: textColor.withValues(alpha: 0.5))),
                    ),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Job History (${state.pastJobs.length})', textColor),
                  ...state.pastJobs.map((j) => _buildJobCard(j, surfaceColor, textColor)),
                  if (state.pastJobs.isEmpty)
                    Text('No completed jobs yet.', style: TextStyle(color: textColor.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ),

          // ── Divider ──────────────────────────────────────────────────────
          Container(width: 1, color: Colors.grey.withValues(alpha: 0.2)),

          // ── Right: Chat ──────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Container(
              color: surfaceColor,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: isDark ? Colors.black12 : Colors.grey[100],
                    width: double.infinity,
                    child: Text('Internal Messaging',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: state.messages.length,
                      itemBuilder: (context, i) {
                        final m = state.messages[i];
                        return Align(
                          alignment: m.isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: m.isAdmin
                                  ? AppColors.fireRed
                                  : (isDark ? Colors.grey[800] : Colors.grey[200]),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(12),
                                topRight: const Radius.circular(12),
                                bottomLeft: Radius.circular(m.isAdmin ? 12 : 0),
                                bottomRight: Radius.circular(m.isAdmin ? 0 : 12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: m.isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(m.content, style: TextStyle(color: m.isAdmin ? Colors.white : textColor, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('HH:mm').format(m.createdAt),
                                  style: TextStyle(fontSize: 10, color: m.isAdmin ? Colors.white60 : Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              filled: true,
                              fillColor: isDark ? Colors.black26 : Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onSubmitted: (val) {
                              if (val.trim().isNotEmpty) {
                                controller.sendMessage(val);
                                _msgController.clear();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: AppColors.fireRed,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white, size: 20),
                            onPressed: () {
                              if (_msgController.text.trim().isNotEmpty) {
                                controller.sendMessage(_msgController.text);
                                _msgController.clear();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Builders ────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> p, bool isActive, String shopName, Color surfaceColor, Color textColor) {
    final tier = p['tier']?.toString() ?? 'standard';
    return Card(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: AppColors.fireRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storefront, size: 30, color: AppColors.fireRed),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shopName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _chip(tier.toUpperCase(), isActive ? Colors.blue : Colors.grey),
                      const SizedBox(width: 8),
                      _chip(isActive ? 'ACTIVE' : 'SUSPENDED', isActive ? Colors.green : Colors.orange),
                      if (p['submitted_at'] != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Joined ${DateFormat.yMMMd().format(DateTime.parse(p['submitted_at'].toString()))}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCompanyCard(Map<String, dynamic> p, Color surfaceColor, Color textColor) {
    return Card(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Email', p['email']?.toString() ?? p['contact_email']?.toString() ?? 'N/A', textColor),
            _detailRow('Phone', p['phone']?.toString() ?? p['contact_phone']?.toString() ?? 'N/A', textColor),
            _detailRow('Address', p['address']?.toString() ?? 'N/A', textColor),
            _detailRow('Paint Brand', p['paint_brand']?.toString() ?? 'N/A', textColor),
            _detailRow('Daily Capacity', '${p['throughput_capacity'] ?? 'N/A'} panels/day', textColor),
            _detailRow('Service Radius', '${p['service_radius_km'] ?? 'N/A'} km', textColor),
            _detailRow('Status', p['is_active'] == true ? 'Active' : 'Suspended',
                p['is_active'] == true ? Colors.green : Colors.orange),
            if (p['created_at'] != null)
              _detailRow('Joined', DateFormat.yMMMd().format(DateTime.parse(p['created_at'].toString())), textColor),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> p, Color surfaceColor, Color textColor) {
    final docs = [
      ('NIB', 'nib_file_key'),
      ('NPWP', 'npwp_file_key'),
      ('SIUP', 'siup_file_key'),
      ('KTP Owner', 'ktp_file_key'),
    ];
    return Card(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: docs.map((doc) {
            final hasDoc = p[doc.$2] != null && p[doc.$2].toString().isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 18, color: hasDoc ? Colors.green : Colors.orange),
                  const SizedBox(width: 10),
                  SizedBox(width: 80, child: Text(doc.$1, style: TextStyle(color: textColor, fontWeight: FontWeight.w500))),
                  const SizedBox(width: 8),
                  _chip(hasDoc ? 'UPLOADED' : 'PENDING', hasDoc ? Colors.green : Colors.orange),
                  const Spacer(),
                  if (hasDoc)
                    TextButton(
                      onPressed: () {},
                      child: const Text('View', style: TextStyle(color: AppColors.fireRed)),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(AdminPartnerProfileState state, Color surfaceColor, Color textColor) {
    return Card(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: state.scheduleData == null
            ? const Text('No schedule configured yet.',
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Guaranteed Slots/Day',
                      state.scheduleData!['guaranteed_slots_per_day']?.toString() ?? 'N/A', textColor),
                  _detailRow('Simultaneous Capacity',
                      state.scheduleData!['simultaneous_panel_capacity']?.toString() ?? 'N/A', textColor),
                  _detailRow('Working Days',
                      _parseWorkingDays(state.scheduleData!['standard_working_days']), textColor),
                  _detailRow('Blacklisted Dates',
                      '${(state.scheduleData!['blacklisted_dates'] as List?)?.length ?? 0} date(s) blocked', textColor),
                ],
              ),
      ),
    );
  }

  Widget _buildKpiCard(AdminPartnerProfileState state, Color surfaceColor, Color textColor) {
    return Card(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _kpiTile('Total Jobs Done', '${state.totalJobsDone}', Icons.check_circle_outline, Colors.green, textColor),
            ),
            Expanded(
              child: _kpiTile('Avg. Repair Days',
                  '${state.avgRepairDays.toStringAsFixed(1)} days', Icons.schedule_outlined, Colors.blue, textColor),
            ),
            Expanded(
              child: _kpiTile('Active Jobs Now',
                  '${state.activeJobs.length}', Icons.build_outlined, AppColors.fireRed, textColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiTile(String label, String value, IconData icon, Color color, Color textColor) {
    return Column(
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildPhotosCard(AdminPartnerProfileState state, Color surfaceColor) {
    return Card(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: state.facilityPhotoUrls.isEmpty
            ? const Text('No facility photos uploaded.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
            : SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.facilityPhotoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      state.facilityPhotoUrls[i],
                      width: 150, height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 150, height: 110,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job, Color surfaceColor, Color textColor) {
    final vehicle = job['vehicles'] as Map<String, dynamic>? ?? {};
    final profile = job['profiles'] as Map<String, dynamic>? ?? {};
    final status = job['status']?.toString() ?? '';
    final statusLabel = status.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').toUpperCase();
    final statusColor = _statusColor(status);
    return Card(
      color: surfaceColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(
          '${vehicle['make'] ?? 'Unknown'} ${vehicle['model'] ?? ''}'.trim(),
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text('${profile['full_name'] ?? 'N/A'} • ${vehicle['license_plate'] ?? '—'}',
            style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text(DateFormat.MMMd().format(DateTime.parse(job['created_at'].toString())),
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: valueColor, fontSize: 13))),
        ],
      ),
    );
  }

  Color _statusColor(String s) {
    if (s.contains('in_progress') || s.contains('admitted')) return AppColors.fireRed;
    if (s.contains('finished')) return Colors.orange;
    if (s.contains('awaiting')) return Colors.green;
    if (s.contains('paid') || s.contains('booked')) return Colors.blue;
    if (s.contains('done')) return Colors.grey;
    return Colors.grey;
  }

  String _parseWorkingDays(dynamic days) {
    if (days == null) return 'N/A';
    if (days is! List) return days.toString();
    const map = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    return days.map((d) => map[d] ?? d.toString()).join(', ');
  }

  Future<void> _confirmSuspend(BuildContext context, AdminPartnerProfileController controller, String shopName, bool isActive) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend Partner?'),
        content: Text('Suspend "$shopName"? Their dashboard will become inaccessible until reactivated.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SUSPEND'),
          ),
        ],
      ),
    );
    if (confirm == true) controller.suspendPartner();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, String shopName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Partner?'),
        content: Text('Permanently delete "$shopName"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await Supabase.instance.client.from('partners').delete().eq('id', widget.partnerId);
        ref.read(adminDashboardProvider.notifier).removePartnerLocal(widget.partnerId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Partner deleted successfully')));
          context.go('/admin-central');
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}
