/// Resolving how to reach a customer about a job.
///
/// A job carries its own contact number (captured at booking) and the customer's
/// profile carries one too. The job's wins: it is the number the customer
/// confirmed for THIS booking, whereas the profile may have changed since, or
/// (until the booking flow started writing it) may never have been set at all.
library;

/// The single contact string to show an operator, plus how to treat it.
///
/// Precedence: job contact number, then profile phone, then profile email.
/// Email is the last resort because a valet cannot ring it, but showing it beats
/// showing nothing — `profiles.phone` is unset on most accounts.
class CustomerContact {
  final String value;
  final bool isPhone;
  final bool hasAny;

  const CustomerContact._(this.value, this.isPhone, this.hasAny);

  /// True when there is nothing on file and the UI should say so explicitly
  /// rather than implying the customer simply has no phone.
  bool get isEmpty => !hasAny;

  static CustomerContact resolve({
    String? jobContactPhone,
    String? profilePhone,
    String? profileEmail,
  }) {
    final candidates = <(String, bool)>[
      (jobContactPhone ?? '', true),
      (profilePhone ?? '', true),
      (profileEmail ?? '', false),
    ];

    for (final (raw, isPhone) in candidates) {
      final value = raw.trim();
      if (value.isNotEmpty) {
        return CustomerContact._(value, isPhone, true);
      }
    }
    return const CustomerContact._('', false, false);
  }
}
