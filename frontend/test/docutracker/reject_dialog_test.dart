import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_reject_dialog.dart';

void main() {
  Finder confirmButton() =>
      find.byKey(const ValueKey('docutracker-reject-confirm'));

  FilledButton confirmWidget(WidgetTester tester) =>
      tester.widget<FilledButton>(confirmButton());

  Future<void> pumpDialog(
    WidgetTester tester, {
    required DocuTrackerRejectCallback onConfirm,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => DocuTrackerRejectDialog(onConfirm: onConfirm),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirmation follows trimmed reason validity', (tester) async {
    await pumpDialog(tester, onConfirm: (_) async => true);

    expect(confirmWidget(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-reject-reason')),
      '   ',
    );
    await tester.pump();
    expect(confirmWidget(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-reject-reason')),
      'Incorrect supporting record',
    );
    await tester.pump();
    expect(confirmWidget(tester).onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-reject-reason')),
      '',
    );
    await tester.pump();
    expect(confirmWidget(tester).onPressed, isNull);
  });

  testWidgets('loading prevents repeated confirmation', (tester) async {
    final pending = Completer<bool>();
    var submissions = 0;
    await pumpDialog(
      tester,
      onConfirm: (reason) {
        submissions++;
        return pending.future;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-reject-reason')),
      'Valid reason',
    );
    await tester.pump();
    await tester.tap(confirmButton());
    await tester.pump();

    expect(submissions, 1);
    expect(confirmWidget(tester).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(confirmButton(), warnIfMissed: false);
    await tester.pump();
    expect(submissions, 1);

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(DocuTrackerRejectDialog), findsNothing);
  });

  testWidgets('cancel closes without submitting', (tester) async {
    var submissions = 0;
    await pumpDialog(
      tester,
      onConfirm: (_) async {
        submissions++;
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('docutracker-reject-cancel')));
    await tester.pumpAndSettle();

    expect(submissions, 0);
    expect(find.byType(DocuTrackerRejectDialog), findsNothing);
  });
}
