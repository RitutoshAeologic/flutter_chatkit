enum MessageRole { user, assistant }

enum MessageType { text, image }

class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime createdAt;
  final bool isLoading;
  final MessageType type;
  final String? imageUrl;

  ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
    this.isLoading = false,
    this.type = MessageType.text,
    this.imageUrl,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now(),
      isLoading: json['isLoading'] as bool? ?? false,
      type: json['type'] == 'image' ? MessageType.image : MessageType.text,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'role': role == MessageRole.user ? 'user' : 'assistant',
      'createdAt': createdAt.toIso8601String(),
      'isLoading': isLoading,
      'type': type == MessageType.image ? 'image' : 'text',
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }
}
