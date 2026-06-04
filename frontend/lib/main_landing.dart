import 'package:flutter/material.dart';
import 'package:hrms_plaridel/app/route_observer.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/pages/landing_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiClient.instance.init();

  runApp(const LandingOnlyApp());
}

class LandingOnlyApp extends StatelessWidget {
  const LandingOnlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HRMS Plaridel Applicant Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      navigatorObservers: [routeObserver],
      home: const LandingPage(),
    );
  }
}
