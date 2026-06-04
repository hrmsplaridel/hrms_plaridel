import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/app/providers.dart';
import 'package:hrms_plaridel/app/route_observer.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/admin_dashboard.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_access_policy.dart';
import 'package:hrms_plaridel/features/landing/presentation/pages/landing_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/shared/widgets/sign_out_flow.dart';
import 'package:provider/provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.auth, required this.themeNotifier});

  final AuthProvider auth;
  final ThemeModeNotifier themeNotifier;

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      auth: auth,
      themeNotifier: themeNotifier,
      child: _HrmsMaterialApp(auth: auth, themeNotifier: themeNotifier),
    );
  }
}

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
