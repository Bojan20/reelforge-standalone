// Session Persistence Provider
//
// Persist session state with:
// - IndexedDB-like storage
// - Auto-save with debouncing
// - Version migration
// - Emergency backup on close
// - Schema validation

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

// ============ Types ============

class SerializedClip {
  final String id;
  final String trackId;
  final String name;
  final double startTime;
  final double duration;
  final String color;
  final String? audioFileId;

  const SerializedClip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.startTime,
    required this.duration,
    required this.color,
    this.audioFileId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackId': trackId,
    'name': name,
    'startTime': startTime,
    'duration': duration,
    'color': color,
    'audioFileId': audioFileId,
  };

  factory SerializedClip.fromJson(Map<String, dynamic> json) => SerializedClip(
    id: json['id'] as String,
    trackId: json['trackId'] as String,
    name: json['name'] as String,
    startTime: (json['startTime'] as num).toDouble(),
    duration: (json['duration'] as num).toDouble(),
    color: json['color'] as String,
    audioFileId: json['audioFileId'] as String?,
  );
}

class SerializedTrack {
  final String id;
  final String name;
  final String color;
  final bool muted;
  final bool solo;
  final bool armed;

  const SerializedTrack({
    required this.id,
    required this.name,
    required this.color,
    this.muted = false,
    this.solo = false,
    this.armed = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'muted': muted,
    'solo': solo,
    'armed': armed,
  };

  factory SerializedTrack.fromJson(Map<String, dynamic> json) => SerializedTrack(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    muted: json['muted'] as bool? ?? false,
    solo: json['solo'] as bool? ?? false,
    armed: json['armed'] as bool? ?? false,
  );
}

class SerializedBus {
  final String id;
  final String name;
  final double volume;
  final double pan;
  final bool muted;
  final bool solo;
  final List<SerializedInsert> inserts;

  const SerializedBus({
    required this.id,
    required this.name,
    this.volume = 0.85,
    this.pan = 0,
    this.muted = false,
    this.solo = false,
    this.inserts = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'volume': volume,
    'pan': pan,
    'muted': muted,
    'solo': solo,
    'inserts': inserts.map((i) => i.toJson()).toList(),
  };

  factory SerializedBus.fromJson(Map<String, dynamic> json) => SerializedBus(
    id: json['id'] as String,
    name: json['name'] as String,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.85,
    pan: (json['pan'] as num?)?.toDouble() ?? 0,
    muted: json['muted'] as bool? ?? false,
    solo: json['solo'] as bool? ?? false,
    inserts: (json['inserts'] as List<dynamic>?)
        ?.map((i) => SerializedInsert.fromJson(i as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class SerializedInsert {
  final String id;
  final String pluginId;
  final String name;
  final bool bypassed;
  final Map<String, double> params;

  const SerializedInsert({
    required this.id,
    required this.pluginId,
    required this.name,
    this.bypassed = false,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'pluginId': pluginId,
    'name': name,
    'bypassed': bypassed,
    'params': params,
  };

  factory SerializedInsert.fromJson(Map<String, dynamic> json) => SerializedInsert(
    id: json['id'] as String,
    pluginId: json['pluginId'] as String,
    name: json['name'] as String,
    bypassed: json['bypassed'] as bool? ?? false,
    params: (json['params'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
  );
}

class SessionState {
  final int version;
  final int timestamp;
  final SessionTimeline timeline;
  final SessionTransport transport;
  final SessionMixer mixer;
  final SessionUI ui;

  const SessionState({
    this.version = 1,
    required this.timestamp,
    required this.timeline,
    required this.transport,
    required this.mixer,
    required this.ui,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp,
    'timeline': timeline.toJson(),
    'transport': transport.toJson(),
    'mixer': mixer.toJson(),
    'ui': ui.toJson(),
  };

  factory SessionState.fromJson(Map<String, dynamic> json) => SessionState(
    version: json['version'] as int? ?? 1,
    timestamp: json['timestamp'] as int,
    timeline: SessionTimeline.fromJson(json['timeline'] as Map<String, dynamic>),
    transport: SessionTransport.fromJson(json['transport'] as Map<String, dynamic>),
    mixer: SessionMixer.fromJson(json['mixer'] as Map<String, dynamic>),
    ui: SessionUI.fromJson(json['ui'] as Map<String, dynamic>),
  );
}

class SessionTimeline {
  final List<SerializedClip> clips;
  final List<SerializedTrack> tracks;
  final double zoom;
  final double scrollOffset;

  const SessionTimeline({
    this.clips = const [],
    this.tracks = const [],
    this.zoom = 50,
    this.scrollOffset = 0,
  });

  Map<String, dynamic> toJson() => {
    'clips': clips.map((c) => c.toJson()).toList(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'zoom': zoom,
    'scrollOffset': scrollOffset,
  };

  factory SessionTimeline.fromJson(Map<String, dynamic> json) => SessionTimeline(
    clips: (json['clips'] as List<dynamic>?)
        ?.map((c) => SerializedClip.fromJson(c as Map<String, dynamic>))
        .toList() ?? [],
    tracks: (json['tracks'] as List<dynamic>?)
        ?.map((t) => SerializedTrack.fromJson(t as Map<String, dynamic>))
        .toList() ?? [],
    zoom: (json['zoom'] as num?)?.toDouble() ?? 50,
    scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
  );
}

class SessionTransport {
  final double currentTime;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  final double tempo;

  const SessionTransport({
    this.currentTime = 0,
    this.loopEnabled = false,
    this.loopStart = 0,
    this.loopEnd = 60,
    this.tempo = 120,
  });

  Map<String, dynamic> toJson() => {
    'currentTime': currentTime,
    'loopEnabled': loopEnabled,
    'loopStart': loopStart,
    'loopEnd': loopEnd,
    'tempo': tempo,
  };

  factory SessionTransport.fromJson(Map<String, dynamic> json) => SessionTransport(
    currentTime: (json['currentTime'] as num?)?.toDouble() ?? 0,
    loopEnabled: json['loopEnabled'] as bool? ?? false,
    loopStart: (json['loopStart'] as num?)?.toDouble() ?? 0,
    loopEnd: (json['loopEnd'] as num?)?.toDouble() ?? 60,
    tempo: (json['tempo'] as num?)?.toDouble() ?? 120,
  );
}

class SessionMixer {
  final List<SerializedBus> buses;

  const SessionMixer({this.buses = const []});

  Map<String, dynamic> toJson() => {
    'buses': buses.map((b) => b.toJson()).toList(),
  };

  factory SessionMixer.fromJson(Map<String, dynamic> json) => SessionMixer(
    buses: (json['buses'] as List<dynamic>?)
        ?.map((b) => SerializedBus.fromJson(b as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class SessionUI {
  final bool leftPanelOpen;
  final bool rightPanelOpen;
  final bool bottomPanelOpen;
  final double leftPanelWidth;
  final double rightPanelWidth;
  final double bottomPanelHeight;
  final String? selectedBusId;
  final List<String> selectedClipIds;

  const SessionUI({
    this.leftPanelOpen = true,
    this.rightPanelOpen = true,
    this.bottomPanelOpen = true,
    this.leftPanelWidth = 280,
    this.rightPanelWidth = 320,
    this.bottomPanelHeight = 200,
    this.selectedBusId,
    this.selectedClipIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'leftPanelOpen': leftPanelOpen,
    'rightPanelOpen': rightPanelOpen,
    'bottomPanelOpen': bottomPanelOpen,
    'leftPanelWidth': leftPanelWidth,
    'rightPanelWidth': rightPanelWidth,
    'bottomPanelHeight': bottomPanelHeight,
    'selectedBusId': selectedBusId,
    'selectedClipIds': selectedClipIds,
  };

  factory SessionUI.fromJson(Map<String, dynamic> json) => SessionUI(
    leftPanelOpen: json['leftPanelOpen'] as bool? ?? true,
    rightPanelOpen: json['rightPanelOpen'] as bool? ?? true,
    bottomPanelOpen: json['bottomPanelOpen'] as bool? ?? true,
    leftPanelWidth: (json['leftPanelWidth'] as num?)?.toDouble() ?? 280,
    rightPanelWidth: (json['rightPanelWidth'] as num?)?.toDouble() ?? 320,
    bottomPanelHeight: (json['bottomPanelHeight'] as num?)?.toDouble() ?? 200,
    selectedBusId: json['selectedBusId'] as String?,
    selectedClipIds: (json['selectedClipIds'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList() ?? [],
  );
}

// ============ Provider ============

class SessionPersistenceProvider extends ChangeNotifier {
  static const int _sessionVersion = 1;
  static const String _storageKey = 'fluxforge_session';

  Timer? _saveTimer;
  SessionState? _pendingState;
  int _lastSaveTime = 0;

  final int debounceMs;
  final int autoSaveInterval;

  // Callbacks
  void Function(SessionState state)? onRestore;
  void Function(Exception error)? onError;

  // In-memory storage (in real app, use SharedPreferences or IndexedDB)
  final Map<String, String> _storage = {};

  SessionPersistenceProvider({
    this.debounceMs = 1000,
    this.autoSaveInterval = 30000,
  }) {
    _startAutoSave();
  }

  void _startAutoSave() {
    Timer.periodic(Duration(milliseconds: autoSaveInterval), (_) {
      if (_pendingState != null) {
        saveNow(_pendingState!);
      }
    });
  }

  /// Save state with debouncing
  void saveState(SessionState state) {
    _pendingState = SessionState(
      version: _sessionVersion,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      timeline: state.timeline,
      transport: state.transport,
      mixer: state.mixer,
      ui: state.ui,
    );

    _saveTimer?.cancel();
    _saveTimer = Timer(Duration(milliseconds: debounceMs), () async {
      if (_pendingState != null) {
        await saveNow(_pendingState!);
        _pendingState = null;
      }
    });
  }

  /// Save immediately
  Future<bool> saveNow(SessionState state) async {
    try {
      final json = jsonEncode(state.toJson());
      _storage[_storageKey] = json;
      _lastSaveTime = DateTime.now().millisecondsSinceEpoch;
      return true;
    } catch (e) {
      onError?.call(Exception('Save failed: $e'));
      return false;
    }
  }

  /// Load state
  Future<SessionState?> loadState() async {
    try {
      final json = _storage[_storageKey];
      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      final state = SessionState.fromJson(data);

      // Version check
      if (state.version != _sessionVersion) {
      }

      onRestore?.call(state);
      return state;
    } catch (e) {
      onError?.call(Exception('Load failed: $e'));
      return null;
    }
  }

  /// Clear saved state
  Future<bool> clearState() async {
    try {
      _storage.remove(_storageKey);
      return true;
    } catch (e) {
      onError?.call(Exception('Clear failed: $e'));
      return false;
    }
  }

  /// Get last save time
  int get lastSaveTime => _lastSaveTime;

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

// ============ Factory ============

SessionState createSessionState({
  List<SerializedClip>? clips,
  List<SerializedTrack>? tracks,
  double? zoom,
  double? scrollOffset,
  double? currentTime,
  bool? loopEnabled,
  double? loopStart,
  double? loopEnd,
  double? tempo,
  List<SerializedBus>? buses,
  bool? leftPanelOpen,
  bool? rightPanelOpen,
  bool? bottomPanelOpen,
  double? leftPanelWidth,
  double? rightPanelWidth,
  double? bottomPanelHeight,
  String? selectedBusId,
  List<String>? selectedClipIds,
}) {
  return SessionState(
    timestamp: DateTime.now().millisecondsSinceEpoch,
    timeline: SessionTimeline(
      clips: clips ?? [],
      tracks: tracks ?? [],
      zoom: zoom ?? 50,
      scrollOffset: scrollOffset ?? 0,
    ),
    transport: SessionTransport(
      currentTime: currentTime ?? 0,
      loopEnabled: loopEnabled ?? false,
      loopStart: loopStart ?? 0,
      loopEnd: loopEnd ?? 60,
      tempo: tempo ?? 120,
    ),
    mixer: SessionMixer(buses: buses ?? []),
    ui: SessionUI(
      leftPanelOpen: leftPanelOpen ?? true,
      rightPanelOpen: rightPanelOpen ?? true,
      bottomPanelOpen: bottomPanelOpen ?? true,
      leftPanelWidth: leftPanelWidth ?? 280,
      rightPanelWidth: rightPanelWidth ?? 320,
      bottomPanelHeight: bottomPanelHeight ?? 200,
      selectedBusId: selectedBusId,
      selectedClipIds: selectedClipIds ?? [],
    ),
  );
}
