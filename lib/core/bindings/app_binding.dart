import 'package:get/get.dart';
import '../../features/auth/controllers/auth_controller.dart';

/// Permanent service registration.
/// RAG services (ObjectBox, EmbeddingService, InferenceRouter, etc.) are
/// registered in main.dart in the exact order specified in spec §6.
/// ChatService has been removed — ChatController now calls InferenceRouter directly.
class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(AuthController(), permanent: true);
  }
}
