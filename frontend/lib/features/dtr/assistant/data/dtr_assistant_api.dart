import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';

class DtrAssistantApi {
  DtrAssistantApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<DtrAssistantMessage> sendMessage(
    String message, {
    String? intent,
    String? modelProfile,
    CancelToken? cancelToken,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/dtr-assistant/chat',
      data: {
        'message': message,
        if (intent != null) 'intent': intent,
        if (modelProfile != null) 'modelProfile': modelProfile,
      },
      cancelToken: cancelToken,
      // Ollama can take up to 90s to generate a free-form answer locally.
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    final data = res.data ?? <String, dynamic>{};
    final messageJson = data['message'];
    if (messageJson is Map<String, dynamic>) {
      return DtrAssistantMessage.fromJson(messageJson);
    }
    if (messageJson is Map) {
      return DtrAssistantMessage.fromJson(
        Map<String, dynamic>.from(messageJson),
      );
    }
    throw Exception('Assistant returned an invalid response.');
  }

  Future<void> resetChat() async {
    await _client.post<Map<String, dynamic>>('/api/dtr-assistant/reset');
  }

  Future<({String defaultModelProfile, List<DtrAssistantModelProfile> models})>
  fetchModels() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/dtr-assistant/models',
    );
    final data = res.data ?? <String, dynamic>{};
    final rawModels = data['models'];
    final models = rawModels is List
        ? rawModels
              .whereType<Map>()
              .map(
                (item) => DtrAssistantModelProfile.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.id.isNotEmpty && item.label.isNotEmpty)
              .toList(growable: false)
        : const <DtrAssistantModelProfile>[];
    return (
      defaultModelProfile:
          data['defaultModelProfile']?.toString() ?? 'tools_ollama',
      models: models,
    );
  }

  Future<Uint8List> downloadAttachment(
    DtrAssistantAttachment attachment,
  ) async {
    if (attachment.contentBase64.isNotEmpty) {
      return Uint8List.fromList(base64Decode(attachment.contentBase64));
    }
    if (attachment.downloadUrl.isEmpty) {
      return Uint8List.fromList([]);
    }
    final res = await _client.get<List<int>>(
      attachment.downloadUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }

  Future<void> submitFeedback({
    required DtrAssistantMessage message,
    required String rating,
    required String modelProfile,
    String? promptPreview,
    String? comment,
  }) async {
    final id = message.id;
    if (id == null || id.isEmpty) return;
    await _client.post<Map<String, dynamic>>(
      '/api/dtr-assistant/feedback',
      data: {
        'messageId': id,
        'rating': rating,
        'intent': message.intent,
        'provider': message.provider,
        'model': message.model,
        'modelProfile': message.modelProfile ?? modelProfile,
        'promptPreview': promptPreview ?? message.promptPreview,
        'intentConfidence': message.intentConfidence,
        'intentSource': message.intentSource,
        'contentPreview': message.content,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
    );
  }
}
