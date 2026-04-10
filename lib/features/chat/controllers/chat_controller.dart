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
  final isSending = false.obs;
  final currentSession = Rxn<ChatSession>();

  @override
  void onInit() {
    super.onInit();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final user = _auth.user;
    if (user != null) {
      currentSession.value = await _service.createSession("New Chat", user.uid);
    }
  }

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
      
      final index = messages.indexOf(assistantPlaceholder);
      if (index != -1) {
        messages[index] = reply;
      }
    } catch (e) {
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
