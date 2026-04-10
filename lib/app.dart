import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/theme/app_theme.dart';
import 'core/bindings/app_binding.dart';
import 'core/routes/app_routes.dart';

class ChatKitApp extends StatelessWidget {
  const ChatKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ChatKit AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // GetX runs AppBinding once at startup — registers all global services
      initialBinding: AppBinding(),

      initialRoute: AppRoutes.chat,
      getPages: AppRoutes.pages,
    );
  }
}
