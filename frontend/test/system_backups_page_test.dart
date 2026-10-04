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
        var running = false;
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
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
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '14');
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '14',
        );
        await tester.ensureVisible(find.text('Back up now'));
        await tester.tap(find.text('Back up now'));
        await tester.pumpAndSettle();
        expect(starts, 1);
        expect(find.text('Backup in progress'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
