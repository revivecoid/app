// lib/core/utils/storage_url.dart
//
// Helper terpusat untuk menghasilkan URL foto. Semua foto ada di bucket
// Cloudflare R2 `revive-photos`; URL bertanda tangan (presigned) diminta ke
// edge function `r2-presign`. Lihat core/services/r2_storage.dart.
//
// Kode yang sebelumnya memanggil getPublicUrl() atau createSignedUrl() harus
// memakai helper ini.

import '../services/r2_storage.dart';

const int _kDefaultTtlSeconds = 3600; // 1 jam (TTL diatur oleh r2-presign)

/// Menghasilkan signed URL untuk objek di bucket revive-photos (R2).
/// Mengembalikan null bila fileKey kosong atau ada error.
Future<String?> signedPhotoUrl(
  String? fileKey, {
  int ttlSeconds = _kDefaultTtlSeconds,
}) async {
  if (fileKey == null || fileKey.isEmpty) return null;
  return R2Storage.signedUrl(fileKey);
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
