import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

const _me = '00000000-0000-4000-8000-000000000011';

final _documents = [
  {
    'id': 'doc-1',
    'document_number': 'DOC-2026-0001',
    'document_type': 'memo',
    'title': 'Budget Planning Memo',
    'status': 'in_review',
    'current_step': 2,
    'created_by': _me,
    'current_holder_id': _me,
    'creator_name': 'Alice Creator',
    'assignee_name': 'Bob Reviewer',
    'created_at': '2026-10-01T08:00:00.000Z',
    'updated_at': '2026-10-02T08:00:00.000Z',
  },
  {
    'id': 'doc-2',
    'document_number': 'DOC-2026-0002',
    'document_type': 'purchaseRequest',
    'title': 'Office Supplies Request',
    'status': 'approved',
    'current_step': 3,
    'created_by': _me,
    'creator_name': 'Alice Creator',
    'assignee_name': 'Workflow complete',
    'release_required': true,
    'released_at': null,
    'created_at': '2026-10-03T08:00:00.000Z',
    'updated_at': '2026-10-04T08:00:00.000Z',
  },
  {
    'id': 'doc-3',
    'document_number': 'DOC-2026-0003',
    'document_type': 'memo',
    'title': 'Released Circular',
    'status': 'approved',
    'current_step': 3,
    'created_by': _me,
    'release_required': true,
    'released_at': '2026-10-05T08:00:00.000Z',
    'released_to_department_name': 'Finance',
    'created_at': '2026-10-04T08:00:00.000Z',
    'updated_at': '2026-10-05T08:00:00.000Z',
  },
];

Future<void> _pumpDocuments(
  WidgetTester tester, {
  Size size = const Size(1280, 1800),
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
                email: 'list.tester@hrms.local',
                role: 'employee',
                fullName: 'List Tester',
              ),
            ),
        ),
        ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: DocuTrackerDocumentsScreen(isAdmin: false),
          ),
        ),
      ),
    ),
  );

  for (
    var i = 0;
    i < 120 && find.text('Budget Planning Memo').evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');
  late Interceptor interceptor;

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
  });

  setUp(() {
    ApiClient.instance.dio.interceptors.clear();
    interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.uri.path;
        final data = switch (path) {
          '/api/docutracker/documents' => _documents,
          '/api/docutracker/document-types/creatable' => <dynamic>[],
          '/api/docutracker/routing-configs' => <dynamic>[],
          '/api/docutracker/sources/rsp/signature-requests' => <dynamic>[],
          '/api/docutracker/permission-explain' => <String, dynamic>{
            'final_decision': false,
          },
          _ => <dynamic>[],
        };
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: data),
        );
      },
    );
    ApiClient.instance.dio.interceptors.add(interceptor);
  });

  tearDown(() {
    ApiClient.instance.dio.interceptors.remove(interceptor);
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorage, null);
    messenger.setMockMethodCallHandler(packageInfo, null);
  });

  group('docuTrackerDocumentMatchesSearch', () {
    const doc = DocuTrackerDocument(
      id: '1',
      documentNumber: 'DOC-9',
      documentType: 'memo',
      title: 'Quarterly Report',
      creatorName: 'Nina Sender',
      assigneeName: 'Omar Holder',
    );

    test('matches title, number, sender, assignee, and type', () {
      expect(docuTrackerDocumentMatchesSearch(doc, 'quarterly'), isTrue);
      expect(docuTrackerDocumentMatchesSearch(doc, 'DOC-9'), isTrue);
      expect(docuTrackerDocumentMatchesSearch(doc, 'nina'), isTrue);
      expect(docuTrackerDocumentMatchesSearch(doc, 'omar'), isTrue);
      expect(docuTrackerDocumentMatchesSearch(doc, 'memo'), isTrue);
      expect(docuTrackerDocumentMatchesSearch(doc, 'missing'), isFalse);
      expect(docuTrackerDocumentMatchesSearch(doc, '  '), isTrue);
    });
  });

  testWidgets('desktop table shows docs, numbers, and release labels', (
    tester,
  ) async {
    await _pumpDocuments(tester, size: const Size(1400, 2000));

    final table = find.byKey(const ValueKey('docutracker-document-table'));
    expect(find.byKey(const ValueKey('docutracker-document-search')), findsOneWidget);
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('Budget Planning Memo')),
      findsOneWidget,
    );
    expect(find.textContaining('DOC-2026-0001'), findsWidgets);
    expect(find.text('Awaiting release'), findsOneWidget);
    expect(find.text('Released'), findsOneWidget);
    expect(find.byKey(const ValueKey('docutracker-document-count')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters locally and clear restores the list', (
    tester,
  ) async {
    await _pumpDocuments(tester, size: const Size(1400, 2000));
    final table = find.byKey(const ValueKey('docutracker-document-table'));

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-document-search')),
      'office supplies',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(of: table, matching: find.text('Office Supplies Request')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('Budget Planning Memo')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('docutracker-clear-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('docutracker-active-filters')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('docutracker-clear-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(of: table, matching: find.text('Budget Planning Memo')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('Office Supplies Request')),
      findsOneWidget,
    );
  });

  testWidgets('no-results state offers clear search & filters', (tester) async {
    await _pumpDocuments(tester, size: const Size(1400, 2000));

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-document-search')),
      'zzzz-no-match',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('docutracker-documents-no-results')),
      findsOneWidget,
    );
    expect(find.text('No matching documents'), findsOneWidget);
    expect(find.byKey(const ValueKey('docutracker-document-table')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('docutracker-no-results-clear')));
    await tester.pump();

    final table = find.byKey(const ValueKey('docutracker-document-table'));
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('Budget Planning Memo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('docutracker-documents-no-results')),
      findsNothing,
    );
  });

  testWidgets('narrow layout uses document cards instead of table', (
    tester,
  ) async {
    await _pumpDocuments(tester, size: const Size(420, 1600));

    expect(find.byKey(const ValueKey('docutracker-document-table')), findsNothing);
    expect(find.byKey(const ValueKey('docutracker-mobile-filters')), findsOneWidget);
    expect(find.textContaining('Current assignee'), findsWidgets);
    expect(find.byKey(const ValueKey('docutracker-document-count')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme keeps list readable', (tester) async {
    await _pumpDocuments(
      tester,
      size: const Size(1400, 2000),
      theme: AppTheme.darkTheme,
    );

    final table = find.byKey(const ValueKey('docutracker-document-table'));
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('Budget Planning Memo')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('status labels prefer release wording for approved docs', () {
    final awaiting = DocuTrackerDocument(
      documentType: 'memo',
      title: 'Awaiting',
      status: DocumentStatus.approved,
      releaseRequired: true,
    );
    final released = DocuTrackerDocument(
      documentType: 'memo',
      title: 'Done',
      status: DocumentStatus.approved,
      releaseRequired: true,
      releasedAt: DateTime.parse('2026-10-05T08:00:00.000Z'),
    );
    expect(awaiting.isAwaitingRelease, isTrue);
    expect(released.isReleased, isTrue);
  });
}
