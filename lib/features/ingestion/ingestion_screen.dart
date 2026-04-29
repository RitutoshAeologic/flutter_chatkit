import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../../core/asset_ingestion_service.dart';
import '../../../core/network_service.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/rag_models.dart';

/// Shown on first install to index bundled PDFs into ObjectBox.
/// Handles all network scenarios:
///  - No internet on open  → shows "No Connection" UI, waits for network
///  - Network lost mid-ingest → cleans partial data, shows retry
///  - Auto-starts when connectivity restores
///  - Navigates to chat automatically when done
class IngestionScreen extends StatefulWidget {
  const IngestionScreen({super.key});

  @override
  State<IngestionScreen> createState() => _IngestionScreenState();
}

/// All possible states of the ingestion screen.
enum _ScreenState { waitingForNetwork, ingesting, error, done }

class _IngestionScreenState extends State<IngestionScreen> {
  final _ingestion = Get.find<AssetIngestionService>();
  final _network   = Get.find<NetworkService>();

  _ScreenState _state = _ScreenState.waitingForNetwork;
  String  _status       = '';
  double  _progress     = 0.0;
  String? _errorMessage;
  bool    _isNetworkError = false;

  // Stream subscriptions — ALWAYS cancelled in dispose() to prevent leaks
  StreamSubscription<IngestionEvent>? _ingestSub;
  StreamSubscription<bool>?           _networkSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Entry point: check network then decide what to show.
  Future<void> _init() async {
    final connected = await _network.isConnected;
    if (!mounted) return;

    if (connected) {
      _startIngestion();
    } else {
      _setOfflineWaiting();
    }
  }

  /// Show "waiting for network" UI and subscribe to connectivity changes.
  void _setOfflineWaiting() {
    if (!mounted) return;
    setState(() {
      _state         = _ScreenState.waitingForNetwork;
      _errorMessage  = null;
      _isNetworkError = false;
    });
    _subscribeToNetwork();
  }

  /// Listen to connectivity stream. When we come online, start ingestion.
  /// The subscription is replaced if called again — no duplicate listeners.
  void _subscribeToNetwork() {
    _networkSub?.cancel();
    _networkSub = _network.onlineStream.listen((online) {
      if (!mounted) return;
      if (online && _state == _ScreenState.waitingForNetwork) {
        debugPrint('IngestionScreen: network restored — starting ingestion');
        _startIngestion();
      }
    });
  }

  /// Kick off the ingestion pipeline.
  void _startIngestion() {
    if (!mounted) return;
    setState(() {
      _state          = _ScreenState.ingesting;
      _progress       = 0.0;
      _status         = 'Preparing your documents…';
      _errorMessage   = null;
      _isNetworkError = false;
    });

    _ingestSub?.cancel();
    _ingestSub = _ingestion.forceReingest().listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case IngestionProgress(:final message, :final fraction):
            setState(() {
              _status   = message;
              _progress = fraction;
            });

          case IngestionComplete():
            // Individual file done — stream continues until all files finish.
            break;

          case IngestionError(:final message):
            _handleIngestionError(message);
        }
      },
      onDone: () {
        if (!mounted) return;
        // Only navigate if there was no error
        if (_state == _ScreenState.ingesting) {
          Get.offAllNamed(AppRoutes.chat);
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('IngestionScreen: stream error: $e\n$st');
        if (mounted) _handleIngestionError(e.toString());
      },
      cancelOnError: false, // let the stream finish even after an error event
    );
  }

  /// Determines whether it's a network error and shows appropriate UI.
  void _handleIngestionError(String message) {
    if (!mounted) return;
    final type = NetworkService.classify(Exception(message));
    final isNet = type == NetworkErrorType.noInternet ||
        type == NetworkErrorType.timeout;

    setState(() {
      _state          = _ScreenState.error;
      _errorMessage   = NetworkService.messageFor(type, raw: message);
      _isNetworkError = isNet;
    });

    // If it's a network error, start watching for reconnection so we can
    // auto-retry when the internet comes back.
    if (isNet) {
      _subscribeToNetwork();
      // Override the network listener to restart ingestion, not just set state
      _networkSub?.cancel();
      _networkSub = _network.onlineStream.listen((online) {
        if (!mounted) return;
        if (online && _state == _ScreenState.error && _isNetworkError) {
          debugPrint('IngestionScreen: network restored after error — retrying');
          _retry();
        }
      });
    }
  }

  /// Cleans up partial ObjectBox data and re-runs ingestion.
  void _retry() {
    if (!mounted) return;
    _ingestSub?.cancel();
    // forceReingest() clears any partial data then re-runs ingestAll()
    setState(() {
      _state    = _ScreenState.ingesting;
      _progress = 0.0;
      _status   = 'Cleaning up and retrying…';
      _errorMessage   = null;
      _isNetworkError = false;
    });

    _ingestSub = _ingestion.forceReingest().listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case IngestionProgress(:final message, :final fraction):
            setState(() {
              _status   = message;
              _progress = fraction;
            });
          case IngestionComplete():
            break;
          case IngestionError(:final message):
            _handleIngestionError(message);
        }
      },
      onDone: () {
        if (!mounted) return;
        if (_state == _ScreenState.ingesting) {
          Get.offAllNamed(AppRoutes.chat);
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('IngestionScreen: retry stream error: $e\n$st');
        if (mounted) _handleIngestionError(e.toString());
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    // CRITICAL: always cancel subscriptions — forgetting this causes
    // setState-after-dispose crashes and memory leaks.
    _ingestSub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Animated icon ──────────────────────────────────────────
              _AppIcon(theme: theme, state: _state),
              const SizedBox(height: 40),

              // ── Title ──────────────────────────────────────────────────
              Text(
                'DocSearch AI',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 8),

              // ── Subtitle ───────────────────────────────────────────────
              Text(
                _subtitleFor(_state),
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 48),

              // ── State-specific content ─────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _buildStateContent(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent(ThemeData theme) {
    switch (_state) {
      case _ScreenState.waitingForNetwork:
        return _NoNetworkContent(theme: theme, onRetry: _init);

      case _ScreenState.ingesting:
        return _IngestingContent(
            theme: theme, progress: _progress, status: _status);

      case _ScreenState.error:
        return _ErrorContent(
          theme: theme,
          message: _errorMessage ?? 'An unexpected error occurred.',
          isNetworkError: _isNetworkError,
          onRetry: _retry,
        );

      case _ScreenState.done:
        return const SizedBox.shrink();
    }
  }

  String _subtitleFor(_ScreenState state) {
    switch (state) {
      case _ScreenState.waitingForNetwork:
        return 'Internet connection required\nto index documents on first launch.';
      case _ScreenState.ingesting:
        return 'Indexing your knowledge base…';
      case _ScreenState.error:
        return _isNetworkError
            ? 'Will retry automatically when connected.'
            : 'Something went wrong during indexing.';
      case _ScreenState.done:
        return 'Ready!';
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _AppIcon extends StatelessWidget {
  final ThemeData theme;
  final _ScreenState state;
  const _AppIcon({required this.theme, required this.state});

  @override
  Widget build(BuildContext context) {
    final isError = state == _ScreenState.error ||
        state == _ScreenState.waitingForNetwork;
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isError
              ? [theme.colorScheme.errorContainer, theme.colorScheme.error]
              : [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: (isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary)
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        state == _ScreenState.waitingForNetwork
            ? Icons.wifi_off_rounded
            : state == _ScreenState.error
                ? Icons.error_outline_rounded
                : Icons.library_books_rounded,
        size: 50,
        color: Colors.white,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 2000.ms, color: Colors.white24);
  }
}

class _NoNetworkContent extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onRetry;
  const _NoNetworkContent({required this.theme, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('no-network'),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                'Please connect to Wi-Fi or mobile data to index your documents.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.colorScheme.onErrorContainer, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'This is only needed once. After indexing, the app works completely offline.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
                    fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Text('Waiting for connection…',
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13)),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Check now'),
        ),
      ],
    ).animate().fadeIn();
  }
}

class _IngestingContent extends StatelessWidget {
  final ThemeData theme;
  final double progress;
  final String status;
  const _IngestingContent(
      {required this.theme, required this.progress, required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('ingesting'),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ).animate().fadeIn(delay: 400.ms),
        const SizedBox(height: 20),
        Text(
          status,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
        ).animate().fadeIn(),
        const SizedBox(height: 32),
        Text(
          'This only happens once.\nAll future searches are instant & fully offline.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        ).animate().fadeIn(delay: 600.ms),
      ],
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final ThemeData theme;
  final String message;
  final bool isNetworkError;
  final VoidCallback onRetry;
  const _ErrorContent({
    required this.theme,
    required this.message,
    required this.isNetworkError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('error'),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: theme.colorScheme.onErrorContainer, fontSize: 14),
          ),
        ),
        if (isNetworkError) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Text('Watching for connection…',
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(isNetworkError ? 'Retry now' : 'Retry'),
        ),
      ],
    ).animate().fadeIn();
  }
}
