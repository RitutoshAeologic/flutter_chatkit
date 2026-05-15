import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_exceptions.dart';
import 'network_service.dart';

/// Jina AI embedding service.
///
/// Three-layer optimisation stack:
///   L1 — In-memory LRU cache  (nanoseconds, hot queries in this session)
///   L2 — SharedPreferences disk cache (milliseconds, warm queries across sessions)
///   L3 — Jina API call over a PERSISTENT http.Client (one TLS handshake amortised)
///
/// Cold first-query: ~1-2s (persistent client avoids per-call TLS overhead).
/// Warm query (in-memory): 0ms.
/// Warm query (disk cache): ~5ms.
class EmbeddingService {
  // ── O1: In-memory LRU cache ─────────────────────────────────────────────────
  // Map preserves insertion order → first key = least-recently-used.
  final _memCache = <String, List<double>>{};

  // ── O2: Disk cache ──────────────────────────────────────────────────────────
  // Loaded once at startup; written on every new embedding.
  static const _diskCacheKey = 'embed_cache_v2';
  SharedPreferences? _prefs;

  // ── O3: Persistent HTTP client ──────────────────────────────────────────────
  // A single client reuses TCP connections and TLS sessions across calls.
  // Without this, every call pays ~3-5s for DNS+TCP+TLS on mobile.
  final http.Client _httpClient = http.Client();

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Call once at startup (non-blocking). Loads disk cache into memory.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadDiskCache();
    } catch (e) {
      // Disk cache is best-effort; app still works without it.
      debugPrint('EmbeddingService: disk cache init failed (ignoring): $e');
    }
  }

  void _loadDiskCache() {
    final raw = _prefs?.getString(_diskCacheKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>();
      for (final entry in list) {
        final key = entry['k'] as String;
        final vec = (entry['v'] as List).cast<num>()
            .map((n) => n.toDouble())
            .toList();
        if (_memCache.length < AppConfig.embedCacheMaxSize) {
          _memCache[key] = vec;
        }
      }
      debugPrint('EmbeddingService: loaded ${_memCache.length} entries from disk cache');
    } catch (e) {
      debugPrint('EmbeddingService: disk cache parse error (ignoring): $e');
      _prefs?.remove(_diskCacheKey); // clear corrupt data
    }
  }

  void _saveDiskCache() {
    if (_prefs == null) return;
    try {
      // Save only the most recent AppConfig.embedCacheMaxSize entries
      final entries = _memCache.entries
          .take(AppConfig.embedCacheMaxSize)
          .map((e) => {'k': e.key, 'v': e.value})
          .toList();
      _prefs!.setString(_diskCacheKey, jsonEncode(entries));
    } catch (e) {
      debugPrint('EmbeddingService: disk cache save error (ignoring): $e');
    }
  }

  /// Pre-warms the Jina API connection (TCP + TLS).
  /// Call this in the background after app starts so the first user query is fast.
  Future<void> warmUp() async {
    if (AppConfig.jinaApiKey.isEmpty) return;
    try {
      await _callApi(['ok']); // minimal text — just establishes the connection
      debugPrint('EmbeddingService: connection warmed up ✓');
    } catch (e) {
      debugPrint('EmbeddingService: warm-up failed (ignoring): $e');
    }
  }

  /// Closes the persistent HTTP client. Call when the service is destroyed.
  void dispose() => _httpClient.close();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Embeds a single query text. Three-layer cache lookup before API call.
  Future<List<double>> embed(String text) async {
    // L1: in-memory check
    if (_memCache.containsKey(text)) {
      final v = _memCache.remove(text)!;
      _memCache[text] = v; // move to end (most recently used)
      debugPrint('EmbeddingService: L1 cache HIT');
      return v;
    }

    final sw = Stopwatch()..start();
    final results = await _callApi([text]);
    sw.stop();
    debugPrint('EmbeddingService: embed() API call took ${sw.elapsedMilliseconds}ms');

    final vector = results.first;
    _evictIfNeeded();
    _memCache[text] = vector;
    _saveDiskCache(); // async-safe: SharedPreferences handles concurrency
    return vector;
  }

  /// Embeds many texts. Batch Jina calls (internal splitting at embedBatchSize).
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return [];

    final sw = Stopwatch()..start();
    final result = List<List<double>>.filled(texts.length, const []);

    for (int i = 0; i < texts.length; i += AppConfig.embedBatchSize) {
      final end = (i + AppConfig.embedBatchSize).clamp(0, texts.length);
      final batch = texts.sublist(i, end);
      final batchSw = Stopwatch()..start();
      final batchVectors = await _callApi(batch);
      batchSw.stop();
      debugPrint(
          'EmbeddingService: batch ${i ~/ AppConfig.embedBatchSize + 1} '
          '(${batch.length} texts) took ${batchSw.elapsedMilliseconds}ms');
      for (int j = 0; j < batchVectors.length; j++) {
        result[i + j] = batchVectors[j];
      }
    }

    sw.stop();
    debugPrint(
        'EmbeddingService: embedBatch(${texts.length}) total = ${sw.elapsedMilliseconds}ms');
    return result;
  }

  // ── Internal call with persistent client + retry + error classification ──────

  Future<List<List<double>>> _callApi(List<String> texts) async {
    if (AppConfig.jinaApiKey.isEmpty) {
      throw EmbeddingException(
        'Jina AI API key not configured. '
        'Pass --dart-define=JINA_API_KEY=jina_xxx at build time.',
      );
    }

    EmbeddingException? lastError;

    for (int attempt = 0; attempt < AppConfig.embedMaxRetries; attempt++) {
      try {
        // ── Use persistent client (reuses TCP+TLS connection) ────────────
        final response = await _httpClient
            .post(
              Uri.parse(AppConfig.embedUrl),
              headers: {
                'Authorization': 'Bearer ${AppConfig.jinaApiKey}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'input': texts,
                'model': AppConfig.embedModel,
              }),
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException(
                  'Jina API timed out after 30s', const Duration(seconds: 30)),
            );

        // ── Non-retryable errors ─────────────────────────────────────────
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.authError),
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode == 429) {
          await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
          lastError = EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.rateLimited),
            statusCode: 429,
          );
          continue;
        }
        if (response.statusCode >= 500) {
          lastError = EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.serverError),
            statusCode: response.statusCode,
          );
          await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
          continue;
        }
        if (response.statusCode != 200) {
          throw EmbeddingException(
            'Embedding API error ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
          );
        }

        // ── Parse ────────────────────────────────────────────────────────
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['data'] as List).cast<Map<String, dynamic>>();
        items.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

        return items.map((item) {
          final raw = (item['embedding'] as List).cast<num>();
          return _l2Normalize(raw.map((e) => e.toDouble()).toList());
        }).toList();

      } on EmbeddingException {
        rethrow; // never retry auth errors
      } on TimeoutException catch (e) {
        debugPrint('EmbeddingService: attempt ${attempt + 1} timed out: $e');
        lastError = EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.timeout));
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } on SocketException catch (e) {
        debugPrint('EmbeddingService: SocketException: $e');
        lastError = EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.noInternet));
        break; // network is down — no point retrying
      } catch (e) {
        debugPrint('EmbeddingService: unexpected error attempt ${attempt + 1}: $e');
        final type = NetworkService.classify(e);
        lastError = EmbeddingException(
            NetworkService.messageFor(type, raw: e.toString()));
        if (type == NetworkErrorType.noInternet) break;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    throw lastError ?? EmbeddingException('Unknown embedding error');
  }

  void _evictIfNeeded() {
    if (_memCache.length >= AppConfig.embedCacheMaxSize) {
      _memCache.remove(_memCache.keys.first);
    }
  }

  List<double> _l2Normalize(List<double> v) {
    double sumSq = 0.0;
    for (final x in v) { sumSq += x * x; }
    if (sumSq == 0.0) return v;
    final invNorm = 1.0 / sqrt(sumSq);
    return v.map((x) => x * invNorm).toList();
  }
}
