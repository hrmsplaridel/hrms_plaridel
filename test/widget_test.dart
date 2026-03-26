// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/main.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/api/app_user.dart';

class FakeAuthProvider extends AuthProvider {
  FakeAuthProvider(this._fakeUser);

  final AppUser? _fakeUser;

  @override
  AppUser? get user => _fakeUser;
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Provide a non-null user so `_initialHome` renders the dashboard
    // instead of `LoginPage` (which can overflow at test viewport widths).
    final auth = FakeAuthProvider(
      const AppUser(
        id: 'test-user-id',
        email: 'test@example.com',
        role: 'admin',
      ),
    );

    // The default test viewport width can be too small for some of our pages
    // (e.g. `LoginPage`), causing RenderFlex overflow exceptions.
    await tester.binding.setSurfaceSize(const Size(1200, 2000));

    // Build the app and trigger a frame.
    await tester.pumpWidget(MyApp(
      auth: auth,
      storedLoginAs: 'Admin',
    ));

    // Basic sanity check: the app bootstrapped without throwing.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
