import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';

class LeaveFormSignatoryInfo {
  const LeaveFormSignatoryInfo({this.userId, this.name, this.title});

  final String? userId;
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
      userId: value['user_id']?.toString(),
      name: name == null || name.isEmpty ? null : name,
      title: title == null || title.isEmpty ? null : title,
    );
  }
}

class LeaveFormSignatories {
  const LeaveFormSignatories({
    this.certificationOfficer,
    this.recommendationOfficer,
    this.approvingAuthority,
    this.applicantSignature,
    this.departmentHeadSignature,
    this.hrApproverSignature,
  });

  final LeaveFormSignatoryInfo? certificationOfficer;
  final LeaveFormSignatoryInfo? recommendationOfficer;
  final LeaveFormSignatoryInfo? approvingAuthority;
  final DocuTrackerSourceSignature? applicantSignature;
  final DocuTrackerSourceSignature? departmentHeadSignature;
  final DocuTrackerSourceSignature? hrApproverSignature;
}

LeaveFormSignatories composeLeaveFormSignatories({
  LeaveFormSignatoryInfo? certificationOfficer,
  LeaveFormSignatoryInfo? recommendationOfficer,
  LeaveFormSignatoryInfo? approvingAuthority,
  DocuTrackerSourceSignature? applicantSignature,
  DocuTrackerSourceSignature? departmentHeadSignature,
  DocuTrackerSourceSignature? hrApproverSignature,
}) {
  DocuTrackerSourceSignature? officialSignature(
    LeaveFormSignatoryInfo? official,
    DocuTrackerSourceSignature? signature,
  ) {
    final officialId = _nonBlank(official?.userId);
    return officialId != null &&
            signature?.isSigned == true &&
            _nonBlank(signature?.signedBy) == officialId
        ? signature
        : null;
  }

  return LeaveFormSignatories(
    certificationOfficer: certificationOfficer?.hasName == true
        ? certificationOfficer
        : null,
    recommendationOfficer: recommendationOfficer,
    approvingAuthority: approvingAuthority,
    applicantSignature: applicantSignature,
    departmentHeadSignature: officialSignature(
      recommendationOfficer,
      departmentHeadSignature,
    ),
    hrApproverSignature: officialSignature(
      approvingAuthority,
      hrApproverSignature,
    ),
  );
}

Future<LeaveFormSignatories> loadLeaveFormSignatories({
  required LeaveRequest request,
}) async {
  // Fire both independent API calls concurrently — the signatories endpoint
  // and the DocuTracker signature lookup do not depend on each other.
  final requestId = request.id;
  final results = await Future.wait([
    _fetchSignatoryRoles(request),
    if (requestId != null && requestId.isNotEmpty)
      DocuTrackerRepository.instance.getSourceSignatures(
        sourceModule: 'dtr',
        sourceTable: 'leave_requests',
        sourceRecordId: requestId,
      )
    else
      Future.value(null),
  ]);

  final roles = results[0] as _SignatoryRoles;
  DocuTrackerSourceSignature? applicantSignature;
  DocuTrackerSourceSignature? departmentHeadSignature;
  DocuTrackerSourceSignature? hrApproverSignature;
  final sigResult = results[1];
  if (sigResult is DocuTrackerSuccess<DocuTrackerSourceSignatureBundle>) {
    applicantSignature = sigResult.value.signatureFor('applicant');
    departmentHeadSignature = sigResult.value.signatureFor('department_head');
    hrApproverSignature = sigResult.value.signatureFor('hr_approver');
  }

  return composeLeaveFormSignatories(
    certificationOfficer: roles.certification,
    recommendationOfficer: roles.recommendation,
    approvingAuthority: roles.approvingAuthority,
    applicantSignature: applicantSignature,
    departmentHeadSignature: departmentHeadSignature,
    hrApproverSignature: hrApproverSignature,
  );
}

/// Fetches the named signatory roles from the backend. Returns an empty
/// [_SignatoryRoles] on any error so printing still proceeds.
Future<_SignatoryRoles> _fetchSignatoryRoles(LeaveRequest request) async {
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
    return _SignatoryRoles(
      certification: LeaveFormSignatoryInfo.fromJson(
        data['hr_certification_officer'],
      ),
      recommendation: LeaveFormSignatoryInfo.fromJson(
        data['recommendation_officer'],
      ),
      approvingAuthority: LeaveFormSignatoryInfo.fromJson(
        data['approving_authority'],
      ),
    );
  } catch (_) {
    // Printing should still work even if the optional signatory lookup fails.
    return const _SignatoryRoles();
  }
}

class _SignatoryRoles {
  const _SignatoryRoles({
    this.certification,
    this.recommendation,
    this.approvingAuthority,
  });

  final LeaveFormSignatoryInfo? certification;
  final LeaveFormSignatoryInfo? recommendation;
  final LeaveFormSignatoryInfo? approvingAuthority;
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
