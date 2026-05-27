import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
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
import 'docutracker/services/docutracker_access_policy.dart';
import 'leave/leave_provider.dart';
import 'leave/api_leave_repository.dart';
import 'data/philippine_psgc_loader.dart';
import 'notifications/notification_provider.dart';
import 'realtime/app_realtime_bridge.dart';
import 'realtime/app_realtime_provider.dart';
import 'admin/screens/admin_dashboard.dart';
import 'employee/screens/employee_dashboard.dart';
import 'shared/widgets/sign_out_flow.dart';
import 'utils/form_pdf.dart';

/// Key for persisting last login role (Admin vs Employee) across sessions.
const String kLoginAsKey = 'hrms_login_as';

/// Used by [LandingPage] to refetch job vacancy data when user returns from admin.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Chooses the initial screen based on platform and auth state.
/// If user has a restored session (API), go to the appropriate dashboard
/// based on the user's role from the API.
/// Otherwise: web/desktop → LandingPage, mobile → LoginPage.
Widget _initialHome(AuthProvider auth) {
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
  unawaited(FormPdf.warmupPrintAssets());

  if (kIsWeb) {
    webview_platform_init.registerWebViewPlatform();
  }

  ApiClient.instance.init();

  final auth = AuthProvider();
  final themeNotifier = ThemeModeNotifier(initial: ThemeMode.light);

  runApp(
    MyApp(
      auth: auth,
      themeNotifier: themeNotifier,
    ),
  );
}

/// Isolated [MaterialApp] so theme changes only rebuild this subtree.
class _HrmsMaterialApp extends StatelessWidget {
  const _HrmsMaterialApp({required this.auth, required this.themeNotifier});

  final AuthProvider auth;
  final ThemeModeNotifier themeNotifier;

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
      onGenerateRoute: (settings) {
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
        final isMobile = DocuTrackerAccessPolicy.isMobileWidth(logicalWidth);
        if (isMobile &&
            DocuTrackerAccessPolicy.isRouteRestrictedOnMobile(settings.name)) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _RestrictedMobileRouteScreen(
              attemptedRoute: settings.name ?? '',
            ),
          );
        }
        return null;
      },
      home: _StartupGate(auth: auth, themeNotifier: themeNotifier),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate({required this.auth, required this.themeNotifier});

  final AuthProvider auth;
  final ThemeModeNotifier themeNotifier;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<void> _startup = _bootstrap();

  Future<void> _bootstrap() async {
    final themeModeFuture = ThemeModeNotifier.loadSavedMode();
    final psgcFuture = PhilippinePsgcData.loadIndex();
    final sessionFuture = widget.auth.restoreSession();

    try {
      final savedThemeMode = await themeModeFuture;
      widget.themeNotifier.restorePersistedMode(savedThemeMode);
    } catch (e, st) {
      debugPrint('Theme preference restore failed: $e\n$st');
    }

    try {
      await Future.wait<void>([psgcFuture, sessionFuture]);
    } catch (e, st) {
      debugPrint('Startup bootstrap failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SignOutLoadingOverlay(
            title: 'Preparing your workspace',
            subtitle: 'Loading HRMS Plaridel',
          );
        }
        return _initialHome(widget.auth);
      },
    );
  }
}

class _RestrictedMobileRouteScreen extends StatelessWidget {
  const _RestrictedMobileRouteScreen({required this.attemptedRoute});

  final String attemptedRoute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unavailable on Mobile')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 36),
              const SizedBox(height: 10),
              const Text(
                'This page is desktop-only.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                attemptedRoute.isEmpty
                    ? 'Admin features are disabled on mobile.'
                    : 'Route blocked: $attemptedRoute',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.themeNotifier,
  });

  final AuthProvider auth;
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
              (realtime ?? AppRealtimeProvider())
                ..setCurrentUser(auth.user?.id),
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
        child: _HrmsMaterialApp(auth: auth, themeNotifier: themeNotifier),
      ),
    );
  }
}
