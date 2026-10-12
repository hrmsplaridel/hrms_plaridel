import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'preview loading feedback clears on ${fail ? 'failure' : 'success'}',
      (tester) async {
        final pending = Completer<Uint8List>();
        Object? error;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    try {
                      await LocatorSlipPrint.loadPreview(
                        context,
                        () => pending.future,
                      );
                    } catch (e) {
                      error = e;
                    }
                  },
                  child: const Text('Preview'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Preview'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Loading preview…'), findsOneWidget);
        if (fail) {
          pending.completeError(StateError('Failed to load'));
        } else {
          pending.complete(Uint8List(1));
        }
        await tester.pumpAndSettle();
        expect(find.text('Loading preview…'), findsNothing);
        expect(error, fail ? isA<StateError>() : isNull);
      },
    );
  }
  testWidgets('approved locator offers preview separately from print', (
    tester,
  ) async {
    var previews = 0;
    var prints = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmployeeLocatorMobileDetailActions(
            canCancel: false,
            canPrint: true,
            canOpenAttachment: false,
            onHistory: () {},
            onCancel: () {},
            onPreview: () => previews++,
            onPrint: () => prints++,
            onOpenAttachment: () {},
          ),
        ),
      ),
    );

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    expect(previews, 1);
    expect(prints, 0);
  });
}
