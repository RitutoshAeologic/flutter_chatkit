/// Single source of truth for all tunable constants.
/// Jina AI = embedding only (ingestion). Groq = optional response formatter.
class AppConfig {
  AppConfig._();

  // ── Jina AI — embedding only (called during ingestion, NOT during chat) ───
  static const String jinaApiKey = String.fromEnvironment(
    'JINA_API_KEY',
    defaultValue: 'jina_ec89226c13254adf834fe581502ad6e6CXia9f6ZFPgVeprjrAySnnInvuZo',
  );
  static const String embedUrl   = 'https://api.jina.ai/v1/embeddings';
  static const String embedModel = 'jina-embeddings-v2-base-en'; // 768-dim

  // ── Optional Groq — response formatter (grounded to retrieved chunks only) ─
  // true  → Groq formats the retrieved chunks into natural-language prose.
  // false → raw extracted chunks shown (fully offline, no API call).
  // IMPORTANT: Groq is NEVER called when no chunks are found (hard cutoff).
  static const bool useGroqForResponse = true; // ← enabled for user-friendly answers

  static const String groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '', // inject via: --dart-define=GROQ_API_KEY=gsk_...
  );
  static const String chatUrl   = 'https://api.groq.com/openai/v1/chat/completions';
  static const String chatModel = 'llama-3.1-8b-instant';

  // ── Strict grounding system prompt ────────────────────────────────────────
  // This prompt PREVENTS Groq from using its own training knowledge.
  // Every answer must be traceable to the provided document excerpts.
  static const String groqSystemPrompt =
      'You are a document Q\u0026A assistant with access ONLY to the excerpts below. '
      'Rules you must NEVER break:\n'
      '1. Answer ONLY from the provided excerpts. Zero exceptions.\n'
      '2. Do NOT use any external knowledge, training data, or general facts.\n'
      '3. If the answer is not clearly stated in the excerpts, respond EXACTLY: '
      '"I couldn\'t find this information in the loaded documents."\n'
      '4. Never infer, guess, or extrapolate beyond what the excerpts say.\n'
      '5. Always cite the source label (e.g. [1], [2]) for every fact you state.\n'
      '6. Write in clear, friendly, plain language — summarise the excerpt naturally.\n'
      'Excerpts are labelled [1], [2], etc. with their source file.\n'
      'Begin every response by citing which excerpt(s) you are drawing from.';

  // ── RAG retrieval tuning ──────────────────────────────────────────────────
  static const double similarityThreshold  = 0.25;  // wider net for short queries
  static const int    topKChunks           = 3;     // 5→3: ~850 Groq prompt tokens vs 1400
  static const int    chunkContextMaxChars = 600;   // trim chunks before sending to Groq
  static const int    embeddingDimensions  = 768;

  // ── Asset ingestion ───────────────────────────────────────────────────────
  static const int    maxFileSizeBytes    = 50 * 1024 * 1024;
  static const String pdfAssetPrefix     = 'assets/pdfs/'; // all bundled PDFs live here

  // ── Chunking ──────────────────────────────────────────────────────────────
  static const int chunkWordWindow  = 150;
  static const int chunkWordOverlap = 30;
  static const int chunkMaxChars    = 800;
  static const int chunkMinChars    = 30;

  // ── EmbeddingService internals ────────────────────────────────────────────
  static const int embedCacheMaxSize = 200; // increased: covers more repeat queries
  static const int embedBatchSize    = 96;
  static const int embedMaxRetries   = 3;
}
