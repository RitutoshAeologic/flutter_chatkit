import 'package:get/get.dart';

import '../../../core/asset_ingestion_service.dart';
import '../../../data/source_document.dart';

/// Controller for the read-only document viewer screen.
/// No upload logic — documents are bundled at build time.
class KbManagerController extends GetxController {
  final AssetIngestionService _assetIngestion = Get.find<AssetIngestionService>();

  final documents = <SourceDocument>[].obs;

  @override
  void onInit() {
    super.onInit();
    refreshDocuments();
  }

  void refreshDocuments() {
    documents.value = _assetIngestion.listReadyDocuments();
  }

  int get totalChunks =>
      documents.fold(0, (sum, d) => sum + d.totalChunks);
}
