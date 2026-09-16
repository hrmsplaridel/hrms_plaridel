class FormPrintPaperSize {
  const FormPrintPaperSize({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.widthPt,
    required this.heightPt,
  });

  final String id;
  final String label;
  final String subtitle;
  final double widthPt;
  final double heightPt;

  double get aspectRatio => widthPt / heightPt;
}

class FormPrintCatalogItem {
  const FormPrintCatalogItem({
    required this.key,
    required this.title,
    required this.defaultPaperSizeId,
  });

  final String key;
  final String title;
  final String defaultPaperSizeId;
}

class FormPrintTemplate {
  const FormPrintTemplate({
    required this.module,
    required this.formKey,
    required this.paperSize,
    this.id,
    this.originalFilename,
    this.mimeType,
    this.updatedAt,
  });

  final String? id;
  final String module;
  final String formKey;
  final String paperSize;
  final String? originalFilename;
  final String? mimeType;
  final DateTime? updatedAt;

  factory FormPrintTemplate.fromJson(Map<String, dynamic> json) {
    return FormPrintTemplate(
      id: json['id']?.toString(),
      module: json['module']?.toString() ?? '',
      formKey: json['formKey']?.toString() ?? '',
      paperSize: json['paperSize']?.toString() ?? 'letter',
      originalFilename: json['originalFilename']?.toString(),
      mimeType: json['mimeType']?.toString(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class FormPrintCatalog {
  FormPrintCatalog._();

  static const paperSizes = <FormPrintPaperSize>[
    FormPrintPaperSize(
      id: 'a4',
      label: 'A4',
      subtitle: '210 × 297 mm',
      widthPt: 595.28,
      heightPt: 841.89,
    ),
    FormPrintPaperSize(
      id: 'letter',
      label: 'Letter',
      subtitle: '8.5" × 11"',
      widthPt: 612,
      heightPt: 792,
    ),
    FormPrintPaperSize(
      id: 'letter_landscape',
      label: 'Letter landscape',
      subtitle: '11" × 8.5"',
      widthPt: 792,
      heightPt: 612,
    ),
    FormPrintPaperSize(
      id: 'long_13',
      label: '8.5 × 13',
      subtitle: 'Long bond',
      widthPt: 612,
      heightPt: 936,
    ),
    FormPrintPaperSize(
      id: 'long_14',
      label: '8.5 × 14',
      subtitle: 'Legal / long letter',
      widthPt: 612,
      heightPt: 1008,
    ),
    FormPrintPaperSize(
      id: 'long_landscape',
      label: 'Long landscape',
      subtitle: '14" × 8.5"',
      widthPt: 1008,
      heightPt: 612,
    ),
  ];

  static const rspForms = <FormPrintCatalogItem>[
    FormPrintCatalogItem(
      key: 'bi',
      title: 'Background Investigation (BI Form)',
      defaultPaperSizeId: 'a4',
    ),
    FormPrintCatalogItem(
      key: 'applicants_profile',
      title: 'Applicants Profile',
      defaultPaperSizeId: 'letter',
    ),
    FormPrintCatalogItem(
      key: 'selection_lineup',
      title: 'Selection Line-Up',
      defaultPaperSizeId: 'letter_landscape',
    ),
    FormPrintCatalogItem(
      key: 'computation_of_points',
      title: 'Computation of Points',
      defaultPaperSizeId: 'letter_landscape',
    ),
    FormPrintCatalogItem(
      key: 'work_experience',
      title: 'Work Experience Sheet',
      defaultPaperSizeId: 'letter',
    ),
    FormPrintCatalogItem(
      key: 'turn_around_time',
      title: 'Turn Around Time',
      defaultPaperSizeId: 'letter_landscape',
    ),
    FormPrintCatalogItem(
      key: 'ojt_work_immersion',
      title: 'OJT / Work Immersion Evaluation',
      defaultPaperSizeId: 'letter',
    ),
  ];

  static const ldForms = <FormPrintCatalogItem>[
    FormPrintCatalogItem(
      key: 'training_need_analysis',
      title: 'Training Need Analysis',
      defaultPaperSizeId: 'letter_landscape',
    ),
    FormPrintCatalogItem(
      key: 'action_brainstorming',
      title: 'Action Brainstorming Worksheet',
      defaultPaperSizeId: 'letter_landscape',
    ),
    FormPrintCatalogItem(
      key: 'idp',
      title: 'Individual Development Plan (IDP)',
      defaultPaperSizeId: 'long_13',
    ),
    FormPrintCatalogItem(
      key: 'learning_application_plan',
      title: 'Learning Application Plan',
      defaultPaperSizeId: 'letter_landscape',
    ),
  ];

  static List<FormPrintCatalogItem> formsFor(String module) =>
      module == 'ld' ? ldForms : rspForms;

  static FormPrintPaperSize? paperById(String id) {
    for (final s in paperSizes) {
      if (s.id == id) return s;
    }
    return null;
  }

  static String titleFor(String module, String formKey) {
    for (final f in formsFor(module)) {
      if (f.key == formKey) return f.title;
    }
    return formKey;
  }

  /// Labels shown in the print preview paper-size menu (includes 8.5" × 13").
  static String paperMenuLabel(FormPrintPaperSize s) =>
      '${s.label} (${s.subtitle})';
}
