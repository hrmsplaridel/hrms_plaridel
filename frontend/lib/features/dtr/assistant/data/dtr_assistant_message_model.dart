class DtrAssistantMessage {
  const DtrAssistantMessage({
    this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.intent,
    this.intentConfidence,
    this.intentSource,
    this.provider,
    this.model,
    this.modelProfile,
    this.promptPreview,
    this.suggestions = const <DtrAssistantSuggestion>[],
    this.attachments = const <DtrAssistantAttachment>[],
    this.actions = const <DtrAssistantAction>[],
  });

  final String? id;
  final String role;
  final String content;
  final DateTime createdAt;
  final String? intent;
  final double? intentConfidence;
  final String? intentSource;
  final String? provider;
  final String? model;
  final String? modelProfile;
  final String? promptPreview;
  final List<DtrAssistantSuggestion> suggestions;
  final List<DtrAssistantAttachment> attachments;
  final List<DtrAssistantAction> actions;

  bool get isUser => role == 'user';

  factory DtrAssistantMessage.user(String content) {
    return DtrAssistantMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
      suggestions: const <DtrAssistantSuggestion>[],
      attachments: const <DtrAssistantAttachment>[],
      actions: const <DtrAssistantAction>[],
    );
  }

  factory DtrAssistantMessage.fromJson(Map<String, dynamic> json) {
    final rawSuggestions = json['suggestions'];
    final rawAttachments = json['attachments'];
    final rawActions = json['actions'];
    return DtrAssistantMessage(
      id: json['id']?.toString(),
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      intent: json['intent']?.toString(),
      intentConfidence: _doubleOrNull(json['intentConfidence']),
      intentSource: json['intentSource']?.toString(),
      provider: json['provider']?.toString(),
      model: json['model']?.toString(),
      modelProfile: json['modelProfile']?.toString(),
      promptPreview: json['promptPreview']?.toString(),
      suggestions: rawSuggestions is List
          ? rawSuggestions
                .whereType<Map>()
                .map(
                  (item) => DtrAssistantSuggestion.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.text.isNotEmpty)
                .toList(growable: false)
          : const <DtrAssistantSuggestion>[],
      attachments: rawAttachments is List
          ? rawAttachments
                .whereType<Map>()
                .map(
                  (item) => DtrAssistantAttachment.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where(
                  (item) =>
                      item.filename.isNotEmpty &&
                      (item.contentBase64.isNotEmpty ||
                          item.downloadUrl.isNotEmpty),
                )
                .toList(growable: false)
          : const <DtrAssistantAttachment>[],
      actions: rawActions is List
          ? rawActions
                .whereType<Map>()
                .map(
                  (item) => DtrAssistantAction.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.label.isNotEmpty && item.type.isNotEmpty)
                .toList(growable: false)
          : const <DtrAssistantAction>[],
    );
  }
}

double? _doubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class DtrAssistantAction {
  const DtrAssistantAction({
    required this.id,
    required this.label,
    required this.type,
    this.icon,
    this.intent,
    this.prompt,
    this.payload = const <String, dynamic>{},
    this.autoExecute = false,
  });

  final String id;
  final String label;
  final String type;
  final String? icon;
  final String? intent;
  final String? prompt;
  final Map<String, dynamic> payload;
  final bool autoExecute;

  factory DtrAssistantAction.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return DtrAssistantAction(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      icon: json['icon']?.toString(),
      intent: json['intent']?.toString(),
      prompt: json['prompt']?.toString(),
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      autoExecute: json['autoExecute'] == true,
    );
  }
}

class DtrAssistantAttachment {
  const DtrAssistantAttachment({
    required this.filename,
    required this.mimeType,
    this.contentBase64 = '',
    this.downloadUrl = '',
    this.id,
    this.kind,
    this.expiresAt,
    this.encoding = 'base64',
  });

  final String? id;
  final String filename;
  final String mimeType;
  final String encoding;
  final String contentBase64;
  final String downloadUrl;
  final String? kind;
  final DateTime? expiresAt;

  factory DtrAssistantAttachment.fromJson(Map<String, dynamic> json) {
    return DtrAssistantAttachment(
      id: json['id']?.toString(),
      filename: json['filename']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      encoding: json['encoding']?.toString() ?? 'base64',
      contentBase64: json['contentBase64']?.toString() ?? '',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      kind: json['kind']?.toString(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    );
  }
}

class DtrAssistantSuggestion {
  const DtrAssistantSuggestion({required this.text, this.intent});

  final String text;
  final String? intent;

  factory DtrAssistantSuggestion.fromJson(Map<String, dynamic> json) {
    return DtrAssistantSuggestion(
      text: json['text']?.toString() ?? '',
      intent: json['intent']?.toString(),
    );
  }
}

class DtrAssistantModelProfile {
  const DtrAssistantModelProfile({
    required this.id,
    required this.label,
    required this.engine,
    required this.provider,
    required this.model,
    this.description,
    this.available = true,
    this.recommended = false,
    this.unavailableReason,
  });

  final String id;
  final String label;
  final String engine;
  final String provider;
  final String model;
  final String? description;
  final bool available;
  final bool recommended;
  final String? unavailableReason;

  factory DtrAssistantModelProfile.fromJson(Map<String, dynamic> json) {
    return DtrAssistantModelProfile(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      engine: json['engine']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      description: json['description']?.toString(),
      available: json['available'] != false,
      recommended: json['recommended'] == true,
      unavailableReason: json['unavailableReason']?.toString(),
    );
  }
}
