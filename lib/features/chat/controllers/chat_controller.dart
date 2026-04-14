import 'dart:async';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';
import '../../auth/controllers/auth_controller.dart';

class ChatController extends GetxController {
  final ChatService _service = Get.find<ChatService>();
  final AuthController _auth = Get.find<AuthController>();
  final _uuid = const Uuid();

  final messages = <ChatMessage>[].obs;
  final sessions = <ChatSession>[].obs;
  final isSending = false.obs;
  final isLoadingSessions = false.obs;
  final currentSession = Rxn<ChatSession>();

  @override
  void onInit() {
    super.onInit();
    refreshSessions().then((_) {
      if (sessions.isNotEmpty && currentSession.value == null) {
        selectSession(sessions.first);
      }
    });
  }

  /// Refreshes the list of previous chat sessions.
  Future<void> refreshSessions() async {
    final user = _auth.user;
    if (user != null) {
      isLoadingSessions.value = true;
      try {
        final list = await _service.listSessions(user.uid);
        sessions.assignAll(list);
        
        if (currentSession.value != null) {
          final updated = sessions.firstWhereOrNull((s) => s.id == currentSession.value!.id);
          if (updated != null) {
            currentSession.value = updated;
          }
        }
      } finally {
        isLoadingSessions.value = false;
      }
    }
  }

  /// Starts a completely new chat session.
  Future<void> startNewChat() async {
    final user = _auth.user;
    if (user != null) {
      messages.clear();
      final sessionId = await _service.createOrGetSession(user.uid);
      currentSession.value = ChatSession(
        id: sessionId,
        displayTitle: "New Chat",
        lastUpdated: DateTime.now(),
      );
      await refreshSessions();
    }
  }

  /// Selects and loads an existing chat session.
  Future<void> selectSession(ChatSession session) async {
    currentSession.value = session;
    messages.clear();
    final history = await _service.loadMessages(session.id);
    messages.assignAll(history);
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isSending.value) return;

    final user = _auth.user;
    if (user == null) return;

    final trimmedText = text.trim();
    final isImageRequest = trimmedText.startsWith('/image ');

    final historySnapshot = List<ChatMessage>.from(
      messages.where((m) => !m.isLoading).toList(),
    );

    // Auto-create session if none exists
    if (currentSession.value == null) {
      final sessionId = await _service.createOrGetSession(user.uid);
      currentSession.value = ChatSession(
        id: sessionId,
        displayTitle: "New Chat",
        lastUpdated: DateTime.now(),
      );
      await refreshSessions();
    }

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: trimmedText,
      role: MessageRole.user,
      createdAt: DateTime.now(),
    );

    messages.add(userMsg);
    _saveMessage(userMsg);
    isSending.value = true;

    try {
      final assistantPlaceholder = ChatMessage(
        id: 'loading-${_uuid.v4()}',
        content: '',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        isLoading: true,
        type: isImageRequest ? MessageType.image : MessageType.text,
      );
      messages.add(assistantPlaceholder);
      // Intentionally NOT saved to RTDB — loading states are ephemeral and will be regenerated on app restart.

      ChatMessage reply;

      if (isImageRequest) {
        final prompt = trimmedText.replaceFirst('/image ', '').trim();
        if (prompt.isEmpty) {
          throw Exception('Please provide a prompt for image generation.');
        }

        final imageUrl = await _service.generateImage(prompt);
        reply = ChatMessage(
          id: _uuid.v4(),
          content: 'Generated image for: "$prompt"',
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
          type: MessageType.image,
          imageUrl: imageUrl,
        );

        if (messages.length <= 3) {
          unawaited(_service.updateSessionTitle(user.uid, currentSession.value!.id, prompt));
        }
      } else {
        reply = await _service.sendMessage(
          trimmedText,
          history: historySnapshot,
        );
        if (messages.length <= 3) {
          unawaited(_service.updateSessionTitle(user.uid, currentSession.value!.id, trimmedText));
        }
      }
      
      final index = messages.indexOf(assistantPlaceholder);
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

  void _saveMessage(ChatMessage message) {
    final user = _auth.user;
    if (user != null && currentSession.value != null) {
      unawaited(_service.saveMessage(user.uid, currentSession.value!.id, message));
    }
  }

  Future<void> deleteSession(ChatSession session) async {
    final user = _auth.user;
    if (user != null) {
      await _service.deleteSession(user.uid, session.id);
      if (currentSession.value?.id == session.id) {
        currentSession.value = null;
        messages.clear();
      }
      await refreshSessions();
    }
  }

  Future<void> clearAllHistory() async {
    final user = _auth.user;
    if (user != null) {
      await _service.clearAllHistory(user.uid);
      currentSession.value = null;
      messages.clear();
      await refreshSessions();
    }
  }
}
