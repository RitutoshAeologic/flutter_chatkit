/// Single source of truth: API keys (via --dart-define), model names, URLs,
/// and all tunable thresholds. Zero logic — only constants.
class AppConfig {
  AppConfig._();

  // Groq API key — used for CHAT completions only
  // Pass via --dart-define=GROQ_API_KEY=gsk_... for production.
  static const String groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );

  // Jina AI key — used for EMBEDDINGS only (free: 1M tokens/month)
  // Get yours free at https://jina.ai → "Get API Key"
  // Pass via: flutter run --dart-define=JINA_API_KEY=jina_xxx
  static const String jinaApiKey = String.fromEnvironment(
    'JINA_API_KEY',
    defaultValue: '', // set via --dart-define only
  );


  // Groq endpoints (chat only)
  static const String chatUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // Jina embedding endpoint (replaces Groq embed — Groq removed their embedding API)
  static const String embedUrl = 'https://api.jina.ai/v1/embeddings';

  // Model identifiers
  static const String chatModel = 'llama-3.1-8b-instant'; // 5× faster than 70b, ~85% quality
  // jina-embeddings-v2-base-en → 768-dim, matches ObjectBox schema
  static const String embedModel = 'jina-embeddings-v2-base-en';

  // RAG tuning constants — change here, affects entire system
  static const double similarityThreshold = 0.35;
  static const int topKChunks = 2;           // reduced 3→2: smaller prompt = faster inference
  static const int maxContextChars = 2000;   // reduced 3200→2000: prevent prompt bloat
  static const int embeddingDimensions = 768;
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB

  // Chunking constants
  static const int chunkWordWindow = 150;
  static const int chunkWordOverlap = 30;
  static const int chunkMaxChars = 800;
  static const int chunkMinChars = 30;

  // History budget
  static const int historyMaxChars = 6000; // ~1500 tokens

  // Embedding cache
  static const int embedCacheMaxSize = 100;

  // Groq limits
  static const int embedBatchSize = 96;
  static const int embedMaxRetries = 3;
}
