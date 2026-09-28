// lib/core/models/partner_message.dart
//
// CODE-03 fix: single PartnerMessage model, replaces the two contradictory
// PartnerMessageNode definitions in partner_settings_controller.dart and
// admin_partner_profile_controller.dart.
//
// sender_role is explicit ('admin' | 'owner' | 'mechanic' | 'staff' | 'driver')
// isFromAdmin = from_admin field set by DB trigger (always authoritative).

import 'package:intl/intl.dart';

class PartnerMessage {
  final String id;
  final String partnerId;
  final String senderId;
  final String content;
  final bool fromAdmin;   // set by DB trigger — authoritative
  final bool isRead;
  final DateTime createdAt;

  const PartnerMessage({
    required this.id,
    required this.partnerId,
    required this.senderId,
    required this.content,
    required this.fromAdmin,
    required this.isRead,
    required this.createdAt,
  });

  factory PartnerMessage.fromMap(Map<String, dynamic> m) {
    // C-81 fix: parse as UTC, convert to local
    final raw = m['created_at']?.toString() ?? '';
    final dt = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    return PartnerMessage(
      id:        m['id']?.toString() ?? '',
      partnerId: m['partner_id']?.toString() ?? '',
      senderId:  m['sender_id']?.toString() ?? '',
      content:   m['content']?.toString() ?? '',
      fromAdmin: m['from_admin'] == true,
      isRead:    m['is_read'] == true,
      createdAt: dt,
    );
  }

  /// Display time in local timezone (C-81).
  String get timeLabel => DateFormat('HH:mm').format(createdAt);

  /// Date label for separators — uses full date to avoid day-of-month collision (C-81).
  String get dateLabel => DateFormat('d MMM yyyy').format(createdAt);

  bool isSameDayAs(PartnerMessage other) =>
      createdAt.year  == other.createdAt.year &&
      createdAt.month == other.createdAt.month &&
      createdAt.day   == other.createdAt.day;
}
