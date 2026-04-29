import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app.dart';
import 'core/embedding_service.dart';
import 'data/document_chunk.dart';
import 'data/object_box_store.dart';
import 'data/source_document.dart';
import 'domain/document_ingestion_service.dart';
import 'domain/rag_retrieval_service.dart';
import 'objectbox.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. ObjectBox ───────────────────────────────────────────────────────────
  final store = await openStore();
  final obx = ObjectBoxStore(store);
  Get.put<ObjectBoxStore>(obx, permanent: true);

  assert(() {
    debugPrint('OBX ready — '
        'chunks: ${store.box<DocumentChunk>().count()}, '
        'docs: ${store.box<SourceDocument>().count()}');
    return true;
  }());

  // ── 2. EmbeddingService (Jina AI — called only during ingestion) ──────────
  final embedder = EmbeddingService();
  Get.put<EmbeddingService>(embedder, permanent: true);

  // ── 3. RagRetrievalService (fully offline vector search) ──────────────────
  final retrieval = RagRetrievalService(obx: obx, embedder: embedder);
  Get.put<RagRetrievalService>(retrieval, permanent: true);

  // ── 4. DocumentIngestionService ───────────────────────────────────────────
  final ingestion = DocumentIngestionService(
    obx: obx,
    embedder: embedder,
    retrieval: retrieval,
  );
  Get.put<DocumentIngestionService>(ingestion, permanent: true);

  runApp(const ChatKitApp());
}
