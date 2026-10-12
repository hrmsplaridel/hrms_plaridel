import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';

void main() {
  test(
    'filing policy round trips and keeps employee and staff eligibility separate',
    () {
      final type = LocatorRequestType.fromJson({
        'code': 'power_outage',
        'filing_access': 'admin',
        'auto_approve_admin': true,
      });
      expect(type.employeeCanFile, isFalse);
      expect(type.adminCanFile, isTrue);
      expect(type.autoApproveAdmin, isTrue);
      expect(type.toJson()['filing_access'], 'admin');
      expect(type.copyWith(filingAccess: 'employee').adminCanFile, isFalse);
      expect(LocatorRequestType.locator.employeeCanFile, isTrue);
      expect(LocatorRequestType.locator.adminCanFile, isFalse);
      expect(LocatorRequestType.fromJson({'code':'legacy'}).adminCanFile,isFalse);
      expect(LocatorRequestType.locator.autoApproveAdmin, isFalse);
    },
  );
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
