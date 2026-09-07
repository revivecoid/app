import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';

// ignore_for_file: library_private_types_in_public_api

// --- Static dashboard data ---
class _NlpIntent {
  final String name, description;
  final int phrases;
  final double accuracy;
  final bool active;
  const _NlpIntent({required this.name, required this.description, required this.phrases, required this.accuracy, this.active = true});
}

const _nlpIntents = [
  _NlpIntent(name: 'estimate_request', description: 'Customer requests damage cost estimate', phrases: 48, accuracy: 97.2),
  _NlpIntent(name: 'booking_schedule', description: 'Customer wants to book workshop slot', phrases: 35, accuracy: 95.8),
  _NlpIntent(name: 'track_repair_status', description: 'Query on ongoing repair progress', phrases: 27, accuracy: 98.1),
  _NlpIntent(name: 'payment_query', description: 'Questions about invoice and payment', phrases: 22, accuracy: 93.4),
  _NlpIntent(name: 'partner_escalation', description: 'Escalate to human partner agent', phrases: 15, accuracy: 91.0),
  _NlpIntent(name: 'promo_inquiry', description: 'Ask about active promotions & discounts', phrases: 19, accuracy: 89.5, active: false),
  _NlpIntent(name: 'complaint_filing', description: 'Customer filing dissatisfaction report', phrases: 31, accuracy: 96.3),
];

class _Settlement {
  final String partner, workshopId, amount, commission, status, date;
  const _Settlement({required this.partner, required this.workshopId, required this.amount, required this.commission, required this.status, required this.date});
}

const _settlements = [
  _Settlement(partner: 'AutoBody Prima JKT', workshopId: 'WS-JKT-001', amount: 'Rp 24.500.000', commission: 'Rp 3.675.000', status: 'paid', date: 'Sep 05, 2026'),
  _Settlement(partner: 'Bengkel Sentosa BSD', workshopId: 'WS-BSD-003', amount: 'Rp 18.200.000', commission: 'Rp 2.730.000', status: 'paid', date: 'Sep 05, 2026'),
  _Settlement(partner: 'CV Maju Kencana', workshopId: 'WS-TNG-007', amount: 'Rp 11.750.000', commission: 'Rp 1.762.500', status: 'pending', date: 'Sep 06, 2026'),
  _Settlement(partner: 'Cat & Body Pondok Indah', workshopId: 'WS-JKS-012', amount: 'Rp 31.000.000', commission: 'Rp 4.650.000', status: 'processing', date: 'Sep 06, 2026'),
  _Settlement(partner: 'Workshop Cibubur Auto', workshopId: 'WS-CBR-004', amount: 'Rp 8.900.000', commission: 'Rp 1.335.000', status: 'paid', date: 'Sep 04, 2026'),
  _Settlement(partner: 'AutoCare Bekasi', workshopId: 'WS-BKS-009', amount: 'Rp 14.300.000', commission: 'Rp 2.145.000', status: 'disputed', date: 'Sep 03, 2026'),
];

// --- Main Screen ---
class FrontendContentStudioScreen extends ConsumerStatefulWidget {
  const FrontendContentStudioScreen({super.key});
  @override
  ConsumerState<FrontendContentStudioScreen> createState() => _FrontendCmsState();
}

class _FrontendCmsState extends ConsumerState<FrontendContentStudioScreen> {
  final _supabase = Supabase.instance.client;
  int _tab = 0;
  bool _loading = true;
  String? _error;
  bool _saving = false;
  Map<String, String> _settings = {};
  List<Map<String, dynamic>> _pricing = [];
  List<FileObject> _assets = [];
  bool _assetsLoading = false;
  String _assetCat = 'All';
  final Map<int, bool> _nlpToggles = {for (var i = 0; i < _nlpIntents.length; i++) i: _nlpIntents[i].active};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _supabase.rpc('get_cms_settings');
      if (res is Map) _settings = res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      final pRes = await _supabase.rpc('get_pricing_rules');
      if (pRes is List) _pricing = pRes.cast<Map<String, dynamic>>();
    } catch (e) { _error = e.toString(); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAssets() async {
    setState(() => _assetsLoading = true);
    try {
      final f = await _supabase.storage.from('revive-photos').list();
      if (mounted) setState(() => _assets = f);
    } catch (_) {}
    if (mounted) setState(() => _assetsLoading = false);
  }

  Future<void> _save(String k, String v, {String cat = 'general'}) async {
    setState(() => _saving = true);
    try {
      await _supabase.rpc('set_cms_setting', params: {'p_key': k, 'p_value': v, 'p_category': cat});
      _settings[k] = v;
    } catch (e) { _snack('Save failed: $e', err: true); }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _updateRule(Map<String, dynamic> r) async {
    try {
      await _supabase.rpc('update_pricing_rule', params: {
        'p_panel_id': r['panel_id'], 'p_base_rate': r['base_rate'],
        'p_severity_min': r['severity_min'], 'p_severity_max': r['severity_max'],
        'p_mode': r['mode'] ?? 'auto', 'p_is_active': r['is_active'] ?? true,
      });
      await _load();
      _snack('Rule updated');
    } catch (e) { _snack('Update failed: $e', err: true); }
  }

  void _snack(String m, {bool err = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), backgroundColor: err ? const Color(0xFFDC2626) : const Color(0xFF059669), duration: const Duration(seconds: 2)));

  String _s(String k, {String fb = ''}) => _settings[k] ?? fb;
  bool _b(String k, {bool fb = true}) => _settings.containsKey(k) ? _settings[k] == 'true' : fb;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(children: [
        _Header(cs: cs, isDark: isDark, ref: ref, tab: _tab, saving: _saving,
          onTab: (i) { setState(() => _tab = i); if (i == 1 && _assets.isEmpty) _loadAssets(); },
          onRefresh: _load),
        Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
            ? _ErrView(cs: cs, error: _error!, onRetry: _load)
            : _body(cs)),
      ]),
    );
  }

  Widget _body(ColorScheme cs) {
    switch (_tab) {
      case 0: return _ContentTab(cs: cs, s: _s, b: _b, onSave: _save);
      case 1: return _AssetTab(cs: cs, assets: _assets, loading: _assetsLoading, cat: _assetCat, onCat: (c) => setState(() => _assetCat = c), onRefresh: _loadAssets, sup: _supabase);
      case 2: return _PricingTab(cs: cs, rules: _pricing, onUpdate: _updateRule);
      case 3: return _NlpTab(cs: cs, toggles: _nlpToggles, onToggle: (i, v) => setState(() => _nlpToggles[i] = v));
      case 4: return _CommissionTab(cs: cs);
      case 5: return _AboutCmsTab(cs: cs, s: _s, onSave: _save);
      case 6: return _PrivacyCmsTab(cs: cs, s: _s, onSave: _save);
      default: return const SizedBox();
    }
  }
}

// --- Header ---
class _Header extends StatelessWidget {
  final ColorScheme cs; final bool isDark, saving; final WidgetRef ref;
  final int tab; final ValueChanged<int> onTab; final VoidCallback onRefresh;
  const _Header({required this.cs, required this.isDark, required this.ref, required this.tab, required this.saving, required this.onTab, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    const icons = [Icons.dashboard_customize_outlined, Icons.folder_special_outlined, Icons.price_change_outlined, Icons.smart_toy_outlined, Icons.payments_outlined, Icons.info_outlined, Icons.privacy_tip_outlined];
    const labels = ['Content Studio', 'Digital Assets', 'Pricing Rules', 'NLP Studio', 'Commissions', 'About Us', 'Privacy Policy'];

    return Container(
      color: cs.surfaceContainerLowest,
      child: Column(children: [
        Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh))),
          child: Row(children: [
            Icon(Icons.tune_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text('Frontend CMS', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            if (saving) ...[
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: cs.primary, strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Saving...', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
            ],
            IconButton(icon: Icon(Icons.refresh_rounded, size: 18, color: cs.onSurfaceVariant), onPressed: onRefresh),
            IconButton(
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 18, color: cs.onSurfaceVariant),
              onPressed: () => ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark),
          ])),
        SizedBox(height: 44, child: ListView.builder(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: labels.length,
          itemBuilder: (_, i) {
            final sel = i == tab;
            return GestureDetector(
              onTap: () => onTab(i),
              child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: sel ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? cs.primary : Colors.transparent)),
                child: Row(children: [
                  Icon(icons[i], size: 14, color: sel ? cs.primary : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(labels[i], style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? cs.primary : cs.onSurfaceVariant)),
                ])));
          })),
      ]));
  }
}

class _ErrView extends StatelessWidget {
  final ColorScheme cs; final String error; final VoidCallback onRetry;
  const _ErrView({required this.cs, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.error_outline, size: 48, color: cs.error), const SizedBox(height: 12),
    Text('Failed to load CMS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
    const SizedBox(height: 4), Text(error, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
    const SizedBox(height: 16), ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
  ]));
}

// --- Tab 0: Content Studio ---
class _ContentTab extends StatefulWidget {
  final ColorScheme cs;
  final String Function(String, {String fb}) s;
  final bool Function(String, {bool fb}) b;
  final Future<void> Function(String, String, {String cat}) onSave;
  const _ContentTab({required this.cs, required this.s, required this.b, required this.onSave});
  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab> {
  late TextEditingController _heroTitle, _heroSub, _heroCta;
  late TextEditingController _s1t, _s1d, _s2t, _s2d, _s3t, _s3d;
  late TextEditingController _cPhone, _cEmail, _cAddr;
  // Support / FAQ page CMS fields
  late TextEditingController _supTitle, _supSub, _supPhone, _supEmail, _supEmergency;
  final _faqQ = <TextEditingController>[], _faqA = <TextEditingController>[];
  int _faqCnt = 3;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _heroTitle = TextEditingController(text: widget.s('hero_title', fb: 'Damage Repaired. Trust Restored.'));
    _heroSub = TextEditingController(text: widget.s('hero_subtitle', fb: 'Premium car body repair - fast, transparent, guaranteed.'));
    _heroCta = TextEditingController(text: widget.s('hero_cta', fb: 'Get Free Estimate'));
    _s1t = TextEditingController(text: widget.s('svc_1_title', fb: 'Damage Assessment'));
    _s1d = TextEditingController(text: widget.s('svc_1_desc', fb: 'AI-powered photo scanning estimates repair cost instantly.'));
    _s2t = TextEditingController(text: widget.s('svc_2_title', fb: 'Workshop Dispatch'));
    _s2d = TextEditingController(text: widget.s('svc_2_desc', fb: 'We assign the best partner workshop near you.'));
    _s3t = TextEditingController(text: widget.s('svc_3_title', fb: 'Quality Guarantee'));
    _s3d = TextEditingController(text: widget.s('svc_3_desc', fb: '90-day workmanship warranty on every repair.'));
    _cPhone = TextEditingController(text: widget.s('contact_phone', fb: '+62 811-1234-5678'));
    _cEmail = TextEditingController(text: widget.s('contact_email', fb: 'hello@revive.co.id'));
    _cAddr = TextEditingController(text: widget.s('contact_address', fb: 'Jakarta, Indonesia'));
    _supTitle     = TextEditingController(text: widget.s('support_page_title',    fb: 'FAQ & Support'));
    _supSub       = TextEditingController(text: widget.s('support_page_subtitle', fb: 'Find answers to common questions or reach out to our team.'));
    _supPhone     = TextEditingController(text: widget.s('support_phone',         fb: '+62 800-123-456'));
    _supEmail     = TextEditingController(text: widget.s('support_email',         fb: 'support@re-v.co.id'));
    _supEmergency = TextEditingController(text: widget.s('support_emergency',     fb: '+62 800-TOW-REVIVE'));
    for (int i = 0; i < _faqCnt; i++) {
      _faqQ.add(TextEditingController(text: widget.s('faq_${i}_q')));
      _faqA.add(TextEditingController(text: widget.s('faq_${i}_a')));
    }
  }

  @override
  void dispose() {
    for (final c in [_heroTitle, _heroSub, _heroCta, _s1t, _s1d, _s2t, _s2d, _s3t, _s3d,
      _cPhone, _cEmail, _cAddr, _supTitle, _supSub, _supPhone, _supEmail, _supEmergency,
      ..._faqQ, ..._faqA]) c.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    final saves = <Future<void>>[
      widget.onSave('hero_title', _heroTitle.text, cat: 'hero'),
      widget.onSave('hero_subtitle', _heroSub.text, cat: 'hero'),
      widget.onSave('hero_cta', _heroCta.text, cat: 'hero'),
      widget.onSave('svc_1_title', _s1t.text, cat: 'services'),
      widget.onSave('svc_1_desc', _s1d.text, cat: 'services'),
      widget.onSave('svc_2_title', _s2t.text, cat: 'services'),
      widget.onSave('svc_2_desc', _s2d.text, cat: 'services'),
      widget.onSave('svc_3_title', _s3t.text, cat: 'services'),
      widget.onSave('svc_3_desc', _s3d.text, cat: 'services'),
      widget.onSave('contact_phone',          _cPhone.text,     cat: 'contact'),
      widget.onSave('contact_email',          _cEmail.text,     cat: 'contact'),
      widget.onSave('contact_address',        _cAddr.text,      cat: 'contact'),
      widget.onSave('support_page_title',     _supTitle.text,   cat: 'support'),
      widget.onSave('support_page_subtitle',  _supSub.text,     cat: 'support'),
      widget.onSave('support_phone',          _supPhone.text,   cat: 'support'),
      widget.onSave('support_email',          _supEmail.text,   cat: 'support'),
      widget.onSave('support_emergency',      _supEmergency.text, cat: 'support'),
    ];
    for (int i = 0; i < _faqCnt; i++) {
      saves.add(widget.onSave('faq_${i}_q', _faqQ[i].text, cat: 'faq'));
      saves.add(widget.onSave('faq_${i}_a', _faqA[i].text, cat: 'faq'));
    }
    await Future.wait(saves);
    setState(() => _dirty = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Content saved'), backgroundColor: Color(0xFF059669)));
  }

  void _mark() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Content Studio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          if (_dirty) FilledButton.icon(onPressed: _saveAll,
            icon: const Icon(Icons.save_rounded, size: 16), label: const Text('Save All Changes')),
        ]),
        const SizedBox(height: 4),
        Text('Control text and toggles on revive.co.id', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        _Card(cs: cs, title: 'Feature Flags', icon: Icons.toggle_on_rounded, children: [
          _Flag(cs: cs, label: 'Hero Banner', sub: 'Main hero section on landing page',
            value: widget.b('hero_enabled'),
            onChange: (v) { widget.onSave('hero_enabled', '$v'); setState(() {}); }),
          _Flag(cs: cs, label: 'Broadcast Bar', sub: 'Top announcement bar',
            value: widget.b('broadcast_enabled'),
            onChange: (v) { widget.onSave('broadcast_enabled', '$v'); setState(() {}); }),
          _Flag(cs: cs, label: 'Promo Toast', sub: 'Floating notification for new visitors',
            value: widget.b('notify_toast'),
            onChange: (v) { widget.onSave('notify_toast', '$v'); setState(() {}); }),
          _Flag(cs: cs, label: 'Urgency Red Bar', sub: 'Red strip for time-sensitive offers',
            value: widget.b('red_bar'),
            onChange: (v) { widget.onSave('red_bar', '$v'); setState(() {}); }),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Hero Section', icon: Icons.star_rounded, children: [
          _Field(cs: cs, label: 'Title', ctrl: _heroTitle, hint: 'Main headline', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Subtitle', ctrl: _heroSub, hint: 'Hero subtext', maxLines: 2, onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'CTA Button', ctrl: _heroCta, hint: 'Button text', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Service Cards', icon: Icons.build_circle_outlined, children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            Text('Service ${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _Field(cs: cs, label: 'Title', ctrl: [_s1t, _s2t, _s3t][i], hint: 'Service name', onChange: _mark),
            const SizedBox(height: 8),
            _Field(cs: cs, label: 'Description', ctrl: [_s1d, _s2d, _s3d][i], hint: 'Service description', maxLines: 2, onChange: _mark),
          ],
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'FAQ & Support Page', icon: Icons.support_agent_outlined, children: [
          _Field(cs: cs, label: 'Page Title',    ctrl: _supTitle,     hint: 'FAQ & Support',  onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Page Subtitle', ctrl: _supSub,       hint: 'Subtitle text', maxLines: 2, onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Phone Number',  ctrl: _supPhone,     hint: '+62 800-xxx-xxx', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Email',         ctrl: _supEmail,     hint: 'support@re-v.co.id', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Emergency / Towing Hotline', ctrl: _supEmergency, hint: '+62 800-TOW-REVIVE', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'FAQ Items', icon: Icons.quiz_outlined, children: [
          for (int i = 0; i < _faqCnt; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Text('FAQ ${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _Field(cs: cs, label: 'Question', ctrl: _faqQ[i], hint: 'e.g. How long does repair take?', onChange: _mark),
            const SizedBox(height: 8),
            _Field(cs: cs, label: 'Answer', ctrl: _faqA[i], hint: 'Answer text', maxLines: 3, onChange: _mark),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () { setState(() { _faqQ.add(TextEditingController()); _faqA.add(TextEditingController()); _faqCnt++; _dirty = true; }); },
            icon: const Icon(Icons.add, size: 16), label: const Text('Add FAQ')),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Contact Info', icon: Icons.contact_phone_outlined, children: [
          _Field(cs: cs, label: 'Phone', ctrl: _cPhone, hint: '+62 xxx', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Email', ctrl: _cEmail, hint: 'hello@revive.co.id', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Address', ctrl: _cAddr, hint: 'City, Country', onChange: _mark),
        ]),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// --- Tab 1: Digital Asset Manager ---
class _AssetTab extends StatelessWidget {
  final ColorScheme cs; final List<FileObject> assets; final bool loading;
  final String cat; final ValueChanged<String> onCat;
  final VoidCallback onRefresh; final SupabaseClient sup;
  const _AssetTab({required this.cs, required this.assets, required this.loading,
    required this.cat, required this.onCat, required this.onRefresh, required this.sup});

  @override
  Widget build(BuildContext context) {
    final filtered = cat == 'All' ? assets : assets.where((a) => _cat(a.name) == cat).toList();
    return Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Digital Asset Manager', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const Spacer(),
        IconButton(icon: Icon(Icons.refresh_rounded, size: 18, color: cs.onSurfaceVariant), onPressed: onRefresh),
      ]),
      Text('revive-photos bucket - Supabase Storage', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, children: ['All', 'Hero', 'Brand', 'Estimator', 'Promo', 'Marketing', 'Other'].map((c) =>
        FilterChip(label: Text(c, style: const TextStyle(fontSize: 11)), selected: cat == c,
          onSelected: (_) => onCat(c),
          selectedColor: cs.primary.withValues(alpha: 0.2),
          checkmarkColor: cs.primary)).toList()),
      const SizedBox(height: 14),
      Expanded(child: loading
        ? Center(child: CircularProgressIndicator(color: cs.primary))
        : assets.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.folder_open_rounded, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No assets in bucket', style: TextStyle(color: cs.onSurfaceVariant))]))
          : ListView.builder(itemCount: filtered.length, itemBuilder: (ctx, i) {
              final f = filtered[i];
              final url = sup.storage.from('revive-photos').getPublicUrl(f.name);
              return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
                child: Row(children: [
                  Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(_icon(f.name), size: 20, color: cs.primary)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                    Text(_cat(f.name), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ])),
                  IconButton(icon: Icon(Icons.copy_rounded, size: 16, color: cs.onSurfaceVariant), tooltip: 'Copy URL',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('URL copied'), duration: Duration(seconds: 1)));
                    }),
                ]));
            })),
    ]));
  }

  String _cat(String n) {
    final l = n.toLowerCase();
    if (l.contains('hero')) return 'Hero';
    if (l.contains('logo') || l.contains('brand')) return 'Brand';
    if (l.contains('blueprint') || l.contains('estimator')) return 'Estimator';
    if (l.contains('promo') || l.contains('banner')) return 'Promo';
    if (l.contains('workshop') || l.contains('marketing')) return 'Marketing';
    return 'Other';
  }
  IconData _icon(String n) {
    final l = n.toLowerCase();
    if (l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.webp') || l.endsWith('.png')) return Icons.image_rounded;
    if (l.endsWith('.svg')) return Icons.draw_rounded;
    return Icons.insert_drive_file_rounded;
  }
}

// --- Tab 2: Pricing Rules ---
class _PricingTab extends StatefulWidget {
  final ColorScheme cs;
  final List<Map<String, dynamic>> rules;
  final Future<void> Function(Map<String, dynamic>) onUpdate;
  const _PricingTab({required this.cs, required this.rules, required this.onUpdate});
  @override State<_PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends State<_PricingTab> {
  int? _editing;
  final Map<int, TextEditingController> _rate = {}, _min = {}, _max = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [..._rate.values, ..._min.values, ..._max.values]) c.dispose();
    super.dispose();
  }

  void _start(int i) {
    final r = widget.rules[i];
    _rate[i] = TextEditingController(text: r['base_rate'].toString());
    _min[i] = TextEditingController(text: r['severity_min'].toString());
    _max[i] = TextEditingController(text: r['severity_max'].toString());
    setState(() => _editing = i);
  }

  Future<void> _commit(int i) async {
    final r = Map<String, dynamic>.from(widget.rules[i]);
    r['base_rate'] = double.tryParse(_rate[i]?.text ?? '') ?? r['base_rate'];
    r['severity_min'] = double.tryParse(_min[i]?.text ?? '') ?? r['severity_min'];
    r['severity_max'] = double.tryParse(_max[i]?.text ?? '') ?? r['severity_max'];
    setState(() => _saving = true);
    await widget.onUpdate(r);
    setState(() { _editing = null; _saving = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final fmt = NumberFormat('#,###', 'id_ID');
    return Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('AI Damage & Pricing Rules', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(width: 12),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text('${widget.rules.length} panels', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary))),
      ]),
      const SizedBox(height: 4),
      Text('Base repair rates per body panel - feeds the customer estimator', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(flex: 3, child: Text('Panel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text('Base Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text('Severity Range', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text('Min / Max Est.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
          SizedBox(width: 90, child: Text('Active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant), textAlign: TextAlign.center)),
          const SizedBox(width: 64),
        ])),
      const SizedBox(height: 8),
      Expanded(child: widget.rules.isEmpty
        ? Center(child: Text('No rules found. Run the SQL seed from the implementation plan.', style: TextStyle(color: cs.onSurfaceVariant)))
        : ListView.builder(itemCount: widget.rules.length, itemBuilder: (ctx, i) {
            final r = widget.rules[i];
            final isEd = _editing == i;
            final base = (r['base_rate'] as num?)?.toDouble() ?? 0;
            final sMin = (r['severity_min'] as num?)?.toDouble() ?? 1.0;
            final sMax = (r['severity_max'] as num?)?.toDouble() ?? 3.0;
            final active = r['is_active'] as bool? ?? true;
            return Container(margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isEd ? cs.primary.withValues(alpha: 0.05) : cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isEd ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant.withValues(alpha: 0.3))),
              child: Row(children: [
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['panel_name'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  Text(r['panel_id'] ?? '', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
                ])),
                Expanded(flex: 2, child: isEd
                  ? TextField(controller: _rate[i], keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                      decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.all(6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))))
                  : Text('Rp ${fmt.format(base)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface))),
                Expanded(flex: 2, child: isEd
                  ? Row(children: [
                      Expanded(child: TextField(controller: _min[i], keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                        decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.all(6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), hintText: 'Min'))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('-', style: TextStyle(color: cs.onSurfaceVariant))),
                      Expanded(child: TextField(controller: _max[i], keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                        decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.all(6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), hintText: 'Max'))),
                    ])
                  : Text('${sMin}x - ${sMax}x', style: TextStyle(fontSize: 12, color: cs.onSurface))),
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Rp ${fmt.format(base * sMin)}', style: const TextStyle(fontSize: 11, color: Color(0xFF059669))),
                  Text('Rp ${fmt.format(base * sMax)}', style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                ])),
                SizedBox(width: 90, child: Center(child: Switch(value: active, activeColor: cs.primary, onChanged: (v) async {
                  final updated = Map<String, dynamic>.from(r);
                  updated['is_active'] = v;
                  await widget.onUpdate(updated);
                }))),
                SizedBox(width: 64, child: isEd
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      _saving
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                        : IconButton(icon: Icon(Icons.check_circle, size: 18, color: cs.primary), onPressed: () => _commit(i)),
                      IconButton(icon: Icon(Icons.cancel_outlined, size: 18, color: cs.error), onPressed: () => setState(() => _editing = null)),
                    ])
                  : IconButton(icon: Icon(Icons.edit_outlined, size: 16, color: cs.onSurfaceVariant), onPressed: () => _start(i))),
              ]));
          })),
    ]));
  }
}

// --- Tab 3: NLP Studio ---
class _NlpTab extends StatelessWidget {
  final ColorScheme cs;
  final Map<int, bool> toggles;
  final void Function(int, bool) onToggle;
  const _NlpTab({required this.cs, required this.toggles, required this.onToggle});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Customer Concierge NLP', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
    const SizedBox(height: 4),
    Text('WhatsApp bot intent management - Dashboard view', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    const SizedBox(height: 20),
    Expanded(child: ListView.builder(itemCount: _nlpIntents.length, itemBuilder: (_, i) {
      final intent = _nlpIntents[i];
      final active = toggles[i] ?? intent.active;
      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(intent.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text(intent.description, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${intent.phrases} phrases', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text('${intent.accuracy}% accuracy', style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 16),
          Switch(value: active, activeColor: cs.primary, onChanged: (v) => onToggle(i, v)),
        ]));
    })),
  ]));
}

// --- Tab 4: Commissions ---
class _CommissionTab extends StatelessWidget {
  final ColorScheme cs;
  const _CommissionTab({required this.cs});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Partner Commission & Settlement', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
    const SizedBox(height: 4),
    Text('Settlement ledger - Dashboard view', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    const SizedBox(height: 20),
    Expanded(child: ListView.builder(itemCount: _settlements.length, itemBuilder: (_, i) {
      final s = _settlements[i];
      final col = s.status == 'paid' ? const Color(0xFF059669) : s.status == 'disputed' ? const Color(0xFFDC2626) : s.status == 'processing' ? const Color(0xFF0ea5e9) : cs.onSurfaceVariant;
      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.partner, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            Text('${s.workshopId} - ${s.date}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(s.amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            Text('Commission: ${s.commission}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(width: 16),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(s.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: col))),
        ]));
    })),
  ]));
}

// --- Shared Widgets ---
class _Card extends StatelessWidget {
  final ColorScheme cs; final String title; final IconData icon; final List<Widget> children;
  const _Card({required this.cs, required this.title, required this.icon, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface))]),
      const Divider(height: 20),
      ...children,
    ]));
}

class _Flag extends StatelessWidget {
  final ColorScheme cs; final String label, sub; final bool value; final ValueChanged<bool> onChange;
  const _Flag({required this.cs, required this.label, required this.sub, required this.value, required this.onChange});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ])),
      Switch(value: value, activeColor: cs.primary, onChanged: onChange),
    ]));
}

class _Field extends StatelessWidget {
  final ColorScheme cs; final String label, hint;
  final TextEditingController ctrl; final int maxLines; final VoidCallback onChange;
  const _Field({required this.cs, required this.label, required this.hint,
    required this.ctrl, this.maxLines = 1, required this.onChange});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 110, child: Padding(padding: const EdgeInsets.only(top: 12),
      child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)))),
    Expanded(child: TextField(controller: ctrl, maxLines: maxLines, onChanged: (_) => onChange(),
      style: TextStyle(fontSize: 13, color: cs.onSurface),
      decoration: InputDecoration(hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.primary))))),
  ]);
}

// --- Tab 5: About Us CMS ---
class _AboutCmsTab extends StatefulWidget {
  final ColorScheme cs;
  final String Function(String, {String fb}) s;
  final Future<void> Function(String, String, {String cat}) onSave;
  const _AboutCmsTab({required this.cs, required this.s, required this.onSave});
  @override State<_AboutCmsTab> createState() => _AboutCmsTabState();
}
class _AboutCmsTabState extends State<_AboutCmsTab> {
  late TextEditingController _title, _tagline, _story, _mission, _vision;
  late TextEditingController _statPartners, _statRating, _statJobs;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _title        = TextEditingController(text: widget.s('about_title',   fb: ''));
    _tagline      = TextEditingController(text: widget.s('about_tagline', fb: ''));
    _story        = TextEditingController(text: widget.s('about_story',   fb: ''));
    _mission      = TextEditingController(text: widget.s('about_mission', fb: ''));
    _vision       = TextEditingController(text: widget.s('about_vision',  fb: ''));
    _statPartners = TextEditingController(text: widget.s('stat_partners', fb: '38+'));
    _statRating   = TextEditingController(text: widget.s('stat_rating',   fb: '4.9/5'));
    _statJobs     = TextEditingController(text: widget.s('stat_jobs',     fb: '12,000+'));
  }

  @override
  void dispose() {
    for (final c in [_title, _tagline, _story, _mission, _vision,
      _statPartners, _statRating, _statJobs]) c.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    await Future.wait([
      widget.onSave('about_title',   _title.text,        cat: 'about'),
      widget.onSave('about_tagline', _tagline.text,      cat: 'about'),
      widget.onSave('about_story',   _story.text,        cat: 'about'),
      widget.onSave('about_mission', _mission.text,      cat: 'about'),
      widget.onSave('about_vision',  _vision.text,       cat: 'about'),
      widget.onSave('stat_partners', _statPartners.text, cat: 'about'),
      widget.onSave('stat_rating',   _statRating.text,   cat: 'about'),
      widget.onSave('stat_jobs',     _statJobs.text,     cat: 'about'),
    ]);
    setState(() => _dirty = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('About page saved'), backgroundColor: Color(0xFF059669)));
  }

  void _mark() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return SingleChildScrollView(padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('About Us Page', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          if (_dirty) FilledButton.icon(onPressed: _saveAll, icon: const Icon(Icons.save_rounded, size: 16), label: const Text('Save Changes')),
        ]),
        const SizedBox(height: 4),
        Text('Manage revive.co.id/about', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        _Card(cs: cs, title: 'Hero Banner', icon: Icons.info_outlined, children: [
          _Field(cs: cs, label: 'Title', ctrl: _title, hint: 'Main heading for About page', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Tagline', ctrl: _tagline, hint: 'Short intro sentence', maxLines: 2, onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Stats Row', icon: Icons.bar_chart_rounded, children: [
          _Field(cs: cs, label: 'Partners',     ctrl: _statPartners, hint: '38+',     onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Rating',       ctrl: _statRating,   hint: '4.9/5',   onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Cars Fixed',   ctrl: _statJobs,     hint: '12,000+', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Content', icon: Icons.article_outlined, children: [
          _Field(cs: cs, label: 'Our Story', ctrl: _story,   hint: 'Company origin story...', maxLines: 5, onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Mission',   ctrl: _mission, hint: 'Mission statement...',     maxLines: 3, onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Vision',    ctrl: _vision,  hint: 'Vision statement...',      maxLines: 3, onChange: _mark),
        ]),
        const SizedBox(height: 80),
      ]));
  }
}

// --- Tab 6: Privacy Policy CMS ---
class _PrivacyCmsTab extends StatefulWidget {
  final ColorScheme cs;
  final String Function(String, {String fb}) s;
  final Future<void> Function(String, String, {String cat}) onSave;
  const _PrivacyCmsTab({required this.cs, required this.s, required this.onSave});
  @override State<_PrivacyCmsTab> createState() => _PrivacyCmsTabState();
}
class _PrivacyCmsTabState extends State<_PrivacyCmsTab> {
  late TextEditingController _pageTitle, _intro, _updated;
  final _secTitle = <TextEditingController>[];
  final _secBody  = <TextEditingController>[];
  static const _n = 8;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _pageTitle = TextEditingController(text: widget.s('privacy_page_title', fb: 'Kebijakan Privasi'));
    _intro     = TextEditingController(text: widget.s('privacy_intro',      fb: ''));
    _updated   = TextEditingController(text: widget.s('privacy_updated',    fb: 'September 2026'));
    for (int i = 0; i < _n; i++) {
      _secTitle.add(TextEditingController(text: widget.s('privacy_${i}_title', fb: '')));
      _secBody.add(TextEditingController(text: widget.s('privacy_${i}_body',   fb: '')));
    }
  }

  @override
  void dispose() {
    for (final c in [_pageTitle, _intro, _updated, ..._secTitle, ..._secBody]) c.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    final saves = <Future<void>>[
      widget.onSave('privacy_page_title', _pageTitle.text, cat: 'legal'),
      widget.onSave('privacy_intro',      _intro.text,     cat: 'legal'),
      widget.onSave('privacy_updated',    _updated.text,   cat: 'legal'),
    ];
    for (int i = 0; i < _n; i++) {
      saves.add(widget.onSave('privacy_${i}_title', _secTitle[i].text, cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_body',  _secBody[i].text,  cat: 'legal'));
    }
    await Future.wait(saves);
    setState(() => _dirty = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Privacy Policy saved'), backgroundColor: Color(0xFF059669)));
  }

  void _mark() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return SingleChildScrollView(padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Privacy Policy Page', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          if (_dirty) FilledButton.icon(onPressed: _saveAll, icon: const Icon(Icons.save_rounded, size: 16), label: const Text('Save Changes')),
        ]),
        const SizedBox(height: 4),
        Text('Manage revive.co.id/privacy', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        _Card(cs: cs, title: 'Page Header', icon: Icons.privacy_tip_outlined, children: [
          _Field(cs: cs, label: 'Page Title',   ctrl: _pageTitle, hint: 'Kebijakan Privasi', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Last Updated', ctrl: _updated,   hint: 'September 2026',   onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Intro Text',   ctrl: _intro,     hint: 'Opening paragraph...', maxLines: 3, onChange: _mark),
        ]),
        const SizedBox(height: 16),
        for (int i = 0; i < _n; i++) ...[
          _Card(cs: cs, title: 'Section ${i + 1}', icon: Icons.article_outlined, children: [
            _Field(cs: cs, label: 'Heading', ctrl: _secTitle[i], hint: 'e.g. 1. Data yang Kami Kumpulkan', onChange: _mark),
            const SizedBox(height: 12),
            _Field(cs: cs, label: 'Body',    ctrl: _secBody[i],  hint: 'Section content...',                maxLines: 4, onChange: _mark),
          ]),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 80),
      ]));
  }
}
