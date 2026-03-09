/// Network Audio Service — ReaStream-style LAN Audio/MIDI Streaming
///
/// #29: Host-to-host streaming audio/MIDI on LAN via UDP broadcast.
///
/// Features:
/// - Send/receive audio streams over UDP
/// - Multi-channel support (up to 64 channels)
/// - Configurable sample rate and buffer size
/// - Auto-discovery of peers on LAN via broadcast
/// - Named stream identifiers for routing
/// - Per-stream level metering
/// - MIDI streaming alongside audio
/// - Latency monitoring and statistics
/// - JSON serialization for persistence
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// STREAM DIRECTION & PROTOCOL
// ═══════════════════════════════════════════════════════════════════════════════

/// Direction of a network audio stream
enum StreamDirection {
  send,
  receive,
}

/// What kind of data is being streamed
enum StreamDataType {
  audio,
  midi,
  audioAndMidi,
}

/// Stream status
enum StreamStatus {
  disconnected,
  connecting,
  connected,
  error,
}

// ═══════════════════════════════════════════════════════════════════════════════
// NETWORK PEER
// ═══════════════════════════════════════════════════════════════════════════════

/// A discovered peer on the network
class NetworkPeer {
  final String id;
  final String hostname;
  final String ipAddress;
  final int port;
  final DateTime lastSeen;
  final List<String> availableStreams;

  const NetworkPeer({
    required this.id,
    required this.hostname,
    required this.ipAddress,
    required this.port,
    required this.lastSeen,
    this.availableStreams = const [],
  });

  bool get isStale =>
      DateTime.now().difference(lastSeen).inSeconds > 10;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hostname': hostname,
    'ipAddress': ipAddress,
    'port': port,
    'lastSeen': lastSeen.toIso8601String(),
    'availableStreams': availableStreams,
  };

  factory NetworkPeer.fromJson(Map<String, dynamic> json) => NetworkPeer(
    id: json['id'] as String? ?? '',
    hostname: json['hostname'] as String? ?? '',
    ipAddress: json['ipAddress'] as String? ?? '',
    port: (json['port'] as int? ?? 58710).clamp(1024, 65535),
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
    availableStreams: (json['availableStreams'] as List<dynamic>?)
        ?.map((e) => e as String).toList() ?? [],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// NETWORK STREAM
// ═══════════════════════════════════════════════════════════════════════════════

/// A configured network audio/MIDI stream
class NetworkStream {
  final String id;
  String name;
  StreamDirection direction;
  StreamDataType dataType;
  StreamStatus status;

  /// Network configuration
  String targetIp;
  int port;
  bool broadcast;

  /// Audio configuration
  int channelCount;
  int sampleRate;
  int bufferSize;

  /// Monitoring
  double peakLevel;    // 0.0 to 1.0
  double rmsLevel;     // 0.0 to 1.0
  double latencyMs;    // measured round-trip
  int packetsLost;
  int packetsSent;
  int packetsReceived;

  /// Enabled state
  bool enabled;

  NetworkStream({
    required this.id,
    required this.name,
    this.direction = StreamDirection.send,
    this.dataType = StreamDataType.audio,
    this.status = StreamStatus.disconnected,
    this.targetIp = '255.255.255.255',
    this.port = 58710,
    this.broadcast = true,
    this.channelCount = 2,
    this.sampleRate = 48000,
    this.bufferSize = 512,
    this.peakLevel = 0,
    this.rmsLevel = 0,
    this.latencyMs = 0,
    this.packetsLost = 0,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.enabled = false,
  });

  bool get isSend => direction == StreamDirection.send;
  bool get isReceive => direction == StreamDirection.receive;
  bool get isConnected => status == StreamStatus.connected;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'direction': direction.name,
    'dataType': dataType.name,
    'targetIp': targetIp,
    'port': port,
    'broadcast': broadcast,
    'channelCount': channelCount,
    'sampleRate': sampleRate,
    'bufferSize': bufferSize,
    'enabled': enabled,
  };

  factory NetworkStream.fromJson(Map<String, dynamic> json) => NetworkStream(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    direction: StreamDirection.values.firstWhere(
      (d) => d.name == json['direction'],
      orElse: () => StreamDirection.send,
    ),
    dataType: StreamDataType.values.firstWhere(
      (d) => d.name == json['dataType'],
      orElse: () => StreamDataType.audio,
    ),
    targetIp: json['targetIp'] as String? ?? '255.255.255.255',
    port: (json['port'] as int? ?? 58710).clamp(1024, 65535),
    broadcast: json['broadcast'] as bool? ?? true,
    channelCount: (json['channelCount'] as int? ?? 2).clamp(1, 64),
    sampleRate: json['sampleRate'] as int? ?? 48000,
    bufferSize: json['bufferSize'] as int? ?? 512,
    enabled: json['enabled'] as bool? ?? false,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// NETWORK AUDIO SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing network audio/MIDI streaming
class NetworkAudioService extends ChangeNotifier {
  NetworkAudioService._();
  static final NetworkAudioService instance = NetworkAudioService._();

  /// Configured streams
  final Map<String, NetworkStream> _streams = {};

  /// Discovered peers on the network
  final Map<String, NetworkPeer> _peers = {};

  /// Default port for ReaStream-compatible protocol
  static const int defaultPort = 58710;

  /// Whether discovery broadcast is active
  bool _discoveryActive = false;

  /// Local hostname identifier
  String _localHostname = 'FluxForge';

  /// Callback for starting/stopping actual network I/O
  void Function(String streamId, bool start)? onStreamControl;

  // Getters
  List<NetworkStream> get streams => _streams.values.toList();
  List<NetworkStream> get sendStreams =>
      _streams.values.where((s) => s.isSend).toList();
  List<NetworkStream> get receiveStreams =>
      _streams.values.where((s) => s.isReceive).toList();
  List<NetworkPeer> get peers => _peers.values.toList();
  List<NetworkPeer> get activePeers =>
      _peers.values.where((p) => !p.isStale).toList();
  int get streamCount => _streams.length;
  int get connectedCount =>
      _streams.values.where((s) => s.isConnected).length;
  bool get discoveryActive => _discoveryActive;
  String get localHostname => _localHostname;

  // ═══════════════════════════════════════════════════════════════════════════
  // STREAM MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new stream
  void addStream(NetworkStream stream) {
    _streams[stream.id] = stream;
    notifyListeners();
  }

  /// Remove a stream
  void removeStream(String id) {
    final stream = _streams[id];
    if (stream != null && stream.isConnected) {
      disconnectStream(id);
    }
    _streams.remove(id);
    notifyListeners();
  }

  /// Get a stream by ID
  NetworkStream? getStream(String id) => _streams[id];

  /// Rename a stream
  void renameStream(String id, String newName) {
    final stream = _streams[id];
    if (stream == null) return;
    stream.name = newName;
    notifyListeners();
  }

  /// Update stream configuration
  void updateStream(String id, {
    StreamDirection? direction,
    StreamDataType? dataType,
    String? targetIp,
    int? port,
    bool? broadcast,
    int? channelCount,
    int? sampleRate,
    int? bufferSize,
  }) {
    final stream = _streams[id];
    if (stream == null) return;

    // Disconnect if changing critical params while connected
    if (stream.isConnected && (direction != null || channelCount != null ||
        sampleRate != null || bufferSize != null)) {
      disconnectStream(id);
    }

    if (direction != null) stream.direction = direction;
    if (dataType != null) stream.dataType = dataType;
    if (targetIp != null) stream.targetIp = targetIp;
    if (port != null) stream.port = port.clamp(1024, 65535);
    if (broadcast != null) stream.broadcast = broadcast;
    if (channelCount != null) stream.channelCount = channelCount.clamp(1, 64);
    if (sampleRate != null) stream.sampleRate = sampleRate;
    if (bufferSize != null) stream.bufferSize = bufferSize;

    notifyListeners();
  }

  /// Create a new send stream with defaults
  NetworkStream createSendStream(String name) {
    final id = 'stream_send_${DateTime.now().millisecondsSinceEpoch}';
    final stream = NetworkStream(
      id: id,
      name: name,
      direction: StreamDirection.send,
    );
    addStream(stream);
    return stream;
  }

  /// Create a new receive stream with defaults
  NetworkStream createReceiveStream(String name) {
    final id = 'stream_recv_${DateTime.now().millisecondsSinceEpoch}';
    final stream = NetworkStream(
      id: id,
      name: name,
      direction: StreamDirection.receive,
    );
    addStream(stream);
    return stream;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNECTION CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Connect/start a stream
  void connectStream(String id) {
    final stream = _streams[id];
    if (stream == null) return;

    stream.status = StreamStatus.connecting;
    stream.enabled = true;
    stream.packetsLost = 0;
    stream.packetsSent = 0;
    stream.packetsReceived = 0;
    onStreamControl?.call(id, true);

    // Simulate connection success (real impl would be async)
    stream.status = StreamStatus.connected;
    notifyListeners();
  }

  /// Disconnect/stop a stream
  void disconnectStream(String id) {
    final stream = _streams[id];
    if (stream == null) return;

    stream.status = StreamStatus.disconnected;
    stream.enabled = false;
    stream.peakLevel = 0;
    stream.rmsLevel = 0;
    onStreamControl?.call(id, false);
    notifyListeners();
  }

  /// Toggle stream connection
  void toggleStream(String id) {
    final stream = _streams[id];
    if (stream == null) return;

    if (stream.isConnected) {
      disconnectStream(id);
    } else {
      connectStream(id);
    }
  }

  /// Disconnect all streams
  void disconnectAll() {
    for (final stream in _streams.values) {
      if (stream.isConnected) {
        stream.status = StreamStatus.disconnected;
        stream.enabled = false;
        stream.peakLevel = 0;
        stream.rmsLevel = 0;
        onStreamControl?.call(stream.id, false);
      }
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METERING UPDATE (called from audio thread periodically)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update metering data for a stream
  void updateMetering(String id, {
    double? peakLevel,
    double? rmsLevel,
    double? latencyMs,
    int? packetsLost,
    int? packetsSent,
    int? packetsReceived,
  }) {
    final stream = _streams[id];
    if (stream == null) return;

    if (peakLevel != null) stream.peakLevel = peakLevel;
    if (rmsLevel != null) stream.rmsLevel = rmsLevel;
    if (latencyMs != null) stream.latencyMs = latencyMs;
    if (packetsLost != null) stream.packetsLost = packetsLost;
    if (packetsSent != null) stream.packetsSent = packetsSent;
    if (packetsReceived != null) stream.packetsReceived = packetsReceived;

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PEER DISCOVERY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle network discovery
  void toggleDiscovery() {
    _discoveryActive = !_discoveryActive;
    notifyListeners();
  }

  /// Register a discovered peer
  void registerPeer(NetworkPeer peer) {
    _peers[peer.id] = peer;
    notifyListeners();
  }

  /// Remove stale peers
  void pruneStale() {
    _peers.removeWhere((_, p) => p.isStale);
    notifyListeners();
  }

  /// Set local hostname
  void setLocalHostname(String hostname) {
    _localHostname = hostname;
    notifyListeners();
  }

  /// Connect to a specific peer (create receive stream)
  void connectToPeer(NetworkPeer peer, {String? streamName}) {
    final name = streamName ?? '${peer.hostname}:${peer.port}';
    final stream = createReceiveStream(name);
    stream.targetIp = peer.ipAddress;
    stream.port = peer.port.clamp(1024, 65535);
    stream.broadcast = false;
    connectStream(stream.id);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'streams': _streams.values.map((s) => s.toJson()).toList(),
    'localHostname': _localHostname,
  };

  void fromJson(Map<String, dynamic> json) {
    _streams.clear();
    _peers.clear();
    _discoveryActive = false;
    _localHostname = json['localHostname'] as String? ?? 'FluxForge';
    final list = json['streams'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final stream = NetworkStream.fromJson(item as Map<String, dynamic>);
        _streams[stream.id] = stream;
      }
    }
    notifyListeners();
  }
}
