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

  test(
    'an older attendance response cannot replace the latest range',
    () async {
      final adapter = _OutOfOrderAttendanceAdapter();
      ApiClient.instance.dio.httpClientAdapter = adapter;
      final provider = DtrProvider();
      addTearDown(provider.dispose);

      provider.onAuthUserChanged('employee-a');
      final augustLoad = provider.loadTimeRecordsForUser(
        startDate: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 31),
      );
      await adapter.augustStarted.future;

      final septemberLoad = provider.loadTimeRecordsForUser(
        startDate: DateTime(2026, 9),
        endDate: DateTime(2026, 9, 30),
      );
      await adapter.septemberStarted.future;

      adapter.completeSeptember();
      await septemberLoad;
      expect(provider.timeRecords.single.recordDate.month, 9);
      expect(provider.filterStart, DateTime(2026, 9));
      expect(provider.filterEnd, DateTime(2026, 9, 30));
      expect(provider.loading, isFalse);

      adapter.completeAugust();
      await augustLoad;
      expect(provider.timeRecords.single.recordDate.month, 9);
      expect(provider.filterStart, DateTime(2026, 9));
      expect(provider.filterEnd, DateTime(2026, 9, 30));
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    },
  );

  test(
    'an older attendance failure cannot disturb the latest result',
    () async {
      final adapter = _OutOfOrderAttendanceAdapter();
      ApiClient.instance.dio.httpClientAdapter = adapter;
      final provider = DtrProvider();
      addTearDown(provider.dispose);

      provider.onAuthUserChanged('employee-a');
      final augustLoad = provider.loadTimeRecordsForUser(
        startDate: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 31),
      );
      await adapter.augustStarted.future;

      final septemberLoad = provider.loadTimeRecordsForUser(
        startDate: DateTime(2026, 9),
        endDate: DateTime(2026, 9, 30),
      );
      await adapter.septemberStarted.future;

      adapter.completeSeptember();
      await septemberLoad;
      adapter.failAugust();
      await augustLoad;

      expect(provider.timeRecords.single.recordDate.month, 9);
      expect(provider.filterStart, DateTime(2026, 9));
      expect(provider.filterEnd, DateTime(2026, 9, 30));
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    },
  );
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

ResponseBody _attendanceResponseFor(String date) => ResponseBody.fromString(
  jsonEncode([
    <String, dynamic>{
      'id': 'record-$date',
      'user_id': 'employee-a',
      'record_date': date,
      'time_in': '${date}T00:00:00.000Z',
      'time_out': '${date}T09:00:00.000Z',
      'status': 'present',
    },
  ]),
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

class _OutOfOrderAttendanceAdapter implements HttpClientAdapter {
  final augustStarted = Completer<void>();
  final septemberStarted = Completer<void>();
  final _augustResponse = Completer<ResponseBody>();
  final _septemberResponse = Completer<ResponseBody>();

  void completeAugust() =>
      _augustResponse.complete(_attendanceResponseFor('2026-08-03'));

  void failAugust() => _augustResponse.complete(
    ResponseBody.fromString(
      jsonEncode({'error': 'August unavailable'}),
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    ),
  );

  void completeSeptember() =>
      _septemberResponse.complete(_attendanceResponseFor('2026-09-03'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    switch (options.queryParameters['start_date']) {
      case '2026-08-01':
        if (!augustStarted.isCompleted) augustStarted.complete();
        return _augustResponse.future;
      case '2026-09-01':
        if (!septemberStarted.isCompleted) septemberStarted.complete();
        return _septemberResponse.future;
      default:
        throw StateError(
          'Unexpected attendance request: ${options.queryParameters}',
        );
    }
  }

  @override
  void close({bool force = false}) {}
}
