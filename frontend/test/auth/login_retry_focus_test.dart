import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

class _RejectedLogin extends AuthProvider {
  @override
  Future<String?> login(String email, String password) async => 'Invalid email or password';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('login fields accept typing after successful reset dialog closes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const size = Size(1920, 1080);
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.reset(); tester.binding.setSurfaceSize(null); });
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField).first, 'test@example.invalid');
    await tester.enterText(find.byType(TextField).last, 'old-password');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    // Simulate the exact successful result returned by the reset endpoint handler.
    Navigator.of(tester.element(find.byType(AlertDialog))).pop(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, isEmpty);
    for (final field in [find.byType(TextField).first, find.byType(TextField).last]) {
      await tester.tap(field);
      await tester.pump();
      final node = tester.widget<TextField>(field).focusNode!;
      expect(node.hasFocus, isTrue);
      tester.testTextInput.enterText('new-credentials');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'new-credentials');
      expect(node.hasFocus, isTrue);
      expect(tester.testTextInput.isRegistered, isTrue);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [const Size(1920, 1080), const Size(390, 844)]) {
    testWidgets('typing after rejected login retains the active field at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() { tester.view.reset(); tester.binding.setSurfaceSize(null); });
      final auth = _RejectedLogin();
      addTearDown(auth.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(value: auth,
        child: const MaterialApp(home: LoginPage())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final email = find.byType(TextField).first;
      final password = find.byType(TextField).last;
      await tester.ensureVisible(email);
      await tester.enterText(email, 'test@example.invalid');
      await tester.ensureVisible(password);
      await tester.enterText(password, 'incorrect');
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Invalid email or password'), findsOneWidget);
        for (final field in [email, password]) {
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.pump();
          final node = tester.widget<TextField>(field).focusNode!;
          expect(node.hasFocus, true, reason: 'Field should accept focus after rejection');
          tester.testTextInput.enterText('retry$attempt');
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, 'retry$attempt');
          expect(node.hasFocus, true, reason: 'Clearing the error must preserve field focus');
          expect(tester.testTextInput.isRegistered, true);
          tester.testTextInput.enterText('retry${attempt}x');
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, 'retry${attempt}x');
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
