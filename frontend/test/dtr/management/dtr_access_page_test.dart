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
  var rejectConflict = false;
  var revision = 'r1';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
  });

  setUp(() {
    writes.clear();
    accountWrites.clear();
    rejectSave = false;
    rejectAccountSave = false;
    rejectConflict = false;
    revision = 'r1';
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
                      'revision': revision,
                      'full_name': 'Admin User',
                      'email': 'admin@test.com',
                      'is_active': true,
                      'reports_allowed': true,
                      'manage_allowed': false,
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
          if (options.method == 'GET' && options.path == '/api/rsp-access') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'admins': [
                    {
                      'id': 'admin-1',
                      'revision': 'rsp-r1',
                      'vacancies_allowed': true,
                      'recruitment_allowed': true,
                      'exams_allowed': false,
                      'forms_allowed': true,
                      'applications_allowed': true,
                      'exam_results_allowed': true,
                      'scheduling_allowed': false,
                      'final_requirements_allowed': true,
                      'form_bi_allowed': true,
                      'form_applicants_profile_allowed': false,
                      'form_selection_lineup_allowed': true,
                      'form_computation_of_points_allowed': false,
                      'form_work_experience_allowed': false,
                      'form_turn_around_time_allowed': false,
                      'form_ojt_allowed': false,
                    },
                  ],
                },
              ),
            );
            return;
          }
          if (options.method == 'GET' && options.path == '/api/ld-access') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'admins': [
                    {
                      'id': 'admin-1',
                      'revision': 'ld-r1',
                      'forms_allowed': true,
                      'daily_reports_allowed': false,
                      'requirements_allowed': true,
                      'form_tna_allowed': true,
                      'form_action_brainstorming_allowed': false,
                      'form_idp_allowed': true,
                      'form_lap_allowed': false,
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
            if (rejectConflict) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'code': 'DTR_ACCESS_CONFLICT',
                      'error':
                          'Permissions have changed. Refresh and review them before saving.',
                    },
                  ),
                ),
              );
              return;
            }
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
                  data: {...writes.last, 'revision': revision = 'r2'},
                ),
              );
            }
            return;
          }
          if (options.method == 'PUT' &&
              (options.path == '/api/rsp-access/admin-1' ||
                  options.path == '/api/ld-access/admin-1')) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  ...Map<String, dynamic>.from(options.data as Map),
                  'revision': 'module-r2',
                },
              ),
            );
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

  testWidgets('back navigation preserves drafts until discard is confirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: DtrAccessPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin User'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage DTR logs'));
    await tester.pump();
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and leave'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(DtrAccessPage), findsNothing);
    expect(writes, isEmpty);
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    // Tall enough for the expanded granular RSP/L&D permission groups.
    tester.view.physicalSize = const Size(1200, 1800);
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

  Future<void> tapSavePermissions(WidgetTester tester) async {
    final save = find.text('Save permissions');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
  }

  testWidgets('drafts multiple permissions and saves them together', (
    tester,
  ) async {
    await openPage(tester);
    // Account creation keeps CheckboxListTile; module features use keyed tiles.
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.byKey(const ValueKey('access_perm_manage_allowed')), findsOneWidget);
    expect(find.byKey(const ValueKey('access_perm_applications_allowed')), findsOneWidget);
    expect(find.byKey(const ValueKey('access_perm_form_tna_allowed')), findsOneWidget);
    expect(find.text('DTR corrections'), findsNothing);
    expect(find.text('Recruitment Management'), findsOneWidget);
    expect(find.text('Applications'), findsOneWidget);
    expect(find.text('Training Need Analysis'), findsOneWidget);

    await tester.tap(find.text('Manage DTR logs'));
    await tester.tap(find.text('Employee profiles'));
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);
    expect(writes, isEmpty);

    await tapSavePermissions(tester);
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single['manage_allowed'], isTrue);
    expect(writes.single['expected_revision'], 'r1');
    expect(writes.single['employees_allowed'], isTrue);
    expect(writes.single['leave_allowed'], isTrue);
    expect(find.text('Unsaved'), findsNothing);
    expect(find.text('DTR permissions saved.'), findsOneWidget);
    await tester.tap(find.text('Employee profiles'));
    await tester.pump();
    await tapSavePermissions(tester);
    await tester.pumpAndSettle();
    expect(writes.last['expected_revision'], 'r2');
  });

  testWidgets(
    'leaving prompts only for unsaved drafts and preserves cancelled edits',
    (tester) async {
      await openPage(tester);
      final state = tester.state<DtrAccessPageState>(
        find.byType(DtrAccessPage),
      );
      expect(await state.confirmLeave(), isTrue);
      await tester.tap(find.text('Manage DTR logs'));
      await tester.pump();
      final cancelled = state.confirmLeave();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(await cancelled, isFalse);
      expect(find.text('Unsaved'), findsOneWidget);
      final discarded = state.confirmLeave();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and leave'));
      await tester.pumpAndSettle();
      expect(await discarded, isTrue);
      expect(writes, isEmpty);
      await tapSavePermissions(tester);
      await tester.pumpAndSettle();
      expect(await state.confirmLeave(), isTrue);
      expect(find.text('Discard unsaved changes?'), findsNothing);
    },
  );

  testWidgets('stale save retains draft and offers an explicit refresh', (
    tester,
  ) async {
    rejectConflict = true;
    await openPage(tester);
    await tester.tap(find.text('Manage DTR logs'));
    await tester.pump();
    await tapSavePermissions(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    expect(find.textContaining('Permissions have changed'), findsOneWidget);
    expect(writes, hasLength(1));
    await tester.tap(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Refresh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets(
    'account creation and DTR access share one compact administrator card',
    (tester) async {
      await openPage(tester);
      expect(find.text('Manage Access'), findsOneWidget);
      expect(find.text('Account creation'), findsOneWidget);
      expect(find.text('DTR permissions'), findsOneWidget);
      expect(find.text('RSP permissions'), findsOneWidget);
      expect(find.text('L&D permissions'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      // Account creation checkbox + 6 DTR + 13 RSP UI + 6 L&D UI tiles
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('access_perm_'),
        ),
        findsNWidgets(25),
      );
      expect(find.text('DTR corrections'), findsNothing);

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
    await tapSavePermissions(tester);
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
      find.descendant(
        of: find.byKey(const ValueKey('access_perm_leave_allowed')),
        matching: find.byIcon(Icons.check_box_rounded),
      ),
      findsOneWidget,
    );
  });
}
