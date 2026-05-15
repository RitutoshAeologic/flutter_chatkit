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

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'role': role.name,
        'createdAt': createdAt.toIso8601String(),
        'isLoading': isLoading,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        content: json['content'] as String,
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => MessageRole.user,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isLoading: json['isLoading'] as bool? ?? false,
      );
}
