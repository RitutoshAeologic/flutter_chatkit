import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../../core/routes/app_routes.dart';

class AuthController extends GetxController {
  final _auth = FirebaseAuth.instance;

  final user = Rxn<User>();

  bool get isLoggedIn => user.value != null;
  String get userId => user.value?.uid ?? '';
  String get userEmail => user.value?.email ?? '';

  final isLoading = false.obs;
  final errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    ever(user, _handleAuthChange);
    user.bindStream(_auth.authStateChanges());
  }

  void _handleAuthChange(User? u) {
    if (u == null) {
      Get.offAllNamed(AppRoutes.chat);
    } else {
      Get.offAllNamed(AppRoutes.chat);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      errorMessage.value = _friendlyError(e.code);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      errorMessage.value = _friendlyError(e.code);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  void clearError() => errorMessage.value = null;

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
