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

  test(
    'official HRMS date is parsed as a date without device conversion',
    () async {
      ApiClient.instance.dio.httpClientAdapter = _JsonAdapter({
        'official_date': '2026-09-14',
        'min_year': 2020,
        'max_year': 2026,
        'years': [2020, 2021, 2022, 2023, 2024, 2025, 2026],
      });

      final date = await TimeRecordRepo.instance.getOfficialHrmsDate();

      expect(date, DateTime(2026, 9, 14));
      expect(date.isUtc, isFalse);
    },
  );

  test('invalid official HRMS date is rejected', () async {
    ApiClient.instance.dio.httpClientAdapter = _JsonAdapter({
      'official_date': 'not-a-date',
    });

    expect(
      TimeRecordRepo.instance.getOfficialHrmsDate(),
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
