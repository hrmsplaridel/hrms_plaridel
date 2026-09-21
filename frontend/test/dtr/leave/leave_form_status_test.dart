import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/core/api/client.dart';

const draft = LeaveRequest(
  id: 'leave-1',
  userId: 'employee-1',
  leaveType: LeaveType.sickLeave,
  status: LeaveRequestStatus.draft,
);

class _Repository extends MockLeaveRepository {
  Future<LeaveRequest?> Function() read = () async => draft;

  @override
  Future<LeaveRequest?> getRequestById(String requestId) => read();
}

class _Signatures extends DocuTrackerProvider {
  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async => DocuTrackerSourceSignatureBundle(
    sourceModule: sourceModule,
    sourceTable: sourceTable,
    sourceRecordId: sourceRecordId,
    sourceStatus: 'pending_hr',
    signatures: const [],
  );
}

Future<void> _openForm(
  WidgetTester tester,
  _Repository repository, {
  LeaveRequest initial = draft,
  bool loadOfficialDate = false,
}) async {
  ApiClient.instance.init();
  ApiClient.instance.dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == '/api/leave/types') {
          handler.resolve(Response<List<dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: [
              {'name': 'vacationLeave', 'display_name': 'Vacation Leave'},
              {'name': 'sickLeave', 'display_name': 'Sick Leave'},
            ],
          ));
          return;
        }
        handler.next(options);
      },
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) {
            final provider = LeaveProvider(repository: repository);
            if (loadOfficialDate) unawaited(provider.loadOfficialDate());
            return provider;
          },
        ),
        ChangeNotifierProvider<DocuTrackerProvider>(
          create: (_) => _Signatures(),
        ),
      ],
      child: MaterialApp(
        home: LeaveRequestFormScreen(
          initialRequest: initial,
          onSaveDraft: (_) async => throw StateError('Unexpected draft write'),
          onSubmitRequest: (_) async =>
              throw StateError('Unexpected submission'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('deactivated draft type is not offered for a new filing', (
    tester,
  ) async {
    final repository = _Repository();
    final oldDraft = draft.copyWith(
      leaveType: LeaveType.others,
      leaveTypeName: 'earlLeave',
      leaveTypeDisplayName: 'Earl leave',
    );
    repository.read = () async => oldDraft;
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    LeaveTypeDefinitionCache.instance.invalidate();
    var activeTypes = <Map<String, dynamic>>[
      {'name': 'vacationLeave', 'display_name': 'Vacation Leave'},
      {'name': 'earlLeave', 'display_name': 'Earl leave'},
    ];
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/leave/types') {
            handler.resolve(Response<List<dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: activeTypes,
            ));
            return;
          }
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    await tester.runAsync(
      () => LeaveTypeDefinitionCache.instance.listActiveEmployeeTypes(),
    );
    activeTypes = [
      {'name': 'vacationLeave', 'display_name': 'Vacation Leave'},
    ];

    await _openForm(tester, repository, initial: oldDraft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenuItem<String> && widget.value == 'earlLeave',
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(dropdown.initialValue, 'vacationLeave');
    LeaveTypeDefinitionCache.instance.invalidate();
  });

  testWidgets('missing final reviewer blocks submit before signing or saving', (
    tester,
  ) async {
    final date = DateTime.now().add(const Duration(days: 2));
    final validDraft = draft.copyWith(
      startDate: date,
      endDate: date,
      workingDaysApplied: 1,
      sickLeaveNature: SickLeaveNature.outPatient,
      sickIllnessDetails: 'Fever',
    );
    final repository = _Repository()..read = () async => validDraft;
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    var availabilityChecks = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/leave/submission-availability') {
            availabilityChecks++;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'can_submit': false,
                  'reason': 'No eligible final leave reviewer is configured.',
                },
              ),
            );
            return;
          }
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    await _openForm(
      tester,
      repository,
      initial: validDraft,
      loadOfficialDate: true,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit Request'));
    await tester.tap(find.text('Submit Request'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      availabilityChecks,
      1,
      reason: find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .join(' | '),
    );
    expect(
      find.textContaining('No eligible final leave reviewer'),
      findsOneWidget,
    );
    expect(find.text('Submit Request'), findsOneWidget);
  });

  testWidgets('failed write message survives the saved-status refresh', (
    tester,
  ) async {
    final repository = _Repository();
    await _openForm(tester, repository);
    await tester.pumpAndSettle();
    final finalStatus = Completer<LeaveRequest?>();
    var checks = 0;
    repository.read = () {
      checks++;
      return checks == 2 ? finalStatus.future : Future.value(draft);
    };
    await tester.ensureVisible(find.text('Save Draft'));
    await tester.tap(find.text('Save Draft'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(checks, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Error:'), findsOneWidget);
    finalStatus.complete(draft);
    await tester.pump();
    expect(find.text('Save Draft'), findsOneWidget);
  });

  testWidgets('draft submission can validate after a delayed status check', (
    tester,
  ) async {
    final repository = _Repository();
    await _openForm(tester, repository);
    await tester.pumpAndSettle();
    final response = Completer<LeaveRequest?>();
    repository.read = () => response.future;
    await tester.ensureVisible(find.text('Submit Request'));
    await tester.tap(find.text('Submit Request'));
    await tester.pump();
    response.complete(draft);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Submit Request'), findsOneWidget);
    expect(find.text('Required'), findsWidgets);
  });

  testWidgets(
    'Submit rechecks server status before asking for a signature or writing',
    (tester) async {
      final initial = draft.copyWith(
        startDate: DateTime(2026, 9, 14),
        endDate: DateTime(2026, 9, 15),
        workingDaysApplied: 2,
        sickLeaveNature: SickLeaveNature.outPatient,
        sickIllnessDetails: 'Test illness',
      );
      final repository = _Repository()..read = () async => initial;
      await _openForm(tester, repository, initial: initial);
      await tester.pumpAndSettle();
      repository.read = () async =>
          initial.copyWith(status: LeaveRequestStatus.pendingHr);
      await tester.ensureVisible(find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();
      expect(find.text('Status: Pending HR'), findsOneWidget);
      expect(find.text('Submit Request'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Save rechecks a draft submitted from another window without writing',
    (tester) async {
      final initial = draft.copyWith(
        startDate: DateTime(2026, 9, 14),
        endDate: DateTime(2026, 9, 15),
        workingDaysApplied: 2,
      );
      final repository = _Repository()..read = () async => initial;
      await _openForm(tester, repository, initial: initial);
      await tester.pumpAndSettle();
      repository.read = () async =>
          initial.copyWith(status: LeaveRequestStatus.pendingHr);
      await tester.ensureVisible(find.text('Save Draft'));
      await tester.tap(find.text('Save Draft'));
      await tester.pumpAndSettle();
      expect(find.text('Status: Pending HR'), findsOneWidget);
      expect(find.text('Save Draft'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'stale draft becomes read-only when server says Pending HR at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository()
          ..read = () async =>
              draft.copyWith(status: LeaveRequestStatus.pendingHr);
        await _openForm(tester, repository);
        await tester.pumpAndSettle();
        expect(find.text('Status: Pending HR'), findsOneWidget);
        expect(find.text('Submit Request'), findsNothing);
        expect(find.text('Save Draft'), findsNothing);
        expect(find.text('Close'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('status lookup failure blocks saving and supports retry', (
    tester,
  ) async {
    final repository = _Repository()
      ..read = () async => throw Exception('offline');
    await _openForm(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Save Draft'), findsNothing);
    repository.read = () async =>
        draft.copyWith(status: LeaveRequestStatus.pendingHr);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Pending HR'), findsOneWidget);
    expect(find.text('Submit Request'), findsNothing);
  });

  testWidgets('no write controls are exposed while checking a saved request', (
    tester,
  ) async {
    final response = Completer<LeaveRequest?>();
    final repository = _Repository()..read = () => response.future;
    await _openForm(tester, repository);
    await tester.pump();
    expect(find.text('Submit Request'), findsNothing);
    expect(find.text('Save Draft'), findsNothing);
    response.complete(draft.copyWith(status: LeaveRequestStatus.approved));
    await tester.pumpAndSettle();
    expect(find.text('Status: Approved'), findsOneWidget);
    expect(find.text('Submit Request'), findsNothing);
  });
}
