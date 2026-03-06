/// DocuTracker section identifiers and metadata.
enum DocuTrackerSection { dashboard, documents, admin }

extension DocuTrackerSectionExtension on DocuTrackerSection {
  String get title => switch (this) {
        DocuTrackerSection.dashboard => 'Dashboard',
        DocuTrackerSection.documents => 'Documents',
        DocuTrackerSection.admin => 'Admin',
      };

  int get index => DocuTrackerSection.values.indexOf(this);
}

/// Static route/section helpers for DocuTracker module.
class DocuTrackerRoutes {
  DocuTrackerRoutes._();

  static const List<DocuTrackerSection> sections = DocuTrackerSection.values;

  static DocuTrackerSection sectionFromIndex(int index) {
    if (index < 0 || index >= sections.length) return DocuTrackerSection.documents;
    return sections[index];
  }
}
