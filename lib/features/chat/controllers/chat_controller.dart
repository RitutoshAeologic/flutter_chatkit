import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../../core/routes/app_routes.dart';
import '../../../data/rag_models.dart';
import '../../../domain/rag_retrieval_service.dart';
import '../models/message.dart';

/// Offline extractive-RAG chat controller.
/// No Groq, no Firebase. All answers come directly from ObjectBox chunk search.
class ChatController extends GetxController {
  final RagRetrievalService _retrieval = Get.find<RagRetrievalService>();
  final _uuid = const Uuid();

  // ── Reactive state ─────────────────────────────────────────────────────────
  final messages  = <ChatMessage>[].obs;
  final isSending = false.obs;

  /// Citations map: message.id → list of citations (used by ChatScreen UI).
  final _citationsMap = <String, List<RagCitation>>{};

  // ── Public getters ─────────────────────────────────────────────────────────
  List<RagCitation>? citationsFor(String messageId) => _citationsMap[messageId];

  void clearChat() {
    messages.clear();
    _citationsMap.clear();
  }

  void goToKbManager() => Get.toNamed(AppRoutes.kbManager);

  // ── Core send logic ────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || isSending.value) return;

    // 1. Add user message
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      content: query,
      role: MessageRole.user,
      createdAt: DateTime.now(),
    );
    messages.add(userMsg);
    isSending.value = true;

    // 2. Loading placeholder
    final placeholderId = 'loading-${_uuid.v4()}';
    messages.add(ChatMessage(
      id: placeholderId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      isLoading: true,
    ));

    try {
      // 3. Retrieve relevant chunks (offline dot-product over ObjectBox)
      final sw = Stopwatch()..start();
      final result = await _retrieval.retrieve(query);
      sw.stop();
      debugPrint('ChatController: retrieve() = ${sw.elapsedMilliseconds}ms '
          '(hasContext: ${result.hasContext})');

      // 4. Format extractive answer
      final String answerText;
      if (!result.hasContext) {
        answerText = '❌ No relevant information found in your uploaded documents.\n\n'
            'Try uploading a PDF or text file related to your question using the **📚** button.';
      } else {
        final buf = StringBuffer();
        buf.writeln(
            '✅ Found **${result.citations.length}** relevant passage${result.citations.length > 1 ? 's' : ''} in your documents:\n');
        for (final c in result.citations) {
          buf.writeln('**[${c.index}] 📄 ${c.sourceLabel}** *(score: ${(c.score * 100).toStringAsFixed(1)}%)*');
          buf.writeln();
          // Find the full chunk text for this citation
          final idx = result.citations.indexOf(c);
          final blocks = result.contextBlock.split('\n\n');
          if (idx < blocks.length) {
            // Strip the "[N] label\n" header line added by retrieval service
            final lines = blocks[idx].split('\n');
            final chunkBody = lines.length > 1 ? lines.sublist(1).join('\n') : lines.first;
            buf.writeln('> $chunkBody');
          }
          buf.writeln();
        }
        answerText = buf.toString().trimRight();
      }

      final replyId = _uuid.v4();
      final reply = ChatMessage(
        id: replyId,
        content: answerText,
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );

      // Store citations for the citations row widget
      if (result.hasContext) {
        _citationsMap[replyId] = result.citations;
      }

      // 5. Replace placeholder with actual answer
      final idx = messages.indexWhere((m) => m.id == placeholderId);
      if (idx != -1) {
        messages[idx] = reply;
      } else {
        messages.add(reply);
      }
    } catch (e) {
      messages.removeWhere((m) => m.id == placeholderId);
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        content: '⚠️ Error retrieving answer: $e',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );
      messages.add(errMsg);
      debugPrint('ChatController.sendMessage error: $e');
    } finally {
      isSending.value = false;
    }
  }
}
