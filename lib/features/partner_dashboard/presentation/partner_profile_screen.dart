import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import 'partner_profile_controller.dart';

const _emerald500 = Color(0xFF10B981);
const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);

const _kSidebarWidth = 240.0;

class PartnerProfileScreen extends ConsumerStatefulWidget {
  const PartnerProfileScreen({super.key});
  @override
  ConsumerState<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends ConsumerState<PartnerProfileScreen> {
  bool _isEditing = false;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _paintBrandCtrl;
  late final TextEditingController _throughputCtrl;
  late final TextEditingController _radiusCtrl;

  @override
  void initState() {
    super.initState();
    _addressCtrl = TextEditingController();
    _paintBrandCtrl = TextEditingController();
    _throughputCtrl = TextEditingController();
    _radiusCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _paintBrandCtrl.dispose();
    _throughputCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  void _populateControllers(Map<String, dynamic> data) {
    _addressCtrl.text = data['address']?.toString() ?? '';
    _paintBrandCtrl.text = data['paint_brand']?.toString() ?? '';
    _throughputCtrl.text = data['throughput_capacity']?.toString() ?? '';
    _radiusCtrl.text = data['service_radius_km']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(partnerProfileProvider);
    final controller = ref.read(partnerProfileProvider.notifier);

    // Show success/error snackbars reactively
    ref.listen(partnerProfileProvider, (prev, next) {
      if (next.successMessage != null && next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.successMessage!), backgroundColor: _emerald500),
        );
        setState(() => _isEditing = false);
      }
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        children: [
          _buildSidebar(context, isDark, cs),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, isDark, cs, state, controller),
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.fireRed))
                      : state.partnerData == null
                          ? _buildEmptyOrError(isDark, cs, state.errorMessage)
                          : _buildBody(isDark, cs, state, controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Sidebar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSidebar(BuildContext context, bool isDark, ColorScheme cs) {
    final items = [
      (Icons.dashboard_outlined, 'Dashboard', '/partner-dashboard'),
      (Icons.storefront_outlined, 'My Profile', '/partner-dashboard/profile'),
      (Icons.settings_outlined, 'Settings', '/partner-dashboard/settings'),
      (Icons.calendar_month_outlined, 'Schedule', '/partner-dashboard/schedule'),
      (Icons.timer_outlined, 'Panel Durations', '/partner-dashboard/quota'),
    ];
    final sidebarBg = isDark ? AppColors.surfaceContainerLowest : Colors.white;
    final dividerColor = isDark ? AppColors.outlineVariant : Colors.black12;

    return Container(
      width: _kSidebarWidth,
      color: sidebarBg,
      child: Column(
        children: [
          Container(
            height: 64,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car, color: AppColors.fireRed, size: 22),
                const SizedBox(width: 10),
                Text('Partner Portal',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final isActive = item.$3 == '/partner-dashboard/profile';
            return InkWell(
              onTap: () => context.go(item.$3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                color: isActive ? AppColors.fireRed.withValues(alpha: 0.08) : Colors.transparent,
                child: Row(
                  children: [
                    Icon(item.$1, size: 18,
                        color: isActive ? AppColors.fireRed : cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(item.$2,
                        style: TextStyle(
                          color: isActive ? AppColors.fireRed : cs.onSurface,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 14,
                        )),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // â”€â”€ Top Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildTopBar(BuildContext context, bool isDark, ColorScheme cs,
      PartnerProfileState state, PartnerProfileController controller) {
    final dividerColor = isDark ? AppColors.outlineVariant : Colors.black12;
    final barBg = isDark ? AppColors.surfaceContainerLowest : Colors.white;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      child: Row(
        children: [
          Text('My Workshop Profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const Spacer(),
          // â”€â”€ Theme toggle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                color: cs.onSurfaceVariant),
            tooltip: 'Toggle Theme',
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: 4),
          if (state.partnerData != null) ...[
            // Online / Offline toggle
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: state.partnerData!['is_active'] == true
                        ? _emerald500
                        : cs.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  state.partnerData!['is_active'] == true ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: state.partnerData!['is_active'] == true
                        ? _emerald500 : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500, fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: state.partnerData!['is_active'] == true,
                  activeThumbColor: _emerald500,
                  onChanged: (val) => controller.toggleOnlineStatus(val),
                ),
              ],
            ),
            const SizedBox(width: 16),
            if (_isEditing) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    side: BorderSide(color: dividerColor)),
                onPressed: () => setState(() => _isEditing = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.fireRed,
                    foregroundColor: Colors.white),
                icon: state.isSaving
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 16),
                label: const Text('Save Changes'),
                onPressed: state.isSaving ? null : () {
                  controller.updateProfile(
                    address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
                    paintBrand: _paintBrandCtrl.text.trim().isEmpty ? null : _paintBrandCtrl.text.trim(),
                    throughputCapacity: int.tryParse(_throughputCtrl.text.trim()),
                    serviceRadiusKm: double.tryParse(_radiusCtrl.text.trim()),
                  );
                },
              ),
            ] else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.fireRed,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Profile'),
                onPressed: () {
                  _populateControllers(state.partnerData!);
                  setState(() => _isEditing = true);
                },
              ),
          ],
        ],
      ),
    );
  }

  // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBody(bool isDark, ColorScheme cs, PartnerProfileState state, PartnerProfileController controller) {
    final p = state.partnerData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(isDark, cs, p),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildContactCard(isDark, cs, p)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildKpiCard(isDark, cs, state)),
            ],
          ),
          const SizedBox(height: 20),
          _buildFacilityPhotosCard(isDark, cs, state),
          const SizedBox(height: 20),
          _buildDocumentStatusCard(isDark, cs, p),
        ],
      ),
    );
  }

  Widget _card(bool isDark, ColorScheme cs, Widget child, {EdgeInsets padding = const EdgeInsets.all(20)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.outlineVariant : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _buildHeroCard(bool isDark, ColorScheme cs, Map<String, dynamic> p) {
    final tier = p['tier']?.toString() ?? 'standard';
    final tierColor = switch (tier.toLowerCase()) {
      'premium' => _amber500,
      'elite'   => AppColors.fireRed,
      _         => _blue500,
    };
    final statusPending = p['status']?.toString() == 'pending';
    return _card(isDark, cs, padding: const EdgeInsets.all(24), Row(
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppColors.fireRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.storefront, size: 36, color: AppColors.fireRed),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      p['entity_name']?.toString() ?? p['shop_name']?.toString() ?? 'Workshop Name',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: tierColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(tier.toUpperCase(),
                        style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  if (statusPending) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _amber500.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _amber500.withValues(alpha: 0.4)),
                      ),
                      child: const Text('PENDING REVIEW',
                          style: TextStyle(color: _amber500, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p['address']?.toString() ?? 'No address on file',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              if (p['submitted_at'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Member since ${DateFormat.yMMMd().format(DateTime.parse(p['submitted_at'].toString()))}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    ));
  }

  Widget _buildContactCard(bool isDark, ColorScheme cs, Map<String, dynamic> p) {
    return _card(isDark, cs, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contact & Operations',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 16),
        Divider(color: isDark ? AppColors.outlineVariant : Colors.black12),
        const SizedBox(height: 12),
        if (_isEditing) ...[
          _editField(isDark, cs, 'Address', _addressCtrl, Icons.location_on_outlined),
          const SizedBox(height: 12),
          _editField(isDark, cs, 'Paint Brand Partner', _paintBrandCtrl, Icons.palette_outlined),
          const SizedBox(height: 12),
          _editField(isDark, cs, 'Daily Throughput Capacity', _throughputCtrl, Icons.speed_outlined, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _editField(isDark, cs, 'Service Radius (km)', _radiusCtrl, Icons.radar_outlined, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ] else ...[
          _infoRow(cs, Icons.location_on_outlined, 'Address', p['address']?.toString() ?? 'â€”'),
          _infoRow(cs, Icons.palette_outlined, 'Paint Brand', p['paint_brand']?.toString() ?? 'â€”'),
          _infoRow(cs, Icons.speed_outlined, 'Daily Capacity', '${p['throughput_capacity'] ?? 'â€”'} panels/day'),
          _infoRow(cs, Icons.radar_outlined, 'Service Radius', '${p['service_radius_km'] ?? 'â€”'} km'),
        ],
      ],
    ));
  }

  Widget _editField(bool isDark, ColorScheme cs, String label, TextEditingController ctrl, IconData icon,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 14, color: cs.onSurface),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: isDark ? AppColors.surfaceContainerLowest : Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: isDark ? AppColors.outlineVariant : Colors.black12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: isDark ? AppColors.outlineVariant : Colors.black12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.fireRed, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _infoRow(ColorScheme cs, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(width: 140,
              child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildKpiCard(bool isDark, ColorScheme cs, PartnerProfileState state) {
    return _card(isDark, cs, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Performance KPIs',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 16),
        Divider(color: isDark ? AppColors.outlineVariant : Colors.black12),
        const SizedBox(height: 12),
        _kpiTile(cs, 'Total Jobs Completed', '${state.totalJobsDone}', Icons.check_circle_outline, _emerald500),
        const SizedBox(height: 12),
        _kpiTile(cs, 'Avg. Repair Duration', '${state.avgRepairDays.toStringAsFixed(1)} days', Icons.schedule_outlined, _blue500),
        const SizedBox(height: 12),
        _kpiTile(cs, 'Daily Capacity', '${state.partnerData?['throughput_capacity'] ?? 'â€”'} panels', Icons.speed_outlined, _amber500),
      ],
    ));
  }

  Widget _kpiTile(ColorScheme cs, String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFacilityPhotosCard(bool isDark, ColorScheme cs, PartnerProfileState state) {
    return _card(isDark, cs, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Facility Photos',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 14),
        state.facilityPhotoUrls.isEmpty
            ? Container(
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceContainerLowest : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? AppColors.outlineVariant : Colors.black12),
                ),
                child: Text('No facility photos uploaded yet.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              )
            : SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.facilityPhotoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        state.facilityPhotoUrls[i],
                        width: 160, height: 120, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 160, height: 120,
                          color: isDark ? AppColors.surfaceContainerLowest : Colors.grey.shade100,
                          child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ],
    ));
  }

  Widget _buildDocumentStatusCard(bool isDark, ColorScheme cs, Map<String, dynamic> p) {
    final docs = [
      ('NIB', 'nib_file_key', Icons.article_outlined),
      ('NPWP', 'npwp_file_key', Icons.receipt_long_outlined),
      ('SIUP', 'siup_file_key', Icons.business_center_outlined),
      ('KTP', 'ktp_file_key', Icons.badge_outlined),
    ];
    return _card(isDark, cs, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Document Status',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 14),
        ...docs.map((doc) {
          final hasDoc = p[doc.$2] != null && p[doc.$2].toString().isNotEmpty;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(doc.$3, size: 18, color: hasDoc ? _emerald500 : cs.onSurfaceVariant),
                const SizedBox(width: 12),
                SizedBox(width: 60,
                    child: Text(doc.$1,
                        style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500))),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasDoc ? _emerald500.withValues(alpha: 0.1) : _amber500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasDoc ? 'Uploaded' : 'Pending Upload',
                    style: TextStyle(
                        color: hasDoc ? _emerald500 : _amber500,
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ));
  }

  Widget _buildEmptyOrError(bool isDark, ColorScheme cs, String? msg) {
    final isError = msg != null && msg.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.storefront_outlined,
            size: 56,
            color: isError ? AppColors.fireRed : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            isError ? 'Failed to load profile' : 'No Workshop Profile Yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            isError
                ? msg
                : 'Your workshop profile hasn\'t been created yet.\nContact support to get started.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
