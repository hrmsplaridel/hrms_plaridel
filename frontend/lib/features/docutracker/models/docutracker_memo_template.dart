import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

/// Editable metadata of the official Municipality of Plaridel Memorandum.
///
/// Stored as a tagged, non-Quill operation at the start of builder page 1, so
/// the existing builder storage carries it without a schema change. The body
/// stays in the page's Quill delta; the letterhead, title, field labels,
/// signature labels and footer are fixed by the template and never stored.
class DocuTrackerMemoTemplate {
  const DocuTrackerMemoTemplate({
    this.to = '',
    this.subject = '',
    this.date = '',
    this.cc = '',
  });

  static const String operationKey = 'docutracker_template';
  static const String templateId = 'memo_v1';

  static const int maxToLength = 600;
  static const int maxSubjectLength = 300;
  static const int maxDateLength = 60;
  static const int maxCcLength = 600;

  /// Printed recipients ("To"). Independent of the release recipient
  /// department; neither one overwrites the other.
  final String to;
  final String subject;
  final String date;

  /// Copy furnished / distribution list, one entry per line.
  final String cc;

  static bool isTemplateOperation(Map<String, dynamic> operation) =>
      !operation.containsKey('insert') && operation[operationKey] is String;

  static DocuTrackerMemoTemplate? fromOperation(
    Map<String, dynamic> operation,
  ) {
    if (operation[operationKey] != templateId) return null;
    final raw = operation['memo'];
    final memo = raw is Map ? raw : const <String, dynamic>{};
    String text(String key, int max) {
      final value = memo[key]?.toString() ?? '';
      return value.length > max ? value.substring(0, max) : value;
    }

    return DocuTrackerMemoTemplate(
      to: text('to', maxToLength),
      subject: text('subject', maxSubjectLength),
      date: text('date', maxDateLength),
      cc: text('cc', maxCcLength),
    );
  }

  Map<String, dynamic> toOperation() => <String, dynamic>{
    operationKey: templateId,
    'memo': <String, dynamic>{
      'to': to,
      'subject': subject,
      'date': date,
      'cc': cc,
    },
  };

  /// Non-empty, trimmed lines of a multiline value.
  static List<String> lines(String value) => value
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
}

const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Calendar date in the HRMS timezone (Asia/Manila, UTC+8, no DST),
/// e.g. "October 7, 2026".
String docuTrackerMemoDateText(DateTime value) {
  final manila = value.toUtc().add(const Duration(hours: 8));
  return '${_months[manila.month - 1]} ${manila.day}, ${manila.year}';
}

enum DocuTrackerMemoSlot { preparedBy, approvedBy }

/// One fixed signatory block of the official Memo (Prepared by / Approved
/// by). Its printed name and position come only from the signer data the
/// server returns, never from document text, so the builder and the PDF
/// always print the same person.
///
/// Before signing the block shows the assigned signer's live directory
/// identity. Once signed it prints only the identity frozen at signing, so
/// later renames, promotions, transfers or a new Mayor never alter it. Fields
/// signed before position/role snapshots existed print no position and no
/// "HON." prefix rather than a guessed historical title.
class DocuTrackerMemoSignatory {
  const DocuTrackerMemoSignatory(this.slot, this.field);

  final DocuTrackerMemoSlot slot;

  /// Null when no signer is assigned to this slot (e.g. no Mayor configured).
  final DocuTrackerSignatureField? field;

  static String labelOf(DocuTrackerMemoSlot slot) => switch (slot) {
    DocuTrackerMemoSlot.preparedBy => DocuTrackerMemoLayout.preparedFieldLabel,
    DocuTrackerMemoSlot.approvedBy => DocuTrackerMemoLayout.approvedFieldLabel,
  };

  /// The page-1 field holding [slot], matched by its fixed label.
  static DocuTrackerMemoSignatory resolve(
    DocuTrackerMemoSlot slot,
    Iterable<DocuTrackerSignatureField> fields,
  ) {
    final label = labelOf(slot);
    DocuTrackerSignatureField? match;
    for (final field in fields) {
      if (field.pageNumber != 1 || field.label != label) continue;
      // A signed field wins over a stale unsigned duplicate.
      if (match == null || (field.isSigned && !match.isSigned)) match = field;
    }
    return DocuTrackerMemoSignatory(slot, match);
  }

  static bool isSlotField(DocuTrackerSignatureField field) =>
      field.pageNumber == 1 &&
      (field.label == DocuTrackerMemoLayout.preparedFieldLabel ||
          field.label == DocuTrackerMemoLayout.approvedFieldLabel);

  bool get isAssigned => field != null;
  bool get isSigned => field?.isSigned ?? false;
  bool get isMayor {
    final source = field;
    if (source == null) return false;
    final role = source.isSigned
        ? source.signerRoleSnapshot
        : source.assignedSignerRole;
    return role?.trim().toLowerCase() == 'mayor';
  }

  /// Upper-case printed name; the Mayor is styled "HON. NAME".
  String? get printedName {
    final source = field;
    if (source == null) return null;
    final name = _clean(
      source.isSigned ? source.signerName : source.assignedSignerName,
    );
    if (name == null) return null;
    final upper = name.toUpperCase();
    if (!isMayor || upper.startsWith('HON.') || upper.startsWith('HON ')) {
      return upper;
    }
    return 'HON. $upper';
  }

  String? get position {
    final source = field;
    if (source == null) return null;
    return _clean(
      source.isSigned
          ? source.signerPositionSnapshot
          : source.assignedSignerPosition,
    );
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Shown instead of a name when nobody is assigned to the slot.
  String get unassignedMessage => switch (slot) {
    DocuTrackerMemoSlot.preparedBy => 'No preparer assigned',
    DocuTrackerMemoSlot.approvedBy => 'No Mayor signatory configured',
  };
}

/// Official release details printed on a released Memo. Only built from
/// backend release data; approved-but-unreleased memos have none.
class DocuTrackerMemoRelease {
  const DocuTrackerMemoRelease({
    required this.departmentName,
    required this.releasedByName,
    required this.releasedAt,
    this.remarks,
  });

  final String departmentName;
  final String releasedByName;
  final DateTime releasedAt;
  final String? remarks;

  static DocuTrackerMemoRelease? fromDocument(DocuTrackerDocument document) {
    final releasedAt = document.releasedAt;
    if (!document.isReleased || releasedAt == null) return null;
    String clean(String? value) => value?.trim() ?? '';
    final remarks = clean(document.releaseRemarks);
    return DocuTrackerMemoRelease(
      departmentName: clean(document.releasedToDepartmentName),
      releasedByName: clean(document.releasedByName),
      releasedAt: releasedAt,
      remarks: remarks.isEmpty ? null : remarks,
    );
  }
}
