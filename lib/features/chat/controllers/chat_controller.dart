import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';

class ChatController extends GetxController {
  final ChatService _service;
  final _uuid = const Uuid();

  ChatController(this._service);

  final messages = <ChatMessage>[].obs;
  final isLoading = false.obs;
  final isSending = false.obs;
  final error = RxnString();
  final sessionId = ''.obs;

  final systemPrompt = 'You are a helpful, knowledgeable, and friendly AI assistant.'.obs;
  final temperature = 0.7.obs;
  final maxTokens = 512.obs;

  final sessions = <ChatSession>[].obs;
  final sessionsLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    sessionId.value = _uuid.v4();
  }

  void openSession(String id) {
    sessionId.value = id;
    messages.clear();
    error.value = null;
  }

  void newConversation() {
    sessionId.value = _uuid.v4();
    messages.clear();
    isLoading.value = false;
    error.value = null;
  }

  Future<void> loadSessions() async {
    sessionsLoading.value = true;
    try {
      final result = await _service.loadSessions();
      sessions.assignAll(result);
    } catch (_) {
    } finally {
      sessionsLoading.value = false;
    }
  }

  Future<void> deleteSession(String id) async {
    await _service.deleteSession(id);
    sessions.removeWhere((s) => s.id == id);
    if (sessionId.value == id) newConversation();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isLoading.value) return;

    final sid = sessionId.value.isEmpty ? _uuid.v4() : sessionId.value;
    sessionId.value = sid;
    error.value = null;

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: text.trim(),
      role: MessageRole.user,
      sessionId: sid,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    messages.add(userMsg);

    const typingId = '__typing__';
    final typingMsg = ChatMessage(
      id: typingId,
      content: '',
      role: MessageRole.assistant,
      sessionId: sid,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    messages.add(typingMsg);

    isLoading.value = true;
    isSending.value = true;

    try {
      final reply = await _service.sendMessage(
        message: text.trim(),
        sessionId: sid,
        systemPrompt: systemPrompt.value,
        temperature: temperature.value,
        maxTokens: maxTokens.value,
      );

      final userIndex = messages.indexWhere((m) => m.id == userMsg.id);
      if (userIndex != -1) {
        messages[userIndex] = userMsg.copyWith(status: MessageStatus.sent);
      }

      final typingIndex = messages.indexWhere((m) => m.id == typingId);
      if (typingIndex != -1) {
        messages[typingIndex] = reply;
      }

      isSending.value = false;
    } on ChatException catch (e) {
      _handleError(userMsg, typingId, e.message);
    } catch (e) {
      _handleError(userMsg, typingId, 'Network error. Please check your connection.');
    } finally {
      isLoading.value = false;
      isSending.value = false;
    }
  }

  void _handleError(ChatMessage userMsg, String typingId, String message) {
    messages.removeWhere((m) => m.id == typingId);
    final idx = messages.indexWhere((m) => m.id == userMsg.id);
    if (idx != -1) {
      messages[idx] = userMsg.copyWith(
        status: MessageStatus.failed,
        errorMessage: message,
      );
    }
    error.value = message;
  }

  Future<void> retryMessage(String messageId) async {
    final msg = messages.firstWhereOrNull((m) => m.id == messageId);
    if (msg == null) return;
    messages.remove(msg);
    await sendMessage(msg.content);
  }

  void clearError() => error.value = null;

  void updateSettings({
    String? prompt,
    double? temp,
    int? tokens,
  }) {
    if (prompt != null) systemPrompt.value = prompt;
    if (temp != null) temperature.value = temp;
    if (tokens != null) maxTokens.value = tokens;
  }
}
