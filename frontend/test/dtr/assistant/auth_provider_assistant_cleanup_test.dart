import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_session_storage.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'account switching and sign out clear the previous user chat history',
    () async {
      const firstUser = AppUser(
        id: 'employee-auth-1',
        email: 'first.employee@test.local',
        role: 'employee',
      );
      const secondUser = AppUser(
        id: 'employee-auth-2',
        email: 'second.employee@test.local',
        role: 'employee',
      );
      final auth = AuthProvider()..replaceUser(firstUser);
      final message = DtrAssistantMessage(
        role: 'user',
        content: 'Private attendance question',
        createdAt: DateTime.utc(2026, 9, 3),
      );

      await DtrAssistantSessionStorage.saveConversationId(
        firstUser.id,
        'first-chat',
      );
      await DtrAssistantSessionStorage.saveMessages(
        firstUser.id,
        'first-chat',
        [message],
      );
      await DtrAssistantSessionStorage.saveConversationId(
        secondUser.id,
        'second-chat',
      );
      await DtrAssistantSessionStorage.saveMessages(
        secondUser.id,
        'second-chat',
        [message],
      );

      auth.replaceUser(secondUser);
      await _waitForUserHistoryRemoval(secureStorage, firstUser.id);

      var values = await secureStorage.readAll();
      expect(values.keys.any((key) => key.contains(firstUser.id)), isFalse);
      expect(values.keys.any((key) => key.contains(secondUser.id)), isTrue);
      expect(auth.user?.id, secondUser.id);

      await auth.signOut();

      values = await secureStorage.readAll();
      expect(values.keys.any((key) => key.contains(secondUser.id)), isFalse);
      expect(auth.user, isNull);
    },
  );
}

Future<void> _waitForUserHistoryRemoval(
  FlutterSecureStorage storage,
  String userId,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    final values = await storage.readAll();
    if (!values.keys.any((key) => key.contains(userId))) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Assistant history for $userId was not cleared.');
}
