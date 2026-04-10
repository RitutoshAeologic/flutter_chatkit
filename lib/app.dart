import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'core/bindings/app_binding.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';

class ChatKitApp extends StatelessWidget {
  const ChatKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ChatKit AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialBinding: AppBinding(),
      initialRoute: AppRoutes.splash,
      getPages: AppRoutes.pages,
    );
  }
}
