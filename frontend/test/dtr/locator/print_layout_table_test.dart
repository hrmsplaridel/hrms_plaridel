import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_layout_pdf.dart';

Map<String, dynamic> tableJson() => {
  'version': 1,
  'orientation': 'portrait',
  'elements': [
    {
      'id': 'table',
      'kind': 'table',
      'x': 40,
      'y': 180,
      'width': 400,
      'height': 120,
      'font_size': 11,
      'column_widths': [1, 2],
      'header_row': true,
      'borders': true,
      'cells': [
        [
          {'kind': 'text', 'text': 'Employee'},
          {'kind': 'text', 'text': 'Destination'},
        ],
        [
          {'kind': 'field', 'source': 'employee_name'},
          {'kind': 'field', 'source': 'custom:destination'},
        ],
      ],
    },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('table data survives parsing, moving and serialization', () {
    final layout = LocatorPrintLayout.fromJson(tableJson());
    expect(layout.validate(), isNull);
    final moved = layout
        .copyWith(elements: [layout.elements.single.copyWith(x: 80)])
        .toJson();
    expect(moved['elements'][0]['cells'], tableJson()['elements'][0]['cells']);
    expect(moved['elements'][0]['column_widths'], [1, 2]);
  });
  test('table geometry and text limits are checked locally', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (t) => t['height'] = 20,
      (t) => t['column_widths'] = [0, 1],
      (t) => t['cells'][0][0]['text'] = 'x' * 501,
    ]) {
      final json = tableJson();
      change(json['elements'][0]);
      expect(LocatorPrintLayout.fromJson(json).validate(), isNotNull);
    }
  });
  test(
    'short table-bound custom answers print on one page; long answers continue',
    () async {
      final layout = LocatorPrintLayout.fromJson(tableJson());
      Future<List<int>> render(String answer) => buildLocatorLayoutPdf(
        layout: layout,
        form: {
          'employee_name': 'Ana',
          'additional_details': {'destination': answer},
          'employee_detail_schema_snapshot': [
            {'key': 'destination', 'label': 'Destination'},
          ],
        },
        signatories: const LocatorFormSignatories(),
      );
      final pages = RegExp(r'/Type\s*/Page\b');
      expect(
        pages.allMatches(latin1.decode(await render('Municipal Hall'))).length,
        1,
      );
      expect(
        pages
            .allMatches(
              latin1.decode(
                await render(List.filled(400, 'Long destination').join(' ')),
              ),
            )
            .length,
        greaterThan(1),
      );
    },
  );
  test('leave tables print leave-specific fields using the shared renderer',()async{
    final json=tableJson();json['elements'][0]['cells'][1]=[{'kind':'field','source':'inclusive_dates'},{'kind':'field','source':'working_days'}];
    final bytes=await buildLeaveLayoutPdf(layout:LocatorPrintLayout.fromJson(json),request:LeaveRequest(userId:'employee',employeeName:'Ana',leaveType:LeaveType.vacationLeave,startDate:DateTime(2026,10,13),endDate:DateTime(2026,10,14),workingDaysApplied:2));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,1);
  });
  testWidgets('designer inserts, edits and applies a table', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    LocatorPrintLayout? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<LocatorPrintLayout>(
                  context: context,
                  builder: (_) => LocatorPrintLayoutEditor(
                    requestType: LocatorRequestType.locator.copyWith(
                      employeeDetailSchema: const [
                        LeaveCustomFieldDefinition(
                          key: 'destination',
                          label: 'Destination',
                        ),
                      ],
                    ),
                    onPreview: (_) async {},
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
    await tester.tap(find.text('Insert table'));
    await tester.pumpAndSettle();
    expect(find.text('Table rows'), findsOneWidget);
    expect(find.text('Column widths'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('table-cell-text')));
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-text')),
      'Summary',
    );
    await tester.pump();
    final node = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('layout-node-item_'),
    );
    await tester.drag(node, const Offset(40, 20));
    await tester.pumpAndSettle();
    Finder dropdown(String label) => find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField && w.decoration.labelText == label,
    );
    tester
        .widget<DropdownButtonFormField<int>>(dropdown('Table rows'))
        .onChanged!(4);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<int>>(dropdown('Table columns'))
        .onChanged!(3);
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const ValueKey('table-column-width-0')))
        .onChanged!(2);
    await tester.pump();
    tester
        .widget<Checkbox>(find.byKey(const ValueKey('table-header-row')))
        .onChanged!(false);
    await tester.pump();
    tester
        .widget<Checkbox>(find.byKey(const ValueKey('table-borders')))
        .onChanged!(false);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<int>>(dropdown('Cell row'))
        .onChanged!(1);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<int>>(dropdown('Cell column'))
        .onChanged!(2);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(dropdown('Cell content'))
        .onChanged!('field');
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(dropdown('Request field'))
        .onChanged!('custom:destination');
    await tester.pump();
    await tester.tap(find.text('Use layout'));
    await tester.pumpAndSettle();
    final table = saved!.toJson()['elements'].singleWhere(
      (e) => e['kind'] == 'table',
    );
    expect(table['cells'][0][0]['text'], 'Summary');
    expect(table['column_widths'], [2, 1, 1]);
    expect(table['cells'].length, 4);
    expect(table['cells'][1][2]['source'], 'custom:destination');
    expect(table['header_row'], false);
    expect(table['borders'], false);
    expect(table['x'], greaterThan(40));
  });
}
