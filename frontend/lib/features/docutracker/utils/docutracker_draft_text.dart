import '../models/document.dart';
import '../models/document_builder.dart';
import '../models/document_type.dart';
import '../models/document_purchase_items.dart';

/// Local, editable starter wording. Unknown facts remain explicit placeholders.
abstract final class DocuTrackerDraftText {
  /// Adapted from DSWD's Handbook of Style (Memos, pp. 27-28) and the
  /// LGU Appendix 47 purchase-request layout. These are editable drafts,
  /// not a certification of the municipality's procurement requirements.
  /// https://fo8.dswd.gov.ph/km-portal/wp-content/uploads/2024/04/DSWD-Handbook-of-Style_2020.pdf
  /// https://malita.gov.ph/wp-content/uploads/2025/08/PR-N2506-534-.pdf
  static DocuTrackerDocumentPage composePage(DocuTrackerDocument document) {
    final type = DocumentType.fromValue(document.documentType);
    if (type != DocumentType.memo && type != DocumentType.purchaseRequest) {
      return DocuTrackerDocumentPage(
        delta: [
          {'insert': '${_composeGeneral(document)}\n'},
        ],
      );
    }
    final operations = <Map<String, dynamic>>[];
    final size = type == DocumentType.memo ? '16' : '14';
    void line(
      String text, {
      bool bold = false,
      bool centered = false,
      bool justify = false,
    }) {
      operations.add({
        'insert': text,
        'attributes': {'size': size, if (bold) 'bold': true},
      });
      operations.add({
        'insert': '\n',
        if (centered || justify)
          'attributes': {'align': centered ? 'center' : 'justify'},
      });
    }

    void label(String heading, String value) {
      operations.add({
        'insert': '$heading: ',
        'attributes': {'bold': true, 'size': size},
      });
      line(value);
    }

    void gap() => operations.add({
      'insert': '\n',
      'attributes': {'size': '10'},
    });
    final title = document.title.trim().isEmpty
        ? '[Subject]'
        : document.title.trim();
    final description = document.description?.trim() ?? '';
    if (type == DocumentType.memo) {
      line('MEMORANDUM', bold: true, centered: true);
      line('No. [Number], s. [Year]', centered: true);
      gap();
      label('TO', '[Recipient / office]');
      label('FROM', '[Sender name and designation]');
      label('SUBJECT', title);
      label('DATE', '[Day Month Year]');
      gap();
      line(
        description.isEmpty
            ? '[State the purpose and background of this memorandum.]'
            : description,
        justify: true,
      );
      gap();
      line(
        'In connection with the above, [state the instructions, supporting details, or arrangements].',
        justify: true,
      );
      gap();
      line(
        'Please [required action] on or before [deadline]. For questions or clarification, contact [contact person and office].',
        justify: true,
      );
      gap();
      gap();
      line('[SIGNATURE / E-SIGNATURE]');
      line('[SENDER NAME]', bold: true);
      line('[Designation]');
      gap();
      label('Attachments', '[List, if any; otherwise remove this line]');
    } else {
      line('PURCHASE REQUEST', bold: true, centered: true);
      gap();
      label('LGU', 'Municipality of Plaridel');
      label('Fund', '[Fund]');
      label('Office / Section', '[Requesting office / section]');
      label('PR No.', '[Assigned PR number]');
      label('Date', '[Day Month Year]');
      label('F/P/P', '[Function / Program / Project code]');
      label('Project / Subject', title);
      gap();
      operations.add({'insert': DocumentPurchaseItems.blank().toInsertJson()});
      operations.add({'insert': '\n'});
      gap();
      label(
        'Purpose',
        description.isEmpty
            ? '[Explain why the items are needed.]'
            : description,
      );
      gap();
      line('Requested by:', bold: true);
      line('Signature: ____________________');
      line('Printed name: [Requesting official]\nDesignation: [Designation]');
      gap();
      line('Approved by:', bold: true);
      line('Signature: ____________________');
      line('Printed name: [Approving official]\nDesignation: [Designation]');
    }
    return DocuTrackerDocumentPage(delta: operations);
  }

  /// Only a newly opened, untouched blank builder is eligible for prefilling.
  /// The caller must also opt in from the successful document-creation flow.
  static bool canPrefill(DocuTrackerDocumentBuilderData data) =>
      data.canEditLayout &&
      data.revision == 0 &&
      data.signatureFields.isEmpty &&
      data.pages.length == 1 &&
      data.pages.single.delta.every((operation) {
        final insert = operation['insert'];
        return insert is String && insert.trim().isEmpty;
      });

  static String compose(DocuTrackerDocument document) {
    final text = StringBuffer();
    for (final operation in composePage(document).delta) {
      final insert = operation['insert'];
      if (insert is String) {
        text.write(insert);
      } else if (insert is Map) {
        final items = DocumentPurchaseItems.decode(
          insert[DocumentPurchaseItems.embedType],
        );
        text.writeln(DocumentPurchaseItems.headers.join('\t'));
        for (final row in items.rows) {
          text.writeln(row.join('\t'));
        }
        text.write('TOTAL: ${items.total}');
      }
    }
    return text.toString().trimRight();
  }

  static String _composeGeneral(DocuTrackerDocument document) {
    final title = document.title.trim();
    final subject = title.isEmpty ? '[Subject]' : title;
    final description = document.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    const introduction =
        'Please see the following details regarding the subject above.';
    final details = hasDescription
        ? description
        : '[Enter the purpose and details of this document.]';
    return 'To: [Recipient / office]\n'
        'From: [Sender / office]\n'
        'Date: [Date]\n'
        'Subject: $subject\n\n'
        '$introduction\n\n'
        '$details\n\n'
        'Kindly [required action] on or before [deadline]. '
        'For clarification, please contact [contact person / office].\n\n'
        'Thank you.';
  }
}
