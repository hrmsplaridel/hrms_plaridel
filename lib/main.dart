import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'webview_platform_init_stub.dart'
    if (dart.library.html) 'webview_platform_init_web.dart'
    as webview_platform_init;
import 'api/client.dart';
import 'landingpage/constants/app_theme.dart';
import 'landingpage/screens/landing_page.dart';
import 'login/screens/login_page.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/recruitment_hire_prefill.dart';
import 'dtr/dtr_provider.dart';
import 'docutracker/docutracker_provider.dart';
import 'leave/leave_provider.dart';
import 'leave/api_leave_repository.dart';
import 'data/philippine_psgc_loader.dart';
import 'notifications/notification_provider.dart';
import 'realtime/app_realtime_bridge.dart';
import 'realtime/app_realtime_provider.dart';
import 'admin/screens/admin_dashboard.dart';
import 'employee/screens/employee_dashboard.dart';

/// Key for persisting last login role (Admin vs Employee) across sessions.
const String kLoginAsKey = 'hrms_login_as';

/// Used by [LandingPage] to refetch job vacancy data when user returns from admin.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Chooses the initial screen based on platform and auth state.
/// If user has a restored session (API), go to the appropriate dashboard
/// based on the user's role from the API (not user choice).
/// Otherwise: web → LandingPage, mobile → LoginPage.
Widget _initialHome(AuthProvider auth, String storedLoginAs) {
  if (auth.user != null) {
    final role = auth.user!.role ?? 'employee';
    final isPrivileged = role == 'admin' || role == 'hr';
    return isPrivileged ? const AdminDashboard() : const EmployeeDashboard();
  }

  if (kIsWeb) {
    return const LandingPage();
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return const LoginPage();
    default:
      return const LandingPage();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    webview_platform_init.registerWebViewPlatform();
  }

  await PhilippinePsgcData.loadIndex();

  ApiClient.instance.init();

  final auth = AuthProvider();
  await auth.restoreSession();
  final prefs = await SharedPreferences.getInstance();
  final storedLoginAs = prefs.getString(kLoginAsKey) ?? 'Admin';
  final themeNotifier = await ThemeModeNotifier.load();

  runApp(
    MyApp(
      auth: auth,
      storedLoginAs: storedLoginAs,
      themeNotifier: themeNotifier,
    ),
  );
}

/// Isolated [MaterialApp] so theme changes only rebuild this subtree.
class _HrmsMaterialApp extends StatelessWidget {
  const _HrmsMaterialApp({required this.auth, required this.storedLoginAs});

  final AuthProvider auth;
  final String storedLoginAs;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<ThemeModeNotifier, ThemeMode>(
      (n) => n.mode,
    );

    return MaterialApp(
      title: 'HRMS Plaridel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 420),
      themeAnimationCurve: Curves.easeInOutCubic,
      navigatorObservers: [routeObserver],
      home: _initialHome(auth, storedLoginAs),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.storedLoginAs,
    required this.themeNotifier,
  });

  final AuthProvider auth;
  final String storedLoginAs;
  final ThemeModeNotifier themeNotifier;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeModeNotifier>.value(value: themeNotifier),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProxyProvider<AuthProvider, AppRealtimeProvider>(
          create: (_) => AppRealtimeProvider(),
          update: (_, auth, realtime) =>
              (realtime ?? AppRealtimeProvider())..setCurrentUser(auth.user?.id),
        ),
        ChangeNotifierProvider(create: (_) => DtrProvider()),
        ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(
          create: (context) => LeaveProvider(
            repository: ApiLeaveRepository(),
            onMutation: () {
              context.read<NotificationProvider>().refreshUnreadCount();
            },
          ),
        ),
        ChangeNotifierProvider(create: (_) => RecruitmentHirePrefill()),
      ],
      child: AppRealtimeBridge(
        child: _HrmsMaterialApp(auth: auth, storedLoginAs: storedLoginAs),
      ),
    );
  }
}
