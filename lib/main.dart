import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/asset_ingestion_service.dart';
import 'core/embedding_service.dart';
import 'core/network_service.dart';
import 'core/routes/app_routes.dart';
import 'data/document_chunk.dart';
import 'data/object_box_store.dart';
import 'data/source_document.dart';
import 'domain/rag_retrieval_service.dart';
import 'domain/user_pdf_ingestion_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'objectbox.g.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── 1. ObjectBox ───────────────────────────────────────────────────────────
  final store = await openStore();
  final obx = ObjectBoxStore(store);
  Get.put<ObjectBoxStore>(obx, permanent: true);

  debugPrint('OBX ready — '
      'chunks: ${store.box<DocumentChunk>().count()}, '
      'docs: ${store.box<SourceDocument>().count()}');

  // ── 2. NetworkService (connectivity monitoring) ───────────────────────────
  Get.put<NetworkService>(NetworkService(), permanent: true);

  // ── 3. EmbeddingService (Jina — ingestion only) ───────────────────────────
  final embedder = EmbeddingService();
  await embedder.init(); // loads disk cache (fast, <5ms)
  Get.put<EmbeddingService>(embedder, permanent: true);

  // Fire warm-up in the background — don't await.
  // This establishes the TCP+TLS connection to Jina before the first user query,
  // cutting cold-start latency from ~6s to ~1s.
  unawaited(embedder.warmUp());

  // ── 4. RagRetrievalService (100% offline vector search) ───────────────────
  final retrieval = RagRetrievalService(obx: obx, embedder: embedder);
  Get.put<RagRetrievalService>(retrieval, permanent: true);

  // ── 5. AssetIngestionService ──────────────────────────────────────────────
  final assetIngestion = AssetIngestionService(
    obx: obx,
    embedder: embedder,
    retrieval: retrieval,
  );
  Get.put<AssetIngestionService>(assetIngestion, permanent: true);

  // ── 6. UserPdfIngestionService ────────────────────────────────────────────
  Get.put<UserPdfIngestionService>(
    UserPdfIngestionService(obx: obx, embedder: embedder, retrieval: retrieval),
    permanent: true,
  );

  // ── 7. Decide initial route ───────────────────────────────────────────────
  final currentUser = FirebaseAuth.instance.currentUser;
  
  String initialRoute;
  if (currentUser == null) {
    initialRoute = AppRoutes.auth;
  } else {
    // First install (or reinstall): show ingestion screen to index bundled PDFs.
    // Subsequent launches: skip straight to chat (ObjectBox already populated).
    final needsIngest = await assetIngestion.needsIngestion();
    initialRoute = needsIngest ? AppRoutes.ingestion : AppRoutes.chat;
  }

  runApp(ChatKitApp(initialRoute: initialRoute));
}
