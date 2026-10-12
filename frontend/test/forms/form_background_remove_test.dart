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

  testWidgets('Forms header shows one Print Background button', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormsHubHeader(
            isNarrow: false,
            onPrintBackground: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Print Background'), findsOneWidget);
    expect(find.text('Upload, preview, or remove a letterhead.'), findsNothing);
    expect(find.byType(OutlinedButton), findsOneWidget);
    await tester.tap(find.text('Print Background'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('narrow Forms header keeps Print Background visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormsHubHeader(
            isNarrow: true,
            onPrintBackground: () {},
          ),
        ),
      ),
    );

    expect(find.text('Forms'), findsOneWidget);
    expect(find.text('Print Background'), findsOneWidget);
  });
}
