import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  test('sign out clears attendance and filter state immediately', () async {
    ApiClient.instance.dio.httpClientAdapter = _StaticAttendanceAdapter();
    final provider = DtrProvider();
    addTearDown(provider.dispose);

    provider.onAuthUserChanged('employee-a');
    await provider.loadTimeRecordsForUser(
      startDate: DateTime(2026, 8),
      endDate: DateTime(2026, 8, 31),
    );
    provider.setAnalyticsDepartmentFilter('Human Resources');

    expect(provider.timeRecords, hasLength(1));
    expect(provider.filterUserId, 'employee-a');
    expect(provider.analyticsDepartmentName, 'Human Resources');

    provider.onAuthUserChanged(null);

    expect(provider.userId, isNull);
    expect(provider.timeRecords, isEmpty);
    expect(provider.timeRecordTotal, 0);
    expect(provider.filterStart, isNull);
    expect(provider.filterEnd, isNull);
    expect(provider.filterUserId, isNull);
    expect(provider.filterDepartmentId, isNull);
    expect(provider.todayRecord, isNull);
    expect(provider.myShiftStartMinutes, isNull);
    expect(provider.myShiftEndMinutes, isNull);
    expect(provider.analyticsDepartmentName, isNull);
    expect(provider.loading, isFalse);
    expect(provider.error, isNull);
  });

  test('an old account response cannot repopulate a new session', () async {
    final adapter = _DelayedAttendanceAdapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;
    final provider = DtrProvider();
    addTearDown(provider.dispose);

    provider.onAuthUserChanged('employee-a');
    final pendingLoad = provider.loadTimeRecordsForUser(
      startDate: DateTime(2026, 8),
      endDate: DateTime(2026, 8, 31),
    );
    await adapter.requestStarted.future;

    provider.onAuthUserChanged('employee-b');
    adapter.complete();
    await pendingLoad;

    expect(provider.userId, 'employee-b');
    expect(provider.timeRecords, isEmpty);
    expect(provider.filterUserId, isNull);
    expect(provider.loading, isFalse);
  });
}

const _attendancePayload = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'record-a',
    'user_id': 'employee-a',
    'record_date': '2026-08-03',
    'time_in': '2026-08-03T00:00:00.000Z',
    'time_out': '2026-08-03T09:00:00.000Z',
    'status': 'present',
  },
];

ResponseBody _attendanceResponse() => ResponseBody.fromString(
  jsonEncode(_attendancePayload),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    'x-total-count': ['1'],
    'x-limit': ['500'],
    'x-offset': ['0'],
  },
);

class _StaticAttendanceAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => _attendanceResponse();

  @override
  void close({bool force = false}) {}
}

class _DelayedAttendanceAdapter implements HttpClientAdapter {
  final requestStarted = Completer<void>();
  final _response = Completer<ResponseBody>();

  void complete() => _response.complete(_attendanceResponse());

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (!requestStarted.isCompleted) requestStarted.complete();
    return _response.future;
  }

  @override
  void close({bool force = false}) {}
}
