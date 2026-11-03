import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/widgets/pdf_preview_preparation.dart';

class _Harness {
  final jobs = <Completer<int>>[Completer<int>(), Completer<int>()];
  int starts = 0;
  int opened = 0;
  int otherActions = 0;
  int navigation = 0;
  Object? error;
  late Future<void> Function() preview;
  final visible = ValueNotifier(true);
}

Future<void> _mount(WidgetTester tester, _Harness state) async {
  addTearDown(state.visible.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 140,
              child: TextButton(
                onPressed: () => state.navigation++,
                child: const Text('Navigation'),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: state.visible,
                builder: (_, visible, _) => !visible
                    ? const SizedBox.expand()
                    : Builder(
                        builder: (context) {
                          state.preview = () async {
                            try {
                              final result = await preparePdfPreview<int>(
                                context: context,
                                prepare: (_) =>
                                    state.jobs[state.starts++].future,
                              );
                              if (result != null) state.opened++;
                            } catch (error) {
                              state.error = error;
                            }
                          };
                          return SizedBox.expand(
                            child: Column(
                              children: [
                                TextButton(
                                  onPressed: state.preview,
                                  child: const Text('Preview'),
                                ),
                                TextButton(
                                  onPressed: () => state.otherActions++,
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'preparation blocks work-area actions and duplicate jobs but keeps navigation usable',
    (tester) async {
      final state = _Harness();
      await _mount(tester, state);
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(find.text('Preparing preview…'), findsOneWidget);
      unawaited(state.preview());
      await tester.pump();
      expect(state.starts, 1);
      await tester.tap(find.text('Approve'), warnIfMissed: false);
      expect(state.otherActions, 0);
      await tester.tap(find.text('Navigation'));
      expect(state.navigation, 1);
      state.jobs[0].complete(1);
      await tester.pumpAndSettle();
      expect(state.opened, 1);
      expect(find.text('Preparing preview…'), findsNothing);
      await tester.tap(find.text('Approve'));
      expect(state.otherActions, 1);
    },
  );

  for (final lateError in [false, true]) {
    testWidgets(
      'Cancel returns immediately and discards late ${lateError ? 'errors' : 'results'}',
      (tester) async {
        final state = _Harness();
        await _mount(tester, state);
        var returned = false;
        unawaited(state.preview().then((_) => returned = true));
        await tester.pump();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(returned, isTrue);
        expect(find.text('Preparing preview…'), findsNothing);
        if (lateError) {
          state.jobs[0].completeError(StateError('Late failure'));
        } else {
          state.jobs[0].complete(1);
        }
        await tester.pumpAndSettle();
        expect(state.opened, 0);
        expect(state.error, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an active failure restores actions and reaches the caller', (
    tester,
  ) async {
    final state = _Harness();
    await _mount(tester, state);
    unawaited(state.preview());
    await tester.pump();
    state.jobs[0].completeError(StateError('Could not load'));
    await tester.pumpAndSettle();
    expect(find.text('Preparing preview…'), findsNothing);
    expect(state.error, isA<StateError>());
    await tester.tap(find.text('Approve'));
    expect(state.otherActions, 1);
  });

  testWidgets(
    'a cancelled job cannot dismiss or overwrite a newer preparation',
    (tester) async {
      final state = _Harness();
      await _mount(tester, state);
      await tester.tap(find.text('Preview'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview'));
      await tester.pump();
      state.jobs[0].completeError(StateError('Old failure'));
      await tester.pump();
      expect(find.text('Preparing preview…'), findsOneWidget);
      state.jobs[1].complete(2);
      await tester.pumpAndSettle();
      expect(state.opened, 1);
      expect(state.error, isNull);
    },
  );

  testWidgets(
    'leaving the owning view cancels preparation without opening a preview',
    (tester) async {
      final state = _Harness();
      await _mount(tester, state);
      await tester.tap(find.text('Preview'));
      await tester.pump();
      state.visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Preparing preview…'), findsNothing);
      state.jobs[0].complete(1);
      await tester.pumpAndSettle();
      expect(state.opened, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final back in [false, true]) {
    testWidgets(
      '${back ? 'Back' : 'Escape'} cancels preparation and keeps the current page',
      (tester) async {
        final state = _Harness();
        await _mount(tester, state);
        await tester.tap(find.text('Preview'));
        await tester.pump();
        if (back) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(find.text('Preparing preview…'), findsNothing);
        expect(find.text('Approve'), findsOneWidget);
        state.jobs[0].complete(1);
        await tester.pumpAndSettle();
        expect(state.opened, 0);
      },
    );
  }
}
