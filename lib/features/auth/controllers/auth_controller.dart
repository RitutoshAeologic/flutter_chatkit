import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../../core/asset_ingestion_service.dart';
import '../../../core/routes/app_routes.dart';

class AuthController extends GetxController {
  final _auth = FirebaseAuth.instance;
  User? get user => _auth.currentUser;
  final _db = FirebaseDatabase.instance.ref();

  final isLoading = false.obs;
  final errorMessage = RxnString();

  Future<void> signIn(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _navigateAfterLogin();
    } on FirebaseAuthException catch (e) {
      debugPrint(e.message);
      debugPrint(e.code);
      if (e.message == 'The supplied auth credential is incorrect, malformed or has expired.' || e.code == 'user-not-found') {
        await _createAccount(email.trim(), password);
      } else {
        errorMessage.value = e.message;
      }
    //  errorMessage.value = e.message;
    } catch (e) {
      debugPrint(e.toString());

      errorMessage.value = "An unexpected error occurred.";
    } finally {
      isLoading.value = false;
    }
  }
  Future<void> _createAccount(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      /// Save user in Realtime DB
      await _db.child("users").child(uid).set({
        "uid": uid,
        "email": email,
        "createdAt": ServerValue.timestamp,
      });

      await _navigateAfterLogin();

    } on FirebaseAuthException catch (e) {
      debugPrint(e.message);
      if(e.message == "The email address is already in use by another account.") {
        errorMessage.value = "Invalid Password.";
      } else {
      errorMessage.value = e.message;}
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    Get.offAllNamed(AppRoutes.auth);
  }

  Future<void> _navigateAfterLogin() async {
    try {
      final assetIngestion = Get.find<AssetIngestionService>();
      final needsIngest = await assetIngestion.needsIngestion();
      if (needsIngest) {
        Get.offAllNamed(AppRoutes.ingestion);
      } else {
        Get.offAllNamed(AppRoutes.chat);
      }
    } catch (e) {
      // Fallback if service not ready
      Get.offAllNamed(AppRoutes.chat);
    }
  }
}
