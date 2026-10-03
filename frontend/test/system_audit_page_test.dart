import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/system_audit_page.dart';

void main() {
  testWidgets(
    'cursor navigation keeps snapshot, recovers after failure, and refresh resets it',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemAuditPage(
              load: (query) async {
                requests.add(Map.of(query));
                if (query['cursor'] == 'next' && fail) {
                  fail = false;
                  throw Exception('Temporary failure');
                }
                return {
                  'entries': [],
                  'total': 101,
                  'first_cursor': 'first',
                  'next_cursor': query['cursor'] == 'next' ? null : 'next',
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.last['pagination'], 'cursor');
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(requests.last['cursor'], 'next');
      expect(find.text('Page 2'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Next page',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(requests.last['cursor'], 'first');
      await tester.tap(find.byTooltip('Refresh audit log'));
      await tester.pumpAndSettle();
      expect(requests.last.containsKey('cursor'), false);
      await tester.enterText(find.byType(TextField).first, 'new actor');
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(requests.last.containsKey('actor'), false);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(requests.last['actor'], 'new actor');
      expect(requests.last.containsKey('cursor'), false);
      expect(find.text('Page 1'), findsOneWidget);
    },
  );

  testWidgets('defaults to changes, explains permissions, and can show views', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SystemAuditPage(
            load: (query) async {
              requests.add(query);
              return {
                'total': 1,
                'entries': [
                  {
                    'action': 'dtr_admin_access_changed',
                    'actor_name': 'System Administrator',
                    'target_name': 'Maria Santos',
                    'entity_type': 'user',
                    'entity_id': 'uuid-1',
                    'created_at': '2026-10-03T13:14:00Z',
                    'details': {
                      'before': {'reports_allowed': false},
                      'after': {'reports_allowed': true},
                    },
                  },
                ],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.first['hide_views'], '1');
    expect(find.text('DTR access changed'), findsOneWidget);
    expect(find.textContaining('Report access granted'), findsOneWidget);
    await tester.tap(find.text('DTR access changed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Report access: Off → On'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Include audit log visits'));
    await tester.pumpAndSettle();
    expect(requests.last.containsKey('hide_views'), false);
  });

  testWidgets(
    'date picker sends local calendar days as UTC bounds and reset clears them',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final start = DateTime(2026, 10, 2);
      final end = DateTime(2026, 10, 3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemAuditPage(
              load: (query) async {
                requests.add(query);
                return {'total': 0, 'entries': []};
              },
              pickDateRange: (_, _) async =>
                  DateTimeRange(start: start, end: end),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select dates'));
      await tester.pumpAndSettle();
      expect(requests.last['date_from'], start.toUtc().toIso8601String());
      expect(
        requests.last['date_before'],
        DateTime(2026, 10, 4).toUtc().toIso8601String(),
      );
      expect(find.text('Oct 2 – Oct 3, 2026'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(requests.last.containsKey('date_from'), false);
      expect(requests.last.containsKey('date_before'), false);
      expect(find.text('Select dates'), findsOneWidget);
    },
  );
}
