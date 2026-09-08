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
      case 2: return _NlpTab(cs: cs, toggles: _nlpToggles, onToggle: (i, v) => setState(() => _nlpToggles[i] = v));
      case 3: return _CommissionTab(cs: cs);
      case 4: return _AboutCmsTab(cs: cs, s: _s, onSave: _save);
      case 5: return _PrivacyCmsTab(cs: cs, s: _s, onSave: _save);
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
    const icons = [Icons.dashboard_customize_outlined, Icons.folder_special_outlined, Icons.smart_toy_outlined, Icons.payments_outlined, Icons.info_outlined, Icons.privacy_tip_outlined];
    const labels = ['Content Studio', 'Digital Assets', 'NLP Studio', 'Commissions', 'About Us', 'Privacy Policy'];

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
  // ── EN (primary) controllers ──────────────────────────────────────────────
  late TextEditingController _heroTitle, _heroSub, _heroCta;
  late TextEditingController _s1t, _s1d, _s2t, _s2d, _s3t, _s3d;
  late TextEditingController _cPhone, _cEmail, _cAddr;
  late TextEditingController _supTitle, _supSub, _supPhone, _supEmail, _supEmergency;
  late TextEditingController _ftTitle, _ftBody, _ftBadge;
  late TextEditingController _st1t, _st1d, _st2t, _st2d, _st3t, _st3d, _st4t, _st4d;
  late TextEditingController _b1v, _b1l, _b2v, _b2l, _b3v, _b3l;
  late TextEditingController _footer;
  late TextEditingController _abTitle, _abTagline, _abStory, _abMission, _abVision;
  late TextEditingController _stPartners, _stRating, _stJobs;
  late TextEditingController _v1t, _v1s, _v2t, _v2s, _v3t, _v3s, _v4t, _v4s;
  late TextEditingController _pcTitle, _pcSub;
  late TextEditingController _ppTitle, _ppUpdated, _ppIntro;
  final List<TextEditingController> _ppST = [], _ppSB = [];
  final _faqQ = <TextEditingController>[], _faqA = <TextEditingController>[];
  // ── ID (Indonesian) controllers ───────────────────────────────────────────
  late TextEditingController _heroTitleId, _heroSubId, _heroCtaId;
  late TextEditingController _s1tId, _s1dId, _s2tId, _s2dId, _s3tId, _s3dId;
  late TextEditingController _supTitleId, _supSubId;
  late TextEditingController _ftTitleId, _ftBodyId;
  late TextEditingController _st1tId, _st1dId, _st2tId, _st2dId, _st3tId, _st3dId, _st4tId, _st4dId;
  late TextEditingController _b1lId, _b2lId, _b3lId;
  late TextEditingController _abTitleId, _abTaglineId, _abStoryId, _abMissionId, _abVisionId;
  late TextEditingController _v1tId, _v1sId, _v2tId, _v2sId, _v3tId, _v3sId, _v4tId, _v4sId;
  late TextEditingController _pcTitleId, _pcSubId;
  late TextEditingController _ppTitleId, _ppIntroId;
  final List<TextEditingController> _ppSTId = [], _ppSBId = [];
  final _faqQId = <TextEditingController>[], _faqAId = <TextEditingController>[];
  int _faqCnt = 3;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // ── EN controllers ─────────────────────────────────────────────────────
    _heroTitle = TextEditingController(text: widget.s('hero_title', fb: 'Damage Repaired. Trust Restored.'));
    _heroSub   = TextEditingController(text: widget.s('hero_subtitle', fb: 'Premium car body repair - fast, transparent, guaranteed.'));
    _heroCta   = TextEditingController(text: widget.s('hero_cta', fb: 'Get Free Estimate'));
    _s1t = TextEditingController(text: widget.s('svc_1_title', fb: 'Damage Assessment'));
    _s1d = TextEditingController(text: widget.s('svc_1_desc',  fb: 'AI-powered photo scanning estimates repair cost instantly.'));
    _s2t = TextEditingController(text: widget.s('svc_2_title', fb: 'Workshop Dispatch'));
    _s2d = TextEditingController(text: widget.s('svc_2_desc',  fb: 'We assign the best partner workshop near you.'));
    _s3t = TextEditingController(text: widget.s('svc_3_title', fb: 'Quality Guarantee'));
    _s3d = TextEditingController(text: widget.s('svc_3_desc',  fb: '90-day workmanship warranty on every repair.'));
    _cPhone = TextEditingController(text: widget.s('contact_phone',   fb: '+62 811-1234-5678'));
    _cEmail = TextEditingController(text: widget.s('contact_email',   fb: 'hello@revive.co.id'));
    _cAddr  = TextEditingController(text: widget.s('contact_address', fb: 'Jakarta, Indonesia'));
    _supTitle     = TextEditingController(text: widget.s('support_page_title',    fb: 'FAQ & Support'));
    _supSub       = TextEditingController(text: widget.s('support_page_subtitle', fb: 'Find answers to common questions or reach out to our team.'));
    _supPhone     = TextEditingController(text: widget.s('support_phone',         fb: '+62 800-123-456'));
    _supEmail     = TextEditingController(text: widget.s('support_email',         fb: 'support@re-v.co.id'));
    _supEmergency = TextEditingController(text: widget.s('support_emergency',     fb: '+62 800-TOW-REVIVE'));
    _ftTitle = TextEditingController(text: widget.s('feature_title', fb: 'Jabodetabek Certified Network'));
    _ftBody  = TextEditingController(text: widget.s('feature_body',  fb: 'Over 38 OEM-compliant spray booths with digitized color-matching precision.'));
    _ftBadge = TextEditingController(text: widget.s('feature_badge', fb: 'SLA < 48 Hrs'));
    _st1t = TextEditingController(text: widget.s('step_1_title', fb: 'Snap Damage Photos'));
    _st1d = TextEditingController(text: widget.s('step_1_desc',  fb: 'Take 3 clear photos around your vehicle dents, scratches, or panel gaps.'));
    _st2t = TextEditingController(text: widget.s('step_2_title', fb: 'Instant AI Assessment'));
    _st2d = TextEditingController(text: widget.s('step_2_desc',  fb: 'Get sub-millimeter part analysis and fixed-price estimate.'));
    _st3t = TextEditingController(text: widget.s('step_3_title', fb: 'Select Hub & Bay'));
    _st3d = TextEditingController(text: widget.s('step_3_desc',  fb: 'Choose your closest certified workshop and lock a priority slot.'));
    _st4t = TextEditingController(text: widget.s('step_4_title', fb: 'Live Tracking to Handover'));
    _st4d = TextEditingController(text: widget.s('step_4_desc',  fb: 'Watch real-time telemetry until delivery back to your driveway.'));
    _b1v = TextEditingController(text: widget.s('badge_1_value', fb: '38+'));      _b1l = TextEditingController(text: widget.s('badge_1_label', fb: 'Partner Bengkel'));
    _b2v = TextEditingController(text: widget.s('badge_2_value', fb: '4.9/5'));    _b2l = TextEditingController(text: widget.s('badge_2_label', fb: 'Customer Rating'));
    _b3v = TextEditingController(text: widget.s('badge_3_value', fb: '24 Month')); _b3l = TextEditingController(text: widget.s('badge_3_label', fb: 'Paint Guarantee'));
    _footer    = TextEditingController(text: widget.s('footer_copy',       fb: '2026 re-V.co.id. Premium Automotive Body Repair, Powered by AI.'));
    _abTitle   = TextEditingController(text: widget.s('about_title',       fb: 'About Revive'));
    _abTagline = TextEditingController(text: widget.s('about_tagline',     fb: 'Leading the transformation of Indonesia automotive repair.'));
    _abStory   = TextEditingController(text: widget.s('about_story',       fb: 'Revive was born from real frustration...'));
    _abMission = TextEditingController(text: widget.s('about_mission',     fb: 'Making vehicle body repair in Indonesia fully transparent.'));
    _abVision  = TextEditingController(text: widget.s('about_vision',      fb: 'To become the #1 automotive repair platform in Southeast Asia.'));
    _stPartners = TextEditingController(text: widget.s('stat_partners', fb: '38+'));
    _stRating   = TextEditingController(text: widget.s('stat_rating',   fb: '4.9/5'));
    _stJobs     = TextEditingController(text: widget.s('stat_jobs',     fb: '12,000+'));
    _v1t = TextEditingController(text: widget.s('value_1_title', fb: 'Transparent')); _v1s = TextEditingController(text: widget.s('value_1_sub', fb: 'Real cost estimate, no hidden fees'));
    _v2t = TextEditingController(text: widget.s('value_2_title', fb: 'Fast'));         _v2s = TextEditingController(text: widget.s('value_2_sub', fb: 'Digital process from claim to vehicle pickup'));
    _v3t = TextEditingController(text: widget.s('value_3_title', fb: 'Trusted'));      _v3s = TextEditingController(text: widget.s('value_3_sub', fb: '90-day workmanship guarantee across all our partners'));
    _v4t = TextEditingController(text: widget.s('value_4_title', fb: 'Innovative'));   _v4s = TextEditingController(text: widget.s('value_4_sub', fb: 'AI damage detection and pricing leading the industry'));
    _pcTitle = TextEditingController(text: widget.s('partner_cta_title', fb: 'Join as a Workshop Partner'));
    _pcSub   = TextEditingController(text: widget.s('partner_cta_sub',   fb: 'Register your workshop and start receiving orders from Revive.'));
    _ppTitle   = TextEditingController(text: widget.s('privacy_page_title', fb: 'Privacy Policy'));
    _ppUpdated = TextEditingController(text: widget.s('privacy_updated',    fb: 'Last updated: September 2026'));
    _ppIntro   = TextEditingController(text: widget.s('privacy_intro',      fb: 'We are committed to protecting the privacy and security of your personal data.'));
    const ppDefaultsEn = [
      ('1. Data We Collect', 'We collect information you provide when registering (name, email, phone number), vehicle data (make, model, license plate), damage photos you upload, and anonymous app usage data to improve the service.'),
      ('2. Use of Data', 'Your data is used to process AI damage estimates, connect you with the nearest partner workshop, send repair status updates, process payments and insurance claims, and improve the accuracy of our AI model.'),
      ('3. Data Security', 'All data is stored on Supabase infrastructure with AES-256 encryption. We never sell your personal data to third parties. Data access is restricted only to the services you use.'),
      ('4. Sharing Data with Third Parties', 'Minimal necessary data is shared with the partner workshop you select for repair purposes, and with insurance companies if you file a claim. All partners are bound by data confidentiality agreements.'),
      ('5. User Rights', 'You have the right to access, correct, or delete your personal data at any time via the profile page. For account deletion requests, contact privacy@revive.co.id and we will process it within 30 business days.'),
      ('6. Cookies and Tracking', 'Our web app uses session cookies for authentication and theme preferences. No third-party tracking or advertising cookies are used on our platform.'),
      ('7. Policy Changes', 'This policy may be updated at any time. Material changes will be communicated via your registered email at least 14 days before taking effect.'),
      ('8. Contact', 'For privacy data enquiries, contact us at: privacy@revive.co.id or via the Support feature in our application.'),
    ];
    for (int i = 0; i < 8; i++) {
      _ppST.add(TextEditingController(text: widget.s('privacy_${i}_title', fb: ppDefaultsEn[i].$1)));
      _ppSB.add(TextEditingController(text: widget.s('privacy_${i}_body',  fb: ppDefaultsEn[i].$2)));
    }
    for (int i = 0; i < _faqCnt; i++) {
      _faqQ.add(TextEditingController(text: widget.s('faq_${i}_q')));
      _faqA.add(TextEditingController(text: widget.s('faq_${i}_a')));
    }
    // ── ID controllers ─────────────────────────────────────────────────────
    _heroTitleId = TextEditingController(text: widget.s('hero_title_id',    fb: 'Body Repair Jadi Mudah.'));
    _heroSubId   = TextEditingController(text: widget.s('hero_subtitle_id', fb: 'Estimasi perbaikan bodi instan & pelacakan real-time.'));
    _heroCtaId   = TextEditingController(text: widget.s('hero_cta_id',     fb: 'Dapatkan Estimasi AI Gratis'));
    _s1tId = TextEditingController(text: widget.s('svc_1_title_id', fb: 'Penilaian Kerusakan'));
    _s1dId = TextEditingController(text: widget.s('svc_1_desc_id',  fb: 'Pemindaian foto bertenaga AI memperkirakan biaya perbaikan secara instan.'));
    _s2tId = TextEditingController(text: widget.s('svc_2_title_id', fb: 'Penugasan Bengkel'));
    _s2dId = TextEditingController(text: widget.s('svc_2_desc_id',  fb: 'Kami menugaskan bengkel mitra terbaik di dekat Anda.'));
    _s3tId = TextEditingController(text: widget.s('svc_3_title_id', fb: 'Garansi Kualitas'));
    _s3dId = TextEditingController(text: widget.s('svc_3_desc_id',  fb: 'Garansi pengerjaan 90 hari untuk setiap perbaikan.'));
    _supTitleId = TextEditingController(text: widget.s('support_page_title_id',    fb: 'FAQ & Dukungan'));
    _supSubId   = TextEditingController(text: widget.s('support_page_subtitle_id', fb: 'Temukan jawaban atas pertanyaan umum atau hubungi tim kami.'));
    _ftTitleId = TextEditingController(text: widget.s('feature_title_id', fb: 'Jaringan Tersertifikasi Jabodetabek'));
    _ftBodyId  = TextEditingController(text: widget.s('feature_body_id',  fb: 'Lebih dari 38 spray booth OEM-compliant dengan presisi color-matching digital.'));
    _st1tId = TextEditingController(text: widget.s('step_1_title_id', fb: 'Foto Kerusakan'));
    _st1dId = TextEditingController(text: widget.s('step_1_desc_id',  fb: 'Ambil 3 foto jelas di sekitar penyok, goresan, atau celah panel kendaraan.'));
    _st2tId = TextEditingController(text: widget.s('step_2_title_id', fb: 'Penilaian AI Instan'));
    _st2dId = TextEditingController(text: widget.s('step_2_desc_id',  fb: 'Dapatkan analisis bagian sub-milimeter dan estimasi harga tetap.'));
    _st3tId = TextEditingController(text: widget.s('step_3_title_id', fb: 'Pilih Hub & Bay'));
    _st3dId = TextEditingController(text: widget.s('step_3_desc_id',  fb: 'Pilih bengkel tersertifikasi terdekat dan kunci reservasi slot prioritas.'));
    _st4tId = TextEditingController(text: widget.s('step_4_title_id', fb: 'Pelacakan Live Hingga Serah Terima'));
    _st4dId = TextEditingController(text: widget.s('step_4_desc_id',  fb: 'Pantau persiapan real-time, pengecatan booth, dan telemetri kontrol kualitas.'));
    _b1lId = TextEditingController(text: widget.s('badge_1_label_id', fb: 'Bengkel Mitra'));
    _b2lId = TextEditingController(text: widget.s('badge_2_label_id', fb: 'Rating Pelanggan'));
    _b3lId = TextEditingController(text: widget.s('badge_3_label_id', fb: 'Garansi Cat'));
    _abTitleId   = TextEditingController(text: widget.s('about_title_id',   fb: 'Tentang Revive'));
    _abTaglineId = TextEditingController(text: widget.s('about_tagline_id', fb: 'Memimpin transformasi industri perbaikan otomotif Indonesia.'));
    _abStoryId   = TextEditingController(text: widget.s('about_story_id',   fb: 'Revive lahir dari frustrasi nyata...'));
    _abMissionId = TextEditingController(text: widget.s('about_mission_id', fb: 'Menjadikan perbaikan bodi kendaraan di Indonesia sepenuhnya transparan.'));
    _abVisionId  = TextEditingController(text: widget.s('about_vision_id',  fb: 'Menjadi platform perbaikan otomotif #1 di Asia Tenggara.'));
    _v1tId = TextEditingController(text: widget.s('value_1_title_id', fb: 'Transparan')); _v1sId = TextEditingController(text: widget.s('value_1_sub_id', fb: 'Estimasi biaya real, tidak ada biaya tersembunyi'));
    _v2tId = TextEditingController(text: widget.s('value_2_title_id', fb: 'Cepat'));      _v2sId = TextEditingController(text: widget.s('value_2_sub_id', fb: 'Proses digital dari klaim hingga pengambilan kendaraan'));
    _v3tId = TextEditingController(text: widget.s('value_3_title_id', fb: 'Terpercaya')); _v3sId = TextEditingController(text: widget.s('value_3_sub_id', fb: '90 hari garansi pengerjaan di semua mitra kami'));
    _v4tId = TextEditingController(text: widget.s('value_4_title_id', fb: 'Inovatif'));   _v4sId = TextEditingController(text: widget.s('value_4_sub_id', fb: 'AI damage detection dan pricing terdepan di industri'));
    _pcTitleId = TextEditingController(text: widget.s('partner_cta_title_id', fb: 'Bergabung sebagai Partner Bengkel'));
    _pcSubId   = TextEditingController(text: widget.s('partner_cta_sub_id',   fb: 'Daftarkan bengkel Anda dan mulai terima order dari Revive.'));
    _ppTitleId = TextEditingController(text: widget.s('privacy_page_title_id', fb: 'Kebijakan Privasi'));
    _ppIntroId = TextEditingController(text: widget.s('privacy_intro_id',      fb: 'Kami berkomitmen untuk melindungi privasi dan keamanan data pribadi Anda.'));
    for (int i = 0; i < 8; i++) {
      _ppSTId.add(TextEditingController(text: widget.s('privacy_${i}_title_id', fb: '')));
      _ppSBId.add(TextEditingController(text: widget.s('privacy_${i}_body_id',  fb: '')));
    }
    for (int i = 0; i < _faqCnt; i++) {
      _faqQId.add(TextEditingController(text: widget.s('faq_${i}_q_id')));
      _faqAId.add(TextEditingController(text: widget.s('faq_${i}_a_id')));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _heroTitle, _heroSub, _heroCta,
      _heroTitleId, _heroSubId, _heroCtaId,
      _s1t, _s1d, _s2t, _s2d, _s3t, _s3d,
      _s1tId, _s1dId, _s2tId, _s2dId, _s3tId, _s3dId,
      _cPhone, _cEmail, _cAddr,
      _supTitle, _supSub, _supPhone, _supEmail, _supEmergency,
      _supTitleId, _supSubId,
      _ftTitle, _ftBody, _ftBadge,
      _ftTitleId, _ftBodyId,
      _st1t, _st1d, _st2t, _st2d, _st3t, _st3d, _st4t, _st4d,
      _st1tId, _st1dId, _st2tId, _st2dId, _st3tId, _st3dId, _st4tId, _st4dId,
      _b1v, _b1l, _b2v, _b2l, _b3v, _b3l,
      _b1lId, _b2lId, _b3lId,
      _footer,
      _abTitle, _abTagline, _abStory, _abMission, _abVision,
      _abTitleId, _abTaglineId, _abStoryId, _abMissionId, _abVisionId,
      _stPartners, _stRating, _stJobs,
      _v1t, _v1s, _v2t, _v2s, _v3t, _v3s, _v4t, _v4s,
      _v1tId, _v1sId, _v2tId, _v2sId, _v3tId, _v3sId, _v4tId, _v4sId,
      _pcTitle, _pcSub, _pcTitleId, _pcSubId,
      _ppTitle, _ppUpdated, _ppIntro, _ppTitleId, _ppIntroId,
      ..._ppST, ..._ppSB, ..._ppSTId, ..._ppSBId,
      ..._faqQ, ..._faqA, ..._faqQId, ..._faqAId,
    ]) c.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    final saves = <Future<void>>[
      // ── EN ─────────────────────────────────────────────────────────────────
      widget.onSave('hero_title',    _heroTitle.text, cat: 'hero'),
      widget.onSave('hero_subtitle', _heroSub.text,   cat: 'hero'),
      widget.onSave('hero_cta',      _heroCta.text,   cat: 'hero'),
      widget.onSave('svc_1_title',   _s1t.text, cat: 'services'),
      widget.onSave('svc_1_desc',    _s1d.text, cat: 'services'),
      widget.onSave('svc_2_title',   _s2t.text, cat: 'services'),
      widget.onSave('svc_2_desc',    _s2d.text, cat: 'services'),
      widget.onSave('svc_3_title',   _s3t.text, cat: 'services'),
      widget.onSave('svc_3_desc',    _s3d.text, cat: 'services'),
      widget.onSave('contact_phone',         _cPhone.text,       cat: 'contact'),
      widget.onSave('contact_email',         _cEmail.text,       cat: 'contact'),
      widget.onSave('contact_address',       _cAddr.text,        cat: 'contact'),
      widget.onSave('support_page_title',    _supTitle.text,     cat: 'support'),
      widget.onSave('support_page_subtitle', _supSub.text,       cat: 'support'),
      widget.onSave('support_phone',         _supPhone.text,     cat: 'support'),
      widget.onSave('support_email',         _supEmail.text,     cat: 'support'),
      widget.onSave('support_emergency',     _supEmergency.text, cat: 'support'),
      widget.onSave('feature_title',  _ftTitle.text, cat: 'landing'),
      widget.onSave('feature_body',   _ftBody.text,  cat: 'landing'),
      widget.onSave('feature_badge',  _ftBadge.text, cat: 'landing'),
      widget.onSave('step_1_title',   _st1t.text,    cat: 'landing'),
      widget.onSave('step_1_desc',    _st1d.text,    cat: 'landing'),
      widget.onSave('step_2_title',   _st2t.text,    cat: 'landing'),
      widget.onSave('step_2_desc',    _st2d.text,    cat: 'landing'),
      widget.onSave('step_3_title',   _st3t.text,    cat: 'landing'),
      widget.onSave('step_3_desc',    _st3d.text,    cat: 'landing'),
      widget.onSave('step_4_title',   _st4t.text,    cat: 'landing'),
      widget.onSave('step_4_desc',    _st4d.text,    cat: 'landing'),
      widget.onSave('badge_1_value',  _b1v.text, cat: 'landing'),
      widget.onSave('badge_1_label',  _b1l.text, cat: 'landing'),
      widget.onSave('badge_2_value',  _b2v.text, cat: 'landing'),
      widget.onSave('badge_2_label',  _b2l.text, cat: 'landing'),
      widget.onSave('badge_3_value',  _b3v.text, cat: 'landing'),
      widget.onSave('badge_3_label',  _b3l.text, cat: 'landing'),
      widget.onSave('footer_copy',    _footer.text,    cat: 'landing'),
      widget.onSave('about_title',    _abTitle.text,   cat: 'about'),
      widget.onSave('about_tagline',  _abTagline.text, cat: 'about'),
      widget.onSave('about_story',    _abStory.text,   cat: 'about'),
      widget.onSave('about_mission',  _abMission.text, cat: 'about'),
      widget.onSave('about_vision',   _abVision.text,  cat: 'about'),
      widget.onSave('stat_partners',  _stPartners.text, cat: 'about'),
      widget.onSave('stat_rating',    _stRating.text,   cat: 'about'),
      widget.onSave('stat_jobs',      _stJobs.text,     cat: 'about'),
      widget.onSave('value_1_title',  _v1t.text, cat: 'about'), widget.onSave('value_1_sub', _v1s.text, cat: 'about'),
      widget.onSave('value_2_title',  _v2t.text, cat: 'about'), widget.onSave('value_2_sub', _v2s.text, cat: 'about'),
      widget.onSave('value_3_title',  _v3t.text, cat: 'about'), widget.onSave('value_3_sub', _v3s.text, cat: 'about'),
      widget.onSave('value_4_title',  _v4t.text, cat: 'about'), widget.onSave('value_4_sub', _v4s.text, cat: 'about'),
      widget.onSave('partner_cta_title', _pcTitle.text, cat: 'about'),
      widget.onSave('partner_cta_sub',   _pcSub.text,   cat: 'about'),
      widget.onSave('privacy_page_title', _ppTitle.text,   cat: 'legal'),
      widget.onSave('privacy_updated',    _ppUpdated.text, cat: 'legal'),
      widget.onSave('privacy_intro',      _ppIntro.text,   cat: 'legal'),
      // ── ID ─────────────────────────────────────────────────────────────────
      widget.onSave('hero_title_id',    _heroTitleId.text, cat: 'hero'),
      widget.onSave('hero_subtitle_id', _heroSubId.text,   cat: 'hero'),
      widget.onSave('hero_cta_id',      _heroCtaId.text,   cat: 'hero'),
      widget.onSave('svc_1_title_id',   _s1tId.text, cat: 'services'),
      widget.onSave('svc_1_desc_id',    _s1dId.text, cat: 'services'),
      widget.onSave('svc_2_title_id',   _s2tId.text, cat: 'services'),
      widget.onSave('svc_2_desc_id',    _s2dId.text, cat: 'services'),
      widget.onSave('svc_3_title_id',   _s3tId.text, cat: 'services'),
      widget.onSave('svc_3_desc_id',    _s3dId.text, cat: 'services'),
      widget.onSave('support_page_title_id',    _supTitleId.text, cat: 'support'),
      widget.onSave('support_page_subtitle_id', _supSubId.text,   cat: 'support'),
      widget.onSave('feature_title_id',  _ftTitleId.text, cat: 'landing'),
      widget.onSave('feature_body_id',   _ftBodyId.text,  cat: 'landing'),
      widget.onSave('step_1_title_id',   _st1tId.text,    cat: 'landing'),
      widget.onSave('step_1_desc_id',    _st1dId.text,    cat: 'landing'),
      widget.onSave('step_2_title_id',   _st2tId.text,    cat: 'landing'),
      widget.onSave('step_2_desc_id',    _st2dId.text,    cat: 'landing'),
      widget.onSave('step_3_title_id',   _st3tId.text,    cat: 'landing'),
      widget.onSave('step_3_desc_id',    _st3dId.text,    cat: 'landing'),
      widget.onSave('step_4_title_id',   _st4tId.text,    cat: 'landing'),
      widget.onSave('step_4_desc_id',    _st4dId.text,    cat: 'landing'),
      widget.onSave('badge_1_label_id',  _b1lId.text, cat: 'landing'),
      widget.onSave('badge_2_label_id',  _b2lId.text, cat: 'landing'),
      widget.onSave('badge_3_label_id',  _b3lId.text, cat: 'landing'),
      widget.onSave('about_title_id',    _abTitleId.text,   cat: 'about'),
      widget.onSave('about_tagline_id',  _abTaglineId.text, cat: 'about'),
      widget.onSave('about_story_id',    _abStoryId.text,   cat: 'about'),
      widget.onSave('about_mission_id',  _abMissionId.text, cat: 'about'),
      widget.onSave('about_vision_id',   _abVisionId.text,  cat: 'about'),
      widget.onSave('value_1_title_id',  _v1tId.text, cat: 'about'), widget.onSave('value_1_sub_id', _v1sId.text, cat: 'about'),
      widget.onSave('value_2_title_id',  _v2tId.text, cat: 'about'), widget.onSave('value_2_sub_id', _v2sId.text, cat: 'about'),
      widget.onSave('value_3_title_id',  _v3tId.text, cat: 'about'), widget.onSave('value_3_sub_id', _v3sId.text, cat: 'about'),
      widget.onSave('value_4_title_id',  _v4tId.text, cat: 'about'), widget.onSave('value_4_sub_id', _v4sId.text, cat: 'about'),
      widget.onSave('partner_cta_title_id', _pcTitleId.text, cat: 'about'),
      widget.onSave('partner_cta_sub_id',   _pcSubId.text,   cat: 'about'),
      widget.onSave('privacy_page_title_id', _ppTitleId.text, cat: 'legal'),
      widget.onSave('privacy_intro_id',      _ppIntroId.text, cat: 'legal'),
    ];
    for (int i = 0; i < 8; i++) {
      saves.add(widget.onSave('privacy_${i}_title',    _ppST[i].text,   cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_body',     _ppSB[i].text,   cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_title_id', _ppSTId[i].text, cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_body_id',  _ppSBId[i].text, cat: 'legal'));
    }
    for (int i = 0; i < _faqCnt; i++) {
      saves.add(widget.onSave('faq_${i}_q',    _faqQ[i].text,   cat: 'faq'));
      saves.add(widget.onSave('faq_${i}_a',    _faqA[i].text,   cat: 'faq'));
      saves.add(widget.onSave('faq_${i}_q_id', _faqQId[i].text, cat: 'faq'));
      saves.add(widget.onSave('faq_${i}_a_id', _faqAId[i].text, cat: 'faq'));
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
          _BilingualField(cs: cs, label: 'Title', ctrlEn: _heroTitle, ctrlId: _heroTitleId, hintEn: 'Main headline (EN)', hintId: 'Judul utama (ID)', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Subtitle', ctrlEn: _heroSub, ctrlId: _heroSubId, hintEn: 'Hero subtext (EN)', hintId: 'Subteks hero (ID)', maxLines: 2, onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'CTA Button', ctrlEn: _heroCta, ctrlId: _heroCtaId, hintEn: 'Button text (EN)', hintId: 'Teks tombol (ID)', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Service Cards', icon: Icons.build_circle_outlined, children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            Text('Service ${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Title', ctrlEn: [_s1t, _s2t, _s3t][i], ctrlId: [_s1tId, _s2tId, _s3tId][i], hintEn: 'Service name (EN)', hintId: 'Nama layanan (ID)', onChange: _mark),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Description', ctrlEn: [_s1d, _s2d, _s3d][i], ctrlId: [_s1dId, _s2dId, _s3dId][i], hintEn: 'Service description (EN)', hintId: 'Deskripsi layanan (ID)', maxLines: 2, onChange: _mark),
          ],
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'FAQ & Support Page', icon: Icons.support_agent_outlined, children: [
          _BilingualField(cs: cs, label: 'Page Title',    ctrlEn: _supTitle, ctrlId: _supTitleId, hintEn: 'FAQ & Support', hintId: 'FAQ & Dukungan', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Page Subtitle', ctrlEn: _supSub,   ctrlId: _supSubId,   hintEn: 'Find answers...', hintId: 'Temukan jawaban...', maxLines: 2, onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Phone',     ctrl: _supPhone,     hint: '+62 800-xxx-xxx',     onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Email',     ctrl: _supEmail,     hint: 'support@re-v.co.id',  onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Emergency', ctrl: _supEmergency, hint: '+62 800-TOW-REVIVE',  onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'FAQ Items', icon: Icons.quiz_outlined, children: [
          for (int i = 0; i < _faqCnt; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Text('FAQ ${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Question', ctrlEn: _faqQ[i], ctrlId: _faqQId[i], hintEn: 'e.g. How long does repair take?', hintId: 'e.g. Berapa lama perbaikan?', onChange: _mark),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Answer', ctrlEn: _faqA[i], ctrlId: _faqAId[i], hintEn: 'Answer text (EN)', hintId: 'Teks jawaban (ID)', maxLines: 3, onChange: _mark),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () { setState(() {
              _faqQ.add(TextEditingController()); _faqA.add(TextEditingController());
              _faqQId.add(TextEditingController()); _faqAId.add(TextEditingController());
              _faqCnt++; _dirty = true;
            }); },
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
        const SizedBox(height: 16),
        // ── Landing: Feature Highlight ────────────────────────────────────────
        _Card(cs: cs, title: 'Feature Highlight Card', icon: Icons.auto_awesome_outlined, children: [
          _BilingualField(cs: cs, label: 'Title',       ctrlEn: _ftTitle, ctrlId: _ftTitleId, hintEn: 'e.g. Jabodetabek Certified Network', hintId: 'e.g. Jaringan Tersertifikasi Jabodetabek', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Body Copy',   ctrlEn: _ftBody,  ctrlId: _ftBodyId,  hintEn: 'Description text (EN)', hintId: 'Teks deskripsi (ID)', maxLines: 3, onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Badge Label', ctrl: _ftBadge, hint: 'e.g. SLA < 48 Hrs', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        // ── Landing: How It Works ────────────────────────────────────────────
        _Card(cs: cs, title: 'How It Works Steps', icon: Icons.linear_scale_rounded, children: [
          for (final step in [
            ('Step 1', _st1t, _st1d, _st1tId, _st1dId),
            ('Step 2', _st2t, _st2d, _st2tId, _st2dId),
            ('Step 3', _st3t, _st3d, _st3tId, _st3dId),
            ('Step 4', _st4t, _st4d, _st4tId, _st4dId),
          ]) ...[
            if (step.$1 != 'Step 1') const SizedBox(height: 16),
            Text(step.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Title',       ctrlEn: step.$2, ctrlId: step.$4, hintEn: 'Step title (EN)',       hintId: 'Judul langkah (ID)',       onChange: _mark),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Description', ctrlEn: step.$3, ctrlId: step.$5, hintEn: 'Step description (EN)', hintId: 'Deskripsi langkah (ID)', maxLines: 2, onChange: _mark),
          ],
        ]),
        const SizedBox(height: 16),
        // ── Landing: Trust Badges ────────────────────────────────────────────
        _Card(cs: cs, title: 'Trust Badges', icon: Icons.verified_outlined, children: [
          for (final badge in [
            ('Badge 1', _b1v, _b1l, _b1lId),
            ('Badge 2', _b2v, _b2l, _b2lId),
            ('Badge 3', _b3v, _b3l, _b3lId),
          ]) ...[
            if (badge.$1 != 'Badge 1') const SizedBox(height: 12),
            Text(badge.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _Field(cs: cs, label: 'Value', ctrl: badge.$2, hint: 'e.g. 38+', onChange: _mark),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Label', ctrlEn: badge.$3, ctrlId: badge.$4, hintEn: 'e.g. Partner Bengkel (EN)', hintId: 'e.g. Bengkel Mitra (ID)', onChange: _mark),
          ],
        ]),
        const SizedBox(height: 16),
        // ── Footer ────────────────────────────────────────────────────────────
        _Card(cs: cs, title: 'Footer', icon: Icons.horizontal_rule_rounded, children: [
          _Field(cs: cs, label: 'Copyright Line', ctrl: _footer, hint: '2026 re-V.co.id...', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        // ── About Us page ─────────────────────────────────────────────────────
        _Card(cs: cs, title: 'About Us Page', icon: Icons.info_outline_rounded, children: [
          _BilingualField(cs: cs, label: 'Page Title', ctrlEn: _abTitle,   ctrlId: _abTitleId,   hintEn: 'About Revive',   hintId: 'Tentang Revive', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Tagline',    ctrlEn: _abTagline, ctrlId: _abTaglineId, hintEn: 'Short tagline (EN)', hintId: 'Tagline singkat (ID)', maxLines: 2, onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Our Story',  ctrlEn: _abStory,   ctrlId: _abStoryId,   hintEn: 'Company story (EN)', hintId: 'Cerita perusahaan (ID)', maxLines: 5, onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Mission',    ctrlEn: _abMission, ctrlId: _abMissionId, hintEn: 'Mission statement (EN)', hintId: 'Pernyataan misi (ID)', maxLines: 3, onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Vision',     ctrlEn: _abVision,  ctrlId: _abVisionId,  hintEn: 'Vision statement (EN)', hintId: 'Pernyataan visi (ID)', maxLines: 3, onChange: _mark),
          const SizedBox(height: 14),
          Text('Statistics Strip', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Field(cs: cs, label: 'Partners',  ctrl: _stPartners, hint: '38+',     onChange: _mark)),
            const SizedBox(width: 8),
            Expanded(child: _Field(cs: cs, label: 'Rating',    ctrl: _stRating,   hint: '4.9/5',  onChange: _mark)),
            const SizedBox(width: 8),
            Expanded(child: _Field(cs: cs, label: 'Cars Fixed', ctrl: _stJobs,    hint: '12,000+', onChange: _mark)),
          ]),
        ]),
        const SizedBox(height: 16),
        // ── Company Values ────────────────────────────────────────────────────
        _Card(cs: cs, title: 'Company Values', icon: Icons.handshake_outlined, children: [
          for (final v in [
            ('Value 1', _v1t, _v1s, _v1tId, _v1sId),
            ('Value 2', _v2t, _v2s, _v2tId, _v2sId),
            ('Value 3', _v3t, _v3s, _v3tId, _v3sId),
            ('Value 4', _v4t, _v4s, _v4tId, _v4sId),
          ]) ...[
            if (v.$1 != 'Value 1') const SizedBox(height: 16),
            Text(v.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Title',    ctrlEn: v.$2, ctrlId: v.$4, hintEn: 'e.g. Transparent (EN)', hintId: 'e.g. Transparan (ID)', onChange: _mark),
            const SizedBox(height: 8),
            _BilingualField(cs: cs, label: 'Subtitle', ctrlEn: v.$3, ctrlId: v.$5, hintEn: 'Short description (EN)', hintId: 'Deskripsi singkat (ID)', onChange: _mark),
          ],
        ]),
        const SizedBox(height: 16),
        // ── Partner CTA ───────────────────────────────────────────────────────
        _Card(cs: cs, title: 'Partner CTA Banner', icon: Icons.store_outlined, children: [
          _BilingualField(cs: cs, label: 'Title',    ctrlEn: _pcTitle, ctrlId: _pcTitleId, hintEn: 'Join as a Workshop Partner', hintId: 'Bergabung sebagai Partner Bengkel', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Subtitle', ctrlEn: _pcSub,   ctrlId: _pcSubId,   hintEn: 'Register your workshop...', hintId: 'Daftarkan bengkel Anda...', maxLines: 2, onChange: _mark),
        ]),
        const SizedBox(height: 16),
        // ── Privacy Policy page ───────────────────────────────────────────────
        _Card(cs: cs, title: 'Privacy Policy Page', icon: Icons.privacy_tip_outlined, children: [
          _BilingualField(cs: cs, label: 'Page Title',   ctrlEn: _ppTitle,   ctrlId: _ppTitleId, hintEn: 'Privacy Policy', hintId: 'Kebijakan Privasi', onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs,           label: 'Last Updated', ctrl: _ppUpdated,               hint: 'Last updated: September 2026', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Introduction', ctrlEn: _ppIntro,   ctrlId: _ppIntroId, hintEn: 'Intro paragraph (EN)...', hintId: 'Paragraf pembuka (ID)...', maxLines: 4, onChange: _mark),
          const SizedBox(height: 14),
          Text('Sections', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
          for (int i = 0; i < 8; i++) ...[
            const SizedBox(height: 12),
            Text('Section ${i + 1}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            _BilingualField(cs: cs, label: 'Title', ctrlEn: _ppST[i],   ctrlId: _ppSTId[i], hintEn: 'Section heading (EN)', hintId: 'Judul bagian (ID)', onChange: _mark),
            const SizedBox(height: 6),
            _BilingualField(cs: cs, label: 'Body',  ctrlEn: _ppSB[i],   ctrlId: _ppSBId[i], hintEn: 'Section content (EN)', hintId: 'Konten bagian (ID)', maxLines: 4, onChange: _mark),
          ],
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

/// Shows two stacked text fields for a bilingual CMS key.
/// The EN controller maps to [key] and the ID controller maps to [key]_id.
class _BilingualField extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final TextEditingController ctrlEn;
  final TextEditingController ctrlId;
  final String hintEn;
  final String hintId;
  final int maxLines;
  final VoidCallback onChange;

  const _BilingualField({
    required this.cs,
    required this.label,
    required this.ctrlEn,
    required this.ctrlId,
    required this.hintEn,
    required this.hintId,
    this.maxLines = 1,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)))),
      Expanded(child: Column(children: [
        // English field
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4)),
            child: const Text('🇬🇧 EN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)))),
          const Spacer(),
        ]),
        const SizedBox(height: 4),
        TextField(controller: ctrlEn, maxLines: maxLines, onChanged: (_) => onChange(),
          style: TextStyle(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hintEn,
            hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: const Color(0xFF1565C0).withValues(alpha: 0.4))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1565C0))))),
        const SizedBox(height: 8),
        // Indonesian field
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4)),
            child: const Text('🇮🇩 ID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)))),
          const Spacer(),
        ]),
        const SizedBox(height: 4),
        TextField(controller: ctrlId, maxLines: maxLines, onChanged: (_) => onChange(),
          style: TextStyle(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hintId,
            hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: const Color(0xFFDC2626).withValues(alpha: 0.4))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDC2626))))),
      ])),
    ]);
  }
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
  late TextEditingController _titleEn, _titleId;
  late TextEditingController _taglineEn, _taglineId;
  late TextEditingController _storyEn, _storyId;
  late TextEditingController _missionEn, _missionId;
  late TextEditingController _visionEn, _visionId;
  late TextEditingController _statPartners, _statRating, _statJobs;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _titleEn      = TextEditingController(text: widget.s('about_title',       fb: 'About Revive'));
    _titleId      = TextEditingController(text: widget.s('about_title_id',    fb: 'Tentang Revive'));
    _taglineEn    = TextEditingController(text: widget.s('about_tagline',     fb: "Leading the transformation of Indonesia's automotive repair industry with AI technology and a trusted workshop network."));
    _taglineId    = TextEditingController(text: widget.s('about_tagline_id',  fb: 'Memimpin transformasi industri perbaikan otomotif Indonesia dengan teknologi AI dan jaringan bengkel terpercaya.'));
    _storyEn      = TextEditingController(text: widget.s('about_story',       fb: 'Revive was born from a real frustration: complicated insurance claim processes, opaque cost estimates, and the difficulty of finding a trustworthy workshop. We built an end-to-end solution combining AI, a verified partner network, and real-time dashboards to ensure every vehicle owner gets the best service at a fair price.'));
    _storyId      = TextEditingController(text: widget.s('about_story_id',    fb: 'Revive lahir dari frustrasi nyata: proses klaim asuransi yang rumit, estimasi biaya yang tidak transparan, dan sulitnya menemukan bengkel terpercaya. Kami membangun solusi end-to-end yang menggabungkan AI, jaringan mitra terverifikasi, dan dashboard real-time untuk memastikan setiap pemilik kendaraan mendapat layanan terbaik dengan harga yang jujur.'));
    _missionEn    = TextEditingController(text: widget.s('about_mission',     fb: 'To make vehicle body repair in Indonesia fully transparent, fast, and accessible to everyone — from insurance claims to work guarantees.'));
    _missionId    = TextEditingController(text: widget.s('about_mission_id',  fb: 'Menjadikan perbaikan bodi kendaraan di Indonesia sepenuhnya transparan, cepat, dan dapat diakses oleh semua orang — dari proses klaim asuransi hingga garansi hasil kerja.'));
    _visionEn     = TextEditingController(text: widget.s('about_vision',      fb: 'To become the #1 automotive repair platform in Southeast Asia with leading AI technology and the most trusted partner workshop ecosystem.'));
    _visionId     = TextEditingController(text: widget.s('about_vision_id',   fb: 'Menjadi platform perbaikan otomotif #1 di Asia Tenggara dengan teknologi AI terdepan dan ekosistem bengkel mitra yang paling dipercaya.'));
    _statPartners = TextEditingController(text: widget.s('stat_partners',     fb: '38+'));
    _statRating   = TextEditingController(text: widget.s('stat_rating',       fb: '4.9/5'));
    _statJobs     = TextEditingController(text: widget.s('stat_jobs',         fb: '12,000+'));
  }

  @override
  void dispose() {
    for (final c in [_titleEn, _titleId, _taglineEn, _taglineId, _storyEn, _storyId,
      _missionEn, _missionId, _visionEn, _visionId, _statPartners, _statRating, _statJobs]) c.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    await Future.wait([
      widget.onSave('about_title',      _titleEn.text,      cat: 'about'),
      widget.onSave('about_title_id',   _titleId.text,      cat: 'about'),
      widget.onSave('about_tagline',    _taglineEn.text,    cat: 'about'),
      widget.onSave('about_tagline_id', _taglineId.text,    cat: 'about'),
      widget.onSave('about_story',      _storyEn.text,      cat: 'about'),
      widget.onSave('about_story_id',   _storyId.text,      cat: 'about'),
      widget.onSave('about_mission',    _missionEn.text,    cat: 'about'),
      widget.onSave('about_mission_id', _missionId.text,    cat: 'about'),
      widget.onSave('about_vision',     _visionEn.text,     cat: 'about'),
      widget.onSave('about_vision_id',  _visionId.text,     cat: 'about'),
      widget.onSave('stat_partners',    _statPartners.text, cat: 'about'),
      widget.onSave('stat_rating',      _statRating.text,   cat: 'about'),
      widget.onSave('stat_jobs',        _statJobs.text,     cat: 'about'),
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
        Text('Manage revive.co.id/about  ·  EN + ID bilingual', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        _Card(cs: cs, title: 'Hero Banner', icon: Icons.info_outlined, children: [
          _BilingualField(cs: cs, label: 'Title',   ctrlEn: _titleEn,   ctrlId: _titleId,   hintEn: 'About Revive',   hintId: 'Tentang Revive', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Tagline', ctrlEn: _taglineEn, ctrlId: _taglineId, hintEn: 'Leading transformation...', hintId: 'Memimpin transformasi...', maxLines: 2, onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Stats Row', icon: Icons.bar_chart_rounded, children: [
          _Field(cs: cs, label: 'Partners (shared)',    ctrl: _statPartners, hint: '38+',     onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Rating (shared)',      ctrl: _statRating,   hint: '4.9/5',   onChange: _mark),
          const SizedBox(height: 12),
          _Field(cs: cs, label: 'Cars Fixed (shared)',  ctrl: _statJobs,     hint: '12,000+', onChange: _mark),
        ]),
        const SizedBox(height: 16),
        _Card(cs: cs, title: 'Content', icon: Icons.article_outlined, children: [
          _BilingualField(cs: cs, label: 'Our Story', ctrlEn: _storyEn,   ctrlId: _storyId,   hintEn: 'Company origin story (EN)...', hintId: 'Cerita perusahaan (ID)...', maxLines: 5, onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Mission',   ctrlEn: _missionEn, ctrlId: _missionId, hintEn: 'Mission statement (EN)...',     hintId: 'Pernyataan misi (ID)...',   maxLines: 3, onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Vision',    ctrlEn: _visionEn,  ctrlId: _visionId,  hintEn: 'Vision statement (EN)...',      hintId: 'Pernyataan visi (ID)...',   maxLines: 3, onChange: _mark),
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
  late TextEditingController _pageTitleEn, _pageTitleId;
  late TextEditingController _introEn, _introId;
  late TextEditingController _updatedEn, _updatedId;
  final _secTitleEn = <TextEditingController>[];
  final _secTitleId = <TextEditingController>[];
  final _secBodyEn  = <TextEditingController>[];
  final _secBodyId  = <TextEditingController>[];
  static const _n = 8;
  bool _dirty = false;

  static const _enTitles = ['1. Data We Collect','2. Use of Data','3. Data Security','4. Sharing Data with Third Parties','5. User Rights','6. Cookies and Tracking','7. Policy Changes','8. Contact'];
  static const _enBodies = [
    'We collect information you provide when registering (name, email, phone number), vehicle data (make, model, license plate), damage photos you upload, and anonymous app usage data to improve the service.',
    'Your data is used to process AI damage estimates, connect you with the nearest partner workshop, send repair status updates, process payments and insurance claims, and improve the accuracy of our AI model.',
    'All data is stored on Supabase infrastructure with AES-256 encryption. We never sell your personal data to third parties. Data access is restricted only to the services you use.',
    'Minimal necessary data is shared with the partner workshop you select for repair purposes, and with insurance companies if you file a claim. All partners are bound by data confidentiality agreements.',
    'You have the right to access, correct, or delete your personal data at any time via the profile page. For account deletion requests, contact privacy@revive.co.id and we will process it within 30 business days.',
    'Our web app uses session cookies for authentication and theme preferences. No third-party tracking or advertising cookies are used on our platform.',
    'This policy may be updated at any time. Material changes will be communicated via your registered email at least 14 days before taking effect.',
    'For privacy data enquiries, contact us at: privacy@revive.co.id or via the Support feature in our application.',
  ];
  static const _idTitles = ['1. Data yang Kami Kumpulkan','2. Penggunaan Data','3. Keamanan Data','4. Berbagi Data dengan Pihak Ketiga','5. Hak Pengguna','6. Cookie dan Pelacakan','7. Perubahan Kebijakan','8. Kontak'];
  static const _idBodies = [
    'Kami mengumpulkan informasi yang Anda berikan saat mendaftar (nama, email, nomor telepon), data kendaraan (merek, model, plat nomor), foto kerusakan yang Anda unggah, dan data penggunaan aplikasi secara anonim untuk meningkatkan layanan.',
    'Data Anda digunakan untuk memproses estimasi kerusakan AI, menghubungkan Anda dengan bengkel partner terdekat, mengirimkan pembaruan status perbaikan, memproses pembayaran dan klaim asuransi, serta meningkatkan akurasi model AI kami.',
    'Seluruh data disimpan di infrastruktur Supabase dengan enkripsi AES-256. Kami tidak pernah menjual data pribadi Anda kepada pihak ketiga. Akses data dibatasi hanya untuk keperluan layanan yang Anda gunakan.',
    'Data minimal yang diperlukan dibagikan kepada bengkel partner yang Anda pilih untuk keperluan perbaikan, serta kepada perusahaan asuransi jika Anda mengajukan klaim. Semua mitra terikat perjanjian kerahasiaan data.',
    'Anda berhak mengakses, memperbaiki, atau menghapus data pribadi Anda kapan saja melalui halaman profil. Untuk permintaan penghapusan akun, hubungi privacy@revive.co.id dan kami akan memprosesnya dalam 30 hari kerja.',
    'Aplikasi web kami menggunakan cookie sesi untuk autentikasi dan preferensi tema. Tidak ada cookie pelacakan pihak ketiga atau iklan yang digunakan di platform kami.',
    'Kebijakan ini dapat diperbarui sewaktu-waktu. Perubahan material akan diberitahukan melalui email terdaftar Anda minimal 14 hari sebelum berlaku.',
    'Untuk pertanyaan terkait privasi data, hubungi kami di: privacy@revive.co.id atau melalui fitur Support di aplikasi kami.',
  ];

  @override
  void initState() {
    super.initState();
    _pageTitleEn = TextEditingController(text: widget.s('privacy_page_title',    fb: 'Privacy Policy'));
    _pageTitleId = TextEditingController(text: widget.s('privacy_page_title_id', fb: 'Kebijakan Privasi'));
    _introEn     = TextEditingController(text: widget.s('privacy_intro',         fb: 'We are committed to protecting the privacy and security of your personal data.'));
    _introId     = TextEditingController(text: widget.s('privacy_intro_id',      fb: 'Kami berkomitmen untuk melindungi privasi dan keamanan data pribadi Anda.'));
    _updatedEn   = TextEditingController(text: widget.s('privacy_updated',       fb: 'Last updated: September 2026'));
    _updatedId   = TextEditingController(text: widget.s('privacy_updated_id',    fb: 'Terakhir diperbarui: September 2026'));
    for (int i = 0; i < _n; i++) {
      _secTitleEn.add(TextEditingController(text: widget.s('privacy_${i}_title',    fb: _enTitles[i])));
      _secTitleId.add(TextEditingController(text: widget.s('privacy_${i}_title_id', fb: _idTitles[i])));
      _secBodyEn.add( TextEditingController(text: widget.s('privacy_${i}_body',     fb: _enBodies[i])));
      _secBodyId.add( TextEditingController(text: widget.s('privacy_${i}_body_id',  fb: _idBodies[i])));
    }
  }

  @override
  void dispose() {
    for (final c in [_pageTitleEn, _pageTitleId, _introEn, _introId, _updatedEn, _updatedId,
      ..._secTitleEn, ..._secTitleId, ..._secBodyEn, ..._secBodyId]) c.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    final saves = <Future<void>>[
      widget.onSave('privacy_page_title',    _pageTitleEn.text, cat: 'legal'),
      widget.onSave('privacy_page_title_id', _pageTitleId.text, cat: 'legal'),
      widget.onSave('privacy_intro',         _introEn.text,     cat: 'legal'),
      widget.onSave('privacy_intro_id',      _introId.text,     cat: 'legal'),
      widget.onSave('privacy_updated',       _updatedEn.text,   cat: 'legal'),
      widget.onSave('privacy_updated_id',    _updatedId.text,   cat: 'legal'),
    ];
    for (int i = 0; i < _n; i++) {
      saves.add(widget.onSave('privacy_${i}_title',    _secTitleEn[i].text, cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_title_id', _secTitleId[i].text, cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_body',     _secBodyEn[i].text,  cat: 'legal'));
      saves.add(widget.onSave('privacy_${i}_body_id',  _secBodyId[i].text,  cat: 'legal'));
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
        Text('Manage revive.co.id/privacy  ·  EN + ID bilingual', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        _Card(cs: cs, title: 'Page Header', icon: Icons.privacy_tip_outlined, children: [
          _BilingualField(cs: cs, label: 'Page Title',   ctrlEn: _pageTitleEn, ctrlId: _pageTitleId, hintEn: 'Privacy Policy', hintId: 'Kebijakan Privasi', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Last Updated', ctrlEn: _updatedEn,   ctrlId: _updatedId,   hintEn: 'Last updated: September 2026', hintId: 'Terakhir diperbarui: September 2026', onChange: _mark),
          const SizedBox(height: 12),
          _BilingualField(cs: cs, label: 'Intro Text',   ctrlEn: _introEn,     ctrlId: _introId,     hintEn: 'Opening paragraph (EN)...', hintId: 'Paragraf pembuka (ID)...', maxLines: 3, onChange: _mark),
        ]),
        const SizedBox(height: 16),
        for (int i = 0; i < _n; i++) ...[
          _Card(cs: cs, title: 'Section ${i + 1}', icon: Icons.article_outlined, children: [
            _BilingualField(cs: cs, label: 'Heading', ctrlEn: _secTitleEn[i], ctrlId: _secTitleId[i], hintEn: _enTitles[i], hintId: _idTitles[i], onChange: _mark),
            const SizedBox(height: 12),
            _BilingualField(cs: cs, label: 'Body',    ctrlEn: _secBodyEn[i],  ctrlId: _secBodyId[i],  hintEn: 'Section content (EN)...', hintId: 'Konten bagian (ID)...', maxLines: 4, onChange: _mark),
          ]),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 80),
      ]));
  }
}
