import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
  }) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const LoginPage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  for (final scenario in [
    (size: const Size(390, 844), scale: 1.0),
    (size: const Size(320, 568), scale: 1.6),
    (size: const Size(360, 640), scale: 2.0),
  ]) {
    testWidgets('mobile reset actions are stacked and reachable with the keyboard at ${scenario.size}, text=${scenario.scale}', (tester) async {
      await pumpAt(tester, scenario.size, textScale: scenario.scale);
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final email = find.descendant(of: dialog, matching: find.byType(TextField));
      final sms = find.widgetWithText(FilledButton, 'Send SMS code');
      await tester.ensureVisible(find.text('Enter a reset code'));
      await tester.tap(find.text('Enter a reset code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your registered email first.'), findsOneWidget);
      expect(tester.getSize(sms).width, closeTo(tester.getSize(email).width, 1));
      final actions = [sms, find.text('Enter a reset code'),
        find.text('Request administrator assistance'), find.text('Cancel')];
      for (var index = 1; index < actions.length; index++) {
        expect(tester.getTopLeft(actions[index]).dy,
          greaterThan(tester.getBottomLeft(actions[index - 1]).dy));
      }
      await tester.ensureVisible(email);
      await tester.enterText(email, 'employee@plaridel.gov.ph');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      for (final action in actions) {
        await tester.ensureVisible(action);
        expect(action.hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Enter a reset code'));
      await tester.tap(find.text('Enter a reset code'));
      await tester.pumpAndSettle();
      final resetFields = find.descendant(of: dialog, matching: find.byType(TextField));
      expect(resetFields, findsNWidgets(3));
      for (final field in resetFields.evaluate().map((e) => find.byWidget(e.widget))) {
        await tester.ensureVisible(field);
        expect(field.hitTestable(), findsOneWidget);
      }
      final reset = find.widgetWithText(FilledButton, 'Reset password');
      await tester.ensureVisible(reset);
      expect(reset.hitTestable(), findsOneWidget);
      expect(tester.getSize(reset).width, closeTo(tester.getSize(resetFields.first).width, 1));
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    });
  }

  testWidgets('desktop login shows branded split layout', (tester) async {
    await pumpAt(tester, const Size(1920, 1080));
    expect(find.textContaining('Empowering'), findsOneWidget);
    expect(find.text('Official HRMS Portal'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(find.text('Municipality of Plaridel'), findsWidgets);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Or quick access'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet login keeps the form usable', (tester) async {
    await pumpAt(tester, const Size(820, 1180));
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(find.text('Or quick access'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile login uses the portal card layout', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in to continue to your HRMS portal.'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(find.text('Plaridel'), findsOneWidget);
    expect(find.text('Email or username'), findsOneWidget);
    expect(find.text('Secure access for municipal employees'), findsOneWidget);
    expect(find.text('Have a productive day!'), findsNothing);
    expect(find.text('Or quick access'), findsNothing);
    expect(find.text('Official HRMS Portal'), findsNothing);
    expect(find.byKey(const ValueKey('mobile-minimal-login')), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty credentials show inline error', (tester) async {
    await pumpAt(tester, const Size(1280, 800));
    await tester.ensureVisible(find.text('Sign In to HRMS'));
    await tester.tap(find.text('Sign In to HRMS'));
    await tester.pump();
    expect(find.text('Please enter email and password'), findsOneWidget);
  });

  testWidgets('password visibility toggle stays accessible', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('login layouts do not overflow at common sizes', (tester) async {
    const sizes = <Size>[
      Size(1920, 1080),
      Size(3840, 2160),
      Size(2560, 1080),
      Size(1366, 768),
      Size(1280, 600),
      Size(1093, 614),
      Size(1024, 768),
      Size(1000, 500),
      Size(999, 600),
      Size(768, 1024),
      Size(320, 568),
      Size(280, 480),
      Size(360, 740),
      Size(360, 640),
      Size(375, 812),
      Size(375, 667),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
      Size(480, 800),
      Size(800, 390),
      Size(600, 240),
    ];
    for (final size in sizes) {
      await pumpAt(tester, size);
      expect(find.text('Sign In to HRMS'), findsOneWidget, reason: '$size');
      await tester.ensureVisible(find.text('Sign In to HRMS'));
      expect(
        find.text('Sign In to HRMS').hitTestable(),
        findsOneWidget,
        reason: '$size',
      );
      await tester.ensureVisible(find.text('Terms'));
      expect(find.text('Terms').hitTestable(), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('desktop branding is not covered by the curved form panel', (
    tester,
  ) async {
    for (final size in [const Size(1366, 768), const Size(1920, 1080)]) {
      await pumpAt(tester, size);
      for (final label in [
        'Secure',
        'For Our People',
        'Modern HR Services',
        'Better Service',
      ]) {
        await tester.ensureVisible(find.text(label));
        expect(
          find.text(label).hitTestable(),
          findsOneWidget,
          reason: '$label at $size',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large text keeps controls reachable on desktop and mobile', (
    tester,
  ) async {
    for (final size in [
      const Size(1024, 600),
      const Size(1366, 768),
      const Size(320, 568),
    ]) {
      await pumpAt(tester, size, textScale: 2);
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign In to HRMS'));
      await tester.tap(find.text('Sign In to HRMS'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Please enter email and password'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('short mobile viewport remains usable with keyboard open', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 600));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'test password');
    await tester.ensureVisible(find.text('Sign In to HRMS'));
    expect(find.text('Sign In to HRMS').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile reset and legal controls retain their actions',
    (tester) async {
      await pumpAt(tester, const Size(375, 812));
      expect(find.text('Remember me'), findsOneWidget);

      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(
        find.byType(TextField).first,
        'employee@plaridel.gov.ph',
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'employee@plaridel.gov.ph',
      );
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reset password'), findsOneWidget);
      final resetEmail = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(resetEmail).controller!.text,
        'employee@plaridel.gov.ph',
      );
      await tester.tap(find.text('Request administrator assistance'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Password reset assistance'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Enter a reset code'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reset code'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('Privacy'));
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Information we process'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
