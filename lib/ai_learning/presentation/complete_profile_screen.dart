import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../data/learning_gate.dart';
import '../data/learning_repository.dart';

/// Shown when the account is signed in but has no respondent profile yet,
/// for example after email confirmation or an account created in the client app.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _busy = false;
  String? _message;

  /// The respondent is about to contribute photos and estimates to the model
  /// training set, so the consent has to be explicit and has to be recorded
  /// before the profile exists. Without this the training data had no owner
  /// and no way to withdraw.
  bool _consentGiven = false;

  @override
  void initState() {
    super.initState();
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    // Google returns the name under full_name, name, or given/family name
    // depending on the scopes granted — fall back so the field is not blank.
    final name = meta?['full_name'] ??
        meta?['name'] ??
        [meta?['given_name'], meta?['family_name']]
            .whereType<Object>()
            .join(' ');
    _name = TextEditingController(text: (name as String?)?.trim() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_consentGiven) {
      setState(() => _message =
          'Centang persetujuan penggunaan data untuk pelatihan model AI.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await LearningRepository(Supabase.instance.client)
          .createRespondentProfile(_name.text);
      // Record the consent next to the data it covers.
      await Supabase.instance.client.rpc('record_consent', params: {
        'p_doc': 'ai_learning',
        'p_version': '1.0',
      });
      await learningGate.refresh();
    } catch (_) {
      setState(() => _message = 'Profil belum tersimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.workspaceLight,
      appBar: AppBar(
        title: const Text('Lengkapi profil Anda'),
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
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nama lengkap'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.workspaceLight.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.fireRed.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _consentGiven,
                          onChanged: (v) =>
                              setState(() => _consentGiven = v ?? false),
                          title: const Text(
                            'Saya setuju foto dan estimasi saya dipakai untuk '
                            'meningkatkan model deteksi kerusakan re-V.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Data dipakai untuk pelatihan model, tidak untuk '
                          'pemasaran. Persetujuan ini tercatat dan dapat '
                          'dicabut kapan saja lewat pengaturan privasi.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Menyimpan…' : 'Lanjutkan'),
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
      ),
    );
  }
}
