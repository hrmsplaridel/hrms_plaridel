/// DTR section identifiers and metadata.
/// Used by [DtrMain] to switch between sub-screens.
enum DtrSection { timeLogs, reports }

extension DtrSectionExtension on DtrSection {
  String get title => switch (this) {
    DtrSection.timeLogs => 'Time Logs',
    DtrSection.reports => 'Reports',
  };

  int get index => DtrSection.values.indexOf(this);
}

/// Pages of the admin DTR area, with the permission each one needs.
///
/// Workforce Setup tabs are declared in tab order; [workforcePages] relies on it.
enum DtrPage {
  home('DTR'),
  timeLogs('Time Logs', needsManage: true),
  reports('Reports', needsReports: true),
  employees('Employees', feature: 'employees_allowed'),
  assignments('Assignments', needsManage: true, isWorkforce: true),
  departments('Departments', needsManage: true, isWorkforce: true),
  positions('Positions', needsManage: true, isWorkforce: true),
  shifts('Shifts', needsManage: true, isWorkforce: true),
  weeklySchedule('Weekly Schedule', needsManage: true, isWorkforce: true),
  holidays('Holidays', needsManage: true, isWorkforce: true),
  attendancePolicies(
    'Attendance Policies',
    needsManage: true,
    isWorkforce: true,
  ),
  leave('Leave Management', feature: 'leave_allowed'),
  biometricDevices('Biometric Devices', needsManage: true),
  locator('Locator & Pass Management', feature: 'locator_allowed'),
  approvals('Approvals & Signatories', feature: 'approvals_allowed');

  const DtrPage(
    this.title, {
    this.needsManage = false,
    this.needsReports = false,
    this.feature,
    this.isWorkforce = false,
  });

  final String title;

  /// Requires DTR manage access.
  final bool needsManage;

  /// Requires DTR report access.
  final bool needsReports;

  /// Feature-access flag that must be `true` (e.g. `leave_allowed`).
  final String? feature;

  /// Shown as a Workforce Setup tab.
  final bool isWorkforce;

  static final List<DtrPage> workforcePages = List.unmodifiable(
    values.where((p) => p.isWorkforce),
  );

  bool isAllowed({
    required bool canManageDtr,
    required bool canViewReports,
    required Map<String, bool> featureAccess,
  }) {
    final flag = feature;
    if (flag != null && featureAccess[flag] != true) return false;
    if (needsReports && !canViewReports) return false;
    if (needsManage && !canManageDtr) return false;
    return true;
  }
}

/// Static route/section helpers for DTR module.
class DtrRoutes {
  DtrRoutes._();

  static const List<DtrSection> sections = DtrSection.values;

  static DtrSection sectionFromIndex(int index) {
    if (index < 0 || index >= sections.length) return DtrSection.timeLogs;
    return sections[index];
  }
}
