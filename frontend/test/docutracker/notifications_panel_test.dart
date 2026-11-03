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
        title: 'Document submitted for your review',
        body: 'Purchase Request Q3 was submitted and requires your review.',
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
      DocumentNotification(
        id: 'n4',
        documentId: 'd4',
        userId: 'u1',
        type: DocumentNotification.typeAssigned,
        title: 'Document reassigned to you',
        body: 'Travel Order requires your review.',
        read: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ];
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<DocumentNotification> notifications,
    required Future<void> Function(DocumentNotification n) onTap,
    Future<void> Function()? onMarkAllRead,
    Future<void> Function(DocumentNotification n)? onMarkRead,
    String? Function(DocumentNotification n)? documentReferenceOf,
    bool loading = false,
    String? errorMessage,
    bool showChrome = true,
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
                onMarkRead: onMarkRead,
                documentReferenceOf: documentReferenceOf,
                loading: loading,
                errorMessage: errorMessage,
                showChrome: showChrome,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('eventKind maps workflow wording without inventing DB types', () {
    final submitted = DocumentNotification(
      documentId: 'd',
      userId: 'u',
      type: DocumentNotification.typeAssigned,
      title: 'Document submitted for your review',
    );
    final recovery = DocumentNotification(
      documentId: 'd',
      userId: 'u',
      type: DocumentNotification.typeAssigned,
      title: 'Document reassigned to you',
    );
    final approved = DocumentNotification(
      documentId: 'd',
      userId: 'u',
      type: DocumentNotification.typeAssigned,
      title: 'Previous step approved',
    );

    expect(submitted.eventKind, DocumentNotification.eventSubmission);
    expect(recovery.eventKind, DocumentNotification.eventAdminRecovery);
    expect(approved.eventKind, DocumentNotification.eventApproval);
    expect(submitted.eventLabel, 'Submission');
    expect(recovery.eventLabel, 'Admin Recovery');
  });

  test('inferredDocumentReference parses document name from body', () {
    final n = DocumentNotification(
      documentId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      userId: 'u',
      type: DocumentNotification.typeAssigned,
      body: 'Purchase Request Q3 was submitted and requires your review.',
    );
    expect(n.inferredDocumentReference, 'Purchase Request Q3');
  });

  testWidgets('groups notifications by urgency and routing', (tester) async {
    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) async {},
      onMarkAllRead: () async {},
    );

    expect(find.text('Overdue & escalations'), findsOneWidget);
    expect(find.text('Assignments & deadlines'), findsOneWidget);
    expect(find.text('Returns, rejections & releases'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(find.text('SUBMISSION'), findsOneWidget);
    expect(find.text('ADMIN RECOVERY'), findsOneWidget);
  });

  testWidgets('shows document reference and mark-read control', (tester) async {
    var markedId = '';
    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) async {},
      onMarkRead: (n) async {
        markedId = n.id ?? '';
      },
      documentReferenceOf: (n) =>
          n.documentId == 'd2' ? 'PR-2026-001' : n.inferredDocumentReference,
    );

    expect(find.text('PR-2026-001'), findsOneWidget);
    expect(find.text('Mark read'), findsWidgets);

    await tester.tap(find.text('Mark read').first);
    await tester.pumpAndSettle();
    expect(markedId.isNotEmpty, isTrue);
  });

  testWidgets('loading and error states render without list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerNotificationPanel(
            notifications: const [],
            unreadCount: 0,
            onNotificationTap: (_) async {},
            loading: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pumpPanel(
      tester,
      notifications: const [],
      onTap: (_) async {},
      errorMessage: 'Network down',
    );
    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(find.text('Network down'), findsOneWidget);
  });

  testWidgets('empty state explains workflow events', (tester) async {
    await pumpPanel(
      tester,
      notifications: const [],
      onTap: (_) async {},
    );
    expect(find.text('All caught up'), findsOneWidget);
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

    await tester.tap(firstTile);
    await tester.pump();

    expect(tapCount, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    completer.complete();
    await tester.pumpAndSettle();
    expect(tapCount, 1);
  });

  testWidgets('narrow width stacks title and timestamp without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) async {},
      onMarkAllRead: () async {},
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Document overdue'), findsOneWidget);
    expect(find.textContaining('ago'), findsWidgets);
  });

  testWidgets('wide width keeps desktop layout readable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpPanel(
      tester,
      notifications: sampleNotifications(),
      onTap: (_) async {},
      onMarkAllRead: () async {},
      documentReferenceOf: (_) => 'DOC-2026-0001',
    );

    expect(tester.takeException(), isNull);
    expect(find.text('DOC-2026-0001'), findsWidgets);
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
