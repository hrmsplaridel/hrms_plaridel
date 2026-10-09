import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

const _me = '00000000-0000-4000-8000-000000000002';

Map<String, dynamic> _rspRequest({
  required String id,
  required String title,
  required Map<String, dynamic> slot,
  bool requiresSetup = false,
}) => {
  'source_module': 'rsp',
  'source_table': 'turn_around_time_entries',
  'source_record_id': id,
  'form_name': 'Turn Around Time',
  'title': title,
  'requires_setup': requiresSetup,
  'signature_bundle': {
    'source_module': 'rsp',
    'source_table': 'turn_around_time_entries',
    'source_record_id': id,
    'signatures': [
      {'slot_key': 'prepared_by', 'label': 'Prepared by', ...slot},
    ],
  },
};

final _rspRequests = [
  _rspRequest(
    id: 'tat-mine',
    title: 'Assigned TAT',
    slot: {
      'assigned_signer_id': _me,
      'assigned_signer_name': 'Test Reviewer',
      'can_sign': true,
    },
  ),
  _rspRequest(
    id: 'tat-other',
    title: 'Other TAT',
    slot: {
      'assigned_signer_id': 'someone-else',
      'assigned_signer_name': 'Someone Else',
      'can_sign': false,
    },
  ),
  _rspRequest(
    id: 'tat-setup',
    title: 'Setup TAT',
    slot: {'assigned_signer_id': ''},
    requiresSetup: true,
  ),
];

/// The list endpoint returns native and DTR rows only; recruitment
/// applications are not DocuTracker documents.
final _documents = [
  {
    'id': 'memo-1',
    'document_type': 'memo',
    'title': 'Budget memo',
    'status': 'in_review',
    'current_step': 1,
    'current_holder_id': _me,
  },
  {
    'id': 'source:dtr:leave-1',
    'document_type': 'dtr',
    'title': 'Leave 2026-10-01',
    'status': 'pending',
    'source_module': 'dtr',
    'source_table': 'leave_requests',
    'source_record_id': 'leave-1',
    'source_status': 'draft',
    'source_action': 'complete_in_dtr',
    'source_action_label': 'Complete and submit in DTR',
    'source_only': true,
  },
];

Future<void> _pumpScreen(WidgetTester tester, {required bool isAdmin}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 4000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider()
            ..replaceUser(
              AppUser(
                id: _me,
                email: 'reviewer@hrms.local',
                role: isAdmin ? 'admin' : 'employee',
                fullName: 'Test Reviewer',
              ),
            ),
        ),
        ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocuTrackerDocumentsScreen(isAdmin: isAdmin),
          ),
        ),
      ),
    ),
  );
  for (
    var i = 0;
    i < 100 && find.text('Assigned TAT').evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorage, (call) async {
      if (call.method == 'containsKey') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(packageInfo, (call) async {
      if (call.method != 'getAll') return null;
      return <String, dynamic>{
        'appName': 'HRMS Test',
        'packageName': 'hrms_plaridel',
        'version': '1.0.0',
        'buildNumber': '1',
        'buildSignature': '',
        'installerStore': null,
      };
    });
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = switch (options.uri.path) {
            '/api/docutracker/permission-explain' => <String, dynamic>{
              'final_decision': true,
            },
            '/api/docutracker/documents' => _documents,
            '/api/docutracker/sources/rsp/signature-requests' => _rspRequests,
            _ => <dynamic>[],
          };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorage, null);
    messenger.setMockMethodCallHandler(packageInfo, null);
  });

  testWidgets('a signer sees only the RSP form assigned to them, next to '
      'unchanged native and DTR actions', (tester) async {
    await _pumpScreen(tester, isAdmin: false);

    expect(find.text('Assigned TAT'), findsOneWidget);
    expect(find.text('RSP · Turn Around Time'), findsOneWidget);
    expect(find.text('Other TAT'), findsNothing);
    expect(find.text('Setup TAT'), findsNothing);
    expect(find.text('Needs setup'), findsNothing);

    expect(find.text('Budget memo'), findsWidgets);
    expect(find.text('Leave 2026-10-01'), findsWidgets);
    expect(find.text('Recruitment Application'), findsNothing);
    expect(find.text('Managed in RSP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admins still see signature setup and waiting RSP forms', (
    tester,
  ) async {
    await _pumpScreen(tester, isAdmin: true);

    expect(find.text('Assigned TAT'), findsOneWidget);
    expect(find.text('Setup TAT'), findsOneWidget);
    expect(find.text('Needs setup'), findsWidgets);
    expect(
      find.text('Other TAT'),
      findsNothing,
      reason: 'waiting is secondary',
    );
    expect(find.textContaining('Show waiting (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening an RSP required action reaches that form\'s signature '
      'view without recruitment workflow', (tester) async {
    await _pumpScreen(tester, isAdmin: false);

    await tester.tap(find.text('Assigned TAT'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Turn Around Time')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Assigned TAT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('Prepared by')),
      findsWidgets,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('Applicant')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
