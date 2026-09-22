import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_hire_email_dialog.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_final_requirements_ui.dart';

/// HR panel: create employee account, email credentials, and Step 8 applicant message.
class RspEmployeeAccountSetupPanel extends StatefulWidget {
  const RspEmployeeAccountSetupPanel({
    super.key,
    required this.app,
    required this.onReload,
    this.onGoToCreateAccount,
    this.busy = false,
    this.onBusyChanged,
    this.enabled = true,
    this.compact = false,
    this.showApplicantStatus = true,
  });

  final RecruitmentApplication app;
  final Future<void> Function() onReload;
  final VoidCallback? onGoToCreateAccount;
  final bool busy;
  final ValueChanged<bool>? onBusyChanged;

  /// When false, all actions are disabled until orientation is marked attended.
  final bool enabled;

  /// Tighter spacing for Final Requirements 3-column layout.
  final bool compact;

  /// When false, Step 8 is rendered by the parent (full-width footer).
  final bool showApplicantStatus;

  @override
  State<RspEmployeeAccountSetupPanel> createState() =>
      _RspEmployeeAccountSetupPanelState();
}

class _RspEmployeeAccountSetupPanelState
    extends State<RspEmployeeAccountSetupPanel> {
  bool get _accountLinked =>
      widget.app.status == 'registered' ||
      (widget.app.hiredUserId != null &&
          widget.app.hiredUserId!.trim().isNotEmpty);

  bool get _canNavigate => widget.onGoToCreateAccount != null;

  Future<void> _withBusy(Future<void> Function() fn) async {
    widget.onBusyChanged?.call(true);
    try {
      await fn();
      await widget.onReload();
    } finally {
      widget.onBusyChanged?.call(false);
    }
  }

  void _goToCreateAccount() {
    final app = widget.app;
    context.read<RecruitmentHirePrefill>().arm(
      applicationId: app.id,
      email: app.email,
      fullName: app.fullName,
      firstName: app.firstName,
      middleName: app.middleName,
      lastName: app.lastName,
      suffix: app.suffix,
      phone: app.phone,
      sex: app.sex,
      address: app.address,
    );
    widget.onGoToCreateAccount?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create Account opened. After you save, you will return here to email credentials.',
          ),
        ),
      );
    }
  }

  Future<void> _openHireEmailForm() async {
    if (!_accountLinked) return;
    final app = widget.app;
    final to = app.email.trim();
    if (to.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This applicant has no email on file.')),
      );
      return;
    }

    final hire = context.read<RecruitmentHirePrefill>();
    final stored = hire.credentialsFor(app.id);
    var loginUsername = stored?.loginEmail ?? to;
    final loginPassword = resolveHireLoginPassword(
      storedPassword: stored?.password,
      persistedPassword: app.hireLoginPassword,
    );
    if ((stored?.loginEmail ?? '').trim().isEmpty) {
      final persistedUser = app.hireLoginUsername?.trim();
      if (persistedUser != null && persistedUser.isNotEmpty) {
        loginUsername = persistedUser;
      }
    }

    if (stored == null &&
        _accountLinked &&
        app.hiredUserId != null &&
        app.hiredUserId!.trim().isNotEmpty) {
      try {
        final res = await ApiClient.instance.get<Map<String, dynamic>>(
          '/api/employees/${app.hiredUserId!.trim()}',
        );
        final linkedEmail = res.data?['email']?.toString().trim();
        if (linkedEmail != null && linkedEmail.isNotEmpty) {
          loginUsername = linkedEmail;
        }
        } catch (_) {
        // Fall back to applicant email and the generated Create Account password.
      }
    }

    hire.recordCreatedCredentials(
      applicationId: app.id,
      loginEmail: loginUsername,
      password: loginPassword,
    );

    if (!mounted) return;
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RspHireApplicantEmailDialog(
        applicantEmail: to,
        applicantName: app.fullName.trim().isEmpty
            ? 'Applicant'
            : app.fullName.trim(),
        initialUsername: loginUsername,
        initialPassword: loginPassword,
        sendHireEmail: (username, password) => RecruitmentRepo.instance
            .sendHireCredentialEmail(app.id, username, password),
      ),
    );
    if (sent == true && mounted) {
      await widget.onReload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email sent to the applicant.')),
      );
    }
  }

  Future<void> _setHrAccountMonitoring(bool done) async {
    await _withBusy(() async {
      await RecruitmentRepo.instance.updateHrAccountSetupMonitoring(
        widget.app.id,
        done,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              done
                  ? 'Applicants will see: account setup complete.'
                  : 'Applicants will see: still setting up account.',
            ),
          ),
        );
      }
    });
  }

  String _formatSchedule(DateTime d, BuildContext context) {
    final local = d.toLocal();
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatFullDate(local);
    final t = TimeOfDay.fromDateTime(local);
    return '$dateStr · ${t.format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final busy = widget.busy;
    final locked = !widget.enabled;
    final compact = widget.compact;
    final navy = AppTheme.primaryNavy;
    final monitoringDone = app.hrAccountSetupDone;
    final emailSent = app.hireCredentialsEmailSent;
    final accountLinked = _accountLinked;
    final btnPad = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 14);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = !compact && c.maxWidth >= 560;
        final openBtn = FilledButton.icon(
          onPressed: locked || !_canNavigate || busy || accountLinked
              ? null
              : _goToCreateAccount,
          icon: Icon(
            accountLinked ? Icons.link_rounded : Icons.open_in_new_rounded,
            size: compact ? 16 : 20,
          ),
          label: Text(accountLinked ? 'Account linked' : 'Open Create Account'),
          style: FilledButton.styleFrom(
            backgroundColor: navy,
            disabledBackgroundColor: navy.withValues(alpha: 0.25),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
            padding: btnPad,
            visualDensity: compact ? VisualDensity.compact : null,
          ),
        );
        final canSendEmail = !locked && !busy && accountLinked;
        final emailLooksLocked = !accountLinked && !emailSent;
        final emailMuted = emailLooksLocked;
        final emailBtn = compact && accountLinked
            ? FilledButton.icon(
                onPressed: canSendEmail ? _openHireEmailForm : null,
                icon: Icon(
                  emailSent
                      ? Icons.mark_email_read_rounded
                      : Icons.mark_email_read_outlined,
                  size: 16,
                ),
                label: Text(emailSent ? 'Send again' : 'Email applicant'),
                style: FilledButton.styleFrom(
                  backgroundColor: navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: navy.withValues(alpha: 0.25),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                  padding: btnPad,
                  visualDensity: VisualDensity.compact,
                ),
              )
            : OutlinedButton.icon(
                onPressed: canSendEmail ? _openHireEmailForm : null,
                icon: Icon(
                  emailSent
                      ? Icons.mark_email_read_rounded
                      : Icons.mark_email_read_outlined,
                  size: compact ? 16 : 20,
                ),
                label: Text(emailSent ? 'Send again' : 'Email applicant'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: emailMuted
                      ? AppTheme.dashTextSecondaryOf(context)
                      : navy,
                  disabledForegroundColor: AppTheme.dashTextSecondaryOf(
                    context,
                  ),
                  side: BorderSide(
                    color: emailMuted
                        ? AppTheme.dashTextSecondaryOf(
                            context,
                          ).withValues(alpha: 0.35)
                        : navy.withValues(alpha: 0.55),
                  ),
                  backgroundColor: emailMuted
                      ? AppTheme.offWhite.withValues(alpha: 0.6)
                      : null,
                  padding: btnPad,
                  visualDensity: compact ? VisualDensity.compact : null,
                ),
              );
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (locked) ...[
              Text(
                app.orientationAttended == false
                    ? 'Unavailable — applicant did not attend orientation.'
                    : 'Mark orientation as attended in Step 2 first.',
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
            ],
            if (accountLinked) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 8 : 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(compact ? 8 : 12),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: compact ? 18 : 22,
                      color: Colors.green.shade800,
                    ),
                    SizedBox(width: compact ? 8 : 10),
                    Expanded(
                      child: Text(
                        compact
                            ? 'Account Linked'
                            : 'Employee account is linked to this application.',
                        style: TextStyle(
                          fontSize: compact ? 12.5 : 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade900,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
            ],
            if (compact) ...[
              if (app.email.trim().isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.mail_outline_rounded,
                      size: 14,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        app.email.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              if (emailSent) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Last credentials email${app.hireCredentialsEmailSentAt != null ? ': ${_formatCompactStamp(app.hireCredentialsEmailSentAt!, context)}' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(child: emailBtn),
                  const SizedBox(width: 6),
                  Expanded(child: openBtn),
                ],
              ),
            ] else ...[
              if (emailSent) ...[
                Text(
                  'Last credentials email${app.hireCredentialsEmailSentAt != null ? ' · ${_formatSchedule(app.hireCredentialsEmailSentAt!, context)}' : ''}. You can send again with the current temporary password.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        accountLinked
                            ? 'Account is ready. Email login details to ${app.email.trim().isEmpty ? 'the applicant' : app.email.trim()}.'
                            : 'Create the employee account first. Email applicant stays gray until the account is linked.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      children: [emailBtn, openBtn],
                    ),
                  ],
                )
              else ...[
                if (!accountLinked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Create the employee account first. Email applicant stays gray until the account is linked.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ),
                SizedBox(width: double.infinity, child: emailBtn),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: openBtn),
              ],
            ],
            if (!_canNavigate) ...[
              SizedBox(height: compact ? 6 : 8),
              Text(
                'Use the admin sidebar to open Create Account.',
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
            if (widget.showApplicantStatus) ...[
              SizedBox(height: compact ? 12 : 22),
              Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
              SizedBox(height: compact ? 10 : 18),
              Text(
                'Applicant status (Step 8)',
                style: TextStyle(
                  fontSize: compact ? 12.5 : 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              IgnorePointer(
                ignoring: busy || locked,
                child: Opacity(
                  opacity: busy || locked ? 0.45 : 1,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        label: Text('Not yet'),
                        icon: Icon(Icons.schedule_rounded, size: 16),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text('Done'),
                        icon: Icon(Icons.check_rounded, size: 16),
                      ),
                    ],
                    selected: {monitoringDone ? 1 : 0},
                    onSelectionChanged: (s) {
                      if (busy || locked) return;
                      final v = s.first;
                      final wantDone = v == 1;
                      if (wantDone == monitoringDone) return;
                      _setHrAccountMonitoring(wantDone);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStateProperty.all(
                        EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 12,
                          vertical: compact ? 8 : 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                monitoringDone
                    ? 'Shown to applicant: account setup complete.'
                    : 'Shown to applicant: still setting up account.',
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ],
        );

        if (!locked) return content;

        return IgnorePointer(child: Opacity(opacity: 0.45, child: content));
      },
    );
  }

  String _formatCompactStamp(DateTime d, BuildContext context) {
    final local = d.toLocal();
    return '${RspFinalReqUi.formatDateShort(local)} · ${TimeOfDay.fromDateTime(local).format(context)}';
  }
}
