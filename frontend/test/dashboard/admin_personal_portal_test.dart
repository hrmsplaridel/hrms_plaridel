import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/admin_dashboard_desktop.dart';

void main() {
  testWidgets(
    'admin personal portal offers locator filing alongside attendance and leave',
    (tester) async {
      AdminMenu? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminPersonalPortalSection(
              selectedMenu: AdminMenu.myLocator,
              onTap: (menu) => selected = menu,
            ),
          ),
        ),
      );
      expect(find.text('My Attendance'), findsOneWidget);
      expect(find.text('My Leave'), findsOneWidget);
      expect(find.text('My Locator'), findsOneWidget);
      await tester.tap(find.text('My Locator'));
      expect(selected, AdminMenu.myLocator);
    },
  );
}
