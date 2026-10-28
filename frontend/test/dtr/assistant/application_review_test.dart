import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/application_review.dart';

void main() {
  tearDown(ActiveApplicationReview.clear);

  test('review follows the language of the current question', () {
    ActiveApplicationReview.register(Object(), 'leave', () => []);
    expect(
      ActiveApplicationReview.matches('Suriin mo ang application ko.'),
      isTrue,
    );
    expect(
      ActiveApplicationReview.reply('Suriin mo ang application ko.'),
      contains('Pagsusuri'),
    );
    expect(
      ActiveApplicationReview.matches(
        'Tan-awa akong application kung naa bay kulang.',
      ),
      isTrue,
    );
    expect(
      ActiveApplicationReview.reply(
        'Tan-awa akong application kung naa bay kulang.',
      ),
      contains('Wala pay na-submit'),
    );
  });

  testWidgets('required errors identify the field', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: key,
            child: TextFormField(
              decoration: const InputDecoration(
                labelText: 'Number of Working Days Applied For',
              ),
              validator: (_) => 'Required',
            ),
          ),
        ),
      ),
    );
    expect(
      reviewFormFields(key.currentState).single.message,
      'Number of Working Days Applied For: Required',
    );
  });

  test(
    'chat review uses current entries and clears closed or signed-out forms',
    () {
      expect(ActiveApplicationReview.matches('Review my application'), isTrue);
      expect(ActiveApplicationReview.matches('Am I ready to submit?'), isTrue);
      expect(
        ActiveApplicationReview.matches('Check my application status'),
        isFalse,
      );
      expect(
        ActiveApplicationReview.reply(),
        contains('Open your leave or locator'),
      );
      final owner = Object();
      var missing = true;
      ActiveApplicationReview.register(
        owner,
        'locator',
        () => [
          if (missing) const ApplicationReviewIssue('Destination is required.'),
        ],
      );
      expect(
        ActiveApplicationReview.reply(),
        contains('Destination is required.'),
      );
      missing = false;
      expect(ActiveApplicationReview.reply(), contains('No issues found'));
      ActiveApplicationReview.clear(Object());
      expect(ActiveApplicationReview.reply(), contains('locator application'));
      ActiveApplicationReview.clear(owner);
      expect(
        ActiveApplicationReview.reply(),
        contains('Open your leave or locator'),
      );
      ActiveApplicationReview.register(owner, 'leave', () => []);
      ActiveApplicationReview.clear();
      expect(
        ActiveApplicationReview.reply(),
        contains('Open your leave or locator'),
      );
    },
  );

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
