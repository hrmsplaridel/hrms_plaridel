import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Read-only pipeline status for one application (same data as [ApplicationFlowPage] / by-email API).
class RspApplicationStatusTimeline extends StatelessWidget {
  const RspApplicationStatusTimeline({
    super.key,
    required this.application,
    this.examResult,
    this.sameAsRecruitmentFlowNote = false,
    this.statusFooterNote,
  });

  final RecruitmentApplication application;
  final RecruitmentExamResult? examResult;
  final bool sameAsRecruitmentFlowNote;

  /// Overrides the default footer about refresh / app bar (e.g. when embedded in Application Flow).
  final String? statusFooterNote;

  bool get _employeeAccountLinked =>
      application.status == 'registered' ||
      (application.hiredUserId != null &&
          application.hiredUserId!.trim().isNotEmpty);

  // ── Derived state ──────────────────────────────────────────────────────────

  bool get _hasExamResult => examResult != null;
  bool get _passed => examResult?.passed ?? false;
  double get _score => examResult?.scorePercent ?? 0.0;
  bool get _beiGradingPending =>
      examResult != null && !examResult!.beiGradingComplete;
  bool get _examPassedInferred =>
      !_beiGradingPending &&
      (_passed ||
          application.status == 'passed' ||
          application.status == 'registered');

  // ── Overall status label + color ──────────────────────────────────────────

  ({String label, Color color, IconData icon}) get _overallBadge {
    if (_employeeAccountLinked) {
      return (
        label: 'Hired',
        color: const Color(0xFF2E7D32),
        icon: Icons.verified_rounded,
      );
    }
    switch (application.status) {
      case 'registered':
        return (
          label: 'Hired',
          color: const Color(0xFF2E7D32),
          icon: Icons.verified_rounded,
        );
      case 'passed':
        return (
          label: 'Exam Passed',
          color: AppTheme.primaryNavy,
          icon: Icons.emoji_events_rounded,
        );
      case 'failed':
        return (
          label: 'Exam Not Passed',
          color: Colors.red.shade700,
          icon: Icons.cancel_rounded,
        );
      case 'document_approved':
        return (
          label: 'Documents Approved',
          color: const Color(0xFF1565C0),
          icon: Icons.task_alt_rounded,
        );
      case 'document_declined':
        return (
          label: 'Documents Declined',
          color: Colors.red.shade700,
          icon: Icons.cancel_rounded,
        );
      case 'exam_taken':
        return (
          label: 'Exam Submitted',
          color: const Color(0xFF6A1B9A),
          icon: Icons.assignment_turned_in_rounded,
        );
      default:
        return (
          label: 'Under Review',
          color: const Color(0xFF0277BD),
          icon: Icons.hourglass_top_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _overallBadge;

    final steps = [
      _StepData(
        step: 1,
        title: 'Application Submitted',
        subtitle: 'Your basic info and documents were received.',
        status: _TimelineStepStatus.done,
        icon: Icons.upload_file_rounded,
      ),
      _StepData(
        step: 2,
        title: 'Document Review',
        subtitle: _documentReviewSubtitle(application.status, _hasExamResult),
        status: _documentReviewStatus(application.status, _hasExamResult),
        icon: Icons.folder_open_rounded,
      ),
      _StepData(
        step: 3,
        title: 'Screening Exams',
        subtitle: _examsSubtitle(
          application.status,
          _hasExamResult,
          _beiGradingPending,
        ),
        status: _examsStatus(
          application.status,
          _hasExamResult,
          _beiGradingPending,
        ),
        icon: Icons.quiz_rounded,
      ),
      _StepData(
        step: 4,
        title: 'Exam Result',
        subtitle: _hasExamResult
            ? (_beiGradingPending
                  ? 'HR is grading your BEI. Final pass/fail appears when all BEI scores are entered.'
                  : (_passed
                        ? 'Passed — ${_score.toStringAsFixed(0)}%.'
                        : 'Not passed — ${_score.toStringAsFixed(0)}%. You may reapply with a new application.'))
            : (application.status == 'passed' ||
                  application.status == 'registered')
            ? 'Passed. (Open Recruitment Application with your email for the exact score.)'
            : 'Complete the exams to see your result.',
        status: _hasExamResult
            ? (_beiGradingPending
                  ? _TimelineStepStatus.current
                  : (_passed
                        ? _TimelineStepStatus.done
                        : _TimelineStepStatus.failed))
            : (application.status == 'passed' ||
                  application.status == 'registered')
            ? _TimelineStepStatus.done
            : _TimelineStepStatus.pending,
        icon: Icons.bar_chart_rounded,
      ),
      _StepData(
        step: 5,
        title: 'Final Interview',
        subtitle: _interviewSubtitle(context),
        status: _interviewStatus(_examPassedInferred),
        icon: Icons.record_voice_over_rounded,
      ),
      _StepData(
        step: 6,
        title: 'Registration & Account',
        subtitle: _registrationSubtitle(
          status: application.status,
          examPassed: _examPassedInferred,
        ),
        status: _registrationStatus(
          status: application.status,
          examPassed: _examPassedInferred,
        ),
        icon: Icons.badge_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Applicant info card ──────────────────────────────────────────────
        _ApplicantCard(application: application, badge: badge),
        const SizedBox(height: 16),
        // ── Refresh note ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.autorenew_rounded,
                size: 15,
                color: AppTheme.primaryNavy.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusFooterNote ??
                      'Status refreshes every 30 s. Tap Refresh in the top bar for an instant update.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // ── Timeline steps ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.timeline_rounded,
                    color: AppTheme.primaryNavy,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Application Pipeline',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...List.generate(steps.length, (i) {
                final isLast = i == steps.length - 1;
                return _TimelineStepTile(data: steps[i], isLast: isLast);
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step subtitle / status helpers ─────────────────────────────────────────

  String _documentReviewSubtitle(String status, bool hasExamResult) {
    switch (status) {
      case 'submitted':
        if (hasExamResult) {
          return 'Completed — documents were accepted (you already took the screening exams).';
        }
        return 'Under review. You will be notified when your documents are approved so you can take the exam.';
      case 'document_approved':
        return 'Approved. Continue to the exams via the Recruitment Application page.';
      case 'document_declined':
        return 'Your documents were not approved. You may submit a new application with updated documents.';
      case 'passed':
      case 'failed':
      case 'registered':
      case 'exam_taken':
        return 'Completed — your documents were accepted so you could take the screening exams.';
      default:
        if (hasExamResult) {
          return 'Completed — documents were accepted before your exam was recorded.';
        }
        return '—';
    }
  }

  _TimelineStepStatus _documentReviewStatus(String status, bool hasExamResult) {
    if (status == 'document_declined') return _TimelineStepStatus.failed;
    if (status == 'submitted' && !hasExamResult)
      return _TimelineStepStatus.current;
    if (status == 'document_approved') return _TimelineStepStatus.done;
    if (status == 'passed' || status == 'failed' || status == 'registered') {
      return _TimelineStepStatus.done;
    }
    if (status == 'submitted' && hasExamResult) return _TimelineStepStatus.done;
    return _TimelineStepStatus.pending;
  }

  String _examsSubtitle(
    String status,
    bool hasExamResult,
    bool beiGradingPending,
  ) {
    if (beiGradingPending) {
      return 'Multiple-choice sections submitted. HR is grading your BEI answers.';
    }
    if (hasExamResult) return 'All sections completed.';
    if (status == 'passed' || status == 'failed' || status == 'registered') {
      return 'Completed (status on file).';
    }
    if (status == 'document_approved') {
      return 'Ready — use Recruitment Application and continue with your email.';
    }
    if (status == 'submitted' || status == 'document_declined') {
      return 'Available after your documents are approved.';
    }
    return '—';
  }

  _TimelineStepStatus _examsStatus(
    String status,
    bool hasExamResult,
    bool beiGradingPending,
  ) {
    if (beiGradingPending) return _TimelineStepStatus.current;
    if (hasExamResult) return _TimelineStepStatus.done;
    if (status == 'passed' || status == 'failed' || status == 'registered') {
      return _TimelineStepStatus.done;
    }
    if (status == 'document_approved') return _TimelineStepStatus.current;
    return _TimelineStepStatus.pending;
  }

  String _registrationSubtitle({
    required String status,
    required bool examPassed,
  }) {
    if (_employeeAccountLinked) {
      return 'Your employee account is linked. Sign in through the Login page.';
    }
    if (!examPassed) {
      if (status == 'failed' ||
          (examResult != null && examResult!.passed == false)) {
        return 'Not applicable — screening exam was not passed.';
      }
      return 'Available after you pass the screening exam.';
    }
    if (application.finalInterviewPassed == false) {
      return 'HR recorded the final interview outcome. Follow HR instructions if you continue.';
    }
    if (application.finalInterviewPassed == true) {
      return 'You passed the final interview. HR will create your account and email you when ready.';
    }
    return 'Waiting for final interview results. Use Recruitment Application for details.';
  }

  _TimelineStepStatus _registrationStatus({
    required String status,
    required bool examPassed,
  }) {
    if (_employeeAccountLinked) return _TimelineStepStatus.done;
    if (!examPassed) return _TimelineStepStatus.pending;
    if (application.finalInterviewPassed == false)
      return _TimelineStepStatus.failed;
    return _TimelineStepStatus.current;
  }

  String _interviewSubtitle(BuildContext context) {
    if (_employeeAccountLinked) {
      return 'Complete — you are hired and linked to an employee account.';
    }
    if (application.finalInterviewPassed == true) {
      return 'You passed the final interview. HR will create your employee account.';
    }
    if (application.finalInterviewPassed == false) {
      return 'HR has recorded your final interview result. Contact the HR office if you have questions.';
    }
    final at = application.finalInterviewAt?.toLocal();
    if (at != null) {
      final loc = MaterialLocalizations.of(context);
      final dateStr = loc.formatFullDate(at);
      final t = TimeOfDay.fromDateTime(at);
      return 'Scheduled: $dateStr · ${t.format(context)}. HR will update the result after your interview.';
    }
    if ((_examPassedInferred) ||
        application.status == 'passed' ||
        application.status == 'registered') {
      return 'Exam passed. HR will schedule your final interview — check back here.';
    }
    return 'HR will contact you if you are shortlisted. Final decision is from the HR office.';
  }

  _TimelineStepStatus _interviewStatus(bool examPassed) {
    if (_employeeAccountLinked) return _TimelineStepStatus.done;
    if (application.finalInterviewPassed == true)
      return _TimelineStepStatus.done;
    if (application.finalInterviewPassed == false)
      return _TimelineStepStatus.failed;
    if (!examPassed) return _TimelineStepStatus.pending;
    return _TimelineStepStatus.current;
  }
}

// ── Applicant info card ───────────────────────────────────────────────────────

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.application, required this.badge});

  final RecruitmentApplication application;
  final ({String label, Color color, IconData icon}) badge;

  String get _initials {
    final parts = application.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryNavyDark, AppTheme.primaryNavy],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Name + email + position
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  application.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  application.email,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (application.positionAppliedFor != null &&
                    application.positionAppliedFor!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      application.positionAppliedFor!.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Status badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badge.color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.icon, size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      badge.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step data model ───────────────────────────────────────────────────────────

class _StepData {
  const _StepData({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
  });
  final int step;
  final String title;
  final String subtitle;
  final _TimelineStepStatus status;
  final IconData icon;
}

enum _TimelineStepStatus { done, current, pending, failed }

// ── Timeline step tile with connector line ────────────────────────────────────

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({required this.data, required this.isLast});

  final _StepData data;
  final bool isLast;

  static const double _nodeSize = 40.0;
  static const double _lineWidth = 2.0;

  ({Color bg, Color border, Color icon, Color text}) get _palette {
    switch (data.status) {
      case _TimelineStepStatus.done:
        return (
          bg: const Color(0xFFFFF3E0),
          border: AppTheme.primaryNavy,
          icon: AppTheme.primaryNavy,
          text: AppTheme.primaryNavyDark,
        );
      case _TimelineStepStatus.current:
        return (
          bg: const Color(0xFFE3F2FD),
          border: const Color(0xFF1565C0),
          icon: const Color(0xFF1565C0),
          text: const Color(0xFF0D47A1),
        );
      case _TimelineStepStatus.failed:
        return (
          bg: const Color(0xFFFFEBEE),
          border: Colors.red.shade600,
          icon: Colors.red.shade600,
          text: Colors.red.shade800,
        );
      case _TimelineStepStatus.pending:
        return (
          bg: const Color(0xFFF5F5F5),
          border: const Color(0xFFBDBDBD),
          icon: const Color(0xFF9E9E9E),
          text: AppTheme.textSecondary,
        );
    }
  }

  IconData get _statusIcon {
    switch (data.status) {
      case _TimelineStepStatus.done:
        return Icons.check_rounded;
      case _TimelineStepStatus.current:
        return Icons.pending_rounded;
      case _TimelineStepStatus.failed:
        return Icons.close_rounded;
      case _TimelineStepStatus.pending:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  Color get _lineColor {
    if (data.status == _TimelineStepStatus.done) return AppTheme.primaryNavy;
    if (data.status == _TimelineStepStatus.current)
      return const Color(0xFF1565C0);
    return const Color(0xFFDEDEDE);
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: node + connector line ────────────────────────────────────
          SizedBox(
            width: _nodeSize + 16,
            child: Column(
              children: [
                // Circle node
                Container(
                  width: _nodeSize,
                  height: _nodeSize,
                  decoration: BoxDecoration(
                    color: p.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.border, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_statusIcon, color: p.icon, size: 20),
                ),
                // Vertical connector
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: _lineWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _lineColor,
                              _lineColor.withValues(alpha: 0.25),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Right: content card ────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: data.status == _TimelineStepStatus.pending
                      ? Colors.transparent
                      : p.bg.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: data.status == _TimelineStepStatus.pending
                      ? null
                      : Border.all(color: p.border.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(data.icon, size: 15, color: p.icon),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Step ${data.step} · ${data.title}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: data.status == _TimelineStepStatus.pending
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        if (data.status == _TimelineStepStatus.current)
                          _PulseDot(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      data.subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: data.status == _TimelineStepStatus.pending
                            ? AppTheme.textSecondary.withValues(alpha: 0.6)
                            : p.text.withValues(alpha: 0.85),
                        height: 1.45,
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
}

// ── Pulsing "active" dot indicator ───────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
