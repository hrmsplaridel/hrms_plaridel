import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/mobile/widgets/employee_dashboard_mobile_drawer.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';

class _EmployeeAuth extends AuthProvider {
  _EmployeeAuth({String? positionName = 'Administrative Assistant'})
    : _positionName = positionName;

  String? _positionName;

  void updatePosition(String? positionName) {
    _positionName = positionName;
    notifyListeners();
  }

  @override
  AppUser get user => AppUser(
    id: 'mobile-drawer-employee',
    email: 'employee@example.test',
    role: 'employee',
    firstName: 'Johnley',
    lastName: 'Matabalan',
    positionName: _positionName,
  );
}

Future<GlobalKey<ScaffoldState>> _openDrawer(
  WidgetTester tester,
  Size size, {
  ValueChanged<int>? onNavSelected,
  VoidCallback? onProfile,
  _EmployeeAuth? employeeAuth,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = employeeAuth ?? _EmployeeAuth();
  final documents = DocuTrackerProvider();
  addTearDown(auth.dispose);
  addTearDown(documents.dispose);
  final scaffold = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<DocuTrackerProvider>.value(value: documents),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: child!,
        ),
        home: Scaffold(
          key: scaffold,
          drawer: EmployeeDashboardMobileDrawer(
            displayName: 'Johnley Matabalan',
            avatarPath: null,
            selectedIndex: 0,
            onNavSelected: onNavSelected ?? (_) {},
            onProfile: onProfile ?? () {},
          ),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
  scaffold.currentState!.openDrawer();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return scaffold;
}

void main() {
  testWidgets(
    'drawer follows position updates and falls back when unassigned',
    (tester) async {
      final auth = _EmployeeAuth(positionName: null);
      await _openDrawer(tester, const Size(390, 844), employeeAuth: auth);
      final profile = find.byType(DashboardSidebarProfileCard);
      String subtitle() =>
          tester.widget<DashboardSidebarProfileCard>(profile).subtitle;

      expect(subtitle(), 'Employee');
      auth.updatePosition('  Human Resource Management Officer  ');
      await tester.pump();
      expect(subtitle(), 'Human Resource Management Officer');
      auth.updatePosition('   ');
      await tester.pump();
      expect(subtitle(), 'Employee');
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('profile stays in the drawer footer at $size', (tester) async {
      await _openDrawer(tester, size);
      final profile = find.byType(DashboardSidebarProfileCard);
      expect(
        tester.widget<DashboardSidebarProfileCard>(profile).subtitle,
        'Administrative Assistant',
      );
      final navigation = find.byType(ListView);
      final copyright = find.textContaining('©');

      expect(
        tester.getTopLeft(profile).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(navigation).dy),
      );
      expect(
        tester.getBottomLeft(profile).dy,
        lessThan(tester.getTopLeft(copyright).dy),
      );
      expect(tester.getBottomLeft(copyright).dy, lessThan(size.height - 24));

      final footerBeforeScroll = tester.getRect(profile);
      await tester.drag(navigation, const Offset(0, -450));
      await tester.pump(const Duration(milliseconds: 350));
      final footerAfterScroll = tester.getRect(profile);
      expect(footerAfterScroll.top, closeTo(footerBeforeScroll.top, 0.01));
      expect(
        footerAfterScroll.bottom,
        closeTo(footerBeforeScroll.bottom, 0.01),
      );
      expect(find.text('DocuTracker').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('account menu opens above footer and Settings works at $size', (
      tester,
    ) async {
      var profileOpened = false;
      final scaffold = await _openDrawer(
        tester,
        size,
        onProfile: () => profileOpened = true,
      );
      await tester.tap(find.byType(DashboardSidebarProfileCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final settings = find.text('Settings');
      final signOut = find.text('Sign out');
      expect(settings.hitTestable(), findsOneWidget);
      expect(signOut.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(settings).dy, greaterThanOrEqualTo(24));
      expect(
        tester.getBottomLeft(signOut).dy,
        lessThan(
          tester.getTopLeft(find.byType(DashboardSidebarProfileCard)).dy,
        ),
      );

      await tester.tap(settings);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 350));
      expect(profileOpened, isTrue);
      expect(scaffold.currentState!.isDrawerOpen, isFalse);
      expect(find.text('Sign out'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drawer navigation still selects and closes at $size', (
      tester,
    ) async {
      int? selected;
      final scaffold = await _openDrawer(
        tester,
        size,
        onNavSelected: (index) => selected = index,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('DocuTracker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(selected, 6);
      expect(scaffold.currentState!.isDrawerOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
