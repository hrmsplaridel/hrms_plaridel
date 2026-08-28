import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/models/biometric_attendance_log.dart';

class BiometricAttendanceExport {
  const BiometricAttendanceExport({
    required this.bytes,
    required this.rowCount,
    this.filename,
  });

  final Uint8List bytes;
  final int rowCount;
  final String? filename;
}

class BiometricAttendanceLogRepository {
  const BiometricAttendanceLogRepository();

  Future<BiometricAttendanceLogPage> list({
    required int limit,
    required int offset,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final response = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/biometric-attendance-logs',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (dateFrom != null) 'date_from': dateOnly(dateFrom),
        if (dateTo != null) 'date_to': dateOnly(dateTo),
      },
    );
    return BiometricAttendanceLogPage.fromJson(response.data ?? const {});
  }

  Future<BiometricAttendanceExport> export({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String format,
  }) async {
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final response = await ApiClient.instance.dio.get<List<int>>(
      '/api/biometric-attendance-logs/export',
      queryParameters: {
        'date_from': dateOnly(dateFrom),
        'date_to': dateOnly(dateTo),
        'format': format,
      },
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    final disposition = response.headers.value('content-disposition') ?? '';
    final filenameMatch = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(disposition);
    final bytes = Uint8List.fromList(response.data ?? const <int>[]);
    final headerRowCount = int.tryParse(
      response.headers.value('x-export-row-count') ?? '',
    );
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    final lineCount = text.isEmpty
        ? 0
        : const LineSplitter().convert(text).length;
    final inferredRowCount = format == 'csv' && lineCount > 0
        ? lineCount - 1
        : lineCount;
    return BiometricAttendanceExport(
      bytes: bytes,
      rowCount: headerRowCount ?? inferredRowCount,
      filename: filenameMatch?.group(1),
    );
  }
}
