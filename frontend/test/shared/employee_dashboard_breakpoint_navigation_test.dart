import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';

/// Mirrors the employee dashboard: one page host (GlobalKey) owns
/// [DashboardContentNavigator], and chrome may swap — including the old
/// PlatformLayoutBuilder mobile/web wrapper swap at 600px — without dropping
/// open document routes or unsaved home form state.
void main() {
  testWidgets(
    'open DocuTracker document survives desktop↔mobile chrome swap both ways',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final navigatorKey = GlobalKey<NavigatorState>();
      final hostKey = GlobalKey();
      var selectedIndex = 6;
      var otherModuleBuilds = 0;

      Widget buildContent() {
        return DashboardContentNavigator(
          key: hostKey,
          navigatorKey: navigatorKey,
          homeCacheKey: selectedIndex,
          homeRefreshKey: selectedIndex == 6
              ? 'employee-docutracker'
              : Object.hash('other', selectedIndex),
          homeBuilder: () {
            if (selectedIndex == 0) {
              otherModuleBuilds += 1;
              return const Text('home:dashboard');
            }
            return const TextField(
              key: ValueKey('docutracker-unsaved-field'),
              decoration: InputDecoration(labelText: 'Remarks'),
            );
          },
          settingsPanel: const Text('settings'),
          homeScrollPadding: EdgeInsets.zero,
          settingsScrollPadding: EdgeInsets.zero,
        );
      }

      Widget host() {
        final width = tester.view.physicalSize.width;
        final content = buildContent();
        return MaterialApp(
          home: Scaffold(
            body: width > 900
                ? Row(
                    children: [
                      const SizedBox(width: 72, child: Text('sidebar')),
                      Expanded(child: content),
                    ],
                  )
                : Column(
                    children: [
                      const SizedBox(height: 48, child: Text('mobile-chrome')),
                      Expanded(child: content),
                    ],
                  ),
          ),
        );
      }

      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpWidget(host());
      await tester.enterText(
        find.byKey(const ValueKey('docutracker-unsaved-field')),
        'draft note',
      );

      final pushed = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/docutracker/document/DOC-1'),
          builder: (_) => Scaffold(
            appBar: AppBar(
              leading: BackButton(
                onPressed: () => navigatorKey.currentState!.pop(),
              ),
            ),
            body: const Text('Document DOC-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Document DOC-1'), findsOneWidget);

      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Document DOC-1'), findsOneWidget);
      expect(find.text('home:dashboard'), findsNothing);

      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Document DOC-1'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await pushed;
      expect(find.text('Document DOC-1'), findsNothing);
      expect(find.text('draft note'), findsOneWidget);

      // Switching modules still works after breakpoint swaps.
      selectedIndex = 0;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('home:dashboard'), findsOneWidget);
      expect(otherModuleBuilds, greaterThan(0));
    },
  );

  testWidgets(
    'open document survives PlatformLayoutBuilder mobile/web host swap',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final pageKey = GlobalKey();
      final navigatorKey = GlobalKey<NavigatorState>();

      Widget page() {
        return Scaffold(
          body: KeyedSubtree(
            key: pageKey,
            child: DashboardContentNavigator(
              navigatorKey: navigatorKey,
              homeCacheKey: 6,
              homeRefreshKey: 'employee-docutracker',
              homeBuilder: () => const TextField(
                key: ValueKey('docutracker-unsaved-field'),
                decoration: InputDecoration(labelText: 'Remarks'),
              ),
              settingsPanel: const Text('settings'),
              homeScrollPadding: EdgeInsets.zero,
              settingsScrollPadding: EdgeInsets.zero,
            ),
          ),
        );
      }

      // Old EmployeeDashboard pattern: different wrappers per platform.
      Widget legacyHost() {
        return MaterialApp(
          home: PlatformLayoutBuilder(
            mobile: (_) => page(),
            web: (_) => page(),
            desktop: (_) => page(),
          ),
        );
      }

      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpWidget(legacyHost());
      await tester.enterText(
        find.byKey(const ValueKey('docutracker-unsaved-field')),
        'keep me',
      );
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Document DOC-1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Document DOC-1'), findsOneWidget);

      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpWidget(legacyHost());
      await tester.pumpAndSettle();
      expect(find.text('Document DOC-1'), findsOneWidget);

      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpWidget(legacyHost());
      await tester.pumpAndSettle();
      expect(find.text('Document DOC-1'), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('keep me'), findsOneWidget);
    },
  );
}
