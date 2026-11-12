import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/r2_storage.dart';
import 'learning_models.dart';

/// Photos live in Cloudflare R2. The app only holds short-lived presigned URLs
/// from the r2-presign edge function and stores the R2 key in Supabase.
class LearningRepository {
  LearningRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  Future<void> createRespondentProfile(String fullName) async {
    await _client.from('ai_learning_respondents').insert({
      'user_id': _uid,
      'full_name': fullName.trim(),
    });
  }

  /// Uploads each JPEG to R2 through a presigned PUT. Returns the R2 keys.
  Future<List<String>> uploadPhotos(List<Uint8List> jpegs) async {
    final keys = <String>[];
    for (final bytes in jpegs) {
      keys.add(await R2Storage.uploadBytes(bytes, scope: R2Scope.learning));
    }
    return keys;
  }

  /// Returns a short-lived read URL for each R2 key.
  Future<List<String>> signedUrls(List<String> keys) async {
    final urls = <String>[];
    for (final key in keys) {
      final url = await R2Storage.signedUrl(key);
      if (url == null) throw Exception('Could not read photo $key');
      urls.add(url);
    }
    return urls;
  }

  /// Calls vision-estimation. Throws if the function reports failure.
  Future<Map<String, dynamic>> analyse({
    required List<String> photoUrls,
    required List<String> selectedPanels,
  }) async {
    final res = await _client.functions.invoke(
      'vision-estimation',
      body: {
        'photoUrls': photoUrls,
        'photoUrl': photoUrls.first,
        'selectedPanels': selectedPanels,
      },
    );
    final data = res.data;
    if (data is! Map<String, dynamic> || data['success'] != true) {
      final msg = data is Map<String, dynamic> ? data['error'] : null;
      throw Exception(msg?.toString() ?? 'Analysis failed');
    }
    return data;
  }

  Future<String> saveSubmission({
    required List<String> photoPaths,
    required List<String> selectedPanels,
    required Map<String, dynamic> aiResult,
  }) async {
    final row = await _client
        .from('ai_learning_submissions')
        .insert({
          'respondent_id': _uid,
          'photo_paths': photoPaths,
          'selected_panels': selectedPanels,
          'ai_result': aiResult,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Saves every panel and part verdict for one submission in two inserts.
  /// Null verdicts must be filtered out by the caller.
  Future<void> saveReviews({
    required String submissionId,
    required List<LearningPanel> panels,
    required Map<String, bool> panelVerdicts,
    required Map<String, bool> partVerdicts,
  }) async {
    final panelRows = [
      for (final p in panels)
        {
          'submission_id': submissionId,
          'panel_name': p.name,
          'ai_severity': p.severity,
          'verdict': panelVerdicts[p.name],
        },
    ];

    final partRows = [
      for (final p in panels)
        for (final part in p.parts)
          {
            'submission_id': submissionId,
            'panel_name': p.name,
            'part_name': part.name,
            'verdict': partVerdicts[partKey(p.name, part.name)],
          },
    ];

    await _client.from('ai_learning_panel_reviews').insert(panelRows);
    if (partRows.isNotEmpty) {
      await _client.from('ai_learning_part_reviews').insert(partRows);
    }
  }
}

/// Stable key for a part inside a panel. The separator is unlikely to appear
/// in AI-generated names.
String partKey(String panel, String part) => '$panel::$part';
