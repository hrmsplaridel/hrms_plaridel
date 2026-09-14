import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

class LeaveFormSignatoryInfo {
  const LeaveFormSignatoryInfo({this.name, this.title});

  final String? name;
  final String? title;

  bool get hasName => name != null && name!.trim().isNotEmpty;

  static LeaveFormSignatoryInfo? fromJson(dynamic value) {
    if (value is! Map) return null;
    final name = value['name']?.toString().trim();
    final title = value['position_title']?.toString().trim();
    if ((name == null || name.isEmpty) && (title == null || title.isEmpty)) {
      return null;
    }
    return LeaveFormSignatoryInfo(
      name: name == null || name.isEmpty ? null : name,
      title: title == null || title.isEmpty ? null : title,
    );
  }
}

class LeaveFormSignatories {
  const LeaveFormSignatories({
    this.certificationOfficer,
    this.recommendationOfficer,
    this.applicantSignature,
    this.departmentHeadSignature,
    this.hrApproverSignature,
  });

  final LeaveFormSignatoryInfo? certificationOfficer;
  final LeaveFormSignatoryInfo? recommendationOfficer;
  final DocuTrackerSourceSignature? applicantSignature;
  final DocuTrackerSourceSignature? departmentHeadSignature;
  final DocuTrackerSourceSignature? hrApproverSignature;
}

Future<LeaveFormSignatories> loadLeaveFormSignatories({
  required LeaveRequest request,
}) async {
  LeaveFormSignatoryInfo? certification;
  LeaveFormSignatoryInfo? recommendation;
  DocuTrackerSourceSignature? applicantSignature;
  DocuTrackerSourceSignature? departmentHeadSignature;
  DocuTrackerSourceSignature? hrApproverSignature;

  try {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/leave/signatories',
      queryParameters: {
        'employee_id': request.userId,
        if (request.id != null && request.id!.isNotEmpty)
          'leave_request_id': request.id,
      },
    );
    final data = res.data ?? const <String, dynamic>{};
    certification = LeaveFormSignatoryInfo.fromJson(
      data['hr_certification_officer'],
    );
    recommendation = LeaveFormSignatoryInfo.fromJson(
      data['recommendation_officer'],
    );
  } catch (_) {
    // Printing should still work even if the optional signatory lookup fails.
  }

  final requestId = request.id;
  if (requestId != null && requestId.isNotEmpty) {
    final result = await DocuTrackerRepository.instance.getSourceSignatures(
      sourceModule: 'dtr',
      sourceTable: 'leave_requests',
      sourceRecordId: requestId,
    );
    if (result is DocuTrackerSuccess<DocuTrackerSourceSignatureBundle>) {
      applicantSignature = result.value.signatureFor('applicant');
      departmentHeadSignature = result.value.signatureFor('department_head');
      hrApproverSignature = result.value.signatureFor('hr_approver');
    }
  }

  final departmentHeadName =
      _nonBlank(departmentHeadSignature?.signerName) ??
      _nonBlank(request.departmentHeadReviewerName);
  if (departmentHeadName != null) {
    recommendation = LeaveFormSignatoryInfo(
      name: departmentHeadName,
      title: recommendation?.title ?? 'Department Head',
    );
  }

  return LeaveFormSignatories(
    certificationOfficer: certification?.hasName == true ? certification : null,
    recommendationOfficer: recommendation,
    applicantSignature: applicantSignature,
    departmentHeadSignature: departmentHeadSignature,
    hrApproverSignature: hrApproverSignature,
  );
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
