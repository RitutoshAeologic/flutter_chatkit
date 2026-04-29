import '../data/rag_models.dart';

/// Pure prompt builder — no I/O, no network, no GetX state.
/// Takes a [RagRetrievalResult] and returns the system prompt string to send
/// to the Grok API. Imports only rag_models.dart (M4 fix).
class FactualHardeningService {
  const FactualHardeningService();

  /// Returns a RAG-augmented system prompt when [result.hasContext] is true,
  /// otherwise returns the plain persona prompt.
  String buildSystemPrompt(RagRetrievalResult result) {
    if (!result.hasContext) {
      return _plainPersona;
    }

    return '''$_plainPersona

VERIFIED FACTS — use these as your primary source of truth when answering:

${result.contextBlock}

Instructions:
- Ground your answer in the VERIFIED FACTS above wherever relevant.
- Cite sources using their bracketed number, e.g. [1], [2].
- If the facts do not cover the question, say so and answer from general knowledge.
- Do not fabricate citations that are not in the VERIFIED FACTS block.
''';
  }

  static const String _plainPersona =
      'You are ChatKit AI, a premium and helpful assistant. '
      'Keep responses helpful, accurate, and formatted with markdown.';
}
