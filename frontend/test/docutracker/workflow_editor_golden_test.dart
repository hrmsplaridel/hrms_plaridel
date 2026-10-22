import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_workflow_editor_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _WorkflowEditorApiStub api;

  setUpAll(() async {
    final fonts = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await fonts.load();
  });

  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    api = _WorkflowEditorApiStub();
    ApiClient.instance.dio.interceptors.add(api.interceptor);
  });

  DocumentRoutingConfig buildConfig() {
    return const DocumentRoutingConfig(
      documentType: DocumentType.memo,
      reviewDeadlineHours: 24,
      version: 1,
      steps: [
        WorkflowStep(stepOrder: 1, assigneeType: 'user', label: 'Draft Intake'),
        WorkflowStep(
          stepOrder: 2,
          assigneeType: 'user',
          label: 'Finance Review',
        ),
        WorkflowStep(
          stepOrder: 3,
          assigneeType: 'user',
          label: 'Final Approval',
        ),
      ],
    );
  }

  DocumentRoutingConfig buildLongConfig() {
    return DocumentRoutingConfig(
      documentType: DocumentType.memo,
      reviewDeadlineHours: 24,
      version: 1,
      steps: const [
        WorkflowStep(stepOrder: 1, assigneeType: 'user', label: 'Draft Intake'),
        WorkflowStep(
          stepOrder: 2,
          assigneeType: 'user',
          label: 'Records Check',
        ),
        WorkflowStep(stepOrder: 3, assigneeType: 'user', label: 'HR Review'),
        WorkflowStep(
          stepOrder: 4,
          assigneeType: 'user',
          label: 'Finance Review',
        ),
        WorkflowStep(stepOrder: 5, assigneeType: 'user', label: 'Legal Review'),
        WorkflowStep(
          stepOrder: 6,
          assigneeType: 'user',
          label: 'Department Head',
        ),
        WorkflowStep(
          stepOrder: 7,
          assigneeType: 'user',
          label: 'Final Approval',
        ),
        WorkflowStep(stepOrder: 8, assigneeType: 'user', label: 'Release'),
      ],
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size viewport,
    required DocumentRoutingConfig config,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewport;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: DocuTrackerWorkflowEditorScreen(initialConfig: config),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(api.unexpectedPaths, isEmpty);
    expect(api.requestedPaths, contains('/api/docutracker/workflow-steps'));
    expect(find.byType(DocuTrackerErrorBanner), findsNothing);
    expect(find.text('Step assignees could not be loaded'), findsNothing);
    expect(find.text('Fix before save'), findsOneWidget);
    expect(
      find.textContaining(
        'Choose a primary reviewer (and optional backups).',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('workflow editor shell golden', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1440, 2400),
      config: buildConfig(),
    );

    expect(find.text('Draft Intake'), findsOneWidget);
    expect(find.text('Finance Review'), findsOneWidget);
    expect(find.text('Final Approval'), findsOneWidget);
    expect(find.text('Publish workflow'), findsOneWidget);

    // matchesGoldenFile compares pixels asynchronously. expect() returns
    // before that finishes, and the test binding then records the mismatch
    // only after it has already treated the test as successful. expectLater
    // keeps the test open until the mismatch is reported.
    await expectLater(
      find.byType(DocuTrackerWorkflowEditorScreen),
      matchesGoldenFile('goldens/docutracker/workflow_editor_shell.png'),
    );
  });

  testWidgets('workflow editor narrow viewport golden', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1024, 1800),
      config: buildConfig(),
    );

    expect(find.text('Draft Intake'), findsOneWidget);
    expect(find.text('Publish workflow'), findsOneWidget);

    await expectLater(
      find.byType(DocuTrackerWorkflowEditorScreen),
      matchesGoldenFile('goldens/docutracker/workflow_editor_shell_narrow.png'),
    );
  });

  testWidgets('workflow editor long-list golden', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1440, 2400),
      config: buildLongConfig(),
    );

    expect(find.text('Draft Intake'), findsOneWidget);

    await expectLater(
      find.byType(DocuTrackerWorkflowEditorScreen),
      matchesGoldenFile(
        'goldens/docutracker/workflow_editor_shell_long_list.png',
      ),
    );
  });

  testWidgets('long workflow list can scroll to every step', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1440, 2400),
      config: buildLongConfig(),
    );

    const labels = [
      'Draft Intake',
      'Records Check',
      'HR Review',
      'Finance Review',
      'Legal Review',
      'Department Head',
      'Final Approval',
      'Release',
    ];
    for (final label in labels) {
      await tester.scrollUntilVisible(
        find.text(label),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

/// Answers the workflow editor's startup reads without HTTP.
///
/// Workflow steps come back empty so the golden fixtures keep their labels
/// and the missing-reviewer validation. Any other path is rejected.
class _WorkflowEditorApiStub {
  final List<String> requestedPaths = <String>[];
  final List<String> unexpectedPaths = <String>[];

  late final Interceptor interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      requestedPaths.add(options.path);
      final data = switch (options.path) {
        '/api/docutracker/workflow-steps' => <dynamic>[],
        '/api/docutracker/release-policies' => <String, dynamic>{
          'policies': <dynamic>[],
        },
        '/api/departments' => <dynamic>[],
        '/api/departments/reviewer-readiness' => <String, dynamic>{
          'departments': <dynamic>[],
        },
        _ => null,
      };
      if (data == null) {
        unexpectedPaths.add(options.path);
        handler.reject(
          DioException(
            requestOptions: options,
            message: 'Unexpected workflow-editor request: ${options.path}',
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }
      handler.resolve(
        Response<dynamic>(requestOptions: options, statusCode: 200, data: data),
      );
    },
  );
}
