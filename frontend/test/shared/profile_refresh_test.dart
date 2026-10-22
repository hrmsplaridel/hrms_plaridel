import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart';

class _RefreshAuth extends AuthProvider {
  final Completer<void> ready = Completer<void>();
  int loads = 0;
  AppUser latest = const AppUser(
    id: 'profile-refresh',
    email: 'profile@test',
    firstName: 'Maria',
    sex: 'female',
  );
  @override
  Future<void> refreshUser() async {
    loads++;
    await ready.future;
    replaceUser(latest);
  }
}

void main() {
  Future<void> mount(WidgetTester tester, AuthProvider auth) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(PhilippinePsgcData.ensureIndexLoaded);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileContent(
                showPasswordSection: false,
                showAppSettings: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder gender(String? value) => find.byKey(ValueKey('sex-${value ?? ''}'));
  testWidgets(
    'opening profile fetches current gender instead of keeping login snapshot',
    (tester) async {
      final auth = _RefreshAuth()
        ..replaceUser(
          const AppUser(
            id: 'profile-refresh',
            email: 'profile@test',
            firstName: 'Maria',
          ),
        );
      addTearDown(auth.dispose);
      await mount(tester, auth);
      expect(auth.loads, 1);
      auth.ready.complete();
      await tester.pumpAndSettle();
      expect(gender('Female'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(gender('Female'))
            .initialValue,
        'Female',
      );
      final save = find.widgetWithText(FilledButton, 'Save changes');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.pump();
      expect(auth.loads, 1);
    },
  );
  testWidgets('clean profile fields follow refreshed account data', (
    tester,
  ) async {
    final auth = _RefreshAuth()
      ..replaceUser(
        const AppUser(
          id: 'profile-refresh',
          email: 'profile@test',
          firstName: 'Maria',
          sex: 'Male',
        ),
      );
    addTearDown(auth.dispose);
    await mount(tester, auth);
    auth.replaceUser(
      const AppUser(
        id: 'profile-refresh',
        email: 'profile@test',
        firstName: 'Maria',
        sex: 'Female',
      ),
    );
    await tester.pumpAndSettle();
    expect(gender('Female'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'late profile refresh keeps unsaved edits and discard uses latest account',
    (tester) async {
      final auth = _RefreshAuth()
        ..replaceUser(
          const AppUser(
            id: 'profile-refresh',
            email: 'profile@test',
            firstName: 'Maria',
            sex: 'Male',
          ),
        );
      addTearDown(auth.dispose);
      await mount(tester, auth);
      final name = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Maria',
      );
      await tester.enterText(name, 'Marie');
      await tester.pumpAndSettle();
      auth.ready.complete();
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == 'Marie',
        ),
        findsOneWidget,
      );
      expect(gender('Male'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save changes');
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Discard changes'));
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(gender('Female'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    },
  );
  testWidgets('refresh does not replace an unsaved gender selection', (
    tester,
  ) async {
    final auth = _RefreshAuth()
      ..replaceUser(
        const AppUser(
          id: 'profile-refresh',
          email: 'profile@test',
          firstName: 'Maria',
          sex: 'Male',
        ),
      );
    auth.latest = const AppUser(
      id: 'profile-refresh',
      email: 'profile@test',
      firstName: 'Maria',
      sex: 'Male',
    );
    addTearDown(auth.dispose);
    await mount(tester, auth);
    tester.widget<DropdownButtonFormField<String>>(gender('Male')).onChanged!(
      'Female',
    );
    await tester.pumpAndSettle();
    auth.ready.complete();
    await tester.pumpAndSettle();
    expect(gender('Female'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'closing profile detaches account listener while refresh is pending',
    (tester) async {
      final auth = _RefreshAuth()
        ..replaceUser(
          const AppUser(
            id: 'profile-refresh',
            email: 'profile@test',
            firstName: 'Maria',
            sex: 'Male',
          ),
        );
      addTearDown(auth.dispose);
      await mount(tester, auth);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      auth.ready.complete();
      await tester.pumpAndSettle();
      expect(auth.hasListeners, false);
      expect(auth.user!.sex, 'female');
      expect(tester.takeException(), isNull);
    },
  );
}
