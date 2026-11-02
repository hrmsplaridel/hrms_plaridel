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

  testWidgets('open document and home state survive 1200 to 390 and back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final navKey = GlobalKey<NavigatorState>();
    final hostKey = GlobalKey();
    const stableDocuTrackerRefreshKey = 'employee-docutracker';

    Widget host() {
      final width = tester.view.physicalSize.width;
      final content = DashboardContentNavigator(
        key: hostKey,
        navigatorKey: navKey,
        homeCacheKey: 6,
        homeRefreshKey: stableDocuTrackerRefreshKey,
        homeBuilder: () =>
            const TextField(key: ValueKey('docutracker-unsaved-field')),
        settingsPanel: const Text('settings'),
        homeScrollPadding: EdgeInsets.zero,
        settingsScrollPadding: EdgeInsets.zero,
      );
      return MaterialApp(
        home: Scaffold(
          body: width > 900
              ? Row(children: [Expanded(child: content)])
              : Column(children: [Expanded(child: content)]),
        ),
      );
    }

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(host());
    await tester.enterText(
      find.byKey(const ValueKey('docutracker-unsaved-field')),
      'unsaved remarks',
    );
    final documentRoute = navKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/docutracker/document/DOC-1'),
        builder: (_) => const Scaffold(body: Text('Document DOC-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Document DOC-1'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Document DOC-1'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Document DOC-1'), findsOneWidget);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await documentRoute;
    expect(find.text('Document DOC-1'), findsNothing);
    expect(find.text('unsaved remarks'), findsOneWidget);
  });
}
