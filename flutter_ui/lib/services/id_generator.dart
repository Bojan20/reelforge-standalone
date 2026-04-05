/// FluxForge ID Generator — Thread-safe atomic ID generation
///
/// Problem:
/// - DateTime.now().millisecondsSinceEpoch can return same value for rapid calls
/// - This causes ID collisions in rapid-fire events (CASCADE_STEP, ROLLUP_TICK)
///
/// Solution:
/// - Atomic counter that guarantees unique IDs
/// - Separate counters for different entity types
/// - High base value to avoid conflicts with FFI IDs
///
/// Usage:
/// ```dart
/// final id = IdGenerator.layer(); // 'layer_10001'
/// final id = IdGenerator.region(); // 'region_20001'
/// final id = IdGenerator.event(); // 'event_30001'
/// ```
library;

/// Centralized ID generator for unique IDs without collisions
class IdGenerator {
  // Atomic counters for different entity types
  // Starting high to avoid conflicts with FFI/engine IDs
  static int _layerCounter = 10000;
  static int _regionCounter = 20000;
  static int _eventCounter = 30000;
  static int _voiceCounter = 40000;
  static int _trackCounter = 50000;
  static int _clipCounter = 60000;
  static int _actionCounter = 70000;
  static int _genericCounter = 100000;

  /// Generate unique layer ID
  static String layer() {
    return 'layer_${++_layerCounter}';
  }

  /// Generate unique region ID
  static String region() {
    return 'region_${++_regionCounter}';
  }

  /// Generate unique event ID
  static String event() {
    return 'event_${++_eventCounter}';
  }

  /// Generate unique voice ID
  static int voice() {
    return ++_voiceCounter;
  }

  /// Generate unique track ID
  static String track() {
    return 'track_${++_trackCounter}';
  }

  /// Generate unique clip ID
  static String clip() {
    return 'clip_${++_clipCounter}';
  }

  /// Generate unique action ID
  static String action() {
    return 'action_${++_actionCounter}';
  }

  /// Generate generic unique ID with custom prefix
  static String custom(String prefix) {
    return '${prefix}_${++_genericCounter}';
  }

  /// Generate unique int ID (for cases where int is needed)
  static int uniqueInt() {
    return ++_genericCounter;
  }

  /// Reset all counters (for testing only)
  static void reset() {
    _layerCounter = 10000;
    _regionCounter = 20000;
    _eventCounter = 30000;
    _voiceCounter = 40000;
    _trackCounter = 50000;
    _clipCounter = 60000;
    _actionCounter = 70000;
    _genericCounter = 100000;
  }

  /// Get current counter values (for debugging)
  static Map<String, int> get counters => {
    'layer': _layerCounter,
    'region': _regionCounter,
    'event': _eventCounter,
    'voice': _voiceCounter,
    'track': _trackCounter,
    'clip': _clipCounter,
    'action': _actionCounter,
    'generic': _genericCounter,
  };
}
