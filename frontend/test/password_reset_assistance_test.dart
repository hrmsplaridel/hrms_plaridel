import 'dart:async';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/auth/presentation/widgets/password_reset_assistance_dialog.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/password_reset_requests_page.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

void main() {
  testWidgets(
    'queue uses Workforce-style status tabs on narrow and desktop layouts',
    (tester) async {
      for (final width in [320.0, 390.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        final queries = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PasswordResetRequestsPage(
                load: (query) async {
                  queries.add(query);
                  return {
                    'requests': [
                      {
                        'id': 'a-long-request-id',
                        'full_name': 'An Administrator With A Very Long Name',
                        'email':
                            'a.very.long.registered.email.address@example.gov.ph',
                        'role': 'admin',
                        'status': query['status'] ?? 'pending',
                        'created_at': '2026-10-04T00:00:00Z',
                      },
                    ],
                    'has_more': false,
                  };
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DropdownButton<String>), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        final tabs = find.byKey(const ValueKey('password-reset-status-tabs'));
        expect(tabs, findsOneWidget);
        for (final entry in {'sent': 'Sent', 'closed': 'Closed', '': 'All requests', 'pending': 'Pending'}.entries) {
          final tab = find.byKey(ValueKey('password-reset-tab-${entry.key.isEmpty ? 'all' : entry.key}'));
          expect(find.descendant(of: tabs, matching: find.text(entry.value)), findsOneWidget);
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(queries.last['status'], entry.key.isEmpty ? isNull : entry.key);
          expect(queries.last['page'], 1);
          expect(tester.widget<Semantics>(tab).properties.selected, isTrue);
          final selectedMaterial = find.descendant(of: tab, matching: find.byType(Material));
          expect(tester.widget<Material>(selectedMaterial).color, AppTheme.primaryNavy);
        }
        await tester.tap(find.byKey(const ValueKey('password-reset-tab-closed')));
        await tester.pumpAndSettle();
        expect(find.text('Send reset OTP'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('status tabs reset pagination and ignore selections while loading', (tester) async {
    final queries = <Map<String, dynamic>>[];
    Completer<Map<String, dynamic>>? response;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PasswordResetRequestsPage(
      load: (query) async {
        queries.add(query);
        return response == null ? {'requests': [], 'has_more': true} : response.future;
      },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));await tester.pumpAndSettle();
    expect(queries.last['page'], 2);
    response = Completer<Map<String, dynamic>>();
    await tester.tap(find.byKey(const ValueKey('password-reset-tab-sent')));
    await tester.pump();
    expect(queries.last, {'page': 1, 'status': 'sent'});
    final count = queries.length;
    await tester.tap(find.byKey(const ValueKey('password-reset-tab-closed')));
    await tester.pump();
    expect(queries.length, count);
    response.complete({'requests': [], 'has_more': false});
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(find.byKey(const ValueKey('password-reset-tab-sent'))).properties.selected, isTrue);
    await tester.tap(find.byTooltip('Refresh requests'));await tester.pumpAndSettle();
    expect(queries.last, {'page': 1, 'status': 'sent'});
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('status tabs wrap at narrow widths with large text in both themes', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!),
        home: Scaffold(body: PasswordResetRequestsPage(load: (_) async => {'requests': [], 'has_more': false})),
      ));
      await tester.pumpAndSettle();
      for (final key in ['pending', 'sent', 'closed', 'all']) {
        final tab = find.byKey(ValueKey('password-reset-tab-$key'));
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(tab);
        expect(bounds.left, greaterThanOrEqualTo(16));
        expect(bounds.right, lessThanOrEqualTo(304));
        await tester.tap(tab);await tester.pumpAndSettle();
        expect(tester.widget<Semantics>(tab).properties.selected, isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets(
    'queue refreshes from live events, defers during confirmation, and polls as fallback',
    (tester) async {
      final events = StreamController<AppRealtimeEvent>.broadcast();
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordResetRequestsPage(
              events: events.stream,
              load: (_) async {
                loads++;
                return {
                  'requests': [
                    {
                      'id': 'r',
                      'full_name': 'Employee $loads',
                      'email': 'e@test.local',
                      'role': 'employee',
                      'status': 'pending',
                    },
                  ],
                  'has_more': false,
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.add(
        const AppRealtimeEvent(name: 'password_reset_requests_changed'),
      );
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.tap(find.text('Send reset OTP'));
      await tester.pumpAndSettle();
      events.add(
        const AppRealtimeEvent(name: 'password_reset_requests_changed'),
      );
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(loads, 3);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(loads, 4);
      await tester.pumpWidget(const SizedBox());
      await events.close();
      await tester.pump(const Duration(seconds: 30));
      expect(loads, 4);
    },
  );
  testWidgets(
    'public assistance validates email, retains failures, and gives generic instructions',
    (tester) async {
      final requests = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordResetAssistanceDialog(
              initialEmail: '',
              submit: (email) async {
                requests.add(email);
                if (requests.length == 1) throw Exception('offline');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.enterText(find.byType(TextField), 'employee@test.local');
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to submit'), findsOneWidget);
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('If this is an eligible account'),
        findsOneWidget,
      );
      expect(find.text('Enter a reset code'), findsOneWidget);
      expect(requests.length, 2);
    },
  );

  testWidgets(
    'admin must confirm verification; failed delivery stays retryable',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordResetRequestsPage(
              load: (_) async => {
                'requests': [
                  {
                    'id': 'request',
                    'full_name': 'Employee',
                    'email': 'employee@test.local',
                    'role': 'employee',
                    'status': 'pending',
                    'created_at': '2026-10-04T00:00:00Z',
                  },
                ],
                'has_more': false,
              },
              act: (id, action) async {
                actions.add(action);
                throw Exception('offline');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send reset OTP'));
      await tester.pumpAndSettle();
      final send = find.widgetWithText(FilledButton, 'Send code');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(actions, ['send']);
      expect(find.text('Send reset OTP'), findsOneWidget);
      expect(find.textContaining('Unable to update'), findsOneWidget);
    },
  );
}
