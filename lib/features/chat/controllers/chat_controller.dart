import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/app_config.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/rag_models.dart';
import '../../../domain/rag_retrieval_service.dart';
import '../models/message.dart';

/// Offline extractive-RAG chat controller.
///
/// Query flow:
///   1. Embed query via Jina (cached)
///   2. Dot-product search over ObjectBox chunks
///   3a. [AppConfig.useGroqForResponse = false] → format extracted chunks as answer
///   3b. [AppConfig.useGroqForResponse = true]  → Groq formats the chunks into prose
///       but is strictly grounded (no external knowledge allowed via system prompt)
///   4. If no chunks found → hard "not found" reply. Groq is NEVER used as fallback.
class ChatController extends GetxController {
  final RagRetrievalService _retrieval = Get.find<RagRetrievalService>();
  final _uuid = const Uuid();

  // ── Reactive state ─────────────────────────────────────────────────────────
  final messages  = <ChatMessage>[].obs;
  final isSending = false.obs;

  final _citationsMap = <String, List<RagCitation>>{};
  List<RagCitation>? citationsFor(String id) => _citationsMap[id];

  void clearChat() {
    messages.clear();
    _citationsMap.clear();
  }

  void goToKbViewer() => Get.toNamed(AppRoutes.kbViewer);

  // ── Send ───────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || isSending.value) return;

    isSending.value = true;

    messages.add(ChatMessage(
      id: _uuid.v4(),
      content: query,
      role: MessageRole.user,
      createdAt: DateTime.now(),
    ));

    final placeholderId = 'loading-${_uuid.v4()}';
    messages.add(ChatMessage(
      id: placeholderId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      isLoading: true,
    ));

    try {
      // ── 1. Retrieve from ObjectBox (fully offline) ─────────────────────
      final sw = Stopwatch()..start();
      final result = await _retrieval.retrieve(query);
      sw.stop();
      debugPrint('ChatController: retrieve = ${sw.elapsedMilliseconds}ms '
          '(hasContext: ${result.hasContext})');

      // ── 2. No chunks found → hard cutoff, no Groq fallback ────────────
      if (!result.hasContext) {
        _replaceLoading(placeholderId, ChatMessage(
          id: _uuid.v4(),
          content:
              '❌ No relevant information found in the loaded documents.\n\n'
              'The knowledge base does not contain an answer to this question.',
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
        ));
        return;
      }

      // ── 3a. Extractive answer (default, fully offline) ─────────────────
      if (!AppConfig.useGroqForResponse) {
        final replyId = _uuid.v4();
        _citationsMap[replyId] = result.citations;
        _replaceLoading(placeholderId, ChatMessage(
          id: replyId,
          content: _formatExtractiveAnswer(result),
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
        ));
        return;
      }

      // ── 3b. Groq formatter — grounded strictly to retrieved chunks ─────
      final groqSw = Stopwatch()..start();
      final groqAnswer = await _callGroqGrounded(query, result);
      groqSw.stop();
      debugPrint('ChatController: Groq call = ${groqSw.elapsedMilliseconds}ms');

      final replyId = _uuid.v4();
      _citationsMap[replyId] = result.citations;
      _replaceLoading(placeholderId, ChatMessage(
        id: replyId,
        content: groqAnswer,
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      messages.removeWhere((m) => m.id == placeholderId);
      messages.add(ChatMessage(
        id: _uuid.v4(),
        content: '⚠️ Error: $e',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      ));
      debugPrint('ChatController.sendMessage error: $e');
    } finally {
      isSending.value = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _replaceLoading(String placeholderId, ChatMessage reply) {
    final idx = messages.indexWhere((m) => m.id == placeholderId);
    if (idx != -1) {
      messages[idx] = reply;
    } else {
      messages.add(reply);
    }
  }

  String _formatExtractiveAnswer(RagRetrievalResult result) {
    final buf = StringBuffer();
    buf.writeln(
        '✅ Found **${result.citations.length}** relevant passage${result.citations.length > 1 ? 's' : ''}:\n');
    for (final c in result.citations) {
      buf.writeln('**[${c.index}] 📄 ${c.sourceLabel}**');
      buf.writeln();
      // Extract the chunk body from the context block
      final blocks = result.contextBlock.split('\n\n');
      if (c.index - 1 < blocks.length) {
        final lines = blocks[c.index - 1].split('\n');
        final body =
            lines.length > 1 ? lines.sublist(1).join('\n') : lines.first;
        buf.writeln('> $body');
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  /// Calls Groq with retrieved chunks as the ONLY context source.
  /// The system prompt forbids Groq from using external knowledge.
  Future<String> _callGroqGrounded(
      String query, RagRetrievalResult result) async {
    if (AppConfig.groqApiKey.isEmpty) {
      throw Exception(
          'GROQ_API_KEY not set. Pass via --dart-define=GROQ_API_KEY=gsk_...');
    }

    final contextBlock = result.contextBlock; // already formatted with source labels
    final userMessage = '''
=== DOCUMENT EXCERPTS (your ONLY allowed source) ===

$contextBlock

=== END OF EXCERPTS ===

Using ONLY the excerpts above (do not use any outside knowledge), please answer this question in a clear, friendly, and concise way:

$query

Remember: if the answer is not in the excerpts, say exactly "I couldn't find this information in the loaded documents."
''';

    final messages = [
      {'role': 'system', 'content': AppConfig.groqSystemPrompt},
      {
        'role': 'user',
        'content': userMessage,
      },
    ];

    final response = await http.post(
      Uri.parse(AppConfig.chatUrl),
      headers: {
        'Authorization': 'Bearer ${AppConfig.groqApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': AppConfig.chatModel,
        'messages': messages,
        'max_tokens': 512,
        'temperature': 0.1, // low temp = more faithful to context
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Groq API ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (data['choices'] as List).first['message']['content'] as String;

    final usage = data['usage'] as Map<String, dynamic>?;
    if (usage != null) {
      debugPrint('ChatController: Groq tokens → '
          'prompt=${usage['prompt_tokens']} '
          'completion=${usage['completion_tokens']}');
    }

    return content.trim();
  }
}
