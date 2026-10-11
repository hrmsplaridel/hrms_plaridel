import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/pages/applicant_required_form_page.dart';

class _FakeAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'ok': true,
      'assignment': {'formType': 'ojt', 'status': 'assigned'},
      'entry': {
        'id': 'x',
        'ojt_immersion': 'Juan',
        'school': 'BSIT',
        'created_at': '2026-10-12T00:00:00.000Z',
        'updated_at': '2026-10-12T00:00:00.000Z',
      },
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real applicant OJT page accepts typing', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    ApiClient.instance.init();
    ApiClient.instance.dio.httpClientAdapter = _FakeAdapter();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ApplicantRequiredFormPage(applicationId: 'app-1'),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Submit to HR').evaluate().isNotEmpty) break;
    }
    expect(find.text('Submit to HR'), findsOneWidget);

    for (final label in ['OJT / Immersion', 'School']) {
      final f = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      expect(f, findsOneWidget);
      await tester.tap(f);
      await tester.pump();
      final et = tester.widget<EditableText>(
        find.descendant(of: f, matching: find.byType(EditableText)),
      );
      expect(et.readOnly, isFalse);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      var text = '';
      for (final ch in 'Abc'.split('')) {
        text += ch;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pump();
      }
      expect(tester.widget<TextField>(f).controller?.text, 'Abc');
      expect(et.focusNode.hasFocus, isTrue);
    }
  });
}
