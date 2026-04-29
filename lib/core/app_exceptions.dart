/// Thrown by EmbeddingService when API call fails after retries.
class EmbeddingException implements Exception {
  final String message;
  final int? statusCode;

  const EmbeddingException(this.message, {this.statusCode});

  @override
  String toString() => 'EmbeddingException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

/// Thrown by InferenceRouter when Grok API call fails.
class RouterException implements Exception {
  final String message;
  final int? statusCode;

  const RouterException(this.message, {this.statusCode});

  @override
  String toString() => 'RouterException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}
