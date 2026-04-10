import 'package:get/get.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/bindings/auth_binding.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/bindings/chat_binding.dart';

abstract class AppRoutes {
  static const auth = '/auth';
  static const chat = '/chat';

  static final pages = <GetPage>[
    GetPage(
      name: auth,
      page: () => const AuthScreen(),
      binding: AuthBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: chat,
      page: () => const ChatScreen(),
      binding: ChatBinding(),
      transition: Transition.fadeIn,
    ),
  ];
}
