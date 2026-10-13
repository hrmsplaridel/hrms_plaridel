import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/application_review.dart';

void main() {
  testWidgets(
    'review reports actual validator errors and returns to the field without submitting',
    (tester) async {
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Destination is required.'
                            : null,
                      ),
                      TextButton(
                        onPressed: () => showApplicationReview(
                          context,
                          reviewFormFields(form.currentState),
                        ),
                        child: const Text('Review'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Application review'), findsOneWidget);
      expect(find.text('Go to field'), findsOneWidget);
      await tester.tap(find.text('Go to field'));
      await tester.pumpAndSettle();
      expect(find.text('Application review'), findsNothing);
      await tester.enterText(find.byType(TextFormField), 'Treasury');
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(
        find.text('No issues found by the current form checks.'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing has been submitted'), findsOneWidget);
    },
  );
}
