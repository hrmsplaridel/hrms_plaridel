import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/mayor/data/mayor_endorsement_offices.dart';

void main() {
  test('endorsement office dropdown has the fixed selectable list', () {
    expect(kMayorEndorsementOffices, const [
      'AMOMC',
      'AMORAP',
      'BANK OF HOPE',
      'CDH',
      'DAR',
      'DEPED',
      'DPWH RENEWAL',
      'LITE SHIPPING',
      'MARSGEN',
      'MAYOR ACOSTA',
      'MOPH',
      'MOTI',
      'OFFICE OF VICE GOVERNOR',
      'PGMO',
      'PNP',
      'REGION',
      'UTILITY',
    ]);
    expect(
      kMayorEndorsementOffices.toSet().length,
      kMayorEndorsementOffices.length,
    );
  });
}
