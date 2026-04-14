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
    print("🔥 Switching to Realtime Database Flow");
  }

  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  // Groq API Configuration
  static const String _groqApiKey = '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';
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  /// Sends a message and saves to Realtime Database.
  Future<ChatMessage> sendMessage(String text, {List<ChatMessage>? history, String? sessionId, String? userId}) async {
    try {
      final List<Map<String, String>> requestMessages = [
        {'role': 'system', 'content': 'You are ChatKit AI, a premium and helpful assistant.'},
      ];

      if (history != null) {
        for (var msg in history.take(10)) {
          requestMessages.add({
            'role': msg.role == MessageRole.user ? 'user' : 'assistant',
            'content': msg.content,
          });
        }
      }
      requestMessages.add({'role': 'user', 'content': text});

      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _groqModel,
          'messages': requestMessages,
          'max_tokens': 1024,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Groq API Error: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final String aiResponse = data['choices'][0]['message']['content'];

      final assistantMessage = ChatMessage(
        id: _uuid.v4(),
        content: aiResponse,
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );

      // Save to RTDB
      if (sessionId != null && userId != null) {
        await _saveToRTDB(userId, sessionId, text, aiResponse);
      }

      return assistantMessage;
    } catch (e) {
      return ChatMessage(
        id: _uuid.v4(),
        content: "Error: $e",
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );
    }
  }

  /// Generates a short title for the chat based on the conversation context.
  Future<String> _generateSmartTitle(String userMsg, String aiMsg) async {
    try {
      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _groqModel,
          'messages': [
            {'role': 'system', 'content': 'Summarize the following user request into a 3-5 word catchy title. Return ONLY the title text.'},
            {'role': 'user', 'content': userMsg},
          ],
          'max_tokens': 15,
          'temperature': 0.5,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String title = data['choices'][0]['message']['content'];
        title = title.replaceAll('"', '').trim();
        return title.isNotEmpty ? title : (userMsg.length > 30 ? "${userMsg.substring(0, 30)}..." : userMsg);
      }
    } catch (e) {
      print("Title generation failed: $e");
    }
    return userMsg.length > 30 ? "${userMsg.substring(0, 30)}..." : userMsg;
  }

  /// Creates a session in Realtime Database.
  Future<ChatSession> createSession(String title, String userId) async {
    try {
      final sessionRef = _db.ref('users/$userId/chat_sessions').push();
      final sessionId = sessionRef.key!;
      
      await sessionRef.set({
        'title': title,
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

      return ChatSession(
        id: sessionId,
        displayTitle: title,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      print("RTDB Create Session Error: $e");
      return ChatSession(id: _uuid.v4(), displayTitle: 'Untitled', lastUpdated: DateTime.now());
    }
  }

  /// Lists all chat sessions for a user.
  Future<List<ChatSession>> listSessions(String userId) async {
    try {
      final snapshot = await _db.ref('users/$userId/chat_sessions').get();
      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return data.entries.map((e) {
        final val = Map<String, dynamic>.from(e.value as Map);
        return ChatSession(
          id: e.key,
          displayTitle: (val['title'] == null || val['title'] == '') 
              ? 'Untitled' 
              : val['title'],
          lastUpdated: DateTime.fromMillisecondsSinceEpoch(val['updatedAt'] ?? 0),
        );
      }).toList()..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    } catch (e) {
      print("RTDB List Sessions Error: $e");
      return [];
    }
  }

  /// Loads all messages for a specific session.
  Future<List<ChatMessage>> loadMessages(String sessionId) async {
    try {
      final snapshot = await _db.ref('chat_messages/$sessionId').get();
      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return data.entries.map((e) {
        final val = Map<String, dynamic>.from(e.value as Map);
        return ChatMessage(
          id: e.key,
          content: val['content'] ?? '',
          role: val['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
          createdAt: DateTime.fromMillisecondsSinceEpoch(val['createdAt'] ?? 0),
        );
      }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (e) {
      print("RTDB Load Messages Error: $e");
      return [];
    }
  }

  /// Saves user and bot messages to Realtime Database.
  Future<void> _saveToRTDB(String userId, String sessionId, String userMsg, String aiMsg) async {
    try {
      final messagesRef = _db.ref('chat_messages/$sessionId');
      
      // Push User Message
      await messagesRef.push().set({
        'role': 'user',
        'content': userMsg,
        'createdAt': ServerValue.timestamp,
      });

      // Push AI Message
      await messagesRef.push().set({
        'role': 'assistant',
        'content': aiMsg,
        'createdAt': ServerValue.timestamp,
      });

      // Update session timestamp and potentially the title if it's the first message
      final sessionRef = _db.ref('users/$userId/chat_sessions/$sessionId');
      final sessionSnap = await sessionRef.get();
      
      Map<String, dynamic> updates = {
        'updatedAt': ServerValue.timestamp,
      };

      if (sessionSnap.exists) {
        final sessionData = Map<String, dynamic>.from(sessionSnap.value as Map);
        final currentTitle = sessionData['title'] ?? '';
        
        // If it's a new chat, generate a smart title based on the chat content
        if (currentTitle == 'New Chat' || currentTitle == '' || currentTitle == 'Untitled') {
          updates['title'] = await _generateSmartTitle(userMsg, aiMsg);
        }
      } else {
        updates['title'] = await _generateSmartTitle(userMsg, aiMsg);
      }

      await sessionRef.update(updates);
      print("✅ Chat saved and smart title updated!");
    } catch (e) {
      print("❌ RTDB Maintenance Error: $e");
    }
  }

  Future<void> deleteSession(String userId, String sessionId) async {
    await _db.ref('users/$userId/chat_sessions/$sessionId').remove();
    await _db.ref('chat_messages/$sessionId').remove();
  }

  Future<void> clearAllHistory(String userId) async {
    // 1. Get all session IDs to delete messages
    final snapshot = await _db.ref('users/$userId/chat_sessions').get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      for (var id in data.keys) {
        await _db.ref('chat_messages/$id').remove();
      }
    }
    // 2. Clear all sessions
    await _db.ref('users/$userId/chat_sessions').remove();
  }
}
