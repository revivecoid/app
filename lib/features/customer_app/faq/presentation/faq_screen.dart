import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  List<Map<String, String>> _items = [];

  static const _defaults = [
    {
      'q': 'Bagaimana cara mendapatkan estimasi biaya perbaikan?',
      'a': 'Gunakan fitur AI Estimator kami — unggah 3-4 foto kerusakan dari berbagai sudut. Sistem Vision AI kami akan menganalisis kedalaman dan luas kerusakan lalu memberikan estimasi biaya dan waktu perbaikan dalam hitungan detik.',
    },
    {
      'q': 'Apakah saya bisa memilih bengkel partner yang menangani perbaikan?',
      'a': 'Ya. Setelah menerima estimasi AI, Anda akan melihat daftar bengkel partner tersertifikasi di area Anda. Anda dapat memilih berdasarkan rating, jarak, dan ketersediaan.',
    },
    {
      'q': 'Apakah ada garansi untuk hasil perbaikan?',
      'a': 'Semua partner tersertifikasi re-V mengikuti standar SLA kami. Setiap perbaikan dilindungi garansi 24 bulan untuk pengerjaan dan pencocokan warna cat, diverifikasi dengan sertifikat telemetri digital.',
    },
    {
      'q': 'Bagaimana cara melacak status perbaikan kendaraan saya?',
      'a': 'Buka bagian "Digital Garage" di profil Anda. Live Tracker menampilkan pembaruan tahap real-time — dari intake, pengerjaan bodi dan pengecatan, hingga serah terima. Setiap tahap didokumentasikan dengan foto.',
    },
    {
      'q': 'Apakah bisa menggunakan asuransi kendaraan?',
      'a': 'Tentu. Hubungkan polis Garda Oto atau Astra Insurance Anda di Profil dan Saved Insurance Policies. Platform kami secara otomatis membuat dokumen loss-adjustment dan mengirimkannya langsung ke perusahaan asuransi Anda.',
    },
    {
      'q': 'Di mana saja jaringan bengkel partner Revive?',
      'a': 'Saat ini kami memiliki 38+ bengkel partner tersertifikasi di area Jabodetabek dan Bandung, dengan ekspansi aktif ke kota-kota besar lainnya.',
    },
    {
      'q': 'Apa itu Revive 24-Month Paint Guarantee?',
      'a': 'Setiap pekerjaan yang diselesaikan melalui re-V mencakup sertifikat garansi 24 bulan yang ditandatangani secara digital, mencakup adhesi cat, akurasi warna, dan kualitas permukaan. Sertifikat disimpan di Garage Profile Anda.',
    },
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('get_cms_settings');
      if (res is Map) {
        final s = res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        final items = <Map<String, String>>[];
        int i = 0;
        while (s.containsKey('faq_${i}_q') || s.containsKey('faq_${i}_a')) {
          final q = s['faq_${i}_q'] ?? '';
          final a = s['faq_${i}_a'] ?? '';
          if (q.isNotEmpty || a.isNotEmpty) items.add({'q': q, 'a': a});
          i++;
        }
        if (items.isNotEmpty) _items = items;
      }
    } catch (_) {}
    if (_items.isEmpty) _items = _defaults.map((e) => Map<String, String>.from(e)).toList();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: const ReVAppBar(title: Text('FAQ'), showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Frequently Asked Questions',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Semua yang perlu Anda ketahui tentang layanan re-V.',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 32),
                    ..._items.map((item) => _buildFaqItem(context, item['q']!, item['a']!, isDark)),
                    const SizedBox(height: 32),
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: AppColors.primaryContainer, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Masih punya pertanyaan?',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                          Text('Tim kami siap membantu 7 hari seminggu.',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ])),
                        TextButton(
                          onPressed: () => context.go('/support'),
                          child: const Text('Hubungi Support',
                              style: TextStyle(color: AppColors.primaryContainer, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _buildFaqItem(BuildContext context, String question, String answer, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(answer,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.6, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
