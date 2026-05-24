/// Canonical DocuTracker roles and legacy aliases.
///
/// Canonical roles:
/// - admin
/// - hr
/// - supervisor
/// - employee
///
/// Legacy aliases:
/// - hr_staff -> hr
/// - dept_head -> supervisor
class DocuTrackerRoles {
  DocuTrackerRoles._();

  static const String admin = 'admin';
  static const String hr = 'hr';
  static const String supervisor = 'supervisor';
  static const String employee = 'employee';

  static const String legacyHrStaff = 'hr_staff';
  static const String legacyDeptHead = 'dept_head';

  static const Set<String> canonical = {admin, hr, supervisor, employee};

  static String normalize(String? roleId) {
    final r = (roleId ?? '').trim().toLowerCase();
    return switch (r) {
      legacyHrStaff => hr,
      legacyDeptHead => supervisor,
      _ => r,
    };
  }

  /// Returns the role ids that should be treated as equivalent for reads.
  /// The first element is always the canonical id when possible.
  static List<String> equivalentsForRead(String? roleId) {
    final normalized = normalize(roleId);
    if (normalized.isEmpty) return const [];
    return switch (normalized) {
      hr => const [hr, legacyHrStaff],
      supervisor => const [supervisor, legacyDeptHead],
      _ => [normalized],
    };
  }
}

