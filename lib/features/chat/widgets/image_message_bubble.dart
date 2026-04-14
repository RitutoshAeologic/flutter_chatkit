import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
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
                        : Image.network(
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
              if (isUser) const SizedBox(width: 8),
            ],
          ),
          if (message.createdAt != null)
            Padding(
              padding: EdgeInsets.only(top: 4, left: isUser ? 0 : 42, right: isUser ? 8 : 0),
              child: Text(
                '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
              ),
            ),
        ],
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),
    );
  }

  void _showOptions(BuildContext context) {
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
              leading: const Icon(Icons.save_alt),
              title: const Text('Save Image'),
              onTap: () {
                Get.back();
                Get.snackbar('Coming Soon', 'Image saving functionality will be added in Phase 5.');
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
}
