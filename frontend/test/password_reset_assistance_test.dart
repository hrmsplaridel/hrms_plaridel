import 'dart:async';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/auth/presentation/widgets/password_reset_assistance_dialog.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/password_reset_requests_page.dart';

void main() {
  testWidgets(
    'queue cards adapt to narrow and desktop layouts with status chips',
    (tester) async {
      for (final width in [390.0, 1440.0]) {
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
        expect(find.widgetWithText(ChoiceChip, 'Pending'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Closed'));
        await tester.pumpAndSettle();
        expect(queries.last['status'], 'closed');
        expect(find.text('Send reset OTP'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
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
