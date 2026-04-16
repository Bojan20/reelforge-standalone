import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Slot Spatial Audio™ Provider — 3D Positional Audio for Slot Games.
///
/// Bridges rf-slot-spatial Rust crate to Flutter UI via FFI.
/// Manages spatial scene state: sources, positions, listener updates.
///
/// Register as GetIt singleton.
class SlotSpatialProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _initialized = false;
  String _gameId = 'default';
  int _sourceCount = 0;
  Map<String, dynamic>? _sceneSnapshot;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  String get gameId => _gameId;
  int get sourceCount => _sourceCount;
  Map<String, dynamic>? get sceneSnapshot => _sceneSnapshot;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  SlotSpatialProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize spatial scene with game ID.
  void init({String gameId = 'default'}) {
    final config = jsonEncode({'game_id': gameId});
    final result = _ffi.slotSpatialInit(configJson: config);
    if (result == 0) {
      _gameId = gameId;
      _initialized = true;
      _refreshState();
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOURCE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add or update a spatial audio source.
  /// [source] should contain: event_id, position {x,y,z}, gain, radius, etc.
  bool addSource(Map<String, dynamic> source) {
    final result = _ffi.slotSpatialAddSource(jsonEncode(source));
    if (result == 0) {
      _refreshState();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Remove a spatial source by event_id.
  bool removeSource(String eventId) {
    final result = _ffi.slotSpatialRemoveSource(eventId);
    if (result == 0) {
      _refreshState();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Get current scene as structured data.
  Map<String, dynamic>? getScene() {
    final json = _ffi.slotSpatialGetScene();
    if (json != null) {
      _sceneSnapshot = jsonDecode(json) as Map<String, dynamic>;
      return _sceneSnapshot;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  void _refreshState() {
    _sourceCount = _ffi.slotSpatialSourceCount();
    getScene();
  }
}
