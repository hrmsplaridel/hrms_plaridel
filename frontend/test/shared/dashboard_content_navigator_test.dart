import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';

void main() {
  testWidgets('settings retain edits when the parent supplies a fresh panel', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    Widget host(String label) => MaterialApp(
      home: Scaffold(
        body: DashboardContentNavigator(
          navigatorKey: navKey,
          homeBuilder: () => const Text('home'),
          settingsPanel: _EditableSettings(label: label),
          homeScrollPadding: EdgeInsets.zero,
          settingsScrollPadding: const EdgeInsets.all(10),
        ),
      ),
    );
    await tester.pumpWidget(host('initial'));
    DashboardContentNavigator.openSettings(navKey);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved security setting');
    await tester.pumpWidget(host('updated'));
    await tester.pumpAndSettle();
    expect(find.text('updated'), findsOneWidget);
    expect(find.text('unsaved security setting'), findsOneWidget);
  });

  testWidgets('settings apply padding changes without replacing the form', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    const panel = _EditableSettings(label: 'settings');
    Widget host(double bottom) => MaterialApp(
      home: Scaffold(
        body: DashboardContentNavigator(
          navigatorKey: navKey,
          homeBuilder: () => const Text('home'),
          settingsPanel: panel,
          homeScrollPadding: EdgeInsets.zero,
          settingsScrollPadding: EdgeInsets.only(bottom: bottom),
        ),
      ),
    );
    await tester.pumpWidget(host(10));
    DashboardContentNavigator.openSettings(navKey);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'keep this draft');
    await tester.pumpWidget(host(90));
    await tester.pumpAndSettle();
    final scroll = find.ancestor(
      of: find.byType(_EditableSettings),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.widget<SingleChildScrollView>(scroll).padding,
      const EdgeInsets.only(bottom: 90),
    );
    expect(find.text('keep this draft'), findsOneWidget);
  });

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

class _EditableSettings extends StatefulWidget {
  const _EditableSettings({required this.label});
  final String label;
  @override
  State<_EditableSettings> createState() => _EditableSettingsState();
}

class _EditableSettingsState extends State<_EditableSettings> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(widget.label),
      TextField(controller: controller),
    ],
  );
}
