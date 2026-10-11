import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/auth/presentation/pages/login_page.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/sign_out_flow.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthProvider {
  final completion = Completer<void>();

  @override
  Future<void> signOut() => completion.future;
}

void main() {
  for (final removeDashboard in [false, true]) {
    testWidgets(
      'logout reaches login with dashboard removed=$removeDashboard',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = _Auth();
        final visible = ValueNotifier(true);
        BuildContext? dashboardContext;
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: MaterialApp(
              home: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (context, show, child) => show
                    ? Builder(
                        builder: (context) {
                          dashboardContext = context;
                          return Scaffold(
                            body: TextButton(
                              onPressed: () => performDashboardSignOut(context),
                              child: const Text('Log out'),
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Log out'));
        await tester.pump();
        expect(find.byType(SignOutLoadingOverlay), findsOneWidget);
        if (removeDashboard) {
          visible.value = false;
          await tester.pump();
          expect(dashboardContext!.mounted, isFalse);
        }
        auth.completion.complete();
        await tester.pump(kSignOutLoadingMinDuration);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(SignOutLoadingOverlay), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        visible.dispose();
        auth.dispose();
      },
    );
  }
}
