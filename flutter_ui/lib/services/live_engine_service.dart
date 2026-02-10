/// Live Engine Service — WebSocket/TCP connection to game engines
///
/// Provides real-time bidirectional communication with game engines
/// for live STAGE event streaming and command sending.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/stage_models.dart';

// =============================================================================
// LIVE ENGINE SERVICE
// =============================================================================

/// Service for live WebSocket/TCP connection to game engines
class LiveEngineService {
  LiveEngineService._();
  static final instance = LiveEngineService._();

  // --- Connection State ---
  WebSocketChannel? _wsChannel;
  Socket? _tcpSocket;
  ConnectionConfig? _config;
  EngineConnectionState _state = EngineConnectionState.disconnected;

  // --- Streams ---
  final _stateController = StreamController<EngineConnectionState>.broadcast();
  final _eventController = StreamController<StageEvent>.broadcast();
  final _messageController = StreamController<EngineMessage>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // --- Reconnection ---
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 5;
  static const _reconnectDelayMs = 2000;

  // --- Recording ---
  bool _isRecording = false;
  final List<RecordedEvent> _recordedEvents = [];
  DateTime? _recordingStartTime;

  // =============================================================================
  // GETTERS
  // =============================================================================

  EngineConnectionState get state => _state;
  Stream<EngineConnectionState> get stateStream => _stateController.stream;
  Stream<StageEvent> get eventStream => _eventController.stream;
  Stream<EngineMessage> get messageStream => _messageController.stream;
  Stream<String> get errorStream => _errorController.stream;

  bool get isConnected => _state == EngineConnectionState.connected;
  bool get isRecording => _isRecording;
  List<RecordedEvent> get recordedEvents => List.unmodifiable(_recordedEvents);
  ConnectionConfig? get currentConfig => _config;

  // =============================================================================
  // CONNECTION
  // =============================================================================

  /// Connect to engine with given config
  Future<bool> connect(ConnectionConfig config) async {
    if (_state == EngineConnectionState.connecting ||
        _state == EngineConnectionState.connected) {
      return false;
    }

    _config = config;
    _setState(EngineConnectionState.connecting);
    _reconnectAttempts = 0;

    try {
      if (config.protocol == ConnectionProtocol.webSocket) {
        return await _connectWebSocket(config);
      } else {
        return await _connectTcp(config);
      }
    } catch (e) {
      _handleError('Connection failed: $e');
      _setState(EngineConnectionState.error);
      return false;
    }
  }

  /// Connect via WebSocket
  Future<bool> _connectWebSocket(ConnectionConfig config) async {
    final url = config.url ?? 'ws://${config.host}:${config.port}';

    try {
      _wsChannel = WebSocketChannel.connect(
        Uri.parse(url),
        protocols: config.authToken != null ? [config.authToken!] : null,
      );

      // Wait for connection
      await _wsChannel!.ready.timeout(
        Duration(milliseconds: config.timeoutMs),
        onTimeout: () {
          throw TimeoutException('Connection timeout');
        },
      );

      // Listen to messages
      _wsChannel!.stream.listen(
        _onWebSocketMessage,
        onError: _onWebSocketError,
        onDone: _onWebSocketDone,
      );

      _setState(EngineConnectionState.connected);
      return true;
    } catch (e) {
      _handleError('WebSocket connection failed: $e');
      _setState(EngineConnectionState.error);
      return false;
    }
  }

  /// Connect via TCP
  Future<bool> _connectTcp(ConnectionConfig config) async {
    try {
      _tcpSocket = await Socket.connect(
        config.host,
        config.port,
        timeout: Duration(milliseconds: config.timeoutMs),
      );

      // Listen to data
      _tcpSocket!.listen(
        _onTcpData,
        onError: _onTcpError,
        onDone: _onTcpDone,
      );

      _setState(EngineConnectionState.connected);
      return true;
    } catch (e) {
      _handleError('TCP connection failed: $e');
      _setState(EngineConnectionState.error);
      return false;
    }
  }

  /// Disconnect from engine
  Future<void> disconnect() async {
    if (_state == EngineConnectionState.disconnected) return;

    _setState(EngineConnectionState.disconnecting);
    _reconnectTimer?.cancel();

    try {
      await _wsChannel?.sink.close();
      _wsChannel = null;

      _tcpSocket?.destroy();
      _tcpSocket = null;
    } catch (e) { /* ignored */ }

    _setState(EngineConnectionState.disconnected);
  }

  // =============================================================================
  // MESSAGE HANDLING
  // =============================================================================

  void _onWebSocketMessage(dynamic message) {
    if (message is String) {
      _processMessage(message);
    } else if (message is List<int>) {
      _processMessage(utf8.decode(message));
    }
  }

  void _onWebSocketError(Object error) {
    _handleError('WebSocket error: $error');
    _attemptReconnect();
  }

  void _onWebSocketDone() {
    if (_state == EngineConnectionState.connected) {
      _attemptReconnect();
    }
  }

  void _onTcpData(List<int> data) {
    final message = utf8.decode(data);
    _processMessage(message);
  }

  void _onTcpError(Object error) {
    _handleError('TCP error: $error');
    _attemptReconnect();
  }

  void _onTcpDone() {
    if (_state == EngineConnectionState.connected) {
      _attemptReconnect();
    }
  }

  /// Process incoming message
  void _processMessage(String rawMessage) {
    try {
      final json = jsonDecode(rawMessage) as Map<String, dynamic>;

      // Parse message type
      final type = json['type'] as String?;

      switch (type) {
        case 'stage_event':
          _processStageEvent(json);

        case 'engine_state':
          _processEngineState(json);

        case 'command_response':
          _processCommandResponse(json);

        case 'error':
          _handleError(json['message'] as String? ?? 'Unknown error');

        default:
          // Try to parse as stage event anyway
          if (json.containsKey('stage') || json.containsKey('event')) {
            _processStageEvent(json);
          } else {
          }
      }

      // Emit raw message
      _messageController.add(EngineMessage.fromJson(json));
    } catch (e) { /* ignored */ }
  }

  void _processStageEvent(Map<String, dynamic> json) {
    try {
      // Extract stage data
      final stageData = json['stage'] ?? json['data'] ?? json;
      final stageName =
          stageData['type'] as String? ?? stageData['name'] as String?;

      if (stageName == null) {
        return;
      }

      // Parse stage
      final stage = Stage.fromTypeName(stageName, stageData);
      if (stage == null) {
        return;
      }

      // Create event
      final timestamp = (json['timestamp'] as num?)?.toDouble() ??
          DateTime.now().millisecondsSinceEpoch.toDouble();

      final event = StageEvent(
        stage: stage,
        timestampMs: timestamp,
        sourceEvent: json['source'] as String?,
        payload: json['payload'] != null
            ? StagePayload.fromJson(json['payload'] as Map<String, dynamic>)
            : const StagePayload(),
      );

      // Emit event
      _eventController.add(event);

      // Record if recording
      if (_isRecording && _recordingStartTime != null) {
        _recordedEvents.add(RecordedEvent(
          event: event,
          recordedAt: DateTime.now(),
          relativeTimeMs: DateTime.now()
              .difference(_recordingStartTime!)
              .inMilliseconds
              .toDouble(),
        ));
      }

    } catch (e) { /* ignored */ }
  }

  void _processEngineState(Map<String, dynamic> json) {
  }

  void _processCommandResponse(Map<String, dynamic> json) {
  }

  // =============================================================================
  // COMMAND SENDING
  // =============================================================================

  /// Send command to engine
  Future<bool> sendCommand(EngineCommand command) async {
    if (!isConnected) {
      return false;
    }

    try {
      final json = jsonEncode(command.toJson());

      if (_wsChannel != null) {
        _wsChannel!.sink.add(json);
      } else if (_tcpSocket != null) {
        _tcpSocket!.write('$json\n');
      } else {
        return false;
      }

      return true;
    } catch (e) {
      _handleError('Failed to send command: $e');
      return false;
    }
  }

  /// Send raw JSON message
  Future<bool> sendRaw(String json) async {
    if (!isConnected) return false;

    try {
      if (_wsChannel != null) {
        _wsChannel!.sink.add(json);
      } else if (_tcpSocket != null) {
        _tcpSocket!.write('$json\n');
      } else {
        return false;
      }
      return true;
    } catch (e) {
      _handleError('Failed to send message: $e');
      return false;
    }
  }

  // =============================================================================
  // RECORDING
  // =============================================================================

  /// Start recording events
  void startRecording() {
    _isRecording = true;
    _recordedEvents.clear();
    _recordingStartTime = DateTime.now();
  }

  /// Stop recording and return events
  List<RecordedEvent> stopRecording() {
    _isRecording = false;
    _recordingStartTime = null;
    final events = List<RecordedEvent>.from(_recordedEvents);
    return events;
  }

  /// Clear recorded events
  void clearRecording() {
    _recordedEvents.clear();
  }

  /// Export recorded events to JSON
  String exportRecordingJson() {
    final events = _recordedEvents
        .map((e) => {
              'event': e.event.toJson(),
              'recorded_at': e.recordedAt.toIso8601String(),
              'relative_time_ms': e.relativeTimeMs,
            })
        .toList();

    return jsonEncode({
      'version': '1.0',
      'recorded_at': DateTime.now().toIso8601String(),
      'event_count': events.length,
      'events': events,
    });
  }

  // =============================================================================
  // RECONNECTION
  // =============================================================================

  void _attemptReconnect() {
    if (_config == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _handleError('Max reconnection attempts reached');
      _setState(EngineConnectionState.error);
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

  }

  // =============================================================================
  // HELPERS
  // =============================================================================

  void _setState(EngineConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  void _handleError(String message) {
    _errorController.add(message);
  }

  /// Dispose resources
  void dispose() {
    _reconnectTimer?.cancel();
    _wsChannel?.sink.close();
    _tcpSocket?.destroy();
    _stateController.close();
    _eventController.close();
    _messageController.close();
    _errorController.close();
  }
}

// =============================================================================
// RECORDED EVENT
// =============================================================================

/// A recorded stage event with timing info
class RecordedEvent {
  final StageEvent event;
  final DateTime recordedAt;
  final double relativeTimeMs;

  const RecordedEvent({
    required this.event,
    required this.recordedAt,
    required this.relativeTimeMs,
  });

  Map<String, dynamic> toJson() => {
        'event': event.toJson(),
        'recorded_at': recordedAt.toIso8601String(),
        'relative_time_ms': relativeTimeMs,
      };
}

// =============================================================================
// ENGINE MESSAGE
// =============================================================================

/// Raw message from engine
class EngineMessage {
  final String type;
  final Map<String, dynamic> data;
  final DateTime receivedAt;

  EngineMessage({
    required this.type,
    required this.data,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory EngineMessage.fromJson(Map<String, dynamic> json) {
    return EngineMessage(
      type: json['type'] as String? ?? 'unknown',
      data: json,
    );
  }
}
