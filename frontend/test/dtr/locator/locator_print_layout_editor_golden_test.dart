import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
    for (final family in ['NotoSerif', 'NotoSansMono']) {
      final fontLoader = FontLoader(family)
        ..addFont(
          rootBundle.load('assets/fonts/form-layout/$family-Regular.ttf'),
        )
        ..addFont(rootBundle.load('assets/fonts/form-layout/$family-Bold.ttf'));
      await fontLoader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  final type = LocatorRequestType.locator.copyWith(
    label: 'Travel Order',
    locationLabel: 'Purpose of travel',
    employeeDetailSchema: const [
      LeaveCustomFieldDefinition(
        key: 'destination',
        label: 'Place of Destination',
      ),
      LeaveCustomFieldDefinition(
        key: 'departure',
        label: 'Date of Departure',
        type: LeaveCustomFieldType.date,
      ),
      LeaveCustomFieldDefinition(
        key: 'return',
        label: 'Expected Date of Return',
        type: LeaveCustomFieldType.date,
      ),
    ],
  );
  for (final (name, size, dark, settings) in [
    ('desktop', const Size(1440, 900), false, false),
    ('table', const Size(1440, 900), false, false),
    ('page_settings', const Size(1440, 900), false, false),
    ('dark', const Size(1440, 900), true, false),
    ('mobile', const Size(390, 844), false, false),
    ('mobile_settings', const Size(390, 844), false, true),
  ]) {
    testWidgets('print editor $name layout', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
            body: LocatorPrintLayoutEditor(
              requestType: type,
              initialLayout: name == 'page_settings'
                  ? const LocatorPrintLayout(
                      paperSize: 'long',
                      fontFamily: 'serif',
                      defaultFontSize: 14,
                      margins: PrintLayoutMargins(
                        top: 36,
                        right: 36,
                        bottom: 36,
                        left: 36,
                      ),
                      elements: [
                        LocatorPrintElement(
                          id: 'title',
                          kind: 'text',
                          text: 'TRAVEL ORDER',
                          x: 60,
                          y: 90,
                          width: 480,
                          height: 70,
                          fontSize: 32,
                          bold: true,
                          align: 'center',
                        ),
                        LocatorPrintElement(
                          id: 'name',
                          kind: 'field',
                          source: 'employee_name',
                          label: 'Employee name',
                          x: 60,
                          y: 180,
                          width: 400,
                          height: 70,
                          fontSize: 18,
                          fontFamily: 'sans',
                        ),
                        LocatorPrintElement(
                          id: 'office',
                          kind: 'field',
                          source: 'office',
                          label: 'Purpose of travel',
                          x: 60,
                          y: 260,
                          width: 400,
                          height: 70,
                          fontSize: 14,
                          fontFamily: 'mono',
                        ),
                      ],
                    )
                  : name == 'table'
                  ? const LocatorPrintLayout(
                      elements: [
                        LocatorPrintElement(
                          id: 'summary_table',
                          kind: 'table',
                          x: 40,
                          y: 180,
                          width: 515,
                          height: 140,
                          fontSize: 11,
                          columnWidths: [1, 2],
                          cells: [
                            [
                              LocatorPrintTableCell(text: 'Employee'),
                              LocatorPrintTableCell(text: 'Destination'),
                            ],
                            [
                              LocatorPrintTableCell(
                                kind: 'field',
                                source: 'employee_name',
                              ),
                              LocatorPrintTableCell(
                                kind: 'field',
                                source: 'custom:destination',
                              ),
                            ],
                            [
                              LocatorPrintTableCell(text: 'Departure date'),
                              LocatorPrintTableCell(
                                kind: 'field',
                                source: 'custom:departure',
                              ),
                            ],
                          ],
                        ),
                      ],
                    )
                  : null,
              onPreview: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (settings) {
        await tester.tap(find.byTooltip('Page and element settings'));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(LocatorPrintLayoutEditor),
        matchesGoldenFile('goldens/locator_print_editor_$name.png'),
      );
    });
  }
}
