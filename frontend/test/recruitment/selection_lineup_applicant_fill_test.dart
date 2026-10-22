import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/learning_development/models/comparative_assessment.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/utils/selection_lineup_applicant_fill.dart';

RecruitmentApplication _app() {
  return const RecruitmentApplication(
    id: 'app-1',
    fullName: 'Maria Santos',
    email: 'maria@example.com',
    status: 'passed',
    applicantNumber: 'PLR-0001',
    course: 'BS Information Technology',
    positionAppliedFor: 'Administrative Officer II',
  );
}

void main() {
  test('course fills education when no other qualification is on file', () {
    final fill = selectionLineupFillFromApplication(
      application: _app(),
      vacantPosition: 'Administrative Officer II',
    );

    expect(fill.name, 'Maria Santos');
    expect(fill.education, 'BS Information Technology');
    expect(fill.experience, isEmpty);
    expect(fill.training, isEmpty);
    expect(fill.eligibility, isEmpty);
  });

  test('saved line-up and assessment values override the course', () {
    final fill = selectionLineupFillFromApplication(
      application: _app(),
      vacantPosition: 'Now Hiring: Administrative Officer II',
      lineups: [
        SelectionLineupEntry(
          vacantPosition: 'Administrative Officer II',
          updatedAt: DateTime(2026, 1, 2),
          applicants: const [
            SelectionLineupApplicant(
              applicationId: 'app-1',
              education: 'Bachelor of Science in Information Technology',
              experience: '2 years clerical work',
            ),
          ],
        ),
      ],
      assessments: [
        ComparativeAssessmentEntry(
          positionToBeFilled: 'administrative officer ii',
          updatedAt: DateTime(2026, 3, 1),
          candidates: const [
            ComparativeAssessmentCandidate(
              candidateName: 'maria santos',
              trainingHrs: '16 hours',
              eligibility: 'Career Service Professional',
            ),
          ],
        ),
      ],
      sheets: [
        const WorkExperienceSheetEntry(
          positionAppliedFor: 'Administrative Officer II',
          applicantName: 'Maria Santos',
          jobDescriptionLastWork: 'Encoded payroll and prepared reports',
          minEducation: 'Should not be copied',
        ),
      ],
    );

    expect(fill.education, 'Bachelor of Science in Information Technology');
    expect(fill.experience, '2 years clerical work');
    expect(fill.training, '16 hours');
    expect(fill.eligibility, 'Career Service Professional');
  });

  test('work experience description is used only for the same position', () {
    final fill = selectionLineupFillFromApplication(
      application: _app(),
      vacantPosition: 'Administrative Officer II',
      sheets: const [
        WorkExperienceSheetEntry(
          positionAppliedFor: 'Nurse I',
          applicantName: 'Maria Santos',
          jobDescriptionLastWork: 'Ward duty',
        ),
      ],
    );

    expect(fill.experience, isEmpty);
  });
}
