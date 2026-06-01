import 'package:flutter/foundation.dart';

/// When an admin opens **Create Account** from RSP (final interview passed), this holds
/// the recruitment row id and applicant fields so [AddEmployeeForm] can prefill and call
/// [RecruitmentRepo.linkHiredUser] after the employee is created.
class RecruitmentHirePrefill extends ChangeNotifier {
  String? applicationId;
  String? applicantEmail;
  String? applicantFullName;
  String? applicantPhone;

  /// Increments on each [arm] so the form reapplies even for the same applicant twice.
  int prefillStamp = 0;

  bool get hasPendingLink =>
      applicationId != null && applicationId!.trim().isNotEmpty;

  void arm({
    required String applicationId,
    required String email,
    required String fullName,
    String? phone,
  }) {
    this.applicationId = applicationId;
    applicantEmail = email.trim().toLowerCase();
    applicantFullName = fullName;
    applicantPhone = phone;
    prefillStamp++;
    notifyListeners();
  }

  void clear() {
    applicationId = null;
    applicantEmail = null;
    applicantFullName = null;
    applicantPhone = null;
    notifyListeners();
  }
}
