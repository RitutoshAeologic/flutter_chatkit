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
    final theme    = Theme.of(context);
    final inputText = ''.obs;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: controller.dismissKeyboard,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
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
              onPressed: controller.startNewChat,
            ),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new',    child: Text('New session')),
                const PopupMenuItem(value: 'logout', child: Text('Sign out')),
              ],
              onSelected: (value) {
                if (value == 'new')    controller.startNewChat();
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 24),
                  itemCount: controller.messages.length,
                  controller: controller.scrollController,
                  itemBuilder: (_, index) {
                    final message = controller.messages[index];
                    if (message.type == MessageType.image) {
                      return ImageMessageBubble(message: message);
                    }
                    return _buildMessageBubble(message, theme);
                  },
                );
              }),
            ),

            // ── NEW: intent confirmation bubble ──────────────────────
            Obx(() {
              if (controller.pendingIntentText.value == null) {
                return const SizedBox.shrink();
              }
              return _buildIntentBubble(
                  theme, controller.pendingIntentText.value!);
            }),

            _buildInputBar(theme, inputText),
          ],
        ),
      ),
    );
  }

  // ── NEW: Intent confirmation bubble ────────────────────────────────────
  //
  // Appears above the input bar when auto-detection fires.
  // User must actively choose — we never generate silently.

  Widget _buildIntentBubble(ThemeData theme, String detectedText) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      offset: Offset.zero,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.secondary.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(Icons.auto_fix_high,
                    size: 16, color: theme.colorScheme.secondary),
                const SizedBox(width: 6),
                Text(
                  'Looks like an image request',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Detected text preview
            Text(
              '"$detectedText"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSecondaryContainer.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 10),
            // Action buttons
            Row(
              children: [
                // Generate image — primary action
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.confirmImageGeneration,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Generate image',
                        style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Answer as text — secondary action
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.declineImageGeneration,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Answer as text',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.3, end: 0);
  }

  // ── Input bar with wand toggle (CHANGED) ───────────────────────────────

  Widget _buildInputBar(ThemeData theme, RxString inputText) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── NEW: mode pill ─────────────────────────────────────────
          Obx(() {
            if (!controller.isImageMode.value) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_fix_high,
                            size: 12, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Image mode — tap wand to switch back',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          // ── Input row ──────────────────────────────────────────────
          Row(
            children: [
              // ── NEW: wand toggle button ────────────────────────────
              Obx(() => IconButton(
                onPressed: controller.toggleImageMode,
                tooltip: controller.isImageMode.value
                    ? 'Switch to text mode'
                    : 'Switch to image mode',
                style: IconButton.styleFrom(
                  backgroundColor: controller.isImageMode.value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHigh,
                  minimumSize: const Size(44, 44),
                  shape: const CircleBorder(),
                ),
                icon: Icon(
                  Icons.auto_fix_high,
                  size: 20,
                  color: controller.isImageMode.value
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              )),
              const SizedBox(width: 8),

              // TextField
              Expanded(
                child: Obx(() => Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                    // Subtle highlight when image mode is active
                    border: controller.isImageMode.value
                        ? Border.all(
                        color:
                        theme.colorScheme.primary.withOpacity(0.4))
                        : null,
                  ),
                  child: TextField(
                    controller: controller.messageController,
                    focusNode: controller.messageFocusNode,
                    onChanged: (val) => inputText.value = val,
                    decoration: InputDecoration(
                      hintText: controller.isImageMode.value
                          ? 'Describe an image…'
                          : 'Ask me anything…',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                    maxLines: 5,
                    minLines: 1,
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        controller.sendCurrentMessage();
                        inputText.value = '';
                      }
                    },
                  ),
                )),
              ),
              const SizedBox(width: 8),

              // Send button (unchanged)
              Obx(() => IconButton.filled(
                onPressed: controller.isSending.value ||
                    inputText.value.trim().isEmpty
                    ? null
                    : controller.sendCurrentMessage,
                icon: controller.isSending.value
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.arrow_upward),
                style: IconButton.styleFrom(
                    minimumSize: const Size(56, 56)),
              )),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empty state (tip copy updated) ────────────────────────────────────

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 80,
                color: theme.colorScheme.primary.withOpacity(0.2)),
            const SizedBox(height: 24),
            Text(
              'How can I help you today?',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            _buildEmptyStateTip(theme), // ── NEW copy ──
            const SizedBox(height: 32),
            _buildQuickPrompt(
                theme, 'Write a creative story about space.', false),
            _buildQuickPrompt(
                theme, 'Explain Quantum Physics to a 5-year-old.', false),
            _buildQuickPrompt(
                theme, 'Give me a healthy 5-minute breakfast idea.', false),
            // ── NEW: wand prompt instead of /image prefix ──
            _buildQuickPrompt(
                theme, 'Draw me a futuristic city under the ocean.', true),
          ],
        ).animate().fadeIn(duration: 800.ms).scale(
          begin: const Offset(0.9, 0.9),
        ),
      ),
    );
  }

  // ── NEW: updated tip (no /image mention) ──────────────────────────────
  Widget _buildEmptyStateTip(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border:
        Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high,
              color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tap the wand icon to switch to image mode, or just describe '
                  'what you want to see — we\'ll detect it automatically.',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick prompt (isImage flag replaces /image prefix check) ──────────
  Widget _buildQuickPrompt(
      ThemeData theme, String prompt, bool isImage) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: InkWell(
        onTap: () => isImage
            ? controller.sendMessage(prompt)
            : controller.sendMessage(prompt),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isImage ? Icons.auto_fix_high : Icons.lightbulb_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(prompt,
                      style: const TextStyle(fontSize: 14))),
              const Icon(Icons.arrow_forward_ios, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── Everything below unchanged from original ───────────────────────────

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
                  Icon(Icons.auto_awesome_mosaic_rounded,
                      size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text('Chat History',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Start New Chat',
                style: TextStyle(fontWeight: FontWeight.w600)),
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
                itemBuilder: (_, index) {
                  final session = controller.sessions[index];
                  final isCurrent =
                      controller.currentSession.value?.id == session.id;
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor:
                    theme.colorScheme.primaryContainer.withOpacity(0.5),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(session.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${session.lastUpdated.day}/${session.lastUpdated.month} '
                          '${session.lastUpdated.hour}:'
                          '${session.lastUpdated.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    onTap: () {
                      controller.selectSession(session);
                      Get.back();
                    },
                    trailing: isCurrent
                        ? Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 16)
                        : null,
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
        label: const Text('Clear All History',
            style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size(double.infinity, 50),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _showClearAllConfirmation(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Clear All History?'),
        content: const Text(
            'This will wipe your entire conversation history. '
                'This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              controller.clearAllHistory();
              Get.back();
              Get.back();
            },
            child: const Text('Clear Everything',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ThemeData theme) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment:
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.auto_awesome,
                      size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : null,
                    color: isUser
                        ? null
                        : theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomRight:
                      isUser ? const Radius.circular(4) : null,
                      bottomLeft:
                      !isUser ? const Radius.circular(4) : null,
                    ),
                  ),
                  child: message.isLoading
                      ? _buildTypingIndicator(theme)
                      : MarkdownBody(
                    data: message.content,
                    styleSheet:
                    MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(
                        color: isUser
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
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
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
            duration: 600.ms,
            delay: (index * 200).ms,
            begin: const Offset(1, 1),
            end: const Offset(1.5, 1.5),
          )
              .then()
              .scale(
            duration: 600.ms,
            begin: const Offset(1.5, 1.5),
            end: const Offset(1, 1),
          );
        }),
      ),
    );
  }
}