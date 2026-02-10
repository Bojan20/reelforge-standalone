// ============================================================================
// P3-04: Remote Collaboration Service — WebSocket Real-Time
// FluxForge Studio — Real-time collaboration via WebSocket
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Connection status for collaboration
enum CollaborationStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error;

  String get displayName {
    switch (this) {
      case CollaborationStatus.disconnected:
        return 'Disconnected';
      case CollaborationStatus.connecting:
        return 'Connecting...';
      case CollaborationStatus.connected:
        return 'Connected';
      case CollaborationStatus.reconnecting:
        return 'Reconnecting...';
      case CollaborationStatus.error:
        return 'Error';
    }
  }

  bool get isActive =>
      this == CollaborationStatus.connected ||
      this == CollaborationStatus.reconnecting;
}

/// Message types for collaboration protocol
enum CollabMessageType {
  // Connection
  join,
  leave,
  ping,
  pong,

  // Presence
  userJoined,
  userLeft,
  userUpdate,
  cursorMove,

  // Operations
  operation,
  operationAck,
  operationReject,

  // Sync
  syncRequest,
  syncResponse,
  stateSnapshot,

  // Chat
  chatMessage,
  chatTyping,

  // Transport
  transport,
  seek,
  loop,

  // Mixer
  mixerChange,
  trackChange,
  faderMove,
  soloMute,

  // SlotLab
  eventChange,
  stageChange,
  layerChange,

  // Session
  sessionLock,
  sessionUnlock,
  sessionKick,
}

/// User role in collaboration session
enum CollabRole {
  owner,
  editor,
  viewer;

  String get displayName {
    switch (this) {
      case CollabRole.owner:
        return 'Owner';
      case CollabRole.editor:
        return 'Editor';
      case CollabRole.viewer:
        return 'Viewer';
    }
  }

  bool get canEdit => this == CollabRole.owner || this == CollabRole.editor;
  bool get canManage => this == CollabRole.owner;
}

// ============================================================================
// MODELS
// ============================================================================

/// Represents a collaborator in the session
class Collaborator {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final CollabRole role;
  final String? color;
  final DateTime joinedAt;
  final CursorPosition? cursor;
  final String? currentSection;
  final bool isTyping;

  const Collaborator({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    required this.role,
    this.color,
    required this.joinedAt,
    this.cursor,
    this.currentSection,
    this.isTyping = false,
  });

  factory Collaborator.fromJson(Map<String, dynamic> json) {
    return Collaborator(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      role: CollabRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => CollabRole.viewer,
      ),
      color: json['color'] as String?,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      cursor: json['cursor'] != null
          ? CursorPosition.fromJson(json['cursor'] as Map<String, dynamic>)
          : null,
      currentSection: json['currentSection'] as String?,
      isTyping: json['isTyping'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl,
        'role': role.name,
        'color': color,
        'joinedAt': joinedAt.toIso8601String(),
        'cursor': cursor?.toJson(),
        'currentSection': currentSection,
        'isTyping': isTyping,
      };

  Collaborator copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    CollabRole? role,
    String? color,
    DateTime? joinedAt,
    CursorPosition? cursor,
    String? currentSection,
    bool? isTyping,
  }) {
    return Collaborator(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      color: color ?? this.color,
      joinedAt: joinedAt ?? this.joinedAt,
      cursor: cursor ?? this.cursor,
      currentSection: currentSection ?? this.currentSection,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}

/// Cursor position for live cursors
class CursorPosition {
  final double x;
  final double y;
  final String? targetId;
  final String? targetType;
  final DateTime timestamp;

  const CursorPosition({
    required this.x,
    required this.y,
    this.targetId,
    this.targetType,
    required this.timestamp,
  });

  factory CursorPosition.fromJson(Map<String, dynamic> json) {
    return CursorPosition(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      targetId: json['targetId'] as String?,
      targetType: json['targetType'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'targetId': targetId,
        'targetType': targetType,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Chat message in collaboration session
class CollabChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final bool isSystem;

  const CollabChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.isSystem = false,
  });

  factory CollabChatMessage.fromJson(Map<String, dynamic> json) {
    return CollabChatMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'isSystem': isSystem,
      };
}

/// Operation for operational transformation
class CollabOperation {
  final String id;
  final String userId;
  final CollabMessageType type;
  final Map<String, dynamic> data;
  final int version;
  final DateTime timestamp;
  final bool acknowledged;

  const CollabOperation({
    required this.id,
    required this.userId,
    required this.type,
    required this.data,
    required this.version,
    required this.timestamp,
    this.acknowledged = false,
  });

  factory CollabOperation.fromJson(Map<String, dynamic> json) {
    return CollabOperation(
      id: json['id'] as String,
      userId: json['userId'] as String,
      type: CollabMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => CollabMessageType.operation,
      ),
      data: json['data'] as Map<String, dynamic>,
      version: json['version'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      acknowledged: json['acknowledged'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type.name,
        'data': data,
        'version': version,
        'timestamp': timestamp.toIso8601String(),
        'acknowledged': acknowledged,
      };

  CollabOperation copyWith({bool? acknowledged}) {
    return CollabOperation(
      id: id,
      userId: userId,
      type: type,
      data: data,
      version: version,
      timestamp: timestamp,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}

/// Collaboration session info
class CollabSession {
  final String id;
  final String projectId;
  final String projectName;
  final String ownerId;
  final DateTime createdAt;
  final List<Collaborator> participants;
  final int operationVersion;
  final bool isLocked;
  final String? lockHolderId;

  const CollabSession({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.ownerId,
    required this.createdAt,
    this.participants = const [],
    this.operationVersion = 0,
    this.isLocked = false,
    this.lockHolderId,
  });

  factory CollabSession.fromJson(Map<String, dynamic> json) {
    return CollabSession(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      ownerId: json['ownerId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => Collaborator.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      operationVersion: json['operationVersion'] as int? ?? 0,
      isLocked: json['isLocked'] as bool? ?? false,
      lockHolderId: json['lockHolderId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'ownerId': ownerId,
        'createdAt': createdAt.toIso8601String(),
        'participants': participants.map((p) => p.toJson()).toList(),
        'operationVersion': operationVersion,
        'isLocked': isLocked,
        'lockHolderId': lockHolderId,
      };

  CollabSession copyWith({
    List<Collaborator>? participants,
    int? operationVersion,
    bool? isLocked,
    String? lockHolderId,
  }) {
    return CollabSession(
      id: id,
      projectId: projectId,
      projectName: projectName,
      ownerId: ownerId,
      createdAt: createdAt,
      participants: participants ?? this.participants,
      operationVersion: operationVersion ?? this.operationVersion,
      isLocked: isLocked ?? this.isLocked,
      lockHolderId: lockHolderId ?? this.lockHolderId,
    );
  }
}

// ============================================================================
// COLLABORATION SERVICE
// ============================================================================

/// Real-time collaboration service via WebSocket
class CollaborationService extends ChangeNotifier {
  // Singleton
  static final CollaborationService _instance = CollaborationService._();
  static CollaborationService get instance => _instance;
  CollaborationService._();

  // State
  CollaborationStatus _status = CollaborationStatus.disconnected;
  CollabSession? _currentSession;
  Collaborator? _localUser;
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastError;

  // Operation queue for OT
  final List<CollabOperation> _pendingOperations = [];
  final List<CollabOperation> _operationHistory = [];
  int _localVersion = 0;

  // Chat messages
  final List<CollabChatMessage> _chatMessages = [];

  // Configuration
  static const String _prefsKey = 'collaboration_config';
  String _serverUrl = 'wss://collab.fluxforge.io/ws';
  int _pingInterval = 30; // seconds
  int _maxReconnectAttempts = 5;
  int _reconnectDelay = 2; // seconds

  // Streams
  final StreamController<CollabOperation> _operationController =
      StreamController<CollabOperation>.broadcast();
  final StreamController<Collaborator> _presenceController =
      StreamController<Collaborator>.broadcast();
  final StreamController<CollabChatMessage> _chatController =
      StreamController<CollabChatMessage>.broadcast();

  // Getters
  CollaborationStatus get status => _status;
  CollabSession? get currentSession => _currentSession;
  Collaborator? get localUser => _localUser;
  List<Collaborator> get participants => _currentSession?.participants ?? [];
  List<Collaborator> get connectedPeers => participants.where((p) => p.id != _localUser?.id).toList();
  List<CollabChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  String? get lastError => _lastError;
  bool get isConnected => _status == CollaborationStatus.connected;
  bool get isInSession => _currentSession != null && isConnected;

  Stream<CollabOperation> get operationStream => _operationController.stream;
  Stream<Collaborator> get presenceStream => _presenceController.stream;
  Stream<CollabChatMessage> get chatStream => _chatController.stream;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize collaboration service
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_prefsKey);

      if (configJson != null) {
        final config = jsonDecode(configJson) as Map<String, dynamic>;
        _serverUrl = config['serverUrl'] as String? ?? _serverUrl;
        _pingInterval = config['pingInterval'] as int? ?? _pingInterval;
        _maxReconnectAttempts =
            config['maxReconnectAttempts'] as int? ?? _maxReconnectAttempts;
      }

    } catch (e) { /* ignored */ }
  }

  /// Save configuration
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'serverUrl': _serverUrl,
          'pingInterval': _pingInterval,
          'maxReconnectAttempts': _maxReconnectAttempts,
        }),
      );
    } catch (e) { /* ignored */ }
  }

  // ============================================================================
  // CONNECTION MANAGEMENT
  // ============================================================================

  /// Create a new collaboration session
  Future<CollabSession?> createSession({
    required String projectId,
    required String projectName,
    required String userName,
    String? userEmail,
  }) async {
    try {
      _setStatus(CollaborationStatus.connecting);

      // Generate session and user IDs
      final sessionId = _generateId('session');
      final userId = _generateId('user');

      // Create local user
      _localUser = Collaborator(
        id: userId,
        name: userName,
        email: userEmail,
        role: CollabRole.owner,
        color: _generateUserColor(userId),
        joinedAt: DateTime.now(),
      );

      // Create session
      _currentSession = CollabSession(
        id: sessionId,
        projectId: projectId,
        projectName: projectName,
        ownerId: userId,
        createdAt: DateTime.now(),
        participants: [_localUser!],
      );

      // Connect to WebSocket
      await _connect(sessionId);

      // Send join message
      _sendMessage(CollabMessageType.join, {
        'sessionId': sessionId,
        'user': _localUser!.toJson(),
        'isCreator': true,
      });

      _setStatus(CollaborationStatus.connected);
      notifyListeners();

      return _currentSession;
    } catch (e) {
      _setStatus(CollaborationStatus.error, e.toString());
      return null;
    }
  }

  /// Join an existing collaboration session
  Future<bool> joinSession({
    required String sessionId,
    required String userName,
    String? userEmail,
    String? inviteCode,
  }) async {
    try {
      _setStatus(CollaborationStatus.connecting);

      // Generate user ID
      final userId = _generateId('user');

      // Create local user (role will be updated by server)
      _localUser = Collaborator(
        id: userId,
        name: userName,
        email: userEmail,
        role: CollabRole.viewer,
        color: _generateUserColor(userId),
        joinedAt: DateTime.now(),
      );

      // Connect to WebSocket
      await _connect(sessionId);

      // Send join message
      _sendMessage(CollabMessageType.join, {
        'sessionId': sessionId,
        'user': _localUser!.toJson(),
        'inviteCode': inviteCode,
        'isCreator': false,
      });

      return true;
    } catch (e) {
      _setStatus(CollaborationStatus.error, e.toString());
      return false;
    }
  }

  /// Leave current session
  Future<void> leaveSession() async {
    if (_currentSession == null) return;

    try {
      _sendMessage(CollabMessageType.leave, {
        'sessionId': _currentSession!.id,
        'userId': _localUser?.id,
      });

      await _disconnect();

      _currentSession = null;
      _localUser = null;
      _chatMessages.clear();
      _pendingOperations.clear();
      _operationHistory.clear();
      _localVersion = 0;

      _setStatus(CollaborationStatus.disconnected);
      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  /// Connect to WebSocket server
  Future<void> _connect(String sessionId) async {
    try {
      final uri = Uri.parse('$_serverUrl/$sessionId');
      _channel = WebSocketChannel.connect(uri);

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      // Start ping timer
      _startPingTimer();

      _reconnectAttempts = 0;
    } catch (e) {
      throw Exception('Failed to connect: $e');
    }
  }

  /// Disconnect from WebSocket
  Future<void> _disconnect() async {
    _stopPingTimer();
    _stopReconnectTimer();

    await _channel?.sink.close();
    _channel = null;
  }

  /// Reconnect to server
  Future<void> _reconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setStatus(CollaborationStatus.error, 'Max reconnect attempts reached');
      return;
    }

    _setStatus(CollaborationStatus.reconnecting);
    _reconnectAttempts++;

    _reconnectTimer = Timer(
      Duration(seconds: _reconnectDelay * _reconnectAttempts),
      () async {
        if (_currentSession != null && _localUser != null) {
          try {
            await _connect(_currentSession!.id);
            _sendMessage(CollabMessageType.join, {
              'sessionId': _currentSession!.id,
              'user': _localUser!.toJson(),
              'isReconnect': true,
            });
            _setStatus(CollaborationStatus.connected);
          } catch (e) {
            _reconnect();
          }
        }
      },
    );
  }

  // ============================================================================
  // MESSAGE HANDLING
  // ============================================================================

  /// Send message to server
  void _sendMessage(CollabMessageType type, Map<String, dynamic> data) {
    if (_channel == null) return;

    final message = jsonEncode({
      'type': type.name,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _channel!.sink.add(message);
  }

  /// Handle incoming message
  void _handleMessage(dynamic rawMessage) {
    try {
      final message = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final typeStr = message['type'] as String;
      final data = message['data'] as Map<String, dynamic>;

      final type = CollabMessageType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => CollabMessageType.operation,
      );

      switch (type) {
        case CollabMessageType.userJoined:
          _handleUserJoined(data);
          break;
        case CollabMessageType.userLeft:
          _handleUserLeft(data);
          break;
        case CollabMessageType.userUpdate:
          _handleUserUpdate(data);
          break;
        case CollabMessageType.cursorMove:
          _handleCursorMove(data);
          break;
        case CollabMessageType.operation:
          _handleOperation(data);
          break;
        case CollabMessageType.operationAck:
          _handleOperationAck(data);
          break;
        case CollabMessageType.operationReject:
          _handleOperationReject(data);
          break;
        case CollabMessageType.syncResponse:
          _handleSyncResponse(data);
          break;
        case CollabMessageType.stateSnapshot:
          _handleStateSnapshot(data);
          break;
        case CollabMessageType.chatMessage:
          _handleChatMessage(data);
          break;
        case CollabMessageType.chatTyping:
          _handleChatTyping(data);
          break;
        case CollabMessageType.sessionLock:
          _handleSessionLock(data);
          break;
        case CollabMessageType.sessionUnlock:
          _handleSessionUnlock(data);
          break;
        case CollabMessageType.sessionKick:
          _handleSessionKick(data);
          break;
        case CollabMessageType.pong:
          // Pong received, connection alive
          break;
        default:
          // Forward operation-like messages
          _handleGenericOperation(type, data);
      }
    } catch (e) { /* ignored */ }
  }

  void _handleUserJoined(Map<String, dynamic> data) {
    final user = Collaborator.fromJson(data['user'] as Map<String, dynamic>);

    if (_currentSession != null) {
      final participants = List<Collaborator>.from(_currentSession!.participants);
      if (!participants.any((p) => p.id == user.id)) {
        participants.add(user);
        _currentSession = _currentSession!.copyWith(participants: participants);

        // Add system message
        _addSystemMessage('${user.name} joined the session');

        _presenceController.add(user);
        notifyListeners();
      }
    }
  }

  void _handleUserLeft(Map<String, dynamic> data) {
    final userId = data['userId'] as String;

    if (_currentSession != null) {
      final participants = _currentSession!.participants
          .where((p) => p.id != userId)
          .toList();

      final leftUser = _currentSession!.participants
          .where((p) => p.id == userId)
          .firstOrNull;

      _currentSession = _currentSession!.copyWith(participants: participants);

      if (leftUser != null) {
        _addSystemMessage('${leftUser.name} left the session');
      }

      notifyListeners();
    }
  }

  void _handleUserUpdate(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final updates = data['updates'] as Map<String, dynamic>;

    if (_currentSession != null) {
      final participants = _currentSession!.participants.map((p) {
        if (p.id == userId) {
          return p.copyWith(
            currentSection: updates['currentSection'] as String?,
            isTyping: updates['isTyping'] as bool?,
          );
        }
        return p;
      }).toList();

      _currentSession = _currentSession!.copyWith(participants: participants);
      notifyListeners();
    }
  }

  void _handleCursorMove(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final cursor = CursorPosition.fromJson(data['cursor'] as Map<String, dynamic>);

    if (_currentSession != null) {
      final participants = _currentSession!.participants.map((p) {
        if (p.id == userId) {
          return p.copyWith(cursor: cursor);
        }
        return p;
      }).toList();

      _currentSession = _currentSession!.copyWith(participants: participants);
      notifyListeners();
    }
  }

  void _handleOperation(Map<String, dynamic> data) {
    final operation = CollabOperation.fromJson(data);

    // Skip if from local user
    if (operation.userId == _localUser?.id) return;

    // Update local version
    _localVersion = operation.version;

    // Add to history
    _operationHistory.add(operation);

    // Emit operation
    _operationController.add(operation);

    notifyListeners();
  }

  void _handleOperationAck(Map<String, dynamic> data) {
    final operationId = data['operationId'] as String;
    final serverVersion = data['version'] as int;

    // Remove from pending
    _pendingOperations.removeWhere((op) => op.id == operationId);

    // Update local version
    _localVersion = serverVersion;
  }

  void _handleOperationReject(Map<String, dynamic> data) {
    final operationId = data['operationId'] as String;
    final reason = data['reason'] as String?;

    // Remove from pending
    final rejected = _pendingOperations
        .where((op) => op.id == operationId)
        .firstOrNull;

    _pendingOperations.removeWhere((op) => op.id == operationId);

    if (rejected != null) {
      // TODO: Handle rejection (rollback, conflict resolution)
    }
  }

  void _handleSyncResponse(Map<String, dynamic> data) {
    final session = CollabSession.fromJson(data['session'] as Map<String, dynamic>);
    _currentSession = session;
    _localVersion = session.operationVersion;

    _setStatus(CollaborationStatus.connected);
    notifyListeners();
  }

  void _handleStateSnapshot(Map<String, dynamic> data) {
    // Full state snapshot from server
    if (data['session'] != null) {
      _currentSession = CollabSession.fromJson(data['session'] as Map<String, dynamic>);
    }
    if (data['version'] != null) {
      _localVersion = data['version'] as int;
    }
    notifyListeners();
  }

  void _handleChatMessage(Map<String, dynamic> data) {
    final message = CollabChatMessage.fromJson(data);
    _chatMessages.add(message);
    _chatController.add(message);
    notifyListeners();
  }

  void _handleChatTyping(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final isTyping = data['isTyping'] as bool;

    if (_currentSession != null) {
      final participants = _currentSession!.participants.map((p) {
        if (p.id == userId) {
          return p.copyWith(isTyping: isTyping);
        }
        return p;
      }).toList();

      _currentSession = _currentSession!.copyWith(participants: participants);
      notifyListeners();
    }
  }

  void _handleSessionLock(Map<String, dynamic> data) {
    final holderId = data['holderId'] as String;

    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        isLocked: true,
        lockHolderId: holderId,
      );
      notifyListeners();
    }
  }

  void _handleSessionUnlock(Map<String, dynamic> data) {
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        isLocked: false,
        lockHolderId: null,
      );
      notifyListeners();
    }
  }

  void _handleSessionKick(Map<String, dynamic> data) {
    final targetUserId = data['userId'] as String;

    if (_localUser?.id == targetUserId) {
      leaveSession();
      _lastError = 'You have been removed from the session';
      notifyListeners();
    }
  }

  void _handleGenericOperation(CollabMessageType type, Map<String, dynamic> data) {
    // Create operation from generic message
    final operation = CollabOperation(
      id: data['id'] as String? ?? _generateId('op'),
      userId: data['userId'] as String? ?? 'unknown',
      type: type,
      data: data,
      version: _localVersion,
      timestamp: DateTime.now(),
    );

    _operationController.add(operation);
  }

  void _handleError(dynamic error) {
    _setStatus(CollaborationStatus.error, error.toString());
  }

  void _handleDisconnect() {
    if (_status != CollaborationStatus.disconnected) {
      _reconnect();
    }
  }

  // ============================================================================
  // OPERATIONS
  // ============================================================================

  /// Send an operation to the server
  void sendOperation(CollabMessageType type, Map<String, dynamic> data) {
    if (!isConnected || _localUser == null) return;

    final operation = CollabOperation(
      id: _generateId('op'),
      userId: _localUser!.id,
      type: type,
      data: data,
      version: _localVersion + 1,
      timestamp: DateTime.now(),
    );

    _pendingOperations.add(operation);
    _sendMessage(type, {
      'operationId': operation.id,
      'userId': operation.userId,
      'version': operation.version,
      ...data,
    });
  }

  /// Send cursor position
  void sendCursorPosition(double x, double y, {String? targetId, String? targetType}) {
    if (!isConnected || _localUser == null) return;

    _sendMessage(CollabMessageType.cursorMove, {
      'userId': _localUser!.id,
      'cursor': CursorPosition(
        x: x,
        y: y,
        targetId: targetId,
        targetType: targetType,
        timestamp: DateTime.now(),
      ).toJson(),
    });
  }

  /// Send section change
  void sendSectionChange(String section) {
    if (!isConnected || _localUser == null) return;

    _sendMessage(CollabMessageType.userUpdate, {
      'userId': _localUser!.id,
      'updates': {'currentSection': section},
    });
  }

  /// Send chat message
  void sendChatMessage(String content) {
    if (!isConnected || _localUser == null || content.trim().isEmpty) return;

    final message = CollabChatMessage(
      id: _generateId('msg'),
      senderId: _localUser!.id,
      senderName: _localUser!.name,
      content: content,
      timestamp: DateTime.now(),
    );

    _chatMessages.add(message);
    _sendMessage(CollabMessageType.chatMessage, message.toJson());
    notifyListeners();
  }

  /// Send typing indicator
  void sendTypingIndicator(bool isTyping) {
    if (!isConnected || _localUser == null) return;

    _sendMessage(CollabMessageType.chatTyping, {
      'userId': _localUser!.id,
      'isTyping': isTyping,
    });
  }

  /// Request session lock
  void requestSessionLock() {
    if (!isConnected || _localUser == null) return;
    if (_localUser!.role != CollabRole.owner) return;

    _sendMessage(CollabMessageType.sessionLock, {
      'holderId': _localUser!.id,
    });
  }

  /// Release session lock
  void releaseSessionLock() {
    if (!isConnected || _localUser == null) return;
    if (_currentSession?.lockHolderId != _localUser!.id) return;

    _sendMessage(CollabMessageType.sessionUnlock, {});
  }

  /// Kick a user from session
  void kickUser(String userId) {
    if (!isConnected || _localUser == null) return;
    if (_localUser!.role != CollabRole.owner) return;

    _sendMessage(CollabMessageType.sessionKick, {
      'userId': userId,
    });
  }

  /// Change user role
  void changeUserRole(String userId, CollabRole newRole) {
    if (!isConnected || _localUser == null) return;
    if (_localUser!.role != CollabRole.owner) return;

    _sendMessage(CollabMessageType.userUpdate, {
      'userId': userId,
      'updates': {'role': newRole.name},
    });
  }

  // ============================================================================
  // TRANSPORT SYNC
  // ============================================================================

  /// Send transport state change
  void sendTransportChange({
    bool? isPlaying,
    double? position,
    bool? isLooping,
    double? loopStart,
    double? loopEnd,
  }) {
    sendOperation(CollabMessageType.transport, {
      if (isPlaying != null) 'isPlaying': isPlaying,
      if (position != null) 'position': position,
      if (isLooping != null) 'isLooping': isLooping,
      if (loopStart != null) 'loopStart': loopStart,
      if (loopEnd != null) 'loopEnd': loopEnd,
    });
  }

  /// Send seek position
  void sendSeek(double position) {
    sendOperation(CollabMessageType.seek, {
      'position': position,
    });
  }

  // ============================================================================
  // MIXER SYNC
  // ============================================================================

  /// Send fader move
  void sendFaderMove(String channelId, double value) {
    sendOperation(CollabMessageType.faderMove, {
      'channelId': channelId,
      'value': value,
    });
  }

  /// Send solo/mute change
  void sendSoloMuteChange(String channelId, {bool? solo, bool? mute}) {
    sendOperation(CollabMessageType.soloMute, {
      'channelId': channelId,
      if (solo != null) 'solo': solo,
      if (mute != null) 'mute': mute,
    });
  }

  /// Send track change
  void sendTrackChange(String trackId, Map<String, dynamic> changes) {
    sendOperation(CollabMessageType.trackChange, {
      'trackId': trackId,
      'changes': changes,
    });
  }

  // ============================================================================
  // SLOTLAB SYNC
  // ============================================================================

  /// Send event change
  void sendEventChange(String eventId, Map<String, dynamic> changes) {
    sendOperation(CollabMessageType.eventChange, {
      'eventId': eventId,
      'changes': changes,
    });
  }

  /// Send stage change
  void sendStageChange(String stage, Map<String, dynamic> data) {
    sendOperation(CollabMessageType.stageChange, {
      'stage': stage,
      'data': data,
    });
  }

  /// Send layer change
  void sendLayerChange(String eventId, String layerId, Map<String, dynamic> changes) {
    sendOperation(CollabMessageType.layerChange, {
      'eventId': eventId,
      'layerId': layerId,
      'changes': changes,
    });
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  void _setStatus(CollaborationStatus newStatus, [String? error]) {
    _status = newStatus;
    _lastError = error;
    notifyListeners();
  }

  void _addSystemMessage(String content) {
    final message = CollabChatMessage(
      id: _generateId('sys'),
      senderId: 'system',
      senderName: 'System',
      content: content,
      timestamp: DateTime.now(),
      isSystem: true,
    );

    _chatMessages.add(message);
    _chatController.add(message);
  }

  void _startPingTimer() {
    _pingTimer = Timer.periodic(
      Duration(seconds: _pingInterval),
      (_) {
        if (_channel != null) {
          _sendMessage(CollabMessageType.ping, {});
        }
      },
    );
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  String _generateId(String prefix) {
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode.abs()}';
  }

  String _generateUserColor(String id) {
    final colors = [
      '#FF6B6B',
      '#4ECDC4',
      '#45B7D1',
      '#96CEB4',
      '#FFEAA7',
      '#DDA0DD',
      '#98D8C8',
      '#F7DC6F',
    ];
    final index = id.hashCode.abs() % colors.length;
    return colors[index];
  }

  // ============================================================================
  // CONFIGURATION
  // ============================================================================

  /// Update server URL
  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    await _saveConfig();
  }

  /// Update ping interval
  Future<void> setPingInterval(int seconds) async {
    _pingInterval = seconds;
    await _saveConfig();

    // Restart ping timer if connected
    if (isConnected) {
      _stopPingTimer();
      _startPingTimer();
    }
  }

  /// Get session invite link
  String? getInviteLink() {
    if (_currentSession == null) return null;
    return 'fluxforge://collab/${_currentSession!.id}';
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    _disconnect();
    _operationController.close();
    _presenceController.close();
    _chatController.close();
    super.dispose();
  }
}
