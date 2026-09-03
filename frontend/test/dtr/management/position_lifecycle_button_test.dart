import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/widgets/position_lifecycle_button.dart';

Widget subject({
  required bool isActive,
  required VoidCallback onDeactivate,
  required VoidCallback onReactivate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PositionLifecycleButton(
        isActive: isActive,
        onDeactivate: onDeactivate,
        onReactivate: onReactivate,
      ),
    ),
  );
}

void main() {
  testWidgets('inactive position exposes Reactivate action', (tester) async {
    var reactivated = false;
    await tester.pumpWidget(
      subject(
        isActive: false,
        onDeactivate: () {},
        onReactivate: () => reactivated = true,
      ),
    );

    expect(find.text('Reactivate'), findsOneWidget);
    expect(find.text('Deactivate'), findsNothing);
    await tester.tap(find.text('Reactivate'));
    expect(reactivated, isTrue);
  });

  testWidgets('active position exposes Deactivate action', (tester) async {
    var deactivated = false;
    await tester.pumpWidget(
      subject(
        isActive: true,
        onDeactivate: () => deactivated = true,
        onReactivate: () {},
      ),
    );

    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Reactivate'), findsNothing);
    await tester.tap(find.text('Deactivate'));
    expect(deactivated, isTrue);
  });
}
