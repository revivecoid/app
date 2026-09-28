// lib/core/utils/storage_url.dart
//
// Helper terpusat untuk menghasilkan URL foto dari bucket private revive-photos.
// SEC-04/PRIV-01: Bucket kini private — gunakan signedUrl, bukan publicUrl.
//
// Semua kode yang sebelumnya memanggil getPublicUrl() harus beralih ke helper ini.

import 'package:supabase_flutter/supabase_flutter.dart';

const String _kBucket = 'revive-photos';
const int _kDefaultTtlSeconds = 3600; // 1 jam

/// Menghasilkan signed URL untuk objek di bucket revive-photos.
/// Mengembalikan null bila fileKey kosong atau ada error.
Future<String?> signedPhotoUrl(
  String? fileKey, {
  int ttlSeconds = _kDefaultTtlSeconds,
}) async {
  if (fileKey == null || fileKey.isEmpty) return null;
  try {
    return await Supabase.instance.client.storage
        .from(_kBucket)
        .createSignedUrl(fileKey, ttlSeconds);
  } catch (e) {
    debugPrintStorageError('signedPhotoUrl', fileKey, e);
    return null;
  }
}

/// Menghasilkan banyak signed URL sekaligus.
/// Map dari fileKey → signedUrl (null bila gagal).
Future<Map<String, String?>> signedPhotoUrls(
  List<String> fileKeys, {
  int ttlSeconds = _kDefaultTtlSeconds,
}) async {
  final results = <String, String?>{};
  for (final key in fileKeys) {
    results[key] = await signedPhotoUrl(key, ttlSeconds: ttlSeconds);
  }
  return results;
}

/// Debug log untuk error storage tanpa crash.
void debugPrintStorageError(String caller, String fileKey, Object error) {
  // ignore: avoid_print
  print('[StorageURL] $caller: error pada $fileKey — $error');
}
