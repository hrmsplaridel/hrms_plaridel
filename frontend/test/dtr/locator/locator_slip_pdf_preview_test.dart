import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

void main() {
  test('locator form can build PDF bytes without opening print', () async {
    final bytes = await LocatorSlipPrint.buildPdf(
      id: 'locator-1',
      employeeName: 'Test Employee',
      dateText: 'Sep 21, 2026',
      requestTypeLabel: 'Official Business',
      locationLabel: 'Municipal Hall',
      office: 'Human Resources',
      remarks: 'Official transaction',
      amIn: true,
      amOut: true,
      pmIn: false,
      pmOut: false,
    );

    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
