import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../features/chat/models/message.dart';

/// Syncs chat messages to Firebase Realtime Database for the authenticated user.
class ChatSyncService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _defaultSessionId = 'default_rag_session';

  /// Saves a message to Realtime Database.
  Future<void> saveMessage(ChatMessage message) async {
    final user = _auth.currentUser;
    if (user == null) return; // Only sync if logged in

    try {
      final messageRef = _db.ref('users/${user.uid}/chat_messages/$_defaultSessionId/${message.id}');
      await messageRef.set(message.toJson());

      // Update session timestamp
      await _db.ref('users/${user.uid}/chat_sessions/$_defaultSessionId').update({
        'updatedAt': DateTime.now().toIso8601String(),
        'title': 'My Knowledge Base Chat',
      });
    } catch (e) {
      debugPrint("RTDB Save Error: $e");
    }
  }

  /// Loads messages for the user's RAG session.
  Future<List<ChatMessage>> loadMessages() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _db.ref('users/${user.uid}/chat_messages/$_defaultSessionId').get();
      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final list = data.values.map((v) => ChatMessage.fromJson(Map<String, dynamic>.from(v as Map))).toList();
      
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (e) {
      debugPrint("RTDB Load Messages Error: $e");
      return [];
    }
  }

  /// Clears chat history for the user.
  Future<void> clearHistory() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await _db.ref('users/${user.uid}/chat_messages/$_defaultSessionId').remove();
    await _db.ref('users/${user.uid}/chat_sessions/$_defaultSessionId').remove();
  }
}
