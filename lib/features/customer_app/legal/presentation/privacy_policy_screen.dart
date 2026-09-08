import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class PrivacyPolicyScreen extends ConsumerStatefulWidget {
  const PrivacyPolicyScreen({super.key});
  @override ConsumerState<PrivacyPolicyScreen> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<PrivacyPolicyScreen> {
  bool _loading = true;
  Map<String, String> _s = {};

  // Locale-aware CMS lookup: uses _id suffixed key when locale is Indonesian.
  String _cmsL(String k, {required String fb}) {
    final isId = ref.read(localeProvider).languageCode == 'id';
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
    final cs = theme.colorScheme;
    final l = AppL.of(context)!;
    final isId = ref.watch(localeProvider).languageCode == 'id';
    final defaults = isId ? _defaultSectionsId : _defaultSectionsEn;

    // Build sections: CMS overrides take priority over locale defaults
    final sections = <(String, String)>[];
    for (int i = 0; i < defaults.length; i++) {
      final title = _cmsL('privacy_${i}_title', fb: defaults[i].$1);
      final body  = _cmsL('privacy_${i}_body',  fb: defaults[i].$2);
      sections.add((title, body));
    }

    final pageTitle   = _cmsL('privacy_page_title', fb: isId ? 'Kebijakan Privasi' : 'Privacy Policy');
    final pageUpdated = _cmsL('privacy_updated',     fb: isId ? 'Terakhir diperbarui: September 2026' : 'Last updated: September 2026');
    final pageIntro   = _cmsL('privacy_intro',       fb: isId
        ? 'Kami berkomitmen untuk melindungi privasi dan keamanan data pribadi Anda.'
        : 'We are committed to protecting the privacy and security of your personal data.');

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(showBackButton: true,
        title: Text(pageTitle,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface))),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: cs.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('LEGAL',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: cs.primary, letterSpacing: 1.2))),
                const SizedBox(height: 10),
                Text(pageTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(pageUpdated,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
                const SizedBox(height: 4),
                Text(pageIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant, height: 1.6)),
                const SizedBox(height: 20),
                ...sections.map((sec) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sec.$1,
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 13, color: cs.primary)),
                    const SizedBox(height: 8),
                    Text(sec.$2,
                        style: TextStyle(fontSize: 13,
                            color: cs.onSurfaceVariant, height: 1.65)),
                  ]))),
                const SizedBox(height: 24),
              ]),
            )),
    );
  }
}
