import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../../core/asset_ingestion_service.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/rag_models.dart';

/// Shown on first install to index bundled PDFs into ObjectBox.
/// Navigates to chat automatically when done.
class IngestionScreen extends StatefulWidget {
  const IngestionScreen({super.key});

  @override
  State<IngestionScreen> createState() => _IngestionScreenState();
}

class _IngestionScreenState extends State<IngestionScreen> {
  final _ingestion = Get.find<AssetIngestionService>();

  String _status = 'Preparing your documents…';
  double _progress = 0.0;
  bool _hasError = false;
  String? _errorMessage;
  StreamSubscription<IngestionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _startIngestion();
  }

  void _startIngestion() {
    _sub = _ingestion.ingestAll().listen(
      (event) {
        switch (event) {
          case IngestionProgress(:final message, :final fraction):
            if (mounted) {
              setState(() {
                _status = message;
                _progress = fraction;
              });
            }

          case IngestionComplete():
            // Single-file completion — wait for stream to finish
            break;

          case IngestionError(:final message):
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = message;
                _status = 'Error';
              });
            }
        }
      },
      onDone: () {
        if (!_hasError && mounted) {
          Get.offAllNamed(AppRoutes.chat);
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = e.toString();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.library_books_rounded,
                    size: 50, color: Colors.white),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 2000.ms, color: Colors.white24),

              const SizedBox(height: 40),

              // Title
              Text(
                'DocSearch AI',
                style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 8),

              Text(
                'Indexing your knowledge base…',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 48),

              if (!_hasError) ...[
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 8,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                        theme.colorScheme.primary),
                  ),
                ).animate().fadeIn(delay: 400.ms),

                const SizedBox(height: 20),

                // Status text
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 32),

                Text(
                  'This only happens once.\nAll future searches are instant & fully offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ).animate().fadeIn(delay: 600.ms),
              ] else ...[
                // Error state
                Icon(Icons.error_outline_rounded,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'An unknown error occurred.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = null;
                      _status = 'Retrying…';
                      _progress = 0;
                    });
                    _sub?.cancel();
                    _startIngestion();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
