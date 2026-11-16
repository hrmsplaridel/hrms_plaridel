import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';

class SignatureConfirmation {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static bool _open = false;
  static void install() {
    ApiClient.instance.signingConfirmation = (challenge) async {
      final context = navigatorKey.currentState?.overlay?.context;
      if (context == null || _open) return null;
      _open = true;
      try {
        return await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ConfirmationDialog(challenge: challenge),
        );
      } finally {
        _open = false;
      }
    };
  }
}

class _ConfirmationDialog extends StatefulWidget {
  const _ConfirmationDialog({required this.challenge});
  final String challenge;
  @override
  State<_ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog> {
  final _password = TextEditingController();
  bool _reviewed = false, _saving = false;
  String? _error;
  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving || !_reviewed || _password.text.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/signature-security/authorize',
        data: {'challenge': widget.challenge, 'password': _password.text},
      );
      _password.clear();
      if (mounted) {
        Navigator.of(context).pop(response.data?['authorization']?.toString());
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.response?.data is Map
              ? error.response!.data['error']?.toString()
              : null;
          _error ??= 'Could not confirm signing. Please retry.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not confirm signing.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Confirm signing'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Confirm the document you reviewed before applying your signature or approval.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _reviewed,
              title: const Text(
                'I reviewed this document and authorize this action.',
              ),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _reviewed = value == true),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !_saving,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Current password'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirm(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || !_reviewed || _password.text.isEmpty
              ? null
              : _confirm,
          child: Text(_saving ? 'Confirming...' : 'Confirm'),
        ),
      ],
    ),
  );
}
