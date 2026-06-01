import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permission_evaluator.dart';

void main() {
  const evaluator = DocuTrackerPermissionEvaluator();

  test('Default deny when all candidates are null', () {
    expect(
      evaluator.evaluate(
        userSpecificGranted: null,
        userWildcardGranted: null,
        roleSpecificGranted: null,
        roleWildcardGranted: null,
      ),
      isFalse,
    );
  });

  test('User specific overrides everything else', () {
    expect(
      evaluator.evaluate(
        userSpecificGranted: true,
        userWildcardGranted: false,
        roleSpecificGranted: false,
        roleWildcardGranted: true,
      ),
      isTrue,
    );
  });

  test('User wildcard applies when user specific is absent', () {
    expect(
      evaluator.evaluate(
        userSpecificGranted: null,
        userWildcardGranted: true,
        roleSpecificGranted: false,
        roleWildcardGranted: false,
      ),
      isTrue,
    );
  });

  test('Role baseline applies when no user overrides exist', () {
    expect(
      evaluator.evaluate(
        userSpecificGranted: null,
        userWildcardGranted: null,
        roleSpecificGranted: false,
        roleWildcardGranted: true,
      ),
      isFalse,
    );
  });
}
