import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Anonymous ("guest") sessions.
///
/// Estimating is public by design: a visitor picks panels, uploads photos and
/// gets a price before being asked for anything. The vision pipeline itself is
/// not public — `vision-estimation` requires a valid JWT, the photo bucket is
/// private, and the upload policy scopes objects to `<auth.uid()>/...`. A guest
/// therefore needs a real session, just not an identified one.
///
/// Supabase anonymous sign-in provides exactly that: an `authenticated` JWT
/// whose user has `isAnonymous == true` and no email. It is a genuine account
/// row, so there is nothing to clean up when the visitor leaves.
class GuestSession {
  GuestSession._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// A session is present, but bound to no real identity.
  static bool isGuest([User? user]) =>
      (user ?? _sb.auth.currentUser)?.isAnonymous ?? false;

  /// A session exists at all — a signed-in customer or a guest.
  static bool get hasSession => _sb.auth.currentSession != null;

  /// The id to own this visitor's data, signing a guest in when nobody is.
  ///
  /// Returns null only when anonymous sign-in is unavailable (disabled in the
  /// project, or offline), and the caller must then fall back to the login
  /// screen.
  static Future<String?> ensure([User? user]) async {
    final existing = user ?? _sb.auth.currentUser;
    if (existing != null) return existing.id;
    try {
      final res = await _sb.auth.signInAnonymously();
      return res.user?.id;
    } on AuthException catch (e) {
      debugPrint('[GuestSession] anonymous sign-in unavailable: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[GuestSession] anonymous sign-in failed: $e');
      return null;
    }
  }
}
