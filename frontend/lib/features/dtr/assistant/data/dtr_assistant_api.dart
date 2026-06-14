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
}
