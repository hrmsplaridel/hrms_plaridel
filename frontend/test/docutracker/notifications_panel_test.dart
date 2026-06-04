import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_notifications_panel.dart';

void main() {
  List<DocumentNotification> sampleNotifications() {
    return [
      DocumentNotification(
        id: 'n1',
        documentId: 'd1',
        userId: 'u1',
        type: DocumentNotification.typeOverdue,
        title: 'Document overdue',
        body: 'Memo #1 is overdue.',
        read: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      DocumentNotification(
        id: 'n2',
        documentId: 'd2',
        userId: 'u1',
        type: DocumentNotification.typeAssigned,
        title: 'Assigned to you',
        body: 'Please review memo #2.',
        read: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      DocumentNotification(
        id: 'n3',
        documentId: 'd3',
        userId: 'u1',
        type: DocumentNotification.typeRejected,
        title: 'Document rejected',
        body: 'Memo #3 has been rejected.',
        read: true,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<DocumentNotification> notifications,
    required Future<void> Function(DocumentNotification n) onTap,
    Future<void> Function()? onMarkAllRead,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DocuTrackerNotificationPanel(
                notifications: notifications,
                unreadCount: notifications.where((n) => !n.read).length,
                onNotificationTap: onTap,
                onMarkAllRead: onMarkAllRead,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups notifications by urgency and routing', (tester) async {
    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) async {},
      onMarkAllRead: () async {},
    );

    expect(find.text('Overdue & escalations'), findsOneWidget);
    expect(find.text('Assignments & deadlines'), findsOneWidget);
    expect(find.text('Returns & rejections'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('notification tap shows loading and prevents double-open', (
    tester,
  ) async {
    final completer = Completer<void>();
    var tapCount = 0;

    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) {
        tapCount += 1;
        return completer.future;
      },
      onMarkAllRead: () async {},
    );

    final firstTile = find.text('Document overdue');
    expect(firstTile, findsOneWidget);

    await tester.tap(firstTile);
    await tester.pump();

    // Second tap should be ignored while opening.
    await tester.tap(firstTile);
    await tester.pump();

    expect(tapCount, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    completer.complete();
    await tester.pumpAndSettle();
    expect(tapCount, 1);
  });

  testWidgets('mark all read shows in-flight feedback', (tester) async {
    final completer = Completer<void>();
    var markCalls = 0;

    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) async {},
      onMarkAllRead: () {
        markCalls += 1;
        return completer.future;
      },
    );

    await tester.tap(find.text('Mark all read'));
    await tester.pump();

    expect(markCalls, 1);
    expect(find.text('Marking…'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
  });
}
