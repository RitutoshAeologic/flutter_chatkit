/// Single source of truth for all tunable constants.
/// Jina AI = embedding only (ingestion). Groq = optional response formatter.
class AppConfig {
  AppConfig._();

  // ── Jina AI — embedding only (called during ingestion, NOT during chat) ───
  static const String jinaApiKey = String.fromEnvironment(
    'JINA_API_KEY',
    defaultValue: '',
  );
  static const String embedUrl   = 'https://api.jina.ai/v1/embeddings';
  static const String embedModel = 'jina-embeddings-v2-base-en'; // 768-dim

  // ── Optional Groq — response formatter (grounded to retrieved chunks only) ─
  // true  → Groq formats the retrieved chunks into a clear, summarised answer.
  // false → raw extracted chunks shown (fully offline, no API call).
  static const bool useGroqForResponse = true;

  static const String groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
  static const String chatUrl   = 'https://api.groq.com/openai/v1/chat/completions';
  static const String chatModel = 'llama-3.3-70b-versatile'; // smarter model = better summaries

  // ── Grounded system prompt ────────────────────────────────────────────────
  // Rules:
  //  • Summarise the relevant excerpts into a clear, flowing answer.
  //  • Never use knowledge outside the provided excerpts.
  //  • If the answer is absent, say so clearly.
  static const String groqSystemPrompt =
      'You are a precise document Q&A assistant. '
      'You are given numbered excerpts from uploaded documents. '
      'Your job is to read those excerpts carefully and write a clear, '
      'concise, well-summarised answer to the user\'s question.\n\n'
      'STRICT RULES — never break these:\n'
      '1. Use ONLY information from the provided excerpts. '
      'Do NOT use any outside knowledge, training data, or general facts.\n'
      '2. Write a proper summary paragraph — not bullet dumps of raw text.\n'
      '3. Always mention which excerpt(s) you drew from, e.g. "According to [1]...".\n'
      '4. If the answer is not clearly present in the excerpts, respond EXACTLY:\n'
      '   "⚠️ I couldn\'t find this information in the uploaded documents."\n'
      '5. Never guess, infer, or extrapolate beyond what the excerpts state.\n'
      '6. Keep answers concise: 2–5 sentences unless more detail is clearly needed.';

  // ── Groq fallback prompt (used when KB has NO matching chunks) ───────────
  // When cosine similarity is below the threshold for ALL chunks,
  // Groq uses its general knowledge and clearly labels the answer.
  static const bool useGroqFallback = bool.fromEnvironment(
    'USE_GROQ_FALLBACK',
    defaultValue: true,
  );

  static const String groqFallbackSystemPrompt =
      'You are a helpful, knowledgeable AI assistant. '
      'The user asked a question and no relevant information was found in their '
      'uploaded documents. '
      'Answer the question helpfully using your general knowledge. '
      'Be concise and clear. '
      'Always end your reply with this exact line on its own:\n'
      '⚠️ *This answer comes from Groq\'s general knowledge — '
      'not from your uploaded documents.*';

  // ── RAG retrieval tuning ──────────────────────────────────────────────────
  // Raised from 0.40 → 0.75. Jina embeddings cluster heavily around 0.60-0.65
  // even for completely unrelated text (noise). A score < 0.75 is typically off-topic.
  static const double similarityThreshold  = 0.75;

  // Send top-5 chunks so Groq has rich context for summarisation.
  static const int    topKChunks           = 5;

  // Give Groq more text per chunk so it can summarise properly.
  static const int    chunkContextMaxChars = 900;

  static const int    embeddingDimensions  = 768;

  // ── Asset ingestion ───────────────────────────────────────────────────────
  static const int    maxFileSizeBytes    = 50 * 1024 * 1024;
  static const String pdfAssetPrefix     = 'assets/pdfs/';

  // ── Chunking ──────────────────────────────────────────────────────────────
  static const int chunkWordWindow  = 150;
  static const int chunkWordOverlap = 30;
  static const int chunkMaxChars    = 800;
  static const int chunkMinChars    = 30;

  // ── EmbeddingService internals ────────────────────────────────────────────
  static const int embedCacheMaxSize = 200;
  static const int embedBatchSize    = 96;
  static const int embedMaxRetries   = 3;
}
