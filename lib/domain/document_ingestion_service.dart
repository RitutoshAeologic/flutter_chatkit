import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/app_config.dart';
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../data/object_box_store.dart';
import '../data/rag_models.dart';
import '../data/source_document.dart';
import '../objectbox.g.dart';
import 'rag_retrieval_service.dart';

// ── Isolate data transfer objects ────────────────────────────────────────────

class _IsolateInput {
  final Uint8List bytes;
  final String fileType; // 'pdf' | 'txt'
  final String fileName;
  _IsolateInput(this.bytes, this.fileType, this.fileName);
}

class _ChunkData {
  final String text;
  final String sourceLabel;
  final int startOffset;
  final int chunkIndex;
  _ChunkData(this.text, this.sourceLabel, this.startOffset, this.chunkIndex);
}

// ── Top-level isolate function (must be top-level for compute()) ──────────────

List<_ChunkData> _extractAndChunkInIsolate(_IsolateInput input) {
  String fullText;

  if (input.fileType == 'pdf') {
    final document = PdfDocument(inputBytes: input.bytes);
    final buffer = StringBuffer();
    for (int i = 0; i < document.pages.count; i++) {
      final pageText =
          PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);
      if (pageText.trim().isNotEmpty) {
        buffer.write('[[PAGE ${i + 1}]] $pageText ');
      }
    }
    document.dispose();
    fullText = buffer.toString();
  } else {
    fullText = utf8.decode(input.bytes, allowMalformed: true);
  }

  // Sliding-window chunker
  final words = fullText.split(RegExp(r'\s+'));
  int currentPage = 1;
  final chunks = <_ChunkData>[];
  int chunkIndex = 0;

  int i = 0;
  while (i < words.length) {
    final windowWords = <String>[];
    int j = i;

    while (j < words.length && windowWords.length < AppConfig.chunkWordWindow) {
      final word = words[j];
      // Track page markers but strip them from chunk text
      final pageMatch = RegExp(r'\[\[PAGE (\d+)\]\]').firstMatch(word);
      if (pageMatch != null) {
        currentPage = int.parse(pageMatch.group(1)!);
      } else {
        windowWords.add(word);
      }
      j++;
    }

    final chunkText = windowWords.join(' ').trim();

    if (chunkText.length >= AppConfig.chunkMinChars) {
      final truncated = chunkText.length > AppConfig.chunkMaxChars
          ? chunkText.substring(0, AppConfig.chunkMaxChars)
          : chunkText;

      final baseName = input.fileName.contains('.')
          ? input.fileName.substring(0, input.fileName.lastIndexOf('.'))
          : input.fileName;
      final ext = input.fileName.contains('.')
          ? input.fileName.substring(input.fileName.lastIndexOf('.') + 1)
          : '';

      chunks.add(_ChunkData(
        truncated,
        '$baseName.$ext p.$currentPage',
        i,
        chunkIndex++,
      ));
    }

    // Advance by window - overlap
    i += AppConfig.chunkWordWindow - AppConfig.chunkWordOverlap;
    if (i <= 0) i = 1; // safety: never loop forever
  }

  return chunks;
}

// ── DocumentIngestionService ──────────────────────────────────────────────────

/// Full ingestion pipeline: FilePicker → dedup → compute() isolate → embedBatch → putMany.
/// Yields IngestionEvent stream. Calls retrieval.invalidateCache() after every write.
class DocumentIngestionService {
  final ObjectBoxStore _obx;
  final EmbeddingService _embedder;
  final RagRetrievalService _retrieval;

  DocumentIngestionService({
    required ObjectBoxStore obx,
    required EmbeddingService embedder,
    required RagRetrievalService retrieval,
  })  : _obx = obx,
        _embedder = embedder,
        _retrieval = retrieval;

  /// Opens FilePicker, then runs the full ingestion pipeline as a Stream.
  Stream<IngestionEvent> pickAndIngest() async* {
    // ── Step 1: Pick file ──────────────────────────────────────────────────
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
      withData: true,
      allowMultiple: false,
    );

    final file = result?.files.first;
    if (file == null) return; // user cancelled

    // ── O8: File size guard before using bytes ─────────────────────────────
    if (file.size > AppConfig.maxFileSizeBytes) {
      yield IngestionError(
        'File too large (${(file.size / 1048576).toStringAsFixed(1)} MB). '
        'Maximum is ${AppConfig.maxFileSizeBytes ~/ 1048576} MB.',
      );
      return;
    }

    final bytes = file.bytes;
    if (bytes == null) {
      yield IngestionError('Could not read file bytes. Try again.');
      return;
    }

    final fileType = file.extension?.toLowerCase() ?? 'txt';
    final fileName = file.name;

    // ── Step 2: SHA-256 dedup ──────────────────────────────────────────────
    final hash = sha256.convert(bytes);
    final documentId = hash.toString().substring(0, 16);

    final existing = _querySourceDocById(documentId);
    if (existing != null) {
      yield IngestionError('"$fileName" is already in your knowledge base.');
      return;
    }

    // ── Step 3: Create SourceDocument (status: processing) ─────────────────
    final now = DateTime.now().toIso8601String();
    final sourceDoc = SourceDocument()
      ..documentId = documentId
      ..name = fileName
      ..fileType = fileType
      ..fileSizeBytes = bytes.length
      ..status = IngestionStatus.processing.name
      ..createdAt = now
      ..updatedAt = now;
    _obx.box<SourceDocument>().put(sourceDoc);

    yield IngestionProgress(message: 'Extracting text…', fraction: 0.10);

    // ── Step 4: Extract + chunk in background isolate ──────────────────────
    final List<_ChunkData> rawChunks;
    try {
      rawChunks = await compute(
        _extractAndChunkInIsolate,
        _IsolateInput(bytes, fileType, fileName),
      );
    } catch (e) {
      _markFailed(sourceDoc);
      yield IngestionError('Text extraction failed: $e');
      return;
    }

    if (rawChunks.isEmpty) {
      _markFailed(sourceDoc);
      yield IngestionError(
          'No text could be extracted from "$fileName". Is it a scanned PDF?');
      return;
    }

    yield IngestionProgress(
        message: 'Embedding ${rawChunks.length} chunks…', fraction: 0.35);

    // ── Step 5: Embed all chunks in one call (O6) ──────────────────────────
    final List<List<double>> allEmbeddings;
    try {
      allEmbeddings = await _embedder.embedBatch(
        rawChunks.map((c) => c.text).toList(),
      );
    } catch (e) {
      _markFailed(sourceDoc);
      yield IngestionError('Embedding failed: $e');
      return;
    }

    if (allEmbeddings.length != rawChunks.length) {
      _markFailed(sourceDoc);
      yield IngestionError('Embedding count mismatch. Please retry.');
      return;
    }

    yield IngestionProgress(message: 'Saving to database…', fraction: 0.90);

    // ── Step 6: Build DocumentChunk list + putMany (O7) ───────────────────
    final chunkEntities = <DocumentChunk>[];
    for (int i = 0; i < rawChunks.length; i++) {
      final c = rawChunks[i];
      final entity = DocumentChunk()
        ..documentId = documentId
        ..sourceLabel = c.sourceLabel
        ..text = c.text
        ..startOffset = c.startOffset
        ..chunkIndex = c.chunkIndex
        ..embeddingCsv = allEmbeddings[i].join(',')
        ..createdAt = now;
      chunkEntities.add(entity);
    }
    // Single transaction — fast (O7)
    _obx.box<DocumentChunk>().putMany(chunkEntities);

    // ── Step 7: Finalise SourceDocument ────────────────────────────────────
    sourceDoc.totalChunks = chunkEntities.length;
    sourceDoc.status = IngestionStatus.ready.name;
    sourceDoc.updatedAt = DateTime.now().toIso8601String();
    _obx.box<SourceDocument>().put(sourceDoc);

    // ── Step 8: Invalidate retrieval cache ─────────────────────────────────
    _retrieval.invalidateCache();

    yield IngestionProgress(message: 'Done!', fraction: 1.0);
    yield IngestionComplete(
      document: SourceDocumentData(
        documentId: sourceDoc.documentId,
        name: sourceDoc.name,
        fileType: sourceDoc.fileType,
        totalChunks: sourceDoc.totalChunks,
        fileSizeBytes: sourceDoc.fileSizeBytes,
        status: sourceDoc.status,
        createdAt: sourceDoc.createdAt,
      ),
    );
  }

  /// Returns all SourceDocuments sorted by createdAt descending.
  List<SourceDocument> listDocuments() {
    final docs = _obx.box<SourceDocument>().getAll();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  /// Removes all DocumentChunks + the SourceDocument for this [documentId].
  /// All ObjectBox queries closed in try/finally (M1 fix).
  Future<void> deleteDocument(String documentId) async {
    // Delete chunks
    final chunkQuery = _obx
        .box<DocumentChunk>()
        .query(DocumentChunk_.documentId.equals(documentId))
        .build();
    try {
      final chunkIds = chunkQuery.findIds();
      _obx.box<DocumentChunk>().removeMany(chunkIds);
    } finally {
      chunkQuery.close();
    }

    // Delete source document
    final docQuery = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.documentId.equals(documentId))
        .build();
    try {
      final docIds = docQuery.findIds();
      _obx.box<SourceDocument>().removeMany(docIds);
    } finally {
      docQuery.close();
    }

    _retrieval.invalidateCache();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  SourceDocument? _querySourceDocById(String documentId) {
    final q = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.documentId.equals(documentId))
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

  /// Removes all documents stuck in `processing` or `failed` state,
  /// along with any orphaned chunks. Call this on app startup or from UI.
  Future<int> cleanupStaleDocuments() async {
    int removed = 0;

    // Find all processing + failed docs
    final staleQ = _obx
        .box<SourceDocument>()
        .query(
          SourceDocument_.status.equals(IngestionStatus.processing.name).or(
                SourceDocument_.status.equals(IngestionStatus.failed.name),
              ),
        )
        .build();

    final List<SourceDocument> staleDocs;
    try {
      staleDocs = staleQ.find();
    } finally {
      staleQ.close();
    }

    for (final doc in staleDocs) {
      // Remove orphaned chunks
      final chunkQ = _obx
          .box<DocumentChunk>()
          .query(DocumentChunk_.documentId.equals(doc.documentId))
          .build();
      try {
        _obx.box<DocumentChunk>().removeMany(chunkQ.findIds());
      } finally {
        chunkQ.close();
      }

      // Remove the stale doc record
      final docQ = _obx
          .box<SourceDocument>()
          .query(SourceDocument_.documentId.equals(doc.documentId))
          .build();
      try {
        _obx.box<SourceDocument>().removeMany(docQ.findIds());
      } finally {
        docQ.close();
      }

      removed++;
      debugPrint(
          'DocumentIngestionService: cleaned up stale doc "${doc.name}" (${doc.status})');
    }

    if (removed > 0) _retrieval.invalidateCache();
    return removed;
  }
}
