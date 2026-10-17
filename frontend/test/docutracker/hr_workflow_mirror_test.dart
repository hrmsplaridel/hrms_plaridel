import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/hr_workflow_mirror.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_admin_ui.dart';

void main() {
  const payload = <String, dynamic>{
    'key': 'leave',
    'title': 'Leave Request',
    'source_label': 'Synced from DTR',
    'effective_date': '2026-09-29',
    'system_managed': true,
    'steps': [
      {
        'step_order': 1,
        'label': 'Department Review',
        'assignee_summary': 'Dynamic by department · 1 head · 1 backup',
        'groups': [
          {
            'scope_id': 'dept-1',
            'scope_name': 'Human Resources',
            'primary': {
              'id': 'head-1',
              'name': 'Department Head',
              'role': 'primary',
            },
            'backups': [
              {
                'id': 'backup-1',
                'name': 'Backup Reviewer',
                'role': 'backup',
                'backup_rank': 1,
              },
            ],
          },
        ],
      },
      {
        'step_order': 2,
        'label': 'Final HR Review',
        'assignee_summary': 'Primary: HR Admin · 0 backups',
        'groups': [],
      },
    ],
  };

  test('mirror model parses reviewer groups', () {
    final workflow = HrWorkflowMirror.fromJson(payload);

    expect(workflow.title, 'Leave Request');
    expect(workflow.systemManaged, isTrue);
    expect(workflow.steps, hasLength(2));
    expect(workflow.steps.first.groups.single.primary?.name, 'Department Head');
    expect(workflow.steps.first.groups.single.backups.single.backupRank, 1);
  });

  testWidgets('mirrored workflow card is visibly read only', (tester) async {
    var viewed = false;
    final workflow = HrWorkflowMirror.fromJson(payload);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: DocuTrackerMirroredWorkflowCard(
              workflow: workflow,
              onView: () => viewed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Leave Request'), findsOneWidget);
    expect(find.text('System-managed'), findsOneWidget);
    expect(find.text('Synced from DTR'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);

    await tester.tap(find.text('View details'));
    expect(viewed, isTrue);
  });

  for (final width in [1100.0, 380.0]) {
    testWidgets('shared workflow card summarizes its types at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workflow = HrWorkflowMirror.fromJson({
        ...payload,
        'key': 'workflow:standard:v1',
        'title': 'Department - Final HR v1',
        'used_by': [
          {'module': 'leave', 'type_id': 'sick', 'type_name': 'Sick Leave'},
          {
            'module': 'leave',
            'type_id': 'vacation',
            'type_name': 'Vacation Leave',
          },
          {
            'module': 'locator',
            'type_id': 'business',
            'type_name': 'Official Business',
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocuTrackerMirroredWorkflowCard(
                workflow: workflow,
                onView: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Department - Final HR v1'), findsOneWidget);
      expect(
        find.text('Used by 2 leave types · 1 locator type'),
        findsOneWidget,
      );
      expect(find.text('Sick Leave'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('workflow details expand the complete list of types using it', (
    tester,
  ) async {
    final workflow = HrWorkflowMirror.fromJson({
      ...payload,
      'used_by': [
        {'module': 'leave', 'type_id': 'sick', 'type_name': 'Sick Leave'},
        {'module': 'locator', 'type_id': 'travel', 'type_name': 'Travel Order'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocuTrackerWorkflowUsageDetails(workflow: workflow),
          ),
        ),
      ),
    );
    expect(find.text('Sick Leave'), findsNothing);
    await tester.tap(find.text('Used by'));
    await tester.pumpAndSettle();
    expect(find.text('Sick Leave'), findsOneWidget);
    expect(find.text('Travel Order'), findsOneWidget);
    expect(find.text('Leave type'), findsOneWidget);
    expect(find.text('Locator type'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
