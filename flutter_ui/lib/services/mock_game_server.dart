/// Mock Game Server — Local WebSocket server for testing
///
/// Simulates a game server for development/testing without real server.
/// Modes:
/// - Echo: sends back received messages
/// - Auto: periodically sends trigger/rtpc/state messages
/// - Script: plays back a recorded sequence of events
///
/// Runs on localhost, configurable port.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Mock server mode
enum MockServerMode {
  /// Echo received messages back to client
  echo,
  /// Auto-generate game events periodically
  auto,
  /// Stopped
  stopped,
}

/// Mock Game Server — singleton
class MockGameServer with ChangeNotifier {
  MockGameServer._();
  static final instance = MockGameServer._();

  HttpServer? _httpServer;
  WebSocket? _clientSocket;
  MockServerMode _mode = MockServerMode.stopped;
  int _port = 9090;
  Timer? _autoTimer;
  int _seq = 0;

  // Auto mode config
  double _autoIntervalMs = 2000;
  final List<Map<String, dynamic>> _autoEvents = [];

  // Stats
  int _messagesSent = 0;
  int _messagesReceived = 0;
  bool _clientConnected = false;

  // Getters
  MockServerMode get mode => _mode;
  int get port => _port;
  bool get isRunning => _mode != MockServerMode.stopped;
  bool get clientConnected => _clientConnected;
  int get messagesSent => _messagesSent;
  int get messagesReceived => _messagesReceived;

  /// Start mock server
  Future<bool> start({int port = 9090, MockServerMode mode = MockServerMode.echo}) async {
    if (isRunning) return false;
    _port = port;

    try {
      _httpServer = await HttpServer.bind('127.0.0.1', port);
      _mode = mode;
      _seq = 0;

      _httpServer!.transform(WebSocketTransformer()).listen(
        _onClientConnected,
        onError: (e) {},
        onDone: () {
          _mode = MockServerMode.stopped;
          notifyListeners();
        },
      );

      if (mode == MockServerMode.auto) {
        _startAutoMode();
      }

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop mock server
  Future<void> stop() async {
    _autoTimer?.cancel();
    _autoTimer = null;
    await _clientSocket?.close();
    _clientSocket = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
    _mode = MockServerMode.stopped;
    _clientConnected = false;
    notifyListeners();
  }

  /// Send a custom message to connected client
  void sendMessage(Map<String, dynamic> msg) {
    if (_clientSocket == null) return;
    msg['seq'] = ++_seq;
    msg['ts'] = DateTime.now().millisecondsSinceEpoch;
    try {
      _clientSocket!.add(jsonEncode(msg));
      _messagesSent++;
      notifyListeners();
    } catch (_) {}
  }

  /// Send a trigger event
  void sendTrigger(String eventId, {Map<String, dynamic>? params}) {
    sendMessage({
      'type': 'trigger',
      'event': eventId,
      if (params != null) 'params': params,
    });
  }

  /// Send an RTPC value
  void sendRtpc(String param, double value, {int durationMs = 200}) {
    sendMessage({
      'type': 'rtpc',
      'param': param,
      'value': value,
      'duration_ms': durationMs,
    });
  }

  /// Send a state change
  void sendState(String state, {Map<String, dynamic>? params, int transitionMs = 500}) {
    sendMessage({
      'type': 'state',
      'state': state,
      if (params != null) 'params': params,
      'transition_ms': transitionMs,
    });
  }

  /// Send a full snapshot (for testing reconnect recovery)
  void sendSnapshot(Map<String, double> rtpcState, {String? gameState}) {
    sendMessage({
      'type': 'snapshot',
      'state': rtpcState,
      if (gameState != null) 'game_state': gameState,
    });
  }

  /// Configure auto mode events
  void setAutoEvents(List<Map<String, dynamic>> events, {double intervalMs = 2000}) {
    _autoEvents.clear();
    _autoEvents.addAll(events);
    _autoIntervalMs = intervalMs;
    if (_mode == MockServerMode.auto) {
      _startAutoMode();
    }
  }

  /// Default auto events (simulate a slot game cycle)
  void setDefaultAutoEvents() {
    setAutoEvents([
      {'type': 'state', 'state': 'BASE_GAME'},
      {'type': 'trigger', 'event': 'SPIN_START'},
      {'type': 'rtpc', 'param': 'anticipation', 'value': 0.3},
      {'type': 'trigger', 'event': 'REEL_STOP', 'params': {'reel': 0}},
      {'type': 'rtpc', 'param': 'anticipation', 'value': 0.5},
      {'type': 'trigger', 'event': 'REEL_STOP', 'params': {'reel': 1}},
      {'type': 'rtpc', 'param': 'anticipation', 'value': 0.8},
      {'type': 'trigger', 'event': 'REEL_STOP', 'params': {'reel': 2}},
      {'type': 'rtpc', 'param': 'anticipation', 'value': 0.0},
      {'type': 'trigger', 'event': 'WIN_SMALL'},
      {'type': 'rtpc', 'param': 'celebration', 'value': 0.4, 'duration_ms': 1000},
      {'type': 'rtpc', 'param': 'celebration', 'value': 0.0, 'duration_ms': 500},
    ], intervalMs: 500);
  }

  // ═══════════════════════════════════════════════════════════════
  // PRIVATE
  // ═══════════════════════════════════════════════════════════════

  void _onClientConnected(WebSocket socket) {
    _clientSocket = socket;
    _clientConnected = true;
    notifyListeners();

    socket.listen(
      (data) {
        _messagesReceived++;
        if (_mode == MockServerMode.echo && data is String) {
          // Echo mode: send back
          try {
            final msg = jsonDecode(data) as Map<String, dynamic>;
            msg['echo'] = true;
            sendMessage(msg);
          } catch (_) {}
        }
        notifyListeners();
      },
      onDone: () {
        _clientSocket = null;
        _clientConnected = false;
        notifyListeners();
      },
      onError: (_) {
        _clientSocket = null;
        _clientConnected = false;
        notifyListeners();
      },
    );
  }

  int _autoEventIndex = 0;

  void _startAutoMode() {
    _autoTimer?.cancel();
    _autoEventIndex = 0;
    if (_autoEvents.isEmpty) {
      setDefaultAutoEvents();
    }
    _autoTimer = Timer.periodic(
      Duration(milliseconds: _autoIntervalMs.round()),
      (_) {
        if (!_clientConnected || _autoEvents.isEmpty) return;
        sendMessage(Map<String, dynamic>.from(_autoEvents[_autoEventIndex]));
        _autoEventIndex = (_autoEventIndex + 1) % _autoEvents.length;
      },
    );
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
