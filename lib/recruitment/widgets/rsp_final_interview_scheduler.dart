import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/recruitment_hire_prefill.dart';
import 'rsp_hire_email_dialog.dart';

/// Admin: applicants who passed the screening exam — schedule final interview,
/// record pass/fail, then open Create Account (sidebar) using the shared form.
class RspFinalInterviewScheduler extends StatefulWidget {
  const RspFinalInterviewScheduler({super.key, this.onGoToCreateAccount});

  /// Opens the admin **Create Account** screen (sidebar); parent supplies navigation.
  final VoidCallback? onGoToCreateAccount;

  @override
  State<RspFinalInterviewScheduler> createState() =>
      _RspFinalInterviewSchedulerState();
}

class _RspFinalInterviewSchedulerState
    extends State<RspFinalInterviewScheduler> {
  List<RecruitmentApplication> _applications = [];
  Map<String, RecruitmentExamResult> _examResults = {};
  String? _selectedPositionFilter;
  DateTime? _selectedAppliedDate;
  bool _loading = true;
  final Set<String> _savingIds = {};
  /// Any applicant can be collapsed to a compact, name-only row until expanded.
  final Set<String> _expandedHiredApplicantIds = {};

  static const _kSectionGap = 28.0;
  static const _kCardPadding = 24.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final apps = await RecruitmentRepo.instance.listApplications();
    final exams = await RecruitmentRepo.instance.getExamResultsByApplication();
    if (!mounted) return;
    setState(() {
      _applications = apps;
      _examResults = exams;
      _loading = false;
    });
  }

  List<RecruitmentApplication> get _passedApplicants {
    final out = <RecruitmentApplication>[];
    for (final a in _applications) {
      final ex = _examResults[a.id.toLowerCase()];
      if (ex != null && ex.passed) out.add(a);
    }
    out.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    return out;
  }

  Set<String> get _positionFilterOptions {
    final out = <String>{};
    for (final a in _passedApplicants) {
      final p = (a.positionAppliedFor ?? '').trim();
      if (p.isNotEmpty) out.add(p);
    }
    return out;
  }

  bool _isSameLocalDate(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  List<RecruitmentApplication> get _filteredPassedApplicants {
    return _passedApplicants.where((a) {
      final position = (a.positionAppliedFor ?? '').trim();
      if (_selectedPositionFilter != null &&
          _selectedPositionFilter!.isNotEmpty &&
          position != _selectedPositionFilter) {
        return false;
      }
      if (_selectedAppliedDate != null) {
        final createdAt = a.createdAt;
        if (createdAt == null ||
            !_isSameLocalDate(createdAt, _selectedAppliedDate!)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _formatDateShort(DateTime date) {
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = date.toLocal();
    return '${monthNames[d.month - 1]} ${d.day}, ${d.year}';
  }

  static bool _isRegistered(RecruitmentApplication a) {
    return a.status == 'registered' ||
        (a.hiredUserId != null && a.hiredUserId!.trim().isNotEmpty);
  }

  ({String label, IconData icon, Color fg, Color bg, Color border})
      _statusSpec(
    BuildContext context,
    RecruitmentApplication app,
  ) {
    final dark = AppTheme.dashIsDark(context);
    final registered = _isRegistered(app);
    final scheduled = app.finalInterviewAt;
    final outcome = app.finalInterviewPassed;
    final hrDone = app.hrAccountSetupDone == true;

    if (registered) {
      return (
        label: 'Hired · Account linked',
        icon: Icons.verified_rounded,
        fg: dark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
        bg: dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9),
        border: (dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
            .withValues(alpha: 0.35),
      );
    }
    if (outcome == true && hrDone) {
      return (
        label: 'Final passed · Step 8 done',
        icon: Icons.task_alt_rounded,
        fg: dark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
        bg: dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9),
        border: (dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
            .withValues(alpha: 0.35),
      );
    }
    if (outcome == true) {
      return (
        label: 'Final interview passed · Pending account',
        icon: Icons.hourglass_bottom_rounded,
        fg: dark ? const Color(0xFF90CAF9) : const Color(0xFF0D47A1),
        bg: dark ? const Color(0xFF1A2940) : const Color(0xFFE3F2FD),
        border: (dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0))
            .withValues(alpha: 0.35),
      );
    }
    if (outcome == false) {
      return (
        label: 'Final interview: Not passed',
        icon: Icons.cancel_rounded,
        fg: dark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C),
        bg: dark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE),
        border: (dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828))
            .withValues(alpha: 0.35),
      );
    }
    if (scheduled != null) {
      return (
        label: 'Final interview scheduled',
        icon: Icons.event_available_rounded,
        fg: dark ? const Color(0xFFFFB74D) : const Color(0xFF7A3E00),
        bg: dark ? const Color(0xFF3A2E1A) : const Color(0xFFFFF3E0),
        border: (dark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00))
            .withValues(alpha: 0.35),
      );
    }
    return (
      label: 'Waiting for final interview schedule',
      icon: Icons.schedule_rounded,
      fg: dark
          ? const Color(0xFFB0BEC5)
          : AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.95),
      bg: dark ? const Color(0xFF2A3140) : const Color(0xFFF5F7FA),
      border: dark
          ? const Color(0xFF4A5568)
          : Colors.black.withValues(alpha: 0.08),
    );
  }

  Widget _statusBadge(
    RecruitmentApplication app, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    double fontSize = 12,
  }) {
    final s = _statusSpec(context, app);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 16, color: s.fg),
          const SizedBox(width: 8),
          Text(
            s.label,
            style: TextStyle(
              fontFamily: 'NotoSans',
              color: s.fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSchedule(DateTime d, BuildContext context) {
    final local = d.toLocal();
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatFullDate(local);
    final t = TimeOfDay.fromDateTime(local);
    return '$dateStr · ${t.format(context)}';
  }

  Future<void> _withSaveLock(
    String applicationId,
    Future<void> Function() fn,
  ) async {
    setState(() => _savingIds.add(applicationId));
    try {
      await fn();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingIds.remove(applicationId));
    }
  }

  Future<void> _pickDateTime(RecruitmentApplication app) async {
    final now = DateTime.now();
    final initial =
        app.finalInterviewAt?.toLocal() ?? now.add(const Duration(days: 7));
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (day == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateFinalInterviewAt(app.id, dt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Final interview date saved.')),
        );
      }
    });
  }

  Future<void> _clearSchedule(RecruitmentApplication app) async {
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateFinalInterviewAt(app.id, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interview schedule cleared.')),
        );
      }
    });
  }

  Future<void> _setOutcome(RecruitmentApplication app, bool? passed) async {
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateFinalInterviewPassed(app.id, passed);
      if (mounted) {
        final msg = passed == null
            ? 'Outcome cleared (pending).'
            : passed
            ? 'Marked as passed final interview.'
            : 'Marked as did not pass final interview.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
  }

  void _goToCreateAccountFor(RecruitmentApplication app) {
    context.read<RecruitmentHirePrefill>().arm(
      applicationId: app.id,
      email: app.email,
      fullName: app.fullName,
      phone: app.phone,
    );
    widget.onGoToCreateAccount?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create Account is open in the sidebar. The form is prefilled; after you save, this applicant is linked automatically.',
          ),
        ),
      );
    }
  }

  /// Shows a short form (username + password), then opens the admin’s mail app
  /// with **To:** set to the applicant’s email.
  Future<void> _openHireEmailForm(RecruitmentApplication app) async {
    final to = app.email.trim();
    if (to.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This applicant has no email on file.')),
      );
      return;
    }
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RspHireApplicantEmailDialog(
        applicantEmail: to,
        applicantName: app.fullName.trim().isEmpty
            ? 'Applicant'
            : app.fullName.trim(),
        sendHireEmail: (username, password) => RecruitmentRepo.instance
            .sendHireCredentialEmail(app.id, username, password),
      ),
    );
    if (sent == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email sent to the applicant.')),
      );
    }
  }

  Future<void> _setHrAccountMonitoring(
    RecruitmentApplication app,
    bool done,
  ) async {
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateHrAccountSetupMonitoring(
        app.id,
        done,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              done
                  ? 'Step 8 monitoring: Done creating account — applicants see this after they refresh.'
                  : 'Step 8 monitoring: Not yet — applicants see waiting until you choose Done.',
            ),
          ),
        );
      }
    });
  }

  /// Compact status strip (left accent) instead of a full-width loud banner.
  Widget _outcomeStatusStrip(BuildContext context, bool? passed) {
    final dark = AppTheme.dashIsDark(context);
    late Color accent;
    late Color bg;
    late Color fg;
    late IconData icon;
    late String headline;
    late String detail;
    switch (passed) {
      case true:
        accent = const Color(0xFF2E7D32);
        bg = (dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9))
            .withValues(alpha: dark ? 1 : 0.55);
        fg = dark ? const Color(0xFF81C784) : const Color(0xFF1B5E20);
        icon = Icons.check_circle_outline_rounded;
        headline = 'Passed';
        detail =
            'You can create their employee account from the sidebar when ready.';
        break;
      case false:
        accent = const Color(0xFFC62828);
        bg = (dark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE))
            .withValues(alpha: dark ? 1 : 0.5);
        fg = dark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C);
        icon = Icons.cancel_outlined;
        headline = 'Not passed';
        detail = 'No employee account is created from this hiring flow.';
        break;
      default:
        accent = dark
            ? const Color(0xFF78909C)
            : AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.45);
        bg = dark
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.offWhite;
        fg = AppTheme.dashTextSecondaryOf(context);
        icon = Icons.hourglass_empty_rounded;
        headline = 'Pending';
        detail = 'Record the result after the in-person interview.';
    }
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: fg, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: fg,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.dashTextPrimaryOf(context).withValues(
                                alpha: 0.82,
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
          ],
        ),
      ),
    );
  }

  List<Widget> _outcomeActions(
    RecruitmentApplication app,
    bool? outcome,
    bool registered,
    bool busy,
  ) {
    final navy = AppTheme.primaryNavy;
    if (registered) return [];
    if (outcome == null) {
      return [
        FilledButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, true),
          icon: const Icon(Icons.check_rounded, size: 20),
          label: const Text('Mark passed'),
          style: FilledButton.styleFrom(
            backgroundColor: navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: busy ? null : () => _setOutcome(app, false),
          icon: const Icon(Icons.close_rounded, size: 20),
          label: const Text('Mark not passed'),
          style: FilledButton.styleFrom(
            foregroundColor: navy,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ];
    }
    if (outcome == true) {
      return [
        TextButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, false),
          icon: Icon(Icons.swap_horiz_rounded, size: 20, color: navy),
          label: Text(
            'Change to not passed',
            style: TextStyle(color: navy, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, null),
          icon: Icon(
            Icons.restart_alt_rounded,
            size: 20,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          label: Text(
            'Clear and set pending',
            style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
          ),
        ),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: busy ? null : () => _setOutcome(app, true),
        icon: const Icon(Icons.check_rounded, size: 20),
        label: const Text('Mark passed instead'),
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      TextButton.icon(
        onPressed: busy ? null : () => _setOutcome(app, null),
        icon: Icon(
          Icons.restart_alt_rounded,
          size: 20,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
        label: Text(
          'Clear and set pending',
          style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
        ),
      ),
    ];
  }

  Widget _accountSetupStep({
    required RecruitmentApplication app,
    required bool busy,
    required bool canNavigate,
    required bool accountLinked,
  }) {
    final navy = AppTheme.primaryNavy;
    final monitoringDone = app.hrAccountSetupDone;
    final emailSent = app.hireCredentialsEmailSent;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 560;
        final openBtn = FilledButton.icon(
          onPressed: !canNavigate || busy || accountLinked
              ? null
              : () => _goToCreateAccountFor(app),
          icon: Icon(
            accountLinked ? Icons.link_rounded : Icons.open_in_new_rounded,
            size: 20,
          ),
          label: Text(accountLinked ? 'Account linked' : 'Open Create Account'),
          style: FilledButton.styleFrom(
            backgroundColor: navy,
            disabledBackgroundColor: navy.withValues(alpha: 0.25),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
        );
        final emailBtn = OutlinedButton.icon(
          onPressed: busy || emailSent ? null : () => _openHireEmailForm(app),
          icon: Icon(
            emailSent
                ? Icons.mark_email_read_rounded
                : Icons.mark_email_read_outlined,
            size: 20,
          ),
          label: Text(emailSent ? 'Email sent' : 'Email applicant'),
          style: OutlinedButton.styleFrom(
            foregroundColor: emailSent
                ? AppTheme.dashTextSecondaryOf(context)
                : navy,
            disabledForegroundColor: AppTheme.dashTextSecondaryOf(context),
            side: BorderSide(
              color: emailSent
                  ? AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.35)
                  : navy.withValues(alpha: 0.55),
            ),
            backgroundColor:
                emailSent ? AppTheme.offWhite.withValues(alpha: 0.6) : null,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accountLinked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 22,
                      color: Colors.green.shade800,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Employee account is linked to this application.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (emailSent) ...[
              Text(
                'Credentials email was sent${app.hireCredentialsEmailSentAt != null ? ' on ${_formatSchedule(app.hireCredentialsEmailSentAt!, context)}' : ''}. The button stays disabled so HR can see this step is complete.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Email applicant sends from the HRMS server to ${app.email.trim().isEmpty ? '—' : app.email.trim()} (congratulations + hired + login details). SMTP must be set in the API .env.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.95),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Open Create Account in the admin sidebar (below DocuTracker) to link this user. Use Email applicant to enter login details; the server emails them automatically.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
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
              Text(
                'Create Account opens in the sidebar (prefilled). Email applicant sends username/password to the address above via the server.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: emailBtn),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: openBtn),
            ],
            const SizedBox(height: 22),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 18),
            Text(
              'What applicants see (Step 8)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose the message shown after they refresh their application status. This is only a label for the applicant — it does not create the account.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 14),
            IgnorePointer(
              ignoring: busy,
              child: Opacity(
                opacity: busy ? 0.45 : 1,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Not yet'),
                      icon: Icon(Icons.schedule_rounded, size: 18),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Done'),
                      icon: Icon(Icons.check_rounded, size: 18),
                    ),
                  ],
                  selected: {monitoringDone ? 1 : 0},
                  onSelectionChanged: (s) {
                    if (busy) return;
                    final v = s.first;
                    final wantDone = v == 1;
                    if (wantDone == monitoringDone) return;
                    _setHrAccountMonitoring(app, wantDone);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              monitoringDone
                  ? 'Applicants currently see: account setup complete.'
                  : 'Applicants currently see: still setting up account.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.92),
              ),
            ),
          ],
        );
      },
    );
  }

  BoxDecoration _shellCardDecoration(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    return BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: hairline),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primaryNavy.withValues(alpha: 0.06),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _shellTopAccent() {
    return Container(
      height: 4,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
        ),
      ),
    );
  }

  Widget _applicantInitials(BuildContext context, String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    String initials = '';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials += parts.first[0].toUpperCase();
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      initials += parts.last[0].toUpperCase();
    }
    if (initials.isEmpty) initials = '?';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavy.withValues(alpha: 0.18),
            AppTheme.primaryNavyLight.withValues(alpha: 0.1),
          ],
        ),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.22),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'NotoSans',
          color: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final accentNavy = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;
    final filteredPassedApplicants = _filteredPassedApplicants;

    final refreshBtn = FilledButton.icon(
      onPressed: _loading ? null : _load,
      icon: const Icon(Icons.refresh_rounded, size: 20),
      label: const Text('Refresh list'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
    final dateFilterBtn = OutlinedButton.icon(
      onPressed: _loading
          ? null
          : () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedAppliedDate ?? now,
                firstDate: DateTime(now.year - 10),
                lastDate: DateTime(now.year + 1),
                helpText: 'Filter by applied date',
              );
              if (picked == null || !mounted) return;
              setState(() => _selectedAppliedDate = picked);
            },
      icon: const Icon(Icons.event_outlined, size: 18),
      label: Text(
        _selectedAppliedDate == null
            ? 'Applied date'
            : _formatDateShort(_selectedAppliedDate!),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: hairline),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.14),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                Icons.event_available_outlined,
                size: 26,
                color: AppTheme.dashIsDark(context)
                    ? AppTheme.primaryNavyLight
                    : AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Final interview (passed exam)',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applicants listed here already passed the screening exam. Schedule the in-person interview, record the result, then open Create Account when they pass.',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            refreshBtn,
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedPositionFilter,
                decoration: InputDecoration(
                  labelText: 'Position',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline),
                  ),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All positions'),
                  ),
                  ...(_positionFilterOptions.toList()
                        ..sort(
                          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                        ))
                      .map(
                        (p) => DropdownMenuItem<String>(value: p, child: Text(p)),
                      ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() => _selectedPositionFilter = value);
                      },
              ),
            ),
            dateFilterBtn,
            TextButton.icon(
              onPressed: _loading
                  ? null
                  : () => setState(() => _selectedAppliedDate = DateTime.now()),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Today'),
            ),
            TextButton.icon(
              onPressed: (_loading ||
                      (_selectedPositionFilter == null &&
                          _selectedAppliedDate == null))
                  ? null
                  : () {
                      setState(() {
                        _selectedPositionFilter = null;
                        _selectedAppliedDate = null;
                      });
                    },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear filters'),
            ),
            Text(
              '${filteredPassedApplicants.length} shown',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_passedApplicants.isEmpty)
          Container(
            width: double.infinity,
            decoration: _shellCardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _shellTopAccent(),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 40,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No applicants have passed the exam yet. When an applicant completes the screening exam with a passing score, they will show up here automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (filteredPassedApplicants.isEmpty)
          Container(
            width: double.infinity,
            decoration: _shellCardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _shellTopAccent(),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.filter_alt_off_rounded,
                        size: 40,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No passed applicants match the selected filters. Try another position or date.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredPassedApplicants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 18),
            itemBuilder: (context, i) {
              final app = filteredPassedApplicants[i];
              final exam = _examResults[app.id.toLowerCase()];
              final busy = _savingIds.contains(app.id);
              final registered = _isRegistered(app);
              final scheduled = app.finalInterviewAt;
              final outcome = app.finalInterviewPassed;
              final canNavigate = widget.onGoToCreateAccount != null;
              final actions = _outcomeActions(app, outcome, registered, busy);
              final showStep3 = outcome == true;
              final step1Summary = scheduled == null
                  ? 'No date scheduled'
                  : _formatSchedule(scheduled, context);
              final step2Summary = outcome == null
                  ? 'Pending — record result'
                  : (outcome == true ? 'Passed' : 'Not passed');
              final step3Summary = app.hireCredentialsEmailSent
                  ? (registered
                      ? 'Account linked · credentials email sent'
                      : 'Credentials email sent')
                  : (registered
                      ? 'Account linked · send credentials email'
                      : 'Create account & email login details');
              final expandStep1 = scheduled == null;
              final expandStep2 = !expandStep1 && outcome == null;
              final expandStep3 = showStep3 && !expandStep1 && !expandStep2;
              final useMinimalApplicantRow =
                  !_expandedHiredApplicantIds.contains(app.id);

              if (useMinimalApplicantRow) {
                return Container(
                  decoration: _shellCardDecoration(context),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _shellTopAccent(),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(
                            () => _expandedHiredApplicantIds.add(app.id),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                _applicantInitials(context, app.fullName),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        app.fullName,
                                        style: TextStyle(
                                          fontFamily: 'NotoSans',
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                          letterSpacing: -0.2,
                                          color: AppTheme.dashTextPrimaryOf(
                                            context,
                                          ),
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _statusBadge(
                                        app,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        fontSize: 11,
                                      ),
                                    ],
                                  ),
                                ),
                                if (exam != null) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${exam.scorePercent.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontFamily: 'NotoSans',
                                        color: accentNavy,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 10),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: muted,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: hairline),
                                  ),
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    color: AppTheme.dashTextSecondaryOf(
                                      context,
                                    ),
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                decoration: _shellCardDecoration(context),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _shellTopAccent(),
                    Padding(
                      padding: const EdgeInsets.all(_kCardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'APPLICANT',
                                  style: TextStyle(
                                    fontFamily: 'NotoSans',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.65,
                                    color: AppTheme.dashTextSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => setState(
                                  () => _expandedHiredApplicantIds.remove(
                                    app.id,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.unfold_less_rounded,
                                  size: 20,
                                ),
                                label: const Text('Show less'),
                                style: TextButton.styleFrom(
                                  foregroundColor: accentNavy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: muted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: hairline),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _applicantInitials(context, app.fullName),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        app.fullName,
                                        style: TextStyle(
                                          fontFamily: 'NotoSans',
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                          letterSpacing: -0.25,
                                          color: AppTheme.dashTextPrimaryOf(
                                            context,
                                          ),
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        app.email,
                                        style: TextStyle(
                                          fontFamily: 'NotoSans',
                                          color: AppTheme.dashTextSecondaryOf(
                                            context,
                                          ),
                                          fontSize: 14,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (app.positionAppliedFor != null &&
                                          app.positionAppliedFor!
                                              .trim()
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Position: ${app.positionAppliedFor!.trim()}',
                                          style: TextStyle(
                                            fontFamily: 'NotoSans',
                                            color: AppTheme.dashIsDark(context)
                                                ? AppTheme.primaryNavyLight
                                                : AppTheme.primaryNavy
                                                    .withValues(alpha: 0.95),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            if (exam != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.dashPanelOf(
                                                    context,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    999,
                                                  ),
                                                  border: Border.all(
                                                    color: AppTheme.primaryNavy
                                                        .withValues(
                                                      alpha: 0.22,
                                                    ),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppTheme
                                                          .primaryNavy
                                                          .withValues(
                                                        alpha: 0.08,
                                                      ),
                                                      blurRadius: 8,
                                                      offset:
                                                          const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'Exam: ${exam.scorePercent.toStringAsFixed(0)}%',
                                                  style: TextStyle(
                                                    fontFamily: 'NotoSans',
                                                    color: accentNavy.withValues(
                                                      alpha: 0.92,
                                                    ),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            _statusBadge(app),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (registered) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: panel,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.28,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryNavy
                                              .withValues(alpha: 0.1),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.badge_rounded,
                                          size: 20,
                                          color: accentNavy,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Account ready',
                                          style: TextStyle(
                                            fontFamily: 'NotoSans',
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                            color: accentNavy,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Divider(height: 1, color: hairline),
                          const SizedBox(height: 18),
                          Text(
                            'WORKFLOW',
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.65,
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _CollapsibleWorkflowStep(
                            key: ValueKey('${app.id}-wf1'),
                            number: 1,
                            title: 'Interview appointment',
                            subtitle:
                                'Applicants see this date when they continue their application with the same email.',
                            collapsedSummary: step1Summary,
                            initiallyExpanded: expandStep1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: panel,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: hairline),
                                  ),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          width: 4,
                                          margin: const EdgeInsets.only(
                                            left: 12,
                                            top: 12,
                                            bottom: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accentNavy,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              14,
                                              16,
                                              14,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.event_note_rounded,
                                                  size: 22,
                                                  color: accentNavy.withValues(
                                                    alpha: 0.88,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        scheduled == null
                                                            ? 'No date set'
                                                            : _formatSchedule(
                                                                scheduled,
                                                                context,
                                                              ),
                                                        style: TextStyle(
                                                          fontFamily:
                                                              'NotoSans',
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              scheduled == null
                                                              ? AppTheme
                                                                    .dashTextSecondaryOf(
                                                                  context,
                                                                )
                                                              : AppTheme
                                                                    .dashIsDark(
                                                                  context,
                                                                )
                                                                ? AppTheme
                                                                    .primaryNavyLight
                                                                : AppTheme
                                                                    .primaryNavy,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                      if (scheduled == null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 4,
                                                              ),
                                                          child: Text(
                                                            'Pick a date and time for the in-person final interview.',
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  'NotoSans',
                                                              fontSize: 12,
                                                              color: AppTheme
                                                                  .dashTextSecondaryOf(
                                                                context,
                                                              ),
                                                              height: 1.4,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
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
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => _pickDateTime(app),
                                      icon: const Icon(
                                        Icons.edit_calendar_rounded,
                                      ),
                                      label: Text(
                                        scheduled == null
                                            ? 'Set date & time'
                                            : 'Change date & time',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppTheme.primaryNavy,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: busy || scheduled == null
                                          ? null
                                          : () => _clearSchedule(app),
                                      icon: Icon(
                                        Icons.event_busy_rounded,
                                        size: 20,
                                        color: AppTheme.dashTextSecondaryOf(context),
                                      ),
                                      label: Text(
                                        'Clear',
                                        style: TextStyle(
                                          color: AppTheme.dashTextSecondaryOf(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: _kSectionGap + 4),
                          _CollapsibleWorkflowStep(
                            key: ValueKey('${app.id}-wf2'),
                            number: 2,
                            title: 'Final interview result',
                            subtitle:
                                'After the interview, record whether the applicant passed.',
                            collapsedSummary: step2Summary,
                            initiallyExpanded: expandStep2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _outcomeStatusStrip(context, outcome),
                                if (actions.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: actions,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (outcome == true) ...[
                            SizedBox(height: _kSectionGap + 4),
                            _CollapsibleWorkflowStep(
                              key: ValueKey('${app.id}-wf3'),
                              number: 3,
                              title: 'Employee account',
                              subtitle: registered
                                  ? 'Account linked. Send or confirm credentials email and Step 8 applicant message.'
                                  : 'Create their login from the sidebar, then email credentials.',
                              collapsedSummary: step3Summary,
                              initiallyExpanded: expandStep3,
                              child: _accountSetupStep(
                                app: app,
                                busy: busy,
                                canNavigate: canNavigate,
                                accountLinked: registered,
                              ),
                            ),
                            if (!canNavigate)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'Create Account shortcut is not available here. Use the full admin sidebar.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.dashTextSecondaryOf(context),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// One workflow row: tap header to expand/collapse; summary visible when collapsed.
class _CollapsibleWorkflowStep extends StatefulWidget {
  const _CollapsibleWorkflowStep({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.collapsedSummary,
    this.initiallyExpanded = false,
  });

  final int number;
  final String title;
  final String subtitle;
  final Widget child;
  final String collapsedSummary;
  final bool initiallyExpanded;

  @override
  State<_CollapsibleWorkflowStep> createState() =>
      _CollapsibleWorkflowStepState();
}

class _CollapsibleWorkflowStepState extends State<_CollapsibleWorkflowStep> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final summaryStyle = TextStyle(
      fontFamily: 'NotoSans',
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.92),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded
              ? AppTheme.primaryNavy.withValues(alpha: 0.22)
              : hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primaryNavyLight, AppTheme.primaryNavy],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${widget.number}',
              style: const TextStyle(
                fontFamily: 'NotoSans',
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: TextStyle(
                                    fontFamily: 'NotoSans',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.dashTextPrimaryOf(context),
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                  ),
                                ),
                                if (!_expanded) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.collapsedSummary,
                                    style: summaryStyle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.dashMutedSurfaceOf(context),
                              shape: BoxShape.circle,
                              border: Border.all(color: hairline),
                            ),
                            child: Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: AppTheme.dashTextSecondaryOf(context),
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 13,
                              height: 1.5,
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          widget.child,
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
