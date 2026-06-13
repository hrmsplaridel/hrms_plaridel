import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';

class DtrAssistantMessageBubble extends StatelessWidget {
  const DtrAssistantMessageBubble({super.key, required this.message});

  final DtrAssistantMessage message;

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
        child: Container(
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
          child: SelectableText(
            message.content,
            style: TextStyle(color: textColor, height: 1.35, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
