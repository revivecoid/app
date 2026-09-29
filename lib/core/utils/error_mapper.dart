import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized error mapping (UX-09)
/// Maps raw exceptions (especially PostgrestException) to user-friendly messages.
String mapRawErrorToUserMessage(Object e) {
  if (e is PostgrestException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('not found')) {
      return 'Data tidak ditemukan. Silakan periksa kembali.';
    } else if (msg.contains('duplicate key')) {
      return 'Data sudah terdaftar sebelumnya.';
    } else if (msg.contains('row-level security')) {
      return 'Anda tidak memiliki akses ke data ini.';
    } else if (msg.contains('jwt') || msg.contains('token')) {
      return 'Sesi Anda telah berakhir. Silakan login kembali.';
    } else if (msg.contains('violates foreign key')) {
      return 'Terdapat data terkait yang tidak valid.';
    }
    return 'Gagal menyimpan data. Pastikan isian Anda benar atau coba lagi nanti.';
  } else if (e is AuthException) {
    return 'Gagal masuk: ${e.message}';
  } else if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
    return 'Gagal terhubung ke server. Periksa koneksi internet Anda.';
  } else if (e.toString().contains('Estimation Engine Fallback')) {
    return 'Mesin AI sedang sibuk. Kami akan melakukan estimasi manual.';
  }
  return 'Terjadi kesalahan sistem. Silakan coba beberapa saat lagi.';
}
