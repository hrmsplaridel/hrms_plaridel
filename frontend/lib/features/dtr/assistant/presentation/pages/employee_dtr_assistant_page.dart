import 'package:dio/dio.dart';
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
  List<DtrAssistantModelProfile> _modelProfiles = const [
    DtrAssistantModelProfile(
      id: 'tools_ollama',
      label: 'Qwen + HRMS tools',
      engine: 'tools',
      provider: 'ollama',
      model: 'qwen3:4b',
      available: true,
      recommended: true,
    ),
  ];
  String _selectedModelProfile = 'tools_ollama';
  bool _sending = false;
  final _inputController = TextEditingController();
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _loadModelProfiles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _loadModelProfiles() async {
    try {
      final result = await _api.fetchModels();
      if (!mounted || result.models.isEmpty) return;
      final selected =
          result.models.any(
            (item) => item.id == result.defaultModelProfile && item.available,
          )
          ? result.defaultModelProfile
          : result.models
                .firstWhere(
                  (item) => item.available,
                  orElse: () => result.models.first,
                )
                .id;
      setState(() {
        _modelProfiles = result.models;
        _selectedModelProfile = selected;
      });
    } catch (_) {
      // Keep the local default profile if the model list endpoint is unavailable.
    }
  }

  void _stop() {
    _cancelToken?.cancel('Cancelled by user');
    setState(() => _sending = false);
  }

  Future<void> _send(String text, {String? intent}) async {
    if (_sending) return;
    setState(() {
      _messages.add(DtrAssistantMessage.user(text));
      _sending = true;
    });
    _scrollToBottom();
    _cancelToken = CancelToken();

    try {
      final reply = await _api.sendMessage(
        text,
        intent: intent,
        modelProfile: _selectedModelProfile,
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      setState(() => _messages.add(reply));
    } on DioException catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e)) return;
      setState(
        () => _messages.add(
          DtrAssistantMessage(
            role: 'assistant',
            content: userFacingApiError(e),
            createdAt: DateTime.now(),
          ),
        ),
      );
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
                    (message) => Column(
                      crossAxisAlignment: message.isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        DtrAssistantMessageBubble(
                          message: message,
                          onEdit: message.isUser
                              ? () {
                                  _inputController.text = message.content;
                                  setState(() {
                                    final index = _messages.indexOf(message);
                                    if (index != -1) {
                                      _messages.removeRange(
                                        index,
                                        _messages.length,
                                      );
                                    }
                                  });
                                }
                              : null,
                        ),
                        if (!message.isUser && message.suggestions.isNotEmpty)
                          _AssistantSuggestionChips(
                            enabled: !_sending,
                            suggestions: message.suggestions,
                            onSelected: (suggestion) => _send(
                              suggestion.text,
                              intent: suggestion.intent,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_sending) const _TypingIndicator(),
                ],
              ),
            ),
            DtrAssistantInputBar(
              enabled: !_sending,
              sending: _sending,
              modelProfiles: _modelProfiles,
              selectedModelProfile: _selectedModelProfile,
              onModelChanged: (id) =>
                  setState(() => _selectedModelProfile = id),
              onSend: _send,
              onStop: _stop,
              controller: _inputController,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantSuggestionChips extends StatelessWidget {
  const _AssistantSuggestionChips({
    required this.enabled,
    required this.suggestions,
    required this.onSelected,
  });

  final bool enabled;
  final List<DtrAssistantSuggestion> suggestions;
  final ValueChanged<DtrAssistantSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions.take(3).map((suggestion) {
            return ActionChip(
              label: Text(suggestion.text),
              avatar: const Icon(Icons.auto_awesome_rounded, size: 15),
              onPressed: enabled ? () => onSelected(suggestion) : null,
              backgroundColor: AppTheme.dashMutedSurfaceOf(context),
              side: BorderSide(
                color: AppTheme.dashHairlineOf(context).withValues(alpha: 0.75),
              ),
              labelStyle: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 12,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
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
