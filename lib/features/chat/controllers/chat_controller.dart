import 'dart:async' show unawaited; // M6: explicit unawaited import
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../../data/rag_models.dart';
import '../../../domain/inference_router.dart';
import 'package:firebase_database/firebase_database.dart';

class ChatController extends GetxController {
  final InferenceRouter _router = Get.find<InferenceRouter>();
  final AuthController _auth = Get.find<AuthController>();
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final _uuid = const Uuid();

  final messages = <ChatMessage>[].obs;
  final sessions = <ChatSession>[].obs;
  final isSending = false.obs;
  final isLoadingSessions = false.obs;
  final currentSession = Rxn<ChatSession>();

  /// M5: citations map — always cleared together with messages.
  final _citationsMap = <String, List<RagCitation>>{};

  @override
  void onInit() {
    super.onInit();
    refreshSessions().then((_) {
      if (sessions.isNotEmpty && currentSession.value == null) {
        selectSession(sessions.first);
      }
    });
  }

  // ── Public getters ────────────────────────────────────────────────────────

  /// Returns citations for a given message ID (null if not a RAG response).
  List<RagCitation>? citationsFor(String messageId) =>
      _citationsMap[messageId];

  // ── Session management ────────────────────────────────────────────────────

  Future<void> refreshSessions() async {
    final user = _auth.user;
    if (user != null) {
      isLoadingSessions.value = true;
      try {
        final list = await _listSessions(user.uid);
        sessions.assignAll(list);

        if (currentSession.value != null) {
          final updated = sessions.firstWhereOrNull(
              (s) => s.id == currentSession.value!.id);
          if (updated != null) currentSession.value = updated;
        }
      } finally {
        isLoadingSessions.value = false;
      }
    }
  }

  Future<void> startNewChat() async {
    final user = _auth.user;
    if (user != null) {
      _clearMessages(); // M5: always clears citations too
      final sessionId = await _createSession(user.uid);
      currentSession.value = ChatSession(
        id: sessionId,
        displayTitle: 'New Chat',
        lastUpdated: DateTime.now(),
      );
      await refreshSessions();
    }
  }

  Future<void> selectSession(ChatSession session) async {
    currentSession.value = session;
    _clearMessages(); // M5
    final history = await _loadMessages(session.id);
    messages.assignAll(history);
  }

  Future<void> deleteSession(ChatSession session) async {
    final user = _auth.user;
    if (user != null) {
      await _db.ref('users/${user.uid}/chat_sessions/${session.id}').remove();
      await _db.ref('chat_messages/${session.id}').remove();
      if (currentSession.value?.id == session.id) {
        currentSession.value = null;
        _clearMessages(); // M5
      }
      await refreshSessions();
    }
  }

  Future<void> clearAllHistory() async {
    final user = _auth.user;
    if (user != null) {
      final snapshot =
          await _db.ref('users/${user.uid}/chat_sessions').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        for (final id in data.keys) {
          await _db.ref('chat_messages/$id').remove();
        }
      }
      await _db.ref('users/${user.uid}/chat_sessions').remove();
      currentSession.value = null;
      _clearMessages(); // M5
      await refreshSessions();
    }
  }

  // ── Message sending ───────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isSending.value) return;

    final user = _auth.user;
    if (user == null) return;

    final trimmedText = text.trim();
    final isImageRequest = trimmedText.startsWith('/image ');

    // Auto-create session if none exists
    if (currentSession.value == null) {
      final sessionId = await _createSession(user.uid);
      currentSession.value = ChatSession(
        id: sessionId,
        displayTitle: 'New Chat',
        lastUpdated: DateTime.now(),
      );
      await refreshSessions();
    }

    // User message
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: trimmedText,
      role: MessageRole.user,
      createdAt: DateTime.now(),
    );
    messages.add(userMsg);
    _saveMessage(userMsg);
    isSending.value = true;

    // Loading placeholder
    final placeholder = ChatMessage(
      id: 'loading-${_uuid.v4()}',
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      isLoading: true,
      type: isImageRequest ? MessageType.image : MessageType.text,
    );
    messages.add(placeholder);

    try {
      ChatMessage reply;

      if (isImageRequest) {
        // Flow C — Image generation (no RAG)
        final prompt = trimmedText.replaceFirst('/image ', '').trim();
        if (prompt.isEmpty) throw Exception('Please provide an image prompt.');

        final encodedPrompt = Uri.encodeComponent(prompt);
        final seed = DateTime.now().millisecondsSinceEpoch;
        final imageUrl =
            'https://image.pollinations.ai/prompt/$encodedPrompt'
            '?width=1024&height=1024&nologo=true&seed=$seed';

        reply = ChatMessage(
          id: _uuid.v4(),
          content: 'Generated image for: "$prompt"',
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
          type: MessageType.image,
          imageUrl: imageUrl,
        );

        if (messages.length <= 3) {
          unawaited(
            _router.generateTitle(prompt).then((title) {
              if (title != null) {
                _db
                    .ref('users/${user.uid}/chat_sessions/'
                        '${currentSession.value!.id}')
                    .update({'title': title});
              }
            }).catchError((Object e) {
              debugPrint('Title update failed: $e');
            }),
          );
        }
      } else {
        // Flow A/B — Text chat with optional RAG
        final routerResponse = await _router.query(
          trimmedText,
          history: _budgetedHistory(),
        );

        reply = ChatMessage(
          id: _uuid.v4(),
          content: routerResponse.content,
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
        );

        // Store citations if RAG was used (M5: map keyed by message ID)
        if (routerResponse.usedRag && routerResponse.citations.isNotEmpty) {
          _citationsMap[reply.id] = routerResponse.citations;
        }

        if (messages.length <= 3) {
          unawaited(
            _router.generateTitle(trimmedText).then((title) {
              if (title != null) {
                _db
                    .ref('users/${user.uid}/chat_sessions/'
                        '${currentSession.value!.id}')
                    .update({'title': title});
                refreshSessions();
              }
            }).catchError((Object e) {
              debugPrint('Title update failed: $e');
            }),
          );
        }
      }

      // Replace placeholder with real reply
      final index = messages.indexOf(placeholder);
      if (index != -1) {
        messages[index] = reply;
        _saveMessage(reply);
      }

      await refreshSessions();
    } catch (e) {
      messages.removeWhere((m) => m.isLoading);
      final errorMessage = e.toString().contains('Exception:')
          ? e.toString().split('Exception:').last.trim()
          : 'Failed to get a response.';
      Get.snackbar('Error', errorMessage);
    } finally {
      isSending.value = false;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// M5: Always clears _citationsMap when messages are cleared.
  void _clearMessages() {
    messages.clear();
    _citationsMap.clear();
  }

  /// O5: Budget history by character count, newest messages first.
  List<ChatMessage> _budgetedHistory() {
    final result = <ChatMessage>[];
    int chars = 0;
    for (final msg in messages.reversed.where((m) => !m.isLoading)) {
      if (chars + msg.content.length > 6000) break;
      result.insert(0, msg); // maintain chronological order
      chars += msg.content.length;
    }
    return result;
  }

  void _saveMessage(ChatMessage message) {
    final user = _auth.user;
    if (user != null && currentSession.value != null) {
      unawaited(
        _db
            .ref('chat_messages/${currentSession.value!.id}/${message.id}')
            .set(message.toJson())
            .catchError((Object e) {
          debugPrint('RTDB save error: $e');
        }),
      );
      unawaited(
        _db
            .ref(
                'users/${user.uid}/chat_sessions/${currentSession.value!.id}')
            .update({'updatedAt': DateTime.now().toIso8601String()})
            .catchError((Object e) {
          debugPrint('RTDB session update error: $e');
        }),
      );
    }
  }

  Future<String> _createSession(String userId) async {
    final sessionId = _uuid.v4();
    await _db.ref('users/$userId/chat_sessions/$sessionId').set({
      'sessionId': sessionId,
      'title': 'New Chat',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    return sessionId;
  }

  Future<List<ChatMessage>> _loadMessages(String sessionId) async {
    try {
      final snapshot =
          await _db.ref('chat_messages/$sessionId').get();
      if (!snapshot.exists) return [];
      final data =
          Map<String, dynamic>.from(snapshot.value as Map);
      final list = data.values
          .map((v) => ChatMessage.fromJson(
              Map<String, dynamic>.from(v as Map)))
          .toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (e) {
      debugPrint('RTDB load messages error: $e');
      return [];
    }
  }

  Future<List<ChatSession>> _listSessions(String userId) async {
    try {
      final snapshot =
          await _db.ref('users/$userId/chat_sessions').get();
      if (!snapshot.exists) return [];
      final data =
          Map<String, dynamic>.from(snapshot.value as Map);
      return data.entries.map((e) {
        final val = Map<String, dynamic>.from(e.value as Map);
        DateTime updatedAt;
        if (val['updatedAt'] is int) {
          updatedAt =
              DateTime.fromMillisecondsSinceEpoch(val['updatedAt'] as int);
        } else if (val['updatedAt'] is String) {
          updatedAt =
              DateTime.tryParse(val['updatedAt'] as String) ?? DateTime.now();
        } else {
          updatedAt = DateTime.now();
        }
        return ChatSession(
          id: e.key,
          displayTitle: val['title'] as String? ?? 'Untitled',
          lastUpdated: updatedAt,
        );
      }).toList()
        ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    } catch (e) {
      debugPrint('RTDB list sessions error: $e');
      return [];
    }
  }
}
