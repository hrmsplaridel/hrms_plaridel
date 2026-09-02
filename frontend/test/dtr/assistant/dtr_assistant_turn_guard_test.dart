import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_api.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/dtr_assistant_turn_guard.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_input_bar.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TurnAuthProvider extends AuthProvider {
  @override
  AppUser? get user => const AppUser(
    id: 'employee-turn-test',
    email: 'turn@test.local',
    role: 'employee',
  );
}

class _PendingTurn {
  _PendingTurn(this.message, this.completer, this.cancelToken);

  final String message;
  final Completer<DtrAssistantMessage> completer;
  final CancelToken? cancelToken;
}

class _TurnAssistantApi extends DtrAssistantApi {
  final pending = <_PendingTurn>[];

  @override
  Future<({String defaultModelProfile, List<DtrAssistantModelProfile> models})>
  fetchModels() async => (
    defaultModelProfile: 'tools_ollama',
    models: const [
      DtrAssistantModelProfile(
        id: 'tools_ollama',
        label: 'Qwen',
        engine: 'tools',
        provider: 'ollama',
        model: 'test',
      ),
    ],
  );

  @override
  Future<DtrAssistantMessage> sendMessage(
    String message, {
    String? intent,
    String? modelProfile,
    String? conversationId,
    String? externalConsentVersion,
    CancelToken? cancelToken,
  }) {
    final completer = Completer<DtrAssistantMessage>();
    pending.add(_PendingTurn(message, completer, cancelToken));
    return completer.future;
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('turn guard invalidates superseded generations', () {
    final guard = DtrAssistantTurnGuard();
    final first = guard.begin();
    expect(guard.isCurrent(first), isTrue);

    guard.invalidate();
    expect(guard.isCurrent(first), isFalse);

    final second = guard.begin();
    expect(guard.isCurrent(second), isTrue);
    expect(guard.isCurrent(first), isFalse);
  });

  testWidgets('stopped reply cannot overwrite the next assistant turn', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _TurnAssistantApi();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TurnAuthProvider(),
        child: MaterialApp(home: EmployeeDtrAssistantPage(api: api)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    Future<void> send(String text) async {
      tester
          .widget<DtrAssistantInputBar>(find.byType(DtrAssistantInputBar))
          .onSend(text);
      await tester.pump();
    }

    await send('first question');
    expect(api.pending, hasLength(1));
    await tester.tap(find.byTooltip('Stop generating'));
    await tester.pump();
    expect(api.pending.first.cancelToken?.isCancelled, isTrue);

    await send('second question');
    expect(api.pending, hasLength(2));
    api.pending[1].completer.complete(
      DtrAssistantMessage(
        role: 'assistant',
        content: 'second answer',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    api.pending[0].completer.complete(
      DtrAssistantMessage(
        role: 'assistant',
        content: 'stale first answer',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('second answer'), findsOneWidget);
    expect(find.text('stale first answer'), findsNothing);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
