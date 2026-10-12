import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';

void main() {
  test('signature status comes from the API and is not sent back on save', () {
    final entry = ApplicantsProfileEntry.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'position_applied_for': 'Nurse I',
      'signature_status': 'completed',
      'signatures_locked': true,
    });

    expect(entry.signatureStatus, 'completed');
    expect(entry.signaturesLocked, isTrue);
    expect(entry.toJson().containsKey('signatures_locked'), isFalse);
    expect(entry.toJson().containsKey('is_locked'), isFalse);

    final waiting = entry.copyWithSignature(
      signatureStatus: 'awaiting_signatures',
      signaturesLocked: false,
    );
    expect(waiting.signaturesLocked, isFalse);
    expect(waiting.signatureStatus, 'awaiting_signatures');
  });

  test('a form without signature fields stays editable', () {
    final entry = ApplicantsProfileEntry.fromJson({
      'position_applied_for': 'Nurse I',
    });
    expect(entry.signaturesLocked, isFalse);
    expect(entry.signatureStatus, isNull);
  });
}
