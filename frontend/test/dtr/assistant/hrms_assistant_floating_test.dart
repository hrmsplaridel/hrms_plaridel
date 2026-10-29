import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_session_storage.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_message_bubble.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_fab.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_controller.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_overlay.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/hrms_assistant_floating_frame.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

class _FakeAuthProvider extends AuthProvider {
  @override
  AppUser? get user => null;
}

class _HistoryAuthProvider extends AuthProvider {
  @override
  AppUser? get user => const AppUser(
    id: 'history-employee',
    email: 'employee@example.test',
    role: 'employee',
  );
}

class _FakeAssistantApi extends DtrAssistantApi {
  @override
  Future<void> resetChat({String? conversationId}) async {}

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
  testWidgets('restoring and clearing history shows no default reply', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1536, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await DtrAssistantSessionStorage.saveConversationId(
      'history-employee',
      'legacy-welcome',
    );
    await DtrAssistantSessionStorage.saveMessages(
      'history-employee',
      'legacy-welcome',
      [
        DtrAssistantMessage(
          role: 'assistant',
          content:
              'Hi. I am your HRMS Assistant. Ask me about your DTR, leave requests, leave balances, or locator slips.',
          createdAt: DateTime.now(),
        ),
      ],
    );
    final auth = _HistoryAuthProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          home: EmployeeDtrAssistantPage(api: _FakeAssistantApi()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DtrAssistantMessageBubble), findsNothing);
    await tester.tap(find.byTooltip('Clear chat history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Clear history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final list = find.byType(ListView).first;
    expect(tester.widget<ListView>(list).reverse, isFalse);
    // The introduction should follow the app bar, without a blank viewport.
    expect(
      tester
          .getTopLeft(find.textContaining('Answers use your HRMS records'))
          .dy,
      lessThan(220),
    );
    expect(find.byType(DtrAssistantMessageBubble), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });

  testWidgets(
    'long saved conversations build only the visible recent messages',
    (tester) async {
      final semantics = tester.ensureSemantics();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final messages = List.generate(
        500,
        (index) => DtrAssistantMessage(
          role: 'assistant',
          content: 'history-$index: ${'Employee record explanation. ' * 35}',
          createdAt: DateTime.now(),
        ),
      );
      await DtrAssistantSessionStorage.saveConversationId(
        'history-employee',
        'long-history',
      );
      await DtrAssistantSessionStorage.saveMessages(
        'history-employee',
        'long-history',
        messages,
      );
      final auth = _HistoryAuthProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            home: EmployeeDtrAssistantPage(api: _FakeAssistantApi()),
          ),
        ),
      );
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final rendered = tester.widgetList<DtrAssistantMessageBubble>(
        find.byType(DtrAssistantMessageBubble),
      );
      expect(rendered.length, lessThan(20));
      expect(
        rendered.any(
          (bubble) => bubble.message.content.startsWith('history-499:'),
        ),
        isTrue,
      );
      expect(
        (await DtrAssistantSessionStorage.loadMessages(
          'history-employee',
          'long-history',
        )).length,
        500,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      auth.dispose();
      semantics.dispose();
    },
  );

  testWidgets(
    'filing launcher cannot overlap submit, even after dragging down',
    (tester) async {
      for (final width in [390.0, 1536.0]) {
        await tester.binding.setSurfaceSize(Size(width, 778));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmployeeHrmsAssistantOverlay(
                initialBottom: 176,
                child: Stack(
                  children: [
                    Positioned(
                      bottom: 64,
                      right: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton(
                            key: const ValueKey('draft'),
                            onPressed: () {},
                            child: const Text('Save Draft'),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            key: const ValueKey('submit'),
                            onPressed: () {},
                            child: const Text('Submit Request'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final launcher = find.byType(DtrAssistantFab);
        expect(
          tester
              .getRect(launcher)
              .overlaps(tester.getRect(find.byKey(const ValueKey('draft')))),
          isFalse,
        );
        expect(
          tester
              .getRect(launcher)
              .overlaps(tester.getRect(find.byKey(const ValueKey('submit')))),
          isFalse,
        );
        await tester.drag(launcher, const Offset(0, 300));
        await tester.pump();
        expect(
          tester
              .getRect(launcher)
              .overlaps(tester.getRect(find.byKey(const ValueKey('draft')))),
          isFalse,
        );
        expect(
          tester
              .getRect(launcher)
              .overlaps(tester.getRect(find.byKey(const ValueKey('submit')))),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('dashboard launcher returns after a filing form closes', (
    tester,
  ) async {
    for (final width in [390.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      var filing = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return EmployeeHrmsAssistantOverlay(
                isDashboard: true,
                child: filing
                    ? const EmployeeHrmsAssistantOverlay(
                        child: Scaffold(body: Text('Filing')),
                      )
                    : const Scaffold(body: Text('Attendance')),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DraggableDtrAssistantLauncher), findsOneWidget);
      update(() => filing = true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(DraggableDtrAssistantLauncher), findsOneWidget);
      update(() => filing = false);
      await tester.pump();
      await tester.pump();
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.byType(DraggableDtrAssistantLauncher), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    await tester.binding.setSurfaceSize(null);
  });

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

  testWidgets('mobile assistant uses a contained movable panel layout', (
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
      findsOneWidget,
    );
    expect(rect.width, closeTo(320, 0.1));
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.right, lessThanOrEqualTo(378));
    expect(rect.bottom, lessThanOrEqualTo(832));
    expect(rect.top, greaterThanOrEqualTo(12));
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

  testWidgets('embedded assistant suppresses the dashboard launcher', (
    tester,
  ) async {
    final controller = EmployeeHrmsAssistantController.instance;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: controller.baseLauncherSuppressed,
              builder: (_, suppressed, _) => Text('$suppressed'),
            ),
            const EmployeeHrmsAssistantOverlay(
              child: ColoredBox(color: Colors.white),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(controller.baseLauncherSuppressed.value, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(controller.baseLauncherSuppressed.value, isFalse);
  });
}
