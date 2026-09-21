import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/core/utils/customer_contact.dart';

/// How the valet reaches a customer. The job's own number is the one confirmed
/// for that booking and must win; the profile is only a fallback, and email is
/// the last resort because nothing on file is worse than something.
void main() {
  group('precedence', () {
    test('the job contact wins when all three are present', () {
      final c = CustomerContact.resolve(
        jobContactPhone: '0812-job',
        profilePhone: '0812-profile',
        profileEmail: 'a@b.com',
      );
      expect(c.value, '0812-job');
      expect(c.isPhone, isTrue);
      expect(c.isEmpty, isFalse);
    });

    test('the profile phone is used when the job has none', () {
      // Every job booked before the snapshot column existed is in this state.
      final c = CustomerContact.resolve(
        profilePhone: '0812-profile',
        profileEmail: 'a@b.com',
      );
      expect(c.value, '0812-profile');
      expect(c.isPhone, isTrue);
    });

    test('email is the last resort', () {
      final c = CustomerContact.resolve(profileEmail: 'a@b.com');
      expect(c.value, 'a@b.com');
      expect(c.isPhone, isFalse, reason: 'must not render an email with a phone icon');
    });
  });

  group('empty values never win', () {
    test('an empty job contact falls through to the profile phone', () {
      final c = CustomerContact.resolve(
        jobContactPhone: '',
        profilePhone: '0812-profile',
        profileEmail: 'a@b.com',
      );
      expect(c.value, '0812-profile');
    });

    test('whitespace-only values are treated as absent', () {
      final c = CustomerContact.resolve(
        jobContactPhone: '   ',
        profilePhone: '\t',
        profileEmail: '  a@b.com  ',
      );
      expect(c.value, 'a@b.com');
    });

    test('a null profile yields an explicit empty result', () {
      final c = CustomerContact.resolve();
      expect(c.isEmpty, isTrue);
      expect(c.value, '');
      expect(c.isPhone, isFalse);
    });

    test('all-blank inputs report as empty, not as a blank contact', () {
      final c = CustomerContact.resolve(
        jobContactPhone: '',
        profilePhone: '',
        profileEmail: '',
      );
      expect(c.isEmpty, isTrue);
    });
  });

  group('values are returned trimmed', () {
    test('surrounding whitespace is stripped from whichever source wins', () {
      expect(
        CustomerContact.resolve(jobContactPhone: '  0812-job  ').value,
        '0812-job',
      );
    });
  });
}
