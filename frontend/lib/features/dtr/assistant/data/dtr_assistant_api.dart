import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';

class DtrAssistantApi {
  DtrAssistantApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<DtrAssistantMessage> sendMessage(
    String message, {
    String? intent,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/dtr-assistant/chat',
      data: {'message': message, if (intent != null) 'intent': intent},
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
}
