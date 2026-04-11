// file: flutter_ui/lib/providers/brain_provider.dart
/// Brain Provider — AI streaming query state for Flutter UI.
///
/// Connects to cortex-daemon via SSE streaming for real-time AI responses.
/// Widgets listen to [BrainProvider] for:
///   - Streaming text as it arrives (word by word)
///   - Query state (idle, streaming, error)
///   - Query history for the session
///
/// Usage:
/// ```dart
/// final brain = sl.get<BrainProvider>();
/// brain.streamQuery('Analiziraj ovaj audio graph');
/// // Widget rebuilds as text streams in
/// ```

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/cortex_daemon_client.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

enum BrainQueryState {
  idle,
  connecting,
  streaming,
  complete,
  error,
}

/// A single query + response pair.
class BrainConversationEntry {
  final String query;
  final String response;
  final String model;
  final int latencyMs;
  final double costUsd;
  final DateTime timestamp;
  final bool isError;

  const BrainConversationEntry({
    required this.query,
    required this.response,
    this.model = '',
    this.latencyMs = 0,
    this.costUsd = 0.0,
    required this.timestamp,
    this.isError = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Reactive AI brain state — streams Claude responses to the UI in real-time.
class BrainProvider extends ChangeNotifier {
  final CortexDaemonClient _client = CortexDaemonClient.instance;

  // ─── State ────────────────────────────────────────────────────────────────
  BrainQueryState _state = BrainQueryState.idle;
  String _streamingText = '';
  String _currentQuery = '';
  String _errorMessage = '';
  String _lastModel = '';
  int _lastLatencyMs = 0;
  double _lastCostUsd = 0;
  bool _daemonConnected = false;
  StreamSubscription<DaemonStreamEvent>? _activeStream;

  // Session conversation history (last 50 entries)
  final List<BrainConversationEntry> _history = [];
  static const int _maxHistory = 50;

  // Stream controller for raw events — listeners who want chunk-by-chunk
  final StreamController<DaemonStreamEvent> _eventController =
      StreamController<DaemonStreamEvent>.broadcast();

  // ─── Getters ──────────────────────────────────────────────────────────────
  BrainQueryState get state => _state;
  String get streamingText => _streamingText;
  String get currentQuery => _currentQuery;
  String get errorMessage => _errorMessage;
  String get lastModel => _lastModel;
  int get lastLatencyMs => _lastLatencyMs;
  double get lastCostUsd => _lastCostUsd;
  bool get isDaemonConnected => _daemonConnected;
  bool get isStreaming => _state == BrainQueryState.streaming;
  bool get isIdle => _state == BrainQueryState.idle || _state == BrainQueryState.complete;
  List<BrainConversationEntry> get history => List.unmodifiable(_history);
  Stream<DaemonStreamEvent> get eventStream => _eventController.stream;

  // ─── Actions ──────────────────────────────────────────────────────────────

  /// Check if the daemon is alive.
  Future<bool> checkDaemon() async {
    final status = await _client.getStatus();
    _daemonConnected = status != null;
    notifyListeners();
    return _daemonConnected;
  }

  /// Send a streaming query to the daemon.
  /// Text appears in [streamingText] in real-time as chunks arrive.
  void streamQuery(
    String query, {
    String context = '',
    String? systemPrompt,
  }) {
    // Cancel any in-flight query
    cancelQuery();

    _state = BrainQueryState.connecting;
    _streamingText = '';
    _currentQuery = query;
    _errorMessage = '';
    notifyListeners();

    final stream = _client.streamQuery(
      query,
      context: context,
      systemPrompt: systemPrompt,
    );

    _activeStream = stream.listen(
      (event) {
        _daemonConnected = true;

        if (event.isChunk) {
          _state = BrainQueryState.streaming;
          _streamingText += event.text;
          notifyListeners();
        } else if (event.isResult) {
          _state = BrainQueryState.complete;
          // Use the full content from result (authoritative)
          _streamingText = event.content;
          _lastModel = event.model;
          _lastLatencyMs = event.latencyMs;
          _lastCostUsd = event.costUsd;

          _addToHistory(BrainConversationEntry(
            query: query,
            response: event.content,
            model: event.model,
            latencyMs: event.latencyMs,
            costUsd: event.costUsd,
            timestamp: DateTime.now(),
          ));

          notifyListeners();
        } else if (event.isError) {
          _state = BrainQueryState.error;
          _errorMessage = event.errorMessage;

          _addToHistory(BrainConversationEntry(
            query: query,
            response: event.errorMessage,
            timestamp: DateTime.now(),
            isError: true,
          ));

          notifyListeners();
        }

        // Forward to raw event stream
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }
      },
      onError: (e) {
        _state = BrainQueryState.error;
        _errorMessage = e.toString();
        notifyListeners();
      },
      onDone: () {
        if (_state == BrainQueryState.streaming) {
          // Stream ended without explicit result — use accumulated text
          _state = BrainQueryState.complete;

          _addToHistory(BrainConversationEntry(
            query: query,
            response: _streamingText,
            timestamp: DateTime.now(),
          ));

          notifyListeners();
        }
        _activeStream = null;
      },
    );
  }

  /// Cancel the current streaming query.
  void cancelQuery() {
    _activeStream?.cancel();
    _activeStream = null;
    if (_state == BrainQueryState.streaming ||
        _state == BrainQueryState.connecting) {
      _state = BrainQueryState.idle;
      notifyListeners();
    }
  }

  /// Clear conversation history.
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  void _addToHistory(BrainConversationEntry entry) {
    _history.add(entry);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    _eventController.close();
    super.dispose();
  }
}
