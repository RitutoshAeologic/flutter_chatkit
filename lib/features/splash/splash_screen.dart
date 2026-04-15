import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/routes/app_routes.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _controller.forward();

    // Navigation logic after 1.8s
    Future.delayed(const Duration(milliseconds: 1800), () {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        Get.offAllNamed(AppRoutes.chat);
      } else {
        Get.offAllNamed(AppRoutes.auth);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 80,
              color: theme.colorScheme.primary,
            )
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(duration: const Duration(seconds: 2), color: theme.colorScheme.primaryContainer)
            .scale(duration: const Duration(seconds: 1), curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(
              'ChatKit AI',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ).animate().fadeIn(delay: const Duration(milliseconds: 400)).slideY(begin: 0.2),
            const SizedBox(height: 8),
            Text(
              'Your intelligent companion',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ).animate().fadeIn(delay: const Duration(milliseconds: 600)),
            const SizedBox(height: 64),
            const CircularProgressIndicator(strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}

class ChatKitLogoPainter extends CustomPainter {
  final Color color;
  ChatKitLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Speech bubble body
    final RRect rRect = RRect.fromLTRBR(
      0, 0, size.width, size.height * 0.85,
      Radius.circular(size.width * 0.2),
    );
    canvas.drawRRect(rRect, paint);

    // Tail
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.85)
      ..lineTo(size.width * 0.1, size.height)
      ..lineTo(size.width * 0.4, size.height * 0.85)
      ..close();
    canvas.drawPath(path, paint);

    // Three dots
    final dotPaint = Paint()..color = Colors.white;
    final double dotRadius = size.width * 0.05;
    final double centerY = size.height * 0.425;
    
    canvas.drawCircle(Offset(size.width * 0.3, centerY), dotRadius, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.5, centerY), dotRadius, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.7, centerY), dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
