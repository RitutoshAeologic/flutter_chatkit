import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';
import '../models/message.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../splash/splash_screen.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CustomPaint(
              size: const Size(24, 24),
              painter: ChatKitLogoPainter(color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 8),
            const Text('ChatKit AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            onSelected: (value) {
              if (value == 'clear') controller.clearChat();
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
                  return _buildMessageBubble(message, theme);
                },
              );
            }),
          ),
          _buildInputBar(theme, textController),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: 0.1,
            child: CustomPaint(
              size: const Size(120, 120),
              painter: ChatKitLogoPainter(color: theme.colorScheme.onSurface),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Start a conversation',
            style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask me anything',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ).animate().fadeIn(duration: 800.ms).scale(begin: const Offset(0.9, 0.9)),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ThemeData theme) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CustomPaint(
              size: const Size(24, 24),
              painter: ChatKitLogoPainter(color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isUser 
                  ? theme.colorScheme.primary 
                  : theme.colorScheme.surfaceContainerHighest,
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
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 300.ms).slideX(begin: isUser ? 0.1 : -0.1),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
            shape: BoxShape.circle,
          ),
        ).animate(onPlay: (controller) => controller.repeat())
         .scale(duration: 600.ms, delay: (index * 200).ms, begin: const Offset(1, 1), end: const Offset(1.5, 1.5))
         .then()
         .scale(duration: 600.ms, begin: const Offset(1.5, 1.5), end: const Offset(1, 1));
      }),
    );
  }

  Widget _buildInputBar(ThemeData theme, TextEditingController textController) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              maxLines: 5,
              minLines: 1,
              onSubmitted: (_) {
                controller.sendMessage(textController.text);
                textController.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          Obx(() => IconButton.filled(
            onPressed: controller.isSending.value 
              ? null 
              : () {
                controller.sendMessage(textController.text);
                textController.clear();
              },
            icon: controller.isSending.value 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          )),
        ],
      ),
    );
  }
}
