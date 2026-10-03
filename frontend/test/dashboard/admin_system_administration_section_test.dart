import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/admin_dashboard_desktop.dart';

void main() {
  testWidgets(
    'hides System Administration when account creation is unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminSystemAdministrationSection(
              canCreateAccount: false,
              selected: false,
              onCreateAccount: () {},
            ),
          ),
        ),
      );
      expect(find.text('SYSTEM ADMINISTRATION'), findsNothing);
      expect(find.text('Create Account'), findsNothing);
    },
  );

  testWidgets('shows section and create action together when granted', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminSystemAdministrationSection(
            canCreateAccount: true,
            selected: false,
            onCreateAccount: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('SYSTEM ADMINISTRATION'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    await tester.tap(find.text('Create Account'));
    expect(taps, 1);
  });
}
