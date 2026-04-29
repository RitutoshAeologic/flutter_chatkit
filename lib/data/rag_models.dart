import '../features/chat/models/message.dart';

/// Result of a RAG retrieval pass. Passed to FactualHardeningService.
class RagRetrievalResult {
  final String contextBlock; // formatted text injected into system prompt
  final List<RagCitation> citations;
  final bool hasContext; // false → plain persona prompt used

  const RagRetrievalResult({
    required this.contextBlock,
    required this.citations,
    required this.hasContext,
  });

  const RagRetrievalResult.empty()
      : contextBlock = '',
        citations = const [],
        hasContext = false;
}

/// A single cited chunk shown to the user.
class RagCitation {
  final int index; // [1], [2], [3] — matches in-prompt numbering
  final String sourceLabel; // "report.pdf p.3" — shown in UI chip
  final double score; // cosine similarity 0.0–1.0
  final String preview; // first 90 chars of chunk text

  const RagCitation({
    required this.index,
    required this.sourceLabel,
    required this.score,
    required this.preview,
  });
}

/// Returned by InferenceRouter.query().
class RouterResponse {
  final String content; // assistant reply text
  final List<RagCitation> citations; // empty if RAG not used
  final bool usedRag;

  const RouterResponse({
    required this.content,
    required this.citations,
    required this.usedRag,
  });
}

// ── Ingestion events (sealed) ──────────────────────────────────────────────

sealed class IngestionEvent {}

class IngestionProgress extends IngestionEvent {
  final String message; // human-readable status
  final double fraction; // 0.0 – 1.0 for progress bar

  IngestionProgress({required this.message, required this.fraction});
}

class IngestionComplete extends IngestionEvent {
  final SourceDocumentData document;

  IngestionComplete({required this.document});
}

class IngestionError extends IngestionEvent {
  final String message; // shown in snackbar

  IngestionError(this.message);
}

// ── Value object mirroring SourceDocument for use in IngestionComplete ─────

/// Lightweight data class (not ObjectBox entity) used by IngestionComplete
/// so rag_models.dart doesn't import objectbox.
class SourceDocumentData {
  final String documentId;
  final String name;
  final String fileType;
  final int totalChunks;
  final int fileSizeBytes;
  final String status;
  final String createdAt;

  const SourceDocumentData({
    required this.documentId,
    required this.name,
    required this.fileType,
    required this.totalChunks,
    required this.fileSizeBytes,
    required this.status,
    required this.createdAt,
  });
}

// ── History helper ─────────────────────────────────────────────────────────

/// Converts a ChatMessage to the map format expected by the Groq API.
Map<String, String> chatMessageToApiMap(ChatMessage msg) {
  return {
    'role': msg.role == MessageRole.user ? 'user' : 'assistant',
    'content': msg.content,
  };
}
