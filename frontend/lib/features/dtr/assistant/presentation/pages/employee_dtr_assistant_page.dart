import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_leave_prefill.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_privacy_consent_storage.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_session_storage.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/dtr_assistant_turn_guard.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_input_bar.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_message_bubble.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_prompt_chips.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_slip_form_initial_values.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/employee_locator_slip_screen.dart'
    as locator;
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/dtr_reports.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class EmployeeDtrAssistantPage extends StatefulWidget {
  const EmployeeDtrAssistantPage({
    super.key,
    DtrAssistantApi? api,
    this.floating = false,
    this.onMinimize,
    this.onClose,
    this.onExpand,
  }) : _api = api;

  final DtrAssistantApi? _api;
  final bool floating;
  final FutureOr<void> Function()? onMinimize;
  final FutureOr<void> Function()? onClose;
  final FutureOr<void> Function()? onExpand;

  @override
  State<EmployeeDtrAssistantPage> createState() =>
      _EmployeeDtrAssistantPageState();
}

class _EmployeeDtrAssistantPageState extends State<EmployeeDtrAssistantPage> {
  static const _welcomeMessageText =
      'Hi. I am your HRMS Assistant. Ask me about your DTR, leave requests, leave balances, or locator slips.';

  late final DtrAssistantApi _api = widget._api ?? DtrAssistantApi();
  final _scrollController = ScrollController();
  final _messages = <DtrAssistantMessage>[];
  final _feedbackByMessageId = <String, String>{};
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
  String? _selectedExternalConsentVersion;
  bool _sending = false;
  bool _resettingChat = false;
  bool _sessionLoaded = false;
  String _conversationId = DtrAssistantSessionStorage.createConversationId();
  final _inputController = TextEditingController();
  final _turnGuard = DtrAssistantTurnGuard();
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _loadModelProfiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreSession());
    });
  }

  DtrAssistantMessage _welcomeMessage() {
    return DtrAssistantMessage(
      role: 'assistant',
      content: _welcomeMessageText,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _restoreSession() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(_welcomeMessage());
        _sessionLoaded = true;
      });
      return;
    }

    final conversationId =
        await DtrAssistantSessionStorage.loadOrCreateConversationId(userId);
    final restored = await DtrAssistantSessionStorage.loadMessages(
      userId,
      conversationId,
    );
    if (!mounted) return;
    setState(() {
      _conversationId = conversationId;
      _messages
        ..clear()
        ..addAll(restored.isEmpty ? [_welcomeMessage()] : restored);
      _sessionLoaded = true;
    });
    if (_messages.length > 1) {
      _scrollToBottom();
    }
  }

  Future<void> _persistSession() async {
    if (!mounted || !_sessionLoaded) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) return;
    await DtrAssistantSessionStorage.saveMessages(
      userId,
      _conversationId,
      _messages,
    );
  }

  Future<void> _startNewChat() async {
    if (_sending || _resettingChat) return;
    final userId = context.read<AuthProvider>().user?.id;
    final previousConversationId = _conversationId;
    setState(() => _resettingChat = true);
    try {
      await _api.resetChat(conversationId: previousConversationId);
    } catch (_) {
      // Local reset still helps even if the backend reset fails.
    }
    if (userId != null && userId.isNotEmpty) {
      await DtrAssistantSessionStorage.clearAllForUser(userId);
      final nextConversationId =
          DtrAssistantSessionStorage.createConversationId();
      await DtrAssistantSessionStorage.saveConversationId(
        userId,
        nextConversationId,
      );
      _conversationId = nextConversationId;
    } else {
      _conversationId = DtrAssistantSessionStorage.createConversationId();
    }
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add(_welcomeMessage());
      _feedbackByMessageId.clear();
      _autoExecutedActionKeys.clear();
      _resettingChat = false;
    });
    _scrollToBottom();
  }

  Future<void> _confirmClearChatHistory() async {
    if (_sending || _resettingChat) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'This permanently removes your saved HRMS Assistant conversation '
          'from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep history'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _startNewChat();
    }
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
    if (!_sending) return;
    _turnGuard.invalidate();
    _cancelToken?.cancel('Cancelled by user');
    _cancelToken = null;
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _handleModelChanged(String id) async {
    final profile = _modelProfiles.cast<DtrAssistantModelProfile?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (profile == null || !profile.available) return;

    if (!profile.external || !profile.requiresConsent) {
      if (!mounted) return;
      setState(() {
        _selectedModelProfile = profile.id;
        _selectedExternalConsentVersion = null;
      });
      return;
    }

    final userId = context.read<AuthProvider>().user?.id ?? '';
    final consentVersion = profile.consentVersion?.trim() ?? '';
    final alreadyConsented = await DtrAssistantPrivacyConsentStorage.hasConsent(
      userId: userId,
      provider: profile.provider,
      version: consentVersion,
    );
    if (!mounted) return;

    var accepted = alreadyConsented;
    if (!accepted) {
      accepted = await _showExternalAiConsentDialog(profile);
      if (!accepted || !mounted) return;
      await DtrAssistantPrivacyConsentStorage.grantConsent(
        userId: userId,
        provider: profile.provider,
        version: consentVersion,
      );
    }
    if (!mounted) return;
    setState(() {
      _selectedModelProfile = profile.id;
      _selectedExternalConsentVersion = consentVersion;
    });
  }

  Future<bool> _showExternalAiConsentDialog(
    DtrAssistantModelProfile profile,
  ) async {
    final disclosure =
        profile.dataDisclosure ??
        'Your question and the minimum HRMS records needed to answer it will be processed by ${profile.provider}.';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('dtr-assistant-external-ai-consent-dialog'),
        icon: const Icon(Icons.cloud_outlined),
        title: Text('Use ${profile.label}?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            '$disclosure\n\nThe local Qwen model remains available if you do not agree.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const ValueKey('dtr-assistant-external-ai-consent-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.cloud_done_outlined),
            label: const Text('Agree and use cloud AI'),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _runPresentationAction(FutureOr<void> Function()? action) async {
    if (action == null || _sending || _resettingChat) return;
    await _persistSession();
    if (!mounted) return;
    await action();
  }

  Future<void> _send(String text, {String? intent}) async {
    if (_sending) return;
    final selectedProfile = _modelProfiles.firstWhere(
      (item) => item.id == _selectedModelProfile,
      orElse: () => _modelProfiles.first,
    );
    if (selectedProfile.external &&
        selectedProfile.requiresConsent &&
        _selectedExternalConsentVersion != selectedProfile.consentVersion) {
      await _handleModelChanged(selectedProfile.id);
      if (!mounted ||
          _selectedExternalConsentVersion != selectedProfile.consentVersion) {
        return;
      }
    }
    setState(() {
      _messages.add(DtrAssistantMessage.user(text));
      _sending = true;
    });
    final turnGeneration = _turnGuard.begin();
    _scrollToBottom();
    unawaited(_persistSession());
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    try {
      final reply = await _api.sendMessage(
        text,
        intent: intent,
        modelProfile: _selectedModelProfile,
        conversationId: _conversationId,
        externalConsentVersion: _selectedExternalConsentVersion,
        cancelToken: cancelToken,
      );
      if (!mounted || !_turnGuard.isCurrent(turnGeneration)) return;
      setState(() {
        _messages.add(reply);
      });
      await _persistSession();
      _runAutoAction(reply);
    } on DioException catch (e) {
      if (!mounted || !_turnGuard.isCurrent(turnGeneration)) return;
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
      if (!mounted || !_turnGuard.isCurrent(turnGeneration)) return;
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
      if (mounted && _turnGuard.isCurrent(turnGeneration)) {
        if (identical(_cancelToken, cancelToken)) _cancelToken = null;
        setState(() => _sending = false);
        await _persistSession();
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
      final unavailable = e is DioException && e.response?.statusCode == 404;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unavailable
                ? 'This export is no longer available.'
                : 'Could not prepare ${attachment.filename}: $e',
          ),
          action: unavailable
              ? SnackBarAction(
                  label: 'Regenerate',
                  onPressed: () => unawaited(
                    _send(
                      _regenerateExportPrompt(attachment),
                      intent: 'dtr_export_guidance',
                    ),
                  ),
                )
              : null,
        ),
      );
    }
  }

  String _regenerateExportPrompt(DtrAssistantAttachment attachment) {
    final match = RegExp(
      r'dtr_export_(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})\.',
    ).firstMatch(attachment.filename);
    if (match == null) return 'Generate my DTR export again.';
    final startDate = match.group(1);
    final endDate = match.group(2);
    if (startDate == endDate) {
      return 'Generate my DTR export for $startDate.';
    }
    return 'Generate my DTR export from $startDate to $endDate.';
  }

  Future<void> _executeAction(
    DtrAssistantMessage message,
    DtrAssistantAction action,
  ) async {
    switch (action.type) {
      case 'send_prompt':
        final prompt = _resolvedActionPrompt(action);
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
          child: _LocatorActionPage(
            openForm: true,
            initialValues: LocatorSlipFormInitialValues.fromActionPayload(
              action.payload,
            ),
          ),
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
          title: 'My DTR Report',
          child: const DtrReports(selfService: true),
        );
        return;
    }
  }

  String? _resolvedActionPrompt(DtrAssistantAction action) {
    if (action.id == 'generate_dtr_export') {
      final startDate = action.payload['startDate']?.toString().trim();
      final endDate = action.payload['endDate']?.toString().trim();
      if (startDate != null && startDate.isNotEmpty) {
        if (endDate == null || endDate.isEmpty || endDate == startDate) {
          return 'Generate my DTR export for $startDate.';
        }
        return 'Generate my DTR export from $startDate to $endDate.';
      }
    }
    return action.prompt?.trim();
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
    final initialRequest = leaveRequestFromAssistantAction(action, userId);
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

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final floating = widget.floating;

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        automaticallyImplyLeading: !floating,
        title: const Text('HRMS Assistant'),
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        elevation: dark ? 0 : 1,
        actions: [
          if (!floating && widget.onMinimize != null)
            IconButton(
              tooltip: 'Minimize to floating assistant',
              onPressed: (_sending || _resettingChat)
                  ? null
                  : () => _runPresentationAction(widget.onMinimize),
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
            ),
          IconButton(
            tooltip: 'Clear chat history',
            onPressed: (_sending || _resettingChat)
                ? null
                : _confirmClearChatHistory,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          if (floating && widget.onExpand != null)
            IconButton(
              tooltip: 'Open full assistant',
              onPressed: (_sending || _resettingChat)
                  ? null
                  : () => _runPresentationAction(widget.onExpand),
              icon: const Icon(Icons.open_in_full_rounded),
            ),
          if (floating && widget.onClose != null)
            IconButton(
              tooltip: 'Close assistant',
              onPressed: (_sending || _resettingChat)
                  ? null
                  : () => _runPresentationAction(widget.onClose),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  floating ? 12 : 16,
                  floating ? 12 : 16,
                  floating ? 12 : 16,
                  12,
                ),
                children: [
                  if (!floating) ...[
                    _AssistantHeader(sending: _sending),
                    const SizedBox(height: 16),
                  ],
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
              onModelChanged: (id) => unawaited(_handleModelChanged(id)),
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
  const _LocatorActionPage({required this.openForm, this.initialValues});

  final bool openForm;
  final LocatorSlipFormInitialValues? initialValues;

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
      await _locatorKey.currentState?.openCreateForm(
        initialValues: widget.initialValues,
      );
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
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final lottieSize = isNarrow ? 54.0 : 74.0;

    return Container(
      padding: EdgeInsets.all(isNarrow ? 12 : 14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: lottieSize,
            height: lottieSize,
            child: Lottie.asset(
              'assets/animations/chatbot_assistant.json',
              repeat: true,
            ),
          ),
          SizedBox(width: isNarrow ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HRMS Assistant',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: isNarrow ? 16 : 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sending
                      ? 'Checking your records...'
                      : 'Answers use your HRMS records, including DTR, leave, and locator.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: isNarrow ? 12 : 13,
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
