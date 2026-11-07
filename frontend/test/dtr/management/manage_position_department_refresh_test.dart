import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/departments/pages/manage_department.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/pages/manage_position.dart';

class _WorkforceTabs extends StatefulWidget {
  const _WorkforceTabs();
  @override
  State<_WorkforceTabs> createState() => _WorkforceTabsState();
}

class _WorkforceTabsState extends State<_WorkforceTabs> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          TextButton(
            onPressed: () => setState(() => index = 0),
            child: const Text('Positions tab'),
          ),
          TextButton(
            onPressed: () => setState(() => index = 1),
            child: const Text('Departments tab'),
          ),
        ],
      ),
      IndexedStack(
        index: index,
        children: const [ManagePosition(), ManageDepartment()],
      ),
    ],
  );
}

void main() {
  var departments = <Map<String, dynamic>>[];
  var failDepartmentLoad = false;
  var holdInitialLoad = false;
  RequestOptions? heldOptions;
  RequestInterceptorHandler? heldHandler;
  var departmentReads = 0;
  Map<String, dynamic>? createdPosition;
  var positionRows = <Map<String, dynamic>>[];

  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    departments = [];
    failDepartmentLoad = false;
    holdInitialLoad = false;
    heldHandler = null;
    heldOptions = null;
    departmentReads = 0;
    createdPosition = null;
    positionRows = [];
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data;
          if (options.path == '/api/departments') {
            if (options.method == 'POST') {
              departments.add({
                'id': 'new-department',
                ...Map<String, dynamic>.from(options.data as Map),
              });
              data = departments.last;
            } else {
              departmentReads++;
              if (holdInitialLoad && departmentReads == 1) {
                heldOptions = options;
                heldHandler = handler;
                return;
              }
              if (failDepartmentLoad) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 500,
                      data: {'error': 'Department service unavailable.'},
                    ),
                  ),
                );
                return;
              }
              data = List<Map<String, dynamic>>.of(departments);
            }
          } else if (options.path == '/api/positions') {
            if (options.method == 'POST') {
              createdPosition = Map<String, dynamic>.from(options.data as Map);
              data = {'id': 'created-position'};
            } else {
              data = {
                'items': positionRows,
                'pagination': {
                  'page': 1,
                  'page_count': 1,
                  'total': positionRows.length,
                },
              };
            }
          } else if (options.path == '/api/positions/existing' &&
              options.method == 'PUT') {
            createdPosition = Map<String, dynamic>.from(options.data as Map);
            data = {'id': 'existing'};
          } else if (options.path == '/api/departments/reviewer-readiness') {
            data = {'departments': []};
          } else {
            handler.reject(DioException(requestOptions: options));
            return;
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> mount(WidgetTester tester, {bool tabs = false}) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: tabs ? const _WorkforceTabs() : const ManagePosition(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Add Position'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a department created in another cached tab is available when adding a position',
    (tester) async {
      await mount(tester, tabs: true);
      await tester.tap(find.text('Departments tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add Department'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'New Engineering Department',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add Department').last,
      );
      await tester.pumpAndSettle();
      expect(departments.single['name'], 'New Engineering Department');
      await tester.tap(find.text('Positions tab'));
      await tester.pumpAndSettle();
      await openForm(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('New Engineering Department'), findsWidgets);
      await tester.tap(find.text('New Engineering Department').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Engineering Staff',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add Position').last);
      await tester.pumpAndSettle();
      expect(createdPosition?['department_id'], 'new-department');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed department load shows a retry instead of silently empty options',
    (tester) async {
      failDepartmentLoad = true;
      await mount(tester);
      await openForm(tester);
      expect(find.textContaining('Could not load departments'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Retained title',
      );
      failDepartmentLoad = false;
      departments.add({
        'id': 'recovered',
        'name': 'Recovered department',
        'is_active': true,
      });
      await tester.tap(find.byTooltip('Refresh departments'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load departments'), findsNothing);
      expect(find.text('Retained title'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('Recovered department'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late initial department results cannot replace the fresh drawer options',
    (tester) async {
      holdInitialLoad = true;
      await mount(tester);
      departments.add({
        'id': 'new',
        'name': 'Newest department',
        'is_active': true,
      });
      await openForm(tester);
      heldHandler!.resolve(
        Response(
          requestOptions: heldOptions!,
          statusCode: 200,
          data: <dynamic>[],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('Newest department'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing reloads departments while retaining an existing inactive department',
    (tester) async {
      departments.add({
        'id': 'inactive',
        'name': 'Old department',
        'is_active': false,
      });
      positionRows.add({
        'id': 'existing',
        'name': 'Existing Staff',
        'department_id': 'inactive',
        'department_name': 'Old department',
        'is_active': true,
      });
      await mount(tester);
      departments.add({
        'id': 'new',
        'name': 'New department',
        'is_active': true,
      });
      await tester.tap(find.text('Existing Staff'));
      await tester.pumpAndSettle();
      expect(find.text('Old department (Inactive)'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('New department'), findsWidgets);
      final oldOption = tester.widget<DropdownMenuItem<String?>>(
        find
            .byWidgetPredicate(
              (w) => w is DropdownMenuItem<String?> && w.value == 'inactive',
            )
            .last,
      );
      expect(oldOption.enabled, isFalse);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      expect(createdPosition?['department_id'], 'inactive');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late initial department failure cannot hide the refreshed choices',
    (tester) async {
      holdInitialLoad = true;
      await mount(tester);
      departments.add({
        'id': 'new',
        'name': 'Newest department',
        'is_active': true,
      });
      await openForm(tester);
      heldHandler!.reject(
        DioException(
          requestOptions: heldOptions!,
          type: DioExceptionType.connectionError,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load departments'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('Newest department'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
