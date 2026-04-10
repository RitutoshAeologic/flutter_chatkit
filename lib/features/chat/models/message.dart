enum MessageRole { user, assistant }
enum MessageStatus { sending, sent, failed }

class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final String sessionId;
  final DateTime timestamp;
  final MessageStatus status;
  final String? errorMessage;

  ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.sessionId,
    required this.timestamp,
    required this.status,
    this.errorMessage,
  });

  ChatMessage copyWith({
    String? id,
    String? content,
    MessageRole? role,
    String? sessionId,
    DateTime? timestamp,
    MessageStatus? status,
    String? errorMessage,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      role: role ?? this.role,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
