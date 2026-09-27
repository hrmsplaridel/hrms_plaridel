import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/pages/leave_type_management_screen.dart';

void main() {
  final requests = <RequestOptions>[];
  var rows = <Map<String, dynamic>>[];
  var rejectWrite = false;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
  });

  setUp(() {
    requests.clear();
    rows = [];
    rejectWrite = false;
    LeaveTypeDefinitionCache.instance.invalidate();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.method == 'GET' && options.path == '/api/leave/types') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: rows,
              ),
            );
            return;
          }
          if ((options.method == 'POST' || options.method == 'PUT') &&
              (options.path == '/api/leave/types' ||
                  options.path.startsWith('/api/leave/types/'))) {
            if (rejectWrite) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 409,
                    data: {'error': 'Leave type key already exists'},
                  ),
                ),
              );
              return;
            }
            final data = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 201 : 200,
                data: {
                  ...data,
                  'id': options.method == 'POST'
                      ? '11111111-1111-4111-8111-111111111111'
                      : options.path.split('/').last,
                  'is_system': false,
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 404,
              ),
            ),
          );
        },
      ),
    );
  });

  tearDown(() {
    LeaveTypeDefinitionCache.instance.invalidate();
    ApiClient.instance.dio.interceptors.clear();
  });

  Finder textField(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

  Finder stringDropdown(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
  );

  Finder formScrollable() => find
      .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
      .first;

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaveTypeManagementScreen())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterRequiredName(
    WidgetTester tester,
    String displayName,
  ) async {
    await tester.enterText(textField('Leave type name'), displayName);
    await tester.pump();
  }

  testWidgets('invalid numeric rules block creation before the API call', (
    tester,
  ) async {
    await mount(tester);
    await enterRequiredName(tester, 'Bereavement Leave');
    await tester.enterText(textField('Minimum advance days'), '1.5');
    await tester.enterText(textField('Max working days'), '-1');

    await tester.tap(find.text('Create Leave Type'));
    await tester.pump();

    expect(
      find.text('Minimum advance days must be a whole number'),
      findsOneWidget,
    );
    expect(
      find.text('Maximum working days must be greater than 0'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });

  testWidgets(
    'valid creation sends eligibility, threshold, and custom fields',
    (tester) async {
      await mount(tester);
      await enterRequiredName(tester, 'Bereavement Leave');
      await tester.enterText(textField('Minimum advance days'), '0');
      await tester.enterText(textField('Max working days'), '5.5');

      tester
          .widget<DropdownButtonFormField<String>>(
            stringDropdown('Employee sex eligibility'),
          )
          .onChanged!('female');
      await tester.tap(find.text('Require attachment'));
      await tester.pump();
      await tester.enterText(textField('Require attachment over days'), '2');

      await tester.scrollUntilVisible(
        find.text('Add field'),
        300,
        scrollable: formScrollable(),
      );
      await tester.tap(find.text('Add field'));
      await tester.pump();
      await tester.scrollUntilVisible(
        textField('Field label'),
        200,
        scrollable: formScrollable(),
      );
      await tester.enterText(textField('Field label'), 'Relationship');
      await tester.pump();

      await tester.tap(find.text('Create Leave Type'));
      await tester.pumpAndSettle();

      final post = requests.singleWhere((request) => request.method == 'POST');
      final data = Map<String, dynamic>.from(post.data as Map);
      expect(data['name'], 'bereavementLeave');
      expect(data['max_days'], 5.5);
      expect(data['minimum_advance_days'], 0);
      expect(data['requires_attachment'], true);
      expect(data['requires_attachment_when_over_days'], 2.0);
      expect(data['sex_eligibility'], 'female');
      expect(data['employee_detail_schema'], [
        {
          'key': 'custom_relationship',
          'label': 'Relationship',
          'type': 'text',
          'required': false,
          'max_length': 255,
        },
      ]);
      expect(find.text('Leave type added.'), findsOneWidget);
    },
  );

  testWidgets('editing a custom type sends PUT and preserves its system code', (
    tester,
  ) async {
    rows = [
      {
        'id': '22222222-2222-4222-8222-222222222222',
        'name': 'bereavementLeave',
        'display_name': 'Bereavement Leave',
        'is_active': true,
        'is_system': false,
        'employee_can_file': true,
        'admin_only': false,
        'allows_past_dates': true,
        'requires_attachment': false,
        'affects_dtr_normally': true,
        'balance_ledger_type': 'none',
        'entitlement_basis': 'per_request',
        'sex_eligibility': 'any',
        'employee_detail_schema': <dynamic>[],
      },
    ];
    await mount(tester);
    await tester.enterText(
      textField('Leave type name'),
      'Bereavement and Funeral Leave',
    );

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    final put = requests.singleWhere((request) => request.method == 'PUT');
    expect(put.path, '/api/leave/types/22222222-2222-4222-8222-222222222222');
    final data = Map<String, dynamic>.from(put.data as Map);
    expect(data['name'], 'bereavementLeave');
    expect(data['display_name'], 'Bereavement and Funeral Leave');
    expect(find.text('Leave type updated.'), findsOneWidget);
  });

  testWidgets('duplicate-key API error is shown without adding an item', (
    tester,
  ) async {
    rejectWrite = true;
    await mount(tester);
    await enterRequiredName(tester, 'Bereavement Leave');

    await tester.tap(find.text('Create Leave Type'));
    await tester.pumpAndSettle();

    expect(find.text('Leave type key already exists'), findsOneWidget);
    expect(find.text('0 leave types'), findsOneWidget);
  });
}
