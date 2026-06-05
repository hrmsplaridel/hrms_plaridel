import 'package:flutter/foundation.dart';

/// Default passwords used when creating HRMS accounts (Create Account form).
const String kDefaultEmployeeAccountPassword = 'Employee123';
const String kDefaultAdminAccountPassword = 'Admin123';

/// Login details captured when HR creates an account from RSP.
class CreatedAccountCredentials {
  const CreatedAccountCredentials({
    required this.loginEmail,
    required this.password,
  });

  final String loginEmail;
  final String password;
}

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

  final Map<String, CreatedAccountCredentials> _createdCredentials = {};

  bool get hasPendingLink =>
      applicationId != null && applicationId!.trim().isNotEmpty;

  CreatedAccountCredentials? credentialsFor(String applicationId) {
    final id = applicationId.trim();
    if (id.isEmpty) return null;
    return _createdCredentials[id];
  }

  void recordCreatedCredentials({
    required String applicationId,
    required String loginEmail,
    required String password,
  }) {
    final id = applicationId.trim();
    if (id.isEmpty || loginEmail.trim().isEmpty || password.isEmpty) return;
    _createdCredentials[id] = CreatedAccountCredentials(
      loginEmail: loginEmail.trim().toLowerCase(),
      password: password,
    );
    notifyListeners();
  }

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
