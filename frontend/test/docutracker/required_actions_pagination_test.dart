import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_main.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

String _n(int i) => i.toString().padLeft(2, '0');

Map<String, dynamic> _dtrJson(int i) => {
  'id': 'source:dtr:leave-$i',
  'document_type': 'dtr',
  'title': 'Leave ${_n(i)}',
  'status': 'pending',
  'source_module': 'dtr',
  'source_table': 'leave_requests',
  'source_record_id': 'leave-$i',
  'source_status': 'draft',
  'source_action': 'complete_in_dtr',
  'source_action_label': 'Complete and submit in DTR',
  'source_only': true,
};

DocuTrackerDocument _dtr(int i) => DocuTrackerDocument.fromJson(_dtrJson(i));

DocuTrackerDocument _memo(int i) => DocuTrackerDocument.fromJson({
  'id': 'memo-$i',
  'document_type': 'memo',
  'title': 'Memo ${_n(i)}',
  'status': 'in_review',
  'current_step': 1,
});

enum _Slot { mine, waiting, signed, setup }

DocuTrackerRspSignatureRequest _request(int i, _Slot slot) {
  final signature = switch (slot) {
    _Slot.mine => {'assigned_signer_id': 'me', 'can_sign': true},
    _Slot.waiting => {'assigned_signer_id': 'other', 'can_sign': false},
    _Slot.signed => {
      'assigned_signer_id': 'other',
      'can_sign': false,
      'signature_asset_id': 'asset-$i',
      'signature_image_base64': 'AQ==',
      'signed_at': '2026-01-01T00:00:00Z',
    },
    _Slot.setup => {'assigned_signer_id': ''},
  };
  return DocuTrackerRspSignatureRequest.fromJson({
    'source_module': 'rsp',
    'source_table': 'turn_around_time_entries',
    'source_record_id': 'tat-${slot.name}-$i',
    'form_name': 'Turn Around Time',
    'title': '${slot.name} TAT ${_n(i)}',
    'requires_setup': slot == _Slot.setup,
    'signature_bundle': {
      'source_module': 'rsp',
      'source_table': 'turn_around_time_entries',
      'source_record_id': 'tat-${slot.name}-$i',
      'signatures': [signature],
    },
  });
}

List<DocuTrackerDocument> _dtrs(int count, {int from = 1}) => [
  for (var i = from; i < from + count; i++) _dtr(i),
];

Widget _panel({
  List<DocuTrackerDocument> documents = const [],
  List<DocuTrackerRspSignatureRequest> requests = const [],
}) {
  return DocuTrackerRequiredActionsPanel(
    documents: documents,
    sourceRequests: requests,
    loading: false,
    hasPartialError: false,
    onRefreshSignatures: () async {},
    onDocumentTap: (_) async => false,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  Widget panel, {
  DocuTrackerProvider? provider,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 4000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider<DocuTrackerProvider>.value(
      value: provider ?? DocuTrackerProvider(),
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: panel)),
      ),
    ),
  );
  await tester.pump();
}

final _pager = find.byKey(const ValueKey('docutracker-required-actions-pager'));
final _label = find.byKey(
  const ValueKey('docutracker-required-actions-page-label'),
);
final _prev = find.byKey(const ValueKey('docutracker-required-actions-prev'));
final _next = find.byKey(const ValueKey('docutracker-required-actions-next'));

Finder _pageButton(int page) =>
    find.byKey(ValueKey('docutracker-required-actions-page-$page'));

String _labelText(WidgetTester tester) => tester.widget<Text>(_label).data!;

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<IconButton>(button).onPressed != null;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ten items or fewer show every card and no paginator', (
    tester,
  ) async {
    await _pumpPanel(tester, _panel(documents: _dtrs(10)));
    expect(_pager, findsNothing);
    for (var i = 1; i <= 10; i++) {
      expect(find.text('Leave ${_n(i)}'), findsOneWidget);
    }
  });

  testWidgets('more than ten items page through in order with boundaries', (
    tester,
  ) async {
    await _pumpPanel(tester, _panel(documents: _dtrs(13)));
    expect(_pager, findsOneWidget);
    expect(_labelText(tester), 'Showing 1–10 of 13');
    for (var i = 1; i <= 10; i++) {
      expect(find.text('Leave ${_n(i)}'), findsOneWidget);
    }
    expect(find.text('Leave 11'), findsNothing);
    expect(_enabled(tester, _prev), isFalse);
    expect(_enabled(tester, _next), isTrue);

    await _tap(tester, _next);
    expect(_labelText(tester), 'Showing 11–13 of 13');
    for (var i = 11; i <= 13; i++) {
      expect(find.text('Leave ${_n(i)}'), findsOneWidget);
    }
    expect(find.text('Leave 01'), findsNothing);
    expect(_enabled(tester, _prev), isTrue);
    expect(_enabled(tester, _next), isFalse);

    await _tap(tester, _prev);
    expect(_labelText(tester), 'Showing 1–10 of 13');

    await _tap(tester, _pageButton(2));
    expect(_labelText(tester), 'Showing 11–13 of 13');
  });

  testWidgets('search resets to page 1', (tester) async {
    await _pumpPanel(tester, _panel(documents: _dtrs(13)));
    await _tap(tester, _next);
    expect(_labelText(tester), 'Showing 11–13 of 13');

    await tester.enterText(find.byType(TextField), 'Leave');
    await tester.pumpAndSettle();
    expect(_labelText(tester), 'Showing 1–10 of 13');
    expect(find.text('Leave 01'), findsOneWidget);
  });

  testWidgets('module filter resets to page 1', (tester) async {
    await _pumpPanel(
      tester,
      _panel(documents: [..._dtrs(12), for (var i = 1; i <= 12; i++) _memo(i)]),
    );
    expect(_labelText(tester), 'Showing 1–10 of 24');
    await _tap(tester, _pageButton(2));
    expect(_labelText(tester), 'Showing 11–20 of 24');

    await _tap(tester, find.widgetWithText(FilterChip, 'DocuTracker'));
    expect(_labelText(tester), 'Showing 1–10 of 12');
    expect(find.text('Memo 01'), findsOneWidget);
    expect(find.text('Leave 01'), findsNothing);
  });

  testWidgets('form-type filter resets to page 1', (tester) async {
    await _pumpPanel(
      tester,
      _panel(documents: [..._dtrs(12), for (var i = 1; i <= 12; i++) _memo(i)]),
    );
    await _tap(tester, _pageButton(2));
    expect(_labelText(tester), 'Showing 11–20 of 24');

    await _tap(tester, find.byType(DropdownButton<String?>));
    await _tap(tester, find.text('Leave').last);
    expect(_labelText(tester), 'Showing 1–10 of 12');
    expect(find.text('Leave 01'), findsOneWidget);
  });

  testWidgets('waiting and fully-signed toggle resets to page 1 and keeps '
      'full counts', (tester) async {
    await _pumpPanel(
      tester,
      _panel(
        documents: _dtrs(12),
        requests: [
          for (var i = 1; i <= 3; i++) _request(i, _Slot.waiting),
          for (var i = 1; i <= 2; i++) _request(i, _Slot.signed),
        ],
      ),
    );
    expect(_labelText(tester), 'Showing 1–10 of 12');
    expect(find.text('Show waiting (3) & fully signed (2)'), findsNothing);

    await _tap(tester, _next);
    expect(_labelText(tester), 'Showing 11–12 of 12');
    final toggle = find.text('Show waiting (3) & fully signed (2)');
    expect(toggle, findsOneWidget);

    await _tap(tester, toggle);
    expect(_labelText(tester), 'Showing 1–10 of 17');
    expect(find.text('Waiting on other signers'), findsNothing);

    await _tap(tester, _next);
    expect(_labelText(tester), 'Showing 11–17 of 17');
    expect(find.text('Waiting on other signers'), findsOneWidget);
    expect(find.text('Fully signed'), findsOneWidget);
    expect(find.text('Hide waiting & signed'), findsOneWidget);
  });

  testWidgets('the badge and counts use the full filtered collection', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      _panel(
        documents: _dtrs(25),
        requests: [for (var i = 1; i <= 3; i++) _request(i, _Slot.mine)],
      ),
    );
    expect(_labelText(tester), 'Showing 1–10 of 28');
    expect(find.text('28'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Leave 1');
    await tester.pumpAndSettle();
    expect(find.text('Showing 10 matching'), findsOneWidget);
    expect(_pager, findsNothing);
    expect(find.text('28'), findsOneWidget);
  });

  testWidgets('the current page clamps when items disappear', (tester) async {
    late StateSetter setDocs;
    var docs = _dtrs(25);
    await _pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          setDocs = setState;
          return _panel(documents: docs);
        },
      ),
    );
    await _tap(tester, _pageButton(3));
    expect(_labelText(tester), 'Showing 21–25 of 25');

    setDocs(() => docs = _dtrs(12));
    await tester.pumpAndSettle();
    expect(_labelText(tester), 'Showing 11–12 of 12');
    expect(find.text('Leave 12'), findsOneWidget);

    setDocs(() => docs = _dtrs(14));
    await tester.pumpAndSettle();
    expect(
      _labelText(tester),
      'Showing 11–14 of 14',
      reason: 'refresh keeps a still-valid page',
    );

    setDocs(() => docs = _dtrs(4));
    await tester.pumpAndSettle();
    expect(_pager, findsNothing);
    expect(find.text('Leave 04'), findsOneWidget);
  });

  testWidgets('group headings render only for groups on the current page', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      _panel(
        documents: [..._dtrs(4), for (var i = 1; i <= 3; i++) _memo(i)],
        requests: [for (var i = 1; i <= 5; i++) _request(i, _Slot.setup)],
      ),
    );
    expect(_labelText(tester), 'Showing 1–10 of 12');
    expect(find.text('Needs your signature'), findsOneWidget);
    // Section heading plus one chip per setup card on this page.
    expect(find.text('Needs setup'), findsNWidgets(1 + 3));
    // Module headings, plus the module filter chip for each. DocuTracker
    // cards also show "DocuTracker" as their source label.
    expect(find.text('DTR'), findsNWidgets(2));
    expect(find.text('DocuTracker'), findsNWidgets(2 + 3));
    expect(find.text('RSP'), findsNWidgets(2));
    expect(find.text('setup TAT 03'), findsOneWidget);
    expect(find.text('setup TAT 04'), findsNothing);

    await _tap(tester, _next);
    expect(_labelText(tester), 'Showing 11–12 of 12');
    expect(find.text('Needs your signature'), findsNothing);
    expect(find.text('Needs setup'), findsNWidgets(1 + 2));
    expect(find.text('DTR'), findsOneWidget, reason: 'filter chip only');
    expect(
      find.text('DocuTracker'),
      findsOneWidget,
      reason: 'filter chip only',
    );
    expect(find.text('RSP'), findsNWidgets(2));
    expect(find.text('setup TAT 04'), findsOneWidget);
    expect(find.text('setup TAT 05'), findsOneWidget);
  });

  testWidgets('the selected page survives leaving and returning to the panel', (
    tester,
  ) async {
    final provider = DocuTrackerProvider();
    await _pumpPanel(tester, _panel(documents: _dtrs(13)), provider: provider);
    await _tap(tester, _next);
    expect(_labelText(tester), 'Showing 11–13 of 13');

    await _pumpPanel(tester, const SizedBox.shrink(), provider: provider);
    await _pumpPanel(tester, _panel(documents: _dtrs(13)), provider: provider);
    expect(_labelText(tester), 'Showing 11–13 of 13');
  });

  testWidgets('collapse survives rebuilds, refreshes, navigation, and a '
      're-keyed parent without losing search, filters, or page', (
    tester,
  ) async {
    late StateSetter setOuter;
    var docs = [..._dtrs(12), for (var i = 1; i <= 12; i++) _memo(i)];
    var parentKey = 0;
    await _pumpPanel(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return KeyedSubtree(
            key: ValueKey(parentKey),
            child: _panel(documents: docs),
          );
        },
      ),
    );
    final header = find.text('Required actions');
    final search = find.byType(TextField);

    expect(search, findsOneWidget, reason: 'starts expanded');
    await _tap(tester, find.widgetWithText(FilterChip, 'DTR'));
    await tester.enterText(search, 'Leave');
    await tester.pumpAndSettle();
    await _tap(tester, _pageButton(2));
    expect(_labelText(tester), 'Showing 11–12 of 12');

    await _tap(tester, header);
    expect(search, findsNothing);
    expect(_pager, findsNothing);
    expect(find.text('24'), findsOneWidget, reason: 'badge stays visible');

    setOuter(() {});
    await tester.pumpAndSettle();
    expect(search, findsNothing, reason: 'plain rebuild keeps it collapsed');

    setOuter(
      () => docs = [..._dtrs(13), for (var i = 1; i <= 12; i++) _memo(i)],
    );
    await tester.pumpAndSettle();
    expect(search, findsNothing, reason: 'data refresh keeps it collapsed');
    expect(find.text('25'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(search, findsNothing, reason: 'returning from a document');

    setOuter(() => parentKey++);
    await tester.pumpAndSettle();
    expect(
      search,
      findsNothing,
      reason: 'a re-keyed parent remounts the panel in the same frame',
    );

    await _tap(tester, header);
    expect(search, findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, 'Leave');
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'DTR'))
          .selected,
      isTrue,
    );
    expect(_labelText(tester), 'Showing 11–13 of 13');
    expect(find.text('Leave 13'), findsOneWidget);
  });

  testWidgets('the paginator fits a narrow phone with many pages', (
    tester,
  ) async {
    await _pumpPanel(tester, _panel(documents: _dtrs(90)));
    tester.view.physicalSize = const Size(360, 4000);
    await tester.pumpAndSettle();
    await _tap(tester, _pageButton(4));
    await _tap(tester, _pageButton(5));
    expect(_labelText(tester), 'Showing 41–50 of 90');
    expect(_pageButton(1), findsOneWidget);
    expect(_pageButton(4), findsOneWidget);
    expect(_pageButton(6), findsOneWidget);
    expect(_pageButton(9), findsOneWidget);
    expect(_pageButton(2), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('on the Documents screen', () {
    final requestedPaths = <String>[];
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
            final path = options.uri.path;
            requestedPaths.add(path);
            final data = switch (path) {
              '/api/docutracker/permission-explain' => <String, dynamic>{
                'final_decision': true,
              },
              '/api/docutracker/documents' => <dynamic>[
                for (var i = 1; i <= 13; i++) _dtrJson(i),
              ],
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

    testWidgets('changing pages does not reload any data', (tester) async {
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
                    id: '00000000-0000-4000-8000-000000000002',
                    email: 'reviewer@hrms.local',
                    role: 'employee',
                    fullName: 'Test Reviewer',
                  ),
                ),
            ),
            ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DocuTrackerMain()),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100 && _label.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(_labelText(tester), 'Showing 1–10 of 13');

      final requestsBefore = requestedPaths.length;
      await _tap(tester, _next);
      expect(_labelText(tester), 'Showing 11–13 of 13');
      await _tap(tester, _prev);
      await _tap(tester, _pageButton(2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        requestedPaths.sublist(requestsBefore),
        isEmpty,
        reason: 'page changes must reuse the loaded data',
      );
      expect(tester.takeException(), isNull);

      final collapseBefore = requestedPaths.length;
      await _tap(tester, find.text('Required actions'));
      expect(_label, findsNothing);
      await _tap(tester, find.text('Required actions'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_labelText(tester), 'Showing 11–13 of 13');
      expect(
        requestedPaths.sublist(collapseBefore),
        isEmpty,
        reason: 'collapsing and expanding must not reload data',
      );
    });
  });
}
