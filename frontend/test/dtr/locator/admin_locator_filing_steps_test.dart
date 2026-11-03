import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/admin_locator_filing_dialog.dart';

const alice = '11111111-1111-4111-8111-111111111111';
const bob = '22222222-2222-4222-8222-222222222222';
const employees = [
  {'id': alice, 'full_name': 'Alice', 'department_name': 'HR'},
  {'id': bob, 'full_name': 'Bob', 'department_name': 'Accounting'},
];

class _AttachmentPicker extends FilePicker {
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
      name: 'support.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}

class _Signatures extends DocuTrackerProvider {
  int loads = 0;
  @override
  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async {
    loads++;
    return [
      DocuTrackerSignatureAsset(
        id: 'saved-approval',
        ownerUserId: 'encoder',
        mimeType: 'image/png',
        sourceType: 'uploaded',
        isSaved: true,
        imageBytes: Uint8List(0),
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  var validationFails = false;
  var unavailable = false;
  var posts = 0;
  var canReview = false;
  setUp(() {
    requests.clear();
    validationFails = false;
    unavailable = false;
    posts = 0;
    canReview = false;
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add(o);
          dynamic data;
          if (o.uri.path.endsWith('/filing-employees')) {
            if (o.queryParameters['employee_ids'] != null) {
              if (validationFails) {
                h.reject(DioException(requestOptions: o));
                return;
              }
              data = {
                'employees': unavailable ? [employees.first] : employees,
                'total': unavailable ? 1 : 2,
              };
            } else {
              final search = o.queryParameters['search'];
              data = {
                'employees': search == 'Bob' ? [employees.last] : employees,
                'total': search == 'Bob' ? 1 : 2,
              };
            }
          } else if (o.uri.path.endsWith('/final-reviewer/me')) {
            data = {'can_review': canReview};
          } else {
            posts++;
            final ids =
                jsonDecode(
                      Map.fromEntries(
                        (o.data as FormData).fields,
                      )['employee_ids']!,
                    )
                    as List;
            data = {
              'results': [
                for (final id in ids)
                  {
                    'employee_id': id,
                    if (id == bob && posts == 1)
                      'error': 'No working shift'
                    else
                      'request': {'status': 'pending_department_head'},
                  },
              ],
            };
          }
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> mount(
    WidgetTester t,
    double width, {
    LocatorRequestType type = LocatorRequestType.locator,
    Widget Function(Widget)? wrap,
  }) async {
    t.view.physicalSize = Size(width, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Widget app = MaterialApp(
      home: AdminLocatorFilingDialog(requestTypes: [type]),
    );
    if (wrap != null) app = wrap(app);
    await t.pumpWidget(app);
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).last);
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> details(WidgetTester t) async {
    await t.enterText(
      find.byKey(const ValueKey('locator-filing-destination')),
      'Municipal Hall',
    );
    await t.enterText(
      find.byKey(const ValueKey('locator-filing-reason')),
      'Official transaction',
    );
    await tap(t, 'AM IN');
    await tap(t, 'AM OUT');
  }

  Future<void> changeDate(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('locator-filing-date')));
    await t.pumpAndSettle();
    final picker = t.element(find.byType(DatePickerDialog));
    Navigator.of(picker).pop(DateTime.now().add(const Duration(days: 1)));
    await t.pumpAndSettle();
  }

  for (final width in [900.0, 390.0]) {
    testWidgets(
      'staff filing selects employees, preserves edits and retries only failures at $width',
      (t) async {
        await mount(t, width);
        expect(find.text('Step 1 of 3 • Employees'), findsOneWidget);
        expect(find.textContaining('Locator date: '), findsOneWidget);
        expect(
          find.text('Employees are listed based on the selected date.'),
          findsOneWidget,
        );
        expect(find.textContaining('Available on '), findsNothing);
        expect(find.text('Close'), findsNothing);
        expect(find.byTooltip('Close filing'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('locator-filing-destination')),
          findsNothing,
        );
        await tap(t, 'Continue');
        expect(find.text('Select at least one employee.'), findsOneWidget);
        await tap(t, 'Select loaded employees (up to 100)');
        await tap(t, 'Continue');
        expect(find.text('Step 2 of 3 • Request details'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
        expect(find.byTooltip('Close filing'), findsOneWidget);
        await details(t);
        await tap(t, 'Review requests');
        expect(find.text('Step 3 of 3 • Review and submit'), findsOneWidget);
        expect(find.text('Municipal Hall'), findsOneWidget);
        expect(find.text('Official transaction'), findsOneWidget);
        expect(posts, 0);
        await tap(t, 'Back');
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('locator-filing-destination')),
              )
              .controller!
              .text,
          'Municipal Hall',
        );
        await tap(t, 'Change employees');
        expect(find.text('2 selected · 2 of 2 employees'), findsOneWidget);
        await tap(t, 'Continue');
        await tap(t, 'Review requests');
        await tap(t, 'File requests');
        expect(
          find.text('1 request filed successfully · 1 failed'),
          findsOneWidget,
        );
        expect(find.text('No working shift'), findsOneWidget);
        await tap(t, 'Retry failed requests');
        expect(
          find.text('1 request filed successfully · 0 failed'),
          findsOneWidget,
        );
        final submitted = requests.where((r) => r.method == 'POST').toList();
        expect(submitted, hasLength(2));
        expect(
          jsonDecode(
            Map.fromEntries(
              (submitted[0].data as FormData).fields,
            )['employee_ids']!,
          ),
          [alice, bob],
        );
        expect(
          jsonDecode(
            Map.fromEntries(
              (submitted[1].data as FormData).fields,
            )['employee_ids']!,
          ),
          [bob],
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'search keeps selected employees that are absent from search results',
    (t) async {
      await mount(t, 900);
      await tap(t, 'Alice');
      await t.enterText(
        find.byKey(const ValueKey('locator-filing-search')),
        'Bob',
      );
      await tap(t, 'Search');
      await tap(t, 'Bob');
      await tap(t, 'Continue');
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    },
  );

  testWidgets(
    'date changes revalidate selected IDs and explain unavailable employees',
    (t) async {
      await mount(t, 900);
      await tap(t, 'Select loaded employees (up to 100)');
      await tap(t, 'Continue');
      await details(t);
      unavailable = true;
      await changeDate(t);
      final validation = requests.lastWhere(
        (r) => r.queryParameters['employee_ids'] != null,
      );
      expect(jsonDecode(validation.queryParameters['employee_ids'] as String), [
        alice,
        bob,
      ]);
      expect(find.textContaining('Bob is unavailable'), findsOneWidget);
      await tap(t, 'Review requests');
      expect(posts, 0);
      expect(find.text('Step 2 of 3 • Request details'), findsOneWidget);
      await tap(t, 'Change employees');
      await t.tap(find.byTooltip('Remove Bob'));
      await t.pumpAndSettle();
      await tap(t, 'Continue');
      await tap(t, 'Review requests');
      expect(find.text('Step 3 of 3 • Review and submit'), findsOneWidget);
      expect(find.text('Municipal Hall'), findsOneWidget);
    },
  );

  testWidgets('availability check failures block review until retry succeeds', (
    t,
  ) async {
    await mount(t, 900);
    await tap(t, 'Alice');
    await tap(t, 'Continue');
    await details(t);
    validationFails = true;
    await changeDate(t);
    expect(
      find.textContaining('Unable to check selected employees'),
      findsOneWidget,
    );
    await tap(t, 'Review requests');
    expect(find.text('Step 3 of 3 • Review and submit'), findsNothing);
    validationFails = false;
    await tap(t, 'Retry availability check');
    await tap(t, 'Review requests');
    expect(find.text('Step 3 of 3 • Review and submit'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets(
    'required attachments survive Back and are uploaded only after review',
    (t) async {
      FilePicker.platform = _AttachmentPicker();
      await mount(
        t,
        900,
        type: LocatorRequestType.locator.copyWith(requiresAttachment: true),
      );
      await tap(t, 'Alice');
      await tap(t, 'Continue');
      await details(t);
      await tap(t, 'Review requests');
      expect(find.text('Upload the required attachment.'), findsOneWidget);
      expect(posts, 0);
      await tap(t, 'Upload required attachment');
      await tap(t, 'Review requests');
      expect(find.text('support.pdf'), findsOneWidget);
      await tap(t, 'Back');
      expect(find.text('support.pdf'), findsOneWidget);
      await tap(t, 'Review requests');
      await tap(t, 'File requests');
      final data =
          requests.singleWhere((r) => r.method == 'POST').data as FormData;
      expect(data.files.single.value.filename, 'support.pdf');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'auto-approval asks for a signature only at final submission and respects cancellation',
    (t) async {
      canReview = true;
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(id: 'encoder', email: 'encoder@test.local', role: 'hr'),
        );
      final signatures = _Signatures();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        signatures.dispose();
      });
      await mount(
        t,
        900,
        type: LocatorRequestType.locator.copyWith(autoApproveAdmin: true),
        wrap: (child) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider<DocuTrackerProvider>.value(
              value: signatures,
            ),
          ],
          child: child,
        ),
      );
      await tap(t, 'Alice');
      await tap(t, 'Continue');
      await details(t);
      await tap(t, 'Review requests');
      expect(signatures.loads, 0);
      expect(posts, 0);
      await tap(t, 'File requests');
      expect(find.text('Sign and Approve'), findsOneWidget);
      await tap(t, 'Cancel');
      expect(posts, 0);
      expect(find.text('Step 3 of 3 • Review and submit'), findsOneWidget);
      await tap(t, 'File requests');
      await tap(t, 'Saved');
      await tap(t, 'Use signature');
      final fields = Map.fromEntries(
        (requests.singleWhere((r) => r.method == 'POST').data as FormData)
            .fields,
      );
      expect(
        jsonDecode(fields['signature']!)['signature_asset_id'],
        'saved-approval',
      );
      expect(t.takeException(), isNull);
    },
  );
}
