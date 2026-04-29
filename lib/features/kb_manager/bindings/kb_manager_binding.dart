import 'package:get/get.dart';
import '../controllers/kb_manager_controller.dart';

class KbManagerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<KbManagerController>(
      () => KbManagerController(),
      fenix: true,
    );
  }
}
