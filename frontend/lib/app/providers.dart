import 'package:flutter/widgets.dart';
import 'package:hrms_plaridel/core/services/app_realtime_bridge.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';
import 'package:provider/provider.dart';

class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.auth,
    required this.themeNotifier,
    required this.child,
  });

  final AuthProvider auth;
  final ThemeModeNotifier themeNotifier;
  final Widget child;

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
      child: AppRealtimeBridge(child: child),
    );
  }
}
