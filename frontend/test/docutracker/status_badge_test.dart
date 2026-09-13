import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_status_badge.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';

void main() {
  Future<void> pumpBadge(
    WidgetTester tester, {
    required DocumentStatus status,
    bool compact = false,
    bool showIcon = true,
    bool dotStyle = false,
    String? label,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DocuTrackerStatusBadge(
              status: status,
              compact: compact,
              showIcon: showIcon,
              dotStyle: dotStyle,
              label: label,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders status text and semantics label', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpBadge(
        tester,
        status: DocumentStatus.inReview,
        compact: false,
        showIcon: true,
      );

      expect(find.text('In Review'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Status: In Review',
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('dot style hides icon and still keeps status semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpBadge(
        tester,
        status: DocumentStatus.overdue,
        compact: true,
        showIcon: true,
        dotStyle: true,
      );

      expect(find.byType(Icon), findsNothing);
      expect(find.text('Overdue'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Status: Overdue',
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('supports a contextual display label without changing status', (
    tester,
  ) async {
    await pumpBadge(tester, status: DocumentStatus.pending, label: 'Draft');

    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
  });

  test('removes raw exception and transport wording from displayed errors', () {
    expect(
      docuTrackerDisplayError('Exception: Invalid workflow'),
      'Invalid workflow',
    );
    expect(
      docuTrackerDisplayError('DioException: connection failed'),
      'Could not complete the request. Check your connection and try again.',
    );
  });
}
