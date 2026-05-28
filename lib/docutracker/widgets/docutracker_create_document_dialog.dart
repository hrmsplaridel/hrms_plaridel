import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../providers/auth_provider.dart';
import '../docutracker_provider.dart';
import '../docutracker_styles.dart';
import '../models/document_type.dart';

/// Shows the DocuTracker "Create Document" dialog.
Future<void> showDocuTrackerCreateDocumentDialog(
  BuildContext context, {
  required AuthProvider auth,
  required DocuTrackerProvider provider,
  List<DocumentType>? allowedDocumentTypes,
  VoidCallback? onCreated,
}) async {
  String title = '';
  final typeOptions = allowedDocumentTypes == null || allowedDocumentTypes.isEmpty
      ? DocumentType.values
      : DocumentType.values
            .where((type) => allowedDocumentTypes.contains(type))
            .toList();
  DocumentType type = typeOptions.first;
  String? description;
  String? inlineError;
  bool creating = false;
  String? pickedFileName;
  List<int>? pickedFileBytes;

  final size = MediaQuery.of(context).size;
  final dialogWidth = (size.width * 0.78).clamp(640.0, 960.0);
  final dialogHeight = (size.height * 0.75).clamp(520.0, 820.0);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        Container(
                          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Draft',
                                style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Start a new workflow document with optional attachment.',
                                style: TextStyle(
                                  color: Theme.of(ctx).hintColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 20, 32, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (inlineError != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          inlineError!,
                                          style: TextStyle(
                                            color: Colors.red.shade900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextField(
                                decoration: DocuTrackerStyles.inputDecoration(
                                  context,
                                  'Enter title',
                                  Icons.title_rounded,
                                ),
                                onChanged: (v) {
                                  title = v;
                                  if (inlineError != null) {
                                    setState(() => inlineError = null);
                                  }
                                },
                              ),
                              const SizedBox(height: 20),
                              DropdownButtonFormField<DocumentType>(
                                initialValue: type,
                                decoration:
                                    DocuTrackerStyles.dropdownDecoration(
                                      context,
                                      'Document Type',
                                    ),
                                items: typeOptions
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
                                  context,
                                  'Description (optional)',
                                  Icons.notes_rounded,
                                ),
                                maxLines: 6,
                                onChanged: (v) =>
                                    description = v.isEmpty ? null : v,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Attachment (optional)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          pickedFileName ??
                                              'PDF, JPG, JPEG, or PNG — max 10 MB',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: creating
                                        ? null
                                        : () async {
                                            final result = await FilePicker
                                                .platform
                                                .pickFiles(
                                                  type: FileType.custom,
                                                  allowedExtensions: const [
                                                    'pdf',
                                                    'jpg',
                                                    'jpeg',
                                                    'png',
                                                  ],
                                                  allowMultiple: false,
                                                  withData: true,
                                                );
                                            if (result == null ||
                                                result.files.isEmpty ||
                                                result.files.single.bytes ==
                                                    null) {
                                              return;
                                            }
                                            final file = result.files.single;
                                            setState(() {
                                              pickedFileName = file.name;
                                              pickedFileBytes = file.bytes;
                                              inlineError = null;
                                            });
                                          },
                                    icon: const Icon(
                                      Icons.upload_file_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      pickedFileName == null
                                          ? 'Choose file'
                                          : 'Change',
                                    ),
                                  ),
                                  if (pickedFileName != null) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: 'Clear file',
                                      onPressed: creating
                                          ? null
                                          : () => setState(() {
                                              pickedFileName = null;
                                              pickedFileBytes = null;
                                            }),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ],
                                ],
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
                      top: BorderSide(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
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
                        onPressed: creating
                            ? null
                            : () async {
                                if (title.trim().isEmpty) {
                                  setState(() {
                                    inlineError =
                                        'Please enter a document title.';
                                  });
                                  return;
                                }
                                setState(() {
                                  creating = true;
                                  inlineError = null;
                                });
                                final created = await provider.createDocument(
                                  title: title.trim(),
                                  documentType: type,
                                  description: description,
                                  createdBy: auth.user?.id ?? '',
                                );
                                if (!ctx.mounted) return;
                                if (created != null) {
                                  var successMessage =
                                      'Draft created successfully.';
                                  if (pickedFileBytes != null &&
                                      pickedFileName != null &&
                                      created.id != null) {
                                    final uploaded = await provider
                                        .uploadAttachment(
                                          documentId: created.id!,
                                          fileBytes: pickedFileBytes!,
                                          fileName: pickedFileName!,
                                        );
                                    if (!ctx.mounted) return;
                                    if (uploaded == null) {
                                      final uploadErr = provider.error?.trim();
                                      setState(() {
                                        creating = false;
                                        inlineError =
                                            (uploadErr != null &&
                                                uploadErr.isNotEmpty)
                                            ? 'Draft saved, but upload failed: $uploadErr'
                                            : 'Draft saved, but attachment upload failed.';
                                      });
                                      onCreated?.call();
                                      return;
                                    }
                                    successMessage =
                                        'Draft created with attachment.';
                                  }
                                  Navigator.of(ctx).pop();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(successMessage)),
                                    );
                                    onCreated?.call();
                                  }
                                  return;
                                }
                                final msg = provider.error?.trim();
                                setState(() {
                                  creating = false;
                                  inlineError = (msg != null && msg.isNotEmpty)
                                      ? msg
                                      : 'Could not create document.';
                                });
                              },
                        style: DocuTrackerStyles.primaryButtonStyle(),
                        child: creating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create Draft'),
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
