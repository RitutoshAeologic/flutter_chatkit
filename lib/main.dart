import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'data/document_chunk.dart';
import 'data/source_document.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/embedding_service.dart';
import 'data/object_box_store.dart';
import 'domain/document_ingestion_service.dart';
import 'domain/factual_hardening_service.dart';
import 'domain/inference_router.dart';
import 'domain/rag_retrieval_service.dart';
import 'objectbox.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── 1. ObjectBox ─────────────────────────────────────────────────────────
  // Must be first. Every domain service depends on it.
  final store = await openStore();
  final obx = ObjectBoxStore(store);
  Get.put<ObjectBoxStore>(obx, permanent: true);

  // Smoke test on first run (spec §15 Step 7)
  assert(() {
    debugPrint('OBX ready — '
        'chunks: ${store.box<DocumentChunk>().count()}, '
        'docs: ${store.box<SourceDocument>().count()}');
    return true;
  }());

  // ── 2. EmbeddingService ──────────────────────────────────────────────────
  // No dependencies beyond AppConfig.
  final embedder = EmbeddingService();
  Get.put<EmbeddingService>(embedder, permanent: true);

  // ── 3. RagRetrievalService ───────────────────────────────────────────────
  // Needs ObjectBoxStore + EmbeddingService.
  final retrieval = RagRetrievalService(obx: obx, embedder: embedder);
  Get.put<RagRetrievalService>(retrieval, permanent: true);

  // ── 4. FactualHardeningService ───────────────────────────────────────────
  // Stateless, no dependencies. const constructor.
  const hardening = FactualHardeningService();
  Get.put<FactualHardeningService>(hardening, permanent: true);

  // ── 5. InferenceRouter ───────────────────────────────────────────────────
  // Needs RagRetrievalService + FactualHardeningService.
  final router = InferenceRouter(retrieval: retrieval, hardening: hardening);
  Get.put<InferenceRouter>(router, permanent: true);

  // ── 6. DocumentIngestionService ──────────────────────────────────────────
  // Needs ObjectBoxStore + EmbeddingService + RagRetrievalService.
  final ingestion = DocumentIngestionService(
    obx: obx,
    embedder: embedder,
    retrieval: retrieval, // for cache invalidation only
  );
  Get.put<DocumentIngestionService>(ingestion, permanent: true);

  // ── Controllers are LAZY — never pre-register them ───────────────────────
  // ChatController: registered in ChatBinding via GetPage
  // KbManagerController: registered in KbManagerBinding via GetPage

  runApp(const ChatKitApp());
}
