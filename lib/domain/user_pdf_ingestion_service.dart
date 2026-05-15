import 'dart:async';

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

// ── DTOs (top-level, plain Dart — required for compute()) ───────────────────

class _UserIsolateInput {
  final Uint8List bytes;
  final String fileType;
  final String fileName;
  _UserIsolateInput(this.bytes, this.fileType, this.fileName);
}

class _UserChunkData {
  final String text;
  final String sourceLabel;
  final int startOffset;
  final int chunkIndex;
  _UserChunkData(this.text, this.sourceLabel, this.startOffset, this.chunkIndex);
}

// ── Top-level isolate fn ──────────────────────────────────────────────────────

List<_UserChunkData> _extractAndChunkUserPdf(_UserIsolateInput input) {
  final baseName = input.fileName.contains('.')
      ? input.fileName.substring(0, input.fileName.lastIndexOf('.'))
      : input.fileName;

  String fullText;
  int currentPage = 1;

  if (input.fileType == 'pdf') {
    final document = PdfDocument(inputBytes: input.bytes);
    final buf = StringBuffer();
    for (int i = 0; i < document.pages.count; i++) {
      final raw = PdfTextExtractor(document)
          .extractText(startPageIndex: i, endPageIndex: i);
      if (raw.trim().isEmpty) continue;
      // Fix SyncFusion word-merging artefact
      final fixed = raw
          .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
          .replaceAllMapped(RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]} ${m[2]}')
          .replaceAllMapped(RegExp(r'(\d)([A-Za-z])'), (m) => '${m[1]} ${m[2]}')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      buf.write('[[PAGE ${i + 1}]] $fixed ');
    }
    document.dispose();
    fullText = buf.toString();
  } else {
    fullText = String.fromCharCodes(input.bytes);
  }

  final words = fullText.split(RegExp(r'\s+'));
  final chunks = <_UserChunkData>[];
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
      chunks.add(_UserChunkData(
        truncated,
        '$baseName p.$currentPage',
        i,
        chunkIndex++,
      ));
    }
    i += AppConfig.chunkWordWindow - AppConfig.chunkWordOverlap;
    if (i <= 0) i = 1;
  }
  debugPrint('_extractAndChunkUserPdf: "${input.fileName}" → ${chunks.length} chunks');
  return chunks;
}

// ── UserPdfIngestionService ───────────────────────────────────────────────────

/// Allows the user to pick a PDF (or TXT) file from their device,
/// embed it via Jina, and store it in ObjectBox alongside the bundled PDFs.
///
/// The new document becomes immediately searchable in the chat RAG pipeline.
class UserPdfIngestionService {
  final ObjectBoxStore _obx;
  final EmbeddingService _embedder;
  final RagRetrievalService _retrieval;

  UserPdfIngestionService({
    required ObjectBoxStore obx,
    required EmbeddingService embedder,
    required RagRetrievalService retrieval,
  })  : _obx = obx,
        _embedder = embedder,
        _retrieval = retrieval;

  /// Opens the OS file picker, then ingests the chosen file.
  /// Yields [IngestionEvent]s so the UI can show progress.
  /// Returns early (empty stream) if the user cancels the picker.
  Stream<IngestionEvent> pickAndIngest() async* {
    // ── 1. Open file picker ────────────────────────────────────────────────
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt'],
        withData: true, // needed on iOS / Web to get bytes
      );
    } catch (e) {
      yield IngestionError('File picker failed: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return; // user cancelled

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      yield IngestionError('Could not read file bytes. Try again.');
      return;
    }

    final fileName = file.name;
    final ext = fileName.toLowerCase().endsWith('.txt') ? 'txt' : 'pdf';

    // File-size guard
    if (bytes.length > AppConfig.maxFileSizeBytes) {
      yield IngestionError(
          '"$fileName" is too large (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Max allowed: ${AppConfig.maxFileSizeBytes ~/ 1024 ~/ 1024} MB.');
      return;
    }

    yield IngestionProgress(message: 'Reading "$fileName"…', fraction: 0.05);
    yield* _ingestBytes(bytes, ext, fileName);
  }

  /// Ingests raw bytes (used for both pick-and-ingest and direct bytes).
  Stream<IngestionEvent> _ingestBytes(
      Uint8List bytes, String fileType, String fileName) async* {
    // ── SHA-256 dedup ─────────────────────────────────────────────────────
    final docId = sha256.convert(bytes).toString().substring(0, 16);
    if (_queryById(docId) != null) {
      yield IngestionError(
          '"$fileName" is already in your knowledge base (duplicate).');
      return;
    }

    final now = DateTime.now().toIso8601String();
    final doc = SourceDocument()
      ..documentId = docId
      ..name = fileName
      ..fileType = 'user_pdf'
      ..fileSizeBytes = bytes.length
      ..status = IngestionStatus.processing.name
      ..createdAt = now
      ..updatedAt = now;
    _obx.box<SourceDocument>().put(doc);

    // ── Extract + chunk in background isolate ─────────────────────────────
    yield IngestionProgress(message: 'Extracting text…', fraction: 0.2);
    final List<_UserChunkData> chunks;
    try {
      chunks = await compute(
          _extractAndChunkUserPdf, _UserIsolateInput(bytes, fileType, fileName));
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

    // ── Embed chunks ──────────────────────────────────────────────────────
    yield IngestionProgress(
        message: 'Embedding ${chunks.length} chunks…', fraction: 0.5);
    final List<List<double>> embeddings;
    try {
      embeddings =
          await _embedder.embedBatch(chunks.map((c) => c.text).toList());
    } catch (e) {
      _markFailed(doc);
      yield IngestionError('Embedding failed for "$fileName": $e');
      return;
    }

    // ── Store in ObjectBox ────────────────────────────────────────────────
    yield IngestionProgress(message: 'Saving to knowledge base…', fraction: 0.85);
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

    _retrieval.invalidateCache();
    debugPrint('UserPdfIngestionService: "$fileName" → ${entities.length} chunks ✓');

    yield IngestionProgress(
        message: 'Indexed "$fileName" (${entities.length} chunks) ✓',
        fraction: 1.0);
    yield IngestionComplete(
      document: SourceDocumentData(
        documentId: docId,
        name: fileName,
        fileType: 'user_pdf',
        totalChunks: entities.length,
        fileSizeBytes: bytes.length,
        status: IngestionStatus.ready.name,
        createdAt: now,
      ),
    );
  }

  /// Returns all user-uploaded documents sorted by name.
  List<SourceDocument> listUserDocuments() {
    final q = _obx
        .box<SourceDocument>()
        .query(SourceDocument_.fileType.equals('user_pdf'))
        .build();
    try {
      return q.find()..sort((a, b) => a.name.compareTo(b.name));
    } finally {
      q.close();
    }
  }

  /// Deletes a user-uploaded document and all its chunks.
  Future<void> deleteUserDocument(String documentId) async {
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
    debugPrint('UserPdfIngestionService: deleted documentId=$documentId');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

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
}
