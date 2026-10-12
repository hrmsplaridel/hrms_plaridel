import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/application_resume.dart';

RecruitmentApplication _app(String status) {
  return RecruitmentApplication(
    id: '11111111-1111-4111-8111-111111111111',
    fullName: 'Test Applicant',
    email: 'test@example.com',
    status: status,
  );
}

void main() {
  test('declined documents open document review so the applicant can resubmit', () {
    final app = _app('document_declined');
    expect(resumeStepForTrackingOnlyEntry(app, null), 2);
    expect(canProceedTrackingContinue(app, null), isTrue);
  });

  test('a new document approval stays on document review until the form is approved', () {
    final waiting = RecruitmentApplication(
      id: '11111111-1111-4111-8111-111111111111',
      fullName: 'Test Applicant',
      email: 'test@example.com',
      status: 'document_approved',
      step2GateRequired: true,
      requiredFormStatus: 'waiting_for_hr_form',
    );
    expect(resumeStepForTrackingOnlyEntry(waiting, null), 2);
    expect(waiting.assessmentUnlocked, isFalse);

    final approved = RecruitmentApplication(
      id: '11111111-1111-4111-8111-111111111111',
      fullName: 'Test Applicant',
      email: 'test@example.com',
      status: 'document_approved',
      step2GateRequired: true,
      requiredFormStatus: 'approved',
    );
    expect(resumeStepForTrackingOnlyEntry(approved, null), 3);
  });

  test('submitted documents stay on tracking until HR reviews', () {
    final app = _app('submitted');
    expect(resumeStepForTrackingOnlyEntry(app, null), 1);
    expect(canProceedTrackingContinue(app, null), isFalse);
  });
}
