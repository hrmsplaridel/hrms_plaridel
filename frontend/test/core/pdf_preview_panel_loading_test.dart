import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/core/widgets/pdf_preview_preparation.dart';

void main() {
  for (final width in [1440.0, 420.0]) {
    for (final outcome in ['Cancel', 'panel close', 'success']) {
      testWidgets(
        'preview stays above details and handles $outcome at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final root = GlobalKey<NavigatorState>();
          final content = GlobalKey<NavigatorState>();
          final pending = Completer<int>();
          final returned = Completer<int?>();
          Route<dynamic>? detailsRoute;
          var otherActions = 0;
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: root,
              home: Scaffold(
                body: Navigator(
                  key: content,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (pageContext) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => openResponsiveRightSidePanel<void>(
                            context: pageContext,
                            builder: (panelContext) {
                              detailsRoute = ModalRoute.of(panelContext);
                              return Scaffold(
                                appBar: AppBar(
                                  title: const Text('Request Details'),
                                ),
                                body: Column(
                                  children: [
                                    TextButton(
                                      onPressed: () async {
                                        // Leave's callback retains its page context
                                        // while the details panel is above it.
                                        returned.complete(
                                          await preparePdfPreview<int>(
                                            context: pageContext,
                                            prepare: (_) => pending.future,
                                          ),
                                        );
                                      },
                                      child: const Text('Preview Form'),
                                    ),
                                    TextButton(
                                      onPressed: () => otherActions++,
                                      child: const Text('Other action'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          child: const Text('Open details'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open details'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Preview Form'));
          await tester.pump();
          expect(find.text('Preparing preview…'), findsOneWidget);
          expect(find.text('Cancel').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Other action'), warnIfMissed: false);
          expect(otherActions, 0);

          if (outcome == 'panel close') {
            final navigator = width >= 1100 ? root : content;
            navigator.currentState!.removeRoute(detailsRoute!);
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pumpAndSettle();
            expect(find.text('Request Details'), findsNothing);
          } else {
            if (outcome == 'success') {
              pending.complete(1);
            } else {
              await tester.tap(find.text('Cancel'));
            }
            await tester.pumpAndSettle();
            expect(find.text('Request Details'), findsOneWidget);
            await tester.tap(find.text('Other action'));
            expect(otherActions, 1);
          }
          expect(returned.isCompleted, isTrue);
          expect(await returned.future, outcome == 'success' ? 1 : isNull);
          expect(find.text('Preparing preview…'), findsNothing);
          if (!pending.isCompleted) pending.complete(1);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
