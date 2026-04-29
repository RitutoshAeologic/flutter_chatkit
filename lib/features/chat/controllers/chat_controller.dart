import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/app_config.dart';
import '../../../core/network_service.dart';
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
      debugPrint('ChatController: sending ${result.citations.length} chunks to Groq');
      debugPrint('ChatController: contextBlock=\n${result.contextBlock}');
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
      // Classify the error so users see a meaningful message, not a stack dump
      final errType = NetworkService.classify(e);
      final userMsg = switch (errType) {
        NetworkErrorType.noInternet =>
          '📵 No internet connection.\n\nYour question needs to be embedded via '
          'Jina AI first. Please check your connection and try again.',
        NetworkErrorType.timeout =>
          '⏱ The server took too long to respond. Please try again.',
        NetworkErrorType.authError =>
          '🔑 API key error. Contact the app developer.',
        NetworkErrorType.rateLimited =>
          '⏳ Too many requests. Please wait a moment and try again.',
        NetworkErrorType.serverError =>
          '🌐 The AI server is temporarily down. Please try again later.',
        NetworkErrorType.unknown =>
          '⚠️ Something went wrong. Please try again.'
      };
      _replaceLoading(placeholderId, ChatMessage(
        id: _uuid.v4(),
        content: userMsg,
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      ));
      debugPrint('ChatController.sendMessage error (${errType.name}): $e');
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
      // No Groq key — fall back to extractive answer gracefully
      debugPrint('ChatController: GROQ_API_KEY not set → falling back to extractive');
      return _formatExtractiveAnswer(result);
    }

    final contextBlock = result.contextBlock;

    // Trim each chunk to chunkContextMaxChars to reduce Groq prompt tokens.
    // Fewer tokens = faster response. The most relevant sentence is usually
    // near the start of a chunk (highest-scoring match).
    final trimmedBlock = contextBlock.split('\n\n').map((block) {
      final lines = block.split('\n');
      if (lines.length < 2) return block;
      final header = lines.first; // "[N] filename p.X"
      final body   = lines.sublist(1).join('\n');
      final trimmed = body.length > AppConfig.chunkContextMaxChars
          ? '${body.substring(0, AppConfig.chunkContextMaxChars)}…'
          : body;
      return '$header\n$trimmed';
    }).join('\n\n');

    final userMessage = '''
=== DOCUMENT EXCERPTS (your ONLY allowed source) ===

$trimmedBlock

=== END OF EXCERPTS ===

Using ONLY the excerpts above (do not use any outside knowledge), answer concisely:

$query

If the answer is not in the excerpts, say exactly "I couldn't find this information in the loaded documents."
''';

    final groqMessages = [
      {'role': 'system', 'content': AppConfig.groqSystemPrompt},
      {'role': 'user', 'content': userMessage},
    ];

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(AppConfig.chatUrl),
            headers: {
              'Authorization': 'Bearer ${AppConfig.groqApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': AppConfig.chatModel,
              'messages': groqMessages,
              'max_tokens': 512,
              'temperature': 0.1,
            }),
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
                'Groq timed out', const Duration(seconds: 20)),
          );
    } on SocketException {
      throw Exception(NetworkService.messageFor(NetworkErrorType.noInternet));
    } on TimeoutException {
      throw Exception(NetworkService.messageFor(NetworkErrorType.timeout));
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(NetworkService.messageFor(NetworkErrorType.authError));
    }
    if (response.statusCode == 429) {
      throw Exception(NetworkService.messageFor(NetworkErrorType.rateLimited));
    }
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
