import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';

void main() {
  test('default locator types do not include Work From Home', () {
    expect(
      LocatorRequestType.values.map((type) => type.code),
      orderedEquals(<String>['locator', 'pass_slip']),
    );
  });

  test('configured coverage mode is authoritative for custom types', () {
    final manualWfh = LocatorRequestType.fromJson(const {
      'code': 'work_from_home',
      'label': 'Work From Home',
      'coverage_mode': 'manual',
    });
    final coveredRemoteWork = LocatorRequestType.fromJson(const {
      'code': 'remote_work',
      'label': 'Remote Work',
      'coverage_mode': 'wfh',
    });

    expect(manualWfh.isSystem, isFalse);
    expect(manualWfh.usesWfhCoverage, isFalse);
    expect(coveredRemoteWork.usesWfhCoverage, isTrue);
  });
}
