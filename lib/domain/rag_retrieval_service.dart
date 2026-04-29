import 'package:flutter/foundation.dart';
import '../core/app_config.dart';
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../data/object_box_store.dart';
import '../data/rag_models.dart';
import '../data/source_document.dart';
import '../objectbox.g.dart';

/// Vector search over locally-stored document chunks.
/// Embeds the query → loads chunk cache → dot-product cosine → filter → top-K.
class RagRetrievalService {
  final ObjectBoxStore _obx;
  final EmbeddingService _embedder;

  // O1: Chunk cache with explicit invalidation
  List<DocumentChunk>? _chunkCache;

  RagRetrievalService({required ObjectBoxStore obx, required EmbeddingService embedder})
      : _obx = obx,
        _embedder = embedder;

  /// Main retrieval entry point.
  Future<RagRetrievalResult> retrieve(String query) async {
    final totalSw = Stopwatch()..start();

    // O3: Early exit when no ready documents — free count, no data loaded
    final countSw = Stopwatch()..start();
    final readyCount = _readyDocumentCount();
    countSw.stop();
    if (readyCount == 0) {
      debugPrint('RagRetrievalService: 0 ready docs → early exit (${countSw.elapsedMilliseconds}ms)');
      return const RagRetrievalResult.empty();
    }
    debugPrint('RagRetrievalService: ready-doc count check = ${countSw.elapsedMilliseconds}ms');

    // Embed query (uses LRU cache in EmbeddingService)
    final queryVec = await _embedder.embed(query);

    // O1: Load chunk cache lazily; only reload after invalidateCache()
    if (_chunkCache == null) {
      final cacheSw = Stopwatch()..start();
      _chunkCache = _loadReadyChunks();
      cacheSw.stop();
      debugPrint(
          'RagRetrievalService: loaded ${_chunkCache!.length} chunks from ObjectBox in ${cacheSw.elapsedMilliseconds}ms');
    } else {
      debugPrint('RagRetrievalService: chunk cache HIT (${_chunkCache!.length} chunks)');
    }

    if (_chunkCache!.isEmpty) return const RagRetrievalResult.empty();

    // Dot-product cosine similarity
    final dotSw = Stopwatch()..start();
    final scored = <({DocumentChunk chunk, double score})>[];
    for (final chunk in _chunkCache!) {
      final emb = chunk.embedding;
      if (emb.length != queryVec.length) continue;
      double dot = 0.0;
      for (int i = 0; i < emb.length; i++) {
        dot += emb[i] * queryVec[i];
      }
      if (dot >= AppConfig.similarityThreshold) {
        scored.add((chunk: chunk, score: dot));
      }
    }
    dotSw.stop();
    debugPrint(
        'RagRetrievalService: dot-product on ${_chunkCache!.length} chunks = ${dotSw.elapsedMilliseconds}ms → ${scored.length} above threshold');

    if (scored.isEmpty) {
      totalSw.stop();
      debugPrint('RagRetrievalService: no chunks above threshold — total ${totalSw.elapsedMilliseconds}ms');
      return const RagRetrievalResult.empty();
    }

    // Sort descending by score, take top-K chunks for context richness
    scored.sort((a, b) => b.score.compareTo(a.score));
    final topChunks = scored.take(AppConfig.topKChunks).toList();

    // Build context block (ALL top-K chunks sent to Groq for rich context)
    final contextLines = <String>[];
    for (int i = 0; i < topChunks.length; i++) {
      contextLines.add('[${i + 1}] ${topChunks[i].chunk.sourceLabel}\n${topChunks[i].chunk.text}');
      debugPrint('RagRetrievalService: [${i + 1}] "${topChunks[i].chunk.sourceLabel}" '
          'score=${topChunks[i].score.toStringAsFixed(3)} '
          'text_preview="${topChunks[i].chunk.text.substring(0, topChunks[i].chunk.text.length.clamp(0, 80))}"');
    }
    final contextBlock = contextLines.join('\n\n');

    // Build citations for UI — dedup by documentId (show each source only once,
    // using the highest-scoring chunk as representative)
    final seenDocIds = <String>{};
    final citations = <RagCitation>[];
    int citIdx = 1;
    for (final item in topChunks) {
      if (seenDocIds.add(item.chunk.documentId)) {
        final preview = item.chunk.text.length > 120
            ? '${item.chunk.text.substring(0, 120)}…'
            : item.chunk.text;
        citations.add(RagCitation(
          index: citIdx++,
          sourceLabel: item.chunk.sourceLabel,
          score: item.score,
          preview: preview,
        ));
      }
    }

    totalSw.stop();
    debugPrint('RagRetrievalService: retrieve() TOTAL = ${totalSw.elapsedMilliseconds}ms '
        '(${topChunks.length} chunks → ${citations.length} unique sources)');

    return RagRetrievalResult(
      contextBlock: contextBlock,
      citations: citations,
      hasContext: true,
    );
  }

  /// Called by DocumentIngestionService after any write/delete.
  void invalidateCache() {
    _chunkCache = null;
    debugPrint('RagRetrievalService: cache invalidated');
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  int _readyDocumentCount() {
    final q = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.status.equals(IngestionStatus.ready.name))
        .build();
    try {
      return q.count();
    } finally {
      q.close();
    }
  }

  List<DocumentChunk> _loadReadyChunks() {
    final docQ = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.status.equals(IngestionStatus.ready.name))
        .build();
    final List<String> readyDocIds;
    try {
      readyDocIds = docQ.find().map((d) => d.documentId).toList();
    } finally {
      docQ.close();
    }

    if (readyDocIds.isEmpty) return [];

    final allChunks = _obx.box<DocumentChunk>().getAll();
    return allChunks.where((c) => readyDocIds.contains(c.documentId)).toList();
  }
}
