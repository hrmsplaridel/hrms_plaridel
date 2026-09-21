import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/app/providers.dart';
import 'package:hrms_plaridel/app/route_observer.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/admin_dashboard.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/features/mayor/presentation/pages/mayor_dashboard_page.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_access_policy.dart';
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
      title: 'HRMS',
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
  late final Future<void> _themeStartup = _loadSavedTheme();
  late final Future<void> _psgcStartup = _loadPsgcIndex();
  late Future<SessionRestoreResult> _startup = _bootstrap();
  Timer? _sessionRetryTimer;
  int _sessionRetryAttempt = 0;

  Future<SessionRestoreResult> _bootstrap() async {
    final restoreResult = await widget.auth.restoreSession();
    if (restoreResult != SessionRestoreResult.temporarilyUnavailable) {
      await _themeStartup;
      await _psgcStartup;
    }
    return restoreResult;
  }

  Future<void> _loadSavedTheme() async {
    try {
      final savedThemeMode = await ThemeModeNotifier.loadSavedMode();
      widget.themeNotifier.restorePersistedMode(savedThemeMode);
    } catch (e, st) {
      debugPrint('Theme preference restore failed: $e\n$st');
    }
  }

  Future<void> _loadPsgcIndex() async {
    try {
      await PhilippinePsgcData.loadIndex();
    } catch (e, st) {
      debugPrint('PSGC startup load failed: $e\n$st');
    }
  }

  Future<SessionRestoreResult> _restoreSessionAfterStartup() async {
    final restoreResult = await widget.auth.restoreSession();
    if (restoreResult != SessionRestoreResult.temporarilyUnavailable) {
      await _themeStartup;
      await _psgcStartup;
    }
    return restoreResult;
  }

  void _scheduleSessionRetry() {
    if (_sessionRetryTimer?.isActive == true) return;
    final delaySeconds = switch (_sessionRetryAttempt) {
      0 => 2,
      1 => 4,
      _ => 8,
    };
    _sessionRetryAttempt += 1;
    _sessionRetryTimer = Timer(Duration(seconds: delaySeconds), _retrySession);
  }

  void _retrySession() {
    _sessionRetryTimer?.cancel();
    _sessionRetryTimer = null;
    if (!mounted) return;
    setState(() {
      _startup = _restoreSessionAfterStartup();
    });
  }

  @override
  void dispose() {
    _sessionRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionRestoreResult>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SignOutLoadingOverlay(
            title: 'Preparing your workspace',
            subtitle: 'Loading HRMS',
          );
        }
        final restoreResult = snapshot.data;
        if (snapshot.hasError ||
            restoreResult == SessionRestoreResult.temporarilyUnavailable) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scheduleSessionRetry();
          });
          return _SessionReconnectScreen(onRetry: _retrySession);
        }
        _sessionRetryTimer?.cancel();
        _sessionRetryTimer = null;
        _sessionRetryAttempt = 0;
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
        return _initialHome(widget.auth, logicalWidth: logicalWidth);
      },
    );
  }
}

class _SessionReconnectScreen extends StatelessWidget {
  const _SessionReconnectScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 44,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Waiting for the HRMS server',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your saved sign-in is still available. The app will reconnect automatically.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry now'),
                ),
              ],
            ),
          ),
        ),
      ),
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
              if (attemptedRoute.isEmpty) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => performDashboardSignOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Return to login'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _initialHome(AuthProvider auth, {required double logicalWidth}) {
  if (auth.user != null) {
    final role = (auth.user!.role ?? 'employee').toLowerCase();
    if (role == 'mayor') return const MayorDashboardPage();
    final isPrivileged = role == 'admin' || role == 'hr';
    final isNativeMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final isMobile =
        isNativeMobile || DocuTrackerAccessPolicy.isMobileWidth(logicalWidth);
    if (isPrivileged && isMobile) {
      return const _RestrictedMobileRouteScreen(attemptedRoute: '');
    }
    return isPrivileged ? const AdminDashboard() : const EmployeeDashboard();
  }

  return const LoginPage();
}
