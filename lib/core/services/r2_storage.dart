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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum R2Scope {
  /// <uid>/learning/... — AI learning respondent photos
  learning,

  /// <uid>/estimator/... — customer damage photos for an estimate
  estimator,

  /// <uid>/... — payment proofs
  self,

  /// <uid>/partner-applications/<docType>/... — documents and facility photos
  /// for an application filed before a partner row exists.
  partnerApplication,

  /// ops/<partnerId>/<jobId>/<stageKey>/... — ops milestone photos
  opsJob,

  /// partners/<partnerId>/docs/... and partners/<partnerId>/facility/...
  partnerDocs,
  partnerFacility,
}

class R2Storage {
  R2Storage._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Set once a direct browser PUT has been refused. The bucket has no CORS
  /// policy, so every later upload skips the doomed attempt and goes straight
  /// to the relay. Resets when the app restarts, which re-probes for free.
  static bool _directUploadBlocked = false;

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
    final scopeFields = <String, dynamic>{
      'scope': scope.name,
      'partner_id': partnerId,
      'job_id': jobId,
      'stage_key': stageKey,
      'doc_type': docType,
      'ext': ext,
    };

    // Direct path: presign here, PUT from the client. Works on native builds
    // and on web once the bucket carries a CORS policy.
    if (!_directUploadBlocked) {
      try {
        final res = await _client.functions.invoke(
          'r2-presign',
          body: {'action': 'upload', ...scopeFields},
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
        if (put.statusCode >= 200 && put.statusCode < 300) {
          return data['key'] as String;
        }
        if (!kIsWeb) throw Exception('Photo upload failed (${put.statusCode})');
      } catch (e) {
        // On web the usual cause is a CORS preflight the bucket refuses, which
        // reaches Dart as `ClientException: Failed to fetch`. Native has no
        // preflight, so a failure there is real and must surface.
        if (!kIsWeb) rethrow;
        _directUploadBlocked = true;
      }
    }

    // Relay path: the function holds the R2 credentials and does the PUT, so
    // the browser never talks to the bucket and CORS cannot block it.
    final relay = await _client.functions.invoke(
      'r2-presign',
      body: {
        'action': 'uploadProxy',
        ...scopeFields,
        'content_type': contentType,
        'content_base64': base64Encode(bytes),
      },
    );
    final relayed = relay.data;
    if (relayed is! Map || relayed['key'] is! String) {
      throw Exception('Photo upload failed: ${relayed is Map ? relayed['error'] : relayed}');
    }
    return relayed['key'] as String;
  }
}
