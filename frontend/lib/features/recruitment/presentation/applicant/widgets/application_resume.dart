import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

int resumeStepForTrackingOnlyEntry(
  RecruitmentApplication app,
  RecruitmentExamResult? exam,
) {
  if (app.status == 'failed') return 1;
  if (exam != null && !exam.passed) {
    if (!exam.beiGradingComplete) return 7;
    return 1;
  }
  if (exam != null) {
    final hired =
        app.hiredUserId != null && app.hiredUserId!.trim().isNotEmpty;
    if (app.status == 'registered' || hired) return 8;
    if (app.finalInterviewPassed == true) return 8;
    return 7;
  }
  if (app.status == 'document_declined') return 2;
  if (app.status == 'document_approved' || app.status == 'exam_taken') {
    return 3;
  }
  if (app.status == 'passed') {
    if (app.finalInterviewPassed == true) return 8;
    return 7;
  }
  if (app.status == 'registered') return 8;
  return 1;
}

bool canProceedTrackingContinue(
  RecruitmentApplication app,
  RecruitmentExamResult? exam,
) {
  return resumeStepForTrackingOnlyEntry(app, exam) > 1;
}

String trackingContinueBlockedHint(
  RecruitmentApplication app,
  RecruitmentExamResult? exam,
) {
  if (exam != null && !exam.passed && !exam.beiGradingComplete) {
    return 'HR is still grading your BEI. When grading is done, Continue will open your final screening result.';
  }
  if (exam != null && !exam.passed) {
    return 'You did not pass the screening exam. You cannot continue to the next steps in this process.';
  }
  if (app.status == 'failed') {
    return 'The screening exam was not passed. You cannot continue to the next steps in this process.';
  }
  if (app.status == 'submitted') {
    return 'Continue will be available after HR approves your documents.';
  }
  if (app.status == 'document_declined') {
    return 'Your documents were not approved. Continue to replace them and resubmit for HR review.';
  }
  return 'You cannot proceed at this time. Check your status above.';
}
