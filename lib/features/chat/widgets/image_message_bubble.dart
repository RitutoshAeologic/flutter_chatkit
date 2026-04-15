import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';

class ImageMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ImageMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: GestureDetector(
                  onTap: () {
                    if (message.imageUrl != null && !message.isLoading) {
                      Get.to(() => _ImagePreviewScreen(imageUrl: message.imageUrl!));
                    }
                  },
                  onLongPress: () => _showOptions(context),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (message.isLoading || message.imageUrl == null)
                        ? Container(
                            width: 260,
                            height: 200,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ).animate(onPlay: (controller) => controller.repeat())
                            .shimmer(duration: 1200.ms, color: theme.colorScheme.primary.withOpacity(0.1))
                        : Hero(
                            tag: message.imageUrl!,
                            child: Image.network(
                              message.imageUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  width: 260,
                                  height: 200,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                ).animate(onPlay: (controller) => controller.repeat())
                                  .shimmer(duration: 1200.ms, color: theme.colorScheme.primary.withOpacity(0.1));
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 260,
                                  height: 200,
                                  color: theme.colorScheme.errorContainer,
                                  child: Icon(Icons.error_outline, color: theme.colorScheme.error),
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ),
              if (isUser) const SizedBox(width: 8),
            ],
          ),
          if (message.createdAt != null)
            Padding(
              padding: EdgeInsets.only(top: 4, left: isUser ? 0 : 42, right: isUser ? 8 : 0),
              child: Text(
                '${message.createdAt!.hour}:${message.createdAt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
              ),
            ),
        ],
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),
    );
  }

  void _showOptions(BuildContext context) {
    if (message.imageUrl == null || message.isLoading) return;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const Text('View Full Screen'),
              onTap: () {
                Get.back();
                Get.to(() => _ImagePreviewScreen(imageUrl: message.imageUrl!));
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to Gallery'),
              onTap: () {
                Get.back();
                _saveImage(message.imageUrl!);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () => Get.back(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveImage(String url) async {
    try {
      Get.snackbar('Saving...', 'Downloading image to gallery', 
        showProgressIndicator: true, 
        snackPosition: SnackPosition.BOTTOM);
      
      final response = await http.get(Uri.parse(url));
      final bytes = response.bodyBytes;
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ai_gen_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      
      await Gal.putImage(file.path);
      Get.snackbar('Success', 'Image saved to gallery!', 
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.withOpacity(0.1));
    } catch (e) {
      Get.snackbar('Error', 'Failed to save image: $e', 
        snackPosition: SnackPosition.BOTTOM);
    }
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  final String imageUrl;

  const _ImagePreviewScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _triggerSave(),
          ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: imageUrl,
          child: InteractiveViewer(
            child: Image.network(imageUrl),
          ),
        ),
      ),
    );
  }

  Future<void> _triggerSave() async {
    try {
      Get.snackbar('Saving...', 'Downloading image...', 
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM);
        
      final response = await http.get(Uri.parse(imageUrl));
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ai_gen_preview.png');
      await file.writeAsBytes(response.bodyBytes);
      
      await Gal.putImage(file.path);
      Get.snackbar('Success', 'Image saved to gallery!', 
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e', 
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM);
    }
  }
}
