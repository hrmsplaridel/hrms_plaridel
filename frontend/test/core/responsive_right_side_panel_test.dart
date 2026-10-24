import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';

const _contentKey = ValueKey('shared-panel-content');

void main() {
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    bool? barrierDismissible,
    ValueChanged<String?>? onResult,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget content(BuildContext context) => Scaffold(
      key: _contentKey,
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.pop(context, 'saved'),
          child: const Text('Close shared panel'),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final result = barrierDismissible == null
                    ? await openResponsiveRightSidePanel<String>(
                        context: context,
                        builder: content,
                      )
                    : await openResponsiveRightSidePanel<String>(
                        context: context,
                        builder: content,
                        barrierDismissible: barrierDismissible,
                      );
                onResult?.call(result);
              },
              child: const Text('Open shared panel'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open shared panel'));
    await tester.pumpAndSettle();
  }

  testWidgets('existing callers still dismiss on outside click by default', (
    tester,
  ) async {
    var closed = false;
    await mount(tester, onResult: (_) => closed = true);
    expect(find.byKey(_contentKey), findsOneWidget);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(_contentKey), findsNothing);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'outside dismissal can be disabled without losing close results',
    (tester) async {
      String? result;
      await mount(
        tester,
        barrierDismissible: false,
        onResult: (value) => result = value,
      );
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(_contentKey), findsOneWidget);
      await tester.tap(find.text('Close shared panel'));
      await tester.pumpAndSettle();
      expect(find.byKey(_contentKey), findsNothing);
      expect(result, 'saved');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow screens retain a full-screen route and return values', (
    tester,
  ) async {
    String? result;
    await mount(
      tester,
      size: const Size(390, 844),
      onResult: (value) => result = value,
    );
    expect(
      tester.getRect(find.byKey(_contentKey)),
      const Rect.fromLTWH(0, 0, 390, 844),
    );
    await tester.tap(find.text('Close shared panel'));
    await tester.pumpAndSettle();
    expect(result, 'saved');
    expect(find.byKey(_contentKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
