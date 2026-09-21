/// Heals a session whose access token is dated in the future.
///
/// PostgREST rejects such a token outright with HTTP 401 / `PGRST303`
/// ("JWT issued at future") before any policy runs, so every read and write on
/// the client fails with a bare PostgrestException while the app still believes
/// it is signed in. Observed in production: a partner staff member could not
/// open a job's milestone list.
///
/// A future-dated token cannot expire its way out of the problem by itself. The
/// `iat` and `exp` claims are both shifted forward, so `exp` also sits in the
/// future and supabase_flutter's expiry arithmetic concludes the token is still
/// valid — it never refreshes on its own, and the window only closes when the
/// client eventually decides to refresh for an unrelated reason.
///
/// Refreshing fixes it: the replacement access token is minted at refresh time,
/// so its `iat` is the real current time. That makes this self-healing on the
/// next page load rather than something a user has to clear storage for.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST allows this much clock skew before calling a token future-dated.
/// Kept as the same value so we only step in when the server would actually
/// reject the token (plus the small guard in [isTokenFutureDated]).
const _postgrestLeeway = Duration(seconds: 30);

/// Extra margin so we heal shortly before PostgREST would refuse the request.
const _safetyMargin = Duration(seconds: 15);

/// Decodes a JWT's payload WITHOUT verifying its signature.
///
/// Safe only for reading harmless metadata such as `iat`, which is all this is
/// used for. Never use the result to make an authorization decision — an
/// unverified payload is attacker-controlled input.
Map<String, dynamic>? decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;

  var segment = parts[1].replaceAll('-', '+').replaceAll('_', '/');
  final remainder = segment.length % 4;
  if (remainder != 0) segment = segment.padRight(segment.length + (4 - remainder), '=');

  try {
    final decoded = utf8.decode(base64.decode(segment));
    final json = jsonDecode(decoded);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null; // Not a decodable payload — treat as unknown, never as valid.
  }
}

/// The token's `iat` as UTC, or null when it is missing or unparseable.
DateTime? jwtIssuedAt(String token) {
  final iat = decodeJwtPayload(token)?['iat'];
  if (iat is int) return DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true);
  if (iat is num) return DateTime.fromMillisecondsSinceEpoch((iat * 1000).round(), isUtc: true);
  return null;
}

/// Whether [token] carries an `iat` far enough ahead of [now] that PostgREST
/// would reject the request.
///
/// Returns false for a token we cannot read: an unreadable token is a different
/// failure with a different remedy, and forcing a refresh on it would be guesswork.
bool isTokenFutureDated(String token, {DateTime? now}) {
  final issuedAt = jwtIssuedAt(token);
  if (issuedAt == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return issuedAt.isAfter(reference.add(_postgrestLeeway + _safetyMargin));
}

/// Guards against overlapping heals: a refresh fires onAuthStateChange, which
/// would otherwise re-enter and queue another refresh.
bool _healing = false;

/// Refreshes the session when, and only when, its token is future-dated.
///
/// Safe to call on every startup and on every auth state change. Failures are
/// swallowed: this is a recovery path, and a failed heal must not break launch.
/// Returns true when a refresh was actually performed.
Future<bool> healFutureDatedSession(SupabaseClient client) async {
  if (_healing) return false;

  final token = client.auth.currentSession?.accessToken;
  if (token == null || !isTokenFutureDated(token)) return false;

  _healing = true;
  try {
    debugPrint('[SessionHealth] Access token is future-dated; refreshing the session.');
    await client.auth.refreshSession();
    return true;
  } catch (e) {
    debugPrint('[SessionHealth] Could not refresh a future-dated session: $e');
    return false;
  } finally {
    _healing = false;
  }
}

/// Whether [error] is a PostgREST rejection of a future-dated token.
///
/// Matched on the message rather than the status code alone, because 401 also
/// covers a genuinely expired token and a missing session, which need opposite
/// remedies (a refresh is pointless once the refresh token is gone).
bool isFutureDatedTokenError(Object error) {
  if (error is! PostgrestException) return false;
  if (error.code == 'PGRST303') return true;
  final message = error.message.toLowerCase();
  return error.code == '401' && message.contains('issued at future');
}

/// Recovers the session and runs [operation] once more when it failed because
/// the token was future-dated. Any other error is rethrown untouched.
///
/// Wrap post-login reads that a user must not be locked out of: the first call
/// surfaces the failure, the heal replaces the token, and the retry succeeds
/// without the caller needing to know any of this happened.
Future<T> retryOnStaleToken<T>(
  SupabaseClient client,
  Future<T> Function() operation,
) async {
  try {
    return await operation();
  } catch (error) {
    if (!isFutureDatedTokenError(error)) rethrow;
    if (!await healFutureDatedSession(client)) rethrow;
    return await operation();
  }
}

/// Keeps the session healthy for the whole app lifetime.
///
/// Heals once immediately (a token restored from storage at startup) and again
/// whenever auth state changes, which is when a freshly surfaced bad token can
/// appear. Returns the subscription so callers can cancel it.
StreamSubscription<AuthState> watchSessionHealth(SupabaseClient client) {
  unawaited(healFutureDatedSession(client));
  return client.auth.onAuthStateChange.listen((data) {
    final token = data.session?.accessToken;
    if (token != null && isTokenFutureDated(token)) {
      unawaited(healFutureDatedSession(client));
    }
  });
}
