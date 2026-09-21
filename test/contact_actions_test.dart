import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/core/utils/contact_actions.dart';

/// Turning what a customer typed into a link that actually opens the right chat.
///
/// The customer sets this up, so the app has no control over the form: numbers
/// arrive as `0812...`, `+62 812-...`, `62812...`, or already stripped. All four
/// are the same line, and only the digits-only international form works in a
/// `wa.me` link — `wa.me/0812...` silently opens WhatsApp on the wrong screen,
/// which is worse than showing no link at all.
void main() {
  group('normaliseIndonesianPhone — the local form customers actually type', () {
    test('08xx becomes 628xx', () {
      expect(normaliseIndonesianPhone('081234567890'), '6281234567890');
    });

    test('a +62 number is not given a second country code', () {
      expect(normaliseIndonesianPhone('+62 812-3456-7890'), '6281234567890');
    });

    test('an already-normalised number is returned unchanged', () {
      expect(normaliseIndonesianPhone('6281234567890'), '6281234567890');
    });

    test('a bare national number gets the country code', () {
      // Some customers drop the leading zero entirely.
      expect(normaliseIndonesianPhone('81234567890'), '6281234567890');
    });
  });

  group('separators and noise', () {
    test('spaces, dashes, dots and parens are all stripped', () {
      expect(normaliseIndonesianPhone('(0812) 3456.7890'), '6281234567890');
      expect(normaliseIndonesianPhone('0812 3456 7890'), '6281234567890');
      expect(normaliseIndonesianPhone('0812-3456-7890'), '6281234567890');
    });

    test('nothing usable yields an empty string rather than a broken link', () {
      expect(normaliseIndonesianPhone(null), '');
      expect(normaliseIndonesianPhone(''), '');
      expect(normaliseIndonesianPhone('   '), '');
      expect(normaliseIndonesianPhone('not a number'), '');
    });

    test('an explicitly foreign + number is not given an Indonesian code', () {
      // Re-pointing a +1 number at an Indonesian line would be worse than
      // showing it unchanged.
      expect(normaliseIndonesianPhone('+1 555 0100'), '15550100');
    });
  });

  group('ContactTarget.resolve — which channel is offered', () {
    test('a phone prefers WhatsApp, because that is how customers are reachable', () {
      final t = ContactTarget.resolve(jobContactPhone: '081234567890');
      expect(t, isNotNull);
      expect(t!.channel, ContactChannel.whatsapp);
      expect(t.uri.toString(), 'https://wa.me/6281234567890');
    });

    test('the job snapshot beats the profile phone', () {
      // Both numbers normalise to 6281200000001 / ...0002, so this asserts the
      // precedence rather than the formatting.
      final t = ContactTarget.resolve(
        jobContactPhone: '081200000001',
        profilePhone: '081200000002',
      );
      expect(t!.uri.toString(), 'https://wa.me/6281200000001');
      expect(t.display, '081200000001');
    });

    test('the profile phone is used when the job has none', () {
      // Every job booked before the snapshot column existed is in this state.
      final t = ContactTarget.resolve(profilePhone: '081200000002');
      expect(t!.uri.toString(), 'https://wa.me/6281200000002');
    });

    test('an empty job phone falls through rather than winning', () {
      final t = ContactTarget.resolve(
        jobContactPhone: '   ',
        profilePhone: '081200000002',
      );
      expect(t!.uri.toString(), 'https://wa.me/6281200000002');
    });

    test('email is offered only when no phone exists', () {
      final t = ContactTarget.resolve(profileEmail: 'itho@itho.eu.org');
      expect(t!.channel, ContactChannel.email);
      // Dart's Uri leaves the @ bare in a path — asserting the encoded form would
      // be asserting a bug that is not there.
      expect(t.uri.toString(), 'mailto:itho@itho.eu.org');
    });

    test('a phone with an email present still prefers the phone', () {
      final t = ContactTarget.resolve(
        profilePhone: '081234567890',
        profileEmail: 'itho@itho.eu.org',
      );
      expect(t!.channel, ContactChannel.whatsapp);
    });

    test('nothing at all resolves to null so the UI can say so plainly', () {
      expect(ContactTarget.resolve(), isNull);
      expect(ContactTarget.resolve(jobContactPhone: '', profilePhone: ''), isNull);
    });

    test('a malformed email is refused instead of producing a dead link', () {
      expect(ContactTarget.resolve(profileEmail: 'not-an-email'), isNull);
    });
  });

  group('callUri — dialling instead of WhatsApp', () {
    test('is offered for a phone, in E.164 form', () {
      final t = ContactTarget.resolve(jobContactPhone: '081234567890');
      expect(t!.callUri.toString(), 'tel:+6281234567890');
    });

    test('is NOT offered for an email, so no dialler opens by mistake', () {
      final t = ContactTarget.resolve(profileEmail: 'itho@itho.eu.org');
      expect(t!.callUri, isNull);
    });
  });
}
