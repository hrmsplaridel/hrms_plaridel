import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/admin_locator_filing_dialog.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/shared/widgets/locator_paper_record_notice.dart';

class _Picker extends FilePicker {
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
      name: 'signed-original.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'paper locator details distinguish the approving official from the HR encoder',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocatorPaperRecordNotice(
              record: {
                'original_filing_date': '2026-09-01',
                'approval_date': '2026-09-02',
                'final_approver': {'name': 'Original Mayor'},
                'encoded_by_name': 'HR Encoder',
              },
              reconciliationRequired: true,
            ),
          ),
        ),
      );
      expect(find.text('Approved by: Original Mayor'), findsOneWidget);
      expect(find.text('Encoded by: HR Encoder'), findsOneWidget);
      expect(find.textContaining('Reconcile the month'), findsOneWidget);
    },
  );
  for (final width in [900.0, 390.0]) {
    testWidgets(
      'approved paper locator records one employee with signed evidence at $width',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        FilePicker.platform = _Picker();
        final posts = <RequestOptions>[];
        final gets = <RequestOptions>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.method == 'GET') gets.add(o);
              dynamic data = <dynamic>[];
              if (o.path.endsWith('/filing-employees')) {
                data = {
                  'employees': [
                    {
                      'id': '11111111-1111-4111-8111-111111111111',
                      'full_name': 'Alice',
                    },
                    {
                      'id': '22222222-2222-4222-8222-222222222222',
                      'full_name': 'Bob',
                    },
                  ],
                  'total': 2,
                };
              }
              if (o.path.endsWith('/paper-signatories')) {
                data = {
                  'final_approver': width == 900
                      ? [
                          {
                            'user_id': '33333333-3333-4333-8333-333333333333',
                            'name': 'Configured Mayor',
                            'position_title': 'Municipal Mayor',
                            'reviewer_role': 'primary',
                            'has_saved_signature': true,
                          },
                        ]
                      : [],
                  'department_reviewer': [],
                  'warnings': [],
                };
              }
              if (o.method == 'POST') {
                posts.add(o);
                data = {
                  'id': 'record',
                  'status': 'approved',
                  'paper_approval_record': {'source': 'approved_paper'},
                };
              }
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: o.method == 'POST' ? 201 : 200,
                  data: data,
                ),
              );
            },
          ),
        );
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminLocatorFilingDialog(
                        requestTypes: [LocatorRequestType.locator],
                        approvedPaper: true,
                      ),
                    ),
                  ),
                  child: const Text('Open paper locator'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open paper locator'));
        await t.pumpAndSettle();
        Future<void> tap(String text) async {
          await t.ensureVisible(find.text(text).last);
          await t.tap(find.text(text).last);
          await t.pumpAndSettle();
        }

        expect(find.text('Record approved paper locator'), findsOneWidget);
        expect(find.text('Select loaded employees (up to 100)'), findsNothing);
        expect(find.text('Select an employee'), findsOneWidget);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.textContaining('Locator date:'), findsNothing);
        expect(find.text('Continue'), findsNothing);
        expect(
          gets.where((o) => o.path.endsWith('/final-reviewer/me')),
          isEmpty,
        );
        final directory = gets.singleWhere(
          (o) => o.path.endsWith('/filing-employees'),
        );
        expect(directory.queryParameters['paper'], 'true');
        expect(directory.queryParameters.containsKey('slip_date'), false);
        await tap('Alice');
        expect(find.text('Step 2 of 3 • Locator details'), findsOneWidget);
        expect(find.text('Locator Details'), findsOneWidget);
        await t.tap(find.byTooltip('Back to employee selection'));
        await t.pumpAndSettle();
        await tap('Bob');
        expect(find.text('Selected employees (1)'), findsNothing);
        await t.enterText(
          find.byKey(const ValueKey('locator-filing-destination')),
          'Municipal Hall',
        );
        await t.enterText(
          find.byKey(const ValueKey('locator-filing-reason')),
          'Official business',
        );
        await t.enterText(
          find.byKey(const ValueKey('locator-paper-original-date')),
          '2026-09-01',
        );
        await tap('AM IN');
        await tap('Continue to paper approval');
        expect(find.text('Original Paper Approval'), findsOneWidget);
        expect(find.text('Step 3 of 3 • Paper approval'), findsOneWidget);
        expect(
          find.textContaining('Each employee receives a separate request'),
          findsNothing,
        );
        expect(find.text('Signed original • Required'), findsOneWidget);
        await t.ensureVisible(
          find.byKey(const ValueKey('locator-paper-approval-date')),
        );
        await t.enterText(
          find.byKey(const ValueKey('locator-paper-approval-date')),
          '2026-09-02',
        );
        await t.pumpAndSettle();
        await tap('Record approved locator');
        expect(posts, isEmpty);
        await t.ensureVisible(
          find.byKey(const ValueKey('paper-final_approver-picker')),
        );
        await t.tap(find.byKey(const ValueKey('paper-final_approver-picker')));
        await t.pumpAndSettle();
        if (width == 900) {
          await tap('Configured Mayor · Primary');
          expect(
            t
                .widget<TextFormField>(
                  find.byKey(const ValueKey('paper-final_approver-name')),
                )
                .controller!
                .text,
            'Configured Mayor',
          );
        } else {
          await tap('Other signatory');
          await t.enterText(
            find.byKey(const ValueKey('paper-final_approver-name')),
            'Original Mayor',
          );
          await t.enterText(
            find.byKey(const ValueKey('paper-final_approver-title')),
            'Municipal Mayor',
          );
        }
        await tap('Upload signed original');
        await t.tap(find.byTooltip('Back to locator details'));
        await t.pumpAndSettle();
        await tap('Continue to paper approval');
        expect(find.text('signed-original.pdf'), findsWidgets);
        await t.ensureVisible(
          find.byKey(const ValueKey('locator-paper-complete')),
        );
        await t.tap(find.byKey(const ValueKey('locator-paper-complete')));
        await t.pumpAndSettle();
        await t.ensureVisible(
          find.byKey(const ValueKey('locator-paper-not-recorded')),
        );
        await t.tap(find.byKey(const ValueKey('locator-paper-not-recorded')));
        await t.pumpAndSettle();
        await tap('Record approved locator');
        expect(posts, hasLength(1));
        expect(posts.single.path, '/api/locator-slips/admin/approved-paper');
        final form = posts.single.data as FormData,
            fields = Map.fromEntries((posts.single.data as FormData).fields);
        expect(fields['employee_id'], '22222222-2222-4222-8222-222222222222');
        expect(fields.containsKey('signature'), false);
        expect(form.files.single.value.filename, 'signed-original.pdf');
        final paper = jsonDecode(fields['paper_approval']!) as Map;
        expect(
          paper['final_approver']['name'],
          width == 900 ? 'Configured Mayor' : 'Original Mayor',
        );
        expect(
          paper['final_approver']['user_id'],
          width == 900 ? '33333333-3333-4333-8333-333333333333' : isNull,
        );
        expect(paper['approval_date'], '2026-09-02');
        expect(paper['confirmed_complete'], true);
        expect(find.text('Open paper locator'), findsOneWidget);
        expect(
          find.text('Original Paper Approval'),
          findsNothing,
          reason: 'Successful recording closes the paper panel, like Leave',
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
