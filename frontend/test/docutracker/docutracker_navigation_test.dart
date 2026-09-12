import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/routes/docutracker_routes.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_main.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          if (call.method == 'containsKey') return false;
          return null;
        });
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.path == '/api/docutracker/permission-explain'
              ? <String, dynamic>{'final_decision': true}
              : <dynamic>[];
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test(
    'DocuTracker navigation opens Documents and has no dashboard section',
    () {
      expect(DocuTrackerRoutes.sections, [
        DocuTrackerSection.documents,
        DocuTrackerSection.admin,
      ]);
      expect(
        DocuTrackerRoutes.sectionFromIndex(0),
        DocuTrackerSection.documents,
      );
      expect(
        DocuTrackerRoutes.sectionFromIndex(-1),
        DocuTrackerSection.documents,
      );
      expect(
        DocuTrackerRoutes.sectionFromIndex(99),
        DocuTrackerSection.documents,
      );
      expect(
        DocuTrackerRoutes.sections.map((section) => section.title),
        isNot(contains('Dashboard')),
      );
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('Documents is the employee landing page at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await _pumpMain(tester);

      expect(find.text('DocuTracker'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(
        find.byKey(const ValueKey('docutracker-document-search')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admins see Documents and Admin without a dashboard tab', (
    tester,
  ) async {
    await _pumpMain(tester, isAdmin: true);

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(
      find.byKey(const ValueKey('docutracker-document-search')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpMain(WidgetTester tester, {bool isAdmin = false}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DocuTrackerMain(isAdmin: isAdmin)),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find
        .byKey(const ValueKey('docutracker-create-document'))
        .evaluate()
        .isNotEmpty) {
      break;
    }
  }
  await tester.pump();
}
