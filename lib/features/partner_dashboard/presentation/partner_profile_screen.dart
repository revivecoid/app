import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import 'partner_profile_controller.dart';

// ─── Brand accent colors (theme-invariant) ───────────────────────────────────
const _primary = Color(0xFFa40016);
const _primaryContainer = Color(0xFFd10721);
const _onPrimary = Color(0xFFffffff);
const _emerald500 = Color(0xFF10B981);
const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);
const _errorRed = Color(0xFF93000a);

const _kSidebarWidth = 260.0;

class PartnerProfileScreen extends ConsumerStatefulWidget {
  PartnerProfileScreen({super.key});
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
    final cs = Theme.of(context).colorScheme;

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

    return LayoutBuilder(builder: (context, constraints) {
      Widget inner = Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        children: [
          _buildSidebar(context, cs),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, state, controller, cs),
                Expanded(
                  child: state.isLoading
                      ? Center(child: CircularProgressIndicator(color: _primaryContainer))
                      : state.partnerData == null
                          ? _buildError(state.errorMessage, cs)
                          : _buildBody(state, controller, cs),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      return inner;
    });
  }

  // ── Sidebar ──────────────────────────────────────────────────────────────
  Widget _buildSidebar(BuildContext context, ColorScheme cs) {
    final items = [
      (Icons.dashboard_outlined, 'Dashboard', '/partner-dashboard'),
      (Icons.storefront_outlined, 'My Profile', '/partner-dashboard/profile'),
      (Icons.settings_outlined, 'Settings', '/partner-dashboard/settings'),
      (Icons.calendar_month_outlined, 'Schedule', '/partner-dashboard/schedule'),
      (Icons.timer_outlined, 'Panel Durations', '/partner-dashboard/quota'),
    ];
    return Container(
      width: _kSidebarWidth,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          Container(
            height: 64,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_car, color: _primaryContainer, size: 22),
                SizedBox(width: 10),
                Text(AppL.of(context)!.partnerPortal, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          SizedBox(height: 12),
          ...items.map((item) {
            final isActive = item.$3 == '/partner-dashboard/profile';
            return InkWell(
              onTap: () => context.go(item.$3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                color: isActive ? _primaryContainer.withValues(alpha: 0.08) : Colors.transparent,
                child: Row(
                  children: [
                    Icon(item.$1, size: 20, color: isActive ? _primaryContainer : cs.onSurfaceVariant),
                    SizedBox(width: 12),
                    Text(item.$2, style: TextStyle(
                      color: isActive ? _primaryContainer : cs.onSurface,
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
  Widget _buildTopBar(BuildContext context, PartnerProfileState state, PartnerProfileController controller, ColorScheme cs) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(AppL.of(context)!.partnerWorkshopProfile, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(width: 16),
          FilledButton.tonal(
            onPressed: () => context.go('/partner-dashboard'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.dashboard_outlined, size: 15),
              const SizedBox(width: 6),
              Text(AppL.of(context)!.partnerDashboard, style: TextStyle(fontSize: 13)),
            ]),
          ),
          Spacer(),
          if (state.partnerData != null) ...[
            // Online / Offline toggle
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: state.partnerData!['is_active'] == true ? _emerald500 : cs.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  state.partnerData!['is_active'] == true ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: state.partnerData!['is_active'] == true ? _emerald500 : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500, fontSize: 13,
                  ),
                ),
                SizedBox(width: 8),
                Switch(
                  value: state.partnerData!['is_active'] == true,
                  activeThumbColor: _emerald500,
                  onChanged: (val) => controller.toggleOnlineStatus(val),
                ),
              ],
            ),
            SizedBox(width: 16),
            if (_isEditing) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: cs.onSurfaceVariant, side: BorderSide(color: cs.outlineVariant)),
                onPressed: () => setState(() => _isEditing = false),
                child: Text(AppL.of(context)!.cancel),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _primaryContainer, foregroundColor: _onPrimary),
                icon: state.isSaving
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: cs.surface, strokeWidth: 2))
                    : Icon(Icons.save_outlined, size: 16),
                label: Text(AppL.of(context)!.saveChanges),
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
                icon: Icon(Icons.edit_outlined, size: 16),
                label: Text(AppL.of(context)!.edit),
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
  Widget _buildBody(PartnerProfileState state, PartnerProfileController controller, ColorScheme cs) {
    final p = state.partnerData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero header
          _buildHeroCard(p, cs),
          SizedBox(height: 20),
          // Two-column row: Contact & KPIs
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildContactCard(p, cs)),
              SizedBox(width: 16),
              Expanded(flex: 2, child: _buildKpiCard(state, cs)),
            ],
          ),
          SizedBox(height: 20),
          _buildFacilityPhotosCard(state, cs),
          SizedBox(height: 20),
          _buildDocumentStatusCard(p, cs),
        ],
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> p, ColorScheme cs) {
    final tier = p['tier']?.toString() ?? 'standard';
    final tierColor = switch (tier.toLowerCase()) {
      'premium' => _amber500,
      'elite'   => _primaryContainer,
      _         => _blue500,
    };
    final statusPending = p['status']?.toString() == 'pending';

    // Google account owner name
    final user = Supabase.instance.client.auth.currentUser;
    final ownerName = user?.userMetadata?['full_name']?.toString()
        ?? user?.userMetadata?['name']?.toString()
        ?? user?.email
        ?? '';
    final avatarUrl = user?.userMetadata?['avatar_url']?.toString();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          // Avatar: Google profile picture if available, else storefront icon
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: _primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.storefront, size: 36, color: _primaryContainer),
                  )
                : Icon(Icons.storefront, size: 36, color: _primaryContainer),
          ),
          SizedBox(width: 20),
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
                    SizedBox(width: 10),
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
                      SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _amber500.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _amber500.withValues(alpha: 0.4)),
                        ),
                        child: Text(AppL.of(context)!.partnerPendingReview, style: TextStyle(color: _amber500, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 4),
                // Account owner name from Google OAuth
                if (ownerName.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 13, color: cs.onSurfaceVariant),
                      SizedBox(width: 4),
                      Text(
                        ownerName,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                SizedBox(height: 4),
                Text(
                  p['address']?.toString() ?? 'No address on file',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (p['submitted_at'] != null) ...[
                  SizedBox(height: 4),
                  Text(
                    'Member since ${DateFormat.yMMMd().format(DateTime.parse(p['submitted_at'].toString()))}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> p, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppL.of(context)!.partnerContactOps, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
          SizedBox(height: 16),
          Divider(color: cs.outlineVariant),
          SizedBox(height: 12),
          if (_isEditing) ...[
            _editField('Address', _addressCtrl, Icons.location_on_outlined, cs),
            SizedBox(height: 12),
            _editField('Paint Brand Partner', _paintBrandCtrl, Icons.palette_outlined, cs),
            SizedBox(height: 12),
            _editField('Daily Throughput Capacity', _throughputCtrl, Icons.speed_outlined, cs, keyboardType: TextInputType.number),
            SizedBox(height: 12),
            _editField('Service Radius (km)', _radiusCtrl, Icons.radar_outlined, cs, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ] else ...[
            _infoRow(Icons.location_on_outlined, 'Address', p['address']?.toString() ?? '—', cs),
            _infoRow(Icons.palette_outlined, 'Paint Brand', p['paint_brand']?.toString() ?? '—', cs),
            _infoRow(Icons.speed_outlined, 'Daily Capacity', '${p['throughput_capacity'] ?? '—'} panels/day', cs),
            _infoRow(Icons.radar_outlined, 'Service Radius', '${p['service_radius_km'] ?? '—'} km', cs),
          ],
        ],
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, IconData icon, ColorScheme cs, {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 14, color: cs.onSurface),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _primaryContainer, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          SizedBox(width: 10),
          SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildKpiCard(PartnerProfileState state, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppL.of(context)!.partnerPerformanceKpis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
          SizedBox(height: 16),
          Divider(color: cs.outlineVariant),
          SizedBox(height: 12),
          _kpiTile('Total Jobs Completed', '${state.totalJobsDone}', Icons.check_circle_outline, _emerald500, cs),
          SizedBox(height: 12),
          _kpiTile('Avg. Repair Duration', '${state.avgRepairDays.toStringAsFixed(1)} days', Icons.schedule_outlined, _blue500, cs),
          SizedBox(height: 12),
          _kpiTile('Daily Capacity', '${state.partnerData?['throughput_capacity'] ?? '—'} panels', Icons.speed_outlined, _amber500, cs),
        ],
      ),
    );
  }

  Widget _kpiTile(String label, String value, IconData icon, Color color, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
        SizedBox(width: 12),
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

  Widget _buildFacilityPhotosCard(PartnerProfileState state, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppL.of(context)!.partnerFacilityPhotos, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
          SizedBox(height: 14),
          state.facilityPhotoUrls.isEmpty
              ? Container(
                  height: 100,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant, style: BorderStyle.solid),
                  ),
                  child: Text(AppL.of(context)!.partnerNoPhotos, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                )
              : SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: state.facilityPhotoUrls.length,
                    separatorBuilder: (_, __) => SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          state.facilityPhotoUrls[i],
                          width: 160, height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 160, height: 120,
                            color: cs.surfaceContainerHighest,
                            child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
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

  Widget _buildDocumentStatusCard(Map<String, dynamic> p, ColorScheme cs) {
    final docs = [
      ('NIB', 'nib_file_key', Icons.article_outlined),
      ('NPWP', 'npwp_file_key', Icons.receipt_long_outlined),
      ('SIUP', 'siup_file_key', Icons.business_center_outlined),
      ('KTP', 'ktp_file_key', Icons.badge_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppL.of(context)!.partnerDocumentStatus, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
          SizedBox(height: 14),
          ...docs.map((doc) {
            final hasDoc = p[doc.$2] != null && p[doc.$2].toString().isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(doc.$3, size: 18, color: hasDoc ? _emerald500 : cs.onSurfaceVariant),
                  SizedBox(width: 12),
                  SizedBox(width: 60, child: Text(doc.$1, style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500))),
                  SizedBox(width: 16),
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

  Widget _buildError(String? msg, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: _errorRed),
          SizedBox(height: 12),
          Text(msg ?? 'Failed to load profile.', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
