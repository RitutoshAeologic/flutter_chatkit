import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';
import '../models/message.dart';
import '../models/chat_session.dart';
import '../../auth/controllers/auth_controller.dart';
import '../widgets/image_message_bubble.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textController = TextEditingController();
    final inputText = "".obs;

    return Scaffold(
      drawer: _buildHistoryDrawer(context, theme),
      appBar: AppBar(
        centerTitle: true,
        title: Obx(() => Text(
          controller.currentSession.value?.displayTitle ?? 'ChatKit AI',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Chat',
            onPressed: () => controller.startNewChat(),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'new', child: Text('New session')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            onSelected: (value) {
              if (value == 'new') controller.startNewChat();
              if (value == 'logout') Get.find<AuthController>().signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              if (controller.messages.isEmpty) {
                return _buildEmptyState(theme);
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                itemCount: controller.messages.length,
                itemBuilder: (context, index) {
                  final message = controller.messages[index];
                  if (message.type == MessageType.image) {
                    return ImageMessageBubble(message: message);
                  }
                  return _buildMessageBubble(message, theme);
                },
              );
            }),
          ),
          _buildInputBar(theme, textController, inputText),
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer(BuildContext context, ThemeData theme) {
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.auto_awesome_mosaic_rounded, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text('Chat History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Start New Chat', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              controller.startNewChat();
              Get.back();
            },
          ),
          const Divider(),
          Expanded(
            child: Obx(() {
              if (controller.isLoadingSessions.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.sessions.isEmpty) {
                return const Center(child: Text('No previous chats'));
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: controller.sessions.length,
                itemBuilder: (context, index) {
                  final session = controller.sessions[index];
                  final isCurrent = controller.currentSession.value?.id == session.id;
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(session.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${session.lastUpdated.day}/${session.lastUpdated.month} ${session.lastUpdated.hour}:${session.lastUpdated.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    onTap: () {
                      controller.selectSession(session);
                      Get.back();
                    },
                    trailing: isCurrent ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 16) : null,
                  );
                },
              );
            }),
          ),
          const Divider(),
          _buildClearAllButton(context, theme),
        ],
      ),
    );
  }

  Widget _buildClearAllButton(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: OutlinedButton.icon(
        onPressed: () => _showClearAllConfirmation(context),
        icon: const Icon(Icons.delete_sweep, color: Colors.red),
        label: const Text('Clear All History', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _showClearAllConfirmation(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Clear All History?'),
        content: const Text('This will wipe your entire conversation history. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              controller.clearAllHistory();
              Get.back();
              Get.back();
            },
            child: const Text('Clear Everything', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 80, color: theme.colorScheme.primary.withOpacity(0.2)),
            const SizedBox(height: 24),
            Text(
              'How can I help you today?',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildQuickPrompt(theme, "Write a creative story about space."),
            _buildQuickPrompt(theme, "Explain Quantum Physics to a 5-year-old."),
            _buildQuickPrompt(theme, "Give me a healthy 5-minute breakfast idea."),
            _buildQuickPrompt(theme, "/image a futuristic city under the ocean"),
          ],
        ).animate().fadeIn(duration: 800.ms).scale(begin: const Offset(0.9, 0.9)),
      ),
    );
  }

  Widget _buildQuickPrompt(ThemeData theme, String prompt) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: InkWell(
        onTap: () => controller.sendMessage(prompt),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(prompt.contains('/image') ? Icons.image_outlined : Icons.lightbulb_outline, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(prompt, style: const TextStyle(fontSize: 14))),
              const Icon(Icons.arrow_forward_ios, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ThemeData theme) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isUser 
                      ? LinearGradient(
                          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                    color: isUser ? null : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomRight: isUser ? const Radius.circular(4) : null,
                      bottomLeft: !isUser ? const Radius.circular(4) : null,
                    ),
                  ),
                  child: message.isLoading
                      ? _buildTypingIndicator(theme)
                      : MarkdownBody(
                          data: message.content,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium?.copyWith(
                              color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return SizedBox(
      width: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (index) {
          return Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(150),
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (controller) => controller.repeat())
           .scale(duration: 600.ms, delay: (index * 200).ms, begin: const Offset(1, 1), end: const Offset(1.5, 1.5))
           .then()
           .scale(duration: 600.ms, begin: const Offset(1.5, 1.5), end: const Offset(1, 1));
        }),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, TextEditingController textController, RxString inputText) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: textController,
                onChanged: (val) => inputText.value = val,
                decoration: InputDecoration(
                  hintText: 'Ask me anything...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                maxLines: 5,
                minLines: 1,
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    controller.sendMessage(val);
                    textController.clear();
                    inputText.value = "";
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Obx(() => IconButton.filled(
            onPressed: controller.isSending.value || inputText.value.trim().isEmpty 
              ? null 
              : () {
                  controller.sendMessage(textController.text);
                  textController.clear();
                  inputText.value = "";
                },
            icon: controller.isSending.value 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.arrow_upward),
            style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
          )),
        ],
      ),
    );
  }
}
