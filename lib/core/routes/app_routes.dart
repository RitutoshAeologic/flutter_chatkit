import 'package:get/get.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/bindings/chat_binding.dart';
import '../../features/ingestion/ingestion_screen.dart';
import '../../features/kb_viewer/kb_viewer_screen.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/bindings/auth_binding.dart';

class AppRoutes {
  static const String ingestion = '/ingestion'; // first-run only
  static const String chat      = '/';
  static const String kbViewer  = '/kb-viewer'; // read-only document list
  static const String auth      = '/auth';

  static final pages = [
    GetPage(
      name: ingestion,
      page: () => const IngestionScreen(),
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
      name: kbViewer,
      page: () => const KbViewerScreen(),
    ),
  ];
}
