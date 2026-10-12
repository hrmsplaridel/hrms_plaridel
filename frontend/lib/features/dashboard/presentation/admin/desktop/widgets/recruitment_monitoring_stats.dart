import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

/// Dashboard-only view of existing RSP application fields.
/// Counts reuse the same status/flag rules already used on the admin dashboard.
class RecruitmentMonitoringStats {
  const RecruitmentMonitoringStats({
    required this.pending,
    required this.inProgress,
    required this.hired,
    required this.closed,
    required this.total,
    required this.pipeline,
    required this.statusBreakdown,
    required this.attention,
    required this.monthlySubmissions,
  });

  final int pending;
  final int inProgress;
  final int hired;
  final int closed;
  final int total;
  final List<RecruitmentPipelineStage> pipeline;
  final List<RecruitmentStatusCount> statusBreakdown;
  final List<RecruitmentAttentionItem> attention;
  final List<RecruitmentMonthCount> monthlySubmissions;

  static const pipelineStages = <({String key, String label})>[
    (key: 'applied', label: 'Applied'),
    (key: 'review', label: 'Document Review'),
    (key: 'required_form', label: 'Required Form'),
    (key: 'assessment', label: 'Assessment'),
    (key: 'exam', label: 'Exam'),
    (key: 'pre_deliberation', label: 'Pre-deliberation'),
    (key: 'interview', label: 'Interview'),
    (key: 'final_hiring', label: 'Final Hiring'),
    (key: 'requirements', label: 'Final Requirements'),
    (key: 'orientation', label: 'Orientation'),
    (key: 'account', label: 'Account Setup'),
    (key: 'hired', label: 'Hired'),
  ];

  static RecruitmentMonitoringStats fromApps(
    List<RecruitmentApplication> apps, {
    DateTime? now,
  }) {
    var pending = 0;
    var inProgress = 0;
    var hired = 0;
    var closed = 0;
    final pipelineCounts = {for (final s in pipelineStages) s.key: 0};
    final statusMap = <String, int>{};

    for (final a in apps) {
      final status = a.status;
      if (status == 'submitted') {
        pending++;
      } else if (status == 'document_approved' ||
          status == 'exam_taken' ||
          status == 'passed') {
        inProgress++;
      } else if (status == 'registered' || a.hiredUserId != null) {
        hired++;
      } else {
        closed++;
      }

      final stageKey = pipelineStageKey(a);
      if (stageKey != null) {
        pipelineCounts[stageKey] = (pipelineCounts[stageKey] ?? 0) + 1;
      }

      final label = detailedStageLabel(a);
      statusMap[label] = (statusMap[label] ?? 0) + 1;
    }

    final statusEntries = statusMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RecruitmentMonitoringStats(
      pending: pending,
      inProgress: inProgress,
      hired: hired,
      closed: closed,
      total: apps.length,
      pipeline: [
        for (final s in pipelineStages)
          RecruitmentPipelineStage(
            key: s.key,
            label: s.label,
            count: pipelineCounts[s.key] ?? 0,
          ),
      ],
      statusBreakdown: [
        for (final e in statusEntries)
          RecruitmentStatusCount(label: e.key, count: e.value),
      ],
      attention: attentionItems(apps),
      monthlySubmissions: monthlyCounts(apps, now: now),
    );
  }

  /// Furthest existing recruitment stage for one applicant.
  static String? pipelineStageKey(RecruitmentApplication app) {
    if (app.status == 'failed' || app.status == 'document_declined') {
      return null;
    }
    if (app.hiredUserId != null || app.status == 'registered') return 'hired';
    if (app.hrAccountSetupDone) return 'account';
    if (app.orientationAttended != null || app.orientationAt != null) {
      return 'orientation';
    }
    if (app.finalRequirementsApproved) return 'requirements';
    if (app.finalInterviewPassed == true &&
        app.step5GateRequired &&
        !app.finalHiringUnlocked) {
      return 'final_hiring';
    }
    if (app.status == 'passed' &&
        app.finalInterviewPassed == null &&
        app.step4GateRequired &&
        !app.deliberationSchedulingUnlocked) {
      return 'pre_deliberation';
    }
    if (app.finalInterviewPassed != null || app.status == 'passed') {
      return 'interview';
    }
    switch (app.status) {
      case 'submitted':
        return 'applied';
      case 'document_approved':
        if (app.step2GateRequired && !app.assessmentUnlocked) {
          return 'required_form';
        }
        if (app.step2GateRequired && app.assessmentUnlocked) {
          return 'assessment';
        }
        return 'review';
      case 'exam_taken':
        return 'exam';
      default:
        return null;
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'Pending review';
      case 'document_approved':
        return 'Docs approved';
      case 'document_declined':
        return 'Docs declined';
      case 'exam_taken':
        return 'Exam taken';
      case 'passed':
        return 'Passed exam';
      case 'failed':
        return 'Failed exam';
      case 'registered':
        return 'Hired';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  /// Current stage, including the issued form, pre-deliberation, and final hiring gates.
  static String detailedStageLabel(RecruitmentApplication app) {
    if (app.hiredUserId != null || app.status == 'registered') return 'Hired';
    if (app.hrAccountSetupDone) return 'Account setup done';
    if (app.orientationAttended == true) return 'Orientation attended';
    if (app.orientationAttended == false) return 'Orientation missed';
    if (app.orientationAt != null) return 'Orientation scheduled';
    if (app.finalRequirementsApproved) return 'Final requirements approved';
    if (app.finalInterviewPassed == true) {
      if (app.step5GateRequired && !app.finalHiringUnlocked) {
        if (app.tatStatus != 'completed') return 'Turn-around time';
        return 'CSC approval';
      }
      return 'Final interview passed';
    }
    if (app.finalInterviewPassed == false) return 'Final interview failed';
    if (app.status == 'passed' &&
        app.step4GateRequired &&
        !app.deliberationSchedulingUnlocked) {
      if (app.wesStatus != 'approved') {
        return app.wesStatus == 'submitted_for_review' ||
                app.wesStatus == 'resubmitted_for_review'
            ? 'Work experience review'
            : 'Work experience';
      }
      if (app.applicantsProfileStatus != 'completed') {
        return 'Applicants profile';
      }
      return 'Selection line-up';
    }
    if (app.status == 'document_approved' && app.step2GateRequired) {
      if (!app.assessmentUnlocked) return _requiredFormStageLabel(app);
      return 'Assessment';
    }

    return statusLabel(app.status);
  }

  static String _requiredFormStageLabel(RecruitmentApplication app) {
    switch (app.requiredFormStatus) {
      case 'submitted_for_review':
      case 'resubmitted_for_review':
        return 'Form for review';
      case 'needs_revision':
        return 'Form revision';
      case 'assigned':
      case 'in_progress':
        if (app.requiredFormType == 'ojt') return 'OJT form';
        if (app.requiredFormType == 'bi') return 'BI form';
        return 'Required form';
      default:
        return 'Waiting for HR form';
    }
  }

  static List<RecruitmentAttentionItem> attentionItems(
    List<RecruitmentApplication> apps,
  ) {
    var documentReview = 0;
    var requiredForm = 0;
    var examReview = 0;
    var preDeliberation = 0;
    var interview = 0;
    var finalHiring = 0;
    var finalRequirements = 0;

    for (final a in apps) {
      if (a.status == 'submitted') {
        documentReview++;
        continue;
      }
      if (a.status == 'document_approved' &&
          a.step2GateRequired &&
          !a.assessmentUnlocked) {
        requiredForm++;
        continue;
      }
      if (a.status == 'exam_taken') {
        examReview++;
        continue;
      }
      if (a.status == 'passed' &&
          a.finalInterviewPassed == null &&
          !a.finalRequirementsApproved &&
          a.orientationAt == null &&
          !a.hrAccountSetupDone &&
          a.hiredUserId == null) {
        if (a.step4GateRequired && !a.deliberationSchedulingUnlocked) {
          preDeliberation++;
        } else {
          interview++;
        }
        continue;
      }
      if (a.finalInterviewPassed == true && !a.finalRequirementsApproved) {
        if (a.step5GateRequired && !a.finalHiringUnlocked) {
          finalHiring++;
        } else {
          finalRequirements++;
        }
      }
    }

    return [
      if (documentReview > 0)
        RecruitmentAttentionItem(
          label: 'Pending document review',
          count: documentReview,
        ),
      if (requiredForm > 0)
        RecruitmentAttentionItem(
          label: 'Required form pending',
          count: requiredForm,
        ),
      if (examReview > 0)
        RecruitmentAttentionItem(
          label: 'Pending exam review',
          count: examReview,
        ),
      if (preDeliberation > 0)
        RecruitmentAttentionItem(
          label: 'Pre-deliberation incomplete',
          count: preDeliberation,
        ),
      if (interview > 0)
        RecruitmentAttentionItem(label: 'Pending interview', count: interview),
      if (finalHiring > 0)
        RecruitmentAttentionItem(
          label: 'Final hiring incomplete',
          count: finalHiring,
        ),
      if (finalRequirements > 0)
        RecruitmentAttentionItem(
          label: 'Incomplete final requirements',
          count: finalRequirements,
        ),
    ];
  }

  static List<RecruitmentMonthCount> monthlyCounts(
    List<RecruitmentApplication> applications, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final months = <DateTime>[];
    for (var i = 5; i >= 0; i--) {
      var y = today.year;
      var m = today.month - i;
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      months.add(DateTime(y, m, 1));
    }

    final counts = {for (final d in months) d: 0};
    for (final app in applications) {
      final dt = app.createdAt?.toLocal();
      if (dt == null) continue;
      final key = DateTime(dt.year, dt.month, 1);
      if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
    }

    const shortMonths = [
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
    return [
      for (final d in months)
        RecruitmentMonthCount(
          label: shortMonths[d.month - 1],
          count: counts[d] ?? 0,
        ),
    ];
  }
}

class RecruitmentPipelineStage {
  const RecruitmentPipelineStage({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;
}

class RecruitmentStatusCount {
  const RecruitmentStatusCount({required this.label, required this.count});

  final String label;
  final int count;
}

class RecruitmentAttentionItem {
  const RecruitmentAttentionItem({required this.label, required this.count});

  final String label;
  final int count;
}

class RecruitmentMonthCount {
  const RecruitmentMonthCount({required this.label, required this.count});

  final String label;
  final int count;
}
