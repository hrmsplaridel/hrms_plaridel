import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/widgets/admin_welcome_status_card.dart';
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

  testWidgets('admin header shows live time and the weather refresh control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminWelcomeStatusCard(
            layout: WelcomeStatusLayout.adminHeader,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byTooltip('Toggle time format'), findsOneWidget);
    expect(find.byTooltip('Refresh weather'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d{2}:\d{2}')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await flushWeatherTimer(tester);
  });

  testWidgets('narrow admin header does not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminWelcomeStatusCard(
            layout: WelcomeStatusLayout.adminHeader,
            fillWidth: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byTooltip('Refresh weather'), findsOneWidget);

    await flushWeatherTimer(tester);
  });
}
