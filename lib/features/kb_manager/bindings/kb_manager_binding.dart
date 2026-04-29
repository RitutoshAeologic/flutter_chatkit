import 'package:get/get.dart';
import '../../../domain/document_ingestion_service.dart';
import '../controllers/kb_manager_controller.dart';

/// Lazy binding for KbManagerController.
/// Used by the router only — never call Get.put() for controllers (spec Rule 8).
class KbManagerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<KbManagerController>(
      () => KbManagerController(
        ingestion: Get.find<DocumentIngestionService>(),
      ),
      fenix: true, // auto-recreates after disposal, prevents double-registration (M7 fix)
    );
  }
}
