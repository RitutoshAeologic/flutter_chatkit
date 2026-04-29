import 'package:objectbox/objectbox.dart';

/// ObjectBox entity: one text chunk + its 768-dim embedding (CSV).
@Entity()
class DocumentChunk {
  @Id()
  int id = 0;

  @Index() // enables fast filter by documentId
  String documentId = ''; // SHA-256 prefix of parent SourceDocument

  String sourceLabel = ''; // "file.pdf p.3" — shown in citation chip
  String text = ''; // chunk text ≤800 chars — sent to Grok as context
  int startOffset = 0; // word index in original document
  int chunkIndex = 0; // sequential position within document
  String embeddingCsv = ''; // 768 floats joined by ','
  String createdAt = ''; // ISO-8601

  /// Transient — not persisted by ObjectBox, computed on demand.
  @Transient()
  List<double>? _cachedEmbedding;

  DocumentChunk();

  /// Deserialises embeddingCsv lazily and caches the result.
  /// Safe to call on every query — expensive parse happens only once per cache
  /// lifecycle (cache is reset when RagRetrievalService.invalidateCache() is called).
  List<double> get embedding {
    _cachedEmbedding ??= embeddingCsv.isEmpty
        ? const []
        : embeddingCsv.split(',').map(double.parse).toList();
    return _cachedEmbedding!;
  }
}
