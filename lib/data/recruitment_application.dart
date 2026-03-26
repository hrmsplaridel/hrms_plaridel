import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';

import '../api/client.dart';
import '../api/config.dart';

/// One recruitment application (Step 1: basic info / documents).
class RecruitmentApplication {
  const RecruitmentApplication({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.resumeNotes,
    this.attachmentPath,
    this.attachmentName,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? resumeNotes;
  final String? attachmentPath;
  final String? attachmentName;
  final String status; // submitted, exam_taken, passed, failed, registered
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'recruitment_applications';
  static const String storageBucket = 'recruitment-attachments';

  factory RecruitmentApplication.fromJson(Map<String, dynamic> json) {
    return RecruitmentApplication(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      resumeNotes: json['resume_notes'] as String?,
      attachmentPath: json['attachment_path'] as String?,
      attachmentName: json['attachment_name'] as String?,
      status: json['status'] as String? ?? 'submitted',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'email': email,
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'resume_notes': resumeNotes?.trim().isEmpty == true
          ? null
          : resumeNotes?.trim(),
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

/// Exam result for one application (Step 2–3).
class RecruitmentExamResult {
  const RecruitmentExamResult({
    required this.id,
    required this.applicationId,
    required this.scorePercent,
    required this.passed,
    this.answersJson,
    this.submittedAt,
  });

  final String id;
  final String applicationId;
  final double scorePercent;
  final bool passed;
  final Map<String, dynamic>? answersJson;
  final DateTime? submittedAt;

  static const String tableName = 'recruitment_exam_results';
}

/// Repo for recruitment applications and exam results.
class RecruitmentRepo {
  RecruitmentRepo._();
  static final RecruitmentRepo instance = RecruitmentRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Delete an applicant and related exam result rows.
  /// Uses backend API to avoid Supabase RLS issues (your admin uses API JWT).
  Future<void> deleteApplication(String applicationId) async {
    try {
      await ApiClient.instance.delete<void>(
        '/api/rsp/applications/$applicationId',
      );
      return;
    } on DioException catch (e) {
      final data = e.response?.data;
      final details =
          (data is Map && (data['details'] != null || data['error'] != null))
          ? (data['details'] ?? data['error'])
          : null;
      // Fallback: try deleting directly from Supabase (in case backend is
      // connected to a different DB than Supabase tables used by this app).
      Object? supabaseErr;
      try {
        // Delete exam results first (FK constraint order).
        await _client
            .from('recruitment_exam_results')
            .delete()
            .eq('application_id', applicationId);
        await _client
            .from(RecruitmentApplication.tableName)
            .delete()
            .eq('id', applicationId);
        return;
      } catch (e2) {
        supabaseErr = e2;
        throw Exception(
          details != null
              ? 'Delete failed (backend): $details. Also failed (Supabase fallback): $supabaseErr'
              : 'Delete failed (backend): ${e.message ?? e.toString()}. Also failed (Supabase fallback): $supabaseErr',
        );
      }
    }
  }

  /// Insert new application (Step 1). Returns the created row id.
  Future<String> insertApplication(RecruitmentApplication app) async {
    final email = app.email.trim();
    final res = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/rsp/applications',
      data: {
        'fullName': app.fullName,
        'email': email.isEmpty ? '' : email.toLowerCase(),
        'phone': app.phone,
        'resumeNotes': app.resumeNotes,
        'status': app.status,
      },
    );
    final appRow = res.data?['application'] as Map<String, dynamic>?;
    final id = appRow?['id'];
    if (id == null) throw Exception('Insert failed: missing id in response');
    return id.toString();
  }

  /// Update application status (e.g. after exam).
  Future<void> updateApplicationStatus(String id, String status) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$id/status',
      data: {'status': status},
    );
  }

  /// Upload a single attachment to storage and set path on application. Path = {applicationId}/{fileName}.
  Future<void> uploadAttachment(
    String applicationId,
    List<int> fileBytes,
    String fileName,
  ) async {
    final path = '$applicationId/$fileName';
    await _client.storage
        .from(RecruitmentApplication.storageBucket)
        .uploadBinary(path, Uint8List.fromList(fileBytes));
    await setApplicationAttachment(applicationId, path, fileName);
  }

  /// Upload multiple attachments to storage. Each file gets a unique path; application row is set to the first file.
  Future<void> uploadAttachments(
    String applicationId,
    List<({List<int> bytes, String fileName})> files,
  ) async {
    if (files.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final uniquePath = '$applicationId/${now}_${i}_${f.fileName}';
      await _client.storage
          .from(RecruitmentApplication.storageBucket)
          .uploadBinary(uniquePath, Uint8List.fromList(f.bytes));
    }
    final first = files.first;
    final firstPath = '$applicationId/${now}_0_${first.fileName}';
    await setApplicationAttachment(applicationId, firstPath, first.fileName);
  }

  /// URL for admin to preview/download (same pattern as L&D training reports:
  /// `${ApiConfig.baseUrl}/api/files/...` so [Image.network] works on web).
  ///
  /// 1) `GET /api/rsp/storage/view-token` → `/api/files/recruitment-attachment?token=...`
  /// 2) Fallback: Supabase signed URL via backend
  Future<String?> getAttachmentDownloadUrl(
    String attachmentPath, {
    String? fileName,
  }) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/storage/view-token',
        queryParameters: {
          'path': attachmentPath,
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
        },
      );
      final token = res.data?['token'] as String?;
      if (token != null && token.isNotEmpty) {
        final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
        return '$base/api/files/recruitment-attachment?token=${Uri.encodeComponent(token)}';
      }
    } on DioException catch (_) {
      // Fall through
    } catch (_) {
      // Fall through
    }

    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/storage/signed-url',
        queryParameters: {
          'path': attachmentPath,
          'bucket': RecruitmentApplication.storageBucket,
        },
      );
      final data = res.data;
      final url = data?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return url;
      }
    } on DioException catch (_) {
      // Fall through to Supabase client
    } catch (_) {
      // Fall through
    }

    try {
      final url = await _client.storage
          .from(RecruitmentApplication.storageBucket)
          .createSignedUrl(attachmentPath, 3600);
      return url;
    } catch (_) {
      // Fallback: if storage bucket allows public reads, use the public URL.
      try {
        final publicUrl = _client.storage
            .from(RecruitmentApplication.storageBucket)
            .getPublicUrl(attachmentPath);
        return publicUrl;
      } catch (_) {
        return null;
      }
    }
  }

  /// Remove an attachment file from storage (admin). Path is e.g. applicationId/filename.
  Future<void> deleteAttachment(String path) async {
    await _client.storage.from(RecruitmentApplication.storageBucket).remove([
      path,
    ]);
  }

  /// Thrown when storage listing is attempted without an authenticated session.
  static const String kErrorNotAuthenticated =
      'Admin not authenticated with Supabase Auth. Please log in again.';

  /// List all attachment paths in storage (bucket structure: {applicationId}/{fileName}.
  /// Requires an authenticated session (admin). Returns list of maps with 'applicationId', 'path', 'fileName'.
  /// Throws if not authenticated or if storage list fails (so caller can show a clear error).
  Future<List<Map<String, String>>> listStorageAttachmentPaths() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw Exception(kErrorNotAuthenticated);
    }
    try {
      final bucket = _client.storage.from(RecruitmentApplication.storageBucket);
      final List<Map<String, String>> out = [];
      final root = await bucket.list(path: '');
      for (final folder in root) {
        final applicationId = folder.name;
        if (applicationId.isEmpty) continue;
        try {
          final files = await bucket.list(path: applicationId);
          for (final file in files) {
            if (file.name.isEmpty) continue;
            final path = '$applicationId/${file.name}';
            out.add({
              'applicationId': applicationId,
              'path': path,
              'fileName': file.name,
            });
          }
        } catch (_) {
          // Skip this folder (e.g. permission on one prefix); continue with others
        }
      }
      return out;
    } catch (e) {
      rethrow;
    }
  }

  /// Set attachment path and name on an application (e.g. after syncing from storage). Admin only.
  Future<void> setApplicationAttachment(
    String applicationId,
    String path,
    String fileName,
  ) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$applicationId/attachment',
      data: {
        'path': path,
        'fileName': fileName,
      },
    );
  }

  /// Update application attachment only if it is currently null (for backfill from storage).
  Future<bool> setApplicationAttachmentIfMissing(
    String applicationId,
    String path,
    String fileName,
  ) async {
    try {
      final res = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/rsp/applications/$applicationId/attachment-if-missing',
        data: {'path': path, 'fileName': fileName},
      );
      final updated = res.data?['updated'];
      if (updated is bool) return updated;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Insert exam result and update application status.
  Future<void> submitExamResult({
    required String applicationId,
    required double scorePercent,
    required bool passed,
    Map<String, dynamic>? answersJson,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/rsp/applications/exam-results',
      data: {
        'applicationId': applicationId,
        'scorePercent': scorePercent,
        'passed': passed,
        'answersJson': answersJson,
      },
    );
  }

  /// List all applications (for admin). Newest first.
  Future<List<RecruitmentApplication>> listApplications() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/applications',
      );
      final rows = res.data?['applications'] as List<dynamic>? ?? [];
      return rows
          .map((e) => RecruitmentApplication.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get the latest application by email (for applicant "Continue application"). Returns null if none.
  Future<RecruitmentApplication?> getApplicationByEmail(String email) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/applications/by-email',
        queryParameters: {'email': email.trim().toLowerCase()},
      );
      final row = res.data?['application'] as Map<String, dynamic>?;
      if (row == null) return null;
      return RecruitmentApplication.fromJson(row);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get exam result for an application (for admin).
  Future<RecruitmentExamResult?> getExamResult(String applicationId) async {
    final all = await getExamResultsByApplication();
    return all[applicationId];
  }

  /// Fetch all exam results for admin (join or separate).
  Future<Map<String, RecruitmentExamResult>>
  getExamResultsByApplication() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/applications/exam-results',
      );
      final rows = res.data?['examResults'] as List<dynamic>? ?? [];
      final map = <String, RecruitmentExamResult>{};
      for (final e in rows) {
        final m = Map<String, dynamic>.from(e as Map);
        final appId = m['application_id'] as String;
        map[appId] = RecruitmentExamResult(
          id: m['id'] as String,
          applicationId: appId,
          scorePercent: (m['score_percent'] as num?)?.toDouble() ?? 0,
          passed: m['passed'] as bool? ?? false,
          answersJson: m['answers_json'] as Map<String, dynamic>?,
          submittedAt: m['submitted_at'] != null
              ? DateTime.tryParse(m['submitted_at'] as String)
              : null,
        );
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Get exam questions for an exam type (e.g. 'bei'), ordered by sort_order. Returns list of question text.
  Future<List<String>> getExamQuestions(String examType) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/exam-questions/$examType',
      );
      final data = res.data;
      final list = (data?['questions'] as List<dynamic>?) ?? [];
      return list
          .map((e) => (e as Map)['question_text']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save exam questions for an exam type. Replaces all existing questions for that type.
  Future<void> saveExamQuestions(
    String examType,
    List<String> questions,
  ) async {
    // Use backend to avoid Supabase RLS issues (app authenticates via API JWT).
    try {
      await ApiClient.instance.put(
        '/api/rsp/exam-questions/$examType',
        data: {'questions': questions},
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final details =
          (data is Map && (data['details'] != null || data['error'] != null))
          ? (data['details'] ?? data['error'])
          : null;
      throw Exception(
        details != null
            ? 'Save failed: $details'
            : 'Save failed: ${e.message ?? e.toString()}',
      );
    }
  }

  /// Get multiple-choice exam questions (e.g. 'general'). Returns list of { question_text, options: List<String>, correct: int }.
  Future<List<Map<String, dynamic>>> getExamQuestionsWithOptions(
    String examType,
  ) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/exam-questions/$examType',
      );
      final data = res.data;
      final rows = (data?['questions'] as List<dynamic>?) ?? [];

      final list = <Map<String, dynamic>>[];
      for (final row in rows) {
        final m = Map<String, dynamic>.from(row as Map);
        final optionsJson = m['options_json'];
        final optionsList = optionsJson is List
            ? optionsJson.map((x) => x.toString()).toList()
            : <String>[];

        list.add({
          'question_text': m['question_text']?.toString() ?? '',
          'options': optionsList,
          'correct': (m['correct_index'] as num?)?.toInt() ?? 0,
        });
      }
      return list
          .where((x) => (x['question_text'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save multiple-choice exam questions. Replaces all existing for that type.
  Future<void> saveExamQuestionsWithOptions(
    String examType,
    List<Map<String, dynamic>> questions,
  ) async {
    // Use backend to avoid Supabase RLS issues (app authenticates via API JWT).
    try {
      await ApiClient.instance.put(
        '/api/rsp/exam-questions/$examType',
        data: {
          'questions': questions.map((q) {
            return {
              'question_text': q['question_text'],
              'options': q['options'] ?? <dynamic>[],
              'correct': q['correct'],
            };
          }).toList(),
        },
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final details =
          (data is Map && (data['details'] != null || data['error'] != null))
          ? (data['details'] ?? data['error'])
          : null;
      throw Exception(
        details != null
            ? 'Save failed: $details'
            : 'Save failed: ${e.message ?? e.toString()}',
      );
    }
  }

  /// Update existing exam result (e.g. after General exam; merge into answers_json and set score/passed).
  Future<void> updateExamResult(
    String applicationId, {
    Map<String, dynamic>? answersJson,
    double? scorePercent,
    bool? passed,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (answersJson != null) updates['answers_json'] = answersJson;
    if (scorePercent != null) updates['score_percent'] = scorePercent;
    if (passed != null) updates['passed'] = passed;
    await _client
        .from(RecruitmentExamResult.tableName)
        .update(updates)
        .eq('application_id', applicationId);
  }

  /// Re-score applicants for `general_info` exam results using the current answer key
  /// stored in `recruitment_exam_questions.correct_index`.
  ///
  /// This is useful when the admin edits the answer key after applicants already submitted.
  // (Auto-correct/rescore helpers removed per your request.)
}
