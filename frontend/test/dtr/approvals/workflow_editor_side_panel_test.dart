import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/approvals_signatories_page.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflows_panel.dart';

const _panelKey = ValueKey('approval-workflow-side-panel');

void main() {
  final calls = <RequestOptions>[];
  var steps = <dynamic>['department', 'hr', 'mayor'];
  Completer<void>? saveGate;

  setUp(() {
    calls.clear();
    steps = ['department', 'hr', 'mayor'];
    saveGate = null;
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          calls.add(request);
          if (request.method == 'PUT' && saveGate != null) {
            await saveGate!.future;
          }
          final dynamic data;
          if (request.path == '/api/approval-workflows' &&
              request.method == 'GET') {
            data = [
              {
                'id': 'full',
                'name': 'Full approval',
                'current_version': 2,
                'steps': steps,
                'is_active': true,
                'self_filing_signatory_policy': 'mayor',
              },
            ];
          } else if (request.path == '/api/employees') {
            data = {'employees': <dynamic>[]};
          } else if (request.path.endsWith('/official-signatories')) {
            data = {'items': <dynamic>[]};
          } else {
            data = <String, dynamic>{};
          }
          handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    bool dark = false,
    bool documentCatalog = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: Scaffold(
          body: documentCatalog
              ? const ApprovalWorkflowsPanel(allowDocumentBinding: true)
              : const SingleChildScrollView(child: ApprovalsSignatoriesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    for (final dark in [false, true]) {
      testWidgets('DTR workflow creation uses a panel at $size, dark=$dark', (
        tester,
      ) async {
        await mount(tester, size: size, dark: dark);
        await tester.tap(find.text('New workflow'));
        await tester.pumpAndSettle();

        expect(find.byKey(_panelKey), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        final panel = tester.getRect(find.byKey(_panelKey));
        expect(panel.right, closeTo(size.width, 0.1));
        expect(panel.top, closeTo(0, 0.1));
        expect(panel.bottom, closeTo(size.height, 0.1));
        if (size.width >= 900) {
          expect(panel.left, greaterThan(0));
        } else {
          expect(panel.left, closeTo(0, 0.1));
        }
        expect(find.text('Create approval workflow'), findsOneWidget);
        expect(find.text('Publish workflow').hitTestable(), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);

        await tester.tap(find.text('Publish workflow'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text('Enter a name and at least one approval step.'),
        );
        expect(calls.where((request) => request.method == 'POST'), isEmpty);
        expect(find.text('Publish workflow').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Close workflow editor'));
        await tester.pumpAndSettle();
        expect(find.byKey(_panelKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'workflow editor reuses the shared draggable and double-tap resize edge',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('New workflow'));
      await tester.pumpAndSettle();
      final panel = find.byKey(_panelKey);
      final initial = tester.getRect(panel);
      await tester.enterText(find.byType(TextFormField).first, 'Resize draft');

      await tester.dragFrom(
        Offset(initial.left + 6, initial.center.dy),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      final expanded = tester.getRect(panel);
      expect(expanded.width, greaterThan(initial.width + 80));
      expect(expanded.right, closeTo(1440, 0.1));
      expect(find.text('Publish workflow').hitTestable(), findsOneWidget);

      Future<void> doubleTapEdge() async {
        final edge = tester.getRect(panel);
        final position = Offset(edge.left + 6, edge.center.dy);
        await tester.tapAt(position);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(position);
        await tester.pumpAndSettle();
      }

      await doubleTapEdge();
      expect(tester.getRect(panel).width, closeTo(1440 - 16, 0.1));
      await doubleTapEdge();
      expect(tester.getRect(panel).width, closeTo(initial.width, 0.1));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Resize draft',
      );
      await tester.tapAt(const Offset(10, 800));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing keeps footer visible, preserves payload and blocks closing during save',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('Edit Full approval'));
      await tester.pumpAndSettle();
      expect(find.byKey(_panelKey), findsOneWidget);
      expect(find.text('Edit approval workflow'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Updated approval',
      );
      final policy = find.byKey(const ValueKey('self-filing-signatory-policy'));
      await tester.ensureVisible(policy);
      await tester.tap(policy);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave blank').last);
      await tester.pumpAndSettle();
      saveGate = Completer<void>();
      await tester.tap(find.text('Update workflow'));
      await tester.pumpAndSettle();

      expect(find.text('Updating…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Close workflow editor',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      final panelContext = tester.element(find.byKey(_panelKey));
      await Navigator.of(panelContext).maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(_panelKey), findsOneWidget);

      saveGate!.complete();
      await tester.pumpAndSettle();
      final write = calls.singleWhere((request) => request.method == 'PUT');
      expect(write.path, '/api/approval-workflows/full');
      expect(write.data['name'], 'Updated approval');
      expect(write.data['steps'], ['department', 'hr', 'mayor']);
      expect(write.data['current_version'], 2);
      expect(write.data['is_active'], true);
      expect(write.data['self_filing_signatory_policy'], 'blank');
      expect(find.byKey(_panelKey), findsNothing);
      expect(
        calls
            .where(
              (request) =>
                  request.path == '/api/approval-workflows' &&
                  request.method == 'GET',
            )
            .length,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile keyboard keeps form scrollable and action footer accessible',
    (tester) async {
      await mount(tester, size: const Size(390, 844));
      await tester.tap(find.text('New workflow'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextFormField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byKey(_panelKey), findsOneWidget);
      final publish = find.text('Publish workflow');
      expect(publish.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(publish).dy, lessThanOrEqualTo(844 - 300));
      await tester.ensureVisible(
        find.byKey(const ValueKey('self-filing-signatory-policy')),
      );
      await tester.pumpAndSettle();
      expect(publish.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long workflows scroll beneath a fixed title and footer', (
    tester,
  ) async {
    steps = [
      for (var i = 0; i < 15; i++)
        {
          'step_order': i + 1,
          'label': 'Review stage ${i + 1}',
          'assignee_type': 'user',
          'assignee_source': 'active_mayor',
          'user_ids': <String>[],
          'requires_signature': true,
          'allowed_actions': ['approve', 'return', 'reject'],
        },
    ];
    await mount(tester);
    await tester.tap(find.byTooltip('Edit Full approval'));
    await tester.pumpAndSettle();
    expect(find.byKey(_panelKey), findsOneWidget);
    final titleBeforeScroll = tester.getRect(
      find.text('Edit approval workflow'),
    );
    final actionBeforeScroll = tester.getRect(find.text('Update workflow'));
    await tester.ensureVisible(
      find.byKey(const ValueKey('self-filing-signatory-policy')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Edit approval workflow')),
      titleBeforeScroll,
    );
    expect(tester.getRect(find.text('Update workflow')), actionBeforeScroll);
    expect(find.text('Update workflow').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.where((request) => request.method == 'PUT'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DocuTracker shared catalog keeps its centered workflow dialog', (
    tester,
  ) async {
    await mount(tester, documentCatalog: true);
    await tester.tap(find.text('New workflow'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(_panelKey), findsNothing);
    expect(find.text('Create approval workflow'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
