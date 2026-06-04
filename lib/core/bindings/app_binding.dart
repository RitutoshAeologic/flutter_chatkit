import 'package:flutter_chatkit/features/chat/services/intent_detection_service.dart';
import 'package:get/get.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/chat/services/chat_service.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ChatService(), permanent: true);
    Get.put(IntentDetectionService(groqApiKey: dotenv.env['GROQ_API_KEY'] ?? ''), permanent: true);
    Get.put(AuthController(), permanent: true);
  }
}
