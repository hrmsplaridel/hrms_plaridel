import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';

/// Saved printed-form config for a DocuTracker document (null = none).
class DocuTrackerDocumentPrintConfig {
  const DocuTrackerDocumentPrintConfig({
    required this.versionId,
    required this.layout,
    required this.hasBackground,
  });

  final String? versionId;
  final LocatorPrintLayout layout;
  final bool hasBackground;
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

String? _formatDate(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// Maps a DocuTracker document (+ optional Memo fields) into print sources.
Map<String, dynamic> docuTrackerPrintFormFromDocument(
  DocuTrackerDocument document, {
  DocuTrackerMemoTemplate? memo,
}) {
  final created = _formatDate(document.createdAt);
  return {
    'title': document.title,
    'subject': (memo?.subject.trim().isNotEmpty ?? false)
        ? memo!.subject.trim()
        : document.title,
    'document_number': document.documentNumber ?? '',
    'description': (memo == null)
        ? (document.description ?? '')
        : [
            if (memo.to.trim().isNotEmpty) 'To:\n${memo.to.trim()}',
            if (memo.subject.trim().isNotEmpty)
              'Subject: ${memo.subject.trim()}',
            if (document.description?.trim().isNotEmpty == true)
              document.description!.trim(),
          ].join('\n\n'),
    'document_type': document.documentType,
    'status': document.status.value,
    'created_by_name': document.creatorName ?? '',
    'created_at': created ?? '',
    'department_name': document.releasedToDepartmentName ?? '',
    'date': (memo?.date.trim().isNotEmpty ?? false)
        ? memo!.date.trim()
        : (created ?? ''),
  };
}

String _signatureSourceForLabel(String label) {
  final key = label.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  if (key.contains('prepared') || key.contains('requested')) {
    return 'prepared_by';
  }
  if (key.contains('approved')) return 'approved_by';
  if (key.contains('mayor')) return 'mayor';
  if (key.contains('department') || key.contains('head')) {
    return 'department_head';
  }
  if (key.contains('review')) return 'reviewer';
  if (key.contains('applicant') || key.contains('creator')) return 'applicant';
  if (docuTrackerPrintLayoutSignatures().containsKey(key)) return key;
  return 'reviewer';
}

LocatorPrintedSignatory docuTrackerPrintSignatoryFromField(
  DocuTrackerSignatureField field,
) => LocatorPrintedSignatory(
  name: (field.signerName ?? field.assignedSignerName ?? '').trim(),
  positionTitle:
      (field.signerPositionSnapshot ?? field.assignedSignerPosition ?? '')
          .trim(),
  signatureBytes: field.isSigned ? field.signatureImageBytes : null,
);

Map<String, LocatorPrintedSignatory> docuTrackerPrintSignatoriesFromFields(
  List<DocuTrackerSignatureField> fields,
) {
  final mapped = <String, LocatorPrintedSignatory>{};
  for (final field in fields) {
    mapped[_signatureSourceForLabel(field.label)] =
        docuTrackerPrintSignatoryFromField(field);
  }
  return mapped;
}

Future<DocuTrackerDocumentPrintConfig?> loadDocuTrackerDocumentPrintConfig(
  String documentId,
) async {
  final response = await ApiClient.instance.get(
    '/api/docutracker/print/documents/${Uri.encodeComponent(documentId)}',
  );
  final data = Map<String, dynamic>.from(response.data as Map? ?? const {});
  if (data['has_custom_print'] != true || data['print_layout'] is! Map) {
    return null;
  }
  return DocuTrackerDocumentPrintConfig(
    versionId: data['version_id']?.toString(),
    layout: LocatorPrintLayout.fromJson(
      Map<String, dynamic>.from(data['print_layout'] as Map),
    ),
    hasBackground: data['has_background'] == true,
  );
}

/// Builds the designed printed PDF for [document], or null when no layout.
Future<Uint8List?> buildDocuTrackerDesignedPrintPdf({
  required DocuTrackerDocument document,
  List<DocuTrackerSignatureField> signatureFields = const [],
  DocuTrackerMemoTemplate? memo,
}) async {
  final documentId = document.id;
  if (documentId == null || documentId.isEmpty) return null;
  final DocuTrackerDocumentPrintConfig? config;
  try {
    config = await loadDocuTrackerDocumentPrintConfig(documentId);
  } on DioException catch (error) {
    final code = error.response?.statusCode ?? 0;
    // Route not loaded yet, or this document has no saved form.
    if (code == 404 || code == 0) return null;
    rethrow;
  }
  if (config == null) return null;

  final form = docuTrackerPrintFormFromDocument(document, memo: memo);
  final extras = docuTrackerPrintSignatoriesFromFields(signatureFields);
  final overlay = await buildLocatorLayoutPdf(
    layout: config.layout,
    form: form,
    signatories: LocatorFormSignatories(
      applicant:
          extras['applicant'] ??
          extras['prepared_by'] ??
          const LocatorPrintedSignatory(),
      departmentHead:
          extras['department_head'] ?? const LocatorPrintedSignatory(),
      finalApprover:
          extras['approved_by'] ??
          extras['mayor'] ??
          const LocatorPrintedSignatory(),
    ),
    extraSignatories: extras,
  );

  final response = await ApiClient.instance.post<List<int>>(
    '/api/docutracker/print/documents/${Uri.encodeComponent(documentId)}/render',
    data: FormData.fromMap({
      if (config.versionId != null) 'version_id': config.versionId,
      'file': MultipartFile.fromBytes(
        overlay,
        filename: 'docutracker-document.pdf',
      ),
    }),
    options: Options(responseType: ResponseType.bytes),
  );
  return Uint8List.fromList(response.data ?? const <int>[]);
}
