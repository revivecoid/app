import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/contact_actions.dart';
import '../utils/customer_contact.dart';

/// The customer's contact detail, shown to an operator and tappable-through.
///
/// Used by both the ops mobile cards and the partner dashboard, so the
/// precedence and the launch behaviour exist once. Precedence is job snapshot,
/// then profile phone, then profile email — a job keeps the number it was booked
/// with, which is more trustworthy than a profile that may have changed since.
///
/// Tapping a phone offers WhatsApp or a call because which one reaches the
/// customer depends on whether they answer unknown numbers. The number always
/// stays visible, so a blocked popup or a missing app costs the operator nothing.
class CustomerContactLine extends StatelessWidget {
  final String? jobContactPhone;
  final String? profilePhone;
  final String? profileEmail;

  /// Tighter spacing and a smaller icon, for the dashboard's dense job cards.
  final bool dense;

  const CustomerContactLine({
    super.key,
    this.jobContactPhone,
    this.profilePhone,
    this.profileEmail,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contact = CustomerContact.resolve(
      jobContactPhone: jobContactPhone,
      profilePhone: profilePhone,
      profileEmail: profileEmail,
    );

    if (contact.isEmpty) {
      // Said plainly rather than hidden: an operator needs to know there is no
      // way to reach this customer, not to wonder where the row went.
      return _line(
        context,
        icon: Icons.contact_phone_outlined,
        colour: Colors.orange.shade700,
        text: 'No phone or email on file',
        textColour: Colors.orange.shade700,
      );
    }

    final target = ContactTarget.resolve(
      jobContactPhone: jobContactPhone,
      profilePhone: profilePhone,
      profileEmail: profileEmail,
    );

    final content = _line(
      context,
      icon: contact.isPhone ? Icons.phone_outlined : Icons.email_outlined,
      colour: cs.onSurfaceVariant,
      text: contact.value,
      textColour: cs.onSurface,
      trailing: target == null
          ? null
          : Icon(
              contact.isPhone ? Icons.chat_outlined : Icons.open_in_new,
              size: dense ? 13 : 15,
              color: cs.primary,
            ),
    );

    if (target == null) return content;

    return InkWell(
      onTap: () => _open(context, target),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
        child: content,
      ),
    );
  }

  Widget _line(
    BuildContext context, {
    required IconData icon,
    required Color colour,
    required String text,
    required Color textColour,
    Widget? trailing,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: dense ? 13 : 16, color: colour),
        SizedBox(width: dense ? 6 : 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: dense ? 11 : 14, color: textColour),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing],
      ],
    );
  }

  /// Opens WhatsApp / the dialler / the mail client. Never throws: the number is
  /// already on screen, so a failure here must not disturb the list.
  Future<void> _open(BuildContext context, ContactTarget target) async {
    final callUri = target.callUri;

    if (callUri == null) {
      await target.launch();
      return;
    }

    final choice = await showModalBottomSheet<_ContactAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp'),
              subtitle: Text(target.display),
              onTap: () => Navigator.pop(sheetContext, _ContactAction.whatsapp),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Call'),
              subtitle: Text(target.display),
              onTap: () => Navigator.pop(sheetContext, _ContactAction.call),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == _ContactAction.whatsapp) {
      await target.launch();
      return;
    }

    try {
      await launchUrl(callUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[contact] call launch failed: $e');
    }
  }
}

enum _ContactAction { whatsapp, call }
