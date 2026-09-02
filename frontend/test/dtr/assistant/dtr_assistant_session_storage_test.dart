import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'stores assistant messages in secure storage, not preferences',
    () async {
      final message = DtrAssistantMessage(
        role: 'user',
        content: 'Why was my sick leave rejected?',
        createdAt: DateTime.utc(2026, 9, 2),
        feedbackToken: 'server-signed-feedback-token',
      );

      await DtrAssistantSessionStorage.saveConversationId(
        'employee-1',
        'chat-1',
      );
      await DtrAssistantSessionStorage.saveMessages('employee-1', 'chat-1', [
        message,
      ]);

      final restored = await DtrAssistantSessionStorage.loadMessages(
        'employee-1',
        'chat-1',
      );
      final secureValues = await secureStorage.readAll();
      final preferences = await SharedPreferences.getInstance();

      expect(restored.single.content, message.content);
      expect(restored.single.feedbackToken, message.feedbackToken);
      expect(
        secureValues.values.any((value) => value.contains(message.content)),
        isTrue,
      );
      expect(
        preferences.getKeys().where((key) => key.startsWith('dtr_assistant_')),
        isEmpty,
      );
    },
  );

  test('clearAllForUser removes all of that user history only', () async {
    final message = DtrAssistantMessage(
      role: 'user',
      content: 'Private message',
      createdAt: DateTime.utc(2026, 9, 2),
    );
    await DtrAssistantSessionStorage.saveConversationId('employee-1', 'chat-1');
    await DtrAssistantSessionStorage.saveMessages('employee-1', 'chat-1', [
      message,
    ]);
    await DtrAssistantSessionStorage.saveMessages('employee-1', 'chat-2', [
      message,
    ]);
    await DtrAssistantSessionStorage.saveConversationId('employee-2', 'chat-3');
    await DtrAssistantSessionStorage.saveMessages('employee-2', 'chat-3', [
      message,
    ]);

    await DtrAssistantSessionStorage.clearAllForUser('employee-1');
    final secureValues = await secureStorage.readAll();

    expect(secureValues.keys.any((key) => key.contains('employee-1')), isFalse);
    expect(secureValues.keys.any((key) => key.contains('employee-2')), isTrue);
  });

  test('deletes expired encrypted history', () async {
    final expiredAt = DateTime.now()
        .toUtc()
        .subtract(DtrAssistantSessionStorage.historyRetention)
        .subtract(const Duration(minutes: 1));
    await secureStorage.write(
      key: 'dtr_assistant_chat_employee-1_chat-old',
      value: jsonEncode({
        'savedAt': expiredAt.toIso8601String(),
        'messages': [
          {
            'role': 'user',
            'content': 'Expired private message',
            'createdAt': expiredAt.toIso8601String(),
          },
        ],
      }),
    );

    final restored = await DtrAssistantSessionStorage.loadMessages(
      'employee-1',
      'chat-old',
    );

    expect(restored, isEmpty);
    expect(
      await secureStorage.read(key: 'dtr_assistant_chat_employee-1_chat-old'),
      isNull,
    );
  });

  test(
    'removes legacy plaintext assistant keys without restoring them',
    () async {
      SharedPreferences.setMockInitialValues({
        'dtr_assistant_conversation_employee-1': 'legacy-chat',
        'dtr_assistant_chat_employee-1': '[{"role":"user","content":"secret"}]',
        'dtr_assistant_chat_employee-1_legacy-chat':
            '[{"role":"user","content":"secret"}]',
      });

      final conversationId =
          await DtrAssistantSessionStorage.loadOrCreateConversationId(
            'employee-1',
          );
      final preferences = await SharedPreferences.getInstance();

      expect(conversationId, isNot('legacy-chat'));
      expect(
        preferences.getKeys().where((key) => key.startsWith('dtr_assistant_')),
        isEmpty,
      );
    },
  );
}
