import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/system_backups_page.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'backup page loads, starts backup and preserves settings draft at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        var starts = 0;
        var reads = 0;
        var running = false;
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'GET') reads++;
              if (options.method == 'POST') {
                starts++;
                running = true;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'settings': {
                      'enabled': false,
                      'time': '02:00',
                      'retentionDays': 7,
                      'revision': 'r1',
                    },
                    'history': running
                        ? [
                            {
                              'id': 'test',
                              'status': 'running',
                              'source': 'manual',
                              'startedAt': '2026-10-04T00:00:00Z',
                            },
                          ]
                        : [],
                    'lastSuccess': null,
                    'health': running ? 'running' : 'missing',
                    'storageLocation': 'private backups',
                    'encryption': {'configured': true, 'scheme': 'age'},
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SystemBackupsPage())),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('No backups yet'), findsOneWidget);
        expect(reads, 1);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '14');
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(reads, 1, reason: 'Idle backup status polls every minute');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '14',
        );
        await tester.ensureVisible(find.text('Back up now'));
        await tester.tap(find.text('Back up now'));
        await tester.pumpAndSettle();
        expect(starts, 1);
        expect(find.text('Backup in progress'), findsOneWidget);
        final afterStart = reads;
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(reads, afterStart + 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump(const Duration(minutes: 2));
        expect(reads, afterStart + 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(reads, afterStart + 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final configured in [false, true]) {
    testWidgets('encryption configuration gates new backups and distinguishes older copies ($configured)', (tester) async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {
          'settings': {'enabled': false, 'time': '02:00', 'retentionDays': 7, 'revision': 'r1'},
          'encryption': {'configured': configured, 'scheme': 'age'},
          'history': [
            {'id': 'encrypted', 'status': 'succeeded', 'source': 'manual', 'sizeBytes': 100,
              'encryption': {'scheme': 'age'}, 'startedAt': '2026-11-08T00:00:00Z'},
            {'id': 'legacy', 'status': 'succeeded', 'source': 'manual', 'sizeBytes': 100,
              'startedAt': '2026-10-04T00:00:00Z'},
          ],
          'health': 'current', 'storageLocation': 'private backups',
        }));
      }));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SystemBackupsPage())));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Back up now')).onPressed != null, configured);
      expect(find.text(configured ? 'Encryption: ready' : 'Encryption: setup required'), findsOneWidget);
      await tester.ensureVisible(find.text('Not encrypted · older backup'));
      expect(find.text('Encrypted · age'), findsOneWidget);
      expect(find.text('Not encrypted · older backup'), findsOneWidget);
      expect(find.text('Off-server copy: not verified'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      ApiClient.instance.dio.interceptors.clear();
    });
  }
}
