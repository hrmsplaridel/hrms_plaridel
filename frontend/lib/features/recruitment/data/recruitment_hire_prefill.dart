import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

/// Default passwords used when creating HRMS accounts (Create Account form).
const String kDefaultEmployeeAccountPassword = 'Employee123';
const String kDefaultAdminAccountPassword = 'Admin123';

/// Randomized temporary password shown on Create Account and emailed to hires.
String generateTemporaryAccountPassword({int length = 12}) {
  final random = Random.secure();
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const numbers = '23456789';
  const symbols = '!@#%';
  const all = '$lower$upper$numbers$symbols';
  final chars = <String>[
    lower[random.nextInt(lower.length)],
    upper[random.nextInt(upper.length)],
    numbers[random.nextInt(numbers.length)],
    symbols[random.nextInt(symbols.length)],
  ];
  while (chars.length < length) {
    chars.add(all[random.nextInt(all.length)]);
  }
  for (var i = chars.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}

/// Password HR should email: the Create Account value, never Employee123.
String resolveHireLoginPassword({
  String? storedPassword,
  String? persistedPassword,
}) {
  final stored = storedPassword?.trim() ?? '';
  if (stored.isNotEmpty) return stored;
  final persisted = persistedPassword?.trim() ?? '';
  if (persisted.isNotEmpty) return persisted;
  return generateTemporaryAccountPassword();
}

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
  String? applicantFirstName;
  String? applicantMiddleName;
  String? applicantLastName;
  String? applicantSuffix;
  String? applicantPhone;
  String? applicantSex;
  String? applicantAddress;

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
    String? firstName,
    String? middleName,
    String? lastName,
    String? suffix,
    String? phone,
    String? sex,
    String? address,
  }) {
    this.applicationId = applicationId;
    applicantEmail = email.trim().toLowerCase();
    applicantFullName = fullName;
    applicantFirstName = firstName?.trim();
    applicantMiddleName = middleName?.trim();
    applicantLastName = lastName?.trim();
    applicantSuffix = suffix?.trim();
    applicantPhone = phone;
    applicantSex = sex?.trim();
    applicantAddress = address?.trim();
    prefillStamp++;
    notifyListeners();
  }

  void clear() {
    applicationId = null;
    applicantEmail = null;
    applicantFullName = null;
    applicantFirstName = null;
    applicantMiddleName = null;
    applicantLastName = null;
    applicantSuffix = null;
    applicantPhone = null;
    applicantSex = null;
    applicantAddress = null;
    notifyListeners();
  }
}
