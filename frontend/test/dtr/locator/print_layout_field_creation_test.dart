import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_print_settings.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_settings.dart';
import 'designer_field_test_helpers.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/print_layout_field_dialog.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/shared/widgets/locator_custom_fields.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  Future<void> size(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets(
    'new select field is staged for preview and committed only with Use layout',
    (tester) async {
      await size(tester);
      List<LeaveCustomFieldDefinition>? committed, previewFields;
      LocatorPrintLayout? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<LocatorPrintLayout>(
                    context: context,
                    builder: (_) => LocatorPrintLayoutEditor(
                      requestType: LocatorRequestType.locator,
                      onCustomFieldsChanged: (v) => committed = v,
                      onPreview: (_) async {},
                      onPreviewWithFields: (_, fields) async =>
                          previewFields = fields,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await createDesignerField(
        tester,
        'Travel category',
        type: LeaveCustomFieldType.select,
      );
      expect(committed, isNull);
      expect(find.text('Local'), findsWidgets);
      await tester.tap(find.text('Preview layout'));
      await tester.pumpAndSettle();
      expect(previewFields!.single.label, 'Travel category');
      expect(committed, isNull);
      await tester.tap(find.text('Use layout'));
      await tester.pumpAndSettle();
      expect(committed!.single.options, ['Local', 'Overseas']);
      expect(committed!.single.required, true);
      expect(result!.elements.last.source, 'custom:${committed!.single.key}');
      final key = GlobalKey<FormState>();
      final values = <String, dynamic>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: key,
              child: LocatorCustomFieldInputs(
                fields: committed!,
                values: values,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Travel category *'), findsOneWidget);
      expect(key.currentState!.validate(), false);
      await tester.pump();
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!('Local');
      await tester.pump();
      expect(values[committed!.single.key], 'Local');
    },
  );
  testWidgets('cancelling designer discards new fields', (tester) async {
    await size(tester);
    List<LeaveCustomFieldDefinition>? committed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => LocatorPrintLayoutEditor(
                  requestType: LocatorRequestType.locator,
                  onCustomFieldsChanged: (v) => committed = v,
                  onPreview: (_) async {},
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await createDesignerField(tester, 'Discarded field');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(committed, isNull);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Insert field'));
    await tester.pumpAndSettle();
    expect(find.text('Discarded field'), findsNothing);
  });
  testWidgets(
    'additional field limit disables creation without affecting existing fields',
    (tester) async {
      await size(tester);
      final fields = List.generate(
        20,
        (i) => LeaveCustomFieldDefinition(key: 'extra_$i', label: 'Extra $i'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocatorPrintLayoutEditor(
              requestType: LocatorRequestType.locator.copyWith(
                employeeDetailSchema: fields,
              ),
              onCustomFieldsChanged: (_) {},
              onPreview: (_) async {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Insert field'));
      await tester.pumpAndSettle();
      final item = find.ancestor(
        of: find.text('Create new field'),
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(tester.widget<PopupMenuItem<String>>(item).enabled, false);
      expect(find.text('Extra 0'), findsWidgets);
    },
  );
  testWidgets('field dialog rejects blank labels and invalid select choices', (
    tester,
  ) async {
    await size(tester);
    LeaveCustomFieldDefinition? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<LeaveCustomFieldDefinition>(
                  context: context,
                  builder: (_) =>
                      const PrintLayoutFieldDialog(existingFields: []),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create field'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a field label.'), findsOneWidget);
    expect(result, isNull);
    final label = find.ancestor(
      of: find.text('Field label'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(label, 'Trip type');
    tester
        .widget<DropdownButtonFormField<LeaveCustomFieldType>>(
          find.byType(DropdownButtonFormField<LeaveCustomFieldType>),
        )
        .onChanged!(LeaveCustomFieldType.select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create field'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least one option.'), findsOneWidget);
    final options = find.ancestor(
      of: find.text('Options (one per line)'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(
      options,
      List.generate(21, (i) => 'Choice $i').join('\n'),
    );
    await tester.tap(find.text('Create field'));
    await tester.pumpAndSettle();
    expect(find.text('Use at most 20 options.'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(options, 'Local\nLocal\n Overseas ');
    await tester.tap(find.text('Create field'));
    await tester.pumpAndSettle();
    expect(result!.options, ['Local', 'Overseas']);
  });
  for (final leave in [false, true]) {
    testWidgets(
      'new fields require saving the type before standalone print settings (leave: $leave)',
      (tester) async {
        await size(tester);
        var fields = <LeaveCustomFieldDefinition>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'layout': 'csc',
                  'print_layout': null,
                  'has_background': false,
                },
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => leave
                    ? LeavePrintSettings(
                        leaveTypeId: 'type',
                        readLeaveType: () => LeaveTypeDefinition(
                          name: 'custom',
                          displayName: 'Custom leave',
                          employeeDetailSchema: fields,
                        ),
                        onCustomFieldsChanged: (v) =>
                            setState(() => fields = v),
                      )
                    : LocatorPrintSettings(
                        typeId: 'type',
                        readRequestType: () => LocatorRequestType.locator
                            .copyWith(employeeDetailSchema: fields),
                        onCustomFieldsChanged: (v) =>
                            setState(() => fields = v),
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Design layout'));
        await tester.pumpAndSettle();
        await createDesignerField(tester, 'New date');
        await tester.tap(find.text('Use layout'));
        await tester.pumpAndSettle();
        expect(fields.single.label, 'New date');
        final button = find.ancestor(
          of: find.text('Save print settings'),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(
          find.text('Save the type changes to keep the new fields and layout.'),
          findsOneWidget,
        );
      },
    );
  }
}
