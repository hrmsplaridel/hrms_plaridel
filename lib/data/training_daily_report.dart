import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import '../api/client.dart';
import '../api/config.dart';

/// One daily training report submitted by an employee.
class TrainingDailyReport {
  const TrainingDailyReport({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.title,
    required this.description,
    required this.submittedAt,
    required this.status,
    this.attachmentId,
    this.attachmentName,
    this.attachmentType,
    this.attachmentPath,
  });

  final String id;
  final String employeeId;
  final String? employeeName;
  final String title;
  final String? description;
  final DateTime submittedAt;
  final String status;
  final String? attachmentId;
  final String? attachmentName;
  final String? attachmentType;
  final String? attachmentPath;

  String? get attachmentUrl => attachmentId == null
      ? null
      : '${ApiConfig.baseUrl}/api/files/training-report/$attachmentId';

  factory TrainingDailyReport.fromJson(Map<String, dynamic> json) {
    return TrainingDailyReport(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      submittedAt: DateTime.tryParse(json['submitted_at'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'submitted',
      attachmentId: json['attachment_id'] as String?,
      attachmentName: json['attachment_name'] as String?,
      attachmentType: json['attachment_type'] as String?,
      attachmentPath: json['attachment_path'] as String?,
    );
  }
}

/// Repository for calling the backend Training Daily Reports API.
class TrainingDailyReportRepo {
  TrainingDailyReportRepo._();
  static final TrainingDailyReportRepo instance = TrainingDailyReportRepo._();

  /// Upload a proof/attachment to the backend. Returns a map with:
  /// { path, originalName, mimeType }.
  Future<Map<String, dynamic>> uploadAttachment(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw ArgumentError('File bytes are required');
    }
    final res = await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
      '/api/upload/training-report',
      bytes: Uint8List.fromList(bytes),
      fileName: file.name,
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return data;
  }

  /// Submit a new daily training report for the current employee.
  Future<void> submitReport({
    required String title,
    String? description,
    Map<String, dynamic>? attachmentMeta,
  }) async {
    await ApiClient.instance.post(
      '/api/training-daily-reports',
      data: {
        'title': title,
        'description': description,
        if (attachmentMeta != null) ...{
          'attachment_path': attachmentMeta['path'],
          'attachment_name': attachmentMeta['originalName'],
          'attachment_type': attachmentMeta['mimeType'],
        },
      },
    );
  }

  /// List reports for the current employee.
  Future<List<TrainingDailyReport>> listMyReports() async {
    final res = await ApiClient.instance.get('/api/training-daily-reports/mine');
    final list = res.data as List<dynamic>? ?? [];
    return list
        .map(
          (e) => TrainingDailyReport.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  /// Admin: list all reports with optional filters.
  Future<List<TrainingDailyReport>> listAllReports({
    String? search,
    String? fromDate,
    String? toDate,
    String? status,
  }) async {
    final res = await ApiClient.instance.get(
      '/api/training-daily-reports',
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (fromDate != null) 'fromDate': fromDate,
        if (toDate != null) 'toDate': toDate,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final list = res.data as List<dynamic>? ?? [];
    return list
        .map(
          (e) => TrainingDailyReport.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  /// Admin: mark a report as seen/reviewed.
  Future<TrainingDailyReport> markAsSeen(String id) async {
    final res = await ApiClient.instance.patch(
      '/api/training-daily-reports/$id/seen',
    );
    return TrainingDailyReport.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }
}

