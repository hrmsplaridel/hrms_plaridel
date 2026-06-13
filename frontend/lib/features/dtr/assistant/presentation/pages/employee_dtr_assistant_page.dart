import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_input_bar.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_message_bubble.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_prompt_chips.dart';
import 'package:lottie/lottie.dart';

class EmployeeDtrAssistantPage extends StatefulWidget {
  const EmployeeDtrAssistantPage({super.key, DtrAssistantApi? api})
    : _api = api;

  final DtrAssistantApi? _api;

  @override
  State<EmployeeDtrAssistantPage> createState() =>
      _EmployeeDtrAssistantPageState();
}

class _EmployeeDtrAssistantPageState extends State<EmployeeDtrAssistantPage> {
  late final DtrAssistantApi _api = widget._api ?? DtrAssistantApi();
  final _scrollController = ScrollController();
  final _messages = <DtrAssistantMessage>[
    DtrAssistantMessage(
      role: 'assistant',
      content:
          'Hi. Ask me about your DTR, leave requests, leave balances, or locator slips.',
      createdAt: DateTime.now(),
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text, {String? intent}) async {
    if (_sending) return;
    setState(() {
      _messages.add(DtrAssistantMessage.user(text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final reply = await _api.sendMessage(text, intent: intent);
      if (!mounted) return;
      setState(() => _messages.add(reply));
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          DtrAssistantMessage(
            role: 'assistant',
            content: userFacingApiError(e),
            createdAt: DateTime.now(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        title: const Text('DTR Assistant'),
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        elevation: dark ? 0 : 1,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  _AssistantHeader(sending: _sending),
                  const SizedBox(height: 16),
                  DtrAssistantPromptChips(
                    enabled: !_sending,
                    onSelected: (prompt) =>
                        _send(prompt.text, intent: prompt.intent),
                  ),
                  const SizedBox(height: 16),
                  ..._messages.map(
                    (message) => DtrAssistantMessageBubble(message: message),
                  ),
                  if (_sending) const _TypingIndicator(),
                ],
              ),
            ),
            DtrAssistantInputBar(enabled: !_sending, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  const _AssistantHeader({required this.sending});

  final bool sending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: Lottie.asset(
              'assets/animations/chatbot_assistant.json',
              repeat: true,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DTR Assistant',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sending
                      ? 'Checking your records...'
                      : 'Answers use your DTR, leave, and locator records.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Thinking',
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
