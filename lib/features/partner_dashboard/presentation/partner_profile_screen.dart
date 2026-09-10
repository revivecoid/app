import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import 'partner_profile_controller.dart';
import 'partner_shell_screen.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _red    = Color(0xFFd10721);
const _onRed  = Color(0xFFffffff);
const _green  = Color(0xFF10B981);
const _amber  = Color(0xFFF59E0B);

class PartnerProfileScreen extends ConsumerStatefulWidget {
  PartnerProfileScreen({super.key});

  @override
  ConsumerState<PartnerProfileScreen> createState() =>
      _PartnerProfileScreenState();
}

class _PartnerProfileScreenState
    extends ConsumerState<PartnerProfileScreen> {
  final _picker = ImagePicker();

  // ── Text controllers (pre-populated when partnerData loads) ───────────────
  final _entityCtrl    = TextEditingController();
  final _shopCtrl      = TextEditingController();
  final _ownerCtrl     = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _addressCtrl   = TextEditingController();
  final _baysCtrl      = TextEditingController();
  final _boothsCtrl    = TextEditingController();

  // ── Local selections (synced from DB on load) ─────────────────────────────
  int    _tier           = 2;
  String _paintBrand     = 'glasurit';
  double _throughput     = 12;
  double _radius         = 15;

  bool _populated = false;  // guard so we only pre-populate once

  // ── Expanded section state ────────────────────────────────────────────────
  final _expanded = [true, false, false, false];

  @override
  void dispose() {
    for (final c in [_entityCtrl, _shopCtrl, _ownerCtrl, _phoneCtrl,
        _emailCtrl, _addressCtrl, _baysCtrl, _boothsCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _populate(Map<String, dynamic> p) {
    if (_populated) return;
    _populated = true;
    _entityCtrl.text  = p['entity_name']?.toString() ?? '';
    _shopCtrl.text    = p['shop_name']?.toString() ?? '';
    _ownerCtrl.text   = p['owner_name']?.toString() ?? '';
    _phoneCtrl.text   = p['phone']?.toString() ?? '';
    _emailCtrl.text   = p['email']?.toString() ?? '';
    _addressCtrl.text = p['address']?.toString() ?? '';
    _baysCtrl.text    = p['working_bays']?.toString() ?? '';
    _boothsCtrl.text  = p['spray_booths']?.toString() ?? '';
    setState(() {
      _tier       = (p['tier'] as num?)?.toInt() ?? 2;
      _paintBrand = p['paint_brand']?.toString() ?? 'glasurit';
      _throughput = (p['throughput_capacity'] as num?)?.toDouble() ?? 12;
      _radius     = (p['service_radius_km'] as num?)?.toDouble() ?? 15;
    });
  }

  // ── Pick & upload doc ─────────────────────────────────────────────────────
  Future<void> _pickDoc(String docType) async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref
        .read(partnerProfileProvider.notifier)
        .uploadDocument(docType, bytes, file.name);
  }

  // ── Pick & upload facility photo ──────────────────────────────────────────
  Future<void> _pickPhoto(int slot) async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1920, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref
        .read(partnerProfileProvider.notifier)
        .uploadFacilityPhoto(slot, bytes);
  }

  // ── Save text fields ───────────────────────────────────────────────────────
  Future<void> _save() async {
    await ref.read(partnerProfileProvider.notifier).saveDetails(
      entityName:        _entityCtrl.text.trim().isEmpty ? null : _entityCtrl.text.trim(),
      shopName:          _shopCtrl.text.trim().isEmpty   ? null : _shopCtrl.text.trim(),
      ownerName:         _ownerCtrl.text.trim().isEmpty  ? null : _ownerCtrl.text.trim(),
      phone:             _phoneCtrl.text.trim().isEmpty  ? null : _phoneCtrl.text.trim(),
      email:             _emailCtrl.text.trim().isEmpty  ? null : _emailCtrl.text.trim(),
      address:           _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      tier:              _tier,
      paintBrand:        _paintBrand,
      throughputCapacity: _throughput.round(),
      serviceRadiusKm:   _radius,
      workingBays:       int.tryParse(_baysCtrl.text.trim()),
      sprayBooths:       int.tryParse(_boothsCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state      = ref.watch(partnerProfileProvider);
    final notifier   = ref.read(partnerProfileProvider.notifier);
    final cs         = Theme.of(context).colorScheme;
    final user       = Supabase.instance.client.auth.currentUser;

    // Pre-populate controllers when data arrives
    if (state.partnerData != null) _populate(state.partnerData!);

    // Snackbars
    ref.listen(partnerProfileProvider, (_, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: _green,
        ));
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: _red,
        ));
      }
    });

    final isActive = state.partnerData?['is_active'] == true;

    final topBarActions = <Widget>[
      // Online toggle
      Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(
                color: isActive ? _green : cs.outlineVariant,
                shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(isActive ? 'Online' : 'Offline',
            style: TextStyle(
                color: isActive ? _green : cs.onSurfaceVariant,
                fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(width: 6),
        Switch(
          value: isActive,
          activeThumbColor: _green,
          onChanged: state.isLoading
              ? null
              : (v) => notifier.toggleOnlineStatus(v),
        ),
      ]),
      const SizedBox(width: 12),
      // Save button
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: _red, foregroundColor: _onRed),
        icon: state.isSaving
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_outlined, size: 16),
        label: const Text('Save Details'),
        onPressed: state.isSaving ? null : _save,
      ),
    ];

    Widget body;
    if (state.isLoading) {
      body = const Center(child: CircularProgressIndicator(color: _red));
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status banner if pending
              if (state.partnerData?['status']?.toString() == 'pending')
                _StatusBanner(
                    cs: cs,
                    msg: 'Your application is under review. Details are editable while pending.'),
              if (state.partnerData == null)
                _StatusBanner(
                    cs: cs,
                    isNew: true,
                    msg: 'Welcome! Fill in your workshop details and tap Save to get started.'),

              const SizedBox(height: 16),

              // Section 1: Workshop Identity
              _SectionCard(
                index: 0,
                expanded: _expanded[0],
                onToggle: () => setState(() => _expanded[0] = !_expanded[0]),
                icon: Icons.apartment_outlined,
                title: '1. Workshop Identity & Tier',
                subtitle: 'Legal entity, contact info, and tier selection',
                cs: cs,
                child: _buildSection1(cs),
              ),
              const SizedBox(height: 12),

              // Section 2: Capacity & Equipment
              _SectionCard(
                index: 1,
                expanded: _expanded[1],
                onToggle: () => setState(() => _expanded[1] = !_expanded[1]),
                icon: Icons.precision_manufacturing_outlined,
                title: '2. Capacity & Equipment',
                subtitle: 'Bays, booths, paint brand, daily throughput',
                cs: cs,
                child: _buildSection2(cs),
              ),
              const SizedBox(height: 12),

              // Section 3: Facility Photos
              _SectionCard(
                index: 2,
                expanded: _expanded[2],
                onToggle: () => setState(() => _expanded[2] = !_expanded[2]),
                icon: Icons.add_photo_alternate_outlined,
                title: '3. Facility Photos',
                subtitle: 'Each upload is saved — previous versions are preserved',
                badge: _photoUploadCount(state, cs),
                cs: cs,
                child: _buildSection3(state, notifier, cs),
              ),
              const SizedBox(height: 12),

              // Section 4: Legal Documents
              _SectionCard(
                index: 3,
                expanded: _expanded[3],
                onToggle: () => setState(() => _expanded[3] = !_expanded[3]),
                icon: Icons.badge_outlined,
                title: '4. Legal Documents',
                subtitle: 'All uploaded versions are stored — nothing is overwritten',
                badge: _docUploadBadge(state, cs),
                cs: cs,
                child: _buildSection4(state, cs),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      );
    }

    return PartnerShellScreen(
      activeRoute: '/partner-dashboard/profile',
      pageTitle: 'Partner Details',
      trailingActions: topBarActions,
      child: body,
    );
  }

  // ── Section 1 — Workshop Identity ─────────────────────────────────────────

  Widget _buildSection1(ColorScheme cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Tier selector
      Text('OPERATIONAL TIER', style: _labelStyle(cs)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _TierCard(tier: 1, selected: _tier == 1,
            title: 'Tier 1 — Flagship', sub: '>10 bays · 85% revenue',
            icon: Icons.workspace_premium_outlined,
            onTap: () => setState(() => _tier = 1))),
        const SizedBox(width: 10),
        Expanded(child: _TierCard(tier: 2, selected: _tier == 2,
            title: 'Tier 2 — Authorized', sub: '5-9 bays · 82% revenue',
            icon: Icons.store_outlined,
            onTap: () => setState(() => _tier = 2))),
        const SizedBox(width: 10),
        Expanded(child: _TierCard(tier: 3, selected: _tier == 3,
            title: 'Tier 3 — Express PDR', sub: '3-5 bays · 80% revenue',
            icon: Icons.build_circle_outlined,
            onTap: () => setState(() => _tier = 3))),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: _field('Legal Entity Name (PT/CV)', _entityCtrl, cs)),
        const SizedBox(width: 14),
        Expanded(child: _field('Trade / Workshop Brand Name', _shopCtrl, cs)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _field('PIC / General Manager', _ownerCtrl, cs)),
        const SizedBox(width: 14),
        Expanded(child: _field('WhatsApp Number', _phoneCtrl, cs,
            keyboardType: TextInputType.phone, prefix: '+62')),
      ]),
      const SizedBox(height: 12),
      _field('Business Email', _emailCtrl, cs,
          keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 12),
      _field('Workshop Address', _addressCtrl, cs, maxLines: 2),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Service Radius', style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w600)),
        Text('${_radius.round()} km',
            style: const TextStyle(color: _red, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
      Slider(
        value: _radius, min: 2, max: 50,
        activeColor: _red,
        onChanged: (v) => setState(() => _radius = v),
      ),
    ]);
  }

  // ── Section 2 — Capacity & Equipment ──────────────────────────────────────

  Widget _buildSection2(ColorScheme cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _field('Active Working Bays', _baysCtrl, cs,
            keyboardType: TextInputType.number, suffix: 'bays')),
        const SizedBox(width: 14),
        Expanded(child: _field('Spray Oven Booths', _boothsCtrl, cs,
            keyboardType: TextInputType.number, suffix: 'booths')),
      ]),
      const SizedBox(height: 20),
      Text('CERTIFIED PAINT BRAND', style: _labelStyle(cs)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final b in [
          ('glasurit', 'Glasurit 2K', 'BASF'),
          ('spies', 'Spies Hecker', 'Axalta'),
          ('sikkens', 'Sikkens', 'AkzoNobel'),
          ('nippon', 'Nippon Paint', 'Nax Premila'),
        ])
          _PaintCard(
            id: b.$1, title: b.$2, sub: b.$3,
            selected: _paintBrand == b.$1,
            onTap: () => setState(() => _paintBrand = b.$1),
            cs: cs,
          ),
      ]),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Daily Throughput Capacity', style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w600)),
        Text('${_throughput.round()} panels/day',
            style: const TextStyle(color: _red, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
      Slider(
        value: _throughput, min: 4, max: 30,
        activeColor: _red,
        divisions: 26,
        onChanged: (v) => setState(() => _throughput = v),
      ),
    ]);
  }

  // ── Section 3 — Facility Photos ───────────────────────────────────────────

  static const _photoLabels = [
    'Workshop Facade', 'Spray Oven Booth', 'Customer Lounge', 'Mixing Station'
  ];

  Widget _photoUploadCount(PartnerProfileState s, ColorScheme cs) {
    final count = s.facilityPhotos.where((slot) => slot.isNotEmpty).length;
    return Text('$count/4 uploaded',
        style: TextStyle(fontSize: 11, color: count == 4 ? _green : cs.onSurfaceVariant));
  }

  Widget _buildSection3(PartnerProfileState state,
      PartnerProfileController notifier, ColorScheme cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tap a slot to upload a new version. Previous photos are saved.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      const SizedBox(height: 14),
      Wrap(spacing: 12, runSpacing: 12,
        children: List.generate(4, (i) {
          final versions = state.facilityPhotos.length > i
              ? state.facilityPhotos[i] : <PartnerPhotoVersion>[];
          final current = versions.where((v) => v.isCurrent).firstOrNull;
          final isUploading = state.uploading.contains('photo_$i');
          final publicUrl = current != null
              ? notifier.getPublicUrl(current.fileKey) : null;

          return SizedBox(
            width: 180, height: 160,
            child: _PhotoSlot(
              label: _photoLabels[i],
              publicUrl: publicUrl,
              versionCount: versions.length,
              isUploading: isUploading,
              cs: cs,
              onTap: () => _pickPhoto(i),
            ),
          );
        }),
      ),
    ]);
  }

  // ── Section 4 — Legal Documents ───────────────────────────────────────────

  Widget? _docUploadBadge(PartnerProfileState s, ColorScheme cs) {
    final count = ['nib','npwp','siup','ktp']
        .where((t) => s.documents[t]?.isNotEmpty == true).length;
    return Text('$count/4 uploaded',
        style: TextStyle(fontSize: 11, color: count == 4 ? _green : cs.onSurfaceVariant));
  }

  static const _docs = [
    ('nib',  Icons.description_outlined,    'NIB — Nomor Induk Berusaha'),
    ('npwp', Icons.receipt_long_outlined,   'NPWP Badan Usaha'),
    ('siup', Icons.upload_file_outlined,    'SIUP — Izin Operasional'),
    ('ktp',  Icons.contact_page_outlined,   'KTP Direktur / PIC'),
  ];

  Widget _buildSection4(PartnerProfileState state, ColorScheme cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Each upload creates a new version. All versions are stored.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        for (final doc in _docs) ...[
          _DocRow(
            docType:     doc.$1,
            icon:        doc.$2,
            title:       doc.$3,
            versions:    state.documents[doc.$1] ?? [],
            isUploading: state.uploading.contains('doc_${doc.$1}'),
            cs:          cs,
            onUpload:    () => _pickDoc(doc.$1),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  TextStyle _labelStyle(ColorScheme cs) =>
      TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
          letterSpacing: 0.5, color: cs.onSurfaceVariant);

  Widget _field(String label, TextEditingController ctrl, ColorScheme cs, {
    TextInputType? keyboardType,
    String? prefix,
    String? suffix,
    int maxLines = 1,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: _labelStyle(cs)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: TextStyle(fontSize: 14, color: cs.onSurface),
        decoration: InputDecoration(
          prefixText: prefix != null ? '$prefix ' : null,
          suffixText: suffix,
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.outlineVariant)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.outlineVariant)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _red, width: 2)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    ]);
  }
}

// ─── Reusable sub-widgets ─────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final ColorScheme cs;
  final String msg;
  final bool isNew;
  const _StatusBanner({required this.cs, required this.msg, this.isNew = false});

  @override
  Widget build(BuildContext context) {
    final color = isNew ? const Color(0xFF3B82F6) : _amber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(isNew ? Icons.waving_hand_outlined : Icons.info_outline,
            size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(msg,
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final int index;
  final bool expanded;
  final VoidCallback onToggle;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? badge;
  final ColorScheme cs;
  final Widget child;

  const _SectionCard({
    required this.index,
    required this.expanded,
    required this.onToggle,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.cs,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: AppColors.fireRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: AppColors.fireRed, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              )),
              if (badge != null) badge!,
              const SizedBox(width: 8),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: cs.onSurfaceVariant),
            ]),
          ),
        ),
        if (expanded) ...[
          Divider(height: 1, color: cs.outlineVariant),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ]),
    );
  }
}

class _TierCard extends StatelessWidget {
  final int tier;
  final bool selected;
  final String title;
  final String sub;
  final IconData icon;
  final VoidCallback onTap;

  const _TierCard({
    required this.tier, required this.selected, required this.title,
    required this.sub, required this.icon, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _red.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? _red : cs.outlineVariant,
              width: selected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: selected ? _red : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4)),
              child: Text('T${tier}',
                  style: TextStyle(
                      color: selected ? _onRed : cs.onSurface,
                      fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            Icon(icon, size: 18,
                color: selected ? _red : cs.onSurfaceVariant),
          ]),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _PaintCard extends StatelessWidget {
  final String id, title, sub;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _PaintCard({required this.id, required this.title, required this.sub,
    required this.selected, required this.onTap, required this.cs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _red.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? _red : cs.outlineVariant,
              width: selected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10,
              color: selected ? _red : cs.outlineVariant),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
            Text(sub, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ]),
        ]),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final String label;
  final String? publicUrl;
  final int versionCount;
  final bool isUploading;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _PhotoSlot({
    required this.label, required this.publicUrl, required this.versionCount,
    required this.isUploading, required this.cs, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: publicUrl != null
                ? _green.withValues(alpha: 0.5)
                : _red.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: isUploading
            ? Center(child: CircularProgressIndicator(color: _red, strokeWidth: 2))
            : publicUrl != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.network(publicUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 36)),
                    // Version count badge
                    if (versionCount > 1)
                      Positioned(top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('v$versionCount',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    // Label + tap to update
                    Positioned(bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        color: Colors.black.withValues(alpha: 0.6),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Flexible(child: Text(label,
                              style: const TextStyle(color: Colors.white, fontSize: 9),
                              overflow: TextOverflow.ellipsis)),
                          const Icon(Icons.upload, size: 12, color: Colors.white70),
                        ]),
                      ),
                    ),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.cloud_upload_outlined, color: _red, size: 28),
                    const SizedBox(height: 6),
                    Text(label,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurface),
                        textAlign: TextAlign.center),
                    Text('Tap to upload',
                        style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                  ]),
      ),
    );
  }
}

class _DocRow extends StatefulWidget {
  final String docType;
  final IconData icon;
  final String title;
  final List<PartnerDocVersion> versions;
  final bool isUploading;
  final ColorScheme cs;
  final VoidCallback onUpload;

  const _DocRow({
    required this.docType, required this.icon, required this.title,
    required this.versions, required this.isUploading, required this.cs,
    required this.onUpload,
  });

  @override
  State<_DocRow> createState() => _DocRowState();
}

class _DocRowState extends State<_DocRow> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final current = widget.versions.where((v) => v.isCurrent).firstOrNull;
    final hasDoc = current != null;
    final historyCount = widget.versions.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: hasDoc
                  ? _green.withValues(alpha: 0.4)
                  : cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: hasDoc
                  ? _green.withValues(alpha: 0.1)
                  : _red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              hasDoc ? Icons.check_circle_outline : widget.icon,
              color: hasDoc ? _green : _red, size: 20,
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 2),
            if (hasDoc)
              Text('${current.fileName}  ·  ${_fmtDate(current.uploadedAt)}',
                  style: TextStyle(fontSize: 10, color: _green),
                  overflow: TextOverflow.ellipsis)
            else
              Text('Not yet uploaded',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            if (historyCount > 1)
              GestureDetector(
                onTap: () => setState(() => _showHistory = !_showHistory),
                child: Text(
                  _showHistory
                      ? 'Hide history'
                      : '$historyCount versions — show history',
                  style: const TextStyle(
                      fontSize: 10, color: _red, fontWeight: FontWeight.w600),
                ),
              ),
          ])),
          // Upload button
          const SizedBox(width: 10),
          widget.isUploading
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: _red, strokeWidth: 2))
              : TextButton.icon(
                  onPressed: widget.onUpload,
                  icon: const Icon(Icons.upload_file_outlined, size: 14),
                  label: Text(hasDoc ? 'New Version' : 'Upload',
                      style: const TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: _red),
                ),
        ]),
      ),
      // History accordion
      if (_showHistory && widget.versions.length > 1)
        Container(
          margin: const EdgeInsets.only(top: 4, left: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            for (final v in widget.versions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(
                    v.isCurrent ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 14,
                    color: v.isCurrent ? _green : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(v.fileName,
                      style: TextStyle(fontSize: 11, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(_fmtDate(v.uploadedAt),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                  if (v.isCurrent) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('current',
                          style: TextStyle(fontSize: 9, color: _green, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
              ),
          ]),
        ),
    ]);
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
