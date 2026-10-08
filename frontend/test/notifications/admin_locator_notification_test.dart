import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';

void main() {
  for (final role in ['admin', 'hr']) {
    for (final type in [
      'locator_approved',
      'locator_rejected',
      'locator_returned',
      'locator_revoked',
      'locator_approved_department_head',
    ]) {
      test('$role own $type notification opens personal locator', () {
        final result = NotificationTapResult.fromNotification(
          AppNotification(
            id: 'notice',
            category: 'locator',
            type: type,
            title: 'Status',
            createdAt: DateTime(2026, 10, 8),
          ),
          role: role,
        );
        expect(result.kind, NotificationTapKind.employeeLocatorRequests);
      });
    }
    for (final type in ['locator_pending_hr', 'locator_forwarded_to_hr']) {
      test('$role $type still opens review management', () {
        final result = NotificationTapResult.fromNotification(
          AppNotification(
            id: 'notice',
            category: 'locator',
            type: type,
            title: 'Review',
            createdAt: DateTime(2026, 10, 8),
          ),
          role: role,
        );
        expect(result.kind, NotificationTapKind.adminDtrLocatorManagement);
      });
    }
  }
}
