import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';
import '../models/message.dart';
import '../../../data/rag_models.dart';
import '../../../core/routes/app_routes.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textController = TextEditingController();
    final inputText = ''.obs;
    final scrollController = ScrollController();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'DocSearch AI',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // Knowledge Base button
          IconButton(
            icon: const Icon(Icons.library_books_rounded),
            tooltip: 'Knowledge Base',
            onPressed: () => Get.toNamed(AppRoutes.kbViewer),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () {
              if (controller.messages.isNotEmpty) {
                Get.dialog(AlertDialog(
                  title: const Text('Clear chat?'),
                  actions: [
                    TextButton(onPressed: Get.back, child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        controller.clearChat();
                        Get.back();
                      },
                      child: const Text('Clear', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Info banner ──────────────────────────────────────────────────
          _OfflineBanner(theme: theme),

          // ── Messages ─────────────────────────────────────────────────────
          Expanded(
            child: Obx(() {
              if (controller.messages.isEmpty) {
                return _EmptyState(theme: theme);
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollController.hasClients) {
                  scrollController.animateTo(
                    scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: controller.messages.length,
                itemBuilder: (context, index) {
                  return _MessageBubble(
                    message: controller.messages[index],
                    theme: theme,
                    citations: controller.citationsFor(controller.messages[index].id),
                  );
                },
              );
            }),
          ),

          // ── Input bar ─────────────────────────────────────────────────────
          _InputBar(
            theme: theme,
            controller: controller,
            textController: textController,
            inputText: inputText,
          ),
        ],
      ),
    );
  }
}

// ── Offline banner ─────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final ThemeData theme;
  const _OfflineBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.offline_bolt_rounded,
              size: 14, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '100% offline · Answers extracted directly from your documents · No AI generation',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded,
                size: 80, color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            const SizedBox(height: 24),
            Text(
              'Ask your documents',
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Upload PDFs or text files via 📚, then ask questions. '
              'Answers are extracted directly from your documents — no internet required.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Get.toNamed(AppRoutes.kbViewer),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Documents'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 50)),
            ),
            const SizedBox(height: 24),
            _SampleQuestionChip(
                label: 'What is this document about?'),
            _SampleQuestionChip(
                label: 'Summarize the key findings'),
            _SampleQuestionChip(
                label: 'What are the main conclusions?'),
          ],
        ).animate().fadeIn(duration: 600.ms),
      ),
    );
  }
}

class _SampleQuestionChip extends StatelessWidget {
  final String label;
  const _SampleQuestionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ChatController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 13)),
        avatar: const Icon(Icons.lightbulb_outline, size: 16),
        onPressed: () => ctrl.sendMessage(label),
      ),
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ThemeData theme;
  final List<RagCitation>? citations;

  const _MessageBubble({
    required this.message,
    required this.theme,
    this.citations,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.search_rounded,
                      size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? LinearGradient(colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withValues(alpha: 0.85),
                          ])
                        : null,
                    color: isUser
                        ? null
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18).copyWith(
                      bottomRight:
                          isUser ? const Radius.circular(4) : null,
                      bottomLeft:
                          !isUser ? const Radius.circular(4) : null,
                    ),
                  ),
                  child: message.isLoading
                      ? _TypingIndicator(theme: theme)
                      : _MarkdownText(
                          text: message.content,
                          isUser: isUser,
                          theme: theme,
                        ),
                ),
              ),
            ],
          ),

          // Citations chip row (only for answers with sources)
          if (citations != null && citations!.isNotEmpty)
            _CitationsChips(citations: citations!, theme: theme),
        ],
      ),
    );
  }
}

/// Simple text with bold/italic parsing (avoids flutter_markdown_plus dep).
class _MarkdownText extends StatelessWidget {
  final String text;
  final bool isUser;
  final ThemeData theme;

  const _MarkdownText(
      {required this.text, required this.isUser, required this.theme});

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      style: TextStyle(
        color: isUser
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        fontSize: 15,
        height: 1.5,
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final ThemeData theme;
  const _TypingIndicator({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .scale(
                delay: (i * 200).ms,
                duration: 500.ms,
                begin: const Offset(1, 1),
                end: const Offset(1.5, 1.5))
            .then()
            .scale(
                duration: 500.ms,
                begin: const Offset(1.5, 1.5),
                end: const Offset(1, 1));
      }),
    );
  }
}

// ── Citations chip row ──────────────────────────────────────────────────────────

class _CitationsChips extends StatelessWidget {
  final List<RagCitation> citations;
  final ThemeData theme;

  const _CitationsChips(
      {required this.citations, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 40),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: citations.map((c) {
          return Chip(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            avatar: CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                '${c.index}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
            label: Text(
              '${c.sourceLabel}  ${(c.score * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 11),
            ),
            backgroundColor: theme.colorScheme.secondaryContainer
                .withValues(alpha: 0.5),
          );
        }).toList(),
      ),
    );
  }
}

// ── Input bar ──────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final ThemeData theme;
  final ChatController controller;
  final TextEditingController textController;
  final RxString inputText;

  const _InputBar({
    required this.theme,
    required this.controller,
    required this.textController,
    required this.inputText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
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
                onChanged: (v) => inputText.value = v,
                decoration: const InputDecoration(
                  hintText: 'Ask a question about your documents…',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                maxLines: 4,
                minLines: 1,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    controller.sendMessage(v);
                    textController.clear();
                    inputText.value = '';
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Obx(() => IconButton.filled(
                onPressed: controller.isSending.value ||
                        inputText.value.trim().isEmpty
                    ? null
                    : () {
                        controller.sendMessage(textController.text);
                        textController.clear();
                        inputText.value = '';
                      },
                icon: controller.isSending.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search_rounded),
                style: IconButton.styleFrom(
                    minimumSize: const Size(52, 52)),
              )),
        ],
      ),
    );
  }
}
