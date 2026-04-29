import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/asset_ingestion_service.dart';
import '../../data/source_document.dart';

/// Read-only viewer of all indexed documents (bundled only).
/// No upload — documents are baked in by the developer at build time.
class KbViewerScreen extends StatefulWidget {
  const KbViewerScreen({super.key});

  @override
  State<KbViewerScreen> createState() => _KbViewerScreenState();
}

class _KbViewerScreenState extends State<KbViewerScreen> {
  final _ingestion = Get.find<AssetIngestionService>();
  List<SourceDocument> _docs = [];

  @override
  void initState() {
    super.initState();
    _refreshDocs();
  }

  void _refreshDocs() {
    setState(() => _docs = _ingestion.listReadyDocuments());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refreshDocs),
        ],
      ),
      body: Column(
        children: [
          // ── Info banner ─────────────────────────────────────────────────
          if (_docs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_docs.length} document${_docs.length > 1 ? 's' : ''} bundled · '
                      '${_docs.fold(0, (s, d) => s + d.totalChunks)} chunks · '
                      '100% offline search',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),

          // ── Document list ────────────────────────────────────────────────
          Expanded(
            child: _docs.isEmpty
                ? _IndexingState(theme: theme)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    itemCount: _docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _DocCard(doc: _docs[i], theme: theme),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${doc.totalChunks} chunks · $mb MB',
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Built-in',
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Shows when no ready documents exist yet — can only mean indexing
/// is still in progress (documents ARE bundled; this is not a config error).
class _IndexingState extends StatelessWidget {
  final ThemeData theme;
  const _IndexingState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Setting up your knowledge base…',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Documents are being indexed in the background.\nThis only happens once.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
