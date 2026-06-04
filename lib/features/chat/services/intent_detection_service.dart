// lib/services/intent_detection_service.dart
//
// TWO-LAYER IMAGE INTENT DETECTOR
//
// Layer 1 — Client-side scorer (instant, zero cost, no API call)
//   Phrase patterns + exclusion check + visual noun score
//   Returns confidence 0.0–1.0
//
// Layer 2 — Groq classifier (fires only when Layer 1 is uncertain)
//   Tiny prompt, max_tokens=1, expects "IMAGE" or "TEXT"
//   ~200–400ms. Falls back to Layer 1 result on any error.
//
// RULE: Never auto-generate. Always return a result so the
// controller can show a confirmation bubble. The user always
// taps "Generate image" before anything is sent to Pollinations.

import 'dart:convert';
import 'package:http/http.dart' as http;

enum IntentType { image, text, uncertain }

class IntentResult {
  final IntentType type;
  final double confidence;

  const IntentResult({required this.type, required this.confidence});
}

class IntentDetectionService {
  // ── Groq config (same key already used in ChatService) ─────────────────
  final String _groqApiKey;
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  // ── Thresholds ─────────────────────────────────────────────────────────
  // >= HIGH → confident IMAGE, skip API call
  // >= LOW  → uncertain, fire Groq classifier
  // <  LOW  → confident TEXT, do nothing
  static const double _highConfidence = 0.75;
  static const double _lowConfidence  = 0.35;

  IntentDetectionService({required String groqApiKey})
      : _groqApiKey = groqApiKey;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Analyse [text] and return an [IntentResult].
  ///
  /// - confident IMAGE (>= 0.75) → show bubble immediately
  /// - uncertain (0.35–0.74)     → calls Groq classifier, then show bubble
  /// - confident TEXT (< 0.35)   → return IntentType.text, no bubble
  Future<IntentResult> detect(String text) async {
    final layer1 = _clientScore(text.toLowerCase().trim());

    if (layer1.confidence >= _highConfidence) return layer1;
    if (layer1.confidence < _lowConfidence)   return layer1;

    // Uncertain range — ask Groq
    return _groqClassify(text, fallback: layer1);
  }

  // ── Layer 1: client-side scoring ───────────────────────────────────────

  // Multi-word trigger phrases. Matched phrase contributes base score 0.70.
  static const List<String> _triggerPhrases = [
    'draw me a', 'draw me an', 'draw a', 'draw an','draw'
    'generate an image', 'generate a picture', 'generate an illustration',
    'create an image', 'create a picture', 'create an illustration',
    'make an image', 'make a picture', 'make an illustration',
    'show me a picture', 'show me an image', 'show me a photo',
    'paint a', 'paint an',
    'render a', 'render an',
    'visualise a', 'visualize a',
    'illustrate a', 'illustrate an',
    'image of a', 'image of an',
    'picture of a', 'picture of an',
    'photo of a', 'photo of an',
    'illustration of a', 'illustration of an',
    'explain the design of a', 'describe the design of a',
    'explain the design', 'describe the design'
    'explain design', 'describe design'
  ];

  // If any exclusion term appears after a trigger, intent is figurative.
  // Presence drops score to 0.0.
  static const List<String> _exclusionTerms = [
    'comparison', 'compare', 'difference', 'between',
    'example', 'examples', 'scenario', 'situation',
    'plan', 'strategy', 'steps', 'roadmap',
    'how to', 'how do', 'how can', 'how would',
    'why', 'what is', 'what are',
    'explain', 'describe', 'definition',
    'summary', 'summarise', 'summarize',
    'list', 'outline', 'overview', 'guide', 'tutorial',
  ];

  // Each matched visual noun adds +0.15 (capped at +0.30 total boost).
  static const List<String> _visualNouns = [
    'landscape', 'portrait', 'sunset', 'sunrise',
    'mountain', 'mountains', 'ocean', 'sea', 'beach', 'river',
    'forest', 'jungle', 'desert', 'cave',
    'city', 'cityscape', 'skyline', 'street', 'building', 'castle',
    'dragon', 'cat', 'dog', 'wolf', 'horse', 'bird', 'lion', 'tiger',
    'person', 'woman', 'man', 'child', 'warrior', 'knight',
    'astronaut', 'robot', 'alien', 'wizard', 'character',
    'spaceship', 'rocket', 'car', 'vehicle',
    'flower', 'tree', 'garden', 'island',
    'galaxy', 'stars', 'nebula', 'planet',
    'anime', 'realistic', 'cartoon', 'painting', 'digital art',
    'watercolour', 'sketch', 'dark', 'vibrant', 'neon',
  ];

  IntentResult _clientScore(String lower) {
    // Check exclusion first — veto any trigger if figurative language present
    for (final ex in _exclusionTerms) {
      if (lower.contains(ex)) {
        return const IntentResult(type: IntentType.text, confidence: 0.0);
      }
    }

    // Check trigger phrases
    double score = 0.0;
    for (final phrase in _triggerPhrases) {
      if (lower.contains(phrase)) {
        score = 0.70;
        break;
      }
    }

    // Visual noun boost (capped at +0.30)
    double boost = 0.0;
    for (final noun in _visualNouns) {
      if (lower.contains(noun)) {
        boost += 0.15;
        if (boost >= 0.30) break;
      }
    }

    score = (score + boost).clamp(0.0, 1.0);

    if (score >= _highConfidence) {
      return IntentResult(type: IntentType.image, confidence: score);
    } else if (score >= _lowConfidence) {
      return IntentResult(type: IntentType.uncertain, confidence: score);
    }
    return IntentResult(type: IntentType.text, confidence: score);
  }

  // ── Layer 2: Groq single-token classifier ──────────────────────────────

  Future<IntentResult> _groqClassify(
      String text, {
        required IntentResult fallback,
      }) async {
    try {
      final response = await http
          .post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _groqModel,
          'messages': [
            {
              'role': 'system',
              'content':
              'You classify user messages. Reply with exactly one word: '
                  'IMAGE if the user wants a visual image generated, '
                  'TEXT if they want a text response. No other output.',
            },
            {'role': 'user', 'content': text},
          ],
          'max_tokens': 1,
          'temperature': 0.0,
        }),
      )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data   = jsonDecode(response.body);
        final answer = (data['choices'][0]['message']['content'] as String)
            .trim()
            .toUpperCase();

        if (answer == 'IMAGE') {
          return const IntentResult(
              type: IntentType.image, confidence: 0.97);
        } else {
          return const IntentResult(
              type: IntentType.text, confidence: 0.97);
        }
      }
    } catch (_) {
      // Network error / timeout — fall back to Layer 1 score silently
    }

    return fallback;
  }
}