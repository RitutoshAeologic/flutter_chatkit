import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/rag_models.dart';
import '../../../data/source_document.dart';
import '../../../domain/document_ingestion_service.dart';

/// GetX controller for KbManagerScreen.
/// Holds reactive state: document list, ingestion progress, ingestion status.
class KbManagerController extends GetxController {
  final DocumentIngestionService _ingestion;

  KbManagerController({required DocumentIngestionService ingestion})
      : _ingestion = ingestion;

  final ragDocuments = <SourceDocument>[].obs;
  final isIngesting = false.obs;
  final ingestionProgress = 0.0.obs;
  final ingestionStatus = ''.obs;

  StreamSubscription<IngestionEvent>? _ingestSub;

  @override
  void onInit() {
    super.onInit();
    // Auto-clean any docs stuck in processing/failed from a previous crashed session
    _ingestion.cleanupStaleDocuments().then((removed) {
      if (removed > 0) debugPrint('KbManager: auto-cleaned $removed stale documents');
      refreshDocuments();
    });
  }

  @override
  void onClose() {
    _ingestSub?.cancel();
    super.onClose();
  }

  /// Refreshes the document list from ObjectBox.
  void refreshDocuments() {
    ragDocuments.assignAll(_ingestion.listDocuments());
  }

  /// Number of ready documents (for badge in ChatScreen).
  int get readyCount =>
      ragDocuments.where((d) => d.status == IngestionStatus.ready.name).length;

  /// Opens FilePicker and starts the ingestion pipeline.
  Future<void> uploadDocument() async {
    if (isIngesting.value) return;

    isIngesting.value = true;
    ingestionProgress.value = 0.0;
    ingestionStatus.value = 'Starting…';

    _ingestSub?.cancel();
    _ingestSub = _ingestion.pickAndIngest().listen(
      (event) {
        switch (event) {
          case IngestionProgress(:final message, :final fraction):
            ingestionStatus.value = message;
            ingestionProgress.value = fraction;
            refreshDocuments();

          case IngestionComplete(:final document):
            isIngesting.value = false;
            ingestionProgress.value = 1.0;
            ingestionStatus.value = '';
            refreshDocuments();
            Get.snackbar(
              'Document Added',
              '"${document.name}" (${document.totalChunks} chunks) added to knowledge base.',
              duration: const Duration(seconds: 4),
            );

          case IngestionError(:final message):
            isIngesting.value = false;
            ingestionStatus.value = '';
            refreshDocuments();
            debugPrint("KbManagerController: ingestion error: $message");
            Get.snackbar(
              'Upload Failed',
              message,
              duration: const Duration(seconds: 5),
            );
        }
      },
      onError: (Object e) {
        isIngesting.value = false;
        ingestionStatus.value = '';
        Get.snackbar('Error', e.toString());
        debugPrint('KbManagerController: unhandled ingestion error: $e');
      },
      onDone: () {
        if (isIngesting.value) isIngesting.value = false;
      },
    );
  }

  /// Shows confirmation dialog then deletes the document.
  Future<void> deleteDocument(SourceDocument doc) async {
    Get.dialog(
      AlertDialog(
        title: const Text('Remove document?'),
        content: Text(
          'Remove "${doc.name}" from the knowledge base?\n'
          'The AI will no longer reference it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await _ingestion.deleteDocument(doc.documentId);
              refreshDocuments();
              Get.snackbar(
                'Removed',
                '"${doc.name}" removed from knowledge base.',
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
