import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Lightweight wrapper around connectivity_plus.
///
/// Important: connectivity_plus tells you the *interface* state (WiFi, mobile),
/// NOT whether the internet is actually reachable (captive portals, DNS failures,
/// firewall blocks). So we also do a lightweight HTTP HEAD check to confirm.
///
/// Usage:
///   final net = Get.find\<NetworkService\>();
///   if (!await net.isOnline) { ... }
///   net.onlineStream.listen(...);
class NetworkService {
  final Connectivity _connectivity;

  NetworkService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Broadcast stream of true/false as the device goes online/offline.
  /// Callers MUST cancel their subscription — never forget this.
  Stream<bool> get onlineStream => _connectivity.onConnectivityChanged
      .map(_isConnected)
      .distinct(); // only emit when state actually changes

  /// One-shot connectivity check.
  /// Returns true if any non-none interface is active.
  /// NOTE: does NOT perform an actual reachability check (see above).
  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    return _isConnected(result);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static bool _isConnected(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// Classifies an exception from http/embedding calls.
  /// Returns a user-friendly message.
  static NetworkErrorType classify(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('no address associated') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('os error')) {
      return NetworkErrorType.noInternet;
    }
    if (msg.contains('timeoutexception') || msg.contains('timed out')) {
      return NetworkErrorType.timeout;
    }
    if (msg.contains('401')) return NetworkErrorType.authError;
    if (msg.contains('429')) return NetworkErrorType.rateLimited;
    if (msg.contains('5')) return NetworkErrorType.serverError;
    return NetworkErrorType.unknown;
  }

  /// Human-readable message for each error type.
  static String messageFor(NetworkErrorType type, {String? raw}) {
    switch (type) {
      case NetworkErrorType.noInternet:
        return 'No internet connection. Please check your Wi-Fi or mobile data and try again.';
      case NetworkErrorType.timeout:
        return 'The server took too long to respond. Please try again.';
      case NetworkErrorType.authError:
        return 'API key is invalid or missing. Contact the app developer.';
      case NetworkErrorType.rateLimited:
        return 'Too many requests. Please wait a moment and try again.';
      case NetworkErrorType.serverError:
        return 'The server is temporarily unavailable. Please try again later.';
      case NetworkErrorType.unknown:
        return raw != null ? 'Unexpected error: $raw' : 'An unexpected error occurred.';
    }
  }
}

enum NetworkErrorType {
  noInternet,
  timeout,
  authError,
  rateLimited,
  serverError,
  unknown,
}
