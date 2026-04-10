import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'core/local_storage/hive_boxes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // If not configured, we'll catch so the UI still loads (mostly for testing without full setup)
    print('Firebase initialization error: $e');
  }

  await Hive.initFlutter();
  await HiveBoxes.openAll();

  // GetX requires no wrapper widget — bindings are registered via GetMaterialApp
  runApp(const ChatKitApp());
}
