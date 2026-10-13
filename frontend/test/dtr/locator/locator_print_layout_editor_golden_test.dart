import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
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
