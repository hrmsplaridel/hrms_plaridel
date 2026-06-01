import 'dart:convert';
import 'package:dio/dio.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/config.dart';
import 'rsp_screening_scores.dart';

/// Required Step 1 documents (API `docKind` values match backend).
enum RspApplicationDocKind {
  applicationLetter('application_letter'),
  resume('resume'),
  tor('tor'),
  eligibilityTrainings('eligibility_trainings');

  const RspApplicationDocKind(this.apiValue);
  final String apiValue;

  static RspApplicationDocKind? fromStorageFileName(String fileName) {
    for (final k in RspApplicationDocKind.values) {
      if (fileName.startsWith('${k.apiValue}_')) return k;
    }
    return null;
  }
}

/// One recruitment application (Step 1: basic info / documents).
class RecruitmentApplication {
  const RecruitmentApplication({
    required this.id,
    required this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    this.sex,
    required this.email,
    this.phone,
    this.resumeNotes,
    this.positionAppliedFor,
    this.attachmentPath,
    this.attachmentName,
    this.docApplicationLetterPath,
    this.docApplicationLetterName,
    this.docResumePath,
    this.docResumeName,
    this.docTorPath,
    this.docTorName,
    this.docEligibilityTrainingsPath,
    this.docEligibilityTrainingsName,
    required this.status,
    this.finalInterviewAt,
    this.finalInterviewPassed,
    this.hiredUserId,
    this.hrAccountSetupDone = false,
    this.hireCredentialsEmailSentAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final String? sex;
  final String email;
  final String? phone;
  final String? resumeNotes;

  /// Job title / vacancy headline the applicant chose on the landing page (e.g. "IT Staff").
  final String? positionAppliedFor;
  final String? attachmentPath;
  final String? attachmentName;
  final String? docApplicationLetterPath;
  final String? docApplicationLetterName;
  final String? docResumePath;
  final String? docResumeName;
  final String? docTorPath;
  final String? docTorName;
  final String? docEligibilityTrainingsPath;
  final String? docEligibilityTrainingsName;
  final String status; // submitted, exam_taken, passed, failed, registered
  /// Set by HR after the applicant passes the screening exam (final interview appointment).
  final DateTime? finalInterviewAt;

  /// In-person final interview result: null = not recorded, true/false = pass/fail.
  final bool? finalInterviewPassed;

  /// Linked `users.id` after HR creates an employee account from this application.
  final String? hiredUserId;

  /// HR-only monitoring flag: shown to applicants on Step 8 (no employee record required).
  final bool hrAccountSetupDone;

  /// Set when admin successfully sends hire credentials email (POST send-hire-email).
  final DateTime? hireCredentialsEmailSentAt;

  bool get hireCredentialsEmailSent => hireCredentialsEmailSentAt != null;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String? docPath(RspApplicationDocKind kind) {
    switch (kind) {
      case RspApplicationDocKind.applicationLetter:
        return docApplicationLetterPath;
      case RspApplicationDocKind.resume:
        return docResumePath;
      case RspApplicationDocKind.tor:
        return docTorPath;
      case RspApplicationDocKind.eligibilityTrainings:
        return docEligibilityTrainingsPath;
    }
  }

  String? docDisplayName(RspApplicationDocKind kind) {
    switch (kind) {
      case RspApplicationDocKind.applicationLetter:
        return docApplicationLetterName;
      case RspApplicationDocKind.resume:
        return docResumeName;
      case RspApplicationDocKind.tor:
        return docTorName;
      case RspApplicationDocKind.eligibilityTrainings:
        return docEligibilityTrainingsName;
    }
  }

  static const String tableName = 'recruitment_applications';
  static bool? _parseTriStateBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == 't' || s == '1') return true;
    if (s == 'false' || s == 'f' || s == '0') return false;
    return null;
  }

  static String? _parseUuidString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory RecruitmentApplication.fromJson(Map<String, dynamic> json) {
    return RecruitmentApplication(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      firstName: json['first_name'] as String?,
      middleName: json['middle_name'] as String?,
      lastName: json['last_name'] as String?,
      suffix: json['suffix'] as String?,
      sex: json['sex'] as String?,
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      resumeNotes: json['resume_notes'] as String?,
      positionAppliedFor: json['position_applied_for'] as String?,
      attachmentPath: json['attachment_path'] as String?,
      attachmentName: json['attachment_name'] as String?,
      docApplicationLetterPath: json['doc_application_letter_path'] as String?,
      docApplicationLetterName: json['doc_application_letter_name'] as String?,
      docResumePath: json['doc_resume_path'] as String?,
      docResumeName: json['doc_resume_name'] as String?,
      docTorPath: json['doc_tor_path'] as String?,
      docTorName: json['doc_tor_name'] as String?,
      docEligibilityTrainingsPath:
          json['doc_eligibility_trainings_path'] as String?,
      docEligibilityTrainingsName:
          json['doc_eligibility_trainings_name'] as String?,
      status: json['status'] as String? ?? 'submitted',
      finalInterviewAt: json['final_interview_at'] != null
          ? DateTime.tryParse(json['final_interview_at'].toString())
          : null,
      finalInterviewPassed: _parseTriStateBool(json['final_interview_passed']),
      hiredUserId: _parseUuidString(json['hired_user_id']),
      hrAccountSetupDone: json['hr_account_setup_done'] == true,
      hireCredentialsEmailSentAt: json['hire_credentials_email_sent_at'] != null
          ? DateTime.tryParse(json['hire_credentials_email_sent_at'].toString())
          : null,
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
      // Prefer new fields; backend will compute full_name.
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'suffix': suffix,
      'sex': sex,
      'fullName': fullName,
      'email': email,
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'resume_notes': resumeNotes?.trim().isEmpty == true
          ? null
          : resumeNotes?.trim(),
      'position_applied_for': positionAppliedFor?.trim().isEmpty == true
          ? null
          : positionAppliedFor?.trim(),
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
    this.beiGradingComplete = true,
  });

  final String id;
  final String applicationId;
  final double scorePercent;
  final bool passed;
  final Map<String, dynamic>? answersJson;
  final DateTime? submittedAt;

  /// False while BEI narratives exist but HR has not entered all scores (public API).
  final bool beiGradingComplete;

  static const String tableName = 'recruitment_exam_results';

  /// From public [GET /api/rsp/applications/by-email] `examResult` (no answers_json).
  factory RecruitmentExamResult.fromByEmailJson(Map<String, dynamic> json) {
    final appId = _RecruitmentJson.coerceUuidString(json['application_id']);
    final id = _RecruitmentJson.coerceUuidString(json['id']);
    final bgc = json['bei_grading_complete'];
    return RecruitmentExamResult(
      id: id ?? '',
      applicationId: appId ?? '',
      scorePercent: _RecruitmentJson.coerceDouble(json['score_percent']),
      passed: _RecruitmentJson.coerceBool(json['passed']),
      answersJson: null,
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'].toString())
          : null,
      beiGradingComplete: bgc is bool ? bgc : true,
    );
  }
}

/// Public lookup: application row plus optional screening exam (same payload as by-email API).
class RspApplicantLookup {
  const RspApplicantLookup({required this.application, this.examResult});

  final RecruitmentApplication application;
  final RecruitmentExamResult? examResult;
}

class _RecruitmentJson {
  static String? coerceUuidString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double coerceDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static bool coerceBool(dynamic v) {
    if (v is bool) return v;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }
}

/// [GET /api/rsp/email-verification/config]: whether Step 1 must verify email via OTP before submit.
class RspEmailVerificationConfig {
  const RspEmailVerificationConfig({
    required this.requiresOtpForNewApplication,
    required this.otpTtlMs,
  });

  final bool requiresOtpForNewApplication;

  /// Server OTP lifetime for display (code validity), not JWT lifetime.
  final int otpTtlMs;

  static RspEmailVerificationConfig fromJson(Map<String, dynamic>? m) {
    if (m == null) {
      return const RspEmailVerificationConfig(
        requiresOtpForNewApplication: false,
        otpTtlMs: 600000,
      );
    }
    final req =
        m['requiresOtpForNewApplication'] == true || m['otpEnabled'] == true;
    final ttlRaw = (m['otpTtlMs'] as num?)?.toInt() ?? 600000;
    final ttl = ttlRaw.clamp(60_000, 3_600_000).toInt();
    return RspEmailVerificationConfig(
      requiresOtpForNewApplication: req,
      otpTtlMs: ttl,
    );
  }
}

/// Repo for recruitment applications and exam results.
class RecruitmentRepo {
  RecruitmentRepo._();
  static final RecruitmentRepo instance = RecruitmentRepo._();

  /// Seconds per MCQ exam (`general`, `math`, `general_info`). Used when API is unavailable.
  static const Map<String, int> kDefaultRspExamTimeLimitSeconds = {
    'general': 45 * 60,
    'math': 45 * 60,
    'general_info': 10 * 60,
  };

  /// Step 1 email OTP enrollment (backend EmailJS template + JWT secret).
  Future<RspEmailVerificationConfig> fetchRspEmailVerificationConfig() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/email-verification/config',
      );
      return RspEmailVerificationConfig.fromJson(res.data);
    } on DioException {
      return const RspEmailVerificationConfig(
        requiresOtpForNewApplication: false,
        otpTtlMs: 600000,
      );
    }
  }

  /// Sends a 6-digit code to the applicant inbox (public).
  ///
  /// Optional [fullName] is sent as `fullName` for EmailJS {{to_name}} when provided.
  Future<void> sendRspApplicantEmailOtp(
    String email, {
    String? fullName,
  }) async {
    final data = <String, dynamic>{'email': email.trim()};
    final n = fullName?.trim();
    if (n != null && n.isNotEmpty) data['fullName'] = n;
    await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/rsp/email-verification/send',
      data: data,
    );
  }

  /// Confirms code; returns short-lived token for [insertApplication].
  Future<String> verifyRspApplicantEmailOtp(String email, String code) async {
    final res = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/rsp/email-verification/verify',
      data: <String, dynamic>{
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
      },
    );
    final t = res.data?['emailVerificationToken']?.toString().trim();
    if (t == null || t.isEmpty) {
      throw Exception('Verification did not return a token. Try again.');
    }
    return t;
  }

  /// Delete an applicant and related exam result rows (PostgreSQL via API).
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
      throw Exception(
        details != null
            ? 'Delete failed: $details'
            : 'Delete failed: ${e.message ?? e.toString()}',
      );
    }
  }

  /// Insert new application (Step 1). Returns the created row id.
  ///
  /// When the server enables email OTP, pass [emailVerificationToken] from
  /// [verifyRspApplicantEmailOtp] for the same address as [app.email].
  Future<String> insertApplication(
    RecruitmentApplication app, {
    String? emailVerificationToken,
  }) async {
    final email = app.email.trim();
    try {
      final body = <String, dynamic>{
        'firstName': app.firstName,
        'middleName': app.middleName,
        'lastName': app.lastName,
        'suffix': app.suffix,
        'sex': app.sex,
        'fullName': app.fullName, // legacy fallback
        'email': email.isEmpty ? '' : email.toLowerCase(),
        'phone': app.phone,
        'resumeNotes': app.resumeNotes,
        'positionAppliedFor': app.positionAppliedFor,
        'status': app.status,
      };
      final tok = emailVerificationToken?.trim();
      if (tok != null && tok.isNotEmpty) {
        body['emailVerificationToken'] = tok;
      }
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/rsp/applications',
        data: body,
      );
      final appRow = res.data?['application'] as Map<String, dynamic>?;
      final id = appRow?['id'];
      if (id == null) throw Exception('Insert failed: missing id in response');
      return id.toString();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final err = data['error']?.toString().trim();
        if (err != null && err.isNotEmpty) {
          throw Exception(err);
        }
      }
      rethrow;
    }
  }

  /// Update application status (e.g. after exam).
  Future<void> updateApplicationStatus(String id, String status) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$id/status',
      data: {'status': status},
    );
  }

  /// Admin: set or clear final interview date/time for an applicant (after they passed the exam).
  Future<void> updateFinalInterviewAt(
    String applicationId,
    DateTime? at,
  ) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$applicationId/final-interview',
      data: <String, dynamic>{
        'finalInterviewAt': at == null
            ? null
            : (at.isUtc ? at : at.toUtc()).toIso8601String(),
      },
    );
  }

  /// Admin: record final interview pass/fail, or `null` to clear (pending).
  Future<void> updateFinalInterviewPassed(
    String applicationId,
    bool? passed,
  ) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$applicationId/final-interview-outcome',
      data: <String, dynamic>{'passed': passed},
    );
  }

  /// Admin: Step 8 monitoring — whether HR marks employee account setup as done (applicant-facing only).
  Future<void> updateHrAccountSetupMonitoring(
    String applicationId,
    bool done,
  ) async {
    await ApiClient.instance.put<dynamic>(
      '/api/rsp/applications/$applicationId/hr-account-setup-monitoring',
      data: <String, dynamic>{'done': done},
    );
  }

  /// Admin: link newly created employee user to this application (sets status `registered`).
  Future<void> linkHiredUser(String applicationId, String userId) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$applicationId/hired-link',
      data: {'userId': userId},
    );
  }

  /// Admin: update applicant name, email, and phone on the application row.
  Future<RecruitmentApplication> updateApplicationBasicInfo(
    String applicationId, {
    required String fullName,
    required String email,
    String? phone,
  }) async {
    try {
      final res = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/rsp/applications/$applicationId/basic-info',
        data: <String, dynamic>{
          'fullName': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'phone': phone == null || phone.trim().isEmpty ? null : phone.trim(),
        },
      );
      final row = res.data?['application'] as Map<String, dynamic>?;
      if (row == null) {
        throw Exception('Update failed: missing application in response');
      }
      return RecruitmentApplication.fromJson(row);
    } on DioException catch (e) {
      final data = e.response?.data;
      String? msg;
      if (data is Map) {
        msg = data['details']?.toString() ?? data['error']?.toString();
      }
      throw Exception(
        msg != null && msg.isNotEmpty
            ? msg
            : 'Update failed: ${e.message ?? e.toString()}',
      );
    }
  }

  /// Admin: send congratulations + HRMS username/password via server SMTP to the
  /// applicant email stored on the application (not the admin’s address).
  Future<void> sendHireCredentialEmail(
    String applicationId,
    String username,
    String password,
  ) async {
    try {
      await ApiClient.instance.post<void>(
        '/api/rsp/applications/$applicationId/send-hire-email',
        data: <String, dynamic>{'username': username, 'password': password},
        options: Options(
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      String? msg;
      if (data is Map) {
        msg = data['details']?.toString() ?? data['error']?.toString();
      }
      throw Exception(
        msg != null && msg.isNotEmpty
            ? msg
            : 'Send failed: ${e.message ?? e.toString()}',
      );
    }
  }

  /// Upload a single attachment to storage and set path on application. Path = {applicationId}/{fileName}.
  Future<void> uploadAttachment(
    String applicationId,
    List<int> fileBytes,
    String fileName,
  ) async {
    await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
      '/api/rsp/applications/$applicationId/attachment-file',
      bytes: fileBytes,
      fileName: fileName,
    );
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
      final uniqueName = '${now}_${i}_${f.fileName}';
      await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
        '/api/rsp/applications/$applicationId/attachment-file?updateDb=0',
        bytes: f.bytes,
        fileName: uniqueName,
      );
    }
    final first = files.first;
    await setApplicationAttachment(
      applicationId,
      '$applicationId/${now}_0_${first.fileName}',
      first.fileName,
    );
  }

  /// Upload one required document for Step 1 (`kind` selects DB column on the backend).
  Future<void> uploadTypedDocument(
    String applicationId,
    RspApplicationDocKind kind,
    List<int> fileBytes,
    String fileName,
  ) async {
    if (fileName.trim().isEmpty) {
      throw ArgumentError('fileName is required');
    }
    if (!fileName.trim().toLowerCase().endsWith('.pdf')) {
      throw ArgumentError('Recruitment attachments must be PDF files (.pdf).');
    }
    final kindParam = Uri.encodeQueryComponent(kind.apiValue);
    await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
      '/api/rsp/applications/$applicationId/attachment-file?kind=$kindParam',
      bytes: fileBytes,
      fileName: fileName,
    );
  }

  Future<void> setApplicationTypedDocument(
    String applicationId,
    String storagePath,
    String displayFileName,
    RspApplicationDocKind kind,
  ) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$applicationId/attachment',
      data: {
        'path': storagePath,
        'fileName': displayFileName,
        'docKind': kind.apiValue,
      },
    );
  }

  /// URL for admin to preview/download (`/api/files/recruitment-attachment?token=...`).
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
    return null;
  }

  /// Remove an attachment file from server disk (admin). Path is e.g. applicationId/filename.
  Future<void> deleteAttachment(String path) async {
    await ApiClient.instance.delete<void>(
      '/api/rsp/applications/attachment-file',
      queryParameters: {'path': path},
    );
  }

  /// List attachment paths on server (`uploads/rsp-attachments`). Admin JWT required.
  Future<List<Map<String, String>>> listStorageAttachmentPaths() async {
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/rsp/storage/attachment-index',
    );
    final list = res.data ?? [];
    return list
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'applicationId': m['applicationId']?.toString() ?? '',
            'path': m['path']?.toString() ?? '',
            'fileName': m['fileName']?.toString() ?? '',
          };
        })
        .where((e) => e['path']!.isNotEmpty)
        .toList();
  }

  /// Set attachment path and name on an application (e.g. after syncing from storage). Admin only.
  Future<void> setApplicationAttachment(
    String applicationId,
    String path,
    String fileName,
  ) async {
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/$applicationId/attachment',
      data: {'path': path, 'fileName': fileName},
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

  /// Backfill a typed document slot from storage when the filename starts with `{kind}_`.
  Future<bool> setApplicationTypedAttachmentIfMissing(
    String applicationId,
    String path,
    String fileName,
    RspApplicationDocKind kind,
  ) async {
    try {
      final res = await ApiClient.instance.put<Map<String, dynamic>>(
        '/api/rsp/applications/$applicationId/attachment-if-missing',
        data: {'path': path, 'fileName': fileName, 'docKind': kind.apiValue},
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
          .map(
            (e) => RecruitmentApplication.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get the latest application by email (for applicant "Continue application").
  /// Includes [RspApplicantLookup.examResult] when a screening exam row exists (public API).
  Future<RspApplicantLookup?> getApplicationByEmail(String email) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/applications/by-email',
        queryParameters: {'email': email.trim().toLowerCase()},
      );
      final data = res.data;
      final row = data?['application'] as Map<String, dynamic>?;
      if (row == null) return null;
      final app = RecruitmentApplication.fromJson(row);
      RecruitmentExamResult? exam;
      final er = data?['examResult'];
      if (er is Map) {
        exam = RecruitmentExamResult.fromByEmailJson(
          Map<String, dynamic>.from(er),
        );
      }
      return RspApplicantLookup(application: app, examResult: exam);
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
    return all[applicationId.toLowerCase()];
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
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final appId = _coerceUuidString(m['application_id']);
        final id = _coerceUuidString(m['id']);
        if (appId == null || id == null) continue;
        // Map keys lowercase so lookups match `app.id` regardless of UUID casing from API/DB.
        final aj = _coerceJsonObjectMap(m['answers_json']);
        map[appId.toLowerCase()] = RecruitmentExamResult(
          id: id,
          applicationId: appId,
          scorePercent: _coerceDouble(m['score_percent']),
          passed: _coerceBool(m['passed']),
          answersJson: aj,
          submittedAt: m['submitted_at'] != null
              ? DateTime.tryParse(m['submitted_at'].toString())
              : null,
          beiGradingComplete: RspScreeningScores.isBeiFullyGraded(aj),
        );
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static String? _coerceUuidString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double _coerceDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static bool _coerceBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 't' || s == 'yes';
  }

  /// API / Postgres may return JSONB as a Map or (rarely) a JSON string.
  static Map<String, dynamic>? _coerceJsonObjectMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((key, val) => MapEntry(key.toString(), val)),
      );
    }
    if (v is String && v.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) {
          return Map<String, dynamic>.from(
            decoded.map((key, val) => MapEntry(key.toString(), val)),
          );
        }
      } catch (_) {}
    }
    return null;
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

  /// Get multiple-choice exam questions (e.g. `general`). Each map has `question_text`, `options`, and `correct`.
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

  /// Per-exam countdown in seconds (0 = no limit). Keys: `general`, `math`, `general_info`.
  Future<Map<String, int>> getExamTimeLimits() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/exam-time-limits',
      );
      final raw = res.data?['limits'];
      final out = Map<String, int>.from(kDefaultRspExamTimeLimitSeconds);
      if (raw is Map) {
        for (final key in kDefaultRspExamTimeLimitSeconds.keys) {
          final v = raw[key];
          if (v is num) {
            out[key] = v.toInt().clamp(0, 86400);
          }
        }
      }
      return out;
    } catch (_) {
      return Map<String, int>.from(kDefaultRspExamTimeLimitSeconds);
    }
  }

  /// Admin: set one exam's time limit in seconds (0 = no limit for applicants).
  Future<void> saveExamTimeLimitSeconds(String examType, int seconds) async {
    final s = seconds.clamp(0, 86400);
    try {
      await ApiClient.instance.put(
        '/api/rsp/exam-time-limits',
        data: {examType: s},
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
  ///
  /// When [syncApplicationStatus] is true, the backend also sets `recruitment_applications.status`
  /// to `passed` or `failed` (e.g. after HR grades BEI and the overall score changes).
  Future<void> updateExamResult(
    String applicationId, {
    Map<String, dynamic>? answersJson,
    double? scorePercent,
    bool? passed,
    bool syncApplicationStatus = false,
  }) async {
    final updates = <String, dynamic>{};
    if (answersJson != null) updates['answers_json'] = answersJson;
    if (scorePercent != null) updates['score_percent'] = scorePercent;
    if (passed != null) updates['passed'] = passed;
    if (syncApplicationStatus) {
      updates['sync_application_status'] = true;
    }
    if (updates.isEmpty) return;
    await ApiClient.instance.put<void>(
      '/api/rsp/applications/exam-results/$applicationId',
      data: updates,
    );
  }

  /// Re-score applicants for `general_info` exam results using the current answer key
  /// stored in `recruitment_exam_questions.correct_index`.
  ///
  /// This is useful when the admin edits the answer key after applicants already submitted.
  // (Auto-correct/rescore helpers removed per your request.)
}
