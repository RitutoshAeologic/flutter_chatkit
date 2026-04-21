import 'dart:async';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';
import '../../auth/controllers/auth_controller.dart';
import 'package:flutter/material.dart';

class ChatController extends GetxController {
  final ChatService _service = Get.find<ChatService>();
  final AuthController _auth = Get.find<AuthController>();
  final _uuid = const Uuid();

  final messages = <ChatMessage>[].obs;
  final sessions = <ChatSession>[].obs;

  final isSending = false.obs;
  final isLoadingSessions = false.obs;
  final currentSession = Rxn<ChatSession>();

  /// UI Controllers
  final scrollController = ScrollController();
  final messageController = TextEditingController();
  final messageFocusNode = FocusNode();

  @override
  void onInit() {
    super.onInit();

    refreshSessions().then((_) {
      if (sessions.isNotEmpty && currentSession.value == null) {
        selectSession(sessions.first);
      }
    });

    /// auto-scroll whenever messages update
    ever(messages, (_) => scrollToBottom());
  }

  @override
  void onClose() {
    scrollController.dispose();
    messageController.dispose();
    messageFocusNode.dispose();
    super.onClose();
  }

  void dismissKeyboard() {
    messageFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> sendCurrentMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty || isSending.value) return;

    messageController.clear();
    dismissKeyboard();

    await sendMessage(text);
  }

  Future<void> refreshSessions() async {
    final user = _auth.user;
    if (user == null) return;

    isLoadingSessions.value = true;

    try {
      final list = await _service.listSessions(user.uid);
      sessions.assignAll(list);

      if (currentSession.value != null) {
        final updated = sessions.firstWhereOrNull(
              (e) => e.id == currentSession.value!.id,
        );

        if (updated != null) {
          currentSession.value = updated;
        }
      }
    } finally {
      isLoadingSessions.value = false;
    }
  }

  Future<void> startNewChat() async {
    final user = _auth.user;
    if (user == null) return;

    messages.clear();

    final sessionId = await _service.createOrGetSession(user.uid);

    currentSession.value = ChatSession(
      id: sessionId,
      displayTitle: "New Chat",
      lastUpdated: DateTime.now(),
    );

    await refreshSessions();
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
      messages.where((m) => !m.isLoading),
    );

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
      final loadingMsg = ChatMessage(
        id: 'loading-${_uuid.v4()}',
        content: '',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        isLoading: true,
        type: isImageRequest ? MessageType.image : MessageType.text,
      );

      messages.add(loadingMsg);

      ChatMessage reply;

      if (isImageRequest) {
        final prompt = trimmedText.replaceFirst('/image ', '').trim();

        final imageUrl = await _service.generateImage(prompt);

        reply = ChatMessage(
          id: _uuid.v4(),
          content: 'Generated image for "$prompt"',
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
          type: MessageType.image,
          imageUrl: imageUrl,
        );
      } else {
        reply = await _service.sendMessage(
          trimmedText,
          history: historySnapshot,
        );
      }

      final index = messages.indexWhere((e) => e.id == loadingMsg.id);

      if (index != -1) {
        messages[index] = reply;
        _saveMessage(reply);
      }

      await refreshSessions();
    } catch (e) {
      messages.removeWhere((m) => m.isLoading);
      Get.snackbar("Error", "Failed to send message");
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
