import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_welcome_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> flushWeatherTimer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 9));
  }

  Future<void> pumpBanner(
    WidgetTester tester, {
    required Size size,
    required String portalLabel,
    required String displayName,
    required String description,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: size.width,
              child: DashboardWelcomeBanner(
                portalLabel: portalLabel,
                displayName: displayName,
                description: description,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('admin and employee banners keep their own portal copy', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      size: const Size(1440, 400),
      portalLabel: 'Admin Portal',
      displayName: 'Ana Reyes',
      description: "Here's the latest overview of HR activities for Plaridel.",
    );

    expect(find.text('Admin Portal'), findsOneWidget);
    expect(find.text('Employee Portal'), findsNothing);
    expect(find.textContaining('Ana'), findsOneWidget);
    expect(
      find.text("Here's the latest overview of HR activities for Plaridel."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byTooltip('Refresh weather'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await flushWeatherTimer(tester);

    await pumpBanner(
      tester,
      size: const Size(1440, 400),
      portalLabel: 'Employee Portal',
      displayName: 'Juan Dela Cruz',
      description: 'Welcome to your HRMS dashboard.',
    );
    expect(find.text('Employee Portal'), findsOneWidget);
    expect(find.text('Admin Portal'), findsNothing);
    expect(find.text('Welcome to your HRMS dashboard.'), findsOneWidget);
    expect(find.textContaining('Juan'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await flushWeatherTimer(tester);

    await pumpBanner(
      tester,
      size: const Size(1440, 400),
      portalLabel: 'Mayor Portal',
      displayName: 'Mayor',
      description: "Here's an overview of today's endorsement activity.",
    );
    expect(find.text('Mayor Portal'), findsOneWidget);
    expect(find.text('Admin Portal'), findsNothing);
    expect(
      find.text("Here's an overview of today's endorsement activity."),
      findsOneWidget,
    );
    expect(find.textContaining('Mayor'), findsWidgets);
    expect(tester.takeException(), isNull);
    await flushWeatherTimer(tester);
  });

  testWidgets('welcome banner does not overflow from phone to desktop', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(320, 700),
      Size(375, 800),
      Size(768, 900),
      Size(1024, 800),
      Size(1440, 900),
    ];
    for (final size in sizes) {
      await pumpBanner(
        tester,
        size: size,
        portalLabel: 'Employee Portal',
        displayName: 'Maria Magdalena Santos',
        description: 'Welcome to your HRMS dashboard.',
      );
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('Employee Portal'), findsOneWidget, reason: '$size');
      await flushWeatherTimer(tester);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
