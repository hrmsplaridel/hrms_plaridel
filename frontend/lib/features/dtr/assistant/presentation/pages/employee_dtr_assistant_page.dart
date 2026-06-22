import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_input_bar.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_message_bubble.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_prompt_chips.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/features/dtr/dtr_main.dart';
import 'package:hrms_plaridel/features/dtr/dtr_routes.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/employee_locator_slip_screen.dart'
    as locator;
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final _feedbackByMessageId = <String, String>{};
  final _promptByMessageId = <String, String>{};
  final _autoExecutedActionKeys = <String>{};
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
      setState(() {
        _messages.add(reply);
        final replyId = reply.id;
        if (replyId != null && replyId.isNotEmpty) {
          _promptByMessageId[replyId] = text;
        }
      });
      _runAutoAction(reply);
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

  Future<void> _submitFeedback(
    DtrAssistantMessage message,
    String rating,
  ) async {
    final id = message.id;
    if (id == null || id.isEmpty) return;
    final comment = rating == 'down' ? await _showWrongFeedbackDialog() : null;
    if (rating == 'down' && comment == null) return;
    final previous = _feedbackByMessageId[id];
    setState(() => _feedbackByMessageId[id] = rating);
    try {
      await _api.submitFeedback(
        message: message,
        rating: rating,
        modelProfile: _selectedModelProfile,
        promptPreview: _promptByMessageId[id],
        comment: comment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rating == 'up' ? 'Marked correct.' : 'Marked wrong with note.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _feedbackByMessageId.remove(id);
        } else {
          _feedbackByMessageId[id] = previous;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save feedback: ${userFacingApiError(e)}'),
        ),
      );
    }
  }

  Future<String?> _showWrongFeedbackDialog() async {
    final detailsController = TextEditingController();
    String selectedReason = 'Wrong answer';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final reasons = const [
              'Wrong answer',
              'Wrong language',
              'Wrong date',
              'Missing data',
              'Wrong intent',
            ];

            return AlertDialog(
              title: const Text('What went wrong?'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This helps improve the assistant for similar prompts.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: reasons.map((reason) {
                        return ChoiceChip(
                          label: Text(reason),
                          selected: selectedReason == reason,
                          onSelected: (_) =>
                              setDialogState(() => selectedReason = reason),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: detailsController,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Optional details',
                        hintText:
                            'Example: I asked in Bisaya but it replied in English.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final details = detailsController.text.trim();
                    final comment = details.isEmpty
                        ? selectedReason
                        : '$selectedReason: $details';
                    Navigator.of(dialogContext).pop(comment);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    detailsController.dispose();
    return result;
  }

  Future<List<int>> _downloadAttachment(
    DtrAssistantAttachment attachment,
  ) async {
    return _api.downloadAttachment(attachment);
  }

  Future<void> _shareAttachment(DtrAssistantAttachment attachment) async {
    try {
      final bytes = Uint8List.fromList(await _downloadAttachment(attachment));
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare ${attachment.filename}: $e')),
      );
    }
  }

  Future<void> _executeAction(
    DtrAssistantMessage message,
    DtrAssistantAction action,
  ) async {
    switch (action.type) {
      case 'send_prompt':
        final prompt = action.prompt?.trim();
        if (prompt == null || prompt.isEmpty) return;
        await _send(prompt, intent: action.intent);
        return;
      case 'download_attachment':
        final attachment = _attachmentForAction(message, action);
        if (attachment == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export attachment is unavailable.')),
          );
          return;
        }
        await _shareAttachment(attachment);
        return;
      case 'open_leave_form':
        await _openLeaveFormFromAction(action);
        return;
      case 'open_leave_page':
        _openStandalonePage(
          title: 'My Leave',
          child: const LeaveMain(initialSection: LeaveSection.requests),
        );
        return;
      case 'open_locator_form':
        _openStandalonePage(
          title: 'Locator Requests',
          child: const _LocatorActionPage(openForm: true),
        );
        return;
      case 'open_locator_page':
        _openStandalonePage(
          title: 'Locator Requests',
          child: const _LocatorActionPage(openForm: false),
        );
        return;
      case 'open_dtr_time_logs':
        _openStandalonePage(
          title: 'My Attendance',
          child: const EmployeeAttendanceDetailsSection(),
        );
        return;
      case 'open_dtr_reports':
        _openStandalonePage(
          title: 'DTR Reports',
          child: const DtrMain(section: DtrSection.reports),
        );
        return;
    }
  }

  void _runAutoAction(DtrAssistantMessage message) {
    DtrAssistantAction? action;
    for (final item in message.actions) {
      if (!item.autoExecute) continue;
      if (!item.type.startsWith('open_')) continue;
      action = item;
      break;
    }
    if (action == null) return;
    final messageKey =
        message.id ?? '${message.createdAt.microsecondsSinceEpoch}';
    final actionKey = '$messageKey:${action.id}:${action.type}';
    if (!_autoExecutedActionKeys.add(actionKey)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _executeAction(message, action!);
    });
  }

  DtrAssistantAttachment? _attachmentForAction(
    DtrAssistantMessage message,
    DtrAssistantAction action,
  ) {
    final attachmentId = action.payload['attachmentId']?.toString();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      for (final attachment in message.attachments) {
        if (attachment.id == attachmentId) return attachment;
      }
    }
    if (message.attachments.isNotEmpty) return message.attachments.first;
    return null;
  }

  void _openStandalonePage({required String title, required Widget child}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.dashCanvasOf(context),
          appBar: AppBar(
            title: Text(title),
            backgroundColor: AppTheme.dashPanelOf(context),
            foregroundColor: AppTheme.dashTextPrimaryOf(context),
            elevation: AppTheme.dashIsDark(context) ? 0 : 1,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLeaveFormFromAction(DtrAssistantAction action) async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not identify your account.')),
      );
      return;
    }
    final initialRequest = _initialLeaveRequestFromAction(action, userId);
    final result = await openResponsiveLeaveFormHost<String?>(
      context: context,
      builder: (_) => LeaveRequestFormScreen(
        initialRequest: initialRequest,
        onSaveDraft: (request) async {
          final provider = context.read<LeaveProvider>();
          final saved = request.id == null || request.id!.isEmpty
              ? await provider.saveDraft(request)
              : await provider.updateRequest(request);
          return saved != null;
        },
        onSubmitRequest: (request) async {
          final provider = context.read<LeaveProvider>();
          final saved = request.id == null || request.id!.isEmpty
              ? await provider.submitRequest(request)
              : await provider.updateRequest(
                  request.copyWith(status: LeaveRequestStatus.pending),
                );
          return saved != null;
        },
        onSubmitRequestWithAttachment: (request, fileBytes, fileName) async {
          final provider = context.read<LeaveProvider>();
          final saved = await provider.submitRequestWithAttachment(
            request: request,
            fileBytes: fileBytes,
            fileName: fileName,
          );
          return saved != null;
        },
      ),
    );
    if (!mounted || result == null) return;
    if (result != kLeaveFormResultDraftSaved &&
        result != kLeaveFormResultSubmitted) {
      return;
    }
    await context.read<LeaveProvider>().loadMyLeaveData(userId);
    if (!mounted) return;
    showLeaveFormSuccessSnackBar(context, result);
  }

  LeaveRequest _initialLeaveRequestFromAction(
    DtrAssistantAction action,
    String userId,
  ) {
    final payload = action.payload;
    final leaveType = _leaveTypeFromPayload(payload['leaveType']?.toString());
    final startDate = _dateFromPayload(payload['startDate']);
    final endDate = _dateFromPayload(payload['endDate']) ?? startDate;
    return LeaveRequest(
      userId: userId,
      leaveType: leaveType,
      leaveTypeName: leaveType.value,
      leaveTypeDisplayName: leaveType.displayName,
      startDate: startDate,
      endDate: endDate,
      workingDaysApplied: _calendarDayEstimate(startDate, endDate),
      status: LeaveRequestStatus.draft,
    );
  }

  LeaveType _leaveTypeFromPayload(String? value) {
    final normalized = (value ?? '').toLowerCase();
    if (normalized.contains('sick')) return LeaveType.sickLeave;
    if (normalized.contains('vacation')) return LeaveType.vacationLeave;
    return LeaveType.vacationLeave;
  }

  DateTime? _dateFromPayload(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  double? _calendarDayEstimate(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final startOnly = DateTime(start.year, start.month, start.day);
    final endOnly = DateTime(end.year, end.month, end.day);
    if (endOnly.isBefore(startOnly)) return null;
    return endOnly.difference(startOnly).inDays + 1.0;
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
                          feedback: message.id == null
                              ? null
                              : _feedbackByMessageId[message.id],
                          onFeedback: message.isUser
                              ? null
                              : (rating) => _submitFeedback(message, rating),
                          onDownloadAttachment: _downloadAttachment,
                          onEdit: message.isUser
                              ? () {
                                  _inputController.text = message.content;
                                  setState(() {
                                    final index = _messages.indexOf(message);
                                    if (index != -1) {
                                      final removed = _messages.sublist(index);
                                      for (final removedMessage in removed) {
                                        final removedId = removedMessage.id;
                                        if (removedId != null) {
                                          _feedbackByMessageId.remove(
                                            removedId,
                                          );
                                          _promptByMessageId.remove(removedId);
                                        }
                                      }
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
                        if (!message.isUser && message.actions.isNotEmpty)
                          _AssistantActionChips(
                            enabled: !_sending,
                            actions: message.actions,
                            onSelected: (action) =>
                                _executeAction(message, action),
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

class _AssistantActionChips extends StatelessWidget {
  const _AssistantActionChips({
    required this.enabled,
    required this.actions,
    required this.onSelected,
  });

  final bool enabled;
  final List<DtrAssistantAction> actions;
  final ValueChanged<DtrAssistantAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actions.take(4).map((action) {
            return FilledButton.tonalIcon(
              onPressed: enabled ? () => onSelected(action) : null,
              icon: Icon(_iconForAction(action), size: 16),
              label: Text(action.label, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  IconData _iconForAction(DtrAssistantAction action) {
    switch (action.icon) {
      case 'download':
      case 'file_download':
        return Icons.download_rounded;
      case 'event_available':
        return Icons.event_available_rounded;
      case 'event_note':
        return Icons.event_note_rounded;
      case 'add_location':
        return Icons.add_location_alt_rounded;
      case 'pin_drop':
        return Icons.pin_drop_rounded;
      case 'schedule':
        return Icons.schedule_rounded;
      case 'build':
        return Icons.build_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }
}

class _LocatorActionPage extends StatefulWidget {
  const _LocatorActionPage({required this.openForm});

  final bool openForm;

  @override
  State<_LocatorActionPage> createState() => _LocatorActionPageState();
}

class _LocatorActionPageState extends State<_LocatorActionPage> {
  final _locatorKey = GlobalKey<locator.EmployeeLocatorSlipScreenState>();
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.openForm || _opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _locatorKey.currentState?.openCreateForm();
    });
  }

  @override
  Widget build(BuildContext context) {
    return locator.EmployeeLocatorSlipScreen(key: _locatorKey);
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
