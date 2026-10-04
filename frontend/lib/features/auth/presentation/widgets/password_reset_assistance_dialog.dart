import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';

class PasswordResetAssistanceDialog extends StatefulWidget {
  const PasswordResetAssistanceDialog({
    super.key,
    required this.initialEmail,
    this.submit,
  });
  final String initialEmail;
  final Future<void> Function(String email)? submit;
  @override
  State<PasswordResetAssistanceDialog> createState() =>
      _PasswordResetAssistanceDialogState();
}

class _PasswordResetAssistanceDialogState
    extends State<PasswordResetAssistanceDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _submitted = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid registered email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.submit != null) {
        await widget.submit!(email);
      } else {
        await ApiClient.instance.post(
          '/auth/password-reset-assistance',
          data: {'email': email},
        );
      }
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to submit the request. Check your connection or wait a few minutes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Password reset assistance'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use this when you cannot complete the SMS reset. An administrator must verify your request before sending a code to your registered email. If you cannot access that email, contact your system administrator for account recovery.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              enabled: !_busy && !_submitted,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Registered email'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_submitted)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'If this is an eligible account, your assistance request has been recorded. Contact your system administrator for verification. After approval, check your registered email. Return to Forgot Password and choose Enter a reset code when it arrives.',
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (_submitted)
        FilledButton(
          onPressed: () => Navigator.pop(context, _email.text.trim()),
          child: const Text('Enter a reset code'),
        )
      else
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Submit request'),
        ),
    ],
  );
}
