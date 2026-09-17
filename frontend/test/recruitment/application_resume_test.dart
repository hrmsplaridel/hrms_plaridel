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

  test('submitted documents stay on tracking until HR reviews', () {
    final app = _app('submitted');
    expect(resumeStepForTrackingOnlyEntry(app, null), 1);
    expect(canProceedTrackingContinue(app, null), isFalse);
  });
}
