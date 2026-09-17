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
  });
}
