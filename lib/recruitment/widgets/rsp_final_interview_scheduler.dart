import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/recruitment_hire_prefill.dart';

/// Admin: applicants who passed the screening exam — schedule final interview,
/// record pass/fail, then open Create Account (sidebar) using the shared form.
class RspFinalInterviewScheduler extends StatefulWidget {
  const RspFinalInterviewScheduler({super.key, this.onGoToCreateAccount});

  /// Opens admin sidebar tab Create Account (index 5, below DocuTracker).
  final VoidCallback? onGoToCreateAccount;

  @override
  State<RspFinalInterviewScheduler> createState() =>
      _RspFinalInterviewSchedulerState();
}

class _RspFinalInterviewSchedulerState
    extends State<RspFinalInterviewScheduler> {
  List<RecruitmentApplication> _applications = [];
  Map<String, RecruitmentExamResult> _examResults = {};
  bool _loading = true;
  final Set<String> _savingIds = {};

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

  static bool _isRegistered(RecruitmentApplication a) {
    return a.status == 'registered' ||
        (a.hiredUserId != null && a.hiredUserId!.trim().isNotEmpty);
  }

  String _formatSchedule(DateTime d, BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatFullDate(d);
    final t = TimeOfDay.fromDateTime(d);
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
    final initial = app.finalInterviewAt ?? now.add(const Duration(days: 7));
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
        const SnackBar(
          content: Text('This applicant has no email on file.'),
        ),
      );
      return;
    }
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HireApplicantEmailDialog(
        applicantEmail: to,
        applicantName: app.fullName.trim().isEmpty
            ? 'Applicant'
            : app.fullName.trim(),
        sendHireEmail: (username, password) =>
            RecruitmentRepo.instance.sendHireCredentialEmail(
          app.id,
          username,
          password,
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email sent to the applicant.')),
      );
    }
  }

  Future<void> _setHrAccountMonitoring(RecruitmentApplication app, bool done) async {
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateHrAccountSetupMonitoring(app.id, done);
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
  Widget _outcomeStatusStrip(bool? passed) {
    late Color accent;
    late Color bg;
    late Color fg;
    late IconData icon;
    late String headline;
    late String detail;
    switch (passed) {
      case true:
        accent = const Color(0xFF2E7D32);
        bg = const Color(0xFFE8F5E9).withValues(alpha: 0.55);
        fg = const Color(0xFF1B5E20);
        icon = Icons.check_circle_outline_rounded;
        headline = 'Passed';
        detail =
            'You can create their employee account from the sidebar when ready.';
        break;
      case false:
        accent = const Color(0xFFC62828);
        bg = const Color(0xFFFFEBEE).withValues(alpha: 0.5);
        fg = const Color(0xFFB71C1C);
        icon = Icons.cancel_outlined;
        headline = 'Not passed';
        detail = 'No employee account is created from this hiring flow.';
        break;
      default:
        accent = AppTheme.textSecondary.withValues(alpha: 0.45);
        bg = AppTheme.offWhite;
        fg = AppTheme.textSecondary;
        icon = Icons.hourglass_empty_rounded;
        headline = 'Pending';
        detail = 'Record the result after the in-person interview.';
    }
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
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
                              color: AppTheme.textPrimary.withValues(
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
            style: TextStyle(
              color: navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: busy ? null : () => _setOutcome(app, null),
          icon: Icon(Icons.restart_alt_rounded, size: 20, color: AppTheme.textSecondary),
          label: Text(
            'Clear and set pending',
            style: TextStyle(color: AppTheme.textSecondary),
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
        icon: Icon(Icons.restart_alt_rounded, size: 20, color: AppTheme.textSecondary),
        label: Text(
          'Clear and set pending',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    ];
  }


  Widget _accountSetupStep({
    required RecruitmentApplication app,
    required bool busy,
    required bool canNavigate,
  }) {
    final navy = AppTheme.primaryNavy;
    final monitoringDone = app.hrAccountSetupDone;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 560;
        final openBtn = FilledButton.icon(
          onPressed: !canNavigate || busy
              ? null
              : () => _goToCreateAccountFor(app),
          icon: const Icon(Icons.open_in_new_rounded, size: 20),
          label: const Text('Open Create Account'),
          style: FilledButton.styleFrom(
            backgroundColor: navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
        );
        final emailBtn = OutlinedButton.icon(
          onPressed: busy ? null : () => _openHireEmailForm(app),
          icon: const Icon(Icons.mark_email_read_outlined, size: 20),
          label: const Text('Email applicant'),
          style: OutlinedButton.styleFrom(
            foregroundColor: navy,
            side: BorderSide(color: navy.withValues(alpha: 0.55)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Email applicant sends from the HRMS server to ${app.email.trim().isEmpty ? '—' : app.email.trim()} (congratulations + hired + login details). SMTP must be set in the API .env.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.textSecondary.withValues(alpha: 0.95),
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
                        color: AppTheme.textSecondary,
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
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: emailBtn),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: openBtn),
            ],
            const SizedBox(height: 22),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.08)),
            const SizedBox(height: 18),
            Text(
              'What applicants see (Step 8)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose the message shown after they refresh their application status. This is only a label for the applicant — it does not create the account.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppTheme.textSecondary,
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
                color: AppTheme.textSecondary.withValues(alpha: 0.92),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final headerWide = w >= 720;

    final titleStyle = const TextStyle(
      fontFamily: 'NotoSans',
      color: AppTheme.textPrimary,
      fontSize: 24,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      height: 1.15,
    );
    final introStyle = const TextStyle(
      fontFamily: 'NotoSans',
      color: AppTheme.textSecondary,
      fontSize: 14,
      height: 1.55,
      fontWeight: FontWeight.w500,
    );
    final refreshBtn = OutlinedButton.icon(
      onPressed: _loading ? null : _load,
      icon: Icon(
        Icons.refresh_rounded,
        size: 20,
        color: AppTheme.primaryNavy.withValues(alpha: _loading ? 0.4 : 1),
      ),
      label: Text(
        'Refresh list',
        style: TextStyle(
          fontFamily: 'NotoSans',
          color: AppTheme.primaryNavy.withValues(alpha: _loading ? 0.4 : 1),
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        side: BorderSide(
          color: AppTheme.primaryNavy.withValues(alpha: 0.45),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (headerWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Final interview (passed exam)', style: titleStyle),
                    const SizedBox(height: 10),
                    Text(
                      'Applicants listed here already passed the screening exam. Schedule the in-person interview, record the result, then open Create Account when they pass.',
                      style: introStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              refreshBtn,
            ],
          )
        else ...[
          Text('Final interview (passed exam)', style: titleStyle),
          const SizedBox(height: 10),
          Text(
            'Applicants listed here already passed the screening exam. Schedule the in-person interview, record the result, then open Create Account when they pass.',
            style: introStyle,
          ),
          const SizedBox(height: 16),
          refreshBtn,
        ],
        const SizedBox(height: 24),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_passedApplicants.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'No applicants have passed the exam yet. When an applicant completes the screening exam with a passing score, they will show up here automatically.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _passedApplicants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 18),
            itemBuilder: (context, i) {
              final app = _passedApplicants[i];
              final exam = _examResults[app.id.toLowerCase()];
              final busy = _savingIds.contains(app.id);
              final registered = _isRegistered(app);
              final scheduled = app.finalInterviewAt;
              final outcome = app.finalInterviewPassed;
              final canNavigate = widget.onGoToCreateAccount != null;
              final actions = _outcomeActions(app, outcome, registered, busy);
              final showStep3 = outcome == true && !registered;
              final step1Summary = scheduled == null
                  ? 'No date scheduled'
                  : _formatSchedule(scheduled, context);
              final step2Summary = outcome == null
                  ? 'Pending — record result'
                  : (outcome == true ? 'Passed' : 'Not passed');
              const step3Summary =
                  'Employee login & Step 8 applicant message';
              final expandStep1 = scheduled == null;
              final expandStep2 = !expandStep1 && outcome == null;
              final expandStep3 =
                  showStep3 && !expandStep1 && !expandStep2;

              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.07),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                      blurRadius: 26,
                      offset: const Offset(0, 11),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.065),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryNavy,
                            AppTheme.primaryNavyLight,
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(_kCardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                        'Applicant',
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppTheme.textSecondary.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.offWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFE2E6EA),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.045),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: AppTheme.primaryNavy.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    app.fullName,
                                    style: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      letterSpacing: -0.25,
                                      color: AppTheme.textPrimary,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    app.email,
                                    style: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      color: AppTheme.textSecondary,
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (app.positionAppliedFor != null &&
                                      app.positionAppliedFor!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Position: ${app.positionAppliedFor!.trim()}',
                                      style: TextStyle(
                                        fontFamily: 'NotoSans',
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.95,
                                        ),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppTheme.primaryNavy.withValues(
                                            alpha: 0.22,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryNavy
                                                .withValues(alpha: 0.08),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        exam != null
                                            ? 'Screening exam: ${exam.scorePercent.toStringAsFixed(0)}% · ${app.status}'
                                            : 'Status: ${app.status}',
                                        style: TextStyle(
                                          fontFamily: 'NotoSans',
                                          color: AppTheme.primaryNavy.withValues(
                                            alpha: 0.92,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.28,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.1,
                                      ),
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
                                      color: AppTheme.primaryNavy,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Account ready',
                                      style: TextStyle(
                                        fontFamily: 'NotoSans',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: AppTheme.primaryNavy,
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
                      Text(
                        'Workflow',
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppTheme.textSecondary.withValues(alpha: 0.85),
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E6EA),
                                ),
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
                                        color: AppTheme.primaryNavy,
                                        borderRadius: BorderRadius.circular(3),
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
                                              color: AppTheme.primaryNavy
                                                  .withValues(alpha: 0.88),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    scheduled == null
                                                        ? 'No date set'
                                                        : _formatSchedule(
                                                            scheduled,
                                                            context,
                                                          ),
                                                    style: TextStyle(
                                                      fontFamily: 'NotoSans',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: scheduled == null
                                                          ? AppTheme
                                                              .textSecondary
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
                                                        style:
                                                            const TextStyle(
                                                          fontFamily:
                                                              'NotoSans',
                                                          fontSize: 12,
                                                          color: AppTheme
                                                              .textSecondary,
                                                          height: 1.4,
                                                          fontWeight:
                                                              FontWeight.w500,
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
                                  icon: const Icon(Icons.edit_calendar_rounded),
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
                                    color: AppTheme.textSecondary,
                                  ),
                                  label: Text(
                                    'Clear',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
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
                            _outcomeStatusStrip(outcome),
                            if (actions.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: actions,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (outcome == true && !registered) ...[
                        SizedBox(height: _kSectionGap + 4),
                        _CollapsibleWorkflowStep(
                          key: ValueKey('${app.id}-wf3'),
                          number: 3,
                          title: 'Employee account',
                          subtitle:
                              'Create their login from the sidebar, then update what they see on Step 8.',
                          collapsedSummary: step3Summary,
                          initiallyExpanded: expandStep3,
                          child: _accountSetupStep(
                            app: app,
                            busy: busy,
                            canNavigate: canNavigate,
                          ),
                        ),
                        if (!canNavigate)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Create Account shortcut is not available here. Use the full admin sidebar.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
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
    final summaryStyle = TextStyle(
      fontFamily: 'NotoSans',
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppTheme.textSecondary.withValues(alpha: 0.92),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Text(
            '${widget.number}',
            style: const TextStyle(
              fontFamily: 'NotoSans',
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontFamily: 'NotoSans',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.25,
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
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: AppTheme.textSecondary.withValues(alpha: 0.75),
                          size: 28,
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
                            style: const TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 13,
                              height: 1.5,
                              color: AppTheme.textSecondary,
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
    );
  }
}

/// Admin enters HRMS username/password; [sendHireEmail] runs on the API (SMTP).
class _HireApplicantEmailDialog extends StatefulWidget {
  const _HireApplicantEmailDialog({
    required this.applicantEmail,
    required this.applicantName,
    required this.sendHireEmail,
  });

  final String applicantEmail;
  final String applicantName;
  final Future<void> Function(String username, String password) sendHireEmail;

  @override
  State<_HireApplicantEmailDialog> createState() =>
      _HireApplicantEmailDialogState();
}

class _HireApplicantEmailDialogState extends State<_HireApplicantEmailDialog> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePass = true;
  bool _sending = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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
        SnackBar(content: Text('$e')),
      );
      setState(() => _sending = false);
    }
  }

  InputDecoration _credentialFieldDecoration({
    required String label,
    required Color navy,
    Widget? suffixIcon,
  }) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.offWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: base,
      enabledBorder: base,
      focusedBorder: base.copyWith(
        borderSide: BorderSide(color: navy, width: 2),
      ),
      errorBorder: base.copyWith(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      focusedErrorBorder: base.copyWith(
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
          width: 2,
        ),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navy = AppTheme.primaryNavy;
    final mq = MediaQuery.sizeOf(context);
    final contentW = min(mq.width - 40, 420.0);

    return AlertDialog(
      backgroundColor: AppTheme.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: navy.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.mark_email_read_outlined, color: navy, size: 28),
      ),
      title: Text(
        'Email applicant',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
          color: AppTheme.textPrimary,
        ),
      ),
      content: SizedBox(
        width: contentW,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hired — credentials go to the applicant by email.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.sectionAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.alternate_email_rounded, size: 18, color: navy),
                          const SizedBox(width: 8),
                          Text(
                            'RECIPIENT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        widget.applicantEmail,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border(
                      left: BorderSide(color: navy, width: 4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message preview',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Dear ${widget.applicantName}, …',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textPrimary.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Login details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _userCtrl,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: _credentialFieldDecoration(label: 'Username', navy: navy),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter the username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  autofillHints: const [AutofillHints.password],
                  decoration: _credentialFieldDecoration(
                    label: 'Password',
                    navy: navy,
                    suffixIcon: IconButton(
                      tooltip: _obscurePass ? 'Show password' : 'Hide password',
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppTheme.textSecondary,
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
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        size: 22,
                        color: navy.withValues(alpha: 0.95),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Standard email is not encrypted. Send only credentials '
                          'you intend them to use. Ask them to change the password '
                          'after first login if your system allows it.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: AppTheme.textPrimary.withValues(alpha: 0.9),
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
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: navy),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.send_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Send email'),
                  ],
                ),
        ),
      ],
    );
  }
}
