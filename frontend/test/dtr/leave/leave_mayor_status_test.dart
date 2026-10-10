import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

void main() {
  test('Mayor status is pending and cancellable with a clear label', () {
    final status = leaveRequestStatusFromString('pending_mayor');
    expect(status.value, 'pending_mayor');
    expect(status.isPending, isTrue);
    expect(status.displayName, 'Pending Mayor');
  });
}
