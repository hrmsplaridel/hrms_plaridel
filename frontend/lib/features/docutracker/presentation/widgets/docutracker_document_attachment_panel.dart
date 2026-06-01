import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_open_attachment.dart';
import 'docutracker_document_detail_ui.dart';
import 'docutracker_error_banner.dart';

/// Attachment upload, download, and remove for a DocuTracker document.
class DocuTrackerDocumentAttachmentPanel extends StatefulWidget {
  const DocuTrackerDocumentAttachmentPanel({
    super.key,
    required this.document,
    required this.canDownload,
    required this.canModify,
  });

  final DocuTrackerDocument document;
  final bool canDownload;
  final bool canModify;

  @override
  State<DocuTrackerDocumentAttachmentPanel> createState() =>
      _DocuTrackerDocumentAttachmentPanelState();
}

class _DocuTrackerDocumentAttachmentPanelState
    extends State<DocuTrackerDocumentAttachmentPanel> {
  bool _busy = false;

  bool get _hasFile {
    final path = widget.document.filePath?.trim();
    return path != null && path.isNotEmpty;
  }

  String get _displayName {
    final name = widget.document.fileName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Attachment';
  }

  Future<void> _pickAndUpload() async {
    final docId = widget.document.id;
    if (docId == null || docId.isEmpty || !widget.canModify) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) {
      return;
    }
    if (!mounted) return;

    final file = result.files.single;
    final bytes = file.bytes!;
    final name = file.name;
    if (name.isEmpty) return;

    setState(() => _busy = true);
    final provider = context.read<DocuTrackerProvider>();
    final updated = await provider.uploadAttachment(
      documentId: docId,
      fileBytes: bytes,
      fileName: name,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment uploaded.')));
      return;
    }
    showDocuTrackerProviderError(
      context,
      provider,
      fallback: 'Could not upload attachment.',
    );
  }

  Future<void> _openAttachment() async {
    final docId = widget.document.id;
    if (docId == null || docId.isEmpty || !_hasFile || !widget.canDownload) {
      return;
    }

    setState(() => _busy = true);
    final provider = context.read<DocuTrackerProvider>();
    try {
      final bytes = await provider.getAttachmentBytes(docId);
      if (!mounted) return;
      setState(() => _busy = false);
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No attachment found.')));
        return;
      }
      await openDocuTrackerAttachmentBytes(bytes, _displayName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open attachment: $e')));
    }
  }

  Future<void> _removeAttachment() async {
    final docId = widget.document.id;
    if (docId == null || docId.isEmpty || !_hasFile || !widget.canModify) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: const Text('The file will be deleted from this document.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final provider = context.read<DocuTrackerProvider>();
    final updated = await provider.removeAttachment(docId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment removed.')));
      return;
    }
    showDocuTrackerProviderError(
      context,
      provider,
      fallback: 'Could not remove attachment.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canDownload && !widget.canModify) {
      return const SizedBox.shrink();
    }

    return DocuTrackerDetailSectionCard(
      icon: Icons.attach_file_rounded,
      title: 'Attachment',
      subtitle: 'PDF, Image — max 10 MB',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: DocuTrackerTokens.brand,
              ),
            ),
          if (_hasFile) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.insert_drive_file_outlined,
                color: DocuTrackerTokens.brand,
              ),
              title: Text(
                _displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DocuTrackerTokens.textPrimaryOf(context),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.canDownload)
                    IconButton(
                      tooltip: 'Open',
                      onPressed: _busy ? null : _openAttachment,
                      icon: const Icon(Icons.open_in_new_rounded),
                      color: DocuTrackerTokens.brand,
                    ),
                  if (widget.canModify)
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _busy ? null : _removeAttachment,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: DocuTrackerTokens.overdueAccent,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.canModify)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _pickAndUpload,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Replace file'),
                  style: TextButton.styleFrom(
                    foregroundColor: DocuTrackerTokens.brand,
                  ),
                ),
              ),
          ] else if (widget.canModify)
            DocuTrackerPeachDashedBox(
              child: InkWell(
                onTap: _busy ? null : _pickAndUpload,
                borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 32,
                      color: DocuTrackerTokens.brand.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload file',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DocuTrackerTokens.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              'No file attached.',
              style: DocuTrackerTokens.subtitleStyle(context),
            ),
        ],
      ),
    );
  }
}
