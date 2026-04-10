import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/local_storage/hive_boxes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: kIsWeb || defaultTargetPlatform != TargetPlatform.android
        ? DefaultFirebaseOptions.currentPlatform
        : null,
  );

  // Initialize Local Storage (Shared Preferences wrapper)
  await HiveBoxes.init();

  runApp(const ChatKitApp());
}
