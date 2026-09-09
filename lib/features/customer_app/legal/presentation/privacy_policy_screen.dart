import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class PrivacyPolicyScreen extends ConsumerStatefulWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  ConsumerState<PrivacyPolicyScreen> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<PrivacyPolicyScreen> {
  bool _loading = true;
  Map<String, String> _s = {};

  String _cmsL(String k, {required bool isId, required String fb}) {
    if (isId) {
      final idVal = _s['${k}_id'];
      if (idVal != null && idVal.isNotEmpty) return idVal;
    }
    return (_s[k] != null && _s[k]!.isNotEmpty) ? _s[k]! : fb;
  }

  static const _defaultSectionsEn = [
    ('1. Data We Collect',
     'We collect information you provide when registering (name, email, phone number), vehicle data (make, model, license plate), damage photos you upload, and anonymous app usage data to improve the service.'),
    ('2. Use of Data',
     'Your data is used to process AI damage estimates, connect you with the nearest partner workshop, send repair status updates, process payments and insurance claims, and improve the accuracy of our AI model.'),
    ('3. Data Security',
     'All data is stored on Supabase infrastructure with AES-256 encryption. We never sell your personal data to third parties. Data access is restricted only to the services you use.'),
    ('4. Sharing Data with Third Parties',
     'Minimal necessary data is shared with the partner workshop you select for repair purposes, and with insurance companies if you file a claim. All partners are bound by data confidentiality agreements.'),
    ('5. User Rights',
     'You have the right to access, correct, or delete your personal data at any time via the profile page. For account deletion requests, contact privacy@revive.co.id and we will process it within 30 business days.'),
    ('6. Cookies and Tracking',
     'Our web app uses session cookies for authentication and theme preferences. No third-party tracking or advertising cookies are used on our platform.'),
    ('7. Policy Changes',
     'This policy may be updated at any time. Material changes will be communicated via your registered email at least 14 days before taking effect.'),
    ('8. Contact',
     'For privacy data enquiries, contact us at: privacy@revive.co.id or via the Support feature in our application.'),
  ];

  static const _defaultSectionsId = [
    ('1. Data yang Kami Kumpulkan',
     'Kami mengumpulkan informasi yang Anda berikan saat mendaftar (nama, email, nomor telepon), data kendaraan (merek, model, plat nomor), foto kerusakan yang Anda unggah, dan data penggunaan aplikasi secara anonim untuk meningkatkan layanan.'),
    ('2. Penggunaan Data',
     'Data Anda digunakan untuk memproses estimasi kerusakan AI, menghubungkan Anda dengan bengkel partner terdekat, mengirimkan pembaruan status perbaikan, memproses pembayaran dan klaim asuransi, serta meningkatkan akurasi model AI kami.'),
    ('3. Keamanan Data',
     'Seluruh data disimpan di infrastruktur Supabase dengan enkripsi AES-256. Kami tidak pernah menjual data pribadi Anda kepada pihak ketiga. Akses data dibatasi hanya untuk keperluan layanan yang Anda gunakan.'),
    ('4. Berbagi Data dengan Pihak Ketiga',
     'Data minimal yang diperlukan dibagikan kepada bengkel partner yang Anda pilih untuk keperluan perbaikan, serta kepada perusahaan asuransi jika Anda mengajukan klaim. Semua mitra terikat perjanjian kerahasiaan data.'),
    ('5. Hak Pengguna',
     'Anda berhak mengakses, memperbaiki, atau menghapus data pribadi Anda kapan saja melalui halaman profil. Untuk permintaan penghapusan akun, hubungi privacy@revive.co.id dan kami akan memprosesnya dalam 30 hari kerja.'),
    ('6. Cookie dan Pelacakan',
     'Aplikasi web kami menggunakan cookie sesi untuk autentikasi dan preferensi tema. Tidak ada cookie pelacakan pihak ketiga atau iklan yang digunakan di platform kami.'),
    ('7. Perubahan Kebijakan',
     'Kebijakan ini dapat diperbarui sewaktu-waktu. Perubahan material akan diberitahukan melalui email terdaftar Anda minimal 14 hari sebelum berlaku.'),
    ('8. Kontak',
     'Untuk pertanyaan terkait privasi data, hubungi kami di: privacy@revive.co.id atau melalui fitur Support di aplikasi kami.'),
  ];

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
    final cs = theme.colorScheme;
    final isId = ref.watch(localeProvider).languageCode == 'id';
    final defaults = isId ? _defaultSectionsId : _defaultSectionsEn;

    final sections = <(String, String)>[];
    for (int i = 0; i < defaults.length; i++) {
      final title = _cmsL('privacy_${i}_title', isId: isId, fb: defaults[i].$1);
      final body  = _cmsL('privacy_${i}_body',  isId: isId, fb: defaults[i].$2);
      sections.add((title, body));
    }

    final pageTitle   = _cmsL('privacy_page_title', isId: isId, fb: isId ? 'Kebijakan Privasi' : 'Privacy Policy');
    final pageUpdated = _cmsL('privacy_updated',     isId: isId, fb: isId ? 'Terakhir diperbarui: September 2026' : 'Last updated: September 2026');
    final pageIntro   = _cmsL('privacy_intro',       isId: isId, fb: isId
        ? 'Kami berkomitmen untuk melindungi privasi dan keamanan data pribadi Anda.'
        : 'We are committed to protecting the privacy and security of your personal data.');

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

                    // ── Header ────────────────────────────────────────────────
                    Text(pageTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(pageIntro,
                        style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.calendar_today_outlined, size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(pageUpdated,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 32),

                    // ── Sections ──────────────────────────────────────────────
                    ...sections.map((sec) => _SectionCard(
                          title: sec.$1,
                          body: sec.$2,
                          isDark: isDark,
                        )),

                    const SizedBox(height: 8),

                    // ── Contact strip ─────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.shield_outlined, color: cs.primary, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            isId ? 'Pertanyaan Privasi?' : 'Privacy Questions?',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface),
                          ),
                          Text(
                            isId
                                ? 'Hubungi kami di privacy@revive.co.id'
                                : 'Reach us at privacy@revive.co.id',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ])),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
            ),
    );
  }
}

// ── Section card widget ────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final String body;
  final bool isDark;
  const _SectionCard({required this.title, required this.body, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, color: theme.colorScheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Text(body,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.65,
                  color: theme.colorScheme.onSurfaceVariant)),
        ])),
      ]),
    );
  }
}
