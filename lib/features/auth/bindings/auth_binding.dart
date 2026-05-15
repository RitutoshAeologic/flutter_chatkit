import 'package:get/get.dart';

class AuthBinding extends Bindings {
  @override
  void dependencies() {
    // AuthController is injected permanently via AppBinding.
    // Additional auth-scoped injects can go here.
  }
}
