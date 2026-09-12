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
    this.feedbackToken,
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
  final String? feedbackToken;
  final List<DtrAssistantSuggestion> suggestions;
  final List<DtrAssistantAttachment> attachments;
  final List<DtrAssistantAction> actions;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() {
    final safeActions = actions
        .where((item) => item.isSafeForSession)
        .map((item) => item.toSessionJson())
        .toList(growable: true);
    final expiredAttachments = attachments
        .where((item) => item.filename.isNotEmpty)
        .map((item) => item.toExpiredSessionJson())
        .toList(growable: false);

    if (expiredAttachments.isNotEmpty &&
        !safeActions.any((item) => item['id'] == 'regenerate_dtr_export')) {
      safeActions.insert(
        0,
        DtrAssistantAction(
          id: 'regenerate_dtr_export',
          label: 'Regenerate DTR export',
          type: 'send_prompt',
          icon: 'file_download',
          intent: 'dtr_export_guidance',
          prompt: _regenerateExportPrompt(attachments.first.filename),
        ).toSessionJson(),
      );
    }

    return {
      if (id != null) 'id': id,
      'role': role,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      if (intent != null) 'intent': intent,
      if (intentConfidence != null) 'intentConfidence': intentConfidence,
      if (intentSource != null) 'intentSource': intentSource,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (modelProfile != null) 'modelProfile': modelProfile,
      if (promptPreview != null) 'promptPreview': promptPreview,
      if (feedbackToken != null) 'feedbackToken': feedbackToken,
      if (suggestions.isNotEmpty)
        'suggestions': suggestions.map((item) => item.toJson()).toList(),
      if (expiredAttachments.isNotEmpty) 'attachments': expiredAttachments,
      if (safeActions.isNotEmpty) 'actions': safeActions,
    };
  }

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
      feedbackToken: json['feedbackToken']?.toString(),
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
                      (item.isExpired ||
                          item.contentBase64.isNotEmpty ||
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

  bool get isSafeForSession => const <String>{
    'send_prompt',
    'open_leave_form',
    'open_leave_page',
    'open_locator_form',
    'open_locator_page',
    'open_dtr_time_logs',
    'open_dtr_reports',
  }.contains(type);

  Map<String, dynamic> toSessionJson() {
    return {
      'id': id,
      'label': label,
      'type': type,
      if (icon != null) 'icon': icon,
      if (intent != null) 'intent': intent,
      if (prompt != null) 'prompt': prompt,
      if (payload.isNotEmpty) 'payload': payload,
      // Restoring history must never trigger navigation automatically.
      'autoExecute': false,
    };
  }

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
    this.expired = false,
  });

  final String? id;
  final String filename;
  final String mimeType;
  final String encoding;
  final String contentBase64;
  final String downloadUrl;
  final String? kind;
  final DateTime? expiresAt;
  final bool expired;

  bool get isExpired =>
      expired ||
      (expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc()));

  Map<String, dynamic> toExpiredSessionJson() {
    return {
      'filename': filename,
      'mimeType': mimeType,
      if (kind != null) 'kind': kind,
      if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
      'expired': true,
    };
  }

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
      expired: json['expired'] == true,
    );
  }
}

class DtrAssistantSuggestion {
  const DtrAssistantSuggestion({required this.text, this.intent});

  final String text;
  final String? intent;

  Map<String, dynamic> toJson() {
    return {'text': text, if (intent != null) 'intent': intent};
  }

  factory DtrAssistantSuggestion.fromJson(Map<String, dynamic> json) {
    return DtrAssistantSuggestion(
      text: json['text']?.toString() ?? '',
      intent: json['intent']?.toString(),
    );
  }
}

String _regenerateExportPrompt(String filename) {
  final match = RegExp(
    r'dtr_export_(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})\.',
  ).firstMatch(filename);
  if (match == null) return 'Generate my DTR export again.';
  final startDate = match.group(1);
  final endDate = match.group(2);
  if (startDate == endDate) {
    return 'Generate my DTR export for $startDate.';
  }
  return 'Generate my DTR export from $startDate to $endDate.';
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
    this.external = false,
    this.requiresConsent = false,
    this.consentVersion,
    this.dataDisclosure,
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
  final bool external;
  final bool requiresConsent;
  final String? consentVersion;
  final String? dataDisclosure;

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
      external: json['external'] == true,
      requiresConsent: json['requiresConsent'] == true,
      consentVersion: json['consentVersion']?.toString(),
      dataDisclosure: json['dataDisclosure']?.toString(),
    );
  }
}
