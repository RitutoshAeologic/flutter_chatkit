import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';

class ChatService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final _uuid = const Uuid();

  /// Sends a message to the AI via Firebase Cloud Functions.
  Future<ChatMessage> sendMessage(String text, {List<ChatMessage>? history}) async {
    try {
      final callable = _functions.httpsCallable('askAI');
      
      final result = await callable.call({
        'message': text,
        // Optional: Include history if you update your Cloud Function to handle it
      });

      final String aiResponse = result.data['response'] ?? 'No response';

      return ChatMessage(
        id: _uuid.v4(),
        content: aiResponse,
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );
    } on FirebaseFunctionsException catch (e) {
      return ChatMessage(
        id: _uuid.v4(),
        content: "Error: ${e.message}",
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return ChatMessage(
        id: _uuid.v4(),
        content: "Connection Error: $e",
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );
    }
  }

  /// Creates a new chat session in Firestore via Cloud Functions.
  Future<ChatSession> createSession(String title, String userId) async {
    try {
      final callable = _functions.httpsCallable('createChatSession');
      final result = await callable.call({'userId': userId});
      
      final String sessionId = result.data['sessionId'];

      return ChatSession(
        id: sessionId,
        displayTitle: title,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      return ChatSession(
        id: _uuid.v4(),
        displayTitle: title,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// Lists all previous sessions (Stub for now).
  Future<List<ChatSession>> listSessions() async {
    return [];
  }

  /// Loads messages for a specific session (Stub for now).
  Future<List<ChatMessage>> loadMessages(String sessionId) async {
    return [];
  }

  /// Deletes a session.
  Future<void> deleteSession(String id) async {
    return;
  }
}
