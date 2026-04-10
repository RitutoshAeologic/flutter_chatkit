import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../controllers/chat_controller.dart';
import '../../../features/auth/controllers/auth_controller.dart';
import '../models/message.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = Get.find<ChatController>();
    final auth = Get.find<AuthController>();
    final scrollCtrl = ScrollController();
    final theme = Theme.of(context);

    ever(chat.messages, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollCtrl.hasClients) {
          scrollCtrl.animateTo(
            scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ChatKit AI'),
            Obx(() => chat.isLoading.value
                ? Text('AI is thinking...',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.greenAccent))
                : const SizedBox.shrink()),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Chat history',
            onPressed: () => _showHistoryDrawer(context, chat),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _showSettingsSheet(context, chat),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New conversation',
            onPressed: chat.newConversation,
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            onPressed: () => Get.find<AuthController>().signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Obx(() {
            final err = chat.error.value;
            if (err == null) return const SizedBox.shrink();
            return _ErrorBanner(
              message: err,
              onDismiss: chat.clearError,
            ).animate().slideY(begin: -1, duration: 300.ms);
          }),
          Expanded(
            child: Obx(() {
              if (chat.messages.isEmpty) {
                return _EmptyChatState();
              }
              return ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                itemCount: chat.messages.length,
                itemBuilder: (context, index) {
                  final msg = chat.messages[index];
                  if (msg.id == '__typing__') {
                    return const TypingIndicator().animate().fadeIn(duration: 200.ms);
                  }
                  return MessageBubble(
                    message: msg,
                    onRetry: msg.status == MessageStatus.failed
                        ? () => chat.retryMessage(msg.id)
                        : null,
                  ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.08, end: 0);
                },
              );
            }),
          ),
          Obx(() => ChatInputBar(
                isLoading: chat.isLoading.value,
                onSend: chat.sendMessage,
              )),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, ChatController chat) {
    Get.bottomSheet(
      _ChatSettingsSheet(controller: chat),
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  void _showHistoryDrawer(BuildContext context, ChatController chat) {
    chat.loadSessions();
    Get.bottomSheet(
      _SessionHistorySheet(controller: chat),
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;

  const MessageBubble({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;
    final isError = message.status == MessageStatus.failed;

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isError
                    ? theme.colorScheme.errorContainer
                    : isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: SelectableText(
                message.content,
                style: TextStyle(
                  color: isUser
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.4)),
                ),
                if (message.status == MessageStatus.sending) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.primary.withOpacity(0.6)),
                  ),
                ],
                if (isError && onRetry != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onRetry,
                    child: Text('Retry',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
        3,
        (i) => AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 600),
            )..repeat(
                reverse: true,
                period: Duration(milliseconds: 600 + i * 150)));
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (i) => AnimatedBuilder(
                animation: _ctrls[i],
                builder: (_, __) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(
                        0.3 + 0.5 * _ctrls[i].value),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatInputBar extends StatefulWidget {
  final bool isLoading;
  final Future<void> Function(String) onSend;

  const ChatInputBar({super.key, required this.isLoading, required this.onSend});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _ctrl = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _hasText = _ctrl.text.trim().isNotEmpty));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    if (!_hasText || widget.isLoading) return;
    final text = _ctrl.text;
    _ctrl.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
              top: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.15))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Ask anything...',
                  filled: true,
                  fillColor:
                      theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              onPressed: (_hasText && !widget.isLoading) ? _send : null,
              backgroundColor: (_hasText && !widget.isLoading)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.12),
              child: widget.isLoading
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary))
                  : Icon(Icons.send_rounded,
                      size: 18,
                      color: _hasText
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface.withOpacity(0.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_rounded,
              size: 64, color: theme.colorScheme.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('Start a conversation',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5))),
          const SizedBox(height: 8),
          Text('Powered by Free Tier AI',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.3))),
        ],
      ),
    );
  }
}

class _ChatSettingsSheet extends StatefulWidget {
  final ChatController controller;
  const _ChatSettingsSheet({required this.controller});

  @override
  State<_ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends State<_ChatSettingsSheet> {
  late TextEditingController _promptCtrl;
  late double _temp;
  late int _tokens;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _promptCtrl = TextEditingController(text: c.systemPrompt.value);
    _temp = c.temperature.value;
    _tokens = c.maxTokens.value;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      builder: (_, sc) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.all(20),
                children: [
                  Text('AI Settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  Text('System Prompt',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _promptCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        hintText: 'How should the AI behave?',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Temperature',
                          style: Theme.of(context).textTheme.labelMedium),
                      Text(_temp.toStringAsFixed(1)),
                    ],
                  ),
                  Slider(
                    value: _temp, min: 0, max: 1, divisions: 10,
                    onChanged: (v) => setState(() => _temp = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Max Tokens',
                          style: Theme.of(context).textTheme.labelMedium),
                      Text('$_tokens'),
                    ],
                  ),
                  Slider(
                    value: _tokens.toDouble(),
                    min: 64, max: 1024, divisions: 15,
                    onChanged: (v) => setState(() => _tokens = v.round()),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      widget.controller.updateSettings(
                        prompt: _promptCtrl.text,
                        temp: _temp,
                        tokens: _tokens,
                      );
                      Get.back();
                    },
                    child: const Text('Save Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionHistorySheet extends StatelessWidget {
  final ChatController controller;
  const _SessionHistorySheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, sc) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Chat History',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    controller.newConversation();
                    Get.back();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.sessionsLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.sessions.isEmpty) {
                return const Center(child: Text('No previous conversations'));
              }
              return ListView.separated(
                controller: sc,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: controller.sessions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final session = controller.sessions[i];
                  return ListTile(
                    title: Text(session.displayTitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${session.messageCount} messages'),
                    onTap: () {
                      controller.openSession(session.id);
                      Get.back();
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => controller.deleteSession(session.id),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      actions: [
        TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
      ],
    );
  }
}
