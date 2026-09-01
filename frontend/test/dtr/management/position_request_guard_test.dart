import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/data/position_request_guard.dart';

Map<String, dynamic> positionQuery({
  required String status,
  String? departmentId,
  int page = 1,
  String search = '',
}) => <String, dynamic>{
  'status': status,
  'department_id': departmentId,
  'page': page,
  'limit': 10,
  'search': search,
};

void main() {
  test('delayed HR response cannot replace Finance positions', () async {
    final guard = PositionRequestGuard();
    final hrRequest = guard.begin(
      positionQuery(status: 'Active', departmentId: 'hr'),
    );
    final delayedHr = Completer<void>();

    final financeQuery = positionQuery(
      status: 'Active',
      departmentId: 'finance',
    );
    final financeRequest = guard.begin(financeQuery);
    expect(guard.accepts(financeRequest, financeQuery), isTrue);

    delayedHr.complete();
    await delayedHr.future;
    expect(guard.accepts(hrRequest, financeQuery), isFalse);
  });

  test('status mismatch rejects a response from the current generation', () {
    final guard = PositionRequestGuard();
    final request = guard.begin(positionQuery(status: 'Active'));

    expect(guard.accepts(request, positionQuery(status: 'Inactive')), isFalse);
  });

  test('delayed page response cannot replace the current page', () {
    final guard = PositionRequestGuard();
    final firstPage = guard.begin(positionQuery(status: 'Active'));
    final secondPageQuery = positionQuery(status: 'Active', page: 2);
    final secondPage = guard.begin(secondPageQuery);

    expect(guard.accepts(firstPage, secondPageQuery), isFalse);
    expect(guard.accepts(secondPage, secondPageQuery), isTrue);
  });

  test('delayed search response cannot replace newer search results', () {
    final guard = PositionRequestGuard();
    final officerRequest = guard.begin(
      positionQuery(status: 'Active', search: 'officer'),
    );
    final clerkQuery = positionQuery(status: 'Active', search: 'clerk');
    guard.begin(clerkQuery);

    expect(guard.accepts(officerRequest, clerkQuery), isFalse);
  });

  test('dispose invalidation rejects pending position responses', () {
    final guard = PositionRequestGuard();
    final query = positionQuery(status: 'All');
    final request = guard.begin(query);

    guard.invalidate();

    expect(guard.accepts(request, query), isFalse);
  });

  test('equivalent query-map ordering keeps the current response valid', () {
    final guard = PositionRequestGuard();
    final request = guard.begin(<String, dynamic>{
      'status': 'Active',
      'department_id': 'hr',
      'page': 1,
      'limit': 10,
      'search': '',
    });

    expect(
      guard.accepts(request, <String, dynamic>{
        'department_id': 'hr',
        'status': 'Active',
        'search': '',
        'limit': 10,
        'page': 1,
      }),
      isTrue,
    );
  });
}
