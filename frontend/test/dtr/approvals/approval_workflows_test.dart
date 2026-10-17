import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflows_panel.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflow_picker.dart';

void main() {
  final requests = <RequestOptions>[];
  setUp(() {
    ApiClient.instance.init();
    requests.clear();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path.contains('/routing/')
                  ? {'approval_workflow_id': 'full'}
                  : options.method == 'GET'
                  ? [
                      {
                        'id': 'full',
                        'name': 'Full approval',
                        'current_version': 2,
                        'steps': ['department', 'hr', 'mayor'],
                        'employment_types': ['job_order'],
                        'is_active': true,
                      },
                      {
                        'id': 'inactive',
                        'name': 'Archived workflow',
                        'current_version': 1,
                        'steps': ['hr'],
                        'is_active': false,
                      },
                    ]
                  : {'id': 'new'},
            ),
          );
        },
      ),
    );
  });
  testWidgets(
    'type picker loads named workflows, previews steps and emits the selected ID',
    (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalWorkflowPicker(
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Archived workflow'), findsNothing);
      await tester.tap(find.text('Full approval · v2').last);
      await tester.pumpAndSettle();
      expect(selected?['approval_workflow_id'], 'full');
      expect(find.textContaining('Other employment types:'), findsNothing);
      expect(
        find.text('Department Review → HR Review → Mayor Approval'),
        findsOneWidget,
      );
    },
  );
  testWidgets('new workflow controls describe workflow activation only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ApprovalWorkflowsPanel())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workflow'));
    await tester.pumpAndSettle();
    expect(find.text('Active workflow'), findsOneWidget);
    expect(find.text('Available for filing'), findsNothing);
    expect(find.text('Limit to employment types'), findsNothing);
    expect(find.text('Publish workflow'), findsOneWidget);
  });
  testWidgets(
    'central editor updates named ordered steps and preserves concurrency version',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ApprovalWorkflowsPanel())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Full approval'));
      await tester.pumpAndSettle();
      expect(find.text('Update workflow'), findsOneWidget);
      expect(find.text('Publish workflow'), findsNothing);
      expect(find.text('Limit to employment types'), findsNothing);
      expect(find.text('Available for filing'), findsNothing);
      expect(find.text('Active workflow'), findsOneWidget);
      expect(
        find.text(
          'Updating creates a new version for future filings. Existing requests retain their saved version.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full approval'),
        'Full approval updated',
      );
      await tester.ensureVisible(find.text('Active workflow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active workflow'));
      await tester.tap(find.text('Update workflow'));
      await tester.pumpAndSettle();
      final write = requests.singleWhere((r) => r.method == 'PUT');
      expect(write.data['current_version'], 2);
      expect(write.data['steps'], ['department', 'hr', 'mayor']);
      expect(write.data['name'], 'Full approval updated');
      expect(write.data['is_active'], false);
      expect((write.data as Map).containsKey('employment_types'), false);
    },
  );
  testWidgets('linked document opens its selected shared workflow editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApprovalWorkflowsPanel(initialWorkflowId: 'inactive'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller
          ?.text,
      'Archived workflow',
    );
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets('workflow cards stay separated at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            cardTheme: const CardThemeData(margin: EdgeInsets.zero),
          ),
          home: const Scaffold(body: ApprovalWorkflowsPanel()),
        ),
      );
      await tester.pumpAndSettle();
      final cards = find.byType(Card);
      expect(cards, findsNWidgets(2));
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      expect(second.top - first.bottom, greaterThanOrEqualTo(12));
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 390) {
        await tester.tap(find.byTooltip('Edit Full approval'));
        await tester.pumpAndSettle();
        expect(find.text('Edit approval workflow'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('long workflow names wrap without obsolete employment badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: [
              {
                'id': 'restricted',
                'name': 'Department approval followed by manual Mayor signing',
                'current_version': 3,
                'steps': ['department', 'manual_mayor'],
                'employment_types': ['job_order', 'contract_of_service'],
                'is_active': true,
              },
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: const Scaffold(body: ApprovalWorkflowsPanel()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Applies to: Job Order (JO), Contract of Service (COS)'),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byTooltip(
        'Edit Department approval followed by manual Mayor signing',
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
