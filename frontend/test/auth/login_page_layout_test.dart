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

  testWidgets('desktop login shows branded split layout', (tester) async {
    await pumpAt(tester, const Size(1920, 1080));
    expect(find.textContaining('Empowering'), findsOneWidget);
    expect(find.text('Official HRMS Portal'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(find.text('Municipality of Plaridel'), findsWidgets);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Secure login'), findsOneWidget);
    expect(find.text('Admin portal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet login keeps the form usable', (tester) async {
    await pumpAt(tester, const Size(820, 1180));
    expect(find.text('Official HRMS Portal'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile login overlaps hero with crest and footer inside card', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('Official HRMS Portal'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(find.text('Municipality of\nPlaridel'), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Email or username'), findsOneWidget);
    expect(find.text('Have a productive day!'), findsNothing);
    expect(find.text('Or quick access'), findsNothing);
    expect(find.bySemanticsLabel('HRMS system logo'), findsOneWidget);
    final card = find.byKey(const ValueKey('mobile-login-card'));
    final heroRect = tester.getRect(
      find.byKey(const ValueKey('mobile-login-hero')),
    );
    final cardRect = tester.getRect(card);
    final crestRect = tester.getRect(
      find.byKey(const ValueKey('mobile-login-crest')),
    );
    expect(heroRect.bottom - cardRect.top, closeTo(40, 1));
    expect(crestRect.top, lessThan(cardRect.top));
    expect(crestRect.bottom, greaterThan(cardRect.top));
    expect(
      find.descendant(of: card, matching: find.text('Privacy')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Terms')),
      findsOneWidget,
    );
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
    'mobile remember, reset and legal controls retain their actions',
    (tester) async {
      await pumpAt(tester, const Size(375, 812));
      await tester.ensureVisible(find.text('Remember me'));
      await tester.tap(find.text('Remember me'));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

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
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('Privacy'));
      await tester.tap(find.text('Privacy'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
