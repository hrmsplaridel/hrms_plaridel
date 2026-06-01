import 'package:hrms_plaridel/core/api/client.dart';
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
  });

  final LeaveFormSignatoryInfo? certificationOfficer;
  final LeaveFormSignatoryInfo? recommendationOfficer;
}

Future<LeaveFormSignatories> loadLeaveFormSignatories({
  required LeaveRequest request,
}) async {
  LeaveFormSignatoryInfo? certification;
  LeaveFormSignatoryInfo? recommendation;

  try {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/leave/signatories',
      queryParameters: {'employee_id': request.userId},
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

  final departmentHeadName = _nonBlank(request.departmentHeadReviewerName);
  if (recommendation == null && departmentHeadName != null) {
    recommendation = LeaveFormSignatoryInfo(
      name: departmentHeadName,
      title: 'Department Head',
    );
  }

  return LeaveFormSignatories(
    certificationOfficer: certification?.hasName == true ? certification : null,
    recommendationOfficer: recommendation,
  );
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
