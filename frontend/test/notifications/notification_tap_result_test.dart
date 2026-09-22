import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';

void main() {
  AppNotification notification({
    required String category,
    required String type,
    String? referenceId,
  }) {
    return AppNotification(
      id: 'n1',
      category: category,
      type: type,
      title: 'New recruitment application',
      referenceType: 'recruitment_application',
      referenceId: referenceId,
      createdAt: DateTime(2026, 9, 6, 11, 45),
    );
  }

  test('admin recruitment tap opens the referenced application', () {
    final result = NotificationTapResult.fromNotification(
      notification(
        category: 'recruitment',
        type: 'recruitment_new_application',
        referenceId: 'app-123',
      ),
      role: 'admin',
    );

    expect(result.kind, NotificationTapKind.adminRecruitment);
    expect(result.referenceId, 'app-123');
  });

  test('hr recruitment tap also deep-links to the application', () {
    final result = NotificationTapResult.fromNotification(
      notification(
        category: 'recruitment',
        type: 'recruitment_new_application',
        referenceId: '  app-456  ',
      ),
      role: 'hr',
    );

    expect(result.kind, NotificationTapKind.adminRecruitment);
    expect(result.referenceId, 'app-456');
  });

  test('employee recruitment tap does not open admin RSP', () {
    final result = NotificationTapResult.fromNotification(
      notification(
        category: 'recruitment',
        type: 'recruitment_new_application',
        referenceId: 'app-123',
      ),
      role: 'employee',
    );

    expect(result.kind, NotificationTapKind.none);
    expect(result.referenceId, isNull);
  });
}
