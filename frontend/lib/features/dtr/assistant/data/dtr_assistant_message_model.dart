class DtrAssistantMessage {
  const DtrAssistantMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.suggestions = const <DtrAssistantSuggestion>[],
    this.attachments = const <DtrAssistantAttachment>[],
  });

  final String role;
  final String content;
  final DateTime createdAt;
  final List<DtrAssistantSuggestion> suggestions;
  final List<DtrAssistantAttachment> attachments;

  bool get isUser => role == 'user';

  factory DtrAssistantMessage.user(String content) {
    return DtrAssistantMessage(
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
      suggestions: const <DtrAssistantSuggestion>[],
      attachments: const <DtrAssistantAttachment>[],
    );
  }

  factory DtrAssistantMessage.fromJson(Map<String, dynamic> json) {
    final rawSuggestions = json['suggestions'];
    final rawAttachments = json['attachments'];
    return DtrAssistantMessage(
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
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
                      item.filename.isNotEmpty && item.contentBase64.isNotEmpty,
                )
                .toList(growable: false)
          : const <DtrAssistantAttachment>[],
    );
  }
}

class DtrAssistantAttachment {
  const DtrAssistantAttachment({
    required this.filename,
    required this.mimeType,
    required this.contentBase64,
    this.encoding = 'base64',
  });

  final String filename;
  final String mimeType;
  final String encoding;
  final String contentBase64;

  factory DtrAssistantAttachment.fromJson(Map<String, dynamic> json) {
    return DtrAssistantAttachment(
      filename: json['filename']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      encoding: json['encoding']?.toString() ?? 'base64',
      contentBase64: json['contentBase64']?.toString() ?? '',
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
