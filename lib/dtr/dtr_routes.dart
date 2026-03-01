/// DTR section identifiers and metadata.
/// Used by [DtrMain] to switch between sub-screens.
enum DtrSection {
  dashboard,
  timeLogs,
  reports,
}

extension DtrSectionExtension on DtrSection {
  String get title {
    switch (this) {
      case DtrSection.dashboard:
        return 'Dashboard';
      case DtrSection.timeLogs:
        return 'Time Logs';
      case DtrSection.reports:
        return 'Reports';
    }
  }

  int get index => DtrSection.values.indexOf(this);
}

/// Static route/section helpers for DTR module.
class DtrRoutes {
  DtrRoutes._();

  static const List<DtrSection> sections = DtrSection.values;

  static DtrSection sectionFromIndex(int index) {
    if (index < 0 || index >= sections.length) return DtrSection.dashboard;
    return sections[index];
  }
}
