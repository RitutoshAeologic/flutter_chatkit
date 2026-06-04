import 'dart:async';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';
import '../../auth/controllers/auth_controller.dart';
import 'package:flutter/material.dart';

// lib/controllers/chat_controller.dart
//
// CHANGES FROM ORIGINAL (marked with ── NEW ──):
//
// 1. IntentDetectionService injected via constructor
// 2. isImageMode  — RxBool, toggled by wand button in UI
// 3. pendingIntent — Rxn<IntentResult>, drives confirmation bubble
// 4. sendMessage() — checks isImageMode first, then runs intent
//    detection on plain text, shows bubble for IMAGE intent
// 5. confirmImageGeneration() / declineImageGeneration() — called
//    from confirmation bubble buttons
// 6. toggleImageMode() — called by wand icon in input bar
//
// Everything else (session management, Firebase, scroll, keyboard)
// is UNCHANGED from the original.

import 'package:flutter/widgets.dart';

import '../services/intent_detection_service.dart';

class ChatController extends GetxController {
  final ChatService _service = Get.find<ChatService>();
  final AuthController _auth = Get.find<AuthController>();

  // ── NEW ── injected intent detector
  final IntentDetectionService _intent = Get.find<IntentDetectionService>();

  final _uuid = const Uuid();

  // ── Existing observables (unchanged) ──────────────────────────────────
  final messages          = <ChatMessage>[].obs;
  final sessions          = <ChatSession>[].obs;
  final isSending         = false.obs;
  final isLoadingSessions = false.obs;
  final currentSession    = Rxn<ChatSession>();

  // ── UI controllers (unchanged) ─────────────────────────────────────────
  final scrollController  = ScrollController();
  final messageController = TextEditingController();
  final messageFocusNode  = FocusNode();

  // ── NEW: image mode state ──────────────────────────────────────────────
  /// true  → wand mode active, every send goes to Pollinations directly
  final isImageMode = false.obs;

  /// Non-null while the confirmation bubble is visible.
  /// Holds the original user text so we can generate if confirmed.
  final pendingIntentText = Rxn<String>();

  // ──────────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    refreshSessions().then((_) {
      if (sessions.isNotEmpty && currentSession.value == null) {
        selectSession(sessions.first);
      }
    });
    ever(messages, (_) => scrollToBottom());
  }

  @override
  void onClose() {
    scrollController.dispose();
    messageController.dispose();
    messageFocusNode.dispose();
    super.onClose();
  }

  // ── Keyboard helpers (unchanged) ──────────────────────────────────────

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

  // ── Send helpers (unchanged except routing inside sendMessage) ─────────

  Future<void> sendCurrentMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || isSending.value) return;
    messageController.clear();
    dismissKeyboard();
    await sendMessage(text);
  }

  // ── NEW: toggle wand mode ──────────────────────────────────────────────
  void toggleImageMode() {
    isImageMode.value = !isImageMode.value;
    // Clear any pending bubble when toggling
    pendingIntentText.value = null;
  }

  // ── NEW: confirmation bubble callbacks ─────────────────────────────────

  /// User tapped "Generate image" in the confirmation bubble.
  Future<void> confirmImageGeneration() async {
    final text = pendingIntentText.value;
    pendingIntentText.value = null; // dismiss bubble
    if (text == null) return;
    await _sendImageMessage(text);
  }

  /// User tapped "Answer as text" in the confirmation bubble.
  Future<void> declineImageGeneration() async {
    final text = pendingIntentText.value;
    pendingIntentText.value = null; // dismiss bubble
    if (text == null) return;
    await _sendTextMessage(text);
  }

  // ── Core sendMessage ───────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isSending.value) return;

    final trimmed = text.trim();

    // ── OPTION 1: Wand mode is ON → go straight to image ─────────────
    if (isImageMode.value) {
      await _sendImageMessage(trimmed);
      return;
    }

    // ── Legacy /image prefix still works (backwards compat) ───────────
    if (trimmed.startsWith('/image ')) {
      final prompt = trimmed.replaceFirst('/image ', '').trim();
      await _sendImageMessage(prompt);
      return;
    }

    // ── OPTION 3: Auto-detect intent ──────────────────────────────────
    // Run detector. High confidence IMAGE → show confirmation bubble.
    // TEXT / uncertain-resolved-to-text → send normally.
    // We run detection WITHOUT blocking the UI — the user message is
    // added to the list immediately so the screen feels instant.
    final result = await _intent.detect(trimmed);

    if (result.type == IntentType.image) {
      // Show confirmation bubble — never auto-generate
      pendingIntentText.value = trimmed;
      return; // wait for user to confirm or decline
    }

    // Default: send as text
    await _sendTextMessage(trimmed);
  }

  // ── Private send helpers ───────────────────────────────────────────────

  Future<void> _sendImageMessage(String prompt) async {
    final user = _auth.user;
    if (user == null) return;

    await _ensureSession(user.uid);

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: prompt,
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
        type: MessageType.image,
      );
      messages.add(loadingMsg);

      final imageUrl = await _service.generateImage(prompt);

      final reply = ChatMessage(
        id: _uuid.v4(),
        content: 'Generated image for "$prompt"',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        type: MessageType.image,
        imageUrl: imageUrl,
      );

      final index = messages.indexWhere((e) => e.id == loadingMsg.id);
      if (index != -1) {
        messages[index] = reply;
        _saveMessage(reply);
      }

      await refreshSessions();
    } catch (e) {
      messages.removeWhere((m) => m.isLoading);
      Get.snackbar('Error', 'Image generation failed. Please try again.');
    } finally {
      isSending.value = false;
    }
  }

  Future<void> _sendTextMessage(String text) async {
    final user = _auth.user;
    if (user == null) return;

    final historySnapshot = List<ChatMessage>.from(
      messages.where((m) => !m.isLoading),
    );

    await _ensureSession(user.uid);

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: text,
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
        type: MessageType.text,
      );
      messages.add(loadingMsg);

      final reply = await _service.sendMessage(text, history: historySnapshot);

      final index = messages.indexWhere((e) => e.id == loadingMsg.id);
      if (index != -1) {
        messages[index] = reply;
        _saveMessage(reply);
      }

      await refreshSessions();
    } catch (e) {
      messages.removeWhere((m) => m.isLoading);
      Get.snackbar('Error', 'Failed to send message.');
    } finally {
      isSending.value = false;
    }
  }

  // ── Session helpers (unchanged logic, extracted for reuse) ─────────────

  Future<void> _ensureSession(String userId) async {
    if (currentSession.value != null) return;
    final sessionId = await _service.createOrGetSession(userId);
    currentSession.value = ChatSession(
      id: sessionId,
      displayTitle: 'New Chat',
      lastUpdated: DateTime.now(),
    );
    await refreshSessions();
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
        if (updated != null) currentSession.value = updated;
      }
    } finally {
      isLoadingSessions.value = false;
    }
  }

  Future<void> startNewChat() async {
    final user = _auth.user;
    if (user == null) return;
    messages.clear();
    pendingIntentText.value = null;
    final sessionId = await _service.createOrGetSession(user.uid);
    currentSession.value = ChatSession(
      id: sessionId,
      displayTitle: 'New Chat',
      lastUpdated: DateTime.now(),
    );
    await refreshSessions();
  }

  Future<void> selectSession(ChatSession session) async {
    currentSession.value = session;
    messages.clear();
    pendingIntentText.value = null;
    final history = await _service.loadMessages(session.id);
    messages.assignAll(history);
  }

  void _saveMessage(ChatMessage message) {
    final user = _auth.user;
    if (user != null && currentSession.value != null) {
      unawaited(
        _service.saveMessage(user.uid, currentSession.value!.id, message),
      );
    }
  }

  Future<void> deleteSession(ChatSession session) async {
    final user = _auth.user;
    if (user != null) {
      await _service.deleteSession(user.uid, session.id);
      if (currentSession.value?.id == session.id) {
        currentSession.value = null;
        messages.clear();
        pendingIntentText.value = null;
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
      pendingIntentText.value = null;
      await refreshSessions();
    }
  }
}