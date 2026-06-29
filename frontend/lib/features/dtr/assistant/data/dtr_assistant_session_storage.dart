import 'dart:convert';

import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DtrAssistantSessionStorage {
  DtrAssistantSessionStorage._();

  static String _storageKey(String userId) => 'dtr_assistant_chat_$userId';

  static Future<List<DtrAssistantMessage>> loadMessages(String userId) async {
    if (userId.trim().isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(userId));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DtrAssistantMessage.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.content.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveMessages(
    String userId,
    List<DtrAssistantMessage> messages,
  ) async {
    if (userId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(messages.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKey(userId), payload);
  }

  static Future<void> clearMessages(String userId) async {
    if (userId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(userId));
  }
}
