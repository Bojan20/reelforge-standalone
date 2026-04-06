/// GPT Browser Bridge Service — CORTEX ↔ ChatGPT via Chrome Extension
///
/// Manages the bidirectional communication between Corti and ChatGPT
/// running in the browser. No API key — uses WebSocket + Chrome extension.
///
/// Features:
/// - Periodic polling for GPT responses (configurable interval)
/// - Connection status monitoring
/// - Query queueing with intent classification
/// - Conversation memory management
/// - Stream-based response delivery to UI
///
/// Usage:
/// ```dart
/// final gpt = GptBridgeService.instance;
/// gpt.start(); // Begin polling
///
/// // Send a query
/// gpt.sendQuery('Šta misliš o ovom kodu?');
///
/// // Listen for responses
/// gpt.responseStream.listen((response) {
///   print('GPT: ${response.content}');
/// });
/// ```

import 'dart:async';

import '../src/rust/native_ffi.dart';
import '../src/rust/gpt_bridge_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class GptBridgeService {
  // Singleton
  static GptBridgeService? _instance;
  static GptBridgeService get instance => _instance ??= GptBridgeService._();
  GptBridgeService._();

  // Polling
  Timer? _pollTimer;
  Timer? _statusTimer;
  bool _running = false;

  // Streams
  final _responseController =
      StreamController<GptBridgeResponse>.broadcast();
  final _statusController =
      StreamController<GptBridgeStats>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  // State
  GptBridgeStats? _lastStats;
  bool _lastConnected = false;

  /// Stream of GPT responses (from ChatGPT browser).
  Stream<GptBridgeResponse> get responseStream => _responseController.stream;

  /// Stream of bridge statistics (updated every few seconds).
  Stream<GptBridgeStats> get statsStream => _statusController.stream;

  /// Stream of browser connection state changes.
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Last known stats.
  GptBridgeStats? get lastStats => _lastStats;

  /// Is the bridge ready (WebSocket server running)?
  bool get isReady {
    try {
      return NativeFFI.instance.gptBridgeIsReady();
    } catch (_) {
      return false;
    }
  }

  /// Is the browser (Chrome extension) connected right now?
  bool get isBrowserConnected {
    try {
      return NativeFFI.instance.gptBridgeBrowserConnected();
    } catch (_) {
      return false;
    }
  }

  /// Start polling for responses and monitoring connection.
  void start({
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration statusInterval = const Duration(seconds: 3),
  }) {
    if (_running) return;
    _running = true;

    // Poll for responses
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollResponses());

    // Monitor connection status
    _statusTimer = Timer.periodic(statusInterval, (_) => _updateStatus());

    // Initial status check
    _updateStatus();
  }

  /// Stop polling.
  void stop() {
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  /// Send a query to ChatGPT via the browser.
  /// Returns true if the query was sent (browser must be connected).
  bool sendQuery(
    String query, {
    String context = '',
    GptQueryIntent intent = GptQueryIntent.userQuery,
  }) {
    try {
      return NativeFFI.instance.gptBridgeSendQuery(
        query,
        context: context,
        intent: intent,
      );
    } catch (e) {
      return false;
    }
  }

  /// Get current bridge statistics.
  GptBridgeStats? getStats() {
    try {
      final stats = NativeFFI.instance.gptBridgeStats();
      _lastStats = stats;
      return stats;
    } catch (_) {
      return null;
    }
  }

  /// Update bridge configuration.
  bool updateConfig({
    bool? autonomousEnabled,
    int? minQueryIntervalSecs,
    int? responseTimeoutSecs,
  }) {
    try {
      return NativeFFI.instance.gptBridgeUpdateConfig(
        autonomousEnabled: autonomousEnabled,
        minQueryIntervalSecs: minQueryIntervalSecs,
        responseTimeoutSecs: responseTimeoutSecs,
      );
    } catch (_) {
      return false;
    }
  }

  /// Clear conversation memory and start new chat in browser.
  void clearConversation() {
    try {
      NativeFFI.instance.gptBridgeClearConversation();
    } catch (_) {
      // Bridge not initialized
    }
  }

  /// Shutdown the bridge.
  void shutdown() {
    stop();
    try {
      NativeFFI.instance.gptBridgeShutdown();
    } catch (_) {
      // Bridge not initialized
    }
  }

  /// Dispose all resources.
  void dispose() {
    stop();
    _responseController.close();
    _statusController.close();
    _connectionController.close();
    _instance = null;
  }

  // ─── Internal ──────────────────────────────────────────────────────────

  void _pollResponses() {
    try {
      final responses = NativeFFI.instance.gptBridgeDrainResponses();
      for (final response in responses) {
        if (response.content.isNotEmpty) {
          _responseController.add(response);
        }
      }
    } catch (_) {
      // Bridge not initialized or FFI error — silent
    }
  }

  void _updateStatus() {
    try {
      final stats = NativeFFI.instance.gptBridgeStats();
      _lastStats = stats;
      _statusController.add(stats);

      // Detect connection changes
      final connected = stats.browserConnected;
      if (connected != _lastConnected) {
        _lastConnected = connected;
        _connectionController.add(connected);
      }
    } catch (_) {
      // Bridge not initialized
    }
  }
}
