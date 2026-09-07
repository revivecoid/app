import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});
  @override ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  bool _loading = true;
  List<Map<String, String>> _items = [];
  String _pageTitle = 'Frequently Asked Questions';

  // Default FAQ content shown if CMS has no data yet
  static const _defaults = [
    {'q': 'Bagaimana cara mendapatkan estimasi biaya perbaikan?',
     'a': 'Gunakan fitur AI Estimator kami - unggah foto kerusakan kendaraan Anda dan sistem akan memberikan estimasi biaya dalam hitungan detik.'},
    {'q': 'Berapa lama proses perbaikan biasanya berlangsung?',
     'a': 'Tergantung tingkat kerusakan. Perbaikan ringan 1-3 hari, sedang 3-7 hari, berat 1-3 minggu. Kami selalu memberikan estimasi waktu yang akurat sebelum pekerjaan dimulai.'},
    {'q': 'Apakah ada garansi untuk hasil perbaikan?',
     'a': 'Ya! Semua pekerjaan perbaikan dilindungi garansi pengerjaan 90 hari. Jika ada masalah terkait kualitas kerja, kami akan memperbaikinya tanpa biaya tambahan.'},
    {'q': 'Bagaimana cara melacak status perbaikan kendaraan saya?',
     'a': 'Login ke akun Anda di revive.co.id atau aplikasi re-V, lalu buka menu Track Repair. Anda dapat melihat status real-time dengan foto progress dari bengkel.'},
    {'q': 'Apakah bisa menggunakan asuransi kendaraan?',
     'a': 'Tentu! Kami bekerja sama langsung dengan Garda Oto dan Astra Insurance. Tim kami akan membantu proses klaim asuransi dari awal hingga selesai.'},
    {'q': 'Di mana saja jaringan bengkel partner Revive?',
     'a': 'Saat ini kami memiliki 38+ bengkel partner tersertifikasi di area Jabodetabek dan Bandung, dengan ekspansi aktif ke kota-kota besar lainnya.'},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('get_cms_settings');
      if (res is Map) {
        final s = res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        _pageTitle = (s['faq_page_title'] ?? '').isNotEmpty ? s['faq_page_title']! : _pageTitle;
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
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(showBackButton: true,
        title: Text('FAQ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface))),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: cs.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text('HELP CENTER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: 1.2))),
                const SizedBox(height: 10),
                Text(_pageTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('Semua yang perlu Anda ketahui tentang layanan re-V', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 20),
                ..._items.asMap().entries.map((e) => _FaqTile(cs: cs, theme: theme, index: e.key, item: e.value)),
                const SizedBox(height: 32),
                Container(padding: const EdgeInsets.all(16), width: double.infinity,
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Icon(Icons.support_agent_rounded, size: 32, color: cs.primary),
                    const SizedBox(height: 8),
                    Text('Masih punya pertanyaan?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text('Tim kami siap membantu 7 hari seminggu', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.chat_rounded, size: 16), label: const Text('Hubungi Support')),
                  ])),
                const SizedBox(height: 24),
              ]),
            )),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final ColorScheme cs; final ThemeData theme; final int index; final Map<String, String> item;
  const _FaqTile({required this.cs, required this.theme, required this.index, required this.item});
  @override State<_FaqTile> createState() => _FaqTileState();
}
class _FaqTileState extends State<_FaqTile> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return AnimatedContainer(duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _open ? cs.primary.withValues(alpha: 0.05) : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _open ? cs.primary.withValues(alpha: 0.3) : cs.outlineVariant.withValues(alpha: 0.4))),
      child: Column(children: [
        InkWell(borderRadius: BorderRadius.circular(12), onTap: () => setState(() => _open = !_open),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(width: 24, height: 24, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Center(child: Text('${widget.index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.primary)))),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.item['q'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface))),
            Icon(_open ? Icons.remove_rounded : Icons.add_rounded, size: 18, color: cs.primary),
          ]))),
        if (_open)
          Padding(padding: const EdgeInsets.fromLTRB(48, 0, 14, 14),
            child: Text(widget.item['a'] ?? '', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.6))),
      ]));
  }
}
