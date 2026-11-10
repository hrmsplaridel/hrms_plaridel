import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/official_signatory.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_official_signatories_screen.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';

OfficialSignatoryPeriod _period({
  required String roleKey,
  required String employeeId,
  required String name,
}) {
  return OfficialSignatoryPeriod(
    id: roleKey,
    roleKey: roleKey,
    employeeId: employeeId,
    name: name,
    positionTitle: 'Position',
    departmentName: 'Department',
    effectiveFrom: DateTime(2026, 1, 1),
    isEffective: true,
  );
}

void _ignoreConfigure(String roleKey) {}

void main() {
  testWidgets('missing memorandum assignments stay visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              DocuTrackerMemorandumSignatorySection(
                periods: [],
                onConfigure: _ignoreConfigure,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Memorandum'), findsOneWidget);
    expect(find.text('Prepared by'), findsOneWidget);
    expect(find.text('Noted by'), findsOneWidget);
    expect(find.text('Approved by'), findsOneWidget);
    expect(find.text('HR Department Head'), findsOneWidget);
    expect(find.text("Mayor's Office representative"), findsOneWidget);
    expect(find.text('Municipal Mayor'), findsOneWidget);
    expect(
      find.textContaining('Missing: Prepared by, Noted by, Approved by'),
      findsOneWidget,
    );
    expect(find.text('Not configured'), findsNWidgets(3));
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(find.text('No official is configured for today.'), findsNothing);
  });

  testWidgets('automatic memorandum signers stay separate from configuration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              DocuTrackerMemorandumSignatorySection(
                periods: const [],
                onConfigure: _ignoreConfigure,
                resolution: DocuTrackerMemoSignatories.fromJson({
                  'prepared_by': {
                    'id': '11111111-1111-4111-8111-111111111111',
                    'full_name': 'HR Head',
                    'position': 'Department Head',
                  },
                  'noted_by': {
                    'id': '22222222-2222-4222-8222-222222222222',
                    'full_name': "Mayor's Office",
                    'position': "Mayor's Office",
                  },
                  'approved_by': null,
                  'configuration': {
                    'mode': 'automatic',
                    'ready': false,
                    'missing': ['Prepared by', 'Noted by', 'Approved by'],
                  },
                }),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Not configured'), findsNWidgets(3));
    expect(find.text('Currently automatic'), findsNWidgets(3));
    expect(find.text('HR Head'), findsOneWidget);
    expect(find.text("Mayor's Office"), findsNWidgets(2));
    expect(find.text('None available'), findsOneWidget);
    expect(
      find.textContaining('not saved Official Signatories'),
      findsOneWidget,
    );
  });

  testWidgets('a saved role still shows the automatic signer until all three '
      'are valid', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              DocuTrackerMemorandumSignatorySection(
                periods: [
                  _period(
                    roleKey: 'memo_prepared_by',
                    employeeId: 'configured-hr',
                    name: 'Configured HR',
                  ),
                ],
                onConfigure: _ignoreConfigure,
                resolution: DocuTrackerMemoSignatories.fromJson({
                  'prepared_by': {
                    'id': '11111111-1111-4111-8111-111111111111',
                    'full_name': 'Automatic HR',
                  },
                  'noted_by': null,
                  'approved_by': null,
                  'configuration': {
                    'mode': 'automatic',
                    'ready': false,
                    'missing': ['Noted by', 'Approved by'],
                  },
                }),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Configured HR'), findsOneWidget);
    expect(find.text('Automatic HR'), findsOneWidget);
    expect(find.text('Not configured'), findsNWidgets(2));
    expect(find.text('None available'), findsNWidgets(2));
    expect(find.textContaining('still use automatic'), findsOneWidget);
    expect(find.text('Current'), findsNothing);
  });

  testWidgets(
    'a complete memorandum configuration says new documents switch together',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                DocuTrackerMemorandumSignatorySection(
                  periods: [
                    _period(
                      roleKey: 'memo_prepared_by',
                      employeeId: 'hr',
                      name: 'HR Head',
                    ),
                    _period(
                      roleKey: 'memo_noted_by',
                      employeeId: 'office',
                      name: "Mayor's Office",
                    ),
                    _period(
                      roleKey: 'memo_approved_by',
                      employeeId: 'mayor',
                      name: 'Hon. Maria Santos',
                    ),
                  ],
                  onConfigure: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Existing documents stay unchanged'),
        findsOneWidget,
      );
      expect(find.text('HR Head'), findsOneWidget);
      expect(find.text('Hon. Maria Santos'), findsOneWidget);
      expect(find.text('Current'), findsNWidgets(3));
    },
  );

  testWidgets('the same Noted by and Approved by account is called out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              DocuTrackerMemorandumSignatorySection(
                periods: [
                  _period(
                    roleKey: 'memo_prepared_by',
                    employeeId: 'hr',
                    name: 'HR Head',
                  ),
                  _period(
                    roleKey: 'memo_noted_by',
                    employeeId: 'office',
                    name: 'Office',
                  ),
                  _period(
                    roleKey: 'memo_approved_by',
                    employeeId: 'office',
                    name: 'Office',
                  ),
                ],
                onConfigure: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('same account'), findsOneWidget);
  });

  testWidgets('identical names stay selectable by account', (tester) async {
    String? selected;
    final employees = [
      const EmployeeDirectoryEntry(
        id: 'maria-hr',
        fullName: 'Maria Santos',
        departmentName: 'HR Office',
        positionName: 'Department Head',
        roleId: 'employee',
      ),
      const EmployeeDirectoryEntry(
        id: 'maria-mayor',
        fullName: 'Maria Santos',
        departmentName: "Mayor's Office",
        positionName: 'Staff',
        roleId: 'mayor_office_staff',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: DocuTrackerSignatoryEmployeeField(
              employees: employees,
              value: null,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DocuTrackerSignatoryEmployeeField));
    await tester.pumpAndSettle();

    expect(find.text('HR Office · Department Head · Employee'), findsOneWidget);
    expect(
      find.text("Mayor's Office · Staff · Mayor's Office Staff"),
      findsOneWidget,
    );

    await tester.tap(find.text('HR Office · Department Head · Employee'));
    await tester.pumpAndSettle();

    expect(selected, 'maria-hr');
  });

  testWidgets('signatory controls fit tablet and desktop widths', (
    tester,
  ) async {
    const sizes = <Size>[Size(800, 900), Size(1024, 900), Size(1280, 900)];
    final themes = <ThemeData>[
      ThemeData(brightness: Brightness.light, useMaterial3: true),
      ThemeData(brightness: Brightness.dark, useMaterial3: true),
    ];

    for (final size in sizes) {
      for (final theme in themes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: DocuTrackerOfficialSignatoryPanel(
                roleKey: 'memo_prepared_by',
                employees: const [
                  EmployeeDirectoryEntry(
                    id: 'hr',
                    fullName: 'Maria Santos',
                    departmentName: 'HR Office',
                    positionName: 'Department Head',
                    roleId: 'employee',
                  ),
                ],
                current: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.textContaining('From '), findsOneWidget);
        expect(find.text('No end date'), findsOneWidget);
        expect(find.text('Select employee'), findsOneWidget);

        await tester.tap(find.textContaining('From '));
        await tester.pumpAndSettle();
        expect(find.text('OK'), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(find.text('Configure is not saved'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('builder configuration status explains an incomplete switch', () {
    final signatories = DocuTrackerMemoSignatories.fromJson({
      'prepared_by': null,
      'noted_by': {
        'id': '22222222-2222-4222-8222-222222222222',
        'full_name': "Mayor's Office",
        'position': "Mayor's Office",
      },
      'approved_by': null,
      'configuration': {
        'mode': 'automatic',
        'ready': false,
        'missing': ['Prepared by', 'Approved by'],
        'conflict': null,
      },
    });

    expect(signatories, isNotNull);
    expect(signatories!.configuration!.usesAutomaticResolution, isTrue);
    expect(
      signatories.configuration!.statusMessage,
      contains('Missing: Prepared by, Approved by'),
    );
  });
}
