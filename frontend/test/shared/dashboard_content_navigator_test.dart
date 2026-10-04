import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';

void main() {
  testWidgets('menu changes still render after a wide/narrow layout switch', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();

    Widget host({required bool wide, required String menu}) {
      final content = DashboardContentNavigator(
        navigatorKey: navKey,
        homeCacheKey: menu,
        homeRefreshKey: menu,
        homeBuilder: () => Text('home:$menu'),
        settingsPanel: const Text('settings'),
        homeScrollPadding: EdgeInsets.zero,
        settingsScrollPadding: EdgeInsets.zero,
      );
      return MaterialApp(
        home: Scaffold(
          body: wide
              ? Row(children: [Expanded(child: content)])
              : Column(children: [Expanded(child: content)]),
        ),
      );
    }

    await tester.pumpWidget(host(wide: true, menu: 'dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('home:dashboard'), findsOneWidget);

    await tester.pumpWidget(host(wide: false, menu: 'dashboard'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(wide: false, menu: 'docutracker'));
    await tester.pumpAndSettle();

    expect(find.text('home:docutracker'), findsOneWidget);
    expect(find.text('home:dashboard'), findsNothing);

    await tester.pumpWidget(host(wide: true, menu: 'rsp'));
    await tester.pumpAndSettle();
    expect(find.text('home:rsp'), findsOneWidget);
  });
}
