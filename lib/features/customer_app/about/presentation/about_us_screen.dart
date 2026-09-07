import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class AboutUsScreen extends ConsumerStatefulWidget {
  const AboutUsScreen({super.key});
  @override
  ConsumerState<AboutUsScreen> createState() => _AboutState();
}

class _AboutState extends ConsumerState<AboutUsScreen> {
  bool _loading = true;
  Map<String, String> _s = {};

  String _get(String k, {required String fb}) =>
      (_s[k] != null && _s[k]!.isNotEmpty) ? _s[k]! : fb;

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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const ReVAppBar(title: Text('About Us'), showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Header
                    Text(
                      _get('about_title', fb: 'Tentang Revive'),
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _get('about_tagline', fb: 'Memimpin transformasi industri perbaikan otomotif Indonesia dengan teknologi AI dan jaringan bengkel terpercaya.'),
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),

                    // Stats strip
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        _StatItem(theme: theme, value: _get('stat_partners', fb: '38+'), label: 'Partner Bengkel'),
                        _Divider(),
                        _StatItem(theme: theme, value: _get('stat_rating', fb: '4.9/5'), label: 'Rating Pelanggan'),
                        _Divider(),
                        _StatItem(theme: theme, value: _get('stat_jobs', fb: '12,000+'), label: 'Kendaraan Diperbaiki'),
                      ]),
                    ),
                    const SizedBox(height: 24),

                    // Story
                    Text('Cerita Kami',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildCard(theme, isDark,
                        _get('about_story', fb: 'Revive lahir dari frustrasi nyata: proses klaim asuransi yang rumit, estimasi biaya yang tidak transparan, dan sulitnya menemukan bengkel terpercaya. Kami membangun solusi end-to-end yang menggabungkan AI, jaringan mitra terverifikasi, dan dashboard real-time untuk memastikan setiap pemilik kendaraan mendapat layanan terbaik dengan harga yang jujur.')),
                    const SizedBox(height: 24),

                    // Mission & Vision
                    Text('Misi & Visi',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildLabelCard(theme, isDark, Icons.rocket_launch_rounded, 'Misi Kami',
                        _get('about_mission', fb: 'Menjadikan perbaikan bodi kendaraan di Indonesia sepenuhnya transparan, cepat, dan dapat diakses oleh semua orang — dari proses klaim asuransi hingga garansi hasil kerja.')),
                    _buildLabelCard(theme, isDark, Icons.visibility_rounded, 'Visi Kami',
                        _get('about_vision', fb: 'Menjadi platform perbaikan otomotif #1 di Asia Tenggara dengan teknologi AI terdepan dan ekosistem bengkel mitra yang paling dipercaya.')),
                    const SizedBox(height: 24),

                    // Values
                    Text('Nilai-Nilai Kami',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(children: [
                        _ValueTile(theme: theme, icon: Icons.verified_rounded, title: 'Transparan', sub: 'Estimasi biaya real, tidak ada biaya tersembunyi'),
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        _ValueTile(theme: theme, icon: Icons.bolt_rounded, title: 'Cepat', sub: 'Proses digital dari klaim hingga pengambilan kendaraan'),
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        _ValueTile(theme: theme, icon: Icons.handshake_rounded, title: 'Terpercaya', sub: '90 hari garansi pengerjaan di semua mitra kami'),
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        _ValueTile(theme: theme, icon: Icons.smart_toy_rounded, title: 'Inovatif', sub: 'AI damage detection & pricing terdepan di industri'),
                      ]),
                    ),
                    const SizedBox(height: 32),

                    // Partner CTA
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
                          child: const Icon(Icons.handshake_rounded, color: AppColors.primaryContainer, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Bergabung sebagai Partner Bengkel',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                          Text('Daftarkan bengkel Anda dan mulai terima order dari Revive.',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ])),
                        TextButton(
                          onPressed: () {},
                          child: const Text('Daftar',
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

  Widget _buildCard(ThemeData theme, bool isDark, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.6, fontSize: 13)),
    );
  }

  Widget _buildLabelCard(ThemeData theme, bool isDark, IconData icon, String label, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: AppColors.primaryContainer),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        Text(body, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.6, fontSize: 13)),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final ThemeData theme; final String value, label;
  const _StatItem({required this.theme, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryContainer)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
  ]));
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 36,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4));
}

class _ValueTile extends StatelessWidget {
  final ThemeData theme; final IconData icon; final String title, sub;
  const _ValueTile({required this.theme, required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Icon(icon, size: 18, color: AppColors.primaryContainer),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(sub, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      ])),
    ]),
  );
}
