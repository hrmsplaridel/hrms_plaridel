import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/shared/widgets/signature_confirmation_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/signature_integrity_notice.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  testWidgets(
    'signing confirmation requires acknowledgement and the current password',
    (tester) async {
      Map? sent;
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/api/signature-security/authorize');
            sent = options.data as Map;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'authorization': 'proof'},
              ),
            );
          },
        ),
      );
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      SignatureConfirmation.install();
      String? proof;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: SignatureConfirmation.navigatorKey,
          home: Scaffold(
            body: TextButton(
              onPressed: () async {
                proof = await ApiClient.instance.signingConfirmation!(
                  'challenge',
                );
              },
              child: const Text('Sign'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sign'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.enterText(find.byType(TextField), 'current-password');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(sent, {'challenge': 'challenge', 'password': 'current-password'});
      expect(proof, 'proof');
      expect(find.text('Confirm signing'), findsNothing);
    },
  );
  testWidgets(
    'legacy signatures are labelled as a baseline rather than a new verified signature',
    (tester) async {
      final signature = DocuTrackerSourceSignature.fromJson({
        'slot_key': 'applicant',
        'integrity_status': 'legacy_baseline',
      });
      expect(signature.integrityStatus, 'legacy_baseline');
      await tester.pumpWidget(
        MaterialApp(
          home: SignatureIntegrityNotice(status: signature.integrityStatus),
        ),
      );
      expect(find.textContaining('Historical signature'), findsOneWidget);
      expect(
        find.text('Signature matches this document revision.'),
        findsNothing,
      );
    },
  );
}
