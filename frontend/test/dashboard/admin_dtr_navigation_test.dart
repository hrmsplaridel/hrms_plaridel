import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/admin_dashboard_desktop.dart';

void main() {
  for (final permission in [null, 'reports_allowed', 'manage_allowed',
    'employees_allowed', 'leave_allowed', 'approvals_allowed', 'locator_allowed']) {
    testWidgets('DTR navigation requires at least one feature: $permission', (tester) async {
      AdminMenu? selected;
      final allowed = hasAdminDtrAccess(
        canViewReports: permission == 'reports_allowed',
        canManage: permission == 'manage_allowed',
        featureAccess: {if (permission != null) permission: true});
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children:[
        AdminPersonalPortalSection(selectedMenu: AdminMenu.dashboard, onTap:(v)=>selected=v),
        AdminDtrNavigationTile(canAccessDtr:allowed,selectedMenu:AdminMenu.dashboard,onTap:(v)=>selected=v),
      ]))));
      expect(find.text('My Attendance'), findsOneWidget);
      expect(find.text('My Leave'), findsOneWidget);
      expect(find.text('My Locator'), findsOneWidget);
      if(permission == null) {
        expect(find.text('DTR'), findsNothing);
      } else {
        expect(find.text('DTR'), findsOneWidget);
        await tester.tap(find.text('DTR'));
        expect(selected,AdminMenu.dtr);
      }
    });
  }
  testWidgets('revoking access removes DTR from navigation', (tester) async {
    var allowed = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:StatefulBuilder(
      builder:(_,setState) {
        update=setState;
        return AdminDtrNavigationTile(canAccessDtr:allowed,selectedMenu:AdminMenu.dtr,onTap:(_){});
      },
    ))));
    expect(find.text('DTR'),findsOneWidget);
    update(()=>allowed=false);
    await tester.pump();
    expect(find.text('DTR'),findsNothing);
  });
}
