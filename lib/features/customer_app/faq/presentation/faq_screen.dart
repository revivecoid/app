import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/locale_provider.dart';

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});
  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  bool _loading = true;
  // Dual-language FAQ items: each map has 'q', 'a', 'q_id', 'a_id'
  List<Map<String, String>> _faqItems = [];

  String _phone     = '+62 800-123-456';
  String _email     = 'support@re-v.co.id';
  String _emergency = '+62 800-TOW-REVIVE';
  // EN content
  String _pageTitleEn  = '';
  String _pageSubEn    = '';
  // ID content
  String _pageTitleId  = '';
  String _pageSubId    = '';

  static const _defaultFaqEn = [
    {'q': 'How does the AI estimation work?',
     'a': 'Simply upload 3–4 photos of the damaged area from different angles. Our Vision AI analyses the depth and span of the damage and provides an estimated repair cost and time within seconds.'},
    {'q': 'Can I choose which partner workshop handles my repair?',
     'a': 'Yes. After receiving the AI estimate, you will see a list of certified partner workshops in your area. You can select one based on ratings, distance, and availability.'},
    {'q': 'Is the repair quality guaranteed?',
     'a': 'All re-V certified partners adhere to our SLA standards, and all repairs come with a 24-month warranty on workmanship and paint matching verified by our digital telemetry certificate.'},
    {'q': 'How do I track my repair progress?',
     'a': 'Open the "Digital Garage" section of your profile. The Live Tracker shows real-time stage updates — from intake, through active bodywork and painting, to handover. Each stage is photo-documented.'},
    {'q': 'What is the Revive 24-Month Paint Guarantee?',
     'a': 'Every job completed through re-V includes a digitally signed 24-month guarantee certificate covering paint adhesion, colour accuracy, and surface finish. It is stored in your Garage Profile.'},
    {'q': 'How are insurance claims handled?',
     'a': 'Link your Garda Oto or Astra insurance policy in Profile → Saved Insurance Policies. Our platform auto-generates the required loss-adjustment documentation and submits directly to your insurer.'},
  ];

  static const _defaultFaqId = [
    {'q': 'Bagaimana cara mendapatkan estimasi biaya perbaikan?',
     'a': 'Gunakan fitur AI Estimator kami — unggah 3-4 foto kerusakan dari berbagai sudut. Sistem Vision AI kami akan menganalisis kedalaman dan luas kerusakan lalu memberikan estimasi biaya dan waktu perbaikan dalam hitungan detik.'},
    {'q': 'Apakah saya bisa memilih bengkel partner yang menangani perbaikan?',
     'a': 'Ya. Setelah menerima estimasi AI, Anda akan melihat daftar bengkel partner tersertifikasi di area Anda. Anda dapat memilih berdasarkan rating, jarak, dan ketersediaan.'},
    {'q': 'Apakah ada garansi untuk hasil perbaikan?',
     'a': 'Semua partner tersertifikasi re-V mengikuti standar SLA kami. Setiap perbaikan dilindungi garansi 24 bulan untuk pengerjaan dan pencocokan warna cat.'},
    {'q': 'Bagaimana cara melacak status perbaikan kendaraan saya?',
     'a': 'Buka bagian "Digital Garage" di profil Anda. Live Tracker menampilkan pembaruan tahap real-time — dari intake, pengerjaan bodi dan pengecatan, hingga serah terima.'},
    {'q': 'Apa itu Revive 24-Month Paint Guarantee?',
     'a': 'Setiap pekerjaan yang diselesaikan melalui re-V mencakup sertifikat garansi 24 bulan yang ditandatangani secara digital, mencakup adhesi cat, akurasi warna, dan kualitas permukaan.'},
    {'q': 'Bagaimana klaim asuransi diproses?',
     'a': 'Hubungkan polis Garda Oto atau Astra Insurance Anda di Profil → Saved Insurance Policies. Platform kami secara otomatis membuat dokumen loss-adjustment dan mengirimkannya langsung ke perusahaan asuransi Anda.'},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('get_cms_settings');
      if (res is Map) {
        final s = res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        if ((s['support_phone']         ?? '').isNotEmpty) _phone     = s['support_phone']!;
        if ((s['support_email']         ?? '').isNotEmpty) _email     = s['support_email']!;
        if ((s['support_emergency']     ?? '').isNotEmpty) _emergency = s['support_emergency']!;
        _pageTitleEn = s['support_page_title']    ?? '';
        _pageSubEn   = s['support_page_subtitle'] ?? '';
        _pageTitleId = s['support_page_title_id'] ?? '';
        _pageSubId   = s['support_page_subtitle_id'] ?? '';

        final items = <Map<String, String>>[];
        int i = 0;
        while (s.containsKey('faq_${i}_q') || s.containsKey('faq_${i}_a')) {
          final q    = s['faq_${i}_q']    ?? '';
          final a    = s['faq_${i}_a']    ?? '';
          final qId  = s['faq_${i}_q_id'] ?? '';
          final aId  = s['faq_${i}_a_id'] ?? '';
          if (q.isNotEmpty || a.isNotEmpty) items.add({'q': q, 'a': a, 'q_id': qId, 'a_id': aId});
          i++;
        }
        if (items.isNotEmpty) _faqItems = items;
      }
    } catch (_) {}
    if (_faqItems.isEmpty) {
      _faqItems = List.generate(_defaultFaqEn.length, (i) => {
        'q': _defaultFaqEn[i]['q']!, 'a': _defaultFaqEn[i]['a']!,
        'q_id': _defaultFaqId[i]['q']!, 'a_id': _defaultFaqId[i]['a']!,
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  void _copy(String text, String label) {
    // ignore: avoid_print
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final l = AppL.of(context)!;
    final locale = ref.watch(localeProvider).languageCode;
    final isId = locale == 'id';

    final pageTitle = isId
        ? (_pageTitleId.isNotEmpty ? _pageTitleId : l.faqTitle)
        : (_pageTitleEn.isNotEmpty ? _pageTitleEn : l.faqTitle);
    final pageSub = isId
        ? (_pageSubId.isNotEmpty ? _pageSubId : l.faqSubtitle)
        : (_pageSubEn.isNotEmpty ? _pageSubEn : l.faqSubtitle);

    return Scaffold(
      appBar: ReVAppBar(title: Text(pageTitle), showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ── Header ──────────────────────────────────────────────
                    Text(pageTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(pageSub,
                        style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 32),

                    // ── Contact Cards ────────────────────────────────────────
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: _ContactCard(
                          icon: Icons.chat_bubble_outline,
                          title: l.supportLiveChat, subtitle: l.supportTalkToEstimator,
                          actionLabel: l.supportOpenChat,
                          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.loading),
                                behavior: SnackBarBehavior.floating)),
                          isDark: isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _ContactCard(
                          icon: Icons.phone_outlined,
                          title: l.supportCallUs, subtitle: _phone,
                          actionLabel: l.supportCopyNumber,
                          onTap: () => _copy(_phone, l.supportPhone),
                          isDark: isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _ContactCard(
                          icon: Icons.email_outlined,
                          title: 'Email', subtitle: _email,
                          actionLabel: l.supportCopyEmail,
                          onTap: () => _copy(_email, 'Email'),
                          isDark: isDark)),
                      ]),
                    ),

                    const SizedBox(height: 24),

                    // ── Emergency strip ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.local_taxi, color: AppColors.primaryContainer, size: 24)),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.supportEmergencyTitle,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
                          Text('$_emergency  ·  WhatsApp',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ])),
                        TextButton(
                          onPressed: () => _copy(_emergency, l.supportPhone),
                          child: Text(l.supportCopy, style: const TextStyle(color: AppColors.primaryContainer))),
                      ]),
                    ),

                    const SizedBox(height: 32),

                    // ── FAQ Accordion ────────────────────────────────────────
                    Text(l.supportFaqTitle,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ..._faqItems.map((item) {
                      final q = isId
                          ? (item['q_id']!.isNotEmpty ? item['q_id']! : item['q']!)
                          : item['q']!;
                      final a = isId
                          ? (item['a_id']!.isNotEmpty ? item['a_id']! : item['a']!)
                          : item['a']!;
                      return _FaqItem(question: q, answer: a, isDark: isDark);
                    }),

                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ),
    );
  }
}

// ── Contact card widget ────────────────────────────────────────────────────────
class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, actionLabel;
  final VoidCallback onTap;
  final bool isDark;
  const _ContactCard({required this.icon, required this.title, required this.subtitle,
    required this.actionLabel, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(mainAxisSize: MainAxisSize.max, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 24, color: AppColors.primaryContainer)),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
        const Spacer(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryContainer,
              side: BorderSide(color: AppColors.primaryContainer.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text(actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
      ]),
    );
  }
}

// ── FAQ accordion item ─────────────────────────────────────────────────────────
class _FaqItem extends StatelessWidget {
  final String question, answer;
  final bool isDark;
  const _FaqItem({required this.question, required this.answer, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4))),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(answer, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.6, fontSize: 13))),
        ]),
    );
  }
}
