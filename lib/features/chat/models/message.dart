enum MessageRole { user, assistant }

class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime createdAt;
  final bool isLoading;

  ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
    this.isLoading = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isLoading: json['isLoading'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'role': role == MessageRole.user ? 'user' : 'assistant',
      'createdAt': createdAt.toIso8601String(),
      'isLoading': isLoading,
    };
  }
}
