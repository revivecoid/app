import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});
  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  bool _loading = true;
  List<Map<String, String>> _faqItems = [];

  String _phone      = '+62 800-123-456';
  String _email      = 'support@re-v.co.id';
  String _emergency  = '+62 800-TOW-REVIVE';
  String _pageTitle  = 'FAQ & Support';
  String _pageSub    = 'Find answers to common questions or reach out to our team.';

  static const _defaultFaq = [
    {'q': 'Bagaimana cara mendapatkan estimasi biaya perbaikan?',
     'a': 'Gunakan fitur AI Estimator kami — unggah 3-4 foto kerusakan dari berbagai sudut. Sistem Vision AI kami akan menganalisis kedalaman dan luas kerusakan lalu memberikan estimasi biaya dan waktu perbaikan dalam hitungan detik.'},
    {'q': 'Apakah saya bisa memilih bengkel partner yang menangani perbaikan?',
     'a': 'Ya. Setelah menerima estimasi AI, Anda akan melihat daftar bengkel partner tersertifikasi di area Anda. Anda dapat memilih berdasarkan rating, jarak, dan ketersediaan.'},
    {'q': 'Apakah ada garansi untuk hasil perbaikan?',
     'a': 'Semua partner tersertifikasi re-V mengikuti standar SLA kami. Setiap perbaikan dilindungi garansi 24 bulan untuk pengerjaan dan pencocokan warna cat, diverifikasi dengan sertifikat telemetri digital.'},
    {'q': 'Bagaimana cara melacak status perbaikan kendaraan saya?',
     'a': 'Buka bagian "Digital Garage" di profil Anda. Live Tracker menampilkan pembaruan tahap real-time — dari intake, pengerjaan bodi dan pengecatan, hingga serah terima. Setiap tahap didokumentasikan dengan foto.'},
    {'q': 'Apakah bisa menggunakan asuransi kendaraan?',
     'a': 'Tentu. Hubungkan polis Garda Oto atau Astra Insurance Anda di Profil → Saved Insurance Policies. Platform kami secara otomatis membuat dokumen loss-adjustment dan mengirimkannya langsung ke perusahaan asuransi Anda.'},
    {'q': 'Di mana saja jaringan bengkel partner Revive?',
     'a': 'Saat ini kami memiliki 38+ bengkel partner tersertifikasi di area Jabodetabek dan Bandung, dengan ekspansi aktif ke kota-kota besar lainnya.'},
    {'q': 'Apa itu Revive 24-Month Paint Guarantee?',
     'a': 'Setiap pekerjaan yang diselesaikan melalui re-V mencakup sertifikat garansi 24 bulan yang ditandatangani secara digital, mencakup adhesi cat, akurasi warna, dan kualitas permukaan. Sertifikat disimpan di Garage Profile Anda.'},
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
        if ((s['support_page_title']    ?? '').isNotEmpty) _pageTitle = s['support_page_title']!;
        if ((s['support_page_subtitle'] ?? '').isNotEmpty) _pageSub   = s['support_page_subtitle']!;

        final items = <Map<String, String>>[];
        int i = 0;
        while (s.containsKey('faq_${i}_q') || s.containsKey('faq_${i}_a')) {
          final q = s['faq_${i}_q'] ?? '';
          final a = s['faq_${i}_a'] ?? '';
          if (q.isNotEmpty || a.isNotEmpty) items.add({'q': q, 'a': a});
          i++;
        }
        if (items.isNotEmpty) _faqItems = items;
      }
    } catch (_) {}
    if (_faqItems.isEmpty) _faqItems = _defaultFaq.map((e) => Map<String, String>.from(e)).toList();
    if (mounted) setState(() => _loading = false);
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied to clipboard'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: ReVAppBar(title: Text(_pageTitle), showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ── Header ──────────────────────────────────────────────
                    Text(_pageTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_pageSub,
                        style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 32),

                    // ── Contact Cards ────────────────────────────────────────
                    Row(children: [
                      Expanded(child: _ContactCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'Live Chat', subtitle: 'Talk to a master estimator',
                        actionLabel: 'Open Chat',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Live chat launching soon'),
                              behavior: SnackBarBehavior.floating)),
                        isDark: isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _ContactCard(
                        icon: Icons.phone_outlined,
                        title: 'Call Us', subtitle: _phone,
                        actionLabel: 'Copy Number',
                        onTap: () => _copy(_phone, 'Phone number'),
                        isDark: isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _ContactCard(
                        icon: Icons.email_outlined,
                        title: 'Email', subtitle: _email,
                        actionLabel: 'Copy Email',
                        onTap: () => _copy(_email, 'Email'),
                        isDark: isDark)),
                    ]),

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
                          Text('24/7 Towing & Emergency Hotline',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
                          Text('$_emergency  ·  WhatsApp preferred',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ])),
                        TextButton(
                          onPressed: () => _copy(_emergency, 'Hotline'),
                          child: const Text('Copy', style: TextStyle(color: AppColors.primaryContainer))),
                      ]),
                    ),

                    const SizedBox(height: 32),

                    // ── FAQ Accordion ────────────────────────────────────────
                    Text('Frequently Asked Questions',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ..._faqItems.map((item) =>
                        _FaqItem(question: item['q']!, answer: item['a']!, isDark: isDark)),

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
      child: Column(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 24, color: AppColors.primaryContainer)),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
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
