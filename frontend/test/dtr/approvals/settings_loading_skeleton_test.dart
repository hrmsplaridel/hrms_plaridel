import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hrms_plaridel/shared/widgets/settings_loading_skeleton.dart';

void main() {
  for (final width in [360.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets('settings skeleton fits width $width, dark $dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: const Scaffold(body: SettingsMasterDetailSkeleton()),
          ),
        );
        // Shimmer runs continuously while loading; do not pumpAndSettle here.
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(Shimmer), findsWidgets);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('reduced motion disables shimmer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SettingsDetailsSkeleton()),
        ),
      ),
    );
    expect(find.byType(Shimmer), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
