import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/shared/widgets/profile_account_tab_skeleton.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';

void main() {
  testWidgets('deferred address mount safely notifies the parent', (tester) async {
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
