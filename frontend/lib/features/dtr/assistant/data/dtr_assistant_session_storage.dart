import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DtrAssistantSessionStorage {
  DtrAssistantSessionStorage._();

  /// Assistant history is local-only and expires even if the user stays signed in.
  static const historyRetention = Duration(days: 30);
  static const _storageTimeout = Duration(seconds: 5);

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // ignore: deprecated_member_use
      encryptedSharedPreferences: false,
      resetOnError: true,
    ),
  );

  static String _conversationKey(String userId) =>
      'dtr_assistant_conversation_$userId';

  static String _storagePrefix(String userId) =>
      'dtr_assistant_chat_${userId}_';

  static String _storageKey(String userId, String conversationId) =>
      '${_storagePrefix(userId)}$conversationId';

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
    await _removeLegacyPlaintext(userId);
    final stored = (await _safeRead(_conversationKey(userId)))?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final created = createConversationId();
    await _safeWrite(_conversationKey(userId), created);
    return created;
  }

  static Future<void> saveConversationId(
    String userId,
    String conversationId,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return;
    await _removeLegacyPlaintext(userId);
    await _safeWrite(_conversationKey(userId), conversationId.trim());
  }

  static Future<List<DtrAssistantMessage>> loadMessages(
    String userId,
    String conversationId,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return const [];
    await _removeLegacyPlaintext(userId);
    final key = _storageKey(userId, conversationId);
    final raw = await _safeRead(key);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _safeDelete(key);
        return const [];
      }
      final payload = Map<String, dynamic>.from(decoded);
      final savedAt = DateTime.tryParse(payload['savedAt']?.toString() ?? '');
      final rawMessages = payload['messages'];
      if (savedAt == null ||
          rawMessages is! List ||
          DateTime.now().toUtc().difference(savedAt.toUtc()) >
              historyRetention) {
        await _safeDelete(key);
        return const [];
      }
      return rawMessages
          .whereType<Map>()
          .map(
            (item) =>
                DtrAssistantMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.content.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      await _safeDelete(key);
      return const [];
    }
  }

  static Future<void> saveMessages(
    String userId,
    String conversationId,
    List<DtrAssistantMessage> messages,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return;
    await _removeLegacyPlaintext(userId);
    final payload = jsonEncode({
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'messages': messages.map((item) => item.toJson()).toList(),
    });
    await _safeWrite(_storageKey(userId, conversationId), payload);
  }

  static Future<void> clearMessages(
    String userId,
    String conversationId,
  ) async {
    if (userId.trim().isEmpty || conversationId.trim().isEmpty) return;
    await _safeDelete(_storageKey(userId, conversationId));
    await _removeLegacyPlaintext(userId);
  }

  /// Removes every assistant conversation and pointer owned by [userId].
  static Future<void> clearAllForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    final activeConversationId = (await _safeRead(
      _conversationKey(normalizedUserId),
    ))?.trim();
    final allValues = await _safeReadAll();
    final keys = allValues.keys.where(
      (key) =>
          key == _conversationKey(normalizedUserId) ||
          key == _legacyStorageKey(normalizedUserId) ||
          key.startsWith(_storagePrefix(normalizedUserId)),
    );
    await Future.wait(keys.map(_safeDelete));
    if (activeConversationId != null && activeConversationId.isNotEmpty) {
      await _safeDelete(_storageKey(normalizedUserId, activeConversationId));
    }
    await _safeDelete(_conversationKey(normalizedUserId));
    await _removeLegacyPlaintext(normalizedUserId);
  }

  static Future<void> _removeLegacyPlaintext(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (key) =>
          key == _conversationKey(userId) ||
          key == _legacyStorageKey(userId) ||
          key.startsWith(_storagePrefix(userId)),
    );
    await Future.wait(keys.map(prefs.remove));
  }

  static Future<String?> _safeRead(String key) async {
    try {
      return await _secureStorage.read(key: key).timeout(_storageTimeout);
    } catch (error) {
      debugPrint('[DtrAssistantSessionStorage] read failed: $error');
      return null;
    }
  }

  static Future<Map<String, String>> _safeReadAll() async {
    try {
      return await _secureStorage.readAll().timeout(_storageTimeout);
    } catch (error) {
      debugPrint('[DtrAssistantSessionStorage] readAll failed: $error');
      return const {};
    }
  }

  static Future<void> _safeWrite(String key, String value) async {
    try {
      await _secureStorage
          .write(key: key, value: value)
          .timeout(_storageTimeout);
    } catch (error) {
      debugPrint('[DtrAssistantSessionStorage] write failed: $error');
    }
  }

  static Future<void> _safeDelete(String key) async {
    try {
      await _secureStorage.delete(key: key).timeout(_storageTimeout);
    } catch (error) {
      debugPrint('[DtrAssistantSessionStorage] delete failed: $error');
    }
  }
}
