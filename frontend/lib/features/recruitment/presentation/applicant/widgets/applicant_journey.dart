/// Applicant-facing 5-stage journey. Internal `_step` 1–8 is unchanged.
enum ApplicantJourneyStage {
  application,
  documentReview,
  assessment,
  deliberation,
  finalHiring,
}

enum ApplicantJourneyTone {
  completed,
  current,
  locked,
  underReview,
  rejected,
}

ApplicantJourneyStage journeyStageForStep(int step) {
  switch (step) {
    case 1:
      return ApplicantJourneyStage.application;
    case 2:
      return ApplicantJourneyStage.documentReview;
    case 3:
    case 4:
    case 5:
    case 6:
      return ApplicantJourneyStage.assessment;
    case 7:
      return ApplicantJourneyStage.deliberation;
    case 8:
      return ApplicantJourneyStage.finalHiring;
    default:
      return ApplicantJourneyStage.application;
  }
}

extension ApplicantJourneyStageX on ApplicantJourneyStage {
  String get label {
    switch (this) {
      case ApplicantJourneyStage.application:
        return 'Application';
      case ApplicantJourneyStage.documentReview:
        return 'Document Review';
      case ApplicantJourneyStage.assessment:
        return 'Assessment';
      case ApplicantJourneyStage.deliberation:
        return 'Deliberation';
      case ApplicantJourneyStage.finalHiring:
        return 'Final Hiring';
    }
  }

  int get index => ApplicantJourneyStage.values.indexOf(this);

  int get displayNumber => index + 1;
}

ApplicantJourneyTone journeyToneForStage({
  required ApplicantJourneyStage stage,
  required ApplicantJourneyStage current,
  required String? applicationStatus,
  required bool examPassed,
  required bool examBeiGradingPending,
  required bool? finalInterviewPassed,
}) {
  if (stage.index < current.index) {
    return ApplicantJourneyTone.completed;
  }
  if (stage.index > current.index) {
    return ApplicantJourneyTone.locked;
  }

  switch (stage) {
    case ApplicantJourneyStage.documentReview:
      if (applicationStatus == 'document_declined') {
        return ApplicantJourneyTone.rejected;
      }
      if (applicationStatus == 'submitted') {
        return ApplicantJourneyTone.underReview;
      }
      return ApplicantJourneyTone.current;
    case ApplicantJourneyStage.deliberation:
      if (examBeiGradingPending) return ApplicantJourneyTone.underReview;
      if (!examPassed || finalInterviewPassed == false) {
        return ApplicantJourneyTone.rejected;
      }
      if (finalInterviewPassed == true) return ApplicantJourneyTone.current;
      return ApplicantJourneyTone.underReview;
    case ApplicantJourneyStage.application:
    case ApplicantJourneyStage.assessment:
    case ApplicantJourneyStage.finalHiring:
      return ApplicantJourneyTone.current;
  }
}
