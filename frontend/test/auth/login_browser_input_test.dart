@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:convert';
import 'dart:ui_web' as ui_web;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

// Exercise the actual browser input strategy, not TestTextInput's mock channel.
class _BrowserInputBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => false;
}

class _RejectedLogin extends AuthProvider {
  @override
  Future<String?> login(String email, String password) async =>
      'Invalid email or password';
}

// Browser widget tests do not serve the application's image bundle.
class _TestAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin.json') {
      final manifest = const StandardMessageCodec().encodeMessage(
        <String, Object?>{},
      )!;
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(jsonEncode(base64Encode(manifest.buffer.asUint8List()))),
        ),
      );
    }
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    }
    if (key.endsWith('.json')) {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(key == 'FontManifest.json' ? '[]' : '{}'),
        ),
      );
    }
    return ByteData.sublistView(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4AWMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
  }
}

web.HTMLInputElement _activeInput() {
  web.Element? active = web.document.activeElement;
  while (active?.shadowRoot?.activeElement != null) {
    active = active!.shadowRoot!.activeElement;
  }
  expectSync(
    active?.isA<web.HTMLInputElement>(),
    isTrue,
    reason: 'A visible Flutter field must own a live browser input',
  );
  return active as web.HTMLInputElement;
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump();
  // Platform messages use the browser event loop rather than the fake test clock.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  final input = _activeInput();
  input.value = text;
  // Native email inputs do not expose the browser selection-range API.
  if (input.type != 'email' && input.type != 'number') {
    input.setSelectionRange(text.length, text.length);
  }
  input.dispatchEvent(web.Event('input', web.EventInit(bubbles: true)));
  await tester.pump();
  expect(tester.widget<TextField>(field).controller!.text, text);
  expect(tester.takeException(), isNull);
}

void main() {
  ui_web.TestEnvironment.setUp(
    const ui_web.TestEnvironment(
      forceTestFonts: true,
      disableFontFallbacks: true,
      keepSemanticsDisabledOnUpdate: true,
      defaultToTestUrlStrategy: true,
    ),
  );
  _BrowserInputBinding();

  testWidgets('browser typing survives rejected login and password reset', (
    tester,
  ) async {
    web.window.focus();
    final originalErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      web.console.error(details.toString().toJS);
      originalErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalErrorHandler);
    SharedPreferences.setMockInitialValues({});
    const size = Size(1920, 1080);
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.reset();
      tester.binding.setSurfaceSize(null);
    });
    ApiClient.instance.init();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        expectSync(options.path, '/auth/reset-password');
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'ok': true},
          ),
        );
      },
    );
    ApiClient.instance.dio.interceptors.insert(0, interceptor);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(interceptor));
    final auth = _RejectedLogin();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: DefaultAssetBundle(
          bundle: _TestAssets(),
          child: const MaterialApp(home: LoginPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var attempt = 0; attempt < 2; attempt++) {
      await _type(tester, find.byType(TextField).first, 'test@example.invalid');
      await _type(tester, find.byType(TextField).last, 'incorrect');
      await tester.tap(find.text('Sign In to HRMS'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid email or password'), findsOneWidget);
    }

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter a reset code'));
    await tester.pumpAndSettle();
    Finder dialogField(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await _type(tester, dialogField('Reset code'), '123456');
    await _type(tester, dialogField('New password'), 'replacement-password');
    await _type(
      tester,
      dialogField('Confirm password'),
      'replacement-password',
    );
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.idle();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
    await _type(tester, find.byType(TextField).last, 'replacement-password');
    await _type(
      tester,
      find.byType(TextField).first,
      'another@example.invalid',
    );
    await _type(
      tester,
      find.byType(TextField).last,
      'replacement-password-again',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.idle();
    await tester.pumpWidget(const SizedBox.shrink());
    // Drain the engine's zero-delay replies to clearClient/autofill disposal.
    await tester.idle();
  });
}
