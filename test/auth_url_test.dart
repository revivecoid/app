import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/core/utils/auth_url.dart';

/// The app runs the hash URL strategy, so an OAuth/PKCE callback arrives either
/// as `/?code=...#/auth/callback` or as `/#/auth/callback?code=...` depending on
/// how Supabase appends its parameters. readAuthCode must find the code in both
/// positions, and must not invent one when there is none.
void main() {
  group('readAuthCode', () {
    test('finds the code inside the hash fragment (after the router path)', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/#/auth/callback?code=abc123')),
        'abc123',
      );
    });

    test('finds the code in the query string', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/?code=abc123#/auth/callback')),
        'abc123',
      );
    });

    test('prefers the query string when both are present', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/?code=fromQuery#/auth/callback?code=fromFragment')),
        'fromQuery',
      );
    });

    test('reads the code alongside a returnTo parameter', () {
      expect(
        readAuthCode(Uri.parse(
            'https://revive.co.id/#/auth/callback?returnTo=%2Fadmin-central&code=xyz789')),
        'xyz789',
      );
    });

    test('works for the local dev origin', () {
      expect(
        readAuthCode(Uri.parse('http://127.0.0.1:3001/#/auth/callback?code=devcode')),
        'devcode',
      );
    });

    test('returns null on a plain page load', () {
      expect(readAuthCode(Uri.parse('https://revive.co.id/')), isNull);
      expect(readAuthCode(Uri.parse('https://revive.co.id/#/')), isNull);
    });

    test('returns null when the callback carries no code', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/#/auth/callback')),
        isNull,
      );
    });

    test('returns null for an empty code', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/#/auth/callback?code=')),
        isNull,
      );
    });

    test('returns null for non-code auth params (error responses)', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/#/auth/callback?error=access_denied')),
        isNull,
      );
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/?error=access_denied')),
        isNull,
      );
    });

    test('does not mistake a fragment value for the code param', () {
      expect(
        readAuthCode(Uri.parse('https://revive.co.id/#/auth/callback?returnTo=code')),
        isNull,
      );
    });
  });
}
