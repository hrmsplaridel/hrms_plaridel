import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/config.dart';

/// Pre-training: invitation letter. Post-training: LAP + certificate.
enum LdTrainingRequirementDocKind {
  invitationLetter('invitation_letter'),
  lap('lap'),
  trainingCertificate('training_certificate');

  const LdTrainingRequirementDocKind(this.apiValue);
  final String apiValue;

  bool get isPreTraining => this == LdTrainingRequirementDocKind.invitationLetter;
}

class LdTrainingRequirementRecord {
  const LdTrainingRequirementRecord({
    required this.id,
    required this.employeeId,
    this.employeeName,
    this.employeeEmail,
    this.trainingTitle,
    this.docInvitationLetterPath,
    this.docInvitationLetterName,
    this.docLapPath,
    this.docLapName,
    this.docTrainingCertificatePath,
    this.docTrainingCertificateName,
    this.preRequirementsApproved = false,
    this.postRequirementsApproved = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String employeeId;
  final String? employeeName;
  final String? employeeEmail;
  final String? trainingTitle;
  final String? docInvitationLetterPath;
  final String? docInvitationLetterName;
  final String? docLapPath;
  final String? docLapName;
  final String? docTrainingCertificatePath;
  final String? docTrainingCertificateName;
  final bool preRequirementsApproved;
  final bool postRequirementsApproved;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasPreTrainingDoc =>
      docInvitationLetterPath != null && docInvitationLetterPath!.trim().isNotEmpty;

  bool get hasAllPostTrainingDocs {
    final lap = docLapPath != null && docLapPath!.trim().isNotEmpty;
    final cert = docTrainingCertificatePath != null &&
        docTrainingCertificatePath!.trim().isNotEmpty;
    return lap && cert;
  }

  String? docPath(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return docInvitationLetterPath;
      case LdTrainingRequirementDocKind.lap:
        return docLapPath;
      case LdTrainingRequirementDocKind.trainingCertificate:
        return docTrainingCertificatePath;
    }
  }

  String? docDisplayName(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return docInvitationLetterName;
      case LdTrainingRequirementDocKind.lap:
        return docLapName;
      case LdTrainingRequirementDocKind.trainingCertificate:
        return docTrainingCertificateName;
    }
  }

  factory LdTrainingRequirementRecord.fromJson(Map<String, dynamic> json) {
    return LdTrainingRequirementRecord(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String?,
      employeeEmail: json['employee_email'] as String?,
      trainingTitle: json['training_title'] as String?,
      docInvitationLetterPath: json['doc_invitation_letter_path'] as String?,
      docInvitationLetterName: json['doc_invitation_letter_name'] as String?,
      docLapPath: json['doc_lap_path'] as String?,
      docLapName: json['doc_lap_name'] as String?,
      docTrainingCertificatePath:
          json['doc_training_certificate_path'] as String?,
      docTrainingCertificateName:
          json['doc_training_certificate_name'] as String?,
      preRequirementsApproved: json['pre_requirements_approved'] == true,
      postRequirementsApproved: json['post_requirements_approved'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

class LdTrainingRequirementRepo {
  LdTrainingRequirementRepo._();
  static final LdTrainingRequirementRepo instance = LdTrainingRequirementRepo._();

  Future<List<LdTrainingRequirementRecord>> listAll() async {
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/ld/training-requirements',
    );
    return (res.data ?? [])
        .map(
          (e) => LdTrainingRequirementRecord.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<LdTrainingRequirementRecord> loadMine() async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/ld/training-requirements/mine',
    );
    final record = res.data?['record'];
    return LdTrainingRequirementRecord.fromJson(
      Map<String, dynamic>.from(record as Map),
    );
  }

  Future<LdTrainingRequirementRecord> updateMyTrainingTitle(
    String trainingTitle,
  ) async {
    final res = await ApiClient.instance.put<Map<String, dynamic>>(
      '/api/ld/training-requirements/mine',
      data: {'trainingTitle': trainingTitle.trim()},
    );
    return LdTrainingRequirementRecord.fromJson(
      Map<String, dynamic>.from(res.data?['record'] as Map),
    );
  }

  Future<void> uploadDocument(
    String recordId,
    LdTrainingRequirementDocKind kind,
    List<int> fileBytes,
    String fileName,
  ) async {
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError('Only PDF files are accepted.');
    }
    final kindParam = Uri.encodeQueryComponent(kind.apiValue);
    await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
      '/api/ld/training-requirements/$recordId/attachment-file?kind=$kindParam',
      bytes: fileBytes,
      fileName: fileName,
    );
  }

  Future<void> setPreApproved(String recordId, bool approved) async {
    await ApiClient.instance.put<void>(
      '/api/ld/training-requirements/$recordId/pre-approval',
      data: {'approved': approved},
    );
  }

  Future<void> setPostApproved(String recordId, bool approved) async {
    await ApiClient.instance.put<void>(
      '/api/ld/training-requirements/$recordId/post-approval',
      data: {'approved': approved},
    );
  }

  Future<String?> getAttachmentDownloadUrl(
    String attachmentPath, {
    String? fileName,
  }) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/ld/training-requirements/view-token',
        queryParameters: {
          'path': attachmentPath,
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
        },
      );
      final token = res.data?['token'] as String?;
      if (token == null || token.isEmpty) return null;
      final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
      return '$base/api/files/ld-training-requirement?token=${Uri.encodeComponent(token)}';
    } catch (_) {
      return null;
    }
  }
}
