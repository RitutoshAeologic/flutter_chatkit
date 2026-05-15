import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../../core/network_service.dart';
import '../../../data/rag_models.dart';
import '../../../domain/user_pdf_ingestion_service.dart';
import '../controllers/chat_controller.dart';
import '../models/message.dart';

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
            ),
            const SizedBox(width: 8),
            const Text(
              'DocSearch AI',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          // Upload PDF action button
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Upload PDF',
            onPressed: () => _showUploadSheet(context),
          ),
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
        onTap: () => FocusScope.of(context).unfocus(),
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
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            onUpload: () => _showUploadSheet(context),
          ),
        ],
      ),
      ),
    );
  }

  void _showUploadSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadPdfSheet(isOnline: _isOnline),
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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/svg/aeologic_logo.svg',
              height: 80,
              // colorFilter: ColorFilter.mode(
              //   theme.colorScheme.primary.withValues(alpha: 0.2),
              //   BlendMode.srcIn,
              // ),
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
              'Answers are extracted from your knowledge base.\nTap 📎 to upload your own PDF documents.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 32),

          ],
        ).animate().fadeIn(duration: 600.ms),
      ),
    ));
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
  final VoidCallback onUpload;

  const _InputBar({
    required this.theme,
    required this.controller,
    required this.textController,
    required this.inputText,
    required this.isOnline,
    required this.onSend,
    required this.onUpload,
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
              // Attach PDF button
              IconButton(
                onPressed: onUpload,
                icon: Icon(Icons.attach_file_rounded,
                    color: theme.colorScheme.primary),
                tooltip: 'Upload PDF',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: 4),
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
                          ? 'Ask a question..'
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

// ── Upload PDF bottom sheet ─────────────────────────────────────────────────────

class _UploadPdfSheet extends StatefulWidget {
  final bool isOnline;
  const _UploadPdfSheet({required this.isOnline});

  @override
  State<_UploadPdfSheet> createState() => _UploadPdfSheetState();
}

class _UploadPdfSheetState extends State<_UploadPdfSheet> {
  final _uploader = Get.find<UserPdfIngestionService>();
  final _network  = Get.find<NetworkService>();

  _SheetState _state = _SheetState.idle;
  String _statusText = '';
  double _progress = 0.0;
  String? _errorText;
  String? _successText;
  bool _isOnline = true; // live — updated by network stream

  StreamSubscription<IngestionEvent>? _sub;
  StreamSubscription<bool>? _networkSub;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.isOnline; // seed from parent
    _networkSub = _network.onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }

  Future<void> _startUpload() async {
    if (!_isOnline) {
      setState(() {
        _errorText =
            '📵 Internet is required to embed your document.\nPlease connect and try again.';
        _state = _SheetState.error;
      });
      return;
    }

    setState(() {
      _state = _SheetState.picking;
      _errorText = null;
      _successText = null;
    });

    _sub?.cancel();
    // Track whether any event was received.
    // If the stream closes with 0 events → user dismissed the file picker.
    bool receivedEvent = false;

    _sub = _uploader.pickAndIngest().listen(
      (event) {
        if (!mounted) return;
        receivedEvent = true;
        switch (event) {
          case IngestionProgress(:final message, :final fraction):
            setState(() {
              _state = _SheetState.ingesting;
              _statusText = message;
              _progress = fraction;
            });
          case IngestionComplete():
            setState(() {
              _state = _SheetState.done;
              _successText = _statusText;
            });
          case IngestionError(:final message):
            setState(() {
              _state = _SheetState.error;
              _errorText = message;
            });
        }
      },
      onDone: () {
        // Stream finished with no events = user cancelled the file picker.
        // Go back to idle so they can tap "Choose File" again.
        if (!mounted) return;
        if (!receivedEvent) {
          setState(() => _state = _SheetState.idle);
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _state = _SheetState.error;
            _errorText = 'Unexpected error: ${e.toString()}';
          });
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Upload Document',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('PDF or TXT files up to 50 MB',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 24),

          // State content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStateContent(theme),
          ),

          const SizedBox(height: 20),

          // Action buttons
          if (_state == _SheetState.idle || _state == _SheetState.error)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _startUpload,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Choose File'),
                  ),
                ),
              ],
            ),

          if (_state == _SheetState.done)
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Get.toNamed('/kb-viewer');
                    },
                    icon: const Icon(Icons.library_books_rounded, size: 18),
                    label: const Text('View in Knowledge Base'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Done'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStateContent(ThemeData theme) {
    switch (_state) {
      case _SheetState.idle:
        return _IdleUploadContent(theme: theme);

      case _SheetState.picking:
        return _StatusContent(
          key: const ValueKey('picking'),
          theme: theme,
          icon: Icons.file_open_rounded,
          message: 'Opening file picker…',
          showProgress: false,
        );

      case _SheetState.ingesting:
        return _ProgressContent(
          key: ValueKey('ingesting-$_progress'),
          theme: theme,
          statusText: _statusText,
          progress: _progress,
        );

      case _SheetState.done:
        return _StatusContent(
          key: const ValueKey('done'),
          theme: theme,
          icon: Icons.check_circle_rounded,
          message: _successText ?? 'Document added to knowledge base!',
          isSuccess: true,
          showProgress: false,
        );

      case _SheetState.error:
        return _ErrorUploadContent(
          key: const ValueKey('error'),
          theme: theme,
          message: _errorText ?? 'An unexpected error occurred.',
        );
    }
  }
}

enum _SheetState { idle, picking, ingesting, done, error }

// ── Upload sheet sub-widgets ────────────────────────────────────────────────────

class _IdleUploadContent extends StatelessWidget {
  final ThemeData theme;
  const _IdleUploadContent({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('idle'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text('Tap "Choose File" to select a PDF or TXT',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 6),
          Text('The document will be embedded and added to your\nlocal knowledge base for searching.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 12)),
        ],
      ),
    ).animate().fadeIn();
  }
}

class _ProgressContent extends StatelessWidget {
  final ThemeData theme;
  final String statusText;
  final double progress;

  const _ProgressContent(
      {super.key,
      required this.theme,
      required this.statusText,
      required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(statusText,
            style: TextStyle(
                fontSize: 14, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 8),
        Text('${(progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600)),
      ],
    ).animate().fadeIn();
  }
}

class _StatusContent extends StatelessWidget {
  final ThemeData theme;
  final IconData icon;
  final String message;
  final bool showProgress;
  final bool isSuccess;

  const _StatusContent({
    super.key,
    required this.theme,
    required this.icon,
    required this.message,
    this.showProgress = true,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showProgress)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: theme.colorScheme.primary),
          )
        else
          Icon(icon,
              size: 24,
              color: isSuccess
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 14,
                  color: isSuccess
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    ).animate().fadeIn();
  }
}

class _ErrorUploadContent extends StatelessWidget {
  final ThemeData theme;
  final String message;

  const _ErrorUploadContent(
      {super.key, required this.theme, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.onErrorContainer)),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

