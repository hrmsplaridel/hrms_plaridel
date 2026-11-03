import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_notification_bell.dart';

class _BellProvider extends DocuTrackerProvider {
  _BellProvider(this._items);

  final List<DocumentNotification> _items;

  @override
  List<DocumentNotification> get notifications => List.unmodifiable(_items);

  @override
  int get unreadNotificationsCount => _items.where((n) => !n.read).length;
}

void main() {
  testWidgets('bell shows unread badge from DocuTrackerProvider', (
    tester,
  ) async {
    final provider = _BellProvider([
      DocumentNotification(
        id: '1',
        documentId: 'd1',
        userId: 'u1',
        type: DocumentNotification.typeAssigned,
        read: false,
      ),
      DocumentNotification(
        id: '2',
        documentId: 'd2',
        userId: 'u1',
        type: DocumentNotification.typeReturned,
        read: true,
      ),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<DocuTrackerProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: DocuTrackerNotificationBellButton(isAdmin: false),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('DocuTracker notifications'), findsOneWidget);
  });

  testWidgets('bell has no unread badge when all notifications are read', (
    tester,
  ) async {
    final provider = _BellProvider([
      DocumentNotification(
        id: '1',
        documentId: 'd1',
        userId: 'u1',
        type: DocumentNotification.typeAssigned,
        read: true,
      ),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<DocuTrackerProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: DocuTrackerNotificationBellButton(isAdmin: true),
          ),
        ),
      ),
    );

    expect(find.text('1'), findsNothing);
    expect(find.byTooltip('DocuTracker notifications'), findsOneWidget);
  });
}
