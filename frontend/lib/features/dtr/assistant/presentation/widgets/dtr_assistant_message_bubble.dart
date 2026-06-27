import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:share_plus/share_plus.dart';

class DtrAssistantMessageBubble extends StatelessWidget {
  const DtrAssistantMessageBubble({
    super.key,
    required this.message,
    this.onEdit,
    this.feedback,
    this.onFeedback,
    this.onDownloadAttachment,
  });

  final DtrAssistantMessage message;
  final VoidCallback? onEdit;
  final String? feedback;
  final ValueChanged<String>? onFeedback;
  final Future<List<int>> Function(DtrAssistantAttachment attachment)?
  onDownloadAttachment;

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final dark = AppTheme.dashIsDark(context);
    final bubbleColor = isUser
        ? AppTheme.primaryNavy
        : (dark ? AppTheme.dashMutedSurfaceOf(context) : Colors.white);
    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.10)
        : AppTheme.dashHairlineOf(context);
    final textColor = isUser
        ? Colors.white
        : AppTheme.dashTextPrimaryOf(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: Radius.circular(isUser ? 8 : 2),
                  bottomRight: Radius.circular(isUser ? 2 : 8),
                ),
                border: isUser ? null : Border.all(color: borderColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    SelectableText(
                      message.content,
                      style: TextStyle(
                        color: textColor,
                        height: 1.35,
                        fontSize: 14,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      shrinkWrap: true,
                      styleSheet: _assistantMarkdownStyleSheet(
                        context,
                        textColor: textColor,
                      ),
                    ),
                  if (!isUser && message.attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final attachment in message.attachments)
                      _AssistantAttachmentButton(
                        attachment: attachment,
                        onDownloadAttachment: onDownloadAttachment,
                      ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isUser && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    onPressed: onEdit,
                    tooltip: 'Edit message',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                if (isUser && onEdit != null) const SizedBox(width: 8),
                if (!isUser &&
                    message.id != null &&
                    message.id!.isNotEmpty) ...[
                  IconButton(
                    icon: Icon(
                      feedback == 'up'
                          ? Icons.thumb_up_alt_rounded
                          : Icons.thumb_up_alt_outlined,
                      size: 16,
                    ),
                    onPressed: onFeedback == null
                        ? null
                        : () => onFeedback!.call('up'),
                    tooltip: 'Correct',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    color: feedback == 'up'
                        ? Colors.orange.shade800
                        : AppTheme.dashTextSecondaryOf(context),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      feedback == 'down'
                          ? Icons.thumb_down_alt_rounded
                          : Icons.thumb_down_alt_outlined,
                      size: 16,
                    ),
                    onPressed: onFeedback == null
                        ? null
                        : () => onFeedback!.call('down'),
                    tooltip: 'Wrong',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    color: feedback == 'down'
                        ? Colors.orange.shade800
                        : AppTheme.dashTextSecondaryOf(context),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.content_copy_rounded, size: 16),
                  onPressed: () => _copyToClipboard(context),
                  tooltip: 'Copy message',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

MarkdownStyleSheet _assistantMarkdownStyleSheet(
  BuildContext context, {
  required Color textColor,
}) {
  final base = TextStyle(
    color: textColor,
    fontSize: 14,
    height: 1.35,
  );

  return MarkdownStyleSheet(
    p: base,
    pPadding: const EdgeInsets.only(bottom: 8),
    strong: base.copyWith(fontWeight: FontWeight.w700),
    em: base.copyWith(fontStyle: FontStyle.italic),
    listBullet: base,
    listIndent: 24,
    blockSpacing: 8,
    h1: base.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
    h2: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
    h3: base.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: AppTheme.dashHairlineOf(context),
        ),
      ),
    ),
  );
}

class _AssistantAttachmentButton extends StatelessWidget {
  const _AssistantAttachmentButton({
    required this.attachment,
    this.onDownloadAttachment,
  });

  final DtrAssistantAttachment attachment;
  final Future<List<int>> Function(DtrAssistantAttachment attachment)?
  onDownloadAttachment;

  Future<void> _shareAttachment(BuildContext context) async {
    try {
      final rawBytes = onDownloadAttachment == null
          ? const <int>[]
          : await onDownloadAttachment!(attachment);
      final bytes = Uint8List.fromList(rawBytes);
      if (bytes.isEmpty) {
        throw Exception('The file was empty or unavailable.');
      }
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: attachment.filename,
          mimeType: attachment.mimeType,
        ),
      ], subject: attachment.filename);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare ${attachment.filename}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _shareAttachment(context),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(attachment.filename, overflow: TextOverflow.ellipsis),
    );
  }
}
