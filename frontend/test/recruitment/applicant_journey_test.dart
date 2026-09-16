import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/applicant_journey.dart';

void main() {
  test('maps internal steps 1-8 onto five applicant stages', () {
    expect(journeyStageForStep(1), ApplicantJourneyStage.application);
    expect(journeyStageForStep(2), ApplicantJourneyStage.documentReview);
    expect(journeyStageForStep(3), ApplicantJourneyStage.assessment);
    expect(journeyStageForStep(4), ApplicantJourneyStage.assessment);
    expect(journeyStageForStep(5), ApplicantJourneyStage.assessment);
    expect(journeyStageForStep(6), ApplicantJourneyStage.assessment);
    expect(journeyStageForStep(7), ApplicantJourneyStage.deliberation);
    expect(journeyStageForStep(8), ApplicantJourneyStage.finalHiring);
  });

  test('document review submitted is under review', () {
    final tone = journeyToneForStage(
      stage: ApplicantJourneyStage.documentReview,
      current: ApplicantJourneyStage.documentReview,
      applicationStatus: 'submitted',
      examPassed: false,
      examBeiGradingPending: false,
      finalInterviewPassed: null,
    );
    expect(tone, ApplicantJourneyTone.underReview);
  });
}
