/// WebSocket Connector with Token-Based Authentication
///
/// Provides secure WebSocket connection for live stage event streaming:
/// - Token-based authentication (JWT/API key)
/// - Auto-reconnect with exponential backoff
/// - Heartbeat/keep-alive
/// - Connection state management
/// - Message queue for offline buffering
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';


// ═══════════════════════════════════════════════════════════════════════════
// CONNECTION STATE
// ═══════════════════════════════════════════════════════════════════════════

enum WebSocketConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
  error,
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTH CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Authentication configuration for WebSocket connection
class WebSocketAuthConfig {
  /// Authentication type
  final WebSocketAuthType authType;

  /// API key (for apiKey auth)
  final String? apiKey;

  /// JWT token (for jwt auth)
  final String? jwtToken;

  /// Custom headers (for header-based auth)
  final Map<String, String>? customHeaders;

  /// Query parameters for authentication
  final Map<String, String>? queryParams;

  const WebSocketAuthConfig({
    this.authType = WebSocketAuthType.none,
    this.apiKey,
    this.jwtToken,
    this.customHeaders,
    this.queryParams,
  });

  /// Create API key auth config
  factory WebSocketAuthConfig.apiKey(String key) {
    return WebSocketAuthConfig(
      authType: WebSocketAuthType.apiKey,
      apiKey: key,
    );
  }

  /// Create JWT auth config
  factory WebSocketAuthConfig.jwt(String token) {
    return WebSocketAuthConfig(
      authType: WebSocketAuthType.jwt,
      jwtToken: token,
    );
  }

  /// Create header-based auth config
  factory WebSocketAuthConfig.headers(Map<String, String> headers) {
    return WebSocketAuthConfig(
      authType: WebSocketAuthType.headers,
      customHeaders: headers,
    );
  }

  /// Build authentication headers
  Map<String, String> buildHeaders() {
    final headers = <String, String>{};

    switch (authType) {
      case WebSocketAuthType.apiKey:
        if (apiKey != null) {
          headers['X-API-Key'] = apiKey!;
          headers['Authorization'] = 'ApiKey $apiKey';
        }
        break;
      case WebSocketAuthType.jwt:
        if (jwtToken != null) {
          headers['Authorization'] = 'Bearer $jwtToken';
        }
        break;
      case WebSocketAuthType.headers:
        if (customHeaders != null) {
          headers.addAll(customHeaders!);
        }
        break;
      case WebSocketAuthType.none:
        break;
    }

    return headers;
  }

  /// Build authentication message for post-connect auth
  Map<String, dynamic>? buildAuthMessage() {
    switch (authType) {
      case WebSocketAuthType.apiKey:
        return {
          'type': 'auth',
          'method': 'api_key',
          'api_key': apiKey,
        };
      case WebSocketAuthType.jwt:
        return {
          'type': 'auth',
          'method': 'jwt',
          'token': jwtToken,
        };
      case WebSocketAuthType.headers:
      case WebSocketAuthType.none:
        return null;
    }
  }

  /// Build URL with query params
  String buildUrl(String baseUrl) {
    if (queryParams == null || queryParams!.isEmpty) {
      return baseUrl;
    }

    final uri = Uri.parse(baseUrl);
    final newParams = Map<String, String>.from(uri.queryParameters);
    newParams.addAll(queryParams!);

    return uri.replace(queryParameters: newParams).toString();
  }
}

enum WebSocketAuthType {
  none,
  apiKey,
  jwt,
  headers,
}

// ═══════════════════════════════════════════════════════════════════════════
// CONNECTION CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// WebSocket connection configuration
class WebSocketConfig {
  /// Server URL (ws:// or wss://)
  final String url;

  /// Authentication configuration
  final WebSocketAuthConfig auth;

  /// Auto-reconnect on disconnect
  final bool autoReconnect;

  /// Maximum reconnect attempts (0 = unlimited)
  final int maxReconnectAttempts;

  /// Initial reconnect delay (ms)
  final int reconnectDelayMs;

  /// Maximum reconnect delay (ms)
  final int maxReconnectDelayMs;

  /// Heartbeat interval (ms), 0 = disabled
  final int heartbeatIntervalMs;

  /// Connection timeout (ms)
  final int connectionTimeoutMs;

  /// Ping timeout (ms)
  final int pingTimeoutMs;

  const WebSocketConfig({
    required this.url,
    this.auth = const WebSocketAuthConfig(),
    this.autoReconnect = true,
    this.maxReconnectAttempts = 10,
    this.reconnectDelayMs = 1000,
    this.maxReconnectDelayMs = 30000,
    this.heartbeatIntervalMs = 30000,
    this.connectionTimeoutMs = 10000,
    this.pingTimeoutMs = 5000,
  });

  WebSocketConfig copyWith({
    String? url,
    WebSocketAuthConfig? auth,
    bool? autoReconnect,
    int? maxReconnectAttempts,
    int? reconnectDelayMs,
    int? maxReconnectDelayMs,
    int? heartbeatIntervalMs,
    int? connectionTimeoutMs,
    int? pingTimeoutMs,
  }) {
    return WebSocketConfig(
      url: url ?? this.url,
      auth: auth ?? this.auth,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      reconnectDelayMs: reconnectDelayMs ?? this.reconnectDelayMs,
      maxReconnectDelayMs: maxReconnectDelayMs ?? this.maxReconnectDelayMs,
      heartbeatIntervalMs: heartbeatIntervalMs ?? this.heartbeatIntervalMs,
      connectionTimeoutMs: connectionTimeoutMs ?? this.connectionTimeoutMs,
      pingTimeoutMs: pingTimeoutMs ?? this.pingTimeoutMs,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEBSOCKET CONNECTOR
// ═══════════════════════════════════════════════════════════════════════════

/// Secure WebSocket connector with authentication and auto-reconnect
class WebSocketConnector {
  final WebSocketConfig config;

  WebSocket? _socket;
  WebSocketConnectionState _state = WebSocketConnectionState.disconnected;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _authenticated = false;
  DateTime? _lastPong;

  // Streams
  final _stateController = StreamController<WebSocketConnectionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Message queue for offline buffering
  final List<String> _messageQueue = [];
  static const int _maxQueueSize = 100;

  WebSocketConnector(this.config);

  // ─── Getters ────────────────────────────────────────────────────────────────

  WebSocketConnectionState get state => _state;
  bool get isConnected => _state == WebSocketConnectionState.connected;
  bool get isAuthenticated => _authenticated;
  Stream<WebSocketConnectionState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // ─── Connection ─────────────────────────────────────────────────────────────

  /// Connect to WebSocket server
  Future<bool> connect() async {
    if (_state == WebSocketConnectionState.connecting ||
        _state == WebSocketConnectionState.connected) {
      return true;
    }

    _setState(WebSocketConnectionState.connecting);
    _reconnectAttempts = 0;

    try {
      final url = config.auth.buildUrl(config.url);
      final headers = config.auth.buildHeaders();


      _socket = await WebSocket.connect(
        url,
        headers: headers,
      ).timeout(Duration(milliseconds: config.connectionTimeoutMs));

      _socket!.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Send authentication message if required
      final authMessage = config.auth.buildAuthMessage();
      if (authMessage != null) {
        _setState(WebSocketConnectionState.authenticating);
        _sendRaw(jsonEncode(authMessage));
      } else {
        // No auth required, mark as connected
        _authenticated = true;
        _setState(WebSocketConnectionState.connected);
        _startHeartbeat();
        _flushQueue();
      }

      return true;
    } catch (e) {
      _errorController.add('Connection failed: $e');
      _setState(WebSocketConnectionState.error);
      _scheduleReconnect();
      return false;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    if (_socket != null) {
      await _socket!.close(WebSocketStatus.normalClosure, 'Client disconnect');
      _socket = null;
    }

    _authenticated = false;
    _setState(WebSocketConnectionState.disconnected);
  }

  // ─── Messaging ──────────────────────────────────────────────────────────────

  /// Send a message to the server
  bool send(Map<String, dynamic> message) {
    final json = jsonEncode(message);

    if (_state != WebSocketConnectionState.connected) {
      // Queue message for later
      if (_messageQueue.length < _maxQueueSize) {
        _messageQueue.add(json);
      }
      return false;
    }

    return _sendRaw(json);
  }

  /// Send a raw string message
  bool _sendRaw(String message) {
    if (_socket == null) return false;

    try {
      _socket!.add(message);
      return true;
    } catch (e) {
      _errorController.add('Send failed: $e');
      return false;
    }
  }

  /// Flush queued messages after reconnect
  void _flushQueue() {
    while (_messageQueue.isNotEmpty && isConnected) {
      final message = _messageQueue.removeAt(0);
      _sendRaw(message);
    }
    if (_messageQueue.isNotEmpty) {
    }
  }

  // ─── Event Handlers ─────────────────────────────────────────────────────────

  void _onMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;

      // Handle auth response
      if (message['type'] == 'auth_response') {
        if (message['success'] == true) {
          _authenticated = true;
          _setState(WebSocketConnectionState.connected);
          _startHeartbeat();
          _flushQueue();
        } else {
          _authenticated = false;
          _errorController.add('Authentication failed: ${message['error']}');
          _setState(WebSocketConnectionState.error);
          disconnect();
        }
        return;
      }

      // Handle pong
      if (message['type'] == 'pong') {
        _lastPong = DateTime.now();
        return;
      }

      // Forward other messages
      _messageController.add(message);
    } catch (e) { /* ignored */ }
  }

  void _onError(Object error) {
    _errorController.add('Socket error: $error');
    _setState(WebSocketConnectionState.error);
  }

  void _onDone() {
    _socket = null;
    _authenticated = false;
    _stopHeartbeat();

    if (config.autoReconnect) {
      _scheduleReconnect();
    } else {
      _setState(WebSocketConnectionState.disconnected);
    }
  }

  // ─── Heartbeat ──────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _stopHeartbeat();

    if (config.heartbeatIntervalMs <= 0) return;

    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: config.heartbeatIntervalMs),
      (_) => _sendPing(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _sendPing() {
    if (_state != WebSocketConnectionState.connected) return;

    send({'type': 'ping', 'timestamp': DateTime.now().millisecondsSinceEpoch});

    // Start pong timeout
    _pingTimer = Timer(Duration(milliseconds: config.pingTimeoutMs), () {
      if (_lastPong == null ||
          DateTime.now().difference(_lastPong!).inMilliseconds > config.pingTimeoutMs) {
        _socket?.close(WebSocketStatus.goingAway, 'Ping timeout');
      }
    });
  }

  // ─── Reconnect ──────────────────────────────────────────────────────────────

  void _scheduleReconnect() {
    if (!config.autoReconnect) return;

    if (config.maxReconnectAttempts > 0 &&
        _reconnectAttempts >= config.maxReconnectAttempts) {
      _setState(WebSocketConnectionState.disconnected);
      return;
    }

    _setState(WebSocketConnectionState.reconnecting);

    // Exponential backoff
    final delay = (config.reconnectDelayMs * (1 << _reconnectAttempts))
        .clamp(config.reconnectDelayMs, config.maxReconnectDelayMs);


    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectAttempts++;
      connect();
    });
  }

  // ─── State ──────────────────────────────────────────────────────────────────

  void _setState(WebSocketConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  // ─── Cleanup ────────────────────────────────────────────────────────────────

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
    _errorController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE EVENT WEBSOCKET CLIENT
// ═══════════════════════════════════════════════════════════════════════════

/// Specialized WebSocket client for Stage Event streaming
class StageEventWebSocketClient {
  final WebSocketConnector _connector;

  final _stageEventController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _messageSubscription;

  StageEventWebSocketClient(WebSocketConfig config)
      : _connector = WebSocketConnector(config) {
    _messageSubscription = _connector.messageStream.listen(_onMessage);
  }

  // Getters
  WebSocketConnectionState get connectionState => _connector.state;
  bool get isConnected => _connector.isConnected;
  Stream<WebSocketConnectionState> get stateStream => _connector.stateStream;
  Stream<Map<String, dynamic>> get stageEventStream => _stageEventController.stream;
  Stream<String> get errorStream => _connector.errorStream;

  /// Connect to stage event server
  Future<bool> connect() => _connector.connect();

  /// Disconnect from server
  Future<void> disconnect() => _connector.disconnect();

  /// Subscribe to specific stage types
  void subscribe(List<String> stageTypes) {
    _connector.send({
      'type': 'subscribe',
      'stages': stageTypes,
    });
  }

  /// Unsubscribe from stage types
  void unsubscribe(List<String> stageTypes) {
    _connector.send({
      'type': 'unsubscribe',
      'stages': stageTypes,
    });
  }

  /// Request playback of recorded session
  void requestPlayback(String sessionId, {double speed = 1.0}) {
    _connector.send({
      'type': 'playback',
      'session_id': sessionId,
      'speed': speed,
    });
  }

  void _onMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    if (type == 'stage_event') {
      _stageEventController.add(message);
    }
  }

  void dispose() {
    _messageSubscription?.cancel();
    _stageEventController.close();
    _connector.dispose();
  }
}
