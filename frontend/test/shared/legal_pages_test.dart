import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/features/landing/presentation/sections/footer_section.dart';
import 'package:hrms_plaridel/shared/screens/legal_page.dart';
import 'package:hrms_plaridel/shared/widgets/portal_legal_footer.dart';
import 'package:hrms_plaridel/shared/widgets/settings_about_panel.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('login legal pages work and preserve the form at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.reset();
        tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pumpAndSettle();

      expect(
        find.text('© ${DateTime.now().year} Unity Pillar'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(
        find.byType(TextField).first,
        'keep@example.invalid',
      );
      await tester.ensureVisible(find.text('Privacy'));
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Information we process'), findsOneWidget);
      await tester.ensureVisible(find.text('Contact and privacy requests'));
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('keep@example.invalid'), findsOneWidget);

      await tester.ensureVisible(find.text('Terms'));
      await tester.tap(find.text('Terms'));
      await tester.pumpAndSettle();
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Accounts and responsible use'), findsOneWidget);
      await tester.ensureVisible(find.text('Contact and support'));
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('keep@example.invalid'), findsOneWidget);
    });
  }

  for (final width in [390.0, 1440.0]) {
    testWidgets('public landing footer opens both legal pages at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: FooterSection())),
        ),
      );
      await tester.ensureVisible(find.text('Data Privacy Notice'));
      await tester.tap(find.text('Data Privacy Notice'));
      await tester.pumpAndSettle();
      expect(find.text('Information we process'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Terms of Service'));
      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();
      expect(find.text('Accounts and responsible use'), findsOneWidget);
    });
  }

  testWidgets('settings About opens the same complete terms', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SettingsAboutPanel()),
        ),
      ),
    );
    await tester.tap(find.text('Terms & Conditions'));
    await tester.pumpAndSettle();
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Accounts and responsible use'), findsOneWidget);
  });

  testWidgets('sidebar links open above the dashboard content navigator', (
    tester,
  ) async {
    final root = GlobalKey<NavigatorState>();
    final content = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        home: Scaffold(
          body: Navigator(
            key: content,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) =>
                  const Column(children: [TextField(), PortalLegalFooter()]),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'unsaved dashboard draft');
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(root.currentState!.canPop(), isTrue);
    expect(content.currentState!.canPop(), isFalse);
    expect(find.text('Privacy Policy'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('unsaved dashboard draft'), findsOneWidget);
    await tester.tap(find.text('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(content.currentState!.canPop(), isFalse);
  });

  for (final route in [LegalPage.privacyRoute, LegalPage.termsRoute]) {
    testWidgets(
      '$route can be opened directly without an authenticated shell',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            routes: LegalPage.routes,
            initialRoute: route,
            home: const Scaffold(body: Text('Portal entry')),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(route == '/privacy' ? 'Privacy Policy' : 'Terms of Use'),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Portal entry'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'legal pages remain readable on a narrow dark screen with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 180, child: PortalLegalFooter()),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Contact and privacy requests'));
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Contact and support'));
      expect(tester.takeException(), isNull);
    },
  );
}
