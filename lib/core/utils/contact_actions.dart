/// Turning a stored contact value into something an operator can actually use.
///
/// A valet holding a phone number needs one tap, not a number to memorise and
/// retype. The complication is that Indonesian numbers are stored in whatever
/// form the customer typed: `081234567890`, `+62 812-3456-7890`, `62812...`, or
/// occasionally already stripped as `81234567890`. All four are the same line, so
/// normalising is what makes `wa.me` links work — `wa.me/0812...` silently opens
/// WhatsApp on the wrong screen.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Country code for Indonesia, which is where every re-V customer and workshop is.
const String _indonesiaDialCode = '62';

/// Normalises an Indonesian phone number to the digits-only international form
/// (`6281234567890`) that `wa.me` and `tel:` both expect.
///
/// Returns an empty string when there is nothing usable, so callers can fall
/// through to another contact method rather than launching a broken link.
///
/// A number that arrives with a leading `+` and a non-62 country code is left as
/// the customer wrote it rather than being given an Indonesian code — re-V is
/// Indonesia-only today, but silently re-pointing a foreign number at an
/// Indonesian line would be worse than showing it unchanged.
///
/// Deliberately does NOT validate length: a number that is merely unusual is
/// still better to offer than to hide, and the operator can see it is wrong.
String normaliseIndonesianPhone(String? raw) {
  if (raw == null) return '';

  // Detect the international form before stripping, since `+` is the only signal
  // that the caller already chose a country code.
  final hadPlus = raw.trimLeft().startsWith('+');
  // Drop every separator a customer might have typed (spaces, dashes, dots,
  // parens) — none of them are meaningful in a wa.me or tel: URI.
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';

  if (digits.startsWith(_indonesiaDialCode)) {
    // Already international: 62812... . Crucially we must NOT prepend again —
    // that is how "62862812..." links get produced.
    return digits;
  }
  if (hadPlus) {
    // A foreign number the customer chose explicitly. Leave it alone.
    return digits;
  }
  if (digits.startsWith('0')) {
    // The common local form: 0812... -> 62812...
    return _indonesiaDialCode + digits.substring(1);
  }
  // Bare national form with no leading zero: 812... -> 62812...
  return _indonesiaDialCode + digits;
}

/// A contact method the UI can offer, and how to open it.
enum ContactChannel { whatsapp, phone, email }

/// A resolved, launchable contact for one customer.
///
/// Mirrors the precedence the cards display (job snapshot, then profile phone,
/// then profile email) but adds the normalisation and launch URIs, so a widget
/// never has to know how an Indonesian number is spelled.
class ContactTarget {
  final String display;
  final ContactChannel channel;
  final Uri uri;

  const ContactTarget._(this.display, this.channel, this.uri);

  bool get hasChannel => true;

  /// Builds the best available target, or `null` when there is nothing to reach.
  ///
  /// [jobContactPhone] is the number confirmed for this specific booking and so
  /// wins over the profile, which may have changed since — or, on accounts that
  /// never opened the profile editor, was never set at all.
  static ContactTarget? resolve({
    String? jobContactPhone,
    String? profilePhone,
    String? profileEmail,
  }) {
    final phoneSource = _firstNonEmpty([jobContactPhone, profilePhone]);
    if (phoneSource != null) {
      final normalised = normaliseIndonesianPhone(phoneSource);
      if (normalised.isNotEmpty) {
        // WhatsApp first: it is how every re-V customer is actually reachable in
        // Indonesia, and a valet can send the pickup time without a phone call.
        return ContactTarget._(
          phoneSource.trim(),
          ContactChannel.whatsapp,
          Uri.parse('https://wa.me/$normalised'),
        );
      }
    }

    final email = _firstNonEmpty([profileEmail]);
    if (email != null) {
      final address = email.trim();
      // A malformed address would make launchUrl fail with an unclear error, so
      // refuse it here and let the UI show the plain text instead.
      if (address.contains('@')) {
        return ContactTarget._(
          address,
          ContactChannel.email,
          Uri(scheme: 'mailto', path: address),
        );
      }
    }

    return null;
  }

  /// The same number as a `tel:` URI, for operators who would rather call.
  Uri? get callUri {
    if (channel != ContactChannel.whatsapp) return null;
    final normalised = normaliseIndonesianPhone(display);
    if (normalised.isEmpty) return null;
    return Uri(scheme: 'tel', path: '+$normalised');
  }

  /// Opens this contact, reporting whether the platform accepted the handoff.
  ///
  /// Never throws: a blocked popup or an absent WhatsApp install must not take
  /// down the ops list, so the caller keeps the number on screen either way.
  Future<bool> launch() async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[contact] launch failed for ${uri.scheme}: $e');
      return false;
    }
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c;
    }
    return null;
  }
}
