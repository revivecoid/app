import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/image_compressor.dart';
import '../data/learning_models.dart';
import '../data/learning_repository.dart';
import 'review_screen.dart';

/// Pick photos, run the AI estimate, and save the submission.
/// Reviews happen on the next screen.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _maxPhotos = 6;

  final List<XFile> _photos = [];
  bool _busy = false;
  String? _message;
  String? _lastError;
  // Already-compressed bytes, kept so a retry does not re-encode the images.
  List<Uint8List>? _lastJpegs;
  int? _completedCount;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadCount();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    // Showing the build makes it possible to tell which APK is installed when
    // several test builds are circulating.
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'v${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      // PackageInfo is optional; never block the screen for it.
    }
  }

  Future<void> _loadCount() async {
    try {
      final n = await LearningRepository(Supabase.instance.client).completedCount();
      if (mounted) setState(() => _completedCount = n);
    } catch (_) {
      // A count is decoration; ignore failures.
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(_photos.isEmpty
            ? 'You will need to sign in again to continue contributing.'
            : 'You have ${_photos.length} unsent photo(s). They will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.signOut();
      // learningGate listens on onAuthStateChange and the router redirects to
      // /auth, so nothing further is needed here.
    } catch (e) {
      if (mounted) setState(() => _message = 'Sign out failed: $e');
    }
  }

  Future<void> _pick() async {
    final picked = (await ImagePicker().pickMultiImage(limit: _maxPhotos))
        .take(_maxPhotos)
        .toList();
    if (picked.isEmpty) return;

    // Drop duplicates: the same file picked twice would double-count in
    // training and silently bias the model. Compare the compressed bytes,
    // since those are what actually get uploaded. Keep the XFile alongside its
    // bytes so the two lists can never drift apart.
    final kept = <({XFile file, Uint8List bytes})>[];
    final seen = <String>{};
    for (final f in picked) {
      final bytes = await ImageCompressor.compressImage(f);
      if (seen.add(sha256.convert(bytes).toString())) {
        kept.add((file: f, bytes: bytes));
      }
    }
    final skipped = picked.length - kept.length;

    setState(() {
      _photos
        ..clear()
        ..addAll(kept.map((k) => k.file));
      _lastJpegs = kept.map((k) => k.bytes).toList();
      _lastError = null;
      _message = skipped > 0
          ? '$skipped duplicate photo(s) skipped. ${kept.length} ready.'
          : null;
    });
  }

  Future<void> _analyse() async {
    if (_photos.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
      _lastError = null;
    });

    try {
      final repo = LearningRepository(Supabase.instance.client);

      // Reuse the bytes captured at pick time on retry; only compress once.
      final jpegs = _lastJpegs ??= [
        for (final f in _photos) await ImageCompressor.compressImage(f),
      ];
      final paths = await repo.uploadPhotos(jpegs);
      final urls = await repo.signedUrls(paths);

      final result = await repo.analyse(
        photoUrls: urls,
        selectedPanels: const [],
      );
      // Defensive: a non-object structuredData used to throw an uncaught
      // "List<dynamic> is not a subtype of Map<String, dynamic>?" and surface
      // as a raw type error to the user. Accept a list by taking its first
      // map, and treat anything else as "no panels detected".
      final raw = result['structuredData'];
      final Map<String, dynamic>? structured = switch (raw) {
        final Map<String, dynamic> m => m,
        final Map m => Map<String, dynamic>.from(m),
        final List l => l.whereType<Map>().isEmpty
            ? null
            : Map<String, dynamic>.from(l.whereType<Map>().first),
        _ => null,
      };
      final panels = parseDamagedPanels(structured);

      final submissionId = await repo.saveSubmission(
        photoPaths: paths,
        selectedPanels: const [],
        aiResult: structured ?? {},
      );

      if (!mounted) return;
      if (panels.isEmpty) {
        setState(() {
          _photos.clear();
          _lastJpegs = null;
          _message = 'No panels flagged. Submission saved for training.';
        });
        _loadCount();
        return;
      }

      _photos.clear();
      _lastJpegs = null;
      context.push(
        '/review',
        extra: ReviewArgs(submissionId: submissionId, panels: panels),
      ).then((_) {
        if (mounted) {
          setState(() {});
          _loadCount();
        }
      });
    } catch (e) {
      // Keep the photos and the compressed bytes so Retry costs one tap
      // instead of reselecting every image.
      setState(() {
        _lastError = '$e';
        _message = 'Analysis failed. Check your connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.workspaceLight,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/respondent_logo.png', height: 26),
            const SizedBox(width: 8),
            const Text('New scan'),
          ],
        ),
        actions: [
          if (_completedCount != null && _completedCount! > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '$_completedCount confirmed',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (v) {
              if (v == 'signout') _signOut();
            },
            itemBuilder: (_) => [
              if (_version.isNotEmpty)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(_version,
                      style: const TextStyle(fontSize: 12)),
                ),
              const PopupMenuItem<String>(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add up to $_maxPhotos photos of the damaged vehicle. '
              'You will confirm each detected panel and part on the next screen.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_photos.isEmpty
                  ? 'Choose photos'
                  : '${_photos.length} selected, change'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_busy || _photos.isEmpty) ? null : _analyse,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_lastError == null ? 'Run AI estimate' : 'Retry estimate'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: const TextStyle(color: AppColors.daysGray)),
            ],
            if (_lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                _lastError!.length > 200
                    ? '${_lastError!.substring(0, 200)}…'
                    : _lastError!,
                style: const TextStyle(fontSize: 11, color: AppColors.daysGray),
              ),
            ],
            if (_version.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                _version,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: AppColors.daysGray),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
