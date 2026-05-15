import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/document_chunk.dart';
import '../data/object_box_store.dart';
import '../data/source_document.dart';
import '../objectbox.g.dart';
import 'rag_retrieval_service.dart';

// ── DocumentIngestionService ─────────────────────────────────────────────────
// NOTE: User file upload is now handled by UserPdfIngestionService.
//       Asset ingestion is handled by AssetIngestionService.
//       This service is kept only for its cleanup/delete utility methods.

class DocumentIngestionService {
  final ObjectBoxStore _obx;
  final RagRetrievalService _retrieval;

  DocumentIngestionService({
    required ObjectBoxStore obx,
    required RagRetrievalService retrieval,
  })  : _obx = obx,
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
