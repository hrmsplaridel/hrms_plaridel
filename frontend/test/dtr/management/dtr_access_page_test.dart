import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/dtr_access_page.dart';

void main() {
  final writes = <Map<String, dynamic>>[];
  var rejectSave = false;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
  });

  setUp(() {
    writes.clear();
    rejectSave = false;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'GET' && options.path == '/api/dtr-access') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'admins': [
                    {
                      'id': 'admin-1',
                      'full_name': 'Admin User',
                      'email': 'admin@test.com',
                      'is_active': true,
                      'reports_allowed': true,
                      'manage_allowed': false,
                      'corrections_allowed': true,
                      'employees_allowed': false,
                      'leave_allowed': true,
                      'approvals_allowed': true,
                      'locator_allowed': false,
                    },
                  ],
                },
              ),
            );
            return;
          }
          if (options.method == 'PUT' &&
              options.path == '/api/dtr-access/admin-1') {
            writes.add(Map<String, dynamic>.from(options.data as Map));
            if (rejectSave) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'error':
                          'Reassign this active reviewer before disabling leave access.',
                    },
                  ),
                ),
              );
            } else {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  data: writes.last,
                ),
              );
            }
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );
  });

  tearDownAll(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> openPage(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DtrAccessPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin User'));
    await tester.pumpAndSettle();
  }

  testWidgets('drafts multiple permissions and saves them together', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.byType(CheckboxListTile), findsNWidgets(7));

    await tester.tap(find.text('Manage DTR logs'));
    await tester.tap(find.text('Employee profiles'));
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);
    expect(writes, isEmpty);

    await tester.tap(find.text('Save permissions'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single['manage_allowed'], isTrue);
    expect(writes.single['employees_allowed'], isTrue);
    expect(writes.single['leave_allowed'], isTrue);
    expect(find.text('Unsaved'), findsNothing);
    expect(find.text('DTR permissions saved.'), findsOneWidget);
  });

  testWidgets('failed reviewer-protected save keeps draft for correction', (
    tester,
  ) async {
    rejectSave = true;
    await openPage(tester);
    await tester.tap(find.text('Leave management'));
    await tester.pump();
    await tester.tap(find.text('Save permissions'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(writes.single['leave_allowed'], isFalse);
    expect(find.text('Unsaved'), findsOneWidget);
    expect(
      find.textContaining('Reassign this active reviewer'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Unsaved'), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Leave management'),
          )
          .value,
      isTrue,
    );
  });
}
