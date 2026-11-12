// lib/core/services/r2_storage.dart
//
// Single entry point for photo storage. Every photo in re-V lives in the
// Cloudflare R2 bucket `revive-photos`; Supabase holds only the object key.
// The app never holds R2 credentials — short-lived presigned URLs come from
// the `r2-presign` edge function, which is the policy layer (own folder,
// master admin, partner member).
//
// Reads:  await R2Storage.signedUrl(key)
// Writes: final key = await R2Storage.uploadBytes(bytes, scope: R2Scope.opsJob)
//
// The scope decides where the object may land. The function derives the exact
// key, so a caller can never write outside its own scope.

import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum R2Scope {
  /// <uid>/learning/... — AI learning respondent photos
  learning,

  /// <uid>/estimator/... — customer damage photos for an estimate
  estimator,

  /// <uid>/... — payment proofs, partner application documents
  self,

  /// ops/<partnerId>/<jobId>/<stageKey>/... — ops milestone photos
  opsJob,

  /// partners/<partnerId>/docs/... and partners/<partnerId>/facility/...
  partnerDocs,
  partnerFacility,
}

class R2Storage {
  R2Storage._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// A short-lived GET URL for [key]. Returns null when the key is empty or
  /// the caller is not allowed to read it.
  static Future<String?> signedUrl(String? key) async {
    if (key == null || key.isEmpty) return null;
    if (key.startsWith('http://') || key.startsWith('https://')) return key;
    try {
      final res = await _client.functions.invoke(
        'r2-presign',
        body: {'action': 'read', 'key': key},
      );
      final data = res.data;
      if (data is Map && data['url'] is String) return data['url'] as String;
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[R2Storage] signedUrl failed for $key: $e');
      return null;
    }
  }

  /// Uploads [bytes] and returns the R2 key to persist in the database.
  ///
  /// [partnerId] and [jobId] are required for the ops and partner scopes;
  /// [stageKey] names the ops subfolder (e.g. vehicle_intake); [docType]
  /// names a partner document (ktp, nib, npwp, siup) or a facility slot.
  static Future<String> uploadBytes(
    Uint8List bytes, {
    required R2Scope scope,
    String? partnerId,
    String? jobId,
    String? stageKey,
    String? docType,
    String ext = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    final res = await _client.functions.invoke(
      'r2-presign',
      body: {
        'action': 'upload',
        'scope': scope.name,
        'partner_id': partnerId,
        'job_id': jobId,
        'stage_key': stageKey,
        'doc_type': docType,
        'ext': ext,
      },
    );
    final data = res.data;
    if (data is! Map || data['url'] is! String || data['key'] is! String) {
      throw Exception('Could not get an upload URL: ${data is Map ? data['error'] : data}');
    }

    final put = await http.put(
      Uri.parse(data['url'] as String),
      body: bytes,
      headers: {'Content-Type': contentType},
    );
    if (put.statusCode < 200 || put.statusCode >= 300) {
      throw Exception('Photo upload failed (${put.statusCode})');
    }
    return data['key'] as String;
  }
}
