import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('workforce skeletons fit $width, dark $dark', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    WorkforceRowsSkeleton(columns: [1, 3]),
                    WorkforceRowsSkeleton(
                      columns: [1, 1, 1, 1, 1, 1, 1],
                      rows: 2,
                    ),
                    WeeklyScheduleSkeleton(),
                    WorkforceRowsSkeleton(
                      columns: [2, 1, 1, 1, 1, 1, 1, 2],
                      rows: 8,
                      label: 'Loading attendance report',
                    ),
                    SizedBox(
                      width: 168,
                      child: WorkforceRowsSkeleton(
                        columns: [1, 1],
                        rows: 4,
                        cellHeight: 40,
                        label: 'Loading report summary',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        // Loading shimmer never settles; use a bounded pump.
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(Shimmer), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('workforce skeleton respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: WorkforceRowsSkeleton()),
        ),
      ),
    );
    expect(find.byType(Shimmer), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
