import 'dart:convert';
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
    LeaveTypeDefinitionCache.instance.invalidate();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path.startsWith('/api/leave/print/types/') ||
              options.path.startsWith('/api/leave/routing/types/')) {
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
  }

  Future<void> enterRequiredName(
    WidgetTester tester,
    String displayName,
  ) async {
    await tester.enterText(textField('Leave type name'), displayName);
    await tester.pump();
  }

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
      'Approval routing',
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
        expect(find.text('Destination'), findsWidgets);
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
