import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

class DocuTrackerSignatureFieldsPanel extends StatelessWidget {
  const DocuTrackerSignatureFieldsPanel({
    super.key,
    required this.fields,
    required this.activePage,
    required this.selectedFieldId,
    required this.canEditLayout,
    required this.isBusy,
    required this.onSelect,
    required this.onSign,
    required this.onDelete,
    this.onClose,
  });

  final List<DocuTrackerSignatureField> fields;
  final int activePage;
  final String? selectedFieldId;
  final bool canEditLayout;
  final bool isBusy;
  final ValueChanged<DocuTrackerSignatureField> onSelect;
  final ValueChanged<DocuTrackerSignatureField> onSign;
  final ValueChanged<DocuTrackerSignatureField> onDelete;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final ordered = List<DocuTrackerSignatureField>.from(fields)
      ..sort((a, b) {
        final pageOrder = a.pageNumber.compareTo(b.pageNumber);
        return pageOrder != 0 ? pageOrder : a.y.compareTo(b.y);
      });
    final signedCount = fields.where((field) => field.isSigned).length;
    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        side: BorderSide(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.draw_outlined, color: DocuTrackerTokens.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signature Fields',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: DocuTrackerTokens.textPrimaryOf(context),
                            ),
                      ),
                      Text(
                        '$signedCount of ${fields.length} signed',
                        style: DocuTrackerTokens.metaStyle(context),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close signature fields',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          if (isBusy) const LinearProgressIndicator(minHeight: 2),
          Divider(height: 1, color: DocuTrackerTokens.borderSubtleOf(context)),
          if (ordered.isEmpty)
            const Expanded(child: _EmptySignatureFields())
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: ordered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final field = ordered[index];
                  return _SignatureFieldCard(
                    key: ValueKey<String>('signature-field-${field.id}'),
                    field: field,
                    selected: field.id == selectedFieldId,
                    onActivePage: field.pageNumber == activePage,
                    canDelete: canEditLayout && !field.isSigned && !isBusy,
                    canSign: field.canSign && !isBusy,
                    onSelect: () => onSelect(field),
                    onSign: () => onSign(field),
                    onDelete: () => onDelete(field),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SignatureFieldCard extends StatelessWidget {
  const _SignatureFieldCard({
    super.key,
    required this.field,
    required this.selected,
    required this.onActivePage,
    required this.canDelete,
    required this.canSign,
    required this.onSelect,
    required this.onSign,
    required this.onDelete,
  });

  final DocuTrackerSignatureField field;
  final bool selected;
  final bool onActivePage;
  final bool canDelete;
  final bool canSign;
  final VoidCallback onSelect;
  final VoidCallback onSign;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = field.isSigned
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);
    final statusBackground = field.isSigned
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFEDD5);
    return Material(
      color: selected
          ? DocuTrackerTokens.brandSoft
          : DocuTrackerTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        side: BorderSide(
          color: selected
              ? DocuTrackerTokens.brand
              : DocuTrackerTokens.borderSubtleOf(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      field.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: DocuTrackerTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBackground,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      field.isSigned ? 'Signed' : 'Unsigned',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                field.assignedSignerName ?? field.assignedSignerId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DocuTrackerTokens.subtitleStyle(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Page ${field.pageNumber}${onActivePage ? ' - Current page' : ''}',
                style: DocuTrackerTokens.metaStyle(context),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: ValueKey<String>('go-to-${field.id}'),
                    onPressed: onSelect,
                    icon: const Icon(Icons.my_location_outlined, size: 17),
                    label: const Text('Go to'),
                  ),
                  if (canSign)
                    TextButton.icon(
                      key: ValueKey<String>('sign-${field.id}'),
                      onPressed: onSign,
                      icon: Icon(
                        field.isSigned
                            ? Icons.autorenew_rounded
                            : Icons.gesture_rounded,
                        size: 17,
                      ),
                      label: Text(field.isSigned ? 'Change' : 'Sign'),
                    ),
                  if (canDelete)
                    TextButton.icon(
                      key: ValueKey<String>('delete-${field.id}'),
                      onPressed: onDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 17),
                      label: const Text('Delete'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySignatureFields extends StatelessWidget {
  const _EmptySignatureFields();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.draw_outlined,
              size: 36,
              color: DocuTrackerTokens.textMutedOf(context),
            ),
            const SizedBox(height: 10),
            Text(
              'No signature fields yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add a signature field to assign a signer and place it on a page.',
              textAlign: TextAlign.center,
              style: DocuTrackerTokens.metaStyle(context),
            ),
          ],
        ),
      ),
    );
  }
}
