
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../core/app_config.dart';
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../data/object_box_store.dart';
import '../data/rag_models.dart';
import '../data/source_document.dart';
import '../domain/rag_retrieval_service.dart';
import '../objectbox.g.dart';

// ── DTOs (must be top-level and plain-Dart for compute()) ────────────────────

class AssetIsolateInput {
  final Uint8List bytes;
  final String fileName;
  AssetIsolateInput(this.bytes, this.fileName);
}

class AssetChunkData {
  final String text;
  final String sourceLabel;
  final int startOffset;
  final int chunkIndex;
  AssetChunkData(this.text, this.sourceLabel, this.startOffset, this.chunkIndex);
}

// ── Top-level isolate fn ─────────────────────────────────────────────────────

List<AssetChunkData> extractAndChunkPdf(AssetIsolateInput input) {
  final document = PdfDocument(inputBytes: input.bytes);
  final pageBuffer = StringBuffer();

  for (int i = 0; i < document.pages.count; i++) {
    final raw = PdfTextExtractor(document)
        .extractText(startPageIndex: i, endPageIndex: i);
    if (raw.trim().isEmpty) continue;

    // ── Fix: SyncFusion sometimes strips spaces between words ────────────
    // Insert space before uppercase letters following lowercase/digits,
    // before digits following letters, and normalize whitespace.
    final fixed = raw
        .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(
            RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(
            RegExp(r'(\d)([A-Za-z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    pageBuffer.write('[[PAGE ${i + 1}]] $fixed ');
  }
  document.dispose();

  final fullText = pageBuffer.toString();
  debugPrint(
      'extractAndChunkPdf: "${input.fileName}" raw chars=${fullText.length}');

  final words = fullText.split(RegExp(r'\s+'));
  int currentPage = 1;
  final chunks = <AssetChunkData>[];
  int chunkIndex = 0;
  int i = 0;

  final baseName = input.fileName.contains('.')
      ? input.fileName.substring(0, input.fileName.lastIndexOf('.'))
      : input.fileName;

  while (i < words.length) {
    final windowWords = <String>[];
    int j = i;
    while (j < words.length && windowWords.length < AppConfig.chunkWordWindow) {
      final word = words[j];
      final pageMatch = RegExp(r'\[\[PAGE (\d+)\]\]').firstMatch(word);
      if (pageMatch != null) {
        currentPage = int.parse(pageMatch.group(1)!);
      } else if (word.trim().isNotEmpty) {
        windowWords.add(word);
      }
      j++;
    }
    final chunkText = windowWords.join(' ').trim();
    if (chunkText.length >= AppConfig.chunkMinChars) {
      final truncated = chunkText.length > AppConfig.chunkMaxChars
          ? chunkText.substring(0, AppConfig.chunkMaxChars)
          : chunkText;
      chunks.add(AssetChunkData(
        truncated,
        '$baseName.pdf p.$currentPage',
        i,
        chunkIndex++,
      ));
    }
    i += AppConfig.chunkWordWindow - AppConfig.chunkWordOverlap;
    if (i <= 0) i = 1;
  }
  debugPrint(
      'extractAndChunkPdf: "${input.fileName}" → ${chunks.length} chunks');
  return chunks;
}

// ── AssetIngestionService ─────────────────────────────────────────────────────

/// Reads PDFs from assets/pdfs/, embeds via Jina, stores in ObjectBox.
/// Called once on first install. On subsequent launches, skip if already done.
class AssetIngestionService {
  final ObjectBoxStore _obx;
  final EmbeddingService _embedder;
  final RagRetrievalService _retrieval;

  AssetIngestionService({
    required ObjectBoxStore obx,
    required EmbeddingService embedder,
    required RagRetrievalService retrieval,
  })  : _obx = obx,
        _embedder = embedder,
        _retrieval = retrieval;

  /// True if at least one bundled PDF is already ingested and ready.
  bool get isAlreadyIngested {
    final q = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.fileType.equals('bundled_pdf') &
            SourceDocument_.status.equals(IngestionStatus.ready.name))
        .build();
    try {
      return q.count() > 0;
    } finally {
      q.close();
    }
  }

  /// Returns list of all bundled PDF asset paths from AssetManifest.
  Future<List<String>> _listBundledPdfs() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where((p) =>
            p.startsWith(AppConfig.pdfAssetPrefix) && p.endsWith('.pdf'))
        .toList();
  }

  /// Streams ingestion progress events for all bundled PDFs.
  /// Safe to call multiple times — skips already-ingested assets (SHA-256 dedup).
  Stream<IngestionEvent> ingestAll() async* {
    final pdfPaths = await _listBundledPdfs();

    if (pdfPaths.isEmpty) {
      yield IngestionError(
          'No PDFs found in assets/pdfs/. '
          'Add PDF files to assets/pdfs/ and declare them in pubspec.yaml.');
      return;
    }

    for (int i = 0; i < pdfPaths.length; i++) {
      final fileName = pdfPaths[i].split('/').last;
      yield IngestionProgress(
        message: 'Processing $fileName (${i + 1}/${pdfPaths.length})…',
        fraction: i / pdfPaths.length,
      );
      yield* _ingestSinglePdf(pdfPaths[i]);
    }

    _retrieval.invalidateCache();
    debugPrint('AssetIngestionService: all assets ingested ✓');
  }

  Stream<IngestionEvent> _ingestSinglePdf(String assetPath) async* {
    final fileName = assetPath.split('/').last;

    // Load bytes from bundle
    final Uint8List bytes;
    try {
      final data = await rootBundle.load(assetPath);
      bytes = data.buffer.asUint8List();
    } catch (e) {
      yield IngestionError('Could not load asset "$assetPath": $e');
      return;
    }

    // SHA-256 dedup: skip if already ingested
    final docId = sha256.convert(bytes).toString().substring(0, 16);
    if (_queryById(docId) != null) {
      debugPrint('AssetIngestionService: "$fileName" already ingested → skip');
      return;
    }

    final now = DateTime.now().toIso8601String();
    final doc = SourceDocument()
      ..documentId = docId
      ..name = fileName
      ..fileType = 'bundled_pdf'
      ..fileSizeBytes = bytes.length
      ..status = IngestionStatus.processing.name
      ..createdAt = now
      ..updatedAt = now;
    _obx.box<SourceDocument>().put(doc);

    // Extract + chunk in background isolate
    final List<AssetChunkData> chunks;
    try {
      chunks = await compute(extractAndChunkPdf, AssetIsolateInput(bytes, fileName));
    } catch (e) {
      _markFailed(doc);
      yield IngestionError('Text extraction failed for "$fileName": $e');
      return;
    }

    if (chunks.isEmpty) {
      _markFailed(doc);
      yield IngestionError(
          '"$fileName" has no extractable text. Is it a scanned PDF?');
      return;
    }

    yield IngestionProgress(
      message: 'Embedding ${chunks.length} chunks from $fileName…',
      fraction: 0.5,
    );

    // Embed all chunks via Jina
    final List<List<double>> embeddings;
    try {
      embeddings =
          await _embedder.embedBatch(chunks.map((c) => c.text).toList());
    } catch (e) {
      _markFailed(doc);
      yield IngestionError('Embedding failed for "$fileName": $e');
      return;
    }

    // Store chunks in ObjectBox
    final entities = <DocumentChunk>[];
    for (int i = 0; i < chunks.length; i++) {
      entities.add(DocumentChunk()
        ..documentId = docId
        ..sourceLabel = chunks[i].sourceLabel
        ..text = chunks[i].text
        ..startOffset = chunks[i].startOffset
        ..chunkIndex = chunks[i].chunkIndex
        ..embeddingCsv = embeddings[i].join(',')
        ..createdAt = now);
    }
    _obx.box<DocumentChunk>().putMany(entities);

    doc
      ..totalChunks = entities.length
      ..status = IngestionStatus.ready.name
      ..updatedAt = DateTime.now().toIso8601String();
    _obx.box<SourceDocument>().put(doc);

    debugPrint(
        'AssetIngestionService: "$fileName" → ${entities.length} chunks ✓');

    yield IngestionProgress(
      message: 'Indexed "$fileName" (${entities.length} chunks)',
      fraction: 1.0,
    );
  }

  SourceDocument? _queryById(String docId) {
    final q = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.documentId.equals(docId))
        .build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  void _markFailed(SourceDocument doc) {
    doc.status = IngestionStatus.failed.name;
    doc.updatedAt = DateTime.now().toIso8601String();
    _obx.box<SourceDocument>().put(doc);
  }

  /// Returns all ready bundled documents (for KbManagerScreen read-only view).
  List<SourceDocument> listReadyDocuments() {
    final q = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.fileType.equals('bundled_pdf') &
            SourceDocument_.status.equals(IngestionStatus.ready.name))
        .build();
    try {
      return q.find()
        ..sort((a, b) => a.name.compareTo(b.name));
    } finally {
      q.close();
    }
  }

  /// Clears ALL chunks + source docs from ObjectBox then re-ingests all
  /// bundled PDFs from scratch. Use when adding a new PDF or fixing extraction.
  Stream<IngestionEvent> forceReingest() async* {
    debugPrint('AssetIngestionService: force re-ingest — clearing ObjectBox…');
    _obx.box<DocumentChunk>().removeAll();
    _obx.box<SourceDocument>().removeAll();
    _retrieval.invalidateCache();
    yield IngestionProgress(message: 'Cleared old data, re-indexing…', fraction: 0.0);
    yield* ingestAll();
  }
}
