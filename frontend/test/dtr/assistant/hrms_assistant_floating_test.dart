import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/hrms_assistant_floating_frame.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

class _FakeAuthProvider extends AuthProvider {
  @override
  AppUser? get user => null;
}

class _FakeAssistantApi extends DtrAssistantApi {
  @override
  Future<({String defaultModelProfile, List<DtrAssistantModelProfile> models})>
  fetchModels() async {
    return (
      defaultModelProfile: 'tools_ollama',
      models: const [
        DtrAssistantModelProfile(
          id: 'tools_ollama',
          label: 'Qwen',
          engine: 'tools',
          provider: 'ollama',
          model: 'test',
          available: true,
        ),
      ],
    );
  }
}

void main() {
  testWidgets('desktop assistant panel drags freely inside the viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              HrmsAssistantFloatingFrame(
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Assistant content')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final panel = find.byKey(const ValueKey('hrms-assistant-floating-panel'));
    final dragHandle = find.byKey(
      const ValueKey('hrms-assistant-floating-drag-handle'),
    );
    final before = tester.getRect(panel);

    expect(dragHandle, findsOneWidget);
    expect(before.right, lessThanOrEqualTo(1280 - 16));
    expect(before.bottom, lessThanOrEqualTo(1000 - 16));

    await tester.drag(dragHandle, const Offset(-620, 120));
    await tester.pump();

    final after = tester.getRect(panel);
    expect(after.left, closeTo(before.left - 620, 0.1));
    expect(after.top, closeTo(before.top + 120, 0.1));
    expect(after.bottom, lessThanOrEqualTo(1000 - 16));
  });

  testWidgets('mobile assistant uses a contained bottom sheet layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              HrmsAssistantFloatingFrame(
                child: ColoredBox(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

    final panel = find.byKey(const ValueKey('hrms-assistant-floating-panel'));
    final rect = tester.getRect(panel);

    expect(
      find.byKey(const ValueKey('hrms-assistant-floating-drag-handle')),
      findsNothing,
    );
    expect(rect.left, closeTo(8, 0.1));
    expect(rect.right, closeTo(382, 0.1));
    expect(rect.bottom, closeTo(836, 0.1));
    expect(rect.top, greaterThanOrEqualTo(8));
  });

  testWidgets('assistant page exposes minimize and floating window controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = _FakeAuthProvider();
    final api = _FakeAssistantApi();
    var minimized = false;
    var expanded = false;
    var closed = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          home: EmployeeDtrAssistantPage(
            api: api,
            onMinimize: () => minimized = true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Minimize to floating assistant'));
    await tester.pump();
    expect(minimized, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          home: EmployeeDtrAssistantPage(
            api: api,
            floating: true,
            onExpand: () => expanded = true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Minimize to floating assistant'), findsNothing);
    await tester.tap(find.byTooltip('Open full assistant'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close assistant'));
    await tester.pump();

    expect(expanded, isTrue);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
