import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/user_facing_api_error.dart';
import '../../landingpage/constants/app_theme.dart';
import 'rsp_applicant_exam_ui.dart';

/// Admin dialog: send hire congratulations + HRMS login credentials via server email.
class RspHireApplicantEmailDialog extends StatefulWidget {
  const RspHireApplicantEmailDialog({
    super.key,
    required this.applicantEmail,
    required this.applicantName,
    required this.sendHireEmail,
  });

  final String applicantEmail;
  final String applicantName;
  final Future<void> Function(String username, String password) sendHireEmail;

  @override
  State<RspHireApplicantEmailDialog> createState() =>
      _RspHireApplicantEmailDialogState();
}

class _RspHireApplicantEmailDialogState extends State<RspHireApplicantEmailDialog> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePass = true;
  bool _sending = false;

  static const _accent = RspApplicantExamUi.accent;
  static const _navy = AppTheme.primaryNavy;

  @override
  void initState() {
    super.initState();
    _userCtrl.addListener(_onCredentialsChanged);
    _passCtrl.addListener(_onCredentialsChanged);
  }

  void _onCredentialsChanged() => setState(() {});

  @override
  void dispose() {
    _userCtrl.removeListener(_onCredentialsChanged);
    _passCtrl.removeListener(_onCredentialsChanged);
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _messagePreview {
    final name = widget.applicantName.trim().isEmpty
        ? 'Applicant'
        : widget.applicantName.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final credBlock = user.isNotEmpty || pass.isNotEmpty
        ? '\n\nYour login details:\n'
            '${user.isNotEmpty ? 'Username: $user\n' : ''}'
            '${pass.isNotEmpty ? 'Password: $pass\n' : ''}'
        : '\n\nYour login details:\nUsername: …\nPassword: …\n';
    return 'Dear $name,\n\n'
        'Congratulations! We are pleased to inform you that you have passed '
        'the final interview and are hired by LGU Plaridel.$credBlock\n'
        'Please sign in to the HRMS and change your password after first login '
        'if prompted.\n\n'
        'Best regards,\n'
        'Human Resources\n'
        'LGU Plaridel';
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(ClipboardData(text: widget.applicantEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email address copied.')),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _sending = true);
    try {
      await widget.sendHireEmail(_userCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final maxW = min(mq.width - 32, 480.0);
    final maxH = mq.height - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Material(
          color: AppTheme.white,
          elevation: 16,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(applicantName: widget.applicantName),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoCard(
                          icon: Icons.alternate_email_rounded,
                          label: 'Recipient',
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  widget.applicantEmail,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy email',
                                onPressed: _copyEmail,
                                icon: Icon(
                                  Icons.copy_rounded,
                                  size: 20,
                                  color: _navy.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _MessagePreviewCard(body: _messagePreview),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Icon(Icons.key_rounded, size: 20, color: _navy),
                            const SizedBox(width: 8),
                            const Text(
                              'Login details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Included in the email body sent from the HRMS server.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _userCtrl,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          decoration: AppTheme.dashInputDecoration(
                            context,
                            labelText: 'Username',
                            hintText: 'HRMS login username',
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter the username';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          autofillHints: const [AutofillHints.password],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          decoration: AppTheme.dashInputDecoration(
                            context,
                            labelText: 'Password',
                            hintText: 'Temporary password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePass
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscurePass = !_obscurePass),
                              icon: Icon(
                                _obscurePass
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Enter the password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E6),
                            borderRadius: BorderRadius.circular(
                              RspApplicantExamUi.radiusMd,
                            ),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 22,
                                color: _accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Email is not end-to-end encrypted. Send only '
                                  'credentials you intend them to use. Ask them to '
                                  'change the password after first login.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.5,
                                    color: AppTheme.textPrimary
                                        .withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _DialogFooter(
                sending: _sending,
                onCancel: () => Navigator.of(context).pop(),
                onSend: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.applicantName});

  final String applicantName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF3E8),
            Colors.white,
            Color(0xFFF5F8FF),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0x1A1A2E66)),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RspApplicantExamUi.accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: RspApplicantExamUi.accent.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: RspApplicantExamUi.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Email applicant',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hired — login credentials go to the applicant by email.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppTheme.textSecondary.withValues(alpha: 0.95),
            ),
          ),
          if (applicantName.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      applicantName.trim(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryNavy,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryNavy),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: AppTheme.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MessagePreviewCard extends StatelessWidget {
  const _MessagePreviewCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RspApplicantExamUi.radiusMd),
        border: Border.all(
          color: RspApplicantExamUi.accent.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: RspApplicantExamUi.accent),
            Expanded(
              child: ColoredBox(
                color: RspApplicantExamUi.accent.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 18,
                            color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'MESSAGE PREVIEW',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.05,
                              color: AppTheme.textSecondary.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: AppTheme.textPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    required this.sending,
    required this.onCancel,
    required this.onSend,
  });

  final bool sending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: sending ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 20),
            label: Text(sending ? 'Sending…' : 'Send email'),
            style: FilledButton.styleFrom(
              backgroundColor: RspApplicantExamUi.accent,
              disabledBackgroundColor:
                  RspApplicantExamUi.accent.withValues(alpha: 0.45),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
