import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/asset_ingestion_service.dart';
import '../../data/source_document.dart';
import '../../domain/user_pdf_ingestion_service.dart';

/// Read-only viewer of all indexed documents — both bundled and user-uploaded.
class KbViewerScreen extends StatefulWidget {
  const KbViewerScreen({super.key});

  @override
  State<KbViewerScreen> createState() => _KbViewerScreenState();
}

class _KbViewerScreenState extends State<KbViewerScreen> {
  final _assetIngestion = Get.find<AssetIngestionService>();
  final _userIngestion  = Get.find<UserPdfIngestionService>();

  List<SourceDocument> _bundledDocs = [];
  List<SourceDocument> _userDocs    = [];

  @override
  void initState() {
    super.initState();
    _refreshDocs();
  }

  /// Called every time the screen's dependencies change — including when
  /// GetX pushes it back into view after a pop. This keeps the list fresh
  /// without needing a manual Refresh tap.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshDocs();
  }

  void _refreshDocs() {
    if (!mounted) return;
    setState(() {
      _bundledDocs = _assetIngestion.listReadyDocuments();
      _userDocs    = _userIngestion.listUserDocuments();
    });
  }

  Future<void> _deleteUserDoc(SourceDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text('"${doc.name}" will be removed from your knowledge base.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _userIngestion.deleteUserDocument(doc.documentId);
      _refreshDocs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${doc.name}" removed from knowledge base.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDocs = [..._bundledDocs, ..._userDocs];
    final totalChunks = allDocs.fold(0, (s, d) => s + d.totalChunks);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refreshDocs,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Info banner ─────────────────────────────────────────────────
          if (allDocs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${allDocs.length} document${allDocs.length > 1 ? 's' : ''} · '
                      '$totalChunks chunks total',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),

          // ── Document list ───────────────────────────────────────────────
          Expanded(
            child: allDocs.isEmpty
                ? _IndexingState(theme: theme)
                : ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    children: [
                      // Bundled section
                      if (_bundledDocs.isNotEmpty) ...[
                        _SectionHeader(
                            label: 'Built-in Documents (${_bundledDocs.length})',
                            theme: theme),
                        const SizedBox(height: 8),
                        ..._bundledDocs.map((doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _DocCard(
                                  doc: doc,
                                  theme: theme,
                                  isUserDoc: false,
                                  onDelete: null),
                            )),
                        const SizedBox(height: 16),
                      ],

                      // User-uploaded section
                      if (_userDocs.isNotEmpty) ...[
                        _SectionHeader(
                            label: 'My Uploads (${_userDocs.length})',
                            theme: theme),
                        const SizedBox(height: 8),
                        ..._userDocs.map((doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _DocCard(
                                doc: doc,
                                theme: theme,
                                isUserDoc: true,
                                onDelete: () => _deleteUserDoc(doc),
                              ),
                            )),
                      ],

                      if (_userDocs.isEmpty)
                        _UploadHint(theme: theme),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;
  const _SectionHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.5),
    );
  }
}

// ── Document card ──────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  final SourceDocument doc;
  final ThemeData theme;
  final bool isUserDoc;
  final VoidCallback? onDelete;
  const _DocCard(
      {required this.doc,
      required this.theme,
      required this.isUserDoc,
      required this.onDelete});

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
            color: isUserDoc
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isUserDoc ? Icons.upload_file_rounded : Icons.picture_as_pdf_rounded,
            color: isUserDoc
                ? theme.colorScheme.tertiary
                : theme.colorScheme.primary,
            size: 22,
          ),
        ),
        title: Text(doc.name,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${doc.totalChunks} chunks · $mb MB',
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isUserDoc
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isUserDoc ? 'My Upload' : 'Built-in',
                style: TextStyle(
                    fontSize: 11,
                    color: isUserDoc
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold),
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: theme.colorScheme.error),
                onPressed: onDelete,
                tooltip: 'Remove',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

// ── Upload hint card ────────────────────────────────────────────────────────────

class _UploadHint extends StatelessWidget {
  final ThemeData theme;
  const _UploadHint({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.upload_file_rounded,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
              size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tap 📎 in the chat to upload your own PDF documents.',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows when no ready documents exist yet.
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
