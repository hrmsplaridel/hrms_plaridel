import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';

class DtrAssistantInputBar extends StatelessWidget {
  const DtrAssistantInputBar({
    super.key,
    required this.enabled,
    required this.sending,
    required this.modelProfiles,
    required this.selectedModelProfile,
    required this.onModelChanged,
    required this.onSend,
    required this.onStop,
    required this.controller,
  });

  final bool enabled;
  final bool sending;
  final List<DtrAssistantModelProfile> modelProfiles;
  final String selectedModelProfile;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final TextEditingController controller;

  void _send() {
    final text = controller.text.trim();
    if (text.isEmpty || !enabled) return;
    controller.clear();
    onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    final textField = TextField(
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _send(),
      decoration: InputDecoration(
        hintText: 'Ask about your HRMS records and services',
        filled: true,
        fillColor: AppTheme.dashMutedSurfaceOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );

    final modelSelector = _AssistantModelSelector(
      enabled: enabled,
      profiles: modelProfiles,
      selectedId: selectedModelProfile,
      onChanged: onModelChanged,
      iconOnly: isNarrow,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final hasText = controller.text.trim().isNotEmpty;
            final canSend = enabled && hasText;

            final sendButton = sending
                ? IconButton.filled(
                    tooltip: 'Stop generating',
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                  )
                : IconButton.filled(
                    tooltip: 'Send',
                    onPressed: canSend ? _send : null,
                    icon: const Icon(Icons.send_rounded),
                  );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                modelSelector,
                const SizedBox(width: 8),
                Expanded(child: textField),
                const SizedBox(width: 8),
                sendButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AssistantModelSelector extends StatelessWidget {
  const _AssistantModelSelector({
    required this.enabled,
    required this.profiles,
    required this.selectedId,
    required this.onChanged,
    this.iconOnly = false,
  });

  final bool enabled;
  final List<DtrAssistantModelProfile> profiles;
  final String selectedId;
  final ValueChanged<String> onChanged;

  /// Compact, label-less control (icon only) to fit on a single row on mobile.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final selected = profiles.firstWhere(
      (item) => item.id == selectedId,
      orElse: () => profiles.isNotEmpty
          ? profiles.first
          : const DtrAssistantModelProfile(
              id: 'tools_ollama',
              label: 'Qwen',
              engine: 'tools',
              provider: 'ollama',
              model: '',
            ),
    );
    final shortLabel = _shortLabel(selected);

    return PopupMenuButton<String>(
      tooltip: 'AI model',
      enabled: enabled && profiles.isNotEmpty,
      onSelected: onChanged,
      itemBuilder: (context) {
        return profiles.map((profile) {
          final isSelected = profile.id == selected.id;
          final subtitle = profile.available
              ? '${profile.provider} ${profile.engine}'
              : profile.unavailableReason ?? 'Unavailable';
          return PopupMenuItem<String>(
            value: profile.id,
            enabled: profile.available,
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: isSelected
                      ? AppTheme.primaryNavy
                      : AppTheme.dashTextSecondaryOf(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 48,
        width: iconOnly ? 48 : null,
        constraints: iconOnly
            ? null
            : const BoxConstraints(minWidth: 76, maxWidth: 128),
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 10),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: iconOnly
            ? Center(
                child: Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _shortLabel(DtrAssistantModelProfile profile) {
    if (profile.id == 'tools_ollama') return 'Qwen';
    if (profile.id == 'tools_groq') return 'Groq';
    if (profile.id == 'direct_groq') return 'Groq direct';
    return profile.label;
  }
}
