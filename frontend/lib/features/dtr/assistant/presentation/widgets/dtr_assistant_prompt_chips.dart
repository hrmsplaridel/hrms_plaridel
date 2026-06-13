import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class DtrAssistantPromptChips extends StatelessWidget {
  const DtrAssistantPromptChips({
    super.key,
    required this.enabled,
    required this.onSelected,
  });

  final bool enabled;
  final ValueChanged<DtrAssistantPrompt> onSelected;

  static const prompts = <DtrAssistantPrompt>[
    DtrAssistantPrompt(
      text: 'What is my DTR status today?',
      intent: 'today_dtr',
    ),
    DtrAssistantPrompt(
      text: 'Do I have missing logs this week?',
      intent: 'missing_logs',
    ),
    DtrAssistantPrompt(
      text: 'What is my leave balance?',
      intent: 'leave_balance',
    ),
    DtrAssistantPrompt(
      text: 'Can I file 1 day vacation leave tomorrow?',
      intent: 'leave_availability_check',
    ),
    DtrAssistantPrompt(
      text: 'Ano status ng latest leave request ko?',
      intent: 'latest_leave_request',
    ),
    DtrAssistantPrompt(
      text: 'Who is holding my leave request?',
      intent: 'leave_approval_tracker',
    ),
    DtrAssistantPrompt(
      text: 'Na-approve na ba akong locator slip?',
      intent: 'latest_locator_request',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: prompts.map((prompt) {
        return ActionChip(
          label: Text(prompt.text),
          avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
          onPressed: enabled ? () => onSelected(prompt) : null,
          backgroundColor: AppTheme.dashMutedSurfaceOf(context),
          side: BorderSide(
            color: AppTheme.dashHairlineOf(context).withValues(alpha: 0.7),
          ),
          labelStyle: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 13,
          ),
        );
      }).toList(),
    );
  }
}

class DtrAssistantPrompt {
  const DtrAssistantPrompt({required this.text, required this.intent});

  final String text;
  final String intent;
}
