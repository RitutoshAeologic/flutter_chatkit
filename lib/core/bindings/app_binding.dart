import 'package:get/get.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/chat/services/chat_service.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ChatService(), permanent: true);
    Get.put(AuthController(), permanent: true);
  }
}
