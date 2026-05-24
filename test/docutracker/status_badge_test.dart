import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/docutracker/widgets/docutracker_status_badge.dart';

void main() {
  Future<void> pumpBadge(
    WidgetTester tester, {
    required DocumentStatus status,
    bool compact = false,
    bool showIcon = true,
    bool dotStyle = false,
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

  testWidgets('dot style hides icon and still keeps status semantics', (tester) async {
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
}
