import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_admin_hub.dart';
import 'package:hrms_plaridel/shared/widgets/feature_card.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> wideSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  testWidgets('RSP hub shows four feature cards', (tester) async {
    await wideSurface(tester);
    final opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            child: RspAdminHub(onOpenSection: opened.add),
          ),
        ),
      ),
    );

    expect(find.text('RSP'), findsOneWidget);
    expect(find.text('Job Vacancies (Landing Page)'), findsOneWidget);
    expect(find.text('Recruitment Management'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('Forms'), findsOneWidget);
    expect(find.byType(FeatureCard), findsNWidgets(4));

    await tester.tap(find.text('Recruitment Management'));
    await tester.pump();
    expect(opened, [RspAdminHub.recruitmentManagementSection]);
  });

  testWidgets('recruitment tabs keep every section mounted', (tester) async {
    await wideSurface(tester);
    final created = <String>[];
    var tab = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return RspRecruitmentManagement(
                tabIndex: tab,
                onTabChanged: (next) => setState(() => tab = next),
                applications: _MountedProbe('Applications panel', created),
                examResults: _MountedProbe('Exam Results panel', created),
                scheduling: _MountedProbe('Scheduling panel', created),
                finalRequirements: _MountedProbe(
                  'Final Requirements panel',
                  created,
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Applications'), findsOneWidget);
    expect(find.text('Exam Results'), findsOneWidget);
    expect(find.text('Scheduling'), findsOneWidget);
    expect(find.text('Final Requirements'), findsOneWidget);
    expect(find.text('Applications panel'), findsOneWidget);
    expect(find.text('Exam Results panel'), findsNothing);
    expect(
      created,
      [
        'Applications panel',
        'Exam Results panel',
        'Scheduling panel',
        'Final Requirements panel',
      ],
    );

    await tester.tap(find.text('Scheduling'));
    await tester.pump();
    expect(tab, 2);
    expect(find.text('Scheduling panel'), findsOneWidget);
    expect(find.text('Applications panel'), findsNothing);
    expect(created, hasLength(4));

    await tester.tap(find.text('Final Requirements'));
    await tester.pump();
    expect(tab, 3);
    expect(find.text('Final Requirements panel'), findsOneWidget);
    expect(created, hasLength(4));
  });
}

class _MountedProbe extends StatefulWidget {
  const _MountedProbe(this.label, this.created);

  final String label;
  final List<String> created;

  @override
  State<_MountedProbe> createState() => _MountedProbeState();
}

class _MountedProbeState extends State<_MountedProbe> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.label);
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}
