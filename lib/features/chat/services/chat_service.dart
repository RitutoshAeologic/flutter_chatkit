import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';

class ChatException implements Exception {
  final String message;
  ChatException(this.message);
}

class ChatService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<List<ChatSession>> loadSessions() async {
    try {
      final callable = _functions.httpsCallable('listSessions');
      final result = await callable();
      final data = result.data as List<dynamic>?;
      if (data == null) return [];
      
      return data.map((json) {
        return ChatSession(
          id: json['id'] as String,
          displayTitle: json['displayTitle'] as String,
          messageCount: json['messageCount'] as int,
        );
      }).toList();
    } catch (e) {
      throw ChatException('Failed to load sessions');
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      final callable = _functions.httpsCallable('deleteSession');
      await callable({'id': id});
    } catch (e) {
      throw ChatException('Failed to delete session');
    }
  }

  Future<ChatMessage> sendMessage({
    required String message,
    required String sessionId,
    required String systemPrompt,
    required double temperature,
    required int maxTokens,
  }) async {
    try {
      final callable = _functions.httpsCallable('chat');
      final result = await callable({
        'message': message,
        'sessionId': sessionId,
        'systemPrompt': systemPrompt,
        'temperature': temperature,
        'maxTokens': maxTokens,
      });

      final data = result.data as Map<String, dynamic>;
      
      return ChatMessage(
        id: const Uuid().v4(),
        content: data['reply'] as String,
        role: MessageRole.assistant,
        sessionId: sessionId,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );
    } catch (e) {
      throw ChatException('Failed to send message: ${e.toString()}');
    }
  }
}
