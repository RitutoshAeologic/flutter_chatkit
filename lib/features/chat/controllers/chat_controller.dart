import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/chat_service.dart';

class ChatController extends GetxController {
  final ChatService _service = Get.find<ChatService>();
  final _uuid = const Uuid();

  final messages = <ChatMessage>[].obs;
  final isSending = false.obs;

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isSending.value) return;

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: text.trim(),
      role: MessageRole.user,
      createdAt: DateTime.now(),
    );

    messages.add(userMsg);
    isSending.value = true;

    try {
      // Add a placeholder assistant message with isLoading = true
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
      );
      
      // Replace placeholder with actual reply
      final index = messages.indexOf(assistantPlaceholder);
      if (index != -1) {
        messages[index] = reply;
      }
    } catch (e) {
      // Remove loading indicator on error
      messages.removeWhere((m) => m.isLoading);
      Get.snackbar('Error', 'Failed to get a response.');
    } finally {
      isSending.value = false;
    }
  }

  void clearChat() {
    messages.clear();
  }
}
