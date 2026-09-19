import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart';

void main() {
  testWidgets('Save changes follows edits, reverts, and discard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(PhilippinePsgcData.ensureIndexLoaded);
    final auth = AuthProvider();
    auth.replaceUser(const AppUser(
      id: 'profile-test',
      email: 'profile@example.com',
      firstName: 'Maria',
      lastName: 'Santos',
    ));
    addTearDown(auth.dispose);
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

    final save = find.widgetWithText(FilledButton, 'Save changes');
    final firstName = find.byWidgetPredicate(
      (widget) => widget is TextFormField && widget.controller?.text == 'Maria',
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(firstName, 'Marie');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    final edited = find.byWidgetPredicate(
      (widget) => widget is TextFormField && widget.controller?.text == 'Marie',
    );
    await tester.enterText(edited, 'Maria');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(firstName, 'Marie');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Discard changes'));
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(firstName, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
