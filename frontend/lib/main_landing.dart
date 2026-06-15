import 'package:flutter/material.dart';
import 'package:hrms_plaridel/app/route_observer.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/pages/landing_page.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/shared/widgets/sign_out_flow.dart';

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
      home: const _LandingStartupGate(),
    );
  }
}

class _LandingStartupGate extends StatefulWidget {
  const _LandingStartupGate();

  @override
  State<_LandingStartupGate> createState() => _LandingStartupGateState();
}

class _LandingStartupGateState extends State<_LandingStartupGate> {
  late final Future<void> _startup = PhilippinePsgcData.loadIndex();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SignOutLoadingOverlay(
            title: 'Loading applicant portal',
            subtitle: 'Preparing address lists…',
          );
        }
        return const LandingPage();
      },
    );
  }
}
