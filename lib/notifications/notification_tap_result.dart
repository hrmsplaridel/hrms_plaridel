import 'app_notification.dart';
import '../leave/leave_main.dart';

/// Where to navigate after the user taps a notification (panel pops with this result).
enum NotificationTapKind {
  /// No dedicated screen (or unknown); panel still closes on tap if you pop with this.
  none,

  /// HR/Admin: main nav → DTR → Leave Management (approvals).
  adminDtrLeaveManagement,
  adminDtrLocatorManagement,

  /// Employee / department head: My Leave → Approvals.
  employeeLeaveApprovals,

  /// Employee: My Leave → My Requests.
  employeeLeaveRequests,
  employeeLocatorApprovals,
  employeeLocatorRequests,

  /// Employee: My Attendance (e.g. DTR correction approved/rejected).
  employeeMyAttendance,
}

class NotificationTapResult {
  const NotificationTapResult(this.kind);

  final NotificationTapKind kind;

  /// Maps backend [AppNotification.type] + user [role] to a navigation target.
  static NotificationTapResult fromNotification(
    AppNotification n, {
    String? role,
  }) {
    final cat = n.category.toLowerCase();
    final t = n.type.toLowerCase();
    final isPrivileged = role == 'admin' || role == 'hr';

    if (cat == 'dtr') {
      if (!isPrivileged &&
          (t.contains('approved') || t.contains('rejected'))) {
        return const NotificationTapResult(
          NotificationTapKind.employeeMyAttendance,
        );
      }
      return const NotificationTapResult(NotificationTapKind.none);
    }

    if (cat != 'leave') {
      if (cat == 'locator') {
        if (isPrivileged) {
          return const NotificationTapResult(
            NotificationTapKind.adminDtrLocatorManagement,
          );
        }
        if (t.contains('pending_department_head')) {
          return const NotificationTapResult(
            NotificationTapKind.employeeLocatorApprovals,
          );
        }
        return const NotificationTapResult(
          NotificationTapKind.employeeLocatorRequests,
        );
      }
      return const NotificationTapResult(NotificationTapKind.none);
    }

    if (isPrivileged) {
      if (t.contains('pending_hr') ||
          t.contains('forwarded_to_hr') ||
          t.contains('cancelled_hr')) {
        return const NotificationTapResult(
          NotificationTapKind.adminDtrLeaveManagement,
        );
      }
      if (t.startsWith('leave_')) {
        return const NotificationTapResult(
          NotificationTapKind.adminDtrLeaveManagement,
        );
      }
      return const NotificationTapResult(NotificationTapKind.none);
    }

    // Employee, supervisor, or department head (non-admin)
    if (t.contains('pending_department_head') ||
        t.contains('cancelled_department_head')) {
      return const NotificationTapResult(
        NotificationTapKind.employeeLeaveApprovals,
      );
    }

    return const NotificationTapResult(
      NotificationTapKind.employeeLeaveRequests,
    );
  }

  /// Resolved [LeaveSection] for employee [LeaveMain], or null if not applicable.
  LeaveSection? get employeeLeaveSection => switch (kind) {
    NotificationTapKind.employeeLeaveApprovals => LeaveSection.approvals,
    NotificationTapKind.employeeLeaveRequests => LeaveSection.requests,
    _ => null,
  };
}
