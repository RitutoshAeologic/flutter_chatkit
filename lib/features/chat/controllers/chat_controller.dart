import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../auth/controllers/auth_controller.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';

class ChatController extends GetxController {
  final ChatService _service = Get.find<ChatService>();
  final AuthController _auth = Get.find<AuthController>();
  final _uuid = const Uuid();

  final messages = <ChatMessage>[].obs;
  final sessions = <ChatSession>[].obs;
  final isSending = false.obs;
  final isLoadingSessions = false.obs;
  final currentSession = Rxn<ChatSession>();
  final inputText = "".obs;

  @override
  void onInit() {
    super.onInit();
    refreshSessions();
  }

  /// Refreshes the list of previous chat sessions.
  Future<void> refreshSessions() async {
    final user = _auth.user;
    if (user != null) {
      isLoadingSessions.value = true;
      try {
        final list = await _service.listSessions(user.uid);
        sessions.assignAll(list);
        
        // Update current session object if it exists in the list (to pick up the new title)
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
      currentSession.value = await _service.createSession("New Chat", user.uid);
      await refreshSessions();
    }
  }

  /// Selects and loads an existing chat session.
  Future<void> selectSession(ChatSession session) async {
    currentSession.value = session;
    messages.clear();
    final history = await _service.loadMessages(session.id);
    messages.assignAll(history);
    Get.back(); // Close drawer if open
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isSending.value) return;

    final user = _auth.user;
    if (user == null) return;

    // Auto-create session if none exists
    if (currentSession.value == null) {
      currentSession.value = await _service.createSession("New Chat", user.uid);
      await refreshSessions();
    }

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: text.trim(),
      role: MessageRole.user,
      createdAt: DateTime.now(),
    );

    messages.add(userMsg);
    isSending.value = true;

    try {
      final assistantPlaceholder = ChatMessage(
        id: 'loading-${_uuid.v4()}',
        content: '',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        isLoading: true,
      );
      messages.add(assistantPlaceholder);

      final reply = await _service.sendMessage(
        text.trim(),
        history: messages.where((m) => !m.isLoading && m.id != userMsg.id).toList(),
        sessionId: currentSession.value?.id,
        userId: user.uid,
      );
      
      final index = messages.indexOf(assistantPlaceholder);
      if (index != -1) {
        messages[index] = reply;
      }

      // Refresh sessions to update title/timestamp in sidebar
      await refreshSessions();
      
    } catch (e) {
      messages.removeWhere((m) => m.isLoading);
      Get.snackbar('Error', 'Failed to get a response.');
    } finally {
      isSending.value = false;
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

  void clearChat() {
    messages.clear();
  }
}
