import 'package:flutter/material.dart';

enum NotificationType {
  statusUpdate,
  payment,
  pickupReady,
  general,
}

class AppNotification {
  final String id;
  final String? jobId;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;

  AppNotification({
    required this.id,
    this.jobId,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
  });

  AppNotification copyWith({
    String? id,
    String? jobId,
    String? title,
    String? body,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      jobId: map['job_id'] as String?,
      title: map['title'] as String,
      body: map['body'] as String,
      type: _typeFromString(map['type'] as String? ?? 'general'),
      timestamp: DateTime.parse(map['created_at'] as String),
      isRead: map['is_read'] as bool? ?? false,
    );
  }

  static NotificationType _typeFromString(String raw) {
    switch (raw) {
      case 'status_update': return NotificationType.statusUpdate;
      case 'payment':       return NotificationType.payment;
      case 'pickup_ready':  return NotificationType.pickupReady;
      default:              return NotificationType.general;
    }
  }

  IconData get icon {
    switch (type) {
      case NotificationType.statusUpdate: return Icons.build_circle_outlined;
      case NotificationType.payment:      return Icons.payment;
      case NotificationType.pickupReady:  return Icons.car_rental;
      case NotificationType.general:      return Icons.notifications_outlined;
    }
  }

  Color get color {
    switch (type) {
      case NotificationType.statusUpdate: return const Color(0xFFD10721);
      case NotificationType.payment:      return Colors.green;
      case NotificationType.pickupReady:  return Colors.blue;
      case NotificationType.general:      return Colors.grey;
    }
  }
}
