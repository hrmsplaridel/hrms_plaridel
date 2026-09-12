import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/data/assignment_request_guard.dart';

Map<String, dynamic> employeeContext(
  String employeeId, {
  String status = 'Active',
}) => <String, dynamic>{'employee_id': employeeId, 'status': status};

void main() {
  test(
    'delayed employee A response cannot replace employee B records',
    () async {
      final guard = AssignmentRequestGuard();
      final employeeA = guard.begin(employeeContext('employee-a'));
      final delayedA = Completer<void>();

      final employeeB = guard.begin(employeeContext('employee-b'));
      expect(guard.accepts(employeeB, employeeContext('employee-b')), isTrue);

      delayedA.complete();
      await delayedA.future;
      expect(guard.accepts(employeeA, employeeContext('employee-b')), isFalse);
    },
  );

  test('assignment status change invalidates an older response', () {
    final guard = AssignmentRequestGuard();
    final active = guard.begin(employeeContext('employee-a'));

    expect(
      guard.accepts(active, employeeContext('employee-a', status: 'Inactive')),
      isFalse,
    );
  });

  test('explicit invalidation rejects pending requests', () {
    final guard = AssignmentRequestGuard();
    final request = guard.begin(employeeContext('employee-a'));

    guard.invalidate();

    expect(guard.accepts(request, employeeContext('employee-a')), isFalse);
  });

  test('equivalent query maps have the same immutable signature', () {
    final guard = AssignmentRequestGuard();
    final request = guard.begin(<String, dynamic>{
      'employee_id': 'employee-a',
      'status': 'Active',
    });

    expect(
      guard.accepts(request, <String, dynamic>{
        'status': 'Active',
        'employee_id': 'employee-a',
      }),
      isTrue,
    );
  });
}
