import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_native_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

int imageDraws(List<int> bytes) {
  final raw = latin1.decode(bytes);
  final commands = StringBuffer();
  for (final match in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', match.end);
    if (end < 0) continue;
    try {
      final decoded = latin1.decode(zlib.decode(bytes.sublist(match.end, end)));
      if (decoded.contains('BT') && decoded.contains(' Tf')) {
        commands.write(decoded);
      }
    } on FormatException {
      /* Ignore image/font streams. */
    }
  }
  return RegExp(r'/\S+\s+Do\b').allMatches(commands.toString()).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native Locator imports its real slots and keeps all ink after save/load and moving fields',
    () async {
      final oldTheme = pw.ThemeData.buildThemeData;
      addTearDown(() => pw.ThemeData.buildThemeData = oldTheme);
      final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      );
      pw.ThemeData.buildThemeData = () =>
          pw.ThemeData.withFont(base: regular, bold: bold);
      final type = LocatorRequestType.locator.copyWith(
        locationLabel: 'Destination / Location',
      );
      final imported = await importLocatorNativeLayout(type);
      expect(imported.layout.validate(), isNull);
      expect(imported.layout.elements, hasLength(9));
      expect(
        imported.layout.elements
            .where((e) => e.kind == 'field')
            .map((e) => e.source),
        containsAll([
          'date',
          'employee_name',
          'request_type',
          'office',
          'reason',
          'time_segments',
        ]),
      );
      expect(
        imageDraws(imported.background),
        1,
        reason:
            'Only the original logo belongs on the empty native background.',
      );
      final layout = LocatorPrintLayout.fromJson(
        imported.layout
            .copyWith(
              elements: [
                for (final item in imported.layout.elements)
                  item.source == 'hr_approver'
                      ? item.copyWith(x: item.x + 10, width: item.width - 10)
                      : item,
              ],
            )
            .toJson(),
      );
      final ink = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC',
      );
      final form = {
        ...locatorLayoutSample(type),
        'location_label': type.locationLabel,
        'print_layout': layout.toJson(),
      };
      final bytes = await LocatorSlipPrint.buildPdf(
        id: null,
        employeeName: 'Employee',
        dateText: 'Nov 4, 2026',
        requestTypeLabel: type.label,
        locationLabel: type.locationLabel,
        office: 'Hall',
        remarks: 'Business',
        amIn: true,
        amOut: true,
        pmIn: true,
        pmOut: true,
        signatories: LocatorFormSignatories(
          form: form,
          applicant: LocatorPrintedSignatory(
            name: 'Employee',
            signatureBytes: ink,
          ),
          departmentHead: LocatorPrintedSignatory(
            name: 'Department Reviewer',
            signatureBytes: ink,
          ),
          finalApprover: LocatorPrintedSignatory(
            name: 'Final Reviewer',
            positionTitle: 'Human Resource Officer',
            signatureBytes: ink,
          ),
        ),
      );
      expect(
        imageDraws(bytes),
        4,
        reason:
            'The current form must retain its logo and each signature exactly once.',
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)),
        hasLength(1),
      );
      expect(imageDraws(await locatorNativeLayoutBackground(type, layout)), 1);

      for (final paper in printPaperSizes.values) {
        for (final size in [paper, (paper.$2, paper.$1)]) {
          final fitted = locatorNativeLayoutOnBackground(
            layout,
            size.$1,
            size.$2,
          );
          expect(fitted.validate(), isNull);
          expect(
            LocatorPrintLayout.fromJson(fitted.toJson()).toJson(),
            fitted.toJson(),
          );
          final composed = await buildLocatorNativeLayoutPdf(
            layout: fitted,
            form: form,
            signatories: const LocatorFormSignatories(),
          );
          expect(
            RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(composed)),
            hasLength(1),
          );
        }
      }
    },
  );
}
