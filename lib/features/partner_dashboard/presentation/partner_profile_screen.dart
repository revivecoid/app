import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import 'partner_profile_controller.dart';

// ─── Design tokens (match partner_dashboard_desktop) ────────────────────────
const _surface = Color(0xFFfdf8f9);
const _surfaceLowest = Color(0xFFffffff);
const _surfaceLow = Color(0xFFf7f2f3);
const _surfaceHigh = Color(0xFFebe7e8);
const _primary = Color(0xFFa40016);
const _primaryContainer = Color(0xFFd10721);
const _onPrimary = Color(0xFFffffff);
const _onSurface = Color(0xFF1c1b1c);
const _onSurfaceVariant = Color(0xFF5d3f3d);
const _emerald500 = Color(0xFF10B981);
const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);
const _errorRed = Color(0xFF93000a);

const _kSidebarWidth = 260.0;

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
          SnackBar(content: Text(next.errorMessage!), backgroundColor: _errorRed),
        );
      }
    });

    return Scaffold(
      backgroundColor: _surface,
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, state, controller),
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator(color: _primaryContainer))
                      : state.partnerData == null
                          ? _buildError(state.errorMessage)
                          : _buildBody(state, controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sidebar ──────────────────────────────────────────────────────────────
  Widget _buildSidebar(BuildContext context) {
    final items = [
      (Icons.dashboard_outlined, 'Dashboard', '/partner-dashboard'),
      (Icons.storefront_outlined, 'My Profile', '/partner-dashboard/profile'),
      (Icons.settings_outlined, 'Settings', '/partner-dashboard/settings'),
      (Icons.calendar_month_outlined, 'Schedule', '/partner-dashboard/schedule'),
      (Icons.timer_outlined, 'Panel Durations', '/partner-dashboard/quota'),
    ];
    return Container(
      width: _kSidebarWidth,
      color: _surfaceLowest,
      child: Column(
        children: [
          Container(
            height: 64,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _surfaceHigh)),
            ),
            child: const Row(
              children: [
                Icon(Icons.directions_car, color: _primaryContainer, size: 22),
                SizedBox(width: 10),
                Text('Partner Portal', style: TextStyle(color: _onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final isActive = item.$3 == '/partner-dashboard/profile';
            return InkWell(
              onTap: () => context.go(item.$3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                color: isActive ? _primaryContainer.withValues(alpha: 0.08) : Colors.transparent,
                child: Row(
                  children: [
                    Icon(item.$1, size: 20, color: isActive ? _primaryContainer : _onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(item.$2, style: TextStyle(
                      color: isActive ? _primaryContainer : _onSurface,
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

  // ── Top Bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, PartnerProfileState state, PartnerProfileController controller) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _surfaceLowest,
        border: Border(bottom: BorderSide(color: _surfaceHigh)),
      ),
      child: Row(
        children: [
          const Text('My Workshop Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _onSurface)),
          const Spacer(),
          if (state.partnerData != null) ...[
            // Online / Offline toggle
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: state.partnerData!['is_active'] == true ? _emerald500 : _onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  state.partnerData!['is_active'] == true ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: state.partnerData!['is_active'] == true ? _emerald500 : _onSurfaceVariant,
                    fontWeight: FontWeight.w500, fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: state.partnerData!['is_active'] == true,
                  activeColor: _emerald500,
                  onChanged: (val) => controller.toggleOnlineStatus(val),
                ),
              ],
            ),
            const SizedBox(width: 16),
            if (_isEditing) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: _onSurfaceVariant, side: const BorderSide(color: _surfaceHigh)),
                onPressed: () => setState(() => _isEditing = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _primaryContainer, foregroundColor: _onPrimary),
                icon: state.isSaving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
                style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: _onPrimary),
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

  // ── Body ─────────────────────────────────────────────────────────────────
  Widget _buildBody(PartnerProfileState state, PartnerProfileController controller) {
    final p = state.partnerData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero header
          _buildHeroCard(p),
          const SizedBox(height: 20),
          // Two-column row: Contact & KPIs
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildContactCard(p)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildKpiCard(state)),
            ],
          ),
          const SizedBox(height: 20),
          _buildFacilityPhotosCard(state),
          const SizedBox(height: 20),
          _buildDocumentStatusCard(p),
        ],
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> p) {
    final tier = p['tier']?.toString() ?? 'standard';
    final tierColor = switch (tier.toLowerCase()) {
      'premium' => _amber500,
      'elite'   => _primaryContainer,
      _         => _blue500,
    };
    final statusPending = p['status']?.toString() == 'pending';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _surfaceHigh),
      ),
      child: Row(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: _primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.storefront, size: 36, color: _primaryContainer),
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
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _onSurface),
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
                      child: Text(
                        tier.toUpperCase(),
                        style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
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
                        child: const Text('PENDING REVIEW', style: TextStyle(color: _amber500, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  p['address']?.toString() ?? 'No address on file',
                  style: const TextStyle(color: _onSurfaceVariant, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (p['submitted_at'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Member since ${DateFormat.yMMMd().format(DateTime.parse(p['submitted_at'].toString()))}',
                    style: const TextStyle(color: _onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact & Operations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 16),
          const Divider(color: _surfaceHigh),
          const SizedBox(height: 12),
          if (_isEditing) ...[
            _editField('Address', _addressCtrl, Icons.location_on_outlined),
            const SizedBox(height: 12),
            _editField('Paint Brand Partner', _paintBrandCtrl, Icons.palette_outlined),
            const SizedBox(height: 12),
            _editField('Daily Throughput Capacity', _throughputCtrl, Icons.speed_outlined, keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _editField('Service Radius (km)', _radiusCtrl, Icons.radar_outlined, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ] else ...[
            _infoRow(Icons.location_on_outlined, 'Address', p['address']?.toString() ?? '—'),
            _infoRow(Icons.palette_outlined, 'Paint Brand', p['paint_brand']?.toString() ?? '—'),
            _infoRow(Icons.speed_outlined, 'Daily Capacity', '${p['throughput_capacity'] ?? '—'} panels/day'),
            _infoRow(Icons.radar_outlined, 'Service Radius', '${p['service_radius_km'] ?? '—'} km'),
          ],
        ],
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, IconData icon, {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: _onSurface),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: _onSurfaceVariant),
        filled: true,
        fillColor: _surfaceLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _surfaceHigh)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _surfaceHigh)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryContainer, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: const TextStyle(fontSize: 13, color: _onSurfaceVariant),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: _onSurfaceVariant))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: _onSurface, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildKpiCard(PartnerProfileState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance KPIs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 16),
          const Divider(color: _surfaceHigh),
          const SizedBox(height: 12),
          _kpiTile('Total Jobs Completed', '${state.totalJobsDone}', Icons.check_circle_outline, _emerald500),
          const SizedBox(height: 12),
          _kpiTile('Avg. Repair Duration', '${state.avgRepairDays.toStringAsFixed(1)} days', Icons.schedule_outlined, _blue500),
          const SizedBox(height: 12),
          _kpiTile('Daily Capacity', '${state.partnerData?['throughput_capacity'] ?? '—'} panels', Icons.speed_outlined, _amber500),
        ],
      ),
    );
  }

  Widget _kpiTile(String label, String value, IconData icon, Color color) {
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
              Text(label, style: const TextStyle(fontSize: 11, color: _onSurfaceVariant)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFacilityPhotosCard(PartnerProfileState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Facility Photos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 14),
          state.facilityPhotoUrls.isEmpty
              ? Container(
                  height: 100,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _surfaceLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _surfaceHigh, style: BorderStyle.solid),
                  ),
                  child: const Text('No facility photos uploaded yet.', style: TextStyle(color: _onSurfaceVariant, fontSize: 13)),
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
                          width: 160, height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 160, height: 120,
                            color: _surfaceLow,
                            child: const Icon(Icons.broken_image_outlined, color: _onSurfaceVariant),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildDocumentStatusCard(Map<String, dynamic> p) {
    final docs = [
      ('NIB', 'nib_file_key', Icons.article_outlined),
      ('NPWP', 'npwp_file_key', Icons.receipt_long_outlined),
      ('SIUP', 'siup_file_key', Icons.business_center_outlined),
      ('KTP', 'ktp_file_key', Icons.badge_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Document Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 14),
          ...docs.map((doc) {
            final hasDoc = p[doc.$2] != null && p[doc.$2].toString().isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(doc.$3, size: 18, color: hasDoc ? _emerald500 : _onSurfaceVariant),
                  const SizedBox(width: 12),
                  SizedBox(width: 60, child: Text(doc.$1, style: const TextStyle(fontSize: 13, color: _onSurface, fontWeight: FontWeight.w500))),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasDoc ? _emerald500.withValues(alpha: 0.1) : _amber500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hasDoc ? 'Uploaded' : 'Pending Upload',
                      style: TextStyle(color: hasDoc ? _emerald500 : _amber500, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildError(String? msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: _errorRed),
          const SizedBox(height: 12),
          Text(msg ?? 'Failed to load profile.', style: const TextStyle(color: _onSurfaceVariant)),
        ],
      ),
    );
  }
}
