import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

void main() {
  test('by-email payload maps final-requirement files and hire fields', () {
    final app = RecruitmentApplication.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'applicant_number': 'PLR-AB12CD34',
      'full_name': 'Test Applicant',
      'email': 'test@example.com',
      'status': 'final_interview',
      'final_interview_passed': true,
      'final_requirements_approved': false,
      'hired_user_id': '22222222-2222-4222-8222-222222222222',
      'doc_medical_certificate_path': 'app/med.pdf',
      'doc_medical_certificate_name': 'med.pdf',
      'doc_drug_test_path': 'app/drug.pdf',
      'doc_drug_test_name': 'drug.pdf',
      'doc_nbi_clearance_path': 'app/nbi.pdf',
      'doc_nbi_clearance_name': 'nbi.pdf',
      'doc_nbi_clearance_reject_reason': 'Unreadable scan',
    });

    expect(app.applicantNumber, 'PLR-AB12CD34');
    expect(app.hiredUserId, '22222222-2222-4222-8222-222222222222');
    expect(app.docMedicalCertificatePath, 'app/med.pdf');
    expect(app.docDrugTestPath, 'app/drug.pdf');
    expect(app.docNbiClearancePath, 'app/nbi.pdf');
    expect(app.docNbiClearanceRejectReason, 'Unreadable scan');
    expect(app.hasAllFinalRequirementsUploaded, isTrue);
    expect(app.documentRevisionUsed, isFalse);
    expect(app.finalRequirementsRevisionUsed, isFalse);
  });

  test('Step 1 document revision can be used only once', () {
    final firstReview = RecruitmentApplication.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'full_name': 'Test Applicant',
      'email': 'test@example.com',
      'status': 'submitted',
      'document_revision_used': false,
    });
    expect(firstReview.canRejectApplicationDocument, isTrue);

    final afterResubmit = RecruitmentApplication.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'full_name': 'Test Applicant',
      'email': 'test@example.com',
      'status': 'submitted',
      'document_revision_used': true,
    });
    expect(afterResubmit.canRejectApplicationDocument, isFalse);
    expect(afterResubmit.documentRevisionUsed, isTrue);

    final openDecline = RecruitmentApplication.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'full_name': 'Test Applicant',
      'email': 'test@example.com',
      'status': 'document_declined',
      'document_revision_used': false,
      'doc_resume_reject_reason': 'Blurry',
    });
    expect(openDecline.canRejectApplicationDocument, isTrue);
  });

  test('Final requirements revision can be used only once', () {
    final openRound = RecruitmentApplication.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'full_name': 'Test Applicant',
      'email': 'test@example.com',
      'status': 'passed',
      'final_interview_passed': true,
      'final_requirements_revision_used': true,
      'doc_medical_certificate_reject_reason': 'Unreadable',
      'doc_drug_test_path': 'app/drug.pdf',
      'doc_nbi_clearance_path': 'app/nbi.pdf',
    });
    expect(openRound.hasOpenFinalRequirementRevision, isTrue);
    expect(openRound.canRejectFinalRequirementDocument, isTrue);

    final closedRound = RecruitmentApplication.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'full_name': 'Test Applicant',
      'email': 'test@example.com',
      'status': 'passed',
      'final_interview_passed': true,
      'final_requirements_revision_used': true,
      'doc_medical_certificate_path': 'app/med.pdf',
      'doc_drug_test_path': 'app/drug.pdf',
      'doc_nbi_clearance_path': 'app/nbi.pdf',
    });
    expect(closedRound.hasOpenFinalRequirementRevision, isFalse);
    expect(closedRound.canRejectFinalRequirementDocument, isFalse);
  });
}
