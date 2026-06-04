import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';

class ChatService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final _uuid = const Uuid();

  ChatService._internal() {
    print("🔥 ChatService Initialized");
  }

  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  // Groq API Configuration
  static const String _groqApiKey = '';
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  /// Sends a message directly to Groq.
  Future<ChatMessage> sendMessage(String text, {List<ChatMessage>? history}) async {
    try {
      if (_groqApiKey.isEmpty || _groqApiKey.startsWith("YOUR")) {
        return _getStubResponse("Please provide your Groq API Key in `chat_service.dart` to enable real responses.");
      }

      final List<Map<String, String>> messages = [
        {'role': 'system', 'content': 'You are ChatKit AI, a premium and helpful assistant. Keep responses helpful and formatted with markdown.'},
      ];

      // Add history if available
      if (history != null) {
        for (var msg in history.take(10)) {
          messages.add({
            "role": msg.role == MessageRole.user ? "user" : "assistant",
            "content": msg.content
          });
        }
      }

      // Add current message
      messages.add({"role": "user", "content": text});

      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "model": _groqModel,
          "messages": messages,
          "max_tokens": 1024,
          "temperature": 0.7,
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
        return _getStubResponse("Groq API Error: ${response.statusCode}");
      }
    } catch (e) {
      return _getStubResponse("Connection Error: $e");
    }
  }

  /// Generates an image using Pollinations.ai with enhanced parameters.
  Future<String> generateImage(String prompt) async {
    try {
      final encodedPrompt = Uri.encodeComponent(prompt);
      final seed = DateTime.now().millisecondsSinceEpoch;
      final imageUrl = "https://image.pollinations.ai/prompt/$encodedPrompt?width=1024&height=1024&nologo=true&seed=$seed";

      return imageUrl;
    } catch (e) {
      print("Image generation failed: $e");
      throw Exception('Failed to generate image. Please try again.');
    }
  }

  /// Creates or gets a session in Realtime Database.
  Future<String> createOrGetSession(String userId, {String? currentSessionId}) async {
    if (currentSessionId != null && currentSessionId.isNotEmpty) {
      return currentSessionId;
    }

    final sessionId = _uuid.v4();
    final sessionRef = _db.ref('users/$userId/chat_sessions/$sessionId');

    await sessionRef.set({
      'sessionId': sessionId,
      'title': 'New Chat',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });

    return sessionId;
  }

  /// Saves a message to Realtime Database.
  Future<void> saveMessage(String userId, String sessionId, ChatMessage message) async {
    try {
      final messageRef = _db.ref('chat_messages/$sessionId/${message.id}');
      await messageRef.set(message.toJson());

      // Update session timestamp
      await _db.ref('users/$userId/chat_sessions/$sessionId').update({
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print("RTDB Save Error: $e");
    }
  }

  /// Loads messages for a specific session.
  Future<List<ChatMessage>> loadMessages(String sessionId) async {
    try {
      final snapshot = await _db.ref('chat_messages/$sessionId').get();
      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final list = data.values.map((v) => ChatMessage.fromJson(Map<String, dynamic>.from(v as Map))).toList();
      
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (e) {
      print("RTDB Load Messages Error: $e");
      return [];
    }
  }

  /// Generates a smart title for the session
  Future<void> updateSessionTitle(String userId, String sessionId, String content) async {
    if (_groqApiKey.isEmpty || _groqApiKey.startsWith("YOUR")) return;
    try {
      if (content.isEmpty) return;

      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "model": _groqModel,
          "messages": [
            {"role": "system", "content": "Summarize the user request into a 3-5 word title. Return ONLY the title text."},
            {"role": "user", "content": content}
          ],
          "max_tokens": 15,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final title = data['choices'][0]['message']['content'].toString().replaceAll('"', '').trim();
        if (title.isNotEmpty) {
          await _db.ref('users/$userId/chat_sessions/$sessionId').update({'title': title});
        }
      }
    } catch (e) {
      print("Title update failed: $e");
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

  /// Lists all previous sessions for a user.
  Future<List<ChatSession>> listSessions(String userId) async {
    try {
      final snapshot = await _db.ref('users/$userId/chat_sessions').get();
      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return data.entries.map((e) {
        final val = Map<String, dynamic>.from(e.value as Map);
        
        DateTime updatedAt;
        if (val['updatedAt'] is int) {
          updatedAt = DateTime.fromMillisecondsSinceEpoch(val['updatedAt']);
        } else if (val['updatedAt'] is String) {
          updatedAt = DateTime.tryParse(val['updatedAt']) ?? DateTime.now();
        } else {
          updatedAt = DateTime.now();
        }

        return ChatSession(
          id: e.key,
          displayTitle: val['title'] ?? 'Untitled',
          lastUpdated: updatedAt,
        );
      }).toList()..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    } catch (e) {
      print("RTDB List Sessions Error: $e");
      return [];
    }
  }

  /// Deletes a specific session.
  Future<void> deleteSession(String userId, String id) async {
    await _db.ref('users/$userId/chat_sessions/$id').remove();
    await _db.ref('chat_messages/$id').remove();
  }

  /// Clears walkthrough/history for a user.
  Future<void> clearAllHistory(String userId) async {
    final snapshot = await _db.ref('users/$userId/chat_sessions').get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      for (var id in data.keys) {
        await _db.ref('chat_messages/$id').remove();
      }
    }
    await _db.ref('users/$userId/chat_sessions').remove();
  }
}
