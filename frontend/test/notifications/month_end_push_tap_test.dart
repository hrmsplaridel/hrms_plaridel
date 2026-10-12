import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/services/push_notification_service.dart';

void main() {
  test(
    'credit-history push taps are consumed only by the intended signed-in user',
    () {
      final service = PushNotificationService.instance;
      service.handleNotificationTapData({
        'category': 'leave',
        'type': 'leave_month_end_balance_updated',
        'user_id': 'employee-one',
      });
      expect(
        service.consumeMonthEndCreditHistoryTapFor('employee-two'),
        isFalse,
      );
      expect(
        service.consumeMonthEndCreditHistoryTapFor('employee-one'),
        isTrue,
      );
      expect(
        service.consumeMonthEndCreditHistoryTapFor('employee-one'),
        isFalse,
      );
      service.handleNotificationTapData({
        'category': 'leave',
        'type': 'leave_approved',
        'user_id': 'employee-one',
      });
      expect(
        service.consumeMonthEndCreditHistoryTapFor('employee-one'),
        isFalse,
      );
    },
  );
}
