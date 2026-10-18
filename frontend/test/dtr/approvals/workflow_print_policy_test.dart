import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflows_panel.dart';

void main() {
  for (final width in [390.0, 1400.0]) {
    for (final policy in ['mayor', 'blank', 'actual_reviewer']) {
      testWidgets('workflow edit loads and saves $policy at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        final writes = <RequestOptions>[];
        ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (o.method != 'GET') writes.add(o);
          h.resolve(Response(requestOptions: o, statusCode: 200, data: o.path == '/api/approval-workflows' && o.method == 'GET' ? [{
            'id': 'workflow', 'name': 'Workflow', 'current_version': 4,
            'is_active': true, 'steps': ['department', 'hr'], 'self_filing_signatory_policy': policy,
          }] : o.method == 'GET' ? [] : {'id': 'workflow'}));
        }));
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ApprovalWorkflowsPanel(initialWorkflowId: 'workflow'))));
        await tester.pumpAndSettle();
        final dropdown = find.byKey(const ValueKey('self-filing-signatory-policy'));
        expect(dropdown, findsOneWidget);
        expect(tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue, policy);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        final next = policy == 'blank' ? 'actual_reviewer' : 'blank';
        await tester.tap(find.text(next == 'blank' ? 'Leave blank' : 'Show actual approving reviewer').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Update workflow'));
        await tester.pumpAndSettle();
        expect(writes.single.data['self_filing_signatory_policy'], next);
        expect(writes.single.data['current_version'], 4);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('workflow creation offers the default Mayor policy and all three choices', (tester) async {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    addTearDown(() => ApiClient.instance.dio.interceptors.clear());
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: []))));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ApprovalWorkflowsPanel())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workflow'));
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const ValueKey('self-filing-signatory-policy'));
    expect(dropdown, findsOneWidget);
    expect(tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue, 'mayor');
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    for (final label in ['Replace with Mayor', 'Leave blank', 'Show actual approving reviewer']) {
      expect(find.text(label), findsWidgets);
    }
  });
}
