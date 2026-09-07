import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class AboutUsScreen extends ConsumerStatefulWidget {
  const AboutUsScreen({super.key});
  @override ConsumerState<AboutUsScreen> createState() => _AboutState();
}

class _AboutState extends ConsumerState<AboutUsScreen> {
  bool _loading = true;
  Map<String, String> _s = {};

  String _get(String k, {required String fb}) => (_s[k] != null && _s[k]!.isNotEmpty) ? _s[k]! : fb;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('get_cms_settings');
      if (res is Map) _s = res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(showBackButton: true,
        title: Text('About Us', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface))),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: cs.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Hero banner
                Container(width: double.infinity, padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0.15), cs.primary.withValues(alpha: 0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                      child: Text('TENTANG REVIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: 1.2))),
                    const SizedBox(height: 12),
                    Text(_get('about_title', fb: 'Memimpin Transformasi Industri Perbaikan Otomotif Indonesia'),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface, height: 1.25)),
                    const SizedBox(height: 10),
                    Text(_get('about_tagline', fb: 'Revive menghadirkan transparansi, teknologi AI, dan jaringan bengkel terpercaya untuk pengalaman perbaikan kendaraan yang sesungguhnya modern.'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
                  ])),
                const SizedBox(height: 20),
                // Stats row
                Row(children: [
                  _StatCard(cs: cs, theme: theme, icon: Icons.hub_rounded, value: _get('stat_partners', fb: '38+'), label: 'Partner Bengkel'),
                  const SizedBox(width: 8),
                  _StatCard(cs: cs, theme: theme, icon: Icons.star_rounded, value: _get('stat_rating', fb: '4.9/5'), label: 'Rating Pelanggan'),
                  const SizedBox(width: 8),
                  _StatCard(cs: cs, theme: theme, icon: Icons.directions_car_rounded, value: _get('stat_jobs', fb: '12,000+'), label: 'Kendaraan Diperbaiki'),
                ]),
                const SizedBox(height: 20),
                // Story
                _Section(cs: cs, theme: theme, icon: Icons.auto_stories_rounded, title: 'Cerita Kami',
                  body: _get('about_story', fb: 'Revive lahir dari frustrasi nyata: proses klaim asuransi yang rumit, estimasi biaya yang tidak transparan, dan sulitnya menemukan bengkel terpercaya. Kami membangun solusi end-to-end yang menggabungkan AI, jaringan mitra terverifikasi, dan dashboard real-time untuk memastikan setiap pemilik kendaraan mendapat layanan terbaik dengan harga yang jujur.')),
                const SizedBox(height: 12),
                _Section(cs: cs, theme: theme, icon: Icons.rocket_launch_rounded, title: 'Misi Kami',
                  body: _get('about_mission', fb: 'Menjadikan perbaikan bodi kendaraan di Indonesia sepenuhnya transparan, cepat, dan dapat diakses oleh semua orang — dari proses klaim asuransi hingga garansi hasil kerja.')),
                const SizedBox(height: 12),
                _Section(cs: cs, theme: theme, icon: Icons.visibility_rounded, title: 'Visi Kami',
                  body: _get('about_vision', fb: 'Menjadi platform perbaikan otomotif #1 di Asia Tenggara dengan teknologi AI terdepan dan ekosistem bengkel mitra yang paling dipercaya.')),
                const SizedBox(height: 20),
                // Team / values
                Container(padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.workspace_premium_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Nilai-Nilai Kami', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
                    ]),
                    const Divider(height: 20),
                    _ValueRow(cs: cs, icon: Icons.verified_rounded, title: 'Transparan', sub: 'Estimasi biaya real, tidak ada biaya tersembunyi'),
                    _ValueRow(cs: cs, icon: Icons.bolt_rounded, title: 'Cepat', sub: 'Proses digital dari klaim hingga pengambilan kendaraan'),
                    _ValueRow(cs: cs, icon: Icons.handshake_rounded, title: 'Terpercaya', sub: '90 hari garansi pengerjaan di semua mitra kami'),
                    _ValueRow(cs: cs, icon: Icons.smart_toy_rounded, title: 'Inovatif', sub: 'AI damage detection & pricing terdepan di industri'),
                  ])),
                const SizedBox(height: 24),
              ]),
            )),
    );
  }
}

class _StatCard extends StatelessWidget {
  final ColorScheme cs; final ThemeData theme; final IconData icon; final String value, label;
  const _StatCard({required this.cs, required this.theme, required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
    child: Column(children: [
      Icon(icon, size: 20, color: cs.primary),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
      Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
    ])));
}

class _Section extends StatelessWidget {
  final ColorScheme cs; final ThemeData theme; final IconData icon; final String title, body;
  const _Section({required this.cs, required this.theme, required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 16, color: cs.primary), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface))]),
      const SizedBox(height: 10),
      Text(body, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.6)),
    ]));
}

class _ValueRow extends StatelessWidget {
  final ColorScheme cs; final IconData icon; final String title, sub;
  const _ValueRow({required this.cs, required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(icon, size: 16, color: cs.primary),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface)),
        Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ])),
    ]));
}
