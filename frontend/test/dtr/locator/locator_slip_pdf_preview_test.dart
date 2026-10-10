import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'locator PDF merges only its request-bound saved background version',
    () async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      FormData? sent;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            expect(
              o.path,
              '/api/locator-slips/print/requests/locator-1/render',
            );
            sent = o.data as FormData;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: Uint8List.fromList([37, 80, 68, 70, 45, 49]),
              ),
            );
          },
        ),
      );
      final bytes = await LocatorSlipPrint.buildPdf(
        id: 'locator-1',
        employeeName: 'Employee',
        dateText: 'Oct 10, 2026',
        requestTypeLabel: 'Locator',
        locationLabel: 'Office',
        office: 'Hall',
        remarks: 'Business',
        amIn: true,
        amOut: true,
        pmIn: false,
        pmOut: false,
        signatories: const LocatorFormSignatories(
          form: {
            'has_print_background': true,
            'print_template_version_id': 'filed-version',
          },
        ),
      );
      expect(
        sent!.fields.singleWhere((f) => f.key == 'version_id').value,
        'filed-version',
      );
      expect(sent!.files.single.value.filename, 'locator.pdf');
      expect(bytes, [37, 80, 68, 70, 45, 49]);
    },
  );

  test(
    'locator PDF accommodates long official names and all three signatures',
    () async {
      final ink = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      for (final signed in [false, true]) {
        final person = LocatorPrintedSignatory(
          name:
              'A Very Long Official Department Head Name With Several Middle Names',
          signatureBytes: signed ? ink : null,
          positionTitle: 'Municipal Human Resource Management Officer',
        );
        final bytes = await LocatorSlipPrint.buildPdf(
          id: 'locator-1',
          employeeName: 'Test Employee',
          dateText: 'Oct 1, 2026',
          requestTypeLabel: 'Official Business',
          locationLabel: 'Office / Destination',
          office: 'Municipal Hall',
          remarks: 'Official transaction',
          amIn: true,
          amOut: true,
          pmIn: false,
          pmOut: false,
          signatories: LocatorFormSignatories(
            applicant: person,
            departmentHead: person,
            finalApprover: person,
          ),
        );
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(100));
      }
    },
  );

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

  test('empty and whitespace-only signatory names leave blank lines', () async {
    for (final name in ['', '   ']) {
      final person = LocatorPrintedSignatory(name: name);
      final bytes = await LocatorSlipPrint.buildPdf(
        id: null,
        employeeName: name,
        dateText: 'Oct 1, 2026',
        requestTypeLabel: 'Official Business',
        locationLabel: 'Office / Destination',
        office: 'Municipal Hall',
        remarks: 'Official transaction',
        amIn: true,
        amOut: true,
        pmIn: false,
        pmOut: false,
        signatories: LocatorFormSignatories(
          applicant: person,
          departmentHead: person,
          finalApprover: person,
        ),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(100));
    }
  });
}
