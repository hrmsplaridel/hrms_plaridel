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

/// Static route/section helpers for DTR module.
class DtrRoutes {
  DtrRoutes._();

  static const List<DtrSection> sections = DtrSection.values;

  static DtrSection sectionFromIndex(int index) {
    if (index < 0 || index >= sections.length) return DtrSection.timeLogs;
    return sections[index];
  }
}
