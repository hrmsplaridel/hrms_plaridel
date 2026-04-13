import 'package:flutter/material.dart';

import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final status = application.status;
    final hasExamResult = examResult != null;
    final passed = examResult?.passed ?? false;
    final score = examResult?.scorePercent ?? 0.0;
    final beiGradingPending =
        examResult != null && !examResult!.beiGradingComplete;
    final examPassedInferred = !beiGradingPending &&
        (passed || status == 'passed' || status == 'registered');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                color: AppTheme.primaryNavy,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.fullName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      application.email,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (application.positionAppliedFor != null &&
                        application.positionAppliedFor!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Position applied for: ${application.positionAppliedFor!.trim()}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryNavy,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusFooterNote ??
                'Status is refreshed every 30 seconds so you see the latest. You can also tap Refresh in the app bar.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          if (sameAsRecruitmentFlowNote) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'This timeline uses the same records as Recruitment Application when you continue with this email (documents, exam, final interview, account link).',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          _TimelineStepTile(
            step: 1,
            title: 'Application submitted',
            subtitle: 'Your basic info and document were received.',
            status: _TimelineStepStatus.done,
          ),
          _TimelineStepTile(
            step: 2,
            title: 'Document review',
            subtitle: _documentReviewSubtitle(status, hasExamResult),
            status: _documentReviewStatus(status, hasExamResult),
          ),
          _TimelineStepTile(
            step: 3,
            title: 'Exams (BEI, General, Math, General Info)',
            subtitle: _examsSubtitle(status, hasExamResult, beiGradingPending),
            status: _examsStatus(status, hasExamResult, beiGradingPending),
          ),
          _TimelineStepTile(
            step: 4,
            title: 'Exam result',
            subtitle: hasExamResult
                ? (beiGradingPending
                    ? 'HR is grading your BEI. Final pass or fail appears when every BEI score is entered.'
                    : (passed
                        ? 'Passed (${score.toStringAsFixed(0)}%). Matches Recruitment Application Step 7.'
                        : 'Not passed (${score.toStringAsFixed(0)}%). You may reapply with a new application.'))
                : (status == 'passed' || status == 'registered')
                    ? 'Passed. (Open Recruitment Application with your email for the exact score.)'
                    : 'Complete the exams to see your result.',
            status: hasExamResult
                ? (beiGradingPending
                    ? _TimelineStepStatus.current
                    : (passed
                        ? _TimelineStepStatus.done
                        : _TimelineStepStatus.failed))
                : (status == 'passed' || status == 'registered')
                    ? _TimelineStepStatus.done
                    : _TimelineStepStatus.pending,
          ),
          _TimelineStepTile(
            step: 5,
            title: 'Registration & account',
            subtitle: _registrationSubtitle(
              status: status,
              examPassed: examPassedInferred,
            ),
            status: _registrationStatus(
              status: status,
              examPassed: examPassedInferred,
            ),
          ),
          _TimelineStepTile(
            step: 6,
            title: 'Interview & final hiring',
            subtitle: _interviewSubtitle(context),
            status: _interviewStatus(examPassedInferred),
          ),
        ],
      ),
    );
  }

  String _documentReviewSubtitle(String status, bool hasExamResult) {
    switch (status) {
      case 'submitted':
        if (hasExamResult) {
          return 'Completed — documents were accepted (you already took the screening exams).';
        }
        return 'Under review. You will be notified when your documents are approved so you can take the exam.';
      case 'document_approved':
        return 'Approved. You can continue to the exams (use Recruitment Application and continue with your email).';
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
    if (status == 'submitted' && !hasExamResult) return _TimelineStepStatus.current;
    if (status == 'document_approved') return _TimelineStepStatus.done;
    if (status == 'passed' ||
        status == 'failed' ||
        status == 'registered') {
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
    if (hasExamResult) return 'Completed.';
    if (status == 'passed' || status == 'failed' || status == 'registered') {
      return 'Completed (status on file). Open Recruitment Application with your email if you need to review steps.';
    }
    if (status == 'document_approved') {
      return 'Ready to take. Use Recruitment Application on the recruitment page and continue with your email.';
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
      return 'Your employee account is linked. Sign in through Login using the email HR used when your account was created (same as Recruitment Application Step 8).';
    }
    if (!examPassed) {
      if (status == 'failed' || (examResult != null && examResult!.passed == false)) {
        return 'Not applicable — screening exam was not passed.';
      }
      return 'Available after you pass the screening exam.';
    }
    if (application.finalInterviewPassed == false) {
      return 'HR recorded the final interview outcome. Accounts are created by HR only—follow their instructions if you continue in the process.';
    }
    if (application.finalInterviewPassed == true) {
      return 'You passed the final interview. If you are hired, HR will create your account and email you when you can sign in — same as Recruitment Application Step 8.';
    }
    return 'Waiting for final interview results or HR instructions. Use Recruitment Application through Step 8 with this email for details and refresh.';
  }

  _TimelineStepStatus _registrationStatus({
    required String status,
    required bool examPassed,
  }) {
    if (_employeeAccountLinked) return _TimelineStepStatus.done;
    if (!examPassed) return _TimelineStepStatus.pending;
    if (application.finalInterviewPassed == false) return _TimelineStepStatus.failed;
    if (application.finalInterviewPassed == true) {
      return _TimelineStepStatus.current;
    }
    return _TimelineStepStatus.current;
  }

  String _interviewSubtitle(BuildContext context) {
    if (_employeeAccountLinked) {
      return 'Complete — you are hired and your application is linked to an employee account.';
    }
    if (application.finalInterviewPassed == true) {
      return 'You passed the in-person final interview. If you are hired, HR will create your employee account and email you when you can sign in.';
    }
    if (application.finalInterviewPassed == false) {
      return 'HR has recorded your final interview result. Contact the HR office if you have questions.';
    }
    final at = application.finalInterviewAt;
    if (at != null) {
      final loc = MaterialLocalizations.of(context);
      final dateStr = loc.formatFullDate(at);
      final t = TimeOfDay.fromDateTime(at);
      return 'Final interview scheduled: $dateStr · ${t.format(context)}. HR will update the result after your interview.';
    }
    if ((examResult?.beiGradingComplete == true &&
            examResult?.passed == true) ||
        application.status == 'passed' ||
        application.status == 'registered') {
      return 'Screening exam passed. HR will schedule or record your final interview — check back here or use Recruitment Application with your email.';
    }
    return 'HR will contact you if you are shortlisted. Final decision is communicated by the HR office.';
  }

  _TimelineStepStatus _interviewStatus(bool examPassed) {
    if (_employeeAccountLinked) return _TimelineStepStatus.done;
    if (application.finalInterviewPassed == true) return _TimelineStepStatus.done;
    if (application.finalInterviewPassed == false) return _TimelineStepStatus.failed;
    if (!examPassed) return _TimelineStepStatus.pending;
    if (application.finalInterviewAt != null) return _TimelineStepStatus.current;
    return _TimelineStepStatus.current;
  }
}

enum _TimelineStepStatus { done, current, pending, failed }

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final int step;
  final String title;
  final String subtitle;
  final _TimelineStepStatus status;

  @override
  Widget build(BuildContext context) {
    Color iconColor;
    IconData icon;
    switch (status) {
      case _TimelineStepStatus.done:
        iconColor = const Color(0xFFE85D04);
        icon = Icons.check_circle_rounded;
        break;
      case _TimelineStepStatus.current:
        iconColor = AppTheme.primaryNavy;
        icon = Icons.pending_rounded;
        break;
      case _TimelineStepStatus.failed:
        iconColor = Colors.red.shade700;
        icon = Icons.cancel_rounded;
        break;
      case _TimelineStepStatus.pending:
        iconColor = AppTheme.textSecondary;
        icon = Icons.radio_button_unchecked_rounded;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: iconColor, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step $step: $title',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
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
