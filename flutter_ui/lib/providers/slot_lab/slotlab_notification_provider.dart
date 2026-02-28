/// SlotLab Notification Provider — Middleware §36
///
/// 5 notification types with navigation support.
/// Provides real-time feedback on AutoBind results, validation errors,
/// simulation completion, export status, and general info.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §36

import 'package:flutter/foundation.dart';

enum NotificationType {
  /// AutoBind result (files matched/unmatched)
  autoBind,
  /// Validation error or warning
  validation,
  /// Simulation completed with results
  simulation,
  /// Export finished or failed
  export_,
  /// General information
  info,
}

extension NotificationTypeExtension on NotificationType {
  String get displayName {
    switch (this) {
      case NotificationType.autoBind: return 'AutoBind';
      case NotificationType.validation: return 'Validation';
      case NotificationType.simulation: return 'Simulation';
      case NotificationType.export_: return 'Export';
      case NotificationType.info: return 'Info';
    }
  }

  int get iconCodePoint {
    switch (this) {
      case NotificationType.autoBind: return 0xe226; // auto_fix_high
      case NotificationType.validation: return 0xe002; // warning
      case NotificationType.simulation: return 0xe8b8; // science
      case NotificationType.export_: return 0xe2c6; // file_download
      case NotificationType.info: return 0xe88e; // info
    }
  }
}

enum NotificationSeverity { success, warning, error, info }

class SlotLabNotification {
  final String id;
  final NotificationType type;
  final NotificationSeverity severity;
  final String title;
  final String? body;
  final DateTime timestamp;
  final bool read;
  /// Node ID to navigate to on click (optional)
  final String? navigateToNodeId;

  const SlotLabNotification({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    this.body,
    required this.timestamp,
    this.read = false,
    this.navigateToNodeId,
  });

  SlotLabNotification copyWith({bool? read}) {
    return SlotLabNotification(
      id: id,
      type: type,
      severity: severity,
      title: title,
      body: body,
      timestamp: timestamp,
      read: read ?? this.read,
      navigateToNodeId: navigateToNodeId,
    );
  }
}

class SlotLabNotificationProvider extends ChangeNotifier {
  final List<SlotLabNotification> _notifications = [];
  static const int _maxNotifications = 100;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<SlotLabNotification> get notifications => List.unmodifiable(_notifications);
  List<SlotLabNotification> get unread => _notifications.where((n) => !n.read).toList();
  int get unreadCount => unread.length;
  bool get hasUnread => unreadCount > 0;

  List<SlotLabNotification> getByType(NotificationType type) =>
      _notifications.where((n) => n.type == type).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // PUSH NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void push({
    required NotificationType type,
    required NotificationSeverity severity,
    required String title,
    String? body,
    String? navigateToNodeId,
  }) {
    _notifications.insert(0, SlotLabNotification(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      severity: severity,
      title: title,
      body: body,
      timestamp: DateTime.now(),
      navigateToNodeId: navigateToNodeId,
    ));

    while (_notifications.length > _maxNotifications) {
      _notifications.removeLast();
    }

    notifyListeners();
  }

  /// Convenience: push AutoBind result
  void pushAutoBindResult(int autoBound, int suggested, int needsAttention) {
    push(
      type: NotificationType.autoBind,
      severity: needsAttention > 0 ? NotificationSeverity.warning : NotificationSeverity.success,
      title: 'AutoBind: $autoBound matched, $suggested suggested, $needsAttention need attention',
    );
  }

  /// Convenience: push validation result
  void pushValidation(int errors, int warnings) {
    push(
      type: NotificationType.validation,
      severity: errors > 0 ? NotificationSeverity.error : (warnings > 0 ? NotificationSeverity.warning : NotificationSeverity.success),
      title: errors > 0 ? '$errors errors, $warnings warnings found' : (warnings > 0 ? '$warnings warnings found' : 'All validations passed'),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // READ/DISMISS
  // ═══════════════════════════════════════════════════════════════════════════

  void markRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index >= 0) {
      _notifications[index] = _notifications[index].copyWith(read: true);
      notifyListeners();
    }
  }

  void markAllRead() {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(read: true);
    }
    notifyListeners();
  }

  void dismiss(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    notifyListeners();
  }
}
