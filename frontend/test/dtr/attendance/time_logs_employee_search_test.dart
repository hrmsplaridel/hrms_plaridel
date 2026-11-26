import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/shared/pages/dtr_time_logs_content.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/searchable_dropdown_field.dart';

Map<String, dynamic> _record(String id, String userId, String name) => {
  'id': id,
  'user_id': userId,
  'employee_name': name,
  'record_date': DateTime.now().toIso8601String().substring(0, 10),
  'status': 'present',
};

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  test('employee filter labels stay unique when names repeat', () {
    final labels = timeLogEmployeeFilterLabels(const [
      EmployeeOption(id: 'a', fullName: 'Maria Cruz', employeeNumber: 12),
      EmployeeOption(id: 'b', fullName: 'Maria Cruz', employeeNumber: 40),
      EmployeeOption(id: 'c', fullName: 'Ben Santos', employeeNumber: 7),
    ]);
    expect(labels, {
      'Maria Cruz (#12)': 'a',
      'Maria Cruz (#40)': 'b',
      'Ben Santos': 'c',
    });
  });

  testWidgets(
    'choosing an employee loads their logs from every page, not just page 1',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final recordRequests = <Map<String, dynamic>>[];
      final dio = ApiClient.instance.dio;
      dio.interceptors.clear();
      addTearDown(dio.interceptors.clear);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            dynamic data = <dynamic>[];
            final headers = <String, List<String>>{};
            if (options.path == '/api/employees') {
              data = [
                {'id': 'ana', 'full_name': 'Ana Reyes'},
                {'id': 'ben', 'full_name': 'Ben Santos'},
              ];
            } else if (options.path == '/api/dtr-daily-summary') {
              recordRequests.add(Map.of(options.queryParameters));
              final forBen = options.queryParameters['employee_id'] == 'ben';
              // Page 1 of everyone holds only Ana; Ben is on a later page.
              data = forBen
                  ? [_record('r2', 'ben', 'Ben Santos')]
                  : [_record('r1', 'ana', 'Ana Reyes')];
              headers['x-total-count'] = [forBen ? '1' : '300'];
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: data,
                headers: Headers.fromMap(headers),
              ),
            );
          },
        ),
      );

      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(id: 'admin', email: 'admin@test.local', role: 'admin'),
        );
      final dtr = DtrProvider();
      addTearDown(auth.dispose);
      addTearDown(dtr.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider<DtrProvider>.value(value: dtr),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DtrTimeLogsContent()),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The page-only "Search name..." box is gone.
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Search name...',
        ),
        findsNothing,
      );
      expect(find.text('Ana Reyes'), findsWidgets);
      expect(find.text('Ben Santos'), findsNothing);

      final employeeField = find.byType(SearchableDropdownField);
      expect(employeeField, findsOneWidget);
      await tester.enterText(
        find.descendant(of: employeeField, matching: find.byType(TextField)),
        'Ben',
      );
      await tester.pump();
      await tester.tap(find.text('Ben Santos').last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final last = recordRequests.last;
      expect(last['employee_id'], 'ben');
      expect(last['offset'], 0);
      expect(find.text('Ana Reyes'), findsNothing);
      expect(find.text('Ben Santos'), findsWidgets);
    },
  );
}
