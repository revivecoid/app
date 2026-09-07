import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/widgets/rev_app_bar.dart';

class PrivacyPolicyScreen extends ConsumerStatefulWidget {
  const PrivacyPolicyScreen({super.key});
  @override ConsumerState<PrivacyPolicyScreen> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<PrivacyPolicyScreen> {
  bool _loading = true;
  Map<String, String> _s = {};
  String _get(String k, {required String fb}) => (_s[k] != null && _s[k]!.isNotEmpty) ? _s[k]! : fb;

  static const _defaultSections = [
    {'title': '1. Data yang Kami Kumpulkan',
     'body': 'Kami mengumpulkan informasi yang Anda berikan saat mendaftar (nama, email, nomor telepon), data kendaraan (merek, model, plat nomor), foto kerusakan yang Anda unggah, dan data penggunaan aplikasi secara anonim untuk meningkatkan layanan.'},
    {'title': '2. Penggunaan Data',
     'body': 'Data Anda digunakan untuk memproses estimasi kerusakan AI, menghubungkan Anda dengan bengkel partner terdekat, mengirimkan pembaruan status perbaikan, memproses pembayaran dan klaim asuransi, serta meningkatkan akurasi model AI kami.'},
    {'title': '3. Keamanan Data',
     'body': 'Seluruh data disimpan di infrastruktur Supabase dengan enkripsi AES-256. Kami tidak pernah menjual data pribadi Anda kepada pihak ketiga. Akses data dibatasi hanya untuk keperluan layanan yang Anda gunakan.'},
    {'title': '4. Berbagi Data dengan Pihak Ketiga',
     'body': 'Data minimal yang diperlukan dibagikan kepada bengkel partner yang Anda pilih untuk keperluan perbaikan, serta kepada perusahaan asuransi jika Anda mengajukan klaim. Semua mitra terikat perjanjian kerahasiaan data.'},
    {'title': '5. Hak Pengguna',
     'body': 'Anda berhak mengakses, memperbaiki, atau menghapus data pribadi Anda kapan saja melalui halaman profil. Untuk permintaan penghapusan akun, hubungi privacy@revive.co.id dan kami akan memprosesnya dalam 30 hari kerja.'},
    {'title': '6. Cookie dan Pelacakan',
     'body': 'Aplikasi web kami menggunakan cookie sesi untuk autentikasi dan preferensi tema. Tidak ada cookie pelacakan pihak ketiga atau iklan yang digunakan di platform kami.'},
    {'title': '7. Perubahan Kebijakan',
     'body': 'Kebijakan ini dapat diperbarui sewaktu-waktu. Perubahan material akan diberitahukan melalui email terdaftar Anda minimal 14 hari sebelum berlaku. Penggunaan layanan setelah tanggal efektif dianggap sebagai persetujuan atas perubahan tersebut.'},
    {'title': '8. Kontak',
     'body': 'Untuk pertanyaan terkait privasi data, hubungi kami di: privacy@revive.co.id atau melalui fitur Support di aplikasi kami.'},
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

    // Build sections: CMS overrides or defaults
    final sections = <Map<String, String>>[];
    for (int i = 0; i < _defaultSections.length; i++) {
      final title = _get('privacy_${i}_title', fb: _defaultSections[i]['title']!);
      final body  = _get('privacy_${i}_body', fb: _defaultSections[i]['body']!);
      sections.add({'title': title, 'body': body});
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReVAppBar(showBackButton: true,
        title: Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface))),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: cs.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text('LEGAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: 1.2))),
                const SizedBox(height: 10),
                Text(_get('privacy_page_title', fb: 'Kebijakan Privasi'),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(_get('privacy_updated', fb: 'Terakhir diperbarui: September 2026'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
                const SizedBox(height: 4),
                Text(_get('privacy_intro', fb: 'Kami berkomitmen untuk melindungi privasi dan keamanan data pribadi Anda. Kebijakan ini menjelaskan bagaimana Revive Indonesia mengumpulkan, menggunakan, dan melindungi informasi Anda.'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
                const SizedBox(height: 20),
                ...sections.map((sec) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sec['title']!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.primary)),
                    const SizedBox(height: 8),
                    Text(sec['body']!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.65)),
                  ]))),
                const SizedBox(height: 24),
              ]),
            )),
    );
  }
}
