import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/shared/widgets/profile_account_tab_skeleton.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';

void main() {
  testWidgets('unmatched address search is not saved on a narrow form', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.runAsync(PhilippinePsgcData.ensureIndexLoaded);
    final street = TextEditingController();
    addTearDown(street.dispose);
    final key = GlobalKey<StructuredAddressFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StructuredAddressForm(
              key: key,
              streetController: street,
              twoColumn: true,
              inputDecoration: (hint) => InputDecoration(hintText: hint),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final province = find.byWidgetPredicate(
      (w) =>
          w is DropdownMenu<String> &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('province-'),
    );
    await tester.enterText(
      find.descendant(of: province, matching: find.byType(TextField)),
      'Not a real province',
    );
    await tester.pumpAndSettle();
    expect(
      parseStoredAddress(key.currentState!.composeEncoded()).province,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('address dropdowns search and preserve cascading selections', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await PhilippinePsgcData.ensureIndexLoaded();
      await PhilippinePsgcData.loadProvinceMap('Misamis Occidental');
    });
    final street = TextEditingController();
    addTearDown(street.dispose);
    final key = GlobalKey<StructuredAddressFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StructuredAddressForm(
              key: key,
              streetController: street,
              inputDecoration: (hint) => InputDecoration(hintText: hint),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder menu(String prefix) => find.byWidgetPredicate(
      (w) =>
          w is DropdownMenu<String> &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith(prefix),
    );
    Finder search(String prefix) =>
        find.descendant(of: menu(prefix), matching: find.byType(TextField));
    expect(tester.widget<DropdownMenu<String>>(menu('city-')).enabled, isFalse);
    await tester.enterText(search('province-'), 'misamis occ');
    await tester.pumpAndSettle();
    expect(find.text('Abra'), findsNothing);
    await tester.tap(find.text('Misamis Occidental').last);
    await tester.pumpAndSettle();
    await tester.enterText(search('city-'), 'plari');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plaridel').last);
    await tester.pumpAndSettle();
    final barangay = PhilippinePsgcData.barangaysFor(
      'Misamis Occidental',
      'Plaridel',
    )!.first;
    await tester.enterText(search('brgy-'), barangay.toLowerCase());
    await tester.pumpAndSettle();
    await tester.tap(find.text(barangay).last);
    await tester.pumpAndSettle();
    var stored = parseStoredAddress(key.currentState!.composeEncoded());
    expect(stored.province, 'Misamis Occidental');
    expect(stored.city, 'Plaridel');
    expect(stored.barangay, barangay);
    await tester.enterText(search('city-'), 'aloran');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aloran').last);
    await tester.pumpAndSettle();
    stored = parseStoredAddress(key.currentState!.composeEncoded());
    expect(stored.city, 'Aloran');
    expect(stored.barangay, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deferred address mount safely notifies the parent', (
    tester,
  ) async {
    await tester.runAsync(PhilippinePsgcData.ensureIndexLoaded);
    final key = GlobalKey<_ProfileHarnessState>();
    await tester.pumpWidget(MaterialApp(home: _ProfileHarness(key: key)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(key.currentState!.street.text, 'Purok2');
    expect(find.text('Saved street: Purok2'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'New street');
    await tester.pump();
    expect(find.text('Saved street: New street'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ProfileHarness extends StatefulWidget {
  const _ProfileHarness({super.key});

  @override
  State<_ProfileHarness> createState() => _ProfileHarnessState();
}

class _ProfileHarnessState extends State<_ProfileHarness> {
  final street = TextEditingController();

  @override
  void initState() {
    super.initState();
    street.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    street.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Text('Saved street: ${street.text}'),
            DeferredProfileMount(
              builder: () => StructuredAddressForm(
                streetController: street,
                initialRawAddress: 'Purok2',
                inputDecoration: (hint) => InputDecoration(hintText: hint),
                onChanged: _refresh,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
