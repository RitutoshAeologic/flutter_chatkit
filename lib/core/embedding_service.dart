import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'app_exceptions.dart';
import 'network_service.dart';

/// Jina AI embedding API wrapper.
/// - embed(text): single query, uses LRU cache.
/// - embedBatch(texts): bulk, handles 96-per-call batching internally.
/// - All vectors are L2-normalised.
/// - Throws EmbeddingException with user-friendly messages on all failures.
class EmbeddingService {
  // ── LRU query cache: Map preserves insertion order → first = oldest ─────────
  final _queryCache = <String, List<double>>{};

  /// Embeds a single query. Returns cached vector on repeated calls.
  Future<List<double>> embed(String text) async {
    if (_queryCache.containsKey(text)) {
      final v = _queryCache.remove(text)!;
      _queryCache[text] = v; // move to end (most recently used)
      debugPrint('EmbeddingService: cache HIT (${text.length} chars)');
      return v;
    }

    final sw = Stopwatch()..start();
    final results = await _callApi([text]);
    sw.stop();
    debugPrint('EmbeddingService: embed() API call took ${sw.elapsedMilliseconds}ms');

    final vector = results.first;
    _evictIfNeeded();
    _queryCache[text] = vector;
    return vector;
  }

  /// Embeds many texts. Handles Jina's batching limit internally.
  /// Returns vectors in the SAME ORDER as input.
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
        'EmbeddingService: embedBatch(${texts.length} texts) total = ${sw.elapsedMilliseconds}ms');
    return result;
  }

  // ── Internal API call with retry + timeout + classified errors ───────────────

  /// Calls the Jina embedding API.
  /// - Applies a 30-second timeout per attempt.
  /// - Retries up to [AppConfig.embedMaxRetries] times on transient failures.
  /// - Auth errors (401/403) are NOT retried — they always fail fast.
  /// - Throws [EmbeddingException] with a user-friendly message on failure.
  Future<List<List<double>>> _callApi(List<String> texts) async {
    if (AppConfig.jinaApiKey.isEmpty) {
      throw EmbeddingException(
        'Jina AI API key not configured. '
        'Pass it via --dart-define=JINA_API_KEY=jina_xxx at build time.',
      );
    }

    EmbeddingException? lastError;

    for (int attempt = 0; attempt < AppConfig.embedMaxRetries; attempt++) {
      try {
        final response = await http
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

        // ── Non-retryable errors ─────────────────────────────────────────────
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.authError),
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode == 429) {
          // Rate limited — wait longer before retry
          await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
          throw EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.rateLimited),
            statusCode: 429,
          );
        }
        if (response.statusCode >= 500) {
          lastError = EmbeddingException(
            NetworkService.messageFor(NetworkErrorType.serverError),
            statusCode: response.statusCode,
          );
          await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
          continue; // retry on 5xx
        }
        if (response.statusCode != 200) {
          throw EmbeddingException(
            'Embedding API error ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
          );
        }

        // ── Parse response ───────────────────────────────────────────────────
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['data'] as List).cast<Map<String, dynamic>>();

        // Sort by index to guarantee input order is preserved
        items.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

        return items.map((item) {
          final raw = (item['embedding'] as List).cast<num>();
          return _l2Normalize(raw.map((e) => e.toDouble()).toList());
        }).toList();

      } on EmbeddingException {
        rethrow; // auth/key errors — never retry
      } on TimeoutException catch (e) {
        debugPrint('EmbeddingService: attempt ${attempt + 1} timed out: $e');
        lastError = EmbeddingException(
          NetworkService.messageFor(NetworkErrorType.timeout),
        );
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } on SocketException catch (e) {
        debugPrint('EmbeddingService: attempt ${attempt + 1} SocketException: $e');
        lastError = EmbeddingException(
          NetworkService.messageFor(NetworkErrorType.noInternet),
        );
        // Don't wait — network is down, retrying immediately is pointless
        break; // exit retry loop; caller handles network-down scenario
      } catch (e) {
        debugPrint('EmbeddingService: attempt ${attempt + 1} unexpected error: $e');
        final type = NetworkService.classify(e);
        lastError = EmbeddingException(
          NetworkService.messageFor(type, raw: e.toString()),
        );
        if (type == NetworkErrorType.noInternet) break; // no point retrying
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    throw lastError ?? EmbeddingException('Unknown embedding error');
  }

  void _evictIfNeeded() {
    if (_queryCache.length >= AppConfig.embedCacheMaxSize) {
      _queryCache.remove(_queryCache.keys.first); // evict least recently used
    }
  }

  /// L2-normalises a vector so dot-product == cosine similarity.
  List<double> _l2Normalize(List<double> v) {
    double sumSq = 0.0;
    for (final x in v) sumSq += x * x;
    if (sumSq == 0.0) return v;
    final invNorm = 1.0 / sqrt(sumSq);
    return v.map((x) => x * invNorm).toList();
  }
}
