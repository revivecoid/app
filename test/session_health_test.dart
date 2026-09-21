import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:re_v/core/utils/session_health.dart';

/// A session whose access token is dated in the future cannot recover on its
/// own: `iat` and `exp` are shifted forward together, so the client's expiry
/// arithmetic still considers the token valid and never refreshes it. PostgREST,
/// meanwhile, rejects every request with 401 / PGRST303. These tests pin the
/// detection that decides when to force a refresh.
String makeJwt({required int iat, required int exp, String sub = 'user-1'}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'iat': iat, 'exp': exp, 'sub': sub})}.sig';
}

void main() {
  final now = DateTime.utc(2026, 9, 21, 8, 30, 0);
  final nowEpoch = now.millisecondsSinceEpoch ~/ 1000;

  group('decodeJwtPayload', () {
    test('reads the claims from a well-formed token', () {
      final payload = decodeJwtPayload(makeJwt(iat: nowEpoch, exp: nowEpoch + 3600));
      expect(payload?['sub'], 'user-1');
      expect(payload?['iat'], nowEpoch);
    });

    test('handles base64url payloads that need padding', () {
      // A payload whose encoded length is not a multiple of 4.
      final payload = decodeJwtPayload(makeJwt(iat: nowEpoch, exp: nowEpoch + 3600, sub: 'a'));
      expect(payload?['sub'], 'a');
    });

    test('returns null for a token that is not three segments', () {
      expect(decodeJwtPayload('not-a-jwt'), isNull);
      expect(decodeJwtPayload('a.b'), isNull);
    });

    test('returns null when the payload is not valid base64 json', () {
      expect(decodeJwtPayload('aaa.!!!not-base64!!!.sig'), isNull);
    });
  });

  group('jwtIssuedAt', () {
    test('converts the iat claim to a UTC instant', () {
      expect(jwtIssuedAt(makeJwt(iat: nowEpoch, exp: nowEpoch + 3600)), now);
    });

    test('is null when iat is absent', () {
      final header = base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '');
      final body = base64Url.encode(utf8.encode('{"exp":123}')).replaceAll('=', '');
      expect(jwtIssuedAt('$header.$body.sig'), isNull);
    });
  });

  group('isTokenFutureDated', () {
    test('a normal token issued now is NOT future-dated', () {
      expect(isTokenFutureDated(makeJwt(iat: nowEpoch, exp: nowEpoch + 3600), now: now), isFalse);
    });

    test('a token issued just before now is NOT future-dated', () {
      expect(isTokenFutureDated(makeJwt(iat: nowEpoch - 60, exp: nowEpoch + 3600), now: now), isFalse);
    });

    test('a token within PostgREST leeway is NOT flagged (server would still accept)', () {
      // PostgREST tolerates 30s of skew; inside that, no refresh is warranted.
      expect(isTokenFutureDated(makeJwt(iat: nowEpoch + 20, exp: nowEpoch + 3600), now: now), isFalse);
    });

    test('a token just past the leeway IS flagged', () {
      // 30s leeway + 15s margin means anything beyond +45s is clearly rejected.
      expect(isTokenFutureDated(makeJwt(iat: nowEpoch + 60, exp: nowEpoch + 3600), now: now), isTrue);
    });

    test('the observed production case IS flagged', () {
      // Real symptom: a token minted minutes ahead of the server clock, with exp
      // shifted forward to match, which is why it never refreshed itself.
      expect(isTokenFutureDated(makeJwt(iat: nowEpoch + 300, exp: nowEpoch + 3900), now: now), isTrue);
    });

    test('a very stale token is NOT future-dated (a different failure needs a different fix)', () {
      expect(isTokenFutureDated(makeJwt(iat: nowEpoch - 7200, exp: nowEpoch - 3600), now: now), isFalse);
    });

    test('an undecodable token is NOT flagged (do not guess)', () {
      expect(isTokenFutureDated('garbage', now: now), isFalse);
      expect(isTokenFutureDated('', now: now), isFalse);
    });
  });

  group('isFutureDatedTokenError', () {
    test('matches the PostgREST code', () {
      expect(
        isFutureDatedTokenError(
          const PostgrestException(message: 'JWT issued at future', code: 'PGRST303'),
        ),
        isTrue,
      );
    });

    test('matches a 401 whose message names the problem', () {
      expect(
        isFutureDatedTokenError(
          const PostgrestException(message: 'JWT issued at future', code: '401'),
        ),
        isTrue,
      );
    });

    test('does NOT match an unrelated PostgREST error', () {
      expect(
        isFutureDatedTokenError(
          const PostgrestException(message: 'permission denied for table repair_jobs', code: '42501'),
        ),
        isFalse,
      );
    });

    test('does NOT match a plain 401 without the future-dating message', () {
      // An expired or missing session needs a different remedy, so it must not
      // be funnelled into the refresh path.
      expect(
        isFutureDatedTokenError(const PostgrestException(message: 'JWT expired', code: '401')),
        isFalse,
      );
    });

    test('does not match non-PostgREST errors', () {
      expect(isFutureDatedTokenError(Exception('network down')), isFalse);
      expect(isFutureDatedTokenError('a string'), isFalse);
    });
  });
}
