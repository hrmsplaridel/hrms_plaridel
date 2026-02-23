import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'email': email,
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'resume_notes': resumeNotes?.trim().isEmpty == true ? null : resumeNotes?.trim(),
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

  /// Insert new application (Step 1). Returns the created row id.
  Future<String> insertApplication(RecruitmentApplication app) async {
    final email = app.email.trim();
    final res = await _client.from(RecruitmentApplication.tableName).insert({
      'full_name': app.fullName,
      'email': email.isEmpty ? null : email.toLowerCase(),
      'phone': app.phone,
      'resume_notes': app.resumeNotes,
      'status': app.status,
    }).select('id').single();
    return res['id'].toString();
  }

  /// Update application status (e.g. after exam).
  Future<void> updateApplicationStatus(String id, String status) async {
    await _client.from(RecruitmentApplication.tableName).update({'status': status, 'updated_at': DateTime.now().toIso8601String()}).eq('id', id);
  }

  /// Upload attachment to storage and set path on application. Path = {applicationId}/{fileName}.
  Future<void> uploadAttachment(String applicationId, List<int> fileBytes, String fileName) async {
    final path = '$applicationId/$fileName';
    await _client.storage.from(RecruitmentApplication.storageBucket).uploadBinary(path, Uint8List.fromList(fileBytes));
    await _client.from(RecruitmentApplication.tableName).update({
      'attachment_path': path,
      'attachment_name': fileName,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', applicationId);
  }

  /// Get a signed URL for admin to download the attachment (e.g. 1 hour expiry).
  Future<String?> getAttachmentDownloadUrl(String attachmentPath) async {
    try {
      final url = await _client.storage.from(RecruitmentApplication.storageBucket).createSignedUrl(attachmentPath, 3600);
      return url;
    } catch (_) {
      return null;
    }
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
            out.add({'applicationId': applicationId, 'path': path, 'fileName': file.name});
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
  Future<void> setApplicationAttachment(String applicationId, String path, String fileName) async {
    await _client.from(RecruitmentApplication.tableName).update({
      'attachment_path': path,
      'attachment_name': fileName,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', applicationId);
  }

  /// Update application attachment only if it is currently null (for backfill from storage).
  Future<bool> setApplicationAttachmentIfMissing(String applicationId, String path, String fileName) async {
    try {
      final res = await _client
          .from(RecruitmentApplication.tableName)
          .update({
            'attachment_path': path,
            'attachment_name': fileName,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', applicationId)
          .isFilter('attachment_path', null)
          .select('id');
      return (res as List).isNotEmpty;
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
    await _client.from('recruitment_exam_results').insert({
      'application_id': applicationId,
      'score_percent': scorePercent,
      'passed': passed,
      'answers_json': answersJson,
    });
    await updateApplicationStatus(applicationId, passed ? 'passed' : 'failed');
  }

  /// List all applications (for admin). Newest first.
  Future<List<RecruitmentApplication>> listApplications() async {
    try {
      final res = await _client.from(RecruitmentApplication.tableName).select().order('created_at', ascending: false);
      return (res as List).map((e) => RecruitmentApplication.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get the latest application by email (for applicant "Continue application"). Returns null if none.
  Future<RecruitmentApplication?> getApplicationByEmail(String email) async {
    try {
      final res = await _client
          .from(RecruitmentApplication.tableName)
          .select()
          .eq('email', email.trim().toLowerCase())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return RecruitmentApplication.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null;
    }
  }

  /// Get exam result for an application (for admin).
  Future<RecruitmentExamResult?> getExamResult(String applicationId) async {
    try {
      final res = await _client.from(RecruitmentExamResult.tableName).select().eq('application_id', applicationId).maybeSingle();
      if (res == null) return null;
      final m = Map<String, dynamic>.from(res as Map);
      return RecruitmentExamResult(
        id: m['id'] as String,
        applicationId: m['application_id'] as String,
        scorePercent: (m['score_percent'] as num?)?.toDouble() ?? 0,
        passed: m['passed'] as bool? ?? false,
        answersJson: m['answers_json'] as Map<String, dynamic>?,
        submittedAt: m['submitted_at'] != null ? DateTime.tryParse(m['submitted_at'] as String) : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetch all exam results for admin (join or separate).
  Future<Map<String, RecruitmentExamResult>> getExamResultsByApplication() async {
    try {
      final res = await _client.from(RecruitmentExamResult.tableName).select();
      final map = <String, RecruitmentExamResult>{};
      for (final e in res as List) {
        final m = Map<String, dynamic>.from(e as Map);
        final appId = m['application_id'] as String;
        map[appId] = RecruitmentExamResult(
          id: m['id'] as String,
          applicationId: appId,
          scorePercent: (m['score_percent'] as num?)?.toDouble() ?? 0,
          passed: m['passed'] as bool? ?? false,
          answersJson: m['answers_json'] as Map<String, dynamic>?,
          submittedAt: m['submitted_at'] != null ? DateTime.tryParse(m['submitted_at'] as String) : null,
        );
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static const String _examQuestionsTable = 'recruitment_exam_questions';

  /// Get exam questions for an exam type (e.g. 'bei'), ordered by sort_order. Returns list of question text.
  Future<List<String>> getExamQuestions(String examType) async {
    try {
      final res = await _client
          .from(_examQuestionsTable)
          .select('question_text')
          .eq('exam_type', examType)
          .order('sort_order', ascending: true);
      return (res as List).map((e) => (e as Map)['question_text'] as String? ?? '').where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save exam questions for an exam type. Replaces all existing questions for that type.
  Future<void> saveExamQuestions(String examType, List<String> questions) async {
    await _client.from(_examQuestionsTable).delete().eq('exam_type', examType);
    if (questions.isEmpty) return;
    await _client.from(_examQuestionsTable).insert(
      questions.asMap().entries.map((e) => {
        'exam_type': examType,
        'sort_order': e.key + 1,
        'question_text': e.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList(),
    );
  }

  /// Get multiple-choice exam questions (e.g. 'general'). Returns list of { question_text, options: List<String>, correct: int }.
  Future<List<Map<String, dynamic>>> getExamQuestionsWithOptions(String examType) async {
    try {
      final res = await _client
          .from(_examQuestionsTable)
          .select('question_text, options_json, correct_index')
          .eq('exam_type', examType)
          .order('sort_order', ascending: true);
      final list = <Map<String, dynamic>>[];
      for (final e in res as List) {
        final m = Map<String, dynamic>.from(e as Map);
        final options = m['options_json'] as List?;
        final optionsList = options?.map((x) => x.toString()).toList() ?? <String>[];
        list.add({
          'question_text': m['question_text'] as String? ?? '',
          'options': optionsList,
          'correct': (m['correct_index'] as num?)?.toInt() ?? 0,
        });
      }
      return list.where((x) => (x['question_text'] as String).isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save multiple-choice exam questions. Replaces all existing for that type.
  Future<void> saveExamQuestionsWithOptions(String examType, List<Map<String, dynamic>> questions) async {
    await _client.from(_examQuestionsTable).delete().eq('exam_type', examType);
    if (questions.isEmpty) return;
    await _client.from(_examQuestionsTable).insert(
      questions.asMap().entries.map((e) {
        final q = e.value;
        final options = q['options'] as List<dynamic>?;
        return {
          'exam_type': examType,
          'sort_order': e.key + 1,
          'question_text': q['question_text'] as String? ?? '',
          'options_json': options?.map((x) => x.toString()).toList(),
          'correct_index': (q['correct'] as num?)?.toInt(),
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList(),
    );
  }

  /// Update existing exam result (e.g. after General exam; merge into answers_json and set score/passed).
  Future<void> updateExamResult(String applicationId, {Map<String, dynamic>? answersJson, double? scorePercent, bool? passed}) async {
    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (answersJson != null) updates['answers_json'] = answersJson;
    if (scorePercent != null) updates['score_percent'] = scorePercent;
    if (passed != null) updates['passed'] = passed;
    await _client.from(RecruitmentExamResult.tableName).update(updates).eq('application_id', applicationId);
  }
}
