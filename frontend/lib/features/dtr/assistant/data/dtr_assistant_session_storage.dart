import 'dart:convert';
import 'dart:math';

import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DtrAssistantSessionStorage {
  DtrAssistantSessionStorage._();

  static String _conversationKey(String userId) =>
      'dtr_assistant_conversation_$userId';

  static String _storageKey(String userId, String conversationId) =>
      'dtr_assistant_chat_${userId}_$conversationId';

  static String _legacyStorageKey(String userId) =>
      'dtr_assistant_chat_$userId';

  static String createConversationId() {
    final random = Random.secure();
    final suffix = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'chat_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  static Future<String> loadOrCreateConversationId(String userId) async {
    if (userId.trim().isEmpty) return createConversationId();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_conversationKey(userId))?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final created = createConversationId();
    await prefs.setString(_conversationKey(userId), created);
    return created;
  }

  static Future<void> saveConversationId(
    String userId,
    String conversationId,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_conversationKey(userId), conversationId.trim());
  }

  static Future<List<DtrAssistantMessage>> loadMessages(
    String userId,
    String conversationId,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKey(userId, conversationId);
    final raw =
        prefs.getString(key) ?? prefs.getString(_legacyStorageKey(userId));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final messages = decoded
          .whereType<Map>()
          .map(
            (item) =>
                DtrAssistantMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.content.trim().isNotEmpty)
          .toList(growable: false);
      if (!prefs.containsKey(key)) {
        await prefs.setString(key, raw);
        await prefs.remove(_legacyStorageKey(userId));
      }
      return messages;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveMessages(
    String userId,
    String conversationId,
    List<DtrAssistantMessage> messages,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(messages.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKey(userId, conversationId), payload);
  }

  static Future<void> clearMessages(
    String userId,
    String conversationId,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(userId, conversationId));
    await prefs.remove(_legacyStorageKey(userId));
  }
}
