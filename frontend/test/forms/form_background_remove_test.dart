import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';
import 'package:hrms_plaridel/features/forms/presentation/admin/pages/form_background_upload_page.dart';

void main() {
  testWidgets('saved background can be removed from the list', (tester) async {
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormSavedBackgroundTile(
            template: const FormPrintTemplate(
              module: 'rsp',
              formKey: 'ojt_work_immersion',
              paperSize: 'letter',
              originalFilename: 'ojt-bg.pdf',
            ),
            onRemove: () => removed = true,
          ),
        ),
      ),
    );

    expect(find.text('OJT / Work Immersion Evaluation'), findsOneWidget);
    expect(find.textContaining('ojt-bg.pdf'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(removed, isTrue);
  });

  testWidgets('Forms list shows a Print background entry', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormsPrintBackgroundEntry(onOpen: () => opened = true),
        ),
      ),
    );

    expect(find.text('Print background'), findsOneWidget);
    await tester.tap(find.text('Print background'));
    await tester.pump();
    expect(opened, isTrue);
  });
}
