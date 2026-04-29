/// Single source of truth for all constants.
/// No Firebase, no Groq. Jina used only during ingestion for embeddings.
class AppConfig {
  AppConfig._();

  // ── Jina AI — ONLY used during document ingestion to generate embeddings ──
  // Never called during chat / answer retrieval (fully offline).
  // Get your free key at https://jina.ai
  static const String jinaApiKey = String.fromEnvironment(
    'JINA_API_KEY',
    defaultValue: '',
  );
  static const String embedUrl   = 'https://api.jina.ai/v1/embeddings';
  static const String embedModel = 'jina-embeddings-v2-base-en'; // 768-dim

  // ── RAG retrieval tuning ──────────────────────────────────────────────────
  static const double similarityThreshold = 0.35; // min cosine score to include a chunk
  static const int    topKChunks          = 3;     // max chunks returned as answer
  static const int    embeddingDimensions = 768;
  static const int    maxFileSizeBytes    = 50 * 1024 * 1024; // 50 MB

  // ── Chunking (ingestion) ──────────────────────────────────────────────────
  static const int chunkWordWindow  = 150;
  static const int chunkWordOverlap = 30;
  static const int chunkMaxChars    = 800;
  static const int chunkMinChars    = 30;

  // ── Embedding service ─────────────────────────────────────────────────────
  static const int embedCacheMaxSize = 100; // LRU slots
  static const int embedBatchSize    = 96;  // max texts per Jina request
  static const int embedMaxRetries   = 3;
}
