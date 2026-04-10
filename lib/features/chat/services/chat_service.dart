import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/chat_session.dart';
import 'package:uuid/uuid.dart';

class ChatService {
  final _uuid = const Uuid();

  // IMPORTANT: For production, move this to Firebase Cloud Functions.
  // Using direct connection for testing as requested.
  static const String _togetherApiKey = "YOUR_TOGETHER_API_KEY_HERE";
  static const String _togetherModel = "meta-llama/Llama-3.3-70B-Instruct-Turbo";

  /// Sends a message directly to Together AI.
  Future<ChatMessage> sendMessage(String text, {List<ChatMessage>? history}) async {
    try {
      if (_togetherApiKey == "YOUR_TOGETHER_API_KEY_HERE" || _togetherApiKey.isEmpty) {
        return _getStubResponse("Please provide your Together AI API Key in `chat_service.dart` to enable real responses.");
      }

      final List<Map<String, String>> messages = [];
      
      // Add system prompt
      messages.add({
        "role": "system",
        "content": "You are ChatKit AI, a premium, helpful AI assistant built with Flutter. Keep responses helpful and formatted with markdown."
      });

      // Add history if available
      if (history != null) {
        for (var msg in history) {
          messages.add({
            "role": msg.role == MessageRole.user ? "user" : "assistant",
            "content": msg.content
          });
        }
      }

      // Add current message
      messages.add({"role": "user", "content": text});

      final response = await http.post(
        Uri.parse('https://api.together.xyz/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_togetherApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "model": _togetherModel,
          "messages": messages,
          "max_tokens": 1024,
          "temperature": 0.7,
          "top_p": 0.7,
          "top_k": 50,
          "repetition_penalty": 1,
          "stream": false
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        
        return ChatMessage(
          id: _uuid.v4(),
          content: content,
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
        );
      } else {
        return _getStubResponse("API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      return _getStubResponse("Connection Error: $e");
    }
  }

  ChatMessage _getStubResponse(String text) {
    return ChatMessage(
      id: _uuid.v4(),
      content: text,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );
  }

  /// STUB: Creates a new chat session.
  Future<ChatSession> createSession(String title) async {
    return ChatSession(
      id: _uuid.v4(),
      displayTitle: title,
      lastUpdated: DateTime.now(),
    );
  }

  /// STUB: Lists all previous sessions.
  Future<List<ChatSession>> listSessions() async {
    return [];
  }

  /// STUB: Loads messages for a specific session.
  Future<List<ChatMessage>> loadMessages(String sessionId) async {
    return [];
  }

  /// STUB: Deletes a session.
  Future<void> deleteSession(String id) async {
    return;
  }
}
