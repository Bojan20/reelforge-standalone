/// FluxForge Studio — Ultimate WebSocket Client
///
/// Professional-grade bidirectional communication with game engines.
/// Features:
/// - Auto-reconnection with exponential backoff
/// - Message queuing during disconnection
/// - Binary protocol support (MessagePack)
/// - Heartbeat/ping-pong keepalive
/// - Message compression (DEFLATE)
/// - Request/response correlation
/// - Multiple channel subscriptions
/// - Latency monitoring
/// - Connection quality metrics
/// - Event batching and throttling
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// =============================================================================
// WEBSOCKET CLIENT CONFIGURATION
// =============================================================================

/// Configuration for WebSocket client
class WebSocketConfig {
  final String url;
  final Duration connectionTimeout;
  final Duration pingInterval;
  final Duration pongTimeout;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;
  final int maxReconnectAttempts;
  final int maxQueueSize;
  final bool enableCompression;
  final bool enableBinaryProtocol;
  final Map<String, String>? headers;
  final List<String>? protocols;
  final String? authToken;

  const WebSocketConfig({
    required this.url,
    this.connectionTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 30),
    this.pongTimeout = const Duration(seconds: 10),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.maxReconnectAttempts = 10,
    this.maxQueueSize = 1000,
    this.enableCompression = false,
    this.enableBinaryProtocol = false,
    this.headers,
    this.protocols,
    this.authToken,
  });

  WebSocketConfig copyWith({
    String? url,
    Duration? connectionTimeout,
    Duration? pingInterval,
    Duration? pongTimeout,
    Duration? reconnectDelay,
    Duration? maxReconnectDelay,
    int? maxReconnectAttempts,
    int? maxQueueSize,
    bool? enableCompression,
    bool? enableBinaryProtocol,
    Map<String, String>? headers,
    List<String>? protocols,
    String? authToken,
  }) =>
      WebSocketConfig(
        url: url ?? this.url,
        connectionTimeout: connectionTimeout ?? this.connectionTimeout,
        pingInterval: pingInterval ?? this.pingInterval,
        pongTimeout: pongTimeout ?? this.pongTimeout,
        reconnectDelay: reconnectDelay ?? this.reconnectDelay,
        maxReconnectDelay: maxReconnectDelay ?? this.maxReconnectDelay,
        maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
        maxQueueSize: maxQueueSize ?? this.maxQueueSize,
        enableCompression: enableCompression ?? this.enableCompression,
        enableBinaryProtocol: enableBinaryProtocol ?? this.enableBinaryProtocol,
        headers: headers ?? this.headers,
        protocols: protocols ?? this.protocols,
        authToken: authToken ?? this.authToken,
      );
}

// =============================================================================
// CONNECTION STATE
// =============================================================================

/// WebSocket connection state
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  closing,
  closed,
  error;

  bool get isConnected => this == WsConnectionState.connected;
  bool get isConnecting =>
      this == WsConnectionState.connecting ||
      this == WsConnectionState.reconnecting;
  bool get isDisconnected =>
      this == WsConnectionState.disconnected ||
      this == WsConnectionState.closed;
}

/// Connection quality based on latency
enum ConnectionQuality {
  excellent, // < 50ms
  good, // < 100ms
  fair, // < 200ms
  poor, // < 500ms
  bad; // >= 500ms

  static ConnectionQuality fromLatency(Duration latency) {
    final ms = latency.inMilliseconds;
    if (ms < 50) return ConnectionQuality.excellent;
    if (ms < 100) return ConnectionQuality.good;
    if (ms < 200) return ConnectionQuality.fair;
    if (ms < 500) return ConnectionQuality.poor;
    return ConnectionQuality.bad;
  }

  String get displayName => switch (this) {
        excellent => 'Excellent',
        good => 'Good',
        fair => 'Fair',
        poor => 'Poor',
        bad => 'Bad',
      };

  int get bars => switch (this) {
        excellent => 4,
        good => 3,
        fair => 2,
        poor => 1,
        bad => 0,
      };
}

// =============================================================================
// MESSAGES
// =============================================================================

/// WebSocket message types
enum WsMessageType {
  // System
  ping,
  pong,
  subscribe,
  unsubscribe,
  ack,
  error,

  // Engine events
  stageEvent,
  engineState,
  metering,
  transport,

  // Commands
  command,
  request,
  response,

  // Custom
  custom;

  static WsMessageType fromString(String type) => switch (type) {
        'ping' => WsMessageType.ping,
        'pong' => WsMessageType.pong,
        'subscribe' => WsMessageType.subscribe,
        'unsubscribe' => WsMessageType.unsubscribe,
        'ack' => WsMessageType.ack,
        'error' => WsMessageType.error,
        'stage_event' => WsMessageType.stageEvent,
        'engine_state' => WsMessageType.engineState,
        'metering' => WsMessageType.metering,
        'transport' => WsMessageType.transport,
        'command' => WsMessageType.command,
        'request' => WsMessageType.request,
        'response' => WsMessageType.response,
        _ => WsMessageType.custom,
      };
}

/// WebSocket message envelope
class WsMessage {
  final String id;
  final WsMessageType type;
  final String? channel;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? correlationId;
  final int? sequence;

  WsMessage({
    String? id,
    required this.type,
    this.channel,
    Map<String, dynamic>? payload,
    DateTime? timestamp,
    this.correlationId,
    this.sequence,
  })  : id = id ?? _generateId(),
        payload = payload ?? {},
        timestamp = timestamp ?? DateTime.now();

  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${math.Random().nextInt(0xFFFF).toRadixString(16)}';

  factory WsMessage.ping() => WsMessage(type: WsMessageType.ping);

  factory WsMessage.pong(String pingId) => WsMessage(
        type: WsMessageType.pong,
        correlationId: pingId,
      );

  factory WsMessage.subscribe(String channel) => WsMessage(
        type: WsMessageType.subscribe,
        channel: channel,
      );

  factory WsMessage.unsubscribe(String channel) => WsMessage(
        type: WsMessageType.unsubscribe,
        channel: channel,
      );

  factory WsMessage.command(String command, Map<String, dynamic> params) =>
      WsMessage(
        type: WsMessageType.command,
        payload: {'command': command, ...params},
      );

  factory WsMessage.request(String method, Map<String, dynamic> params) =>
      WsMessage(
        type: WsMessageType.request,
        payload: {'method': method, 'params': params},
      );

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
        id: json['id'] as String?,
        type: WsMessageType.fromString(json['type'] as String? ?? 'custom'),
        channel: json['channel'] as String?,
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        correlationId: json['correlation_id'] as String?,
        sequence: json['seq'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (channel != null) 'channel': channel,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        if (correlationId != null) 'correlation_id': correlationId,
        if (sequence != null) 'seq': sequence,
      };

  String toJsonString() => jsonEncode(toJson());

  Uint8List toBinary() {
    // Simple binary format: [type(1)][id_len(1)][id][payload_len(4)][payload]
    final typeIndex = type.index;
    final idBytes = utf8.encode(id);
    final payloadBytes = utf8.encode(jsonEncode(payload));

    final buffer = BytesBuilder();
    buffer.addByte(typeIndex);
    buffer.addByte(idBytes.length);
    buffer.add(idBytes);
    buffer.add([
      (payloadBytes.length >> 24) & 0xFF,
      (payloadBytes.length >> 16) & 0xFF,
      (payloadBytes.length >> 8) & 0xFF,
      payloadBytes.length & 0xFF,
    ]);
    buffer.add(payloadBytes);

    return buffer.toBytes();
  }

  static WsMessage fromBinary(Uint8List data) {
    if (data.length < 6) {
      throw FormatException('Invalid binary message: too short');
    }

    final typeIndex = data[0];
    final idLen = data[1];

    if (data.length < 2 + idLen + 4) {
      throw FormatException('Invalid binary message: truncated');
    }

    final id = utf8.decode(data.sublist(2, 2 + idLen));
    final payloadLen = (data[2 + idLen] << 24) |
        (data[3 + idLen] << 16) |
        (data[4 + idLen] << 8) |
        data[5 + idLen];

    if (data.length < 6 + idLen + payloadLen) {
      throw FormatException('Invalid binary message: payload truncated');
    }

    final payloadBytes = data.sublist(6 + idLen, 6 + idLen + payloadLen);
    final payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;

    return WsMessage(
      id: id,
      type: WsMessageType.values[typeIndex.clamp(0, WsMessageType.values.length - 1)],
      payload: payload,
    );
  }
}

// =============================================================================
// CONNECTION METRICS
// =============================================================================

/// Connection metrics and statistics
class ConnectionMetrics {
  final DateTime connectedAt;
  final int messagesSent;
  final int messagesReceived;
  final int bytesSent;
  final int bytesReceived;
  final int reconnectCount;
  final Duration totalLatency;
  final int latencySamples;
  final Duration minLatency;
  final Duration maxLatency;
  final List<Duration> _latencyWindow;

  ConnectionMetrics({
    DateTime? connectedAt,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.reconnectCount = 0,
    this.totalLatency = Duration.zero,
    this.latencySamples = 0,
    this.minLatency = const Duration(hours: 1),
    this.maxLatency = Duration.zero,
    List<Duration>? latencyWindow,
  })  : connectedAt = connectedAt ?? DateTime.now(),
        _latencyWindow = latencyWindow ?? [];

  Duration get averageLatency =>
      latencySamples > 0 ? totalLatency ~/ latencySamples : Duration.zero;

  Duration get recentAverageLatency {
    if (_latencyWindow.isEmpty) return Duration.zero;
    final sum = _latencyWindow.fold<int>(
      0,
      (sum, d) => sum + d.inMicroseconds,
    );
    return Duration(microseconds: sum ~/ _latencyWindow.length);
  }

  ConnectionQuality get quality => ConnectionQuality.fromLatency(recentAverageLatency);

  Duration get connectionDuration => DateTime.now().difference(connectedAt);

  double get messagesPerSecond {
    final seconds = connectionDuration.inSeconds;
    return seconds > 0 ? messagesSent / seconds : 0;
  }

  ConnectionMetrics copyWith({
    int? messagesSent,
    int? messagesReceived,
    int? bytesSent,
    int? bytesReceived,
    int? reconnectCount,
    Duration? latency,
  }) {
    final newLatencyWindow = List<Duration>.from(_latencyWindow);
    if (latency != null) {
      newLatencyWindow.add(latency);
      if (newLatencyWindow.length > 20) {
        newLatencyWindow.removeAt(0);
      }
    }

    return ConnectionMetrics(
      connectedAt: connectedAt,
      messagesSent: messagesSent ?? this.messagesSent,
      messagesReceived: messagesReceived ?? this.messagesReceived,
      bytesSent: bytesSent ?? this.bytesSent,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      reconnectCount: reconnectCount ?? this.reconnectCount,
      totalLatency: latency != null ? totalLatency + latency : totalLatency,
      latencySamples: latency != null ? latencySamples + 1 : latencySamples,
      minLatency: latency != null && latency < minLatency ? latency : minLatency,
      maxLatency: latency != null && latency > maxLatency ? latency : maxLatency,
      latencyWindow: newLatencyWindow,
    );
  }

  Map<String, dynamic> toJson() => {
        'connected_at': connectedAt.toIso8601String(),
        'connection_duration_ms': connectionDuration.inMilliseconds,
        'messages_sent': messagesSent,
        'messages_received': messagesReceived,
        'bytes_sent': bytesSent,
        'bytes_received': bytesReceived,
        'reconnect_count': reconnectCount,
        'average_latency_ms': averageLatency.inMilliseconds,
        'recent_latency_ms': recentAverageLatency.inMilliseconds,
        'min_latency_ms': minLatency.inMilliseconds,
        'max_latency_ms': maxLatency.inMilliseconds,
        'quality': quality.name,
      };
}

// =============================================================================
// PENDING REQUEST
// =============================================================================

class _PendingRequest {
  final String id;
  final Completer<WsMessage> completer;
  final DateTime sentAt;
  final Timer? timeout;

  _PendingRequest({
    required this.id,
    required this.completer,
    required this.sentAt,
    this.timeout,
  });

  void complete(WsMessage response) {
    timeout?.cancel();
    if (!completer.isCompleted) {
      completer.complete(response);
    }
  }

  void completeError(Object error) {
    timeout?.cancel();
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }
}

// =============================================================================
// ULTIMATE WEBSOCKET CLIENT
// =============================================================================

/// Professional-grade WebSocket client with advanced features
class UltimateWebSocketClient {
  UltimateWebSocketClient._();
  static final instance = UltimateWebSocketClient._();

  // --- Configuration ---
  WebSocketConfig? _config;

  // --- Connection ---
  WebSocketChannel? _channel;
  WsConnectionState _state = WsConnectionState.disconnected;
  StreamSubscription<dynamic>? _subscription;

  // --- Streams ---
  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _messageController = StreamController<WsMessage>.broadcast();
  final _errorController = StreamController<WsError>.broadcast();
  final _metricsController = StreamController<ConnectionMetrics>.broadcast();

  // --- Channels (subscriptions) ---
  final Set<String> _subscribedChannels = {};
  final Map<String, StreamController<WsMessage>> _channelControllers = {};

  // --- Request/Response ---
  final Map<String, _PendingRequest> _pendingRequests = {};
  int _sequence = 0;

  // --- Message Queue ---
  final Queue<WsMessage> _messageQueue = Queue();

  // --- Keepalive ---
  Timer? _pingTimer;
  Timer? _pongTimer;
  DateTime? _lastPingSent;
  DateTime? _lastPongReceived;

  // --- Reconnection ---
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  // --- Metrics ---
  ConnectionMetrics _metrics = ConnectionMetrics();

  // --- Compression ---
  ZLibCodec? _compressor;

  // =============================================================================
  // GETTERS
  // =============================================================================

  WsConnectionState get state => _state;
  Stream<WsConnectionState> get stateStream => _stateController.stream;
  Stream<WsMessage> get messageStream => _messageController.stream;
  Stream<WsError> get errorStream => _errorController.stream;
  Stream<ConnectionMetrics> get metricsStream => _metricsController.stream;
  ConnectionMetrics get metrics => _metrics;
  WebSocketConfig? get config => _config;
  Set<String> get subscribedChannels => Set.unmodifiable(_subscribedChannels);

  bool get isConnected => _state == WsConnectionState.connected;
  bool get isConnecting => _state.isConnecting;

  Duration? get latency {
    if (_lastPingSent == null || _lastPongReceived == null) return null;
    return _lastPongReceived!.difference(_lastPingSent!);
  }

  ConnectionQuality? get connectionQuality {
    final lat = latency;
    return lat != null ? ConnectionQuality.fromLatency(lat) : null;
  }

  // =============================================================================
  // CONNECTION
  // =============================================================================

  /// Connect to WebSocket server
  Future<bool> connect(WebSocketConfig config) async {
    if (_state == WsConnectionState.connected ||
        _state == WsConnectionState.connecting) {
      debugPrint('[WS] Already connected or connecting');
      return false;
    }

    _config = config;
    _setState(WsConnectionState.connecting);
    _reconnectAttempts = 0;

    try {
      final success = await _doConnect();
      if (success) {
        _startKeepalive();
        _flushMessageQueue();
        return true;
      }
      return false;
    } catch (e) {
      _handleError('Connection failed', e);
      _setState(WsConnectionState.error);
      _scheduleReconnect();
      return false;
    }
  }

  Future<bool> _doConnect() async {
    final config = _config!;

    try {
      // Build WebSocket connection
      if (config.enableCompression) {
        _compressor = ZLibCodec(level: 6);
      }

      final uri = Uri.parse(config.url);

      // Create channel with custom headers if supported
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final socket = await WebSocket.connect(
          config.url,
          headers: {
            if (config.authToken != null)
              'Authorization': 'Bearer ${config.authToken}',
            ...?config.headers,
          },
          protocols: config.protocols,
        ).timeout(config.connectionTimeout);

        _channel = IOWebSocketChannel(socket);
      } else {
        _channel = WebSocketChannel.connect(
          uri,
          protocols: config.protocols,
        );

        await _channel!.ready.timeout(config.connectionTimeout);
      }

      // Listen to messages
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _setState(WsConnectionState.connected);
      _metrics = ConnectionMetrics();
      _metricsController.add(_metrics);

      debugPrint('[WS] Connected to ${config.url}');

      // Re-subscribe to channels
      for (final channel in _subscribedChannels) {
        _sendInternal(WsMessage.subscribe(channel));
      }

      return true;
    } catch (e) {
      debugPrint('[WS] Connection error: $e');
      _channel = null;
      return false;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    if (_state == WsConnectionState.disconnected ||
        _state == WsConnectionState.closed) {
      return;
    }

    _setState(WsConnectionState.closing);
    _stopKeepalive();
    _reconnectTimer?.cancel();

    try {
      await _subscription?.cancel();
      await _channel?.sink.close();
    } catch (e) {
      debugPrint('[WS] Disconnect error: $e');
    }

    _channel = null;
    _subscription = null;
    _setState(WsConnectionState.closed);

    debugPrint('[WS] Disconnected');
  }

  /// Reconnect to server
  Future<bool> reconnect() async {
    await disconnect();
    if (_config != null) {
      return connect(_config!);
    }
    return false;
  }

  // =============================================================================
  // MESSAGING
  // =============================================================================

  /// Send message (queued if disconnected)
  bool send(WsMessage message) {
    if (!isConnected) {
      if (_config != null && _messageQueue.length < _config!.maxQueueSize) {
        _messageQueue.add(message);
        debugPrint('[WS] Message queued (${_messageQueue.length} pending)');
        return true;
      }
      return false;
    }

    return _sendInternal(message);
  }

  bool _sendInternal(WsMessage message) {
    if (_channel == null) return false;

    try {
      final data = _config?.enableBinaryProtocol == true
          ? message.toBinary()
          : message.toJsonString();

      final bytes = data is Uint8List ? data : utf8.encode(data as String);
      final compressed =
          _compressor != null ? _compressor!.encode(bytes) : bytes;

      if (_config?.enableBinaryProtocol == true) {
        _channel!.sink.add(compressed);
      } else {
        _channel!.sink.add(
          _compressor != null ? compressed : message.toJsonString(),
        );
      }

      _metrics = _metrics.copyWith(
        messagesSent: _metrics.messagesSent + 1,
        bytesSent: _metrics.bytesSent + compressed.length,
      );

      return true;
    } catch (e) {
      _handleError('Send failed', e);
      return false;
    }
  }

  /// Send command and wait for response
  Future<WsMessage> request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final message = WsMessage.request(method, params);

    final completer = Completer<WsMessage>();
    final timeoutTimer = Timer(timeout, () {
      final pending = _pendingRequests.remove(message.id);
      pending?.completeError(TimeoutException('Request timeout: $method'));
    });

    _pendingRequests[message.id] = _PendingRequest(
      id: message.id,
      completer: completer,
      sentAt: DateTime.now(),
      timeout: timeoutTimer,
    );

    if (!send(message)) {
      _pendingRequests.remove(message.id);
      timeoutTimer.cancel();
      throw StateError('Failed to send request');
    }

    return completer.future;
  }

  /// Send command (fire-and-forget)
  bool command(String command, [Map<String, dynamic>? params]) {
    return send(WsMessage.command(command, params ?? {}));
  }

  void _flushMessageQueue() {
    while (_messageQueue.isNotEmpty && isConnected) {
      final message = _messageQueue.removeFirst();
      _sendInternal(message);
    }
    if (_messageQueue.isEmpty) {
      debugPrint('[WS] Message queue flushed');
    }
  }

  // =============================================================================
  // CHANNELS (Subscriptions)
  // =============================================================================

  /// Subscribe to a channel
  Stream<WsMessage> subscribe(String channel) {
    if (!_channelControllers.containsKey(channel)) {
      _channelControllers[channel] = StreamController<WsMessage>.broadcast();
    }

    if (!_subscribedChannels.contains(channel)) {
      _subscribedChannels.add(channel);
      if (isConnected) {
        send(WsMessage.subscribe(channel));
      }
    }

    return _channelControllers[channel]!.stream;
  }

  /// Unsubscribe from a channel
  void unsubscribe(String channel) {
    _subscribedChannels.remove(channel);
    _channelControllers[channel]?.close();
    _channelControllers.remove(channel);

    if (isConnected) {
      send(WsMessage.unsubscribe(channel));
    }
  }

  // =============================================================================
  // MESSAGE HANDLING
  // =============================================================================

  void _onMessage(dynamic data) {
    try {
      WsMessage message;

      if (data is Uint8List) {
        final decompressed =
            _compressor != null ? _compressor!.decode(data) : data;
        if (_config?.enableBinaryProtocol == true) {
          message = WsMessage.fromBinary(
              decompressed is Uint8List ? decompressed : Uint8List.fromList(decompressed));
        } else {
          final json = jsonDecode(utf8.decode(
              decompressed is Uint8List ? decompressed : Uint8List.fromList(decompressed)));
          message = WsMessage.fromJson(json as Map<String, dynamic>);
        }
      } else if (data is String) {
        final json = jsonDecode(data) as Map<String, dynamic>;
        message = WsMessage.fromJson(json);
      } else {
        debugPrint('[WS] Unknown message type: ${data.runtimeType}');
        return;
      }

      _metrics = _metrics.copyWith(
        messagesReceived: _metrics.messagesReceived + 1,
        bytesReceived:
            _metrics.bytesReceived + (data is String ? data.length : (data as Uint8List).length),
      );

      _processMessage(message);
    } catch (e) {
      debugPrint('[WS] Message parse error: $e');
      _handleError('Message parse error', e);
    }
  }

  void _processMessage(WsMessage message) {
    switch (message.type) {
      case WsMessageType.pong:
        _onPong(message);

      case WsMessageType.ping:
        send(WsMessage.pong(message.id));

      case WsMessageType.response:
        _onResponse(message);

      case WsMessageType.error:
        _handleError(
          message.payload['message'] as String? ?? 'Server error',
          message.payload['code'],
        );

      case WsMessageType.ack:
        debugPrint('[WS] ACK: ${message.correlationId}');

      default:
        // Route to channel if specified
        if (message.channel != null) {
          _channelControllers[message.channel]?.add(message);
        }

        // Emit to general stream
        _messageController.add(message);
    }
  }

  void _onResponse(WsMessage message) {
    final correlationId = message.correlationId;
    if (correlationId == null) return;

    final pending = _pendingRequests.remove(correlationId);
    if (pending != null) {
      final latency = DateTime.now().difference(pending.sentAt);
      _metrics = _metrics.copyWith(latency: latency);
      _metricsController.add(_metrics);

      pending.complete(message);
    }
  }

  void _onError(Object error) {
    _handleError('WebSocket error', error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WS] Connection closed');

    if (_state == WsConnectionState.connected) {
      _setState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  // =============================================================================
  // KEEPALIVE
  // =============================================================================

  void _startKeepalive() {
    _stopKeepalive();

    _pingTimer = Timer.periodic(
      _config?.pingInterval ?? const Duration(seconds: 30),
      (_) => _sendPing(),
    );
  }

  void _stopKeepalive() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  void _sendPing() {
    if (!isConnected) return;

    _lastPingSent = DateTime.now();
    final pingMessage = WsMessage.ping();
    _sendInternal(pingMessage);

    // Start pong timeout
    _pongTimer?.cancel();
    _pongTimer = Timer(
      _config?.pongTimeout ?? const Duration(seconds: 10),
      () {
        debugPrint('[WS] Pong timeout - connection may be dead');
        _handleError('Pong timeout', null);
        _scheduleReconnect();
      },
    );
  }

  void _onPong(WsMessage message) {
    _lastPongReceived = DateTime.now();
    _pongTimer?.cancel();

    if (_lastPingSent != null) {
      final latency = _lastPongReceived!.difference(_lastPingSent!);
      _metrics = _metrics.copyWith(latency: latency);
      _metricsController.add(_metrics);
    }
  }

  // =============================================================================
  // RECONNECTION
  // =============================================================================

  void _scheduleReconnect() {
    if (_config == null) return;
    if (_state == WsConnectionState.closing ||
        _state == WsConnectionState.closed) {
      return;
    }
    if (_reconnectAttempts >= _config!.maxReconnectAttempts) {
      debugPrint('[WS] Max reconnect attempts reached');
      _setState(WsConnectionState.error);
      _errorController.add(WsError(
        message: 'Max reconnection attempts reached',
        code: 'MAX_RECONNECT',
      ));
      return;
    }

    _reconnectTimer?.cancel();
    _setState(WsConnectionState.reconnecting);

    // Exponential backoff with jitter
    final baseDelay = _config!.reconnectDelay.inMilliseconds;
    final maxDelay = _config!.maxReconnectDelay.inMilliseconds;
    final exponentialDelay =
        (baseDelay * math.pow(2, _reconnectAttempts)).toInt();
    final clampedDelay = math.min(exponentialDelay, maxDelay);
    final jitter = (math.Random().nextDouble() * 0.3 * clampedDelay).toInt();
    final delay = Duration(milliseconds: clampedDelay + jitter);

    _reconnectAttempts++;
    debugPrint(
        '[WS] Reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () async {
      if (await _doConnect()) {
        _reconnectAttempts = 0;
        _metrics = ConnectionMetrics(
          reconnectCount: _metrics.reconnectCount + 1,
        );
        _startKeepalive();
        _flushMessageQueue();
      } else {
        _scheduleReconnect();
      }
    });
  }

  // =============================================================================
  // ERROR HANDLING
  // =============================================================================

  void _handleError(String message, Object? error) {
    debugPrint('[WS] Error: $message - $error');
    _errorController.add(WsError(
      message: message,
      error: error,
    ));
  }

  // =============================================================================
  // STATE
  // =============================================================================

  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  // =============================================================================
  // DISPOSE
  // =============================================================================

  Future<void> dispose() async {
    await disconnect();
    _stateController.close();
    _messageController.close();
    _errorController.close();
    _metricsController.close();

    for (final controller in _channelControllers.values) {
      controller.close();
    }
    _channelControllers.clear();

    for (final pending in _pendingRequests.values) {
      pending.completeError(StateError('Client disposed'));
    }
    _pendingRequests.clear();
  }
}

// =============================================================================
// ERROR CLASS
// =============================================================================

class WsError {
  final String message;
  final String? code;
  final Object? error;
  final DateTime timestamp;

  WsError({
    required this.message,
    this.code,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'WsError: $message${code != null ? ' ($code)' : ''}';
}

// =============================================================================
// METERING CHANNEL
// =============================================================================

/// Specialized handler for high-frequency metering data
class MeteringChannel {
  final UltimateWebSocketClient _client;
  final String channelName;
  final Duration throttleInterval;

  StreamSubscription<WsMessage>? _subscription;
  Timer? _throttleTimer;
  WsMessage? _lastMessage;

  final _controller = StreamController<MeteringData>.broadcast();

  MeteringChannel({
    UltimateWebSocketClient? client,
    this.channelName = 'metering',
    this.throttleInterval = const Duration(milliseconds: 50),
  }) : _client = client ?? UltimateWebSocketClient.instance;

  Stream<MeteringData> get stream => _controller.stream;

  void start() {
    _subscription = _client.subscribe(channelName).listen(_onMessage);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
  }

  void _onMessage(WsMessage message) {
    _lastMessage = message;

    if (_throttleTimer == null) {
      _emitMessage();
      _throttleTimer = Timer(throttleInterval, () {
        _throttleTimer = null;
        if (_lastMessage != null) {
          _emitMessage();
        }
      });
    }
  }

  void _emitMessage() {
    if (_lastMessage == null) return;

    try {
      final data = MeteringData.fromJson(_lastMessage!.payload);
      _controller.add(data);
    } catch (e) {
      debugPrint('[Metering] Parse error: $e');
    }

    _lastMessage = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Metering data structure
class MeteringData {
  final double leftPeak;
  final double rightPeak;
  final double leftRms;
  final double rightRms;
  final double lufsShort;
  final double lufsIntegrated;
  final double truePeak;
  final int samplePosition;
  final double timestamp;

  const MeteringData({
    this.leftPeak = -96.0,
    this.rightPeak = -96.0,
    this.leftRms = -96.0,
    this.rightRms = -96.0,
    this.lufsShort = -96.0,
    this.lufsIntegrated = -96.0,
    this.truePeak = -96.0,
    this.samplePosition = 0,
    this.timestamp = 0.0,
  });

  factory MeteringData.fromJson(Map<String, dynamic> json) => MeteringData(
        leftPeak: (json['left_peak'] as num?)?.toDouble() ?? -96.0,
        rightPeak: (json['right_peak'] as num?)?.toDouble() ?? -96.0,
        leftRms: (json['left_rms'] as num?)?.toDouble() ?? -96.0,
        rightRms: (json['right_rms'] as num?)?.toDouble() ?? -96.0,
        lufsShort: (json['lufs_short'] as num?)?.toDouble() ?? -96.0,
        lufsIntegrated: (json['lufs_integrated'] as num?)?.toDouble() ?? -96.0,
        truePeak: (json['true_peak'] as num?)?.toDouble() ?? -96.0,
        samplePosition: json['sample_position'] as int? ?? 0,
        timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'left_peak': leftPeak,
        'right_peak': rightPeak,
        'left_rms': leftRms,
        'right_rms': rightRms,
        'lufs_short': lufsShort,
        'lufs_integrated': lufsIntegrated,
        'true_peak': truePeak,
        'sample_position': samplePosition,
        'timestamp': timestamp,
      };
}

// =============================================================================
// STAGE EVENT CHANNEL
// =============================================================================

/// Specialized handler for stage events
class StageEventChannel {
  final UltimateWebSocketClient _client;
  final String channelName;

  StreamSubscription<WsMessage>? _subscription;
  final _controller = StreamController<StageEventData>.broadcast();

  // Event batching
  final List<StageEventData> _batch = [];
  Timer? _batchTimer;
  final Duration batchInterval;
  final int maxBatchSize;

  StageEventChannel({
    UltimateWebSocketClient? client,
    this.channelName = 'stage_events',
    this.batchInterval = const Duration(milliseconds: 16),
    this.maxBatchSize = 50,
  }) : _client = client ?? UltimateWebSocketClient.instance;

  Stream<StageEventData> get stream => _controller.stream;

  void start() {
    _subscription = _client.subscribe(channelName).listen(_onMessage);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _batchTimer?.cancel();
    _batchTimer = null;
    _batch.clear();
  }

  void _onMessage(WsMessage message) {
    try {
      final event = StageEventData.fromJson(message.payload);
      _batch.add(event);

      if (_batch.length >= maxBatchSize) {
        _flushBatch();
      } else {
        _batchTimer ??= Timer(batchInterval, _flushBatch);
      }
    } catch (e) {
      debugPrint('[StageEvent] Parse error: $e');
    }
  }

  void _flushBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;

    for (final event in _batch) {
      _controller.add(event);
    }
    _batch.clear();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Stage event data
class StageEventData {
  final String stageName;
  final String? category;
  final double timestampMs;
  final Map<String, dynamic> payload;

  const StageEventData({
    required this.stageName,
    this.category,
    required this.timestampMs,
    this.payload = const {},
  });

  factory StageEventData.fromJson(Map<String, dynamic> json) => StageEventData(
        stageName: json['stage'] as String? ?? json['type'] as String? ?? 'unknown',
        category: json['category'] as String?,
        timestampMs: (json['timestamp_ms'] as num?)?.toDouble() ??
            (json['timestamp'] as num?)?.toDouble() ??
            0.0,
        payload: json['payload'] as Map<String, dynamic>? ?? json,
      );

  Map<String, dynamic> toJson() => {
        'stage': stageName,
        if (category != null) 'category': category,
        'timestamp_ms': timestampMs,
        'payload': payload,
      };
}

// =============================================================================
// P3.13: LIVE PARAMETER UPDATE CHANNEL
// =============================================================================

/// Type of parameter update
enum ParameterUpdateType {
  rtpc,
  volume,
  pan,
  mute,
  solo,
  morphPosition,
  macroValue,
  containerState,
  stateGroup,
  switchGroup,
}

/// Live parameter update data
class ParameterUpdate {
  final ParameterUpdateType type;
  final String targetId;
  final double? numericValue;
  final String? stringValue;
  final bool? boolValue;
  final Map<String, dynamic>? metadata;
  final double timestampMs;

  const ParameterUpdate({
    required this.type,
    required this.targetId,
    this.numericValue,
    this.stringValue,
    this.boolValue,
    this.metadata,
    required this.timestampMs,
  });

  factory ParameterUpdate.rtpc(String rtpcId, double value) => ParameterUpdate(
        type: ParameterUpdateType.rtpc,
        targetId: rtpcId,
        numericValue: value,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.volume(String targetId, double value, {bool isBus = false}) =>
      ParameterUpdate(
        type: ParameterUpdateType.volume,
        targetId: targetId,
        numericValue: value,
        metadata: {'is_bus': isBus},
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.pan(String targetId, double value) => ParameterUpdate(
        type: ParameterUpdateType.pan,
        targetId: targetId,
        numericValue: value,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.mute(String targetId, bool muted) => ParameterUpdate(
        type: ParameterUpdateType.mute,
        targetId: targetId,
        boolValue: muted,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.morphPosition(String morphId, double position) =>
      ParameterUpdate(
        type: ParameterUpdateType.morphPosition,
        targetId: morphId,
        numericValue: position,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.macroValue(String macroId, double value) => ParameterUpdate(
        type: ParameterUpdateType.macroValue,
        targetId: macroId,
        numericValue: value,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.stateGroup(String groupId, String stateId) =>
      ParameterUpdate(
        type: ParameterUpdateType.stateGroup,
        targetId: groupId,
        stringValue: stateId,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.switchGroup(String groupId, String objectId, String switchId) =>
      ParameterUpdate(
        type: ParameterUpdateType.switchGroup,
        targetId: groupId,
        stringValue: switchId,
        metadata: {'object_id': objectId},
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory ParameterUpdate.fromJson(Map<String, dynamic> json) => ParameterUpdate(
        type: ParameterUpdateType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ParameterUpdateType.rtpc,
        ),
        targetId: json['target_id'] as String,
        numericValue: (json['numeric_value'] as num?)?.toDouble(),
        stringValue: json['string_value'] as String?,
        boolValue: json['bool_value'] as bool?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        timestampMs: (json['timestamp_ms'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'target_id': targetId,
        if (numericValue != null) 'numeric_value': numericValue,
        if (stringValue != null) 'string_value': stringValue,
        if (boolValue != null) 'bool_value': boolValue,
        if (metadata != null) 'metadata': metadata,
        'timestamp_ms': timestampMs,
      };
}

/// P3.13: Live parameter update channel with throttling
///
/// Sends parameter changes in real-time to connected game engines.
/// Supports throttling to prevent flooding with rapid slider movements.
class LiveParameterChannel {
  final UltimateWebSocketClient _client;
  final String channelName;
  final Duration throttleInterval;

  StreamSubscription<WsMessage>? _subscription;
  final _controller = StreamController<ParameterUpdate>.broadcast();

  // Outgoing throttle
  final Map<String, Timer> _throttleTimers = {};
  final Map<String, ParameterUpdate> _pendingUpdates = {};

  // Incoming handler
  void Function(ParameterUpdate)? onRemoteUpdate;

  LiveParameterChannel({
    UltimateWebSocketClient? client,
    this.channelName = 'parameters',
    this.throttleInterval = const Duration(milliseconds: 33), // ~30Hz max
    this.onRemoteUpdate,
  }) : _client = client ?? UltimateWebSocketClient.instance;

  Stream<ParameterUpdate> get stream => _controller.stream;

  bool get isConnected => _client.isConnected;

  /// Start listening for remote parameter updates
  void start() {
    _subscription = _client.subscribe(channelName).listen(_onMessage);
  }

  /// Stop listening
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    for (final timer in _throttleTimers.values) {
      timer.cancel();
    }
    _throttleTimers.clear();
    _pendingUpdates.clear();
  }

  /// Send parameter update (throttled)
  void send(ParameterUpdate update) {
    final key = '${update.type.name}:${update.targetId}';
    _pendingUpdates[key] = update;

    if (!_throttleTimers.containsKey(key)) {
      // Send immediately, then throttle subsequent updates
      _sendUpdate(update);
      _throttleTimers[key] = Timer(throttleInterval, () {
        _throttleTimers.remove(key);
        final pending = _pendingUpdates.remove(key);
        if (pending != null && pending != update) {
          _sendUpdate(pending);
        }
      });
    }
  }

  void _sendUpdate(ParameterUpdate update) {
    if (!_client.isConnected) return;

    _client.send(WsMessage(
      type: WsMessageType.custom,
      channel: channelName,
      payload: {
        'action': 'update',
        'update': update.toJson(),
      },
    ));
  }

  /// Send RTPC value
  void sendRtpc(String rtpcId, double value) {
    send(ParameterUpdate.rtpc(rtpcId, value));
  }

  /// Send volume
  void sendVolume(String targetId, double value, {bool isBus = false}) {
    send(ParameterUpdate.volume(targetId, value, isBus: isBus));
  }

  /// Send pan
  void sendPan(String targetId, double value) {
    send(ParameterUpdate.pan(targetId, value));
  }

  /// Send mute
  void sendMute(String targetId, bool muted) {
    send(ParameterUpdate.mute(targetId, muted));
  }

  /// Send morph position
  void sendMorphPosition(String morphId, double position) {
    send(ParameterUpdate.morphPosition(morphId, position));
  }

  /// Send macro value
  void sendMacroValue(String macroId, double value) {
    send(ParameterUpdate.macroValue(macroId, value));
  }

  /// Send state group change
  void sendStateChange(String groupId, String stateId) {
    send(ParameterUpdate.stateGroup(groupId, stateId));
  }

  /// Send switch change
  void sendSwitchChange(String groupId, String objectId, String switchId) {
    send(ParameterUpdate.switchGroup(groupId, objectId, switchId));
  }

  void _onMessage(WsMessage message) {
    try {
      final action = message.payload['action'] as String?;

      if (action == 'update') {
        final updateJson = message.payload['update'] as Map<String, dynamic>?;
        if (updateJson != null) {
          final update = ParameterUpdate.fromJson(updateJson);
          _controller.add(update);
          onRemoteUpdate?.call(update);
        }
      }
    } catch (e) {
      debugPrint('[LiveParam] Parse error: $e');
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
