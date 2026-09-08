import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class AboutUsScreen extends ConsumerStatefulWidget {
  const AboutUsScreen({super.key});
  @override
  ConsumerState<AboutUsScreen> createState() => _AboutState();
}

class _AboutState extends ConsumerState<AboutUsScreen> {
  bool _loading = true;
  Map<String, String> _s = {};

  String _cmsL(String k, {required bool isId, required String en, required String id}) {
    if (isId) {
      final v = _s['${k}_id'];
      if (v != null && v.isNotEmpty) return v;
    }
    final v = _s[k];
    if (v != null && v.isNotEmpty) return v;
    return isId ? id : en;
  }

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
    final isId = ref.watch(localeProvider).languageCode == 'id';

    String c(String k, {required String en, required String id}) =>
        _cmsL(k, isId: isId, en: en, id: id);

    return Scaffold(
      appBar: ReVAppBar(title: Text(isId ? 'Tentang Kami' : 'About Us'), showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      c('about_title', en: 'About Revive', id: 'Tentang Revive'),
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c('about_tagline',
                        en: 'Leading the transformation of Indonesia\'s automotive repair industry with AI technology and a trusted workshop network.',
                        id: 'Memimpin transformasi industri perbaikan otomotif Indonesia dengan teknologi AI dan jaringan bengkel terpercaya.'),
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),

                    // Stats
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        _StatItem(theme: theme, value: c('stat_partners', en: '38+', id: '38+'),
                            label: isId ? 'Bengkel Mitra' : 'Partner Hubs'),
                        _Divider(),
                        _StatItem(theme: theme, value: c('stat_rating', en: '4.9/5', id: '4.9/5'),
                            label: isId ? 'Rating Pelanggan' : 'Customer Rating'),
                        _Divider(),
                        _StatItem(theme: theme, value: c('stat_jobs', en: '12,000+', id: '12.000+'),
                            label: isId ? 'Kendaraan Diperbaiki' : 'Cars Repaired'),
                      ]),
                    ),
                    const SizedBox(height: 24),

                    // Story
                    Text(isId ? 'Cerita Kami' : 'Our Story',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildCard(theme, isDark,
                        c('about_story',
                          en: 'Revive was born from a real frustration: complicated insurance claim processes, opaque cost estimates, and the difficulty of finding a trustworthy workshop. We built an end-to-end solution combining AI, a verified partner network, and real-time dashboards to ensure every vehicle owner gets the best service at a fair price.',
                          id: 'Revive lahir dari frustrasi nyata: proses klaim asuransi yang rumit, estimasi biaya yang tidak transparan, dan sulitnya menemukan bengkel terpercaya. Kami membangun solusi end-to-end yang menggabungkan AI, jaringan mitra terverifikasi, dan dashboard real-time untuk memastikan setiap pemilik kendaraan mendapat layanan terbaik dengan harga yang jujur.')),
                    const SizedBox(height: 24),

                    // Mission & Vision
                    Text(isId ? 'Misi & Visi' : 'Mission & Vision',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildLabelCard(theme, isDark, Icons.rocket_launch_rounded,
                        isId ? 'Misi Kami' : 'Our Mission',
                        c('about_mission',
                          en: 'To make vehicle body repair in Indonesia fully transparent, fast, and accessible to everyone — from insurance claims to work guarantees.',
                          id: 'Menjadikan perbaikan bodi kendaraan di Indonesia sepenuhnya transparan, cepat, dan dapat diakses oleh semua orang — dari proses klaim asuransi hingga garansi hasil kerja.')),
                    _buildLabelCard(theme, isDark, Icons.visibility_rounded,
                        isId ? 'Visi Kami' : 'Our Vision',
                        c('about_vision',
                          en: 'To become the #1 automotive repair platform in Southeast Asia with leading AI technology and the most trusted partner workshop ecosystem.',
                          id: 'Menjadi platform perbaikan otomotif #1 di Asia Tenggara dengan teknologi AI terdepan dan ekosistem bengkel mitra yang paling dipercaya.')),
                    const SizedBox(height: 24),

                    // Values
                    Text(isId ? 'Nilai-Nilai Kami' : 'Our Values',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(children: [
                        _ValueTile(theme: theme, icon: Icons.verified_rounded,
                            title: c('value_1_title', en: 'Transparent', id: 'Transparan'),
                            sub:   c('value_1_sub',   en: 'Real cost estimates, no hidden fees', id: 'Estimasi biaya real, tidak ada biaya tersembunyi')),
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        _ValueTile(theme: theme, icon: Icons.bolt_rounded,
                            title: c('value_2_title', en: 'Fast', id: 'Cepat'),
                            sub:   c('value_2_sub',   en: 'Digital process from claim to vehicle pickup', id: 'Proses digital dari klaim hingga pengambilan kendaraan')),
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        _ValueTile(theme: theme, icon: Icons.handshake_rounded,
                            title: c('value_3_title', en: 'Trusted', id: 'Terpercaya'),
                            sub:   c('value_3_sub',   en: '90-day work guarantee at all our partners', id: '90 hari garansi pengerjaan di semua mitra kami')),
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        _ValueTile(theme: theme, icon: Icons.smart_toy_rounded,
                            title: c('value_4_title', en: 'Innovative', id: 'Inovatif'),
                            sub:   c('value_4_sub',   en: 'Industry-leading AI damage detection & pricing', id: 'AI damage detection & pricing terdepan di industri')),
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
                           Text(c('partner_cta_title',
                               en: 'Join as a Partner Workshop',
                               id: 'Bergabung sebagai Partner Bengkel'),
                               style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                           Text(c('partner_cta_sub',
                               en: 'Register your workshop and start receiving orders from Revive.',
                               id: 'Daftarkan bengkel Anda dan mulai terima order dari Revive.'),
                               style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ])),
                        TextButton(
                          onPressed: () {},
                          child: Text(c('cta_register', en: 'Register', id: 'Daftar'),
                              style: const TextStyle(color: AppColors.primaryContainer, fontWeight: FontWeight.bold)),
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
      ),
      child: Text(text, style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface)),
    );
  }

  Widget _buildLabelCard(ThemeData theme, bool isDark, IconData icon, String label, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.primaryContainer, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: theme.colorScheme.onSurfaceVariant)),
        ])),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final ThemeData theme;
  final String value;
  final String label;
  const _StatItem({required this.theme, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: AppColors.fireRed)),
    Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
  ]));
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 40, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4));
}

class _ValueTile extends StatelessWidget {
  final ThemeData theme;
  final IconData icon;
  final String title;
  final String sub;
  const _ValueTile({required this.theme, required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, color: AppColors.primaryContainer, size: 20),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(sub, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      ])),
    ]),
  );
}
