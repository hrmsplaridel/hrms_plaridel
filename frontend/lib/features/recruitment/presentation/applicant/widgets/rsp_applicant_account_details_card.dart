import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Step 8 card after HR finishes creating the employee account.
/// Shows the same login details that were emailed to the applicant.
class RspApplicantAccountDetailsCard extends StatefulWidget {
  const RspApplicantAccountDetailsCard({
    super.key,
    required this.username,
    this.password,
    required this.gmailAddress,
    this.emailSentAt,
    this.onGoToLogin,
    this.onRefresh,
    this.refreshBusy = false,
  });

  final String username;
  final String? password;
  final String gmailAddress;
  final DateTime? emailSentAt;
  final VoidCallback? onGoToLogin;
  final VoidCallback? onRefresh;
  final bool refreshBusy;

  @override
  State<RspApplicantAccountDetailsCard> createState() =>
      _RspApplicantAccountDetailsCardState();
}

class _RspApplicantAccountDetailsCardState
    extends State<RspApplicantAccountDetailsCard> {
  bool _obscurePassword = true;

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final password = widget.password?.trim();
    final hasPassword = password != null && password.isNotEmpty;
    final gmail = widget.gmailAddress.trim();
    final sentAt = widget.emailSentAt;
    String sentLabel;
    if (sentAt != null) {
      final loc = MaterialLocalizations.of(context);
      sentLabel =
          'Sent to ${gmail.isNotEmpty ? gmail : 'your Gmail'} · '
          '${loc.formatFullDate(sentAt.toLocal())}';
    } else if (gmail.isNotEmpty) {
      sentLabel = 'These details were sent to $gmail.';
    } else {
      sentLabel = 'These details were sent to your Gmail.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_rounded,
            size: 36,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(height: 12),
          Text(
            'Your employee account is ready',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These are the same login details sent to your Gmail. '
            'Change your password after the first sign-in if prompted.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 18),
          _CredentialRow(
            label: 'Username',
            value: widget.username,
            onCopy: () => _copy(widget.username, 'Username'),
          ),
          const SizedBox(height: 10),
          if (hasPassword)
            _CredentialRow(
              label: 'Password',
              value: password,
              obscure: _obscurePassword,
              onToggleObscure: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              onCopy: () => _copy(password, 'Password'),
            )
          else
            _CredentialHintRow(
              label: 'Password',
              body: sentAt != null
                  ? 'Open the hire email from HR. Check inbox and spam.'
                  : 'HR will email your password to this Gmail. '
                      'Tap Refresh after you receive it.',
            ),
          const SizedBox(height: 12),
          Text(
            sentLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          if (widget.onGoToLogin != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: widget.onGoToLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                ),
                child: const Text('Go to Login'),
              ),
            ),
          ],
          if (widget.onRefresh != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: widget.refreshBusy ? null : widget.onRefresh,
              icon: widget.refreshBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                widget.refreshBusy ? 'Checking status…' : 'Refresh status',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.obscure = false,
    this.onToggleObscure,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  obscure ? '••••••••' : value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          if (onToggleObscure != null)
            IconButton(
              tooltip: obscure ? 'Show password' : 'Hide password',
              onPressed: onToggleObscure,
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          IconButton(
            tooltip: 'Copy $label',
            onPressed: onCopy,
            icon: Icon(
              Icons.copy_rounded,
              size: 18,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialHintRow extends StatelessWidget {
  const _CredentialHintRow({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
