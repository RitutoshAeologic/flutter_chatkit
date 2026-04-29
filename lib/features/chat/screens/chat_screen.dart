import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../../core/network_service.dart';
import '../controllers/chat_controller.dart';
import '../models/message.dart';
import '../../../data/rag_models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl            = Get.find<ChatController>();
  final _network         = Get.find<NetworkService>();
  final _textController  = TextEditingController();
  final _scrollController = ScrollController();
  final _inputText       = ''.obs;

  // Network state
  bool _isOnline = true;
  StreamSubscription<bool>? _networkSub;

  // Slow-response timer
  Timer? _slowTimer;
  bool _showSlowBanner = false;

  @override
  void initState() {
    super.initState();
    _checkInitialNetwork();
    _subscribeNetwork();
    _watchSending();
  }

  Future<void> _checkInitialNetwork() async {
    final online = await _network.isConnected;
    if (mounted) setState(() => _isOnline = online);
  }

  void _subscribeNetwork() {
    _networkSub = _network.onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  // Watch isSending — start a 5s timer, show "slow response" banner if still waiting
  void _watchSending() {
    ever(_ctrl.isSending, (bool sending) {
      if (sending) {
        _slowTimer?.cancel();
        _slowTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _ctrl.isSending.value) {
            setState(() => _showSlowBanner = true);
          }
        });
      } else {
        _slowTimer?.cancel();
        if (mounted) setState(() => _showSlowBanner = false);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    
    // Dismiss keyboard when sending a query
    FocusScope.of(context).unfocus();

    _ctrl.sendMessage(text);
    _textController.clear();
    _inputText.value = '';
    _scrollToBottom();
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _slowTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/svg/aeologic_logo.svg',
              height: 24,
              colorFilter: ColorFilter.mode(
                theme.colorScheme.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'DocSearch AI',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Knowledge Base',
            onPressed: () => Get.toNamed('/kb-viewer'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () {
              if (_ctrl.messages.isNotEmpty) {
                Get.dialog(AlertDialog(
                  title: const Text('Clear chat?'),
                  actions: [
                    TextButton(onPressed: Get.back, child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        _ctrl.clearChat();
                        Get.back();
                      },
                      child: const Text('Clear',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ));
              }
            },
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(), // Dismiss keyboard on tap outside
        child: Column(
          children: [
          // ── Network offline banner ──────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: !_isOnline
                ? _NetworkBanner(
                    key: const ValueKey('offline'),
                    theme: theme,
                    type: _BannerType.offline,
                  )
                : _showSlowBanner
                    ? _NetworkBanner(
                        key: const ValueKey('slow'),
                        theme: theme,
                        type: _BannerType.slow,
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
          ),

          // ── Messages ────────────────────────────────────────────────────
          Expanded(
            child: Obx(() {
              if (_ctrl.messages.isEmpty) {
                return _EmptyState(theme: theme);
              }
              _scrollToBottom();
              return ListView.builder(
                controller: _scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, // Auto dismiss keyboard on scroll
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: _ctrl.messages.length,
                itemBuilder: (context, index) {
                  return _MessageBubble(
                    message: _ctrl.messages[index],
                    theme: theme,
                    citations: _ctrl.citationsFor(_ctrl.messages[index].id),
                  );
                },
              );
            }),
          ),

          // ── Input bar ──────────────────────────────────────────────────
          _InputBar(
            theme: theme,
            controller: _ctrl,
            textController: _textController,
            inputText: _inputText,
            isOnline: _isOnline,
            onSend: _send,
          ),
        ],
      ),
      ),
    );
  }
}

// ── Network / slow banner ───────────────────────────────────────────────────────

enum _BannerType { offline, slow }

class _NetworkBanner extends StatelessWidget {
  final ThemeData theme;
  final _BannerType type;

  const _NetworkBanner({super.key, required this.theme, required this.type});

  @override
  Widget build(BuildContext context) {
    final isOffline = type == _BannerType.offline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: isOffline
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.9)
          : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.9),
      child: Row(
        children: [
          // Animated icon
          if (!isOffline)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.colorScheme.tertiary),
            )
          else
            Icon(Icons.wifi_off_rounded,
                size: 14,
                color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isOffline
                  ? 'No internet connection. Queries need a brief online moment for embedding. Check your connection.'
                  : 'Taking longer than usual… Processing your query via AI. Please wait.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isOffline
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: -1, end: 0, duration: 250.ms, curve: Curves.easeOut);
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────────

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
            SvgPicture.asset(
              'assets/svg/aeologic_logo.svg',
              height: 80,
              colorFilter: ColorFilter.mode(
                theme.colorScheme.primary.withValues(alpha: 0.2),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ask your documents',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Answers are extracted directly from your bundled documents.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 32),
          ],
        ).animate().fadeIn(duration: 600.ms),
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

          // Citations
          if (citations != null && citations!.isNotEmpty)
            _CitationsChips(citations: citations!, theme: theme),
        ],
      ),
    );
  }
}

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

// ── Citations ───────────────────────────────────────────────────────────────────

class _CitationsChips extends StatelessWidget {
  final List<RagCitation> citations;
  final ThemeData theme;

  const _CitationsChips({required this.citations, required this.theme});

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

// ── Input bar ───────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final ThemeData theme;
  final ChatController controller;
  final TextEditingController textController;
  final RxString inputText;
  final bool isOnline;
  final VoidCallback onSend;

  const _InputBar({
    required this.theme,
    required this.controller,
    required this.textController,
    required this.inputText,
    required this.isOnline,
    required this.onSend,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Offline hint above input (compact, non-blocking)
          if (!isOnline)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded,
                      size: 12,
                      color: theme.colorScheme.error.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'Offline — queries will be sent when connected',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.error.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                    border: !isOnline
                        ? Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.4),
                            width: 1)
                        : null,
                  ),
                  child: TextField(
                    controller: textController,
                    onChanged: (v) => inputText.value = v,
                    decoration: InputDecoration(
                      hintText: isOnline
                          ? 'Ask a question about your documents…'
                          : 'No connection — questions queued when online',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    maxLines: 4,
                    minLines: 1,
                    onSubmitted: (_) => onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Obx(() => IconButton.filled(
                    onPressed: controller.isSending.value ||
                            inputText.value.trim().isEmpty
                        ? null
                        : onSend,
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
        ],
      ),
    );
  }
}
