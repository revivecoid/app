import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../data/learning_gate.dart';

/// Consent wall for the training app.
///
/// Every photo a respondent uploads here becomes training data, so the consent
/// is a separate, explicit step that can be turned down and later withdrawn.
/// The database enforces the same rule (trg_guard_learning_submission_consent),
/// which is why this screen cannot simply be skipped by closing it.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _grant() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('record_consent', params: {
        'p_doc': 'ai_learning',
        'p_version': '1.0',
      });
      final ok = res is Map && res['ok'] == true;
      if (!ok) {
        setState(() => _message = 'Persetujuan belum tercatat. Coba lagi.');
        return;
      }
      await learningGate.refresh();
    } catch (_) {
      setState(() => _message = 'Persetujuan belum tercatat. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.workspaceLight,
      appBar: AppBar(
        title: const Text('Persetujuan penggunaan data'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => Supabase.instance.client.auth.signOut(),
            child: const Text('Keluar'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sebelum mulai',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Aplikasi ini mengumpulkan foto panel kendaraan dan hasil '
                  'penilaian Anda untuk melatih model deteksi kerusakan re-V.',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 12),
                const _Bullet('Foto dan penilaian disimpan di storage re-V.'),
                const _Bullet(
                    'Dipakai untuk pelatihan model, bukan untuk pemasaran.'),
                const _Bullet(
                    'Nama Anda ditampilkan di dasbor internal sebagai kontributor.'),
                const _Bullet(
                    'Persetujuan dapat dicabut kapan saja; data yang sudah '
                    'dikirim akan dikeluarkan dari pelatihan berikutnya.'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _grant,
                  child: Text(_busy ? 'Menyimpan…' : 'Saya setuju dan lanjutkan'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Tidak setuju, keluar'),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.fireRed),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 14, height: 1.5)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
