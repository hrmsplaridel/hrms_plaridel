import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';

/// A short-lived field conversation. Drafts are never applied automatically.
class LeaveFieldAssistant extends StatefulWidget {
  const LeaveFieldAssistant({
    super.key,
    required this.leaveType,
    required this.fieldKey,
    required this.label,
    this.initialValue = '',
    this.canDraft = true,
    this.api,
    this.module = 'leave',
  });

  final String leaveType;
  final String fieldKey;
  final String label;
  final String initialValue;
  final bool canDraft;
  final DtrAssistantApi? api;
  final String module;

  @override
  State<LeaveFieldAssistant> createState() => _LeaveFieldAssistantState();
}

class _LeaveFieldAssistantState extends State<LeaveFieldAssistant> {
  late final _facts = TextEditingController(text: widget.initialValue);
  late final _api = widget.api ?? DtrAssistantApi();
  CancelToken? _cancel;
  bool _busy = false;
  String _answer = '';
  String? _draft;

  @override
  void initState() {
    super.initState();
    _ask(false);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _facts.dispose();
    super.dispose();
  }

  Future<void> _ask(bool draft) async {
    setState(() {
      _busy = true;
      _draft = null;
    });
    _cancel = CancelToken();
    try {
      final reply = await _api.sendMessage(
        draft
            ? 'Help me phrase this field.'
            : 'What should I put in this field? Give an example.',
        modelProfile: 'tools_ollama',
        cancelToken: _cancel,
        formContext: {
          'module': widget.module,
          if (widget.module == 'locator') 'locatorType': widget.leaveType,
          if (widget.module == 'leave') 'leaveType': widget.leaveType,
          'fieldKey': widget.fieldKey,
          'task': draft ? 'draft' : 'explain',
          if (draft) 'facts': _facts.text.trim(),
        },
      );
      if (!mounted) return;
      String? suggestion;
      for (final action in reply.actions) {
        if (action.type == 'apply_field_suggestion' &&
            (action.payload['module'] ?? 'leave') == widget.module &&
            action.payload[widget.module == 'locator'
                    ? 'locatorType'
                    : 'leaveType'] ==
                widget.leaveType &&
            action.payload['fieldKey'] == widget.fieldKey &&
            action.payload['value'] is String) {
          suggestion = action.payload['value'] as String;
        }
      }
      setState(() {
        _answer = reply.content;
        _draft = suggestion;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _answer = error is DioException && error.response?.data is Map
            ? (error.response!.data['error']?.toString() ??
                  'Field help is unavailable. Please try again.')
            : 'Field help is unavailable. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Help with ${widget.label}'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_answer.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(_answer),
            ],
            if (widget.canDraft) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _facts,
                enabled: !_busy,
                maxLines: 3,
                maxLength: 2000,
                onChanged: (_) => setState(() => _draft = null),
                decoration: const InputDecoration(
                  labelText: 'Your actual details',
                  hintText: 'Tell me what you want to say in your own words.',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'The assistant can help phrase your details. Check that the suggested sentence is accurate.',
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _ask(false),
        child: const Text('Explain / example'),
      ),
      if (widget.canDraft)
        TextButton(
          onPressed: _busy ? null : () => _ask(true),
          child: const Text('Draft a sentence'),
        ),
      if (_draft != null && !_busy)
        FilledButton(
          onPressed: () => Navigator.pop(context, _draft),
          child: const Text('Use this suggestion'),
        ),
    ],
  );
}
