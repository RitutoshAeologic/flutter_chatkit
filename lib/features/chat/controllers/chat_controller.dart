import 'dart:async';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../../auth/controllers/auth_controller.dart';

class ChatController extends GetxController {
  final ChatService _service = Get.find<ChatService>();
  final AuthController _auth = Get.find<AuthController>();
  final _uuid = const Uuid();

  final messages = <ChatMessage>[].obs;
  final isSending = false.obs;
  final currentSessionId = "".obs;

  @override
  void onInit() {
    super.onInit();
    _initChat();
  }

  Future<void> _initChat() async {
    final user = _auth.user;
    if (user != null) {
      // For this demo, we use a simple shared session or retrieve the last one
      final sessions = await _service.listSessions(user.uid);
      if (sessions.isNotEmpty) {
        currentSessionId.value = sessions.first.id;
        final history = await _service.loadMessages(currentSessionId.value);
        messages.assignAll(history);
      } else {
        currentSessionId.value = await _service.createOrGetSession(user.uid);
      }
    }
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

    // Ensure session exists
    if (currentSessionId.value.isEmpty) {
      currentSessionId.value = await _service.createOrGetSession(user.uid);
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

        // For image messages, the "content" used for title generation should be the prompt
        if (messages.length <= 3) {
          unawaited(_service.updateSessionTitle(user.uid, currentSessionId.value, prompt));
        }
      } else {
        reply = await _service.sendMessage(
          trimmedText,
          history: historySnapshot,
        );
        // Standard title generation for first few messages
        if (messages.length <= 3) {
          unawaited(_service.updateSessionTitle(user.uid, currentSessionId.value, trimmedText));
        }
      }
      
      final index = messages.indexOf(assistantPlaceholder);
      if (index != -1) {
        messages[index] = reply;
        _saveMessage(reply);
      }
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
    if (user != null && currentSessionId.value.isNotEmpty) {
      unawaited(_service.saveMessage(user.uid, currentSessionId.value, message));
    }
  }

  Future<void> newSession() async {
    final user = _auth.user;
    if (user == null) return;

    messages.clear();
    currentSessionId.value = await _service.createOrGetSession(user.uid);
  }
}
