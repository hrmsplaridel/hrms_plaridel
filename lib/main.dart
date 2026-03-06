import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'landingpage/constants/app_theme.dart';
import 'landingpage/screens/landing_page.dart';
import 'login/screens/login_page.dart';
import 'providers/auth_provider.dart';
import 'dtr/dtr_provider.dart';
import 'docutracker/docutracker_provider.dart';
import 'supabase/supabase_config.dart';
import 'admin/screens/admin_dashboard.dart';
import 'employee/screens/employee_dashboard.dart';

/// Key for persisting last login role (Admin vs Employee) across sessions.
const String kLoginAsKey = 'hrms_login_as';

/// Used by [LandingPage] to refetch job vacancy data when user returns from admin.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Chooses the initial screen based on platform and auth state.
/// If user has a restored session, go to the appropriate dashboard.
/// Otherwise: web → LandingPage, mobile → LoginPage.
Widget _initialHome(String storedLoginAs) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    final isAdmin = storedLoginAs == 'Admin';
    return isAdmin ? const AdminDashboard() : const EmployeeDashboard();
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
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (e) {
    debugPrint('Supabase init failed: $e');
    // Continue so the app still shows (e.g. landing page); auth features will fail until config is fixed.
  }
  final prefs = await SharedPreferences.getInstance();
  final storedLoginAs = prefs.getString(kLoginAsKey) ?? 'Admin';
  runApp(MyApp(storedLoginAs: storedLoginAs));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.storedLoginAs});

  final String storedLoginAs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DtrProvider()),
        ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
      ],
      child: MaterialApp(
        title: 'HRMS Plaridel',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorObservers: [routeObserver],
        home: _initialHome(storedLoginAs),
      ),
    );
  }
}
