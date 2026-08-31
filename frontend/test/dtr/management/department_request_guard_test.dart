import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/departments/data/department_request_guard.dart';

void main() {
  test('delayed Active response cannot replace Inactive results', () async {
    final guard = DepartmentRequestGuard();
    final activeRequest = guard.begin('Active');
    final delayedActive = Completer<void>();

    final inactiveRequest = guard.begin('Inactive');
    expect(guard.accepts(inactiveRequest, 'Inactive'), isTrue);

    delayedActive.complete();
    await delayedActive.future;
    expect(guard.accepts(activeRequest, 'Inactive'), isFalse);
  });

  test('status mismatch rejects a response from the current generation', () {
    final guard = DepartmentRequestGuard();
    final request = guard.begin('Active');

    expect(guard.accepts(request, 'All'), isFalse);
  });

  test('dispose invalidation rejects pending responses', () {
    final guard = DepartmentRequestGuard();
    final request = guard.begin('Active');

    guard.invalidate();

    expect(guard.accepts(request, 'Active'), isFalse);
  });
}
