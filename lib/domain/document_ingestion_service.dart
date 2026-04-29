import 'dart:async';

import 'package:crypto/crypto.dart';
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

// ── DTOs (top-level, plain Dart — required for compute()) ────────────────────

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

// ── Top-level isolate fn ─────────────────────────────────────────────────────

List<_ChunkData> _extractAndChunkInIsolate(_IsolateInput input) {
  final baseName = input.fileName.contains('.')
      ? input.fileName.substring(0, input.fileName.lastIndexOf('.'))
      : input.fileName;

  String fullText;
  if (input.fileType == 'pdf') {
    final document = PdfDocument(inputBytes: input.bytes);
    final buf = StringBuffer();
    int currentPage = 1;
    for (int i = 0; i < document.pages.count; i++) {
      final text = PdfTextExtractor(document)
          .extractText(startPageIndex: i, endPageIndex: i);
      if (text.trim().isNotEmpty) buf.write('[[PAGE ${i + 1}]] $text ');
    }
    document.dispose();
    fullText = buf.toString();
  } else {
    fullText = String.fromCharCodes(input.bytes);
  }

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
      chunks.add(_ChunkData(truncated, '$baseName p.$currentPage', i, chunkIndex++));
    }
    i += AppConfig.chunkWordWindow - AppConfig.chunkWordOverlap;
    if (i <= 0) i = 1;
  }
  return chunks;
}

// ── DocumentIngestionService ─────────────────────────────────────────────────
// NOTE: User file upload is removed. Ingestion is now handled by
// AssetIngestionService which reads PDFs from assets/pdfs/ at first launch.
// This service is kept for its cleanup/delete utility methods.

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

  /// Returns all SourceDocuments sorted by name.
  List<SourceDocument> listDocuments() {
    final docs = _obx.box<SourceDocument>().getAll();
    docs.sort((a, b) => a.name.compareTo(b.name));
    return docs;
  }

  /// Removes a document and all its chunks.
  Future<void> deleteDocument(String documentId) async {
    final chunkQ = _obx
        .box<DocumentChunk>()
        .query(DocumentChunk_.documentId.equals(documentId))
        .build();
    try {
      _obx.box<DocumentChunk>().removeMany(chunkQ.findIds());
    } finally {
      chunkQ.close();
    }
    final docQ = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.documentId.equals(documentId))
        .build();
    try {
      _obx.box<SourceDocument>().removeMany(docQ.findIds());
    } finally {
      docQ.close();
    }
    _retrieval.invalidateCache();
  }

  /// Cleans up documents stuck in `processing` or `failed` state.
  Future<int> cleanupStaleDocuments() async {
    int removed = 0;
    final q = _obx
        .box<SourceDocument>()
        .query(
          SourceDocument_.status.equals(IngestionStatus.processing.name).or(
                SourceDocument_.status.equals(IngestionStatus.failed.name),
              ),
        )
        .build();
    final List<SourceDocument> stale;
    try {
      stale = q.find();
    } finally {
      q.close();
    }
    for (final doc in stale) {
      final cq = _obx
          .box<DocumentChunk>()
          .query(DocumentChunk_.documentId.equals(doc.documentId))
          .build();
      try {
        _obx.box<DocumentChunk>().removeMany(cq.findIds());
      } finally {
        cq.close();
      }
      final dq = _obx
          .box<SourceDocument>()
          .query(SourceDocument_.documentId.equals(doc.documentId))
          .build();
      try {
        _obx.box<SourceDocument>().removeMany(dq.findIds());
      } finally {
        dq.close();
      }
      removed++;
      debugPrint('cleanupStaleDocuments: removed "${doc.name}"');
    }
    if (removed > 0) _retrieval.invalidateCache();
    return removed;
  }
}
