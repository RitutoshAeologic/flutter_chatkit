import 'package:get/get.dart';
import '../../features/auth/controllers/auth_controller.dart';

/// App-level binding — all services wired in main() before runApp().
class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(AuthController(), permanent: true);
  }
}
