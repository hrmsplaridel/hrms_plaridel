import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  test('report period includes historical years and official date', () async {
    ApiClient.instance.dio.httpClientAdapter = _JsonAdapter({
      'official_date': '2026-09-14',
      'min_year': 2019,
      'max_year': 2026,
      'years': [2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026],
    });

    final period = await TimeRecordRepo.instance.getAttendanceReportPeriod();

    expect(period.officialDate, DateTime(2026, 9, 14));
    expect(period.officialDate.isUtc, isFalse);
    expect(period.years, [2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026]);
  });

  test('invalid official HRMS date is rejected', () async {
    ApiClient.instance.dio.httpClientAdapter = _JsonAdapter({
      'official_date': 'not-a-date',
    });

    expect(
      TimeRecordRepo.instance.getOfficialHrmsDate(),
      throwsA(isA<FormatException>()),
    );
  });

  test('missing report years are rejected', () async {
    ApiClient.instance.dio.httpClientAdapter = _JsonAdapter({
      'official_date': '2026-09-14',
    });

    expect(
      TimeRecordRepo.instance.getAttendanceReportPeriod(),
      throwsA(isA<FormatException>()),
    );
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/dtr-daily-summary/report-years');
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
