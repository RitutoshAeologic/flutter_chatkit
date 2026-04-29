import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../data/source_document.dart';
import '../controllers/kb_manager_controller.dart';

/// Document management screen.
/// Shows uploaded documents, ingestion progress, and allows upload/delete.
class KbManagerScreen extends GetView<KbManagerController> {
  const KbManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Knowledge Base',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Upload icon button (disabled while ingesting)
          Obx(() => IconButton(
                icon: const Icon(Icons.upload_file_rounded),
                tooltip: 'Add Document',
                onPressed: controller.isIngesting.value
                    ? null
                    : controller.uploadDocument,
              )),
        ],
      ),
      body: Column(
        children: [
          // ── Ingestion progress banner ──────────────────────────────────
          Obx(() {
            if (!controller.isIngesting.value) return const SizedBox.shrink();
            return _IngestionBanner(
              message: controller.ingestionStatus.value,
              progress: controller.ingestionProgress.value,
              theme: theme,
            );
          }),

          // ── Document list / empty state ────────────────────────────────
          Expanded(
            child: Obx(() {
              if (controller.ragDocuments.isEmpty &&
                  !controller.isIngesting.value) {
                return _EmptyState(
                  theme: theme,
                  onUpload: controller.uploadDocument,
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: controller.ragDocuments.length,
                itemBuilder: (context, index) {
                  final doc = controller.ragDocuments[index];
                  return _DocumentTile(
                    doc: doc,
                    theme: theme,
                    onDelete: () => controller.deleteDocument(doc),
                  );
                },
              );
            }),
          ),
        ],
      ),

      // FAB: hidden while ingesting
      floatingActionButton: Obx(() => controller.isIngesting.value
          ? const SizedBox.shrink()
          : FloatingActionButton.extended(
              onPressed: controller.uploadDocument,
              icon: const Icon(Icons.add),
              label: const Text('Add Document'),
            )),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _IngestionBanner extends StatelessWidget {
  final String message;
  final double progress;
  final ThemeData theme;

  const _IngestionBanner({
    required this.message,
    required this.progress,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.isNotEmpty ? message : 'Processing…',
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            backgroundColor:
                theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
            color: theme.colorScheme.onPrimaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onUpload;

  const _EmptyState({required this.theme, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 24),
            Text(
              'No documents yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Upload a PDF or TXT file to let the AI answer questions grounded in your documents.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Document'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final SourceDocument doc;
  final ThemeData theme;
  final VoidCallback onDelete;

  const _DocumentTile({
    required this.doc,
    required this.theme,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = doc.status == IngestionStatus.ready.name;
    final isProcessing = doc.status == IngestionStatus.processing.name;
    final isFailed = doc.status == IngestionStatus.failed.name;

    final fileSizeKb = (doc.fileSizeBytes / 1024).toStringAsFixed(1);
    final dateStr = doc.createdAt.isNotEmpty
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(doc.createdAt))
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: isFailed
              ? theme.colorScheme.error.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _FileTypeIcon(fileType: doc.fileType),
        title: Text(
          doc.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${doc.totalChunks} chunks · $fileSizeKb KB · $dateStr',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            // Status badge
            if (isProcessing)
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Processing…',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              )
            else if (isFailed)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Failed',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (isReady)
              Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 13,
                      color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Ready',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline,
              color: isProcessing
                  ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                  : theme.colorScheme.error),
          tooltip: 'Remove',
          onPressed: isProcessing ? null : onDelete,
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _FileTypeIcon extends StatelessWidget {
  final String fileType;
  const _FileTypeIcon({required this.fileType});

  @override
  Widget build(BuildContext context) {
    final isPdf = fileType.toLowerCase() == 'pdf';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: (isPdf ? Colors.red : Colors.blue).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isPdf ? Icons.picture_as_pdf_rounded : Icons.text_snippet_rounded,
        color: isPdf ? Colors.red.shade600 : Colors.blue.shade600,
        size: 24,
      ),
    );
  }
}
