/// Practical mailbox shape — mirrors `supabase/functions/_shared/email.ts`.
///
/// Keep the two in step: the applicant's address becomes their login identity,
/// so a typo there locks them out of the dashboard and of the OTP. The server
/// check is the authority; this one only saves the applicant a round trip.
final RegExp emailPattern = RegExp(
  r'^[^@,;:<>()\[\]"\s]+'
  r'@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*'
  r'\.[A-Za-z]{2,}$',
);

/// Longest address accepted (RFC 5321 caps a path at 256 octets).
const int emailMaxLength = 254;

bool isValidEmail(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty || v.length > emailMaxLength) return false;
  return emailPattern.hasMatch(v);
}

String normaliseEmail(String? value) => (value ?? '').trim().toLowerCase();
