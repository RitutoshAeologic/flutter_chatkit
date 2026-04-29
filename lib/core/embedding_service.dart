import 'dart:convert';
import 'dart:math' show sqrt;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_exceptions.dart';

/// Groq embedding API wrapper.
/// - embed(text): single query, uses LRU cache.
/// - embedBatch(texts): bulk, handles 96-per-call batching internally.
/// - All vectors are L2-normalised.
class EmbeddingService {
  // LRU cache: Map preserves insertion order → first = oldest (O2)
  final _queryCache = <String, List<double>>{};

  /// Embeds a single query. Returns cached vector on repeated calls.
  Future<List<double>> embed(String text) async {
    if (_queryCache.containsKey(text)) {
      // Move to end (most recently used)
      final v = _queryCache.remove(text)!;
      _queryCache[text] = v;
      debugPrint('EmbeddingService: cache HIT for query (${text.length} chars)');
      return v;
    }

    final sw = Stopwatch()..start();
    final results = await _callApi([text]);
    sw.stop();
    debugPrint('EmbeddingService: embed() API call took ${sw.elapsedMilliseconds}ms');

    final vector = results.first;
    if (_queryCache.length >= AppConfig.embedCacheMaxSize) {
      _queryCache.remove(_queryCache.keys.first); // evict least recently used
    }
    _queryCache[text] = vector;
    return vector;
  }

  /// Embeds many texts. Handles Jina's batching limit internally.
  /// Returns vectors in the SAME ORDER as input.
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return [];

    final sw = Stopwatch()..start();
    final result = List<List<double>>.filled(texts.length, const []);

    // Split into batches of AppConfig.embedBatchSize
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

  /// Calls the Jina embedding API. Retries up to AppConfig.embedMaxRetries.
  Future<List<List<double>>> _callApi(List<String> texts) async {
    Exception? lastError;

    // Guard: no API key configured
    if (AppConfig.jinaApiKey.isEmpty) {
      throw EmbeddingException(
        'Jina AI API key not set. Get a free key at https://jina.ai and add it '
        'to AppConfig.jinaApiKey or pass --dart-define=JINA_API_KEY=jina_xxx',
      );
    }

    for (int attempt = 0; attempt < AppConfig.embedMaxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse(AppConfig.embedUrl),
          headers: {
            'Authorization': 'Bearer ${AppConfig.jinaApiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'input': texts,
            'model': AppConfig.embedModel,
          }),
        );

        if (response.statusCode != 200) {
          throw EmbeddingException(
            'Embedding API returned ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['data'] as List).cast<Map<String, dynamic>>();

        // Sort by index field to guarantee input order is preserved
        items.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

        return items.map((item) {
          final raw = (item['embedding'] as List).cast<num>();
          return _l2Normalize(raw.map((e) => e.toDouble()).toList());
        }).toList();
      } on EmbeddingException {
        rethrow;
      } catch (e) {
        lastError = EmbeddingException('Network error: $e');
        debugPrint('EmbeddingService: attempt ${attempt + 1} failed: $e');
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    throw lastError ?? EmbeddingException('Unknown embedding error');
  }

  /// L2-normalises a vector so dot-product == cosine similarity.
  List<double> _l2Normalize(List<double> v) {
    double sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    if (sumSq == 0.0) return v;
    final invNorm = 1.0 / sqrt(sumSq);
    return v.map((x) => x * invNorm).toList();
  }
}
