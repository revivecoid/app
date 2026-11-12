import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _pick() async {
    final picked = await ImagePicker().pickMultiImage(limit: _maxPhotos);
    if (picked.isEmpty) return;
    setState(() {
      _photos
        ..clear()
        ..addAll(picked.take(_maxPhotos));
      _message = null;
    });
  }

  Future<void> _analyse() async {
    if (_photos.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final repo = LearningRepository(Supabase.instance.client);

      final jpegs = [
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
          _message = 'No panels flagged. Submission saved for training.';
        });
        return;
      }

      _photos.clear();
      context.push(
        '/review',
        extra: ReviewArgs(submissionId: submissionId, panels: panels),
      );
    } catch (e) {
      setState(() => _message = 'Analysis failed: $e');
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
      ),
      body: Padding(
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
                  : const Text('Run AI estimate'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: const TextStyle(color: AppColors.daysGray)),
            ],
          ],
        ),
      ),
    );
  }
}
