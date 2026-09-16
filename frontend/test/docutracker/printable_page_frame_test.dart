import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_printable_page_frame.dart';

void main() {
  testWidgets('printable page includes official header, body, and footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 794,
            height: 1123,
            child: DocuTrackerPrintablePageFrame(
              documentTitle: 'OFFICE MEMORANDUM',
              child: Align(
                alignment: Alignment.topLeft,
                child: Text('Editable document body'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('docutracker-printable-header')),
      findsOneWidget,
    );
    expect(find.text('Republic of the Philippines'), findsOneWidget);
    expect(find.text('MUNICIPALITY OF PLARIDEL'), findsOneWidget);
    expect(find.text('OFFICE MEMORANDUM'), findsOneWidget);
    expect(find.text('Editable document body'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('docutracker-printable-footer')),
      findsOneWidget,
    );
    expect(find.text('plaridel_misocc@yahoo.com'), findsOneWidget);
    expect(find.text('PLARIDEL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('official A4 background is layered behind title and body', (
    tester,
  ) async {
    final background = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
      'AQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 794,
            height: 1123,
            child: DocuTrackerPrintablePageFrame(
              documentTitle: 'OFFICE MEMORANDUM',
              letterheadImageBytes: background,
              child: const Align(
                alignment: Alignment.topLeft,
                child: Text('Editable document body'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('docutracker-letterhead-background')),
      findsOneWidget,
    );
    expect(find.text('OFFICE MEMORANDUM'), findsOneWidget);
    expect(find.text('Editable document body'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('docutracker-printable-header')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
