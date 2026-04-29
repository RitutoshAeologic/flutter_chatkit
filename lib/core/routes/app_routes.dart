import 'package:get/get.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/bindings/auth_binding.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/bindings/chat_binding.dart';
import '../../features/kb_manager/screens/kb_manager_screen.dart';
import '../../features/kb_manager/bindings/kb_manager_binding.dart';

class AppRoutes {
  static const splash = '/';
  static const auth = '/auth';
  static const chat = '/chat';
  static const kbManager = '/kb-manager';

  static final pages = [
    GetPage(
      name: splash,
      page: () => const SplashScreen(),
    ),
    GetPage(
      name: auth,
      page: () => const AuthScreen(),
      binding: AuthBinding(),
    ),
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
