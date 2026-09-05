import 'package:flutter/material.dart';

enum NotificationType {
  payment,
  repairComplete,
  pickupReady,
  general,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  IconData get icon {
    switch (type) {
      case NotificationType.payment:
        return Icons.payment;
      case NotificationType.repairComplete:
        return Icons.build_circle;
      case NotificationType.pickupReady:
        return Icons.car_rental;
      case NotificationType.general:
        return Icons.notifications;
    }
  }

  Color get color {
    switch (type) {
      case NotificationType.payment:
        return Colors.green;
      case NotificationType.repairComplete:
        return const Color(0xFFD10721); // AppColors.primaryContainer
      case NotificationType.pickupReady:
        return Colors.blue;
      case NotificationType.general:
        return Colors.grey;
    }
  }
}
