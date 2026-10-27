import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_filing_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request_history.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_form_signatories.dart';

const paper = {
  'source': 'approved_paper',
  'original_filing_date': '2026-09-01',
  'approval_date': '2026-09-02',
  'final_approver': {'name': 'Original Mayor', 'position_title': 'Mayor'},
  'encoded_by_name': 'HR Encoder',
};

class _PaperRepository extends MockLeaveRepository {
  @override
  Future<DateTime> getOfficialDate() async => DateTime(2026, 10, 26);
}

class _PaperPicker extends FilePicker {
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
      name: 'signed.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}

void main() {
  for (final width in [1200.0, 390.0]) {
    testWidgets(
      'paper flow selects leave before approval and preserves edits at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FilePicker.platform = _PaperPicker();
        LeaveTypeDefinitionCache.instance.invalidate();
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(id: 'encoder', email: 'hr@test.local', role: 'hr'),
          );
        final provider = LeaveProvider(repository: _PaperRepository());
        final writes = <FormData>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data = <dynamic>[];
              if (o.path == '/api/leave/admin/filing-employees') {
                data = {
                  'employees': [
                    {
                      'id': 'employee',
                      'full_name': 'Paper Employee',
                      'email': 'employee@test.local',
                      'employment_type': 'permanent',
                      'sex': 'Male',
                    },
                  ],
                  'total': 1,
                };
              } else if (o.path == '/api/leave/types') {
                data = [
                  {
                    'name': 'mandatoryForcedLeave',
                    'display_name': 'Forced Leave',
                    'admin_can_file': true,
                    'allow_approved_paper_filing': true,
                    'allows_past_dates': false,
                    'minimum_advance_days': 2,
                    'balance_ledger_type': 'none',
                    'entitlement_basis': 'per_request',
                  },
                  {
                    'name': 'vacationLeave',
                    'display_name': 'Disabled paper type',
                    'admin_can_file': true,
                    'allow_approved_paper_filing': false,
                  },
                ];
              } else if (o.path == '/api/leave/admin/working-days') {
                data = {'working_days_applied': 1};
              } else if (o.path == '/api/employees/employee') {
                data = {'full_name': 'Paper Employee'};
              } else if (o.path == '/api/leave/admin/paper-signatories') {
                if (width < 600 &&
                    o.queryParameters['approval_date'] == '2026-09-03') {
                  h.reject(
                    DioException(
                      requestOptions: o,
                      response: Response(
                        requestOptions: o,
                        statusCode: 500,
                        data: {'error': 'Suggestion lookup unavailable'},
                      ),
                      type: DioExceptionType.badResponse,
                    ),
                  );
                  return;
                }
                data = {
                  'effective_date':
                      o.queryParameters['approval_date'] ??
                      o.queryParameters['filing_date'],
                  'final_approver': [
                    {
                      'user_id': 'primary',
                      'name': 'Primary HR',
                      'position_title': 'HR Director',
                      'reviewer_role': 'primary',
                      'step_label': 'Final HR',
                    },
                    {
                      'user_id': 'backup',
                      'name': 'Backup HR',
                      'has_saved_signature': true,
                      'position_title': 'HR Officer',
                      'reviewer_role': 'backup',
                      'step_label': 'Final HR',
                    },
                  ],
                  'certification_officer': [
                    {
                      'user_id': 'certifier',
                      'name': 'Credit Certifier',
                      'has_saved_signature': true,
                      'position_title': 'Credit Officer',
                      'reviewer_role': 'primary',
                    },
                  ],
                  'department_reviewer': [
                    {
                      'user_id': 'head',
                      'name': 'Department Head',
                      'position_title': 'Department Director',
                      'reviewer_role': 'primary',
                    },
                  ],
                };
              } else if (o.path == '/api/leave/admin/file') {
                writes.add(o.data as FormData);
                data = {
                  'results': [
                    {
                      'request': {
                        'id': 'record',
                        'user_id': 'employee',
                        'status': 'approved',
                        'leave_type': 'mandatoryForcedLeave',
                      },
                    },
                  ],
                };
              }
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: data),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: provider),
            ],
            child: const MaterialApp(home: AdminLeaveFilingPanel()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paper Employee'));
        await tester.pumpAndSettle();
        expect(find.byType(LeaveRequestFormScreen), findsOneWidget);
        expect(find.text('Step 2 of 3 • Leave details'), findsOneWidget);
        expect(find.text('Original Paper Approval'), findsNothing);
        final dropdown = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>).first,
        );
        expect(dropdown.initialValue, 'mandatoryForcedLeave');
        expect(find.text('Disabled paper type'), findsNothing);
        Future<void> reveal(Finder finder) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          if (finder.evaluate().isEmpty) {
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(
            finder,
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await Scrollable.ensureVisible(
            tester.element(finder),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
        }

        final filing = find.byKey(const ValueKey('paper_original_filing_date'));
        await reveal(filing);
        await tester.enterText(filing, '2026-09-01');
        Future<void> chooseDate(String label) async {
          final picker = find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first;
          await reveal(picker);
          await tester.tap(picker);
          await tester.pumpAndSettle();
          tester
              .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
              .onDateChanged(DateTime(2026, 9, 10));
          await tester.pump();
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
        }

        await chooseDate('Start Date');
        await chooseDate('End Date');
        final reason = find.widgetWithText(
          TextFormField,
          'General Reason / Remarks (Optional)',
        );
        await reveal(reason);
        await tester.enterText(reason, 'Original paper details');
        Future<void> next() async {
          await reveal(find.text('Continue to paper approval'));
          await tester.tap(find.text('Continue to paper approval'));
          await tester.pumpAndSettle();
        }

        await next();
        expect(find.text('Step 3 of 3 • Paper approval'), findsOneWidget);
        expect(find.textContaining('Forced Leave'), findsWidgets);
        expect(writes, isEmpty);
        Future<void> enter(String key, String value) async {
          final field = find.byKey(ValueKey('paper_field_$key'));
          await reveal(field);
          await tester.enterText(field, value);
        }

        await enter('approval_date', '2026-09-02');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        Future<void> selectSigner(String group, String label) async {
          final picker = find.byKey(ValueKey('paper_signer_$group'));
          await reveal(picker);
          await tester.tap(picker);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await selectSigner('final_approver', 'Backup HR · Backup');
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('paper_field_final_name')),
              )
              .controller!
              .text,
          'Backup HR',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('paper_field_final_title')),
              )
              .controller!
              .text,
          'HR Officer',
        );
        await enter('approval_date', '2026-09-03');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        if (width < 600) {
          expect(
            find.textContaining('Unable to load signatory suggestions.'),
            findsOneWidget,
          );
          await selectSigner('final_approver', 'Other signatory');
          await enter('final_name', 'Manual Fallback');
          await enter('final_title', 'Former Approver');
        } else {
          expect(
            tester
                .widget<DropdownButtonFormField<String>>(
                  find.byKey(const ValueKey('paper_signer_final_approver')),
                )
                .initialValue,
            isNull,
            reason: 'Date changes require confirming the signer again',
          );
        }
        await enter('approval_date', '2026-09-02');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await selectSigner('final_approver', 'Backup HR · Backup');
        await selectSigner(
          'certification_officer',
          'Credit Certifier · Primary',
        );
        await selectSigner('department_reviewer', 'Other signatory');
        await enter('dept_name', 'Former Department Head');
        await enter('dept_title', 'Former Director');
        if (width < 600) {
          await selectSigner('final_approver', 'Other signatory');
          await enter('final_name', 'Original Mayor');
          await enter('final_title', 'Mayor');
        }
        final selectedFinalName = width < 600 ? 'Original Mayor' : 'Backup HR';
        await tester.tap(find.byTooltip('Back to leave details'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(filing).controller!.text,
          '2026-09-01',
        );
        expect(
          tester.widget<TextFormField>(reason).controller!.text,
          'Original paper details',
        );
        await next();
        await reveal(find.byKey(const ValueKey('paper_field_final_name')));
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('paper_field_final_name')),
              )
              .controller!
              .text,
          selectedFinalName,
        );
        await tester.tap(find.text('Review and record'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Upload the approved signed paper form'),
          findsOneWidget,
        );
        final upload = find.text('Upload signed form');
        await reveal(upload);
        await tester.tap(upload);
        await tester.pumpAndSettle();
        for (final text in [
          'I verified the employee signature and all required approvals on paper, including Mayor or custom reviewers where applicable.',
          'I verified this leave has not already been recorded or deducted in this system.',
        ]) {
          final check = find.widgetWithText(CheckboxListTile, text);
          await reveal(check);
          await tester.tap(check);
          await tester.pump();
        }
        final reviewAction = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and record'),
            )
            .onPressed!;
        reviewAction();
        reviewAction(); // A rapid second tap must not open another confirmation.
        await tester.pumpAndSettle();
        expect(
          find.text('Paid / unpaid days on the approved paper'),
          findsOneWidget,
        );
        expect(writes, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('signed.pdf'), findsOneWidget);
        await tester.tap(find.text('Review and record'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record approval'));
        await tester.pumpAndSettle();
        expect(writes, hasLength(1));
        final fields = Map.fromEntries(writes.single.fields);
        expect(fields['leave_type'], 'mandatoryForcedLeave');
        expect(fields['start_date'], '2026-09-10');
        final recordedPaper = jsonDecode(fields['paper_approval']!);
        expect(recordedPaper['original_filing_date'], '2026-09-01');
        expect(recordedPaper['approval_date'], '2026-09-02');
        expect(recordedPaper['final_approver']['name'], selectedFinalName);
        expect(
          recordedPaper['final_approver']['user_id'],
          width < 600 ? isNull : 'backup',
        );
        expect(recordedPaper['certification_officer']['user_id'], 'certifier');
        expect(recordedPaper['department_reviewer']['user_id'], isNull);
        expect(
          recordedPaper['certification_officer']['name'],
          'Credit Certifier',
        );
        expect(
          recordedPaper['department_reviewer']['name'],
          'Former Department Head',
        );
        expect(writes.single.files.single.value.filename, 'signed.pdf');
        expect(auth.user!.id, 'encoder');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        auth.dispose();
        LeaveTypeDefinitionCache.instance.invalidate();
      },
    );
  }
  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  test(
    'paper permission defaults to disabled and requires explicit configuration',
    () {
      expect(
        LeaveTypeDefinition.fromJson({'name': 'test'}).allowApprovedPaperFiling,
        false,
      );
      final configured = LeaveTypeDefinition.fromJson({
        'name': 'test',
        'allow_approved_paper_filing': true,
      });
      expect(
        configured
            .copyWith(displayName: 'Updated')
            .toJson()['allow_approved_paper_filing'],
        true,
      );
    },
  );
  test(
    'paper requests preserve provenance and render only recorded names without digital signatures',
    () async {
      final request = LeaveRequest.fromJson({
        'id': 'record',
        'user_id': 'employee',
        'leave_type': 'sickLeave',
        'status': 'approved',
        'paper_approval_record': paper,
      });
      var calls = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            calls++;
            h.reject(DioException(requestOptions: o));
          },
        ),
      );
      final officials = await loadLeaveFormSignatories(request: request);
      expect(request.copyWith(reason: 'copy').paperApprovalRecord, paper);
      expect(request.statusLabel, 'Approved (paper record)');
      expect(officials.approvingAuthority?.name, 'Original Mayor');
      expect(officials.hrApproverSignature, isNull);
      expect(officials.applicantSignature, isNull);
      expect(officials.certificationOfficer, isNull);
      expect(calls, 0);
    },
  );
  test(
    'paper previews load only the frozen selected signature for its matching form block',
    () async {
      const encoded =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
      final record = {
        ...paper,
        'encoded_at': '2026-10-26T10:00:00Z',
        'final_approver': {
          'name': 'Original Mayor',
          'position_title': 'Mayor',
          'user_id': 'mayor',
          'signature': {
            'signature_asset_id': 'frozen-asset',
            'owner_user_id': 'mayor',
            'source': 'saved_signature_copy',
          },
        },
        'certification_officer': {
          'name': 'Primary HR',
          'position_title': 'HR Director',
          'user_id': 'hr',
        },
      };
      final request = LeaveRequest.fromJson({
        'id': 'record',
        'user_id': 'employee',
        'leave_type': 'sickLeave',
        'status': 'approved',
        'paper_approval_record': record,
      });
      var calls = 0;
      var wrongOwner = false;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            calls++;
            expect(o.path, '/api/leave/signatories');
            expect(o.queryParameters['leave_request_id'], 'record');
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'paper_signatures': {
                    'final_approver': {
                      'signature_asset_id': 'frozen-asset',
                      'signature_image_base64': encoded,
                      'mime_type': 'image/png',
                      'signed_by': wrongOwner ? 'hr' : 'mayor',
                      'signed_at': '2026-10-26T10:00:00Z',
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final officials = await loadLeaveFormSignatories(request: request);
      expect(
        officials.hrApproverSignature?.signatureImageBytes,
        base64Decode(encoded),
      );
      expect(officials.certificationOfficerSignature, isNull);
      expect(officials.departmentHeadSignature, isNull);
      expect(officials.applicantSignature, isNull);
      expect(officials.approvingAuthority?.name, 'Original Mayor');
      wrongOwner = true;
      expect(
        (await loadLeaveFormSignatories(request: request)).hrApproverSignature,
        isNull,
      );
      expect(calls, 2);
    },
  );
  test(
    'paper previews render the frozen applicant copy only for the request employee',
    () async {
      const encoded =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
      var owner = 'employee';
      var asset = 'applicant-asset';
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            expect(o.path, '/api/leave/signatories');
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'paper_signatures': {
                    'applicant': {
                      'slot_key': 'applicant',
                      'signature_asset_id': asset,
                      'signature_image_base64': encoded,
                      'mime_type': 'image/png',
                      'signed_by': owner,
                      'signed_at': '2026-10-27T01:00:00Z',
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      LeaveRequest requestFor(String applicant) => LeaveRequest.fromJson({
        'id': 'record',
        'user_id': 'employee',
        'leave_type': 'sickLeave',
        'status': 'approved',
        'paper_approval_record': {
          ...paper,
          'applicant': {
            'user_id': applicant,
            'name': 'Employee',
            'signature': {'signature_asset_id': 'applicant-asset'},
          },
        },
      });
      final copy = await loadLeaveFormSignatories(
        request: requestFor('employee'),
      );
      expect(
        copy.applicantSignature?.signatureImageBytes,
        base64Decode(encoded),
      );
      expect(copy.hrApproverSignature, isNull);
      owner = 'encoder';
      expect(
        (await loadLeaveFormSignatories(
          request: requestFor('employee'),
        )).applicantSignature,
        isNull,
      );
      expect(
        (await loadLeaveFormSignatories(
          request: requestFor('encoder'),
        )).applicantSignature,
        isNull,
      );
      owner = 'employee';
      asset = 'replacement-asset';
      expect(
        (await loadLeaveFormSignatories(
          request: requestFor('employee'),
        )).applicantSignature,
        isNull,
      );
    },
  );
  test(
    'recording uploads paper approval data and paid allocation without fabricated signatures',
    () async {
      RequestOptions? sent;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            sent = o;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'results': [
                    {
                      'request': {
                        'id': 'record',
                        'user_id': 'employee',
                        'status': 'approved',
                        'leave_type': 'sickLeave',
                        'paper_approval_record': paper,
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final request = await ApiLeaveRepository().recordApprovedPaperLeave(
        const LeaveRequest(userId: 'employee', leaveType: LeaveType.sickLeave),
        paperApproval: paper,
        fileBytes: [1, 2, 3],
        fileName: 'signed.pdf',
        approval: const LeaveApprovalInput(
          requestId: '',
          reviewerId: '',
          approvedDaysWithPay: 1,
          approvedDaysWithoutPay: 0,
        ),
      );
      final data = Map<String, String>.fromEntries(
        (sent!.data as FormData).fields,
      );
      expect(jsonDecode(data['paper_approval']!), paper);
      expect(data.containsKey('signature'), false);
      expect(data.containsKey('applicant_signature_asset_id'), false);
      expect(data['approved_days_with_pay'], '1.0');
      expect(request.status, LeaveRequestStatus.approved);
    },
  );
  test('paper history identifies recording instead of a new HR approval', () {
    final entry = LeaveRequestHistoryEntry(
      id: 'event',
      requestId: 'record',
      action: 'paper_approved_recorded',
      toStatus: 'approved',
      actedAt: DateTime(2026, 10, 26),
      actorName: 'HR Encoder',
    );
    expect(entry.actionLabel, 'Approved paper leave recorded');
    expect(entry.actorLabel, 'HR Encoder');
  });
}
