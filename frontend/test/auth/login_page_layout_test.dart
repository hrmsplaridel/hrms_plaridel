import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
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

  testWidgets('mobile login stacks hero and form', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('Official HRMS Portal'), findsOneWidget);
    expect(find.text('Sign In to HRMS'), findsOneWidget);
    expect(find.text('Municipality of Plaridel'), findsWidgets);
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
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('login layouts do not overflow at common sizes', (tester) async {
    const sizes = <Size>[
      Size(1920, 1080),
      Size(1366, 768),
      Size(1024, 768),
      Size(768, 1024),
      Size(360, 740),
      Size(390, 844),
      Size(430, 932),
      Size(800, 390),
    ];
    for (final size in sizes) {
      await pumpAt(tester, size);
      expect(find.text('Sign In to HRMS'), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
