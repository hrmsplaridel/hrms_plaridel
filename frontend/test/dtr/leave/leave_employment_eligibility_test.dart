import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_employment_eligibility_field.dart';

void main() {
  testWidgets('HR selects employment types and can reset the restriction', (
    tester,
  ) async {
    List<String>? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LeaveEmploymentEligibilityField(
              value: selection,
              onChanged: (value) => setState(() => selection = value),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(selection, hasLength(7));
    await tester.tap(find.text('Contract of Service (COS)'));
    await tester.pumpAndSettle();
    expect(selection, isNot(contains('contract_of_service')));
    expect(selection, contains('contractual'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(selection, isNull);
  });
  test('employment eligibility survives API serialization and copy', () {
    final type = LeaveTypeDefinition.fromJson({
      'name': 'vacationLeave',
      'eligible_employment_types': ['permanent', 'contractual'],
    });
    expect(type.isEmploymentTypeEligible('permanent'), isTrue);
    expect(type.isEmploymentTypeEligible('contract_of_service'), isFalse);
    expect(type.isEmploymentTypeEligible('regular'), isFalse);
    expect(type.isEmploymentTypeEligible(null), isFalse);
    expect(
      type
          .copyWith(displayName: 'Updated')
          .toJson()['eligible_employment_types'],
      ['permanent', 'contractual'],
    );
  });
  test('unconfigured rule permits legacy and unspecified employment types', () {
    final type = LeaveTypeDefinition.fromJson({'name': 'vacationLeave'});
    expect(type.isEmploymentTypeEligible('regular'), isTrue);
    expect(type.isEmploymentTypeEligible(null), isTrue);
    expect(type.toJson()['eligible_employment_types'], isNull);
  });
}
