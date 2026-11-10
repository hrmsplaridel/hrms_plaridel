import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_purchase_items.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_purchase_pagination.dart';

import 'docutracker_purchase_items_table.dart';
import 'docutracker_purchase_signature_band.dart';

/// One official A4 slice of a Purchase Request.
///
/// Print and Export capture these same slices. Requested by and Approved by
/// are drawn on the closing slice. Stored signature coordinates stay as they are.
class DocuTrackerPurchaseSheet extends StatelessWidget {
  const DocuTrackerPurchaseSheet({
    super.key,
    required this.controller,
    required this.plan,
    required this.slice,
    required this.editable,
    required this.fields,
    required this.onSign,
    this.placementPreviewFieldId,
    this.placementPreviewBytes,
  });

  final quill.QuillController controller;
  final PurchaseDocumentPlan plan;
  final PurchasePageSlice slice;
  final bool editable;
  final List<DocuTrackerSignatureField> fields;
  final ValueChanged<DocuTrackerSignatureField>? onSign;
  final String? placementPreviewFieldId;
  final Uint8List? placementPreviewBytes;

  @override
  Widget build(BuildContext context) {
    final items = plan.parts.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slice.preamble.isNotEmpty)
          _Section(
            editable: editable,
            onEdit: () => _editText(
              context,
              title: 'Edit purchase request',
              ops: plan.parts.preambleOps,
              apply: (ops) => _write(preambleOps: ops),
            ),
            children: [
              for (final paragraph in slice.preamble) _text(paragraph),
            ],
          ),
        if (slice.tableError)
          const Text(
            'This purchase table could not be read. Reload the document before editing.',
            style: TextStyle(color: Colors.black, fontSize: 16, height: 1.15),
          ),
        if (slice.hasTable && items != null)
          DocuTrackerPurchaseItemsTable(
            items: items,
            displayRows: slice.tableRows,
            showTotal: slice.showTotal,
            onEdit: editable ? () => _editItems(context, items) : null,
          ),
        if (slice.purpose.isNotEmpty)
          _Section(
            editable: editable,
            onEdit: () => _editText(
              context,
              title: 'Edit purpose',
              ops: plan.parts.purposeOps,
              apply: (ops) => _write(purposeOps: ops),
            ),
            children: [for (final paragraph in slice.purpose) _text(paragraph)],
          ),
        if (slice.showSignatures)
          DocuTrackerPurchaseSignatureBand(
            fields: fields,
            onSign: onSign,
            placementPreviewFieldId: placementPreviewFieldId,
            placementPreviewBytes: placementPreviewBytes,
          ),
      ],
    );
  }

  Widget _text(PurchaseParagraph paragraph) {
    if (paragraph.spans.isEmpty) {
      return SizedBox(height: paragraph.height);
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final span in paragraph.spans)
            TextSpan(text: span.text, style: span.style),
        ],
      ),
      textAlign: paragraph.align,
    );
  }

  Future<void> _editItems(
    BuildContext context,
    DocumentPurchaseItems items,
  ) async {
    final updated = await showDocuTrackerPurchaseItemsEditor(
      context,
      items: items,
    );
    if (updated == null || !context.mounted) return;
    _write(items: updated);
  }

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> ops,
    required void Function(List<Map<String, dynamic>> ops) apply,
  }) async {
    final saved = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _PurchaseTextDialog(title: title, ops: ops),
    );
    if (saved == null || !context.mounted) return;
    apply(saved);
  }

  void _write({
    List<Map<String, dynamic>>? preambleOps,
    List<Map<String, dynamic>>? purposeOps,
    DocumentPurchaseItems? items,
  }) {
    final parts = plan.parts;
    writePurchaseDocument(
      controller,
      composePurchaseDelta(
        preambleOps: preambleOps ?? parts.preambleOps,
        items: items ?? parts.items,
        purposeOps: purposeOps ?? parts.purposeOps,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.editable,
    required this.onEdit,
    required this.children,
  });

  final bool editable;
  final VoidCallback onEdit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (!editable) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onEdit, child: body),
    );
  }
}

class _PurchaseTextDialog extends StatefulWidget {
  const _PurchaseTextDialog({required this.title, required this.ops});

  final String title;
  final List<Map<String, dynamic>> ops;

  @override
  State<_PurchaseTextDialog> createState() => _PurchaseTextDialogState();
}

class _PurchaseTextDialogState extends State<_PurchaseTextDialog> {
  late final quill.QuillController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
      document: quill.Document.fromJson(
        widget.ops.isEmpty
            ? const [
                {'insert': '\n'},
              ]
            : widget.ops,
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        height: 320,
        child: quill.QuillEditor.basic(
          controller: _controller,
          focusNode: _focusNode,
          config: const quill.QuillEditorConfig(padding: EdgeInsets.all(8)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _controller.document
                .toDelta()
                .toJson()
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
