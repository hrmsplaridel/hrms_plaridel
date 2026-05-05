import 'package:flutter/material.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../docutracker_provider.dart';
import '../docutracker_styles.dart';
import '../models/document_type.dart';

/// Shows the DocuTracker "Create Document" dialog.
Future<void> showDocuTrackerCreateDocumentDialog(
  BuildContext context, {
  required AuthProvider auth,
  required DocuTrackerProvider provider,
  VoidCallback? onCreated,
}) async {
  String title = '';
  DocumentType type = DocumentType.memo;
  String? description;

  final size = MediaQuery.of(context).size;
  final dialogWidth = (size.width * 0.78).clamp(640.0, 960.0);
  final dialogHeight = (size.height * 0.75).clamp(520.0, 820.0);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Dialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 32,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const RspFormHeader(
                          formTitle: 'Create Draft',
                          subtitle: 'DocuTracker - Municipality of Plaridel',
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                decoration: DocuTrackerStyles.inputDecoration(
                                  'Enter title',
                                  Icons.title_rounded,
                                ),
                                onChanged: (v) => title = v,
                              ),
                              const SizedBox(height: 20),
                              DropdownButtonFormField<DocumentType>(
                                value: type,
                                decoration:
                                    DocuTrackerStyles.dropdownDecoration(
                                  'Document Type',
                                ),
                                items: DocumentType.values
                                    .map(
                                      (t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.displayName),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    v != null ? setState(() => type = v) : null,
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                decoration: DocuTrackerStyles.inputDecoration(
                                  'Description (optional)',
                                  Icons.notes_rounded,
                                ),
                                maxLines: 6,
                                onChanged: (v) =>
                                    description = v.isEmpty ? null : v,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: DocuTrackerStyles.outlinedButtonStyle(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () async {
                          if (title.trim().isEmpty) return;
                          final created = await provider.createDocument(
                            title: title.trim(),
                            documentType: type,
                            description: description,
                            createdBy: auth.user?.id ?? '',
                          );
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            if (context.mounted) {
                              if (created != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Draft created successfully.'),
                                  ),
                                );
                                onCreated?.call();
                              } else {
                                final msg = provider.error?.trim();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      (msg != null && msg.isNotEmpty)
                                          ? msg
                                          : 'Could not create document.',
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        style: DocuTrackerStyles.primaryButtonStyle(),
                        child: const Text('Create Draft'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
