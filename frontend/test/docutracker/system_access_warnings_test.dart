import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/security/docutracker_system_access_warnings.dart';

Set<String> codes(List<DocuTrackerAccessWarning> warnings) =>
    warnings.map((warning) => warning.code).toSet();

void main() {
  const allBlocked = {
    'view': false,
    'create_draft': false,
    'submit': false,
    'download': false,
  };

  test('no warnings for a consistent configuration', () {
    expect(docuTrackerAccessWarnings(effective: allBlocked), isEmpty);
    expect(
      docuTrackerAccessWarnings(
        effective: {
          ...allBlocked,
          'view': true,
          'create_draft': true,
          'submit': true,
        },
        roleId: 'hr',
        isRoleDefault: true,
      ),
      isEmpty,
    );
  });

  test('flags submit without create and create without submit', () {
    expect(
      codes(
        docuTrackerAccessWarnings(effective: {...allBlocked, 'submit': true}),
      ),
      {'submit-without-create'},
    );
    expect(
      codes(
        docuTrackerAccessWarnings(
          effective: {...allBlocked, 'create_draft': true},
        ),
      ),
      {'create-without-submit'},
    );
  });

  test('unknown actions are not treated as blocked', () {
    expect(docuTrackerAccessWarnings(effective: {'submit': true}), isEmpty);
  });

  test('role-wide employee grants suggest employee exceptions', () {
    final warnings = docuTrackerAccessWarnings(
      effective: {
        ...allBlocked,
        'create_draft': true,
        'submit': true,
        'download': true,
      },
      roleId: 'employee',
      documentType: 'purchaseRequest',
      isRoleDefault: true,
    );
    expect(codes(warnings), {'role-wide-create', 'download-broad'});
  });

  test('administrators never get warnings', () {
    expect(
      docuTrackerAccessWarnings(
        effective: {...allBlocked, 'submit': true},
        roleId: 'admin',
      ),
      isEmpty,
    );
  });

  test('exceptions equal to the inherited value are redundant', () {
    final warnings = docuTrackerAccessWarnings(
      effective: {...allBlocked, 'view': true},
      exceptions: {'view': true},
      inherited: {...allBlocked, 'view': true},
    );
    expect(codes(warnings), {'redundant-view'});
  });
}
