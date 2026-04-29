import 'package:get/get.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/bindings/chat_binding.dart';
import '../../features/kb_manager/screens/kb_manager_screen.dart';
import '../../features/kb_manager/bindings/kb_manager_binding.dart';

class AppRoutes {
  static const String chat      = '/';
  static const String kbManager = '/kb-manager';

  static final pages = [
    GetPage(
      name: chat,
      page: () => const ChatScreen(),
      binding: ChatBinding(),
    ),
    GetPage(
      name: kbManager,
      page: () => const KbManagerScreen(),
      binding: KbManagerBinding(),
    ),
  ];
}
