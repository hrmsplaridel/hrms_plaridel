class DtrAssistantMessage {
  const DtrAssistantMessage({
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String role;
  final String content;
  final DateTime createdAt;

  bool get isUser => role == 'user';

  factory DtrAssistantMessage.user(String content) {
    return DtrAssistantMessage(
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
    );
  }

  factory DtrAssistantMessage.fromJson(Map<String, dynamic> json) {
    return DtrAssistantMessage(
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
