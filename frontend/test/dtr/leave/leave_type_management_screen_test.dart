import '../approvals/workflow_test_fixtures.dart';
import 'dart:convert';
import 'dart:async';
import '../locator/designer_field_test_helpers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/pages/leave_type_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_employment_eligibility_field.dart';

class _BackgroundPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'letterhead.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}

void main() {
  final requests = <RequestOptions>[];
  var rows = <Map<String, dynamic>>[];
  var rejectWrite = false;
  var rejectPrint = false;
  var rejectRouting = false;
  var rejectRoutingLoad = false;
  final routingById = <String, Map<String, dynamic>>{};
  Completer<void>? routingGate;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FilePicker.platform = _BackgroundPicker();
    ApiClient.instance.init();
  });

  setUp(() {
    requests.clear();
    rows = [];
    rejectWrite = false;
    rejectPrint = false;
    rejectRouting = false;
    rejectRoutingLoad = false;
    routingById.clear();
    routingGate = null;
    LeaveTypeDefinitionCache.instance.invalidate();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          if(options.path=='/api/approval-workflows'){handler.resolve(Response(requestOptions:options,statusCode:200,data:workflowTestCatalog));return;}
          if (options.path.startsWith('/api/leave/routing/types/')) {
            if (rejectRoutingLoad && options.method == 'GET') {
              handler.reject(DioException(requestOptions: options,
                response: Response(requestOptions: options, statusCode: 503)));
              return;
            }
            if (options.method == 'POST') await routingGate?.future;
            final id = options.path.split('/').last;
            if (rejectRouting && options.method == 'POST') {
              handler.reject(DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 503,
                  data: {'error': 'Routing service unavailable'}),
              ));
            } else {
              if (options.method == 'POST') {
                routingById[id] = Map<String, dynamic>.from(options.data as Map);
              }
              handler.resolve(Response(requestOptions: options, statusCode: 200,
                data: {'approval_workflow_id': routingById[id]?['approval_workflow_id'] ?? (routingById[id]?['approval_route']=='mayor'?'manual':'standard'),...?(routingById[id])}));
            }
            return;
          }
          if (options.path.startsWith('/api/leave/print/types/')) {
            if (rejectPrint && options.method == 'POST') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: {'error': 'Use a portrait A4 background'},
                  ),
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'layout': 'csc',
                    'approval_route': 'hr',
                    'has_background': false,
                  },
                ),
              );
            }
            return;
          }
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
    await tester.scrollUntilVisible(stringDropdown('Select workflow'),250,scrollable:formScrollable());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(textField('Leave type name'),-250,scrollable:formScrollable());
    await tester.pumpAndSettle();
  }

  Future<void> enterRequiredName(
    WidgetTester tester,
    String displayName,
  ) async {
    await tester.enterText(textField('Leave type name'), displayName);
    await tester.pump();
  }

  Future<void> changeToMayor(WidgetTester tester) async {
    await tester.scrollUntilVisible(stringDropdown('Select workflow'), 250,
      scrollable: formScrollable());
    await Scrollable.ensureVisible(tester.element(stringDropdown('Select workflow')), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(stringDropdown('Select workflow'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual Mayor signing · v1').last);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> existingType(String id, {bool system = false}) => {
    'id': id, 'name': system ? 'vacationLeave' : '${id}Leave',
    'display_name': system ? 'Vacation Leave' : '$id Leave',
    'is_system': system, 'is_active': true,
  };

  testWidgets('minimum service can be saved and restored for a custom type', (
    tester,
  ) async {
    rows = [
      {...existingType('existing'), 'minimum_service_months': 6},
    ];
    await mount(tester);
    final field = textField('Minimum months of service');
    await tester.scrollUntilVisible(field, 200, scrollable: formScrollable());
    expect(tester.widget<TextFormField>(field).controller!.text, '6');
    await tester.enterText(field, '12');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(
      requests
          .singleWhere((r) => r.method == 'PUT')
          .data['minimum_service_months'],
      12,
    );
  });

  testWidgets('annual first-year proration saves and survives scrolling', (
    tester,
  ) async {
    rows = [
      {
        ...existingType('existing'),
        'entitlement_basis': 'annual',
        'max_days': 5,
      },
    ];
    await mount(tester);
    final field = stringDropdown('First-year allowance');
    await tester.scrollUntilVisible(field, 200, scrollable: formScrollable());
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prorate by date hired (whole days)').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      textField('Leave type name'),
      -200,
      scrollable: formScrollable(),
    );
    await tester.scrollUntilVisible(field, 200, scrollable: formScrollable());
    expect(find.text('Prorate by date hired (whole days)'), findsOneWidget);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(
      requests
          .singleWhere((r) => r.method == 'PUT')
          .data['first_year_allowance'],
      'prorated',
    );
  });

  for (final system in [false, true]) {
    testWidgets('overall save persists routing edits for existing type; protected=$system', (tester) async {
      rows = [existingType('existing', system: system)];
      await mount(tester);
      await changeToMayor(tester);
      await tester.tap(find.text(system ? 'Save Eligibility' : 'Save Changes'));
      await tester.pumpAndSettle();
      final write = requests.singleWhere((r) => r.method == 'PUT');
      final routingWrites = requests.where((r) => r.method == 'POST' && r.path.startsWith('/api/leave/routing/types/')).toList();
      expect(routingWrites, hasLength(1), reason: 'Overall save must persist the routing draft');
      final routing = routingWrites.single;
      expect(routing.path, '/api/leave/routing/types/existing');
      expect(routing.data['approval_workflow_id'], 'manual');
      expect(requests.indexOf(write), lessThan(requests.indexOf(routing)));
      if (system) expect(write.data, {'eligible_employment_types': null});
      expect(find.text('Leave type updated.'), findsOneWidget);
    });
  }

  testWidgets('routing failure reports partial save and preserves routing and print drafts for retry', (tester) async {
    rows = [existingType('existing')];
    await mount(tester);
    await tester.scrollUntilVisible(stringDropdown('Form layout'), 250, scrollable: formScrollable());
    await Scrollable.ensureVisible(tester.element(stringDropdown('Form layout')), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(stringDropdown('Form layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wellness Leave form').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(stringDropdown('Select workflow'), -250, scrollable: formScrollable());
    await changeToMayor(tester);
    rejectRouting = true;
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Leave type updated, but routing could not be saved.'), findsOneWidget);
    expect(find.textContaining('Routing service unavailable'), findsOneWidget);
    expect(find.text('Leave type updated.'), findsNothing);
    expect(requests.where((r) => r.method == 'POST' && r.path.startsWith('/api/leave/print/types/')), isEmpty);
    expect(tester.widget<DropdownButtonFormField<String>>(stringDropdown('Select workflow')).initialValue, 'manual');
    rejectRouting = false;
    ScaffoldMessenger.of(tester.element(find.byType(LeaveTypeManagementScreen))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    final routingWrites = requests.where((r) => r.method == 'POST' && r.path.startsWith('/api/leave/routing/types/')).toList();
    expect(routingWrites.length, 2);
    expect(routingWrites.last.data['approval_workflow_id'], 'manual');
    final print = requests.singleWhere((r) => r.method == 'POST' && r.path.startsWith('/api/leave/print/types/'));
    expect((print.data as FormData).fields.singleWhere((f) => f.key == 'layout').value, 'wellness');
    expect(find.text('Leave type updated.'), findsOneWidget);
  });

  testWidgets('failed type update never attempts routing save', (tester) async {
    rows = [existingType('existing')];
    await mount(tester);
    await changeToMayor(tester);
    rejectWrite = true;
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text('Leave type key already exists'), findsOneWidget);
  });

  testWidgets('type settings do not display obsolete workflow employment conditions', (tester) async {
    rows=[existingType('existing')];
    routingById['existing']={'approval_workflow_id':'restricted'};
    await mount(tester);
    await tester.scrollUntilVisible(stringDropdown('Select workflow'),250,scrollable:formScrollable());
    await tester.pumpAndSettle();
    expect(find.textContaining('Applies to: permanent, casual.'),findsNothing);
    expect(find.text('Limit to employment types'),findsNothing);
    await tester.tap(find.text('Save Changes'));await tester.pumpAndSettle();
    expect(requests.where((r)=>r.method=='POST' && r.path.startsWith('/api/leave/routing/')),isEmpty);
  });

  testWidgets('unchanged routing is not overwritten when saving another type', (tester) async {
    rows = [existingType('first'), existingType('second')];
    routingById['second'] = {'approval_route': 'mayor', 'mayor_employment_types': ['permanent']};
    await mount(tester);
    await changeToMayor(tester);
    await tester.tap(find.text('second Leave').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(requests.singleWhere((r) => r.method == 'PUT').path, '/api/leave/types/second');
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    expect(routingById['second'], {'approval_route': 'mayor', 'mayor_employment_types': ['permanent']});
  });

  testWidgets('overall settings save cannot overwrite routing after routing load fails', (tester) async {
    rows = [existingType('existing')];
    rejectRoutingLoad = true;
    routingById['existing'] = {'approval_route': 'mayor', 'mayor_employment_types': ['permanent']};
    await mount(tester);
    await tester.scrollUntilVisible(stringDropdown('Select workflow'), 250,
      scrollable: formScrollable());
    await tester.pumpAndSettle();
    expect(find.text('Could not load workflow. Please retry.'), findsOneWidget);
    expect(tester.widget<DropdownButtonFormField<String>>(stringDropdown('Select workflow')).onChanged, isNull);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    expect(routingById['existing'], {'approval_route': 'mayor', 'mayor_employment_types': ['permanent']});
  });

  testWidgets('standalone routing save clears the pending overall routing save', (tester) async {
    rows = [existingType('existing')];
    await mount(tester);
    await changeToMayor(tester);
    await tester.ensureVisible(find.text('Save workflow'));
    await tester.tap(find.text('Save workflow'));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(tester.element(find.byType(LeaveTypeManagementScreen))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'POST' && r.path.startsWith('/api/leave/routing/types/')).length, 1);
  });

  testWidgets('overall save blocks routing edits, duplicate saves and switching types until complete', (tester) async {
    rows = [existingType('first'), existingType('second')];
    await mount(tester);
    await changeToMayor(tester);
    routingGate = Completer<void>();
    await tester.tap(find.text('Save Changes'));
    // Do not settle an intentionally pending request and its progress indicator.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<DropdownButtonFormField<String>>(stringDropdown('Select workflow')).onChanged, isNull);
    final saveRouting = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save workflow'));
    expect(saveRouting.onPressed, isNull);
    await tester.tap(find.text('second Leave').first);
    await tester.pump();
    expect(tester.widget<DropdownButtonFormField<String>>(stringDropdown('Select workflow')).initialValue, 'manual');
    expect(requests.where((r) => r.method == 'PUT').length, 1);
    expect(requests.where((r) => r.method == 'POST').length, 1);
    routingGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Leave type updated.'), findsOneWidget);
  });

  for (final access in ['both', 'admin', 'employee']) {
    final adminOnly = access == 'admin';
    testWidgets('filing dropdown saves access=$access', (tester) async {
      await mount(tester);
      await enterRequiredName(tester, 'Custom Filing');
      await tester.scrollUntilVisible(
        stringDropdown('Who can file'),
        250,
        scrollable: formScrollable(),
      );
      expect(find.text('Employees can file'), findsNothing);
      expect(find.text('HR/Admin only'), findsNothing);
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        stringDropdown('Who can file'),
      );
      expect(dropdown.initialValue, 'both');
      await tester.tap(stringDropdown('Who can file'));
      await tester.pumpAndSettle();
      expect(find.text('Employee only'), findsWidgets);
      await tester.tap(find.text('Employee and HR/admin').last);
      await tester.pumpAndSettle();
      dropdown.onChanged!(access);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Leave Type'));
      await tester.pumpAndSettle();
      final create = requests.singleWhere(
        (r) => r.path == '/api/leave/types' && r.method == 'POST',
      );
      final data = create.data as Map;
      expect(data['employee_can_file'], !adminOnly);
      expect(data['admin_only'], adminOnly);
      expect(data['admin_can_file'], access != 'employee');
    });
  }

  testWidgets('leave type settings use consistent bordered sections', (
    tester,
  ) async {
    await mount(tester);
    for (final title in [
      'Basic Information',
      'Filing Requirements',
      'Custom Form Fields',
      'Balance and DTR',
      'Approval workflow',
      'Printed Form',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        250,
        scrollable: formScrollable(),
      );
      final box = find.ancestor(
        of: find.text(title),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.padding == const EdgeInsets.all(16) &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(10),
        ),
      );
      expect(
        box,
        findsOneWidget,
        reason: '$title should have its own settings box',
      );
    }
  });

  testWidgets('designer-created leave field is added to form fields and saved before its layout', (tester) async {
    await mount(tester);await enterRequiredName(tester,'Custom Travel Leave');
    await tester.scrollUntilVisible(find.text('Design layout'),250,scrollable:formScrollable());
    await Scrollable.ensureVisible(tester.element(find.text('Design layout')),alignment:.5);await tester.pumpAndSettle();
    await tester.tap(find.text('Design layout'));await tester.pumpAndSettle();
    await createDesignerField(tester,'Arrival date');
    await tester.tap(find.text('Use layout'));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Arrival date'),-250,scrollable:formScrollable());
    expect(tester.widget<TextFormField>(textField('Field label')).initialValue,'Arrival date');
    await tester.tap(find.text('Create Leave Type'));await tester.pumpAndSettle();
    final saved=requests.singleWhere((r)=>r.method=='POST' && r.path=='/api/leave/types');
    final field=((saved.data as Map)['employee_detail_schema'] as List).single as Map;
    expect(field['label'],'Arrival date');expect(field['type'],'date');expect(field['required'],true);
    final print=requests.singleWhere((r)=>r.method=='POST' && r.path.startsWith('/api/leave/print/types/'));
    final layout=jsonDecode((print.data as FormData).fields.singleWhere((e)=>e.key=='print_layout').value) as Map;
    expect((layout['elements'] as List).where((e)=>e['source']=='custom:${field['key']}').length,1);
    expect(requests.indexOf(saved),lessThan(requests.indexOf(print)));
  });
  for (final failUpload in [false, true]) {
    testWidgets(
      'new type selects a background before creation; upload failure=$failUpload',
      (tester) async {
        final original = FilePicker.platform;
        FilePicker.platform = _BackgroundPicker();
        addTearDown(() => FilePicker.platform = original);
        rejectPrint = failUpload;
        await mount(tester);
        await enterRequiredName(tester, 'Custom Wellness');
        await tester.scrollUntilVisible(
          find.text('Upload background'),
          250,
          scrollable: formScrollable(),
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Upload background')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upload background'));
        await tester.pumpAndSettle();
        expect(find.text('letterhead.pdf'), findsOneWidget);
        await tester.tap(stringDropdown('Form layout'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wellness Leave form').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Leave Type'));
        await tester.pumpAndSettle();
        final creates = requests.where(
          (r) => r.path == '/api/leave/types' && r.method == 'POST',
        );
        expect(creates.length, 1);
        final upload = requests.firstWhere(
          (r) =>
              r.method == 'POST' &&
              r.path.startsWith('/api/leave/print/types/'),
        );
        expect(
          requests.indexOf(upload),
          greaterThan(requests.indexOf(creates.single)),
        );
        final data = upload.data as FormData;
        expect(
          data.fields.firstWhere((f) => f.key == 'layout').value,
          'wellness',
        );
        expect(data.files.single.value.filename, 'letterhead.pdf');
        expect(find.text('Create Leave Type'), findsNothing);
        if (failUpload) {
          expect(
            find.textContaining('Leave type created, but print settings'),
            findsOneWidget,
          );
          expect(find.text('letterhead.pdf'), findsOneWidget);
          rejectPrint = false;
          await tester.scrollUntilVisible(
            find.text('Save print settings'),
            100,
            scrollable: formScrollable(),
          );
          await Scrollable.ensureVisible(
            tester.element(find.text('Save print settings')),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save print settings'));
          await tester.pumpAndSettle();
          expect(creates.length, 1);
          expect(
            requests
                .where(
                  (r) =>
                      r.method == 'POST' &&
                      r.path.startsWith('/api/leave/print/types/'),
                )
                .length,
            2,
          );
        }
      },
    );
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
    'leave type creation sends the configured employment restriction',
    (tester) async {
      await mount(tester);
      await enterRequiredName(tester, 'Restricted Leave');
      tester
          .widget<LeaveEmploymentEligibilityField>(
            find.byType(LeaveEmploymentEligibilityField),
          )
          .onChanged(['permanent', 'contractual']);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Leave Type'));
      await tester.tap(find.text('Create Leave Type'));
      await tester.pumpAndSettle();
      final write = requests.firstWhere((request) => request.method == 'POST');
      expect((write.data as Map)['eligible_employment_types'], [
        'permanent',
        'contractual',
      ]);
    },
  );

  testWidgets('protected type saves only employment eligibility', (
    tester,
  ) async {
    rows = [
      {
        'id': 'protected',
        'name': 'vacationLeave',
        'display_name': 'Vacation Leave',
        'is_system': true,
        'is_active': true,
        'eligible_employment_types': ['permanent'],
        'sex_eligibility': 'any',
      },
    ];
    await mount(tester);
    expect(find.text('Save Eligibility'), findsOneWidget);
    tester
        .widget<LeaveEmploymentEligibilityField>(
          find.byType(LeaveEmploymentEligibilityField),
        )
        .onChanged(['permanent', 'casual']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Eligibility'));
    await tester.pumpAndSettle();
    final write = requests.firstWhere((request) => request.method == 'PUT');
    expect(write.data, {
      'eligible_employment_types': ['permanent', 'casual'],
    });
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
      await tester.ensureVisible(find.text('Require attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Require attachment'));
      await tester.pump();
      await tester.ensureVisible(textField('Require attachment over days'));
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
      for (final entry in {
        'Field instruction': 'State your actual relationship.',
        'Example input': 'Sibling (sample only).',
        'Suggested sentence template': 'The person is my [relationship].',
      }.entries) {
        await tester.ensureVisible(textField(entry.key));
        await tester.enterText(textField(entry.key), entry.value);
        await tester.pump();
      }

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
          'instruction': 'State your actual relationship.',
          'example': 'Sibling (sample only).',
          'sentence_template': 'The person is my [relationship].',
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
        'admin_can_file': false,
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
    expect(data['admin_can_file'], false);
    expect(find.text('Leave type updated.'), findsOneWidget);
  });

  testWidgets('new type restores its designed layout and background after editing fields above', (tester) async {
    await mount(tester);
    await enterRequiredName(tester, 'Wellness Leave');
    await tester.scrollUntilVisible(find.text('Design layout'), 250, scrollable: formScrollable());
    await Scrollable.ensureVisible(tester.element(find.text('Design layout')), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use layout'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Upload background'));
    await tester.tap(find.text('Upload background'));
    await tester.pumpAndSettle();
    expect(find.text('Custom designed form'), findsOneWidget);
    expect(find.text('letterhead.pdf'), findsOneWidget);

    await tester.scrollUntilVisible(textField('Leave type name'), -250, scrollable: formScrollable());
    await tester.pumpAndSettle();
    await tester.enterText(textField('Leave type name'), 'Wellness Leave Updated');
    await tester.tap(stringDropdown('Entitlement basis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annual entitlement').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Preview'), 250, scrollable: formScrollable());
    await tester.pumpAndSettle();
    expect(find.text('Custom designed form'), findsOneWidget);
    expect(find.text('Edit layout'), findsOneWidget);
    expect(find.text('letterhead.pdf'), findsOneWidget);

    await tester.tap(find.text('Create Leave Type'));
    await tester.pumpAndSettle();
    final create = requests.singleWhere((r) => r.method == 'POST' && r.path == '/api/leave/types');
    expect(create.data['display_name'], 'Wellness Leave Updated');
    expect(create.data['entitlement_basis'], 'annual');
    final print = requests.singleWhere((r) => r.method == 'POST' && r.path.startsWith('/api/leave/print/types/')).data as FormData;
    expect(print.fields.singleWhere((f) => f.key == 'layout').value, 'custom');
    expect(print.fields.singleWhere((f) => f.key == 'print_layout').value, contains('WELLNESS LEAVE'));
    expect(print.files.single.value.filename, 'letterhead.pdf');
  });

  testWidgets('scrolling alone retains the custom print selection without editing type fields', (tester) async {
    await mount(tester);
    await enterRequiredName(tester, 'Wellness Leave');
    await tester.scrollUntilVisible(find.text('Design layout'), 250, scrollable: formScrollable());
    await Scrollable.ensureVisible(tester.element(find.text('Design layout')), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use layout'));
    await tester.pumpAndSettle();
    expect(find.text('Custom designed form'), findsOneWidget);

    for (var visit = 0; visit < 2; visit++) {
      await tester.scrollUntilVisible(textField('Leave type name'), -250, scrollable: formScrollable());
      await tester.pumpAndSettle();
      // No input changes: scrolling must not depend on a parent form rebuild.
      await tester.scrollUntilVisible(find.text('Preview'), 250, scrollable: formScrollable());
      await tester.pumpAndSettle();
      expect(find.text('Custom designed form'), findsOneWidget);
      expect(find.text('Edit layout'), findsOneWidget);
      expect(tester.widget<DropdownButtonFormField<String>>(stringDropdown('Form layout')).initialValue, 'custom');
    }
    await tester.tap(find.text('Create Leave Type'));
    await tester.pumpAndSettle();
    final print = requests.singleWhere((r) => r.method == 'POST' && r.path.startsWith('/api/leave/print/types/')).data as FormData;
    expect(print.fields.singleWhere((f) => f.key == 'layout').value, 'custom');
    expect(print.fields.singleWhere((f) => f.key == 'print_layout').value, contains('WELLNESS LEAVE'));
  });

  for (final failUpload in [false, true]) {
    testWidgets(
      'new type saves a designed leave layout after creation; failure=$failUpload',
      (tester) async {
        await mount(tester);
        await enterRequiredName(tester, 'Custom Leave Form');
        await tester.scrollUntilVisible(
          find.text('Design layout'),
          250,
          scrollable: formScrollable(),
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Design layout')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Design layout'));
        await tester.pumpAndSettle();
        expect(find.text('CUSTOM LEAVE FORM'), findsWidgets);
        await tester.tap(find.text('Use layout'));
        await tester.pumpAndSettle();
        rejectPrint = failUpload;
        await tester.tap(find.text('Create Leave Type'));
        await tester.pumpAndSettle();
        expect(
          requests
              .where((r) => r.path == '/api/leave/types' && r.method == 'POST')
              .length,
          1,
        );
        final form =
            requests
                    .firstWhere(
                      (r) =>
                          r.method == 'POST' &&
                          r.path.startsWith('/api/leave/print/types/'),
                    )
                    .data
                as FormData;
        expect(
          form.fields.singleWhere((f) => f.key == 'layout').value,
          'custom',
        );
        expect(
          form.fields.singleWhere((f) => f.key == 'print_layout').value,
          contains('CUSTOM LEAVE FORM'),
        );
        if (failUpload) {
          expect(
            find.textContaining('Leave type created, but print settings'),
            findsOneWidget,
          );
          expect(find.text('Edit layout'), findsOneWidget);
          rejectPrint = false;
          await tester.scrollUntilVisible(
            find.text('Save print settings'),
            100,
            scrollable: formScrollable(),
          );
          await Scrollable.ensureVisible(
            tester.element(find.text('Save print settings')),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save print settings'));
          await tester.pumpAndSettle();
          expect(
            requests
                .where(
                  (r) => r.path == '/api/leave/types' && r.method == 'POST',
                )
                .length,
            1,
          );
          expect(
            requests
                .where(
                  (r) =>
                      r.method == 'POST' &&
                      r.path.startsWith('/api/leave/print/types/'),
                )
                .length,
            2,
          );
        }
      },
    );
  }

  for (final failPrint in [false, true]) {
    testWidgets(
      'Save Changes persists existing type custom layout and retains retry; failure=$failPrint',
      (tester) async {
        rows = [
          {
            'id': '22222222-2222-4222-8222-222222222222',
            'name': 'customLeave',
            'display_name': 'Custom Leave',
            'is_system': false,
            'employee_detail_schema': [
              {'key': 'destination', 'label': 'Destination', 'type': 'text'},
            ],
          },
        ];
        await mount(tester);
        await tester.scrollUntilVisible(
          find.text('Design layout'),
          250,
          scrollable: formScrollable(),
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Design layout')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Design layout'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Insert field'));
        await tester.pumpAndSettle();
        expect(find.text('Destination'), findsWidgets);
        await tester.ensureVisible(find.text('Destination').last);
        await tester.tap(find.text('Destination').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use layout'));
        await tester.pumpAndSettle();
        rejectPrint = failPrint;
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        final upload = requests.firstWhere(
          (r) =>
              r.method == 'POST' &&
              r.path.startsWith('/api/leave/print/types/'),
        );
        final form = upload.data as FormData;
        expect(
          form.fields.singleWhere((f) => f.key == 'layout').value,
          'custom',
        );
        expect(
          form.fields.singleWhere((f) => f.key == 'print_layout').value,
          contains('custom:destination'),
        );
        if (failPrint) {
          expect(
            find.textContaining('Leave type updated, but print settings'),
            findsOneWidget,
          );
          expect(find.text('Edit layout'), findsOneWidget);
          rejectPrint = false;
          await tester.scrollUntilVisible(
            find.text('Save print settings'),
            100,
            scrollable: formScrollable(),
          );
          await Scrollable.ensureVisible(
            tester.element(find.text('Save print settings')),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save print settings'));
          await tester.pumpAndSettle();
          expect(requests.where((r) => r.method == 'PUT').length, 1);
          expect(
            requests
                .where(
                  (r) =>
                      r.method == 'POST' &&
                      r.path.startsWith('/api/leave/print/types/'),
                )
                .length,
            2,
          );
        }
      },
    );
  }

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
