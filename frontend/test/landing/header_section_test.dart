import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/features/landing/presentation/sections/header_section.dart';

void main() {
  Future<void> pumpHeader(
    WidgetTester tester,
    Size size, {
    bool menuOpen = false,
    bool compact = false,
    VoidCallback? onHome,
    VoidCallback? onJobs,
    VoidCallback? onContact,
    ValueChanged<bool>? onMenu,
  }) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HeaderSection(
              menuOpen: menuOpen,
              compact: compact,
              onHomeTap: onHome,
              onJobVacanciesTap: onJobs,
              onContactTap: onContact,
              onMenuOpenChanged: onMenu,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('desktop header shows branding and public links', (tester) async {
    for (final width in [768.0, 820.0, 1024.0, 1280.0, 1366.0, 1440.0, 1920.0]) {
      await pumpHeader(tester, Size(width, 900));
      expect(find.text('Republic of the Philippines'), findsOneWidget);
      expect(find.text('PROVINCE OF MISAMIS OCCIDENTAL'), findsOneWidget);
      expect(find.text('MUNICIPALITY OF PLARIDEL'), findsOneWidget);
      expect(
        find.text('HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE'),
        findsOneWidget,
      );
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Job Vacancies'), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(find.text('Sign In'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('mobile header shows the seal bar and menu button', (tester) async {
    var opened = false;
    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0, 430.0, 600.0, 640.0]) {
      await pumpHeader(
        tester,
        Size(width, 800),
        onMenu: (_) => opened = true,
      );
      expect(find.text('MUNICIPALITY OF PLARIDEL'), findsOneWidget);
      expect(find.text('Republic of the Philippines'), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('desktop links and mobile menu panel use the current section', (
    tester,
  ) async {
    var home = 0;
    await pumpHeader(
      tester,
      const Size(1280, 800),
      onHome: () => home++,
    );
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(home, 1);
    expect(tester.takeException(), isNull);

    var jobs = 0;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 800));
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandingMobileNavPanel(
            activeSection: LandingNavSection.jobVacancies,
            onHome: () {},
            onJobVacancies: () => jobs++,
            onContact: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Job Vacancies'), findsOneWidget);
    await tester.tap(find.text('Job Vacancies'));
    await tester.pump();
    expect(jobs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolled mobile header uses the shorter branding', (tester) async {
    await pumpHeader(tester, const Size(390, 800), compact: true);
    expect(find.text('MUNICIPALITY OF PLARIDEL'), findsOneWidget);
    expect(find.text('HR MANAGEMENT AND DEVELOPMENT OFFICE'), findsOneWidget);
    expect(find.text('Republic of the Philippines'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
