import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

String _drawingCommands(List<int> bytes) {
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
      // Ignore streams that do not contain compressed page drawing commands.
    }
  }
  return commands.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final noto in [true, false]) {
    for (final wrappedLabel in [true, false]) {
      for (final signedFinal in [true, false]) {
        test(
          'default locator keeps final signature block: '
          'Noto=$noto, wrapped label=$wrappedLabel, signed=$signedFinal',
          () async {
            final originalTheme = pw.ThemeData.buildThemeData;
            addTearDown(() => pw.ThemeData.buildThemeData = originalTheme);
            if (noto) {
              final regular = pw.Font.ttf(
                await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
              );
              final bold = pw.Font.ttf(
                await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
              );
              // Match the application's global PDF theme installed at startup.
              pw.ThemeData.buildThemeData = () => pw.ThemeData.withFont(
                base: regular,
                bold: bold,
                italic: regular,
                boldItalic: bold,
              );
            } else {
              pw.ThemeData.buildThemeData = null;
            }
            final ink = base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC',
            );
            final bytes = await LocatorSlipPrint.buildPdf(
              id: null,
              employeeName: 'Sample Employee',
              dateText: 'Nov 4, 2026',
              requestTypeLabel: 'Pass Slip',
              locationLabel: wrappedLabel
                  ? 'Destination / Location'
                  : 'Office / Destination',
              office: 'Municipal Hall',
              remarks: 'Official business',
              amIn: true,
              amOut: true,
              pmIn: true,
              pmOut: true,
              signatories: LocatorFormSignatories(
                applicant: LocatorPrintedSignatory(
                  name: 'Sample Employee',
                  signatureBytes: ink,
                ),
                departmentHead: LocatorPrintedSignatory(
                  name: 'Department Reviewer',
                  signatureBytes: ink,
                ),
                finalApprover: LocatorPrintedSignatory(
                  name: 'Final HR Reviewer',
                  positionTitle:
                      'Human Resource Management and Development Officer',
                  signatureBytes: signedFinal ? ink : null,
                ),
              ),
            );
            final commands = _drawingCommands(bytes);
            expect(
              RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)),
              hasLength(1),
            );
            expect(
              RegExp(r'/\S+\s+Do\b').allMatches(commands),
              hasLength(signedFinal ? 4 : 3),
              reason:
                  'Draw the logo and every supplied signature, including HR.',
            );
            expect(
              commands,
              matches(RegExp(r'420(?:\.0+)? 0 m 0 0 l S')),
              reason:
                  'The final approver underline must survive even unsigned.',
            );
          },
        );
      }
    }
  }
}
