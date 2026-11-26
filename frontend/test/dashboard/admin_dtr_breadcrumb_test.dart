import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/admin_dtr_breadcrumb.dart';

void main() {
  testWidgets('breadcrumb links back to earlier levels only', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDtrBreadcrumb(
            trail: [
              AdminDtrCrumb('DTR', () => tapped.add('DTR')),
              AdminDtrCrumb('Workforce Setup', () => tapped.add('WS')),
              const AdminDtrCrumb('Shifts'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('DTR'), findsOneWidget);
    expect(find.text('Workforce Setup'), findsOneWidget);
    expect(find.text('Shifts'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));

    await tester.tap(find.text('DTR'));
    await tester.tap(find.text('Workforce Setup'));
    await tester.tap(find.text('Shifts'));
    expect(tapped, ['DTR', 'WS']);
  });
}
