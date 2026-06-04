import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:hrms_plaridel/core/api/client.dart';

/// Loads and saves RSP / L&D form rows via the HRMS API (`/api/rsp-ld-saved-entries/*`) into PostgreSQL.
/// Requires an **admin** JWT (same as other RSP admin tools).
class RspLdSavedEntriesApi {
  RspLdSavedEntriesApi._();

  static const String _prefix = '/api/rsp-ld-saved-entries';

  /// JSON body for POST/PUT so Express always receives a parsed object (avoids empty req.body
  /// if the client stack mis-handles Map encoding or content-type on some platforms).
  static String _jsonBody(Map<String, dynamic> payload) =>
      jsonEncode(Map<String, dynamic>.from(payload)..remove('id'));

  static Future<List<Map<String, dynamic>>> listRows(String table) async {
    final res = await ApiClient.instance.get<List<dynamic>>('$_prefix/$table');
    final data = res.data;
    if (data == null) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>?> getRow(String table, String id) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '$_prefix/$table/$id',
    );
    return res.data;
  }

  static Future<void> insertRow(
    String table,
    Map<String, dynamic> payload,
  ) async {
    await ApiClient.instance.post<dynamic>(
      '$_prefix/$table',
      data: _jsonBody(payload),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  static Future<void> updateRow(
    String table,
    String id,
    Map<String, dynamic> payload,
  ) async {
    await ApiClient.instance.put<dynamic>(
      '$_prefix/$table/$id',
      data: _jsonBody(payload),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  static Future<void> deleteRow(String table, String id) async {
    await ApiClient.instance.delete<void>('$_prefix/$table/$id');
  }
}
