import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../../core/routes/app_routes.dart';

class AuthController extends GetxController {
  final _auth = FirebaseAuth.instance;
  User? get user => _auth.currentUser;

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
      Get.offAllNamed(AppRoutes.chat);
    } on FirebaseAuthException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = "An unexpected error occurred.";
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    Get.offAllNamed(AppRoutes.auth);
  }
}
