import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/asset_ingestion_service.dart';
import '../../data/source_document.dart';

/// Read-only viewer of the bundled documents in ObjectBox.
/// No upload — documents are baked into the app at build time.
class KbViewerScreen extends StatelessWidget {
  const KbViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ingestion = Get.find<AssetIngestionService>();
    final docs = ingestion.listReadyDocuments();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loaded Documents',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: docs.isEmpty
          ? _EmptyState(theme: theme)
          : Column(
              children: [
                // Info banner
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${docs.length} document${docs.length > 1 ? 's' : ''} bundled in this app — '
                          'all searches run 100% offline.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Document list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _DocCard(doc: docs[i], theme: theme),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final SourceDocument doc;
  final ThemeData theme;
  const _DocCard({required this.doc, required this.theme});

  @override
  Widget build(BuildContext context) {
    final mb = (doc.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.picture_as_pdf_rounded,
              color: theme.colorScheme.primary, size: 22),
        ),
        title: Text(doc.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${doc.totalChunks} chunks · $mb MB',
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Ready',
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No documents loaded',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Add PDFs to assets/pdfs/ and restart the app.',
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
