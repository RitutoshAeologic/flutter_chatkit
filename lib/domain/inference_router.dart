import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/app_exceptions.dart';
import '../data/rag_models.dart';
import '../features/chat/models/message.dart';
import 'factual_hardening_service.dart';
import 'rag_retrieval_service.dart';

/// Orchestrates RAG retrieval → prompt hardening → Grok API call.
/// Single owner of the Grok chat completions URL and model name.
class InferenceRouter {
  final RagRetrievalService _retrieval;
  final FactualHardeningService _hardening;

  InferenceRouter({
    required RagRetrievalService retrieval,
    required FactualHardeningService hardening,
  })  : _retrieval = retrieval,
        _hardening = hardening;

  /// Main query entry point.
  /// [history] must already be budgeted by the caller (ChatController._budgetedHistory).
  /// RAG failures degrade gracefully — chat always continues (Section 9 contract).
  Future<RouterResponse> query(
    String text, {
    List<ChatMessage> history = const [],
  }) async {
    final totalSw = Stopwatch()..start();

    // O4: Skip RAG for trivial messages (< 3 words OR < 12 chars)
    RagRetrievalResult ragResult = const RagRetrievalResult.empty();
    try {
      if (_isRagCandidate(text)) {
        final ragSw = Stopwatch()..start();
        ragResult = await _retrieval.retrieve(text);
        ragSw.stop();
        debugPrint('InferenceRouter: RAG retrieve = ${ragSw.elapsedMilliseconds}ms (hasContext: ${ragResult.hasContext})');
      } else {
        debugPrint('InferenceRouter: skipping RAG (short query)');
      }
    } on EmbeddingException catch (e) {
      debugPrint('InferenceRouter: RAG retrieval failed, degrading: $e');
    }

    final systemPrompt = _hardening.buildSystemPrompt(ragResult);
    debugPrint('InferenceRouter: system prompt = ${systemPrompt.length} chars');

    // Build message list: [system, ...history, user]
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      for (final msg in history)
        if (!msg.isLoading)
          {
            'role': msg.role == MessageRole.user ? 'user' : 'assistant',
            'content': msg.content,
          },
      {'role': 'user', 'content': text},
    ];

    final groqSw = Stopwatch()..start();
    final response = await http.post(
      Uri.parse(AppConfig.chatUrl),
      headers: {
        'Authorization': 'Bearer ${AppConfig.groqApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': AppConfig.chatModel,
        'messages': messages,
        'max_tokens': 512,   // O-NEW-5: reduced from 1024 → ~200-400ms faster
        'temperature': 0.7,
      }),
    );
    groqSw.stop();
    debugPrint('InferenceRouter: Groq chat API = ${groqSw.elapsedMilliseconds}ms');

    if (response.statusCode != 200) {
      throw RouterException(
        'Grok API returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (data['choices'] as List).first['message']['content'] as String;

    // Log token usage for cost/latency profiling
    final usage = data['usage'] as Map<String, dynamic>?;
    if (usage != null) {
      debugPrint('InferenceRouter: tokens — '
          'prompt=${usage['prompt_tokens']} '
          'completion=${usage['completion_tokens']} '
          'total=${usage['total_tokens']}');
    }

    totalSw.stop();
    debugPrint('InferenceRouter: TOTAL pipeline = ${totalSw.elapsedMilliseconds}ms '  
        '(RAG + embed + Groq)');

    return RouterResponse(
      content: content,
      citations: ragResult.citations,
      usedRag: ragResult.hasContext,
    );
  }

  /// Fire-and-forget title generation. Returns null on any failure.
  Future<String?> generateTitle(String firstUserMessage) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.chatUrl),
        headers: {
          'Authorization': 'Bearer ${AppConfig.groqApiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': AppConfig.chatModel,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Summarize the user request into a 3-5 word title. Return ONLY the title text.',
            },
            {'role': 'user', 'content': firstUserMessage},
          ],
          'max_tokens': 15,
        }),
      );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final title = (data['choices'] as List).first['message']['content']
          .toString()
          .replaceAll('"', '')
          .trim();
      return title.isNotEmpty ? title : null;
    } catch (e) {
      debugPrint('InferenceRouter.generateTitle failed: $e');
      return null;
    }
  }

  // O4: Skip RAG for trivial messages — must pass BOTH conditions
  bool _isRagCandidate(String query) {
    final trimmed = query.trim();
    return trimmed.split(' ').length >= 3 && trimmed.length >= 12;
  }
}
