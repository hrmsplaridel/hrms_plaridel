import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/dtr_access_page.dart';

void main() {
  final writes = <Map<String, dynamic>>[];
  final accountWrites = <bool>[];
  var rejectSave = false;
  var rejectAccountSave = false;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
  });

  setUp(() {
    writes.clear();
    accountWrites.clear();
    rejectSave = false;
    rejectAccountSave = false;
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
          if (options.method == 'GET' &&
              options.path == '/api/account-creation-access') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'admins': [
                    {'id': 'admin-1', 'allowed': false},
                  ],
                },
              ),
            );
            return;
          }
          if (options.method == 'PUT' &&
              options.path == '/api/account-creation-access/admin-1') {
            accountWrites.add((options.data as Map)['allowed'] == true);
            if (rejectAccountSave) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 500,
                    data: {'error': 'Save failed'},
                  ),
                ),
              );
            } else {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  data: {'allowed': accountWrites.last},
                ),
              );
            }
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
    expect(find.byType(CheckboxListTile), findsNWidgets(8));

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

  testWidgets(
    'account creation and DTR access share one compact administrator card',
    (tester) async {
      await openPage(tester);
      expect(find.text('Manage Access'), findsOneWidget);
      expect(find.text('Account creation'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(CheckboxListTile), findsNWidgets(8));

      await tester.tap(find.text('Account creation'));
      await tester.pumpAndSettle();
      expect(accountWrites, [true]);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Account creation'),
            )
            .value,
        isTrue,
      );
      expect(writes, isEmpty);
    },
  );

  testWidgets('failed account creation save leaves its checkbox unchanged', (
    tester,
  ) async {
    rejectAccountSave = true;
    await openPage(tester);
    await tester.tap(find.text('Account creation'));
    await tester.pumpAndSettle();
    expect(accountWrites, [true]);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Account creation'),
          )
          .value,
      isFalse,
    );
    expect(find.textContaining('Save failed'), findsOneWidget);
  });

  testWidgets('accordion keeps one rounded border during opening and closing', (
    tester,
  ) async {
    await openPage(tester);
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(tile.shape, isA<RoundedRectangleBorder>());
    expect(tile.collapsedShape, tile.shape);
    expect(tile.clipBehavior, Clip.antiAlias);
    await tester.tap(find.text('Admin User'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
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
