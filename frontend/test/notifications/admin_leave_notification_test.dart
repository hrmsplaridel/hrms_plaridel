import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';

void main() {
  for (final role in ['admin', 'hr']) {
    for (final type in [
      'leave_approved',
      'leave_endorsed_department_head',
      'leave_rejected_department_head',
      'leave_rejected_hr',
      'leave_returned_department_head',
      'leave_returned_hr',
      'leave_revoked',
    ]) {
      test('$role own $type notification opens My Requests', () {
        final result = NotificationTapResult.fromNotification(
          AppNotification(
            id: 'notice',
            category: 'leave',
            type: type,
            title: 'Your leave request status',
            referenceId: 'request',
            createdAt: DateTime(2026, 10, 18),
          ),
          role: role,
        );
        expect(result.kind, NotificationTapKind.employeeLeaveRequests);
      });
    }

    for (final type in [
      'leave_pending_hr',
      'leave_forwarded_to_hr',
      'leave_cancelled_hr',
    ]) {
      test('$role $type still opens leave review management', () {
        final result = NotificationTapResult.fromNotification(
          AppNotification(
            id: 'notice',
            category: 'leave',
            type: type,
            title: 'Review request',
            createdAt: DateTime(2026, 10, 18),
          ),
          role: role,
        );
        expect(result.kind, NotificationTapKind.adminDtrLeaveManagement);
      });
    }

    test('$role shared workflow assignment still opens review management', () {
      final result = NotificationTapResult.fromNotification(
        AppNotification(
          id: 'notice',
          category: 'leave',
          type: 'leave_pending_hr',
          title: 'Leave request needs your approval',
          referenceId: 'request',
          metadata: {'workflow_approval': true},
          createdAt: DateTime(2026, 10, 18),
        ),
        role: role,
      );
      expect(result.kind, NotificationTapKind.adminDtrLeaveManagement);
      expect(result.referenceId, 'request');
    });
  }
}
