/// FluxForge Audio Pool — Pre-allocated Audio Players for Fast Playback
///
/// Problem:
/// - Creating new audio player instances takes time (~10-50ms)
/// - For rapid-fire events (cascade, rollup ticks), this causes latency
///
/// Solution:
/// - Pre-allocate a pool of audio player voice IDs
/// - Reuse voices when available
/// - Track playing/stopped state
/// - Automatic pool expansion when needed
///
/// Usage:
/// ```dart
/// final voiceId = await AudioPool.instance.acquire('cascade_step', busId: 0);
/// // Voice plays automatically when acquired
/// AudioPool.instance.release(voiceId);
/// ```

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// =============================================================================
// POOL CONFIGURATION
// =============================================================================

/// Configuration for audio pool behavior
class AudioPoolConfig {
  /// Minimum voices per event type
  final int minVoicesPerEvent;

  /// Maximum voices per event type (to prevent memory bloat)
  final int maxVoicesPerEvent;

  /// How long to keep idle voices before releasing (ms)
  final int idleTimeoutMs;

  /// Whether to preload common events on init
  final bool preloadCommonEvents;

  const AudioPoolConfig({
    this.minVoicesPerEvent = 2,
    this.maxVoicesPerEvent = 8,
    this.idleTimeoutMs = 30000,
    this.preloadCommonEvents = true,
  });

  static const defaultConfig = AudioPoolConfig();

  /// Optimized for slot lab rapid-fire events
  static const slotLabConfig = AudioPoolConfig(
    minVoicesPerEvent: 4,
    maxVoicesPerEvent: 12,
    idleTimeoutMs: 60000,
    preloadCommonEvents: true,
  );
}

// =============================================================================
// POOLED VOICE — Single voice instance with tracking
// =============================================================================

/// P1.10 FIX: Use int milliseconds instead of DateTime objects to avoid GC pressure
/// Each DateTime.now() call allocates a new object on the heap.
/// Using millisecondsSinceEpoch directly is allocation-free.
class _PooledVoice {
  final int voiceId;
  final String eventKey;
  final int busId;
  double lastPan; // Track last used pan for potential reuse
  bool isPlaying;
  int lastUsedMs; // P1.10: milliseconds since epoch (no allocation)

  _PooledVoice({
    required this.voiceId,
    required this.eventKey,
    required this.busId,
    this.lastPan = 0.0,
    this.isPlaying = false,
  }) : lastUsedMs = DateTime.now().millisecondsSinceEpoch;

  void markPlaying() {
    isPlaying = true;
    lastUsedMs = DateTime.now().millisecondsSinceEpoch;
  }

  void markStopped() {
    isPlaying = false;
    lastUsedMs = DateTime.now().millisecondsSinceEpoch;
  }

  bool get isIdle => !isPlaying;

  /// P1.10: Returns idle duration in milliseconds (allocation-free)
  int get idleDurationMs => DateTime.now().millisecondsSinceEpoch - lastUsedMs;
}

// =============================================================================
// OVERFLOW VOICE — Temporary voice created when pool is full
// =============================================================================

/// P0.4 FIX: Track overflow voices to prevent memory leaks
/// These are created when the pool is full and all voices are busy.
/// They have an estimated duration and auto-release when done.
/// P1.10 FIX: Use int milliseconds instead of DateTime/Duration objects
class _OverflowVoice {
  final int voiceId;
  final String eventKey;
  final int busId;
  final int createdAtMs; // P1.10: milliseconds since epoch
  final int estimatedDurationMs; // P1.10: milliseconds (not Duration object)

  _OverflowVoice({
    required this.voiceId,
    required this.eventKey,
    required this.busId,
    this.estimatedDurationMs = 2000,
  }) : createdAtMs = DateTime.now().millisecondsSinceEpoch;

  /// Check if this overflow voice should be cleaned up
  /// P1.10: Pure int comparison, no object allocations
  bool get shouldCleanup {
    // Add 500ms buffer to ensure playback completes
    final thresholdMs = estimatedDurationMs + 500;
    return DateTime.now().millisecondsSinceEpoch - createdAtMs > thresholdMs;
  }

  /// P1.10: Age in milliseconds (allocation-free)
  int get ageMs => DateTime.now().millisecondsSinceEpoch - createdAtMs;
}

// =============================================================================
// AUDIO POOL — Singleton manager
// =============================================================================

class AudioPool extends ChangeNotifier {
  // Singleton
  static AudioPool? _instance;
  static AudioPool get instance => _instance ??= AudioPool._();

  // Configuration
  AudioPoolConfig _config = AudioPoolConfig.defaultConfig;

  // Voice pools by event key (e.g., "REEL_STOP_0", "CASCADE_STEP")
  final Map<String, List<_PooledVoice>> _pools = {};

  // All active voices for quick lookup
  final Map<int, _PooledVoice> _activeVoices = {};

  // P0.4 FIX: Track overflow voices separately to prevent memory leaks
  // When pool is full and all voices are busy, we create temporary voices
  // that must be tracked and auto-released when playback ends
  final Map<int, _OverflowVoice> _overflowVoices = {};

  // Stats
  int _totalAcquires = 0;
  int _poolHits = 0;
  int _poolMisses = 0;
  int _overflowCount = 0;  // Track overflow events for diagnostics

  // Cleanup timer
  Timer? _cleanupTimer;
  Timer? _overflowCleanupTimer;  // Separate timer for overflow cleanup

  AudioPool._() {
    _startCleanupTimer();
    _startOverflowCleanupTimer();
  }

  // ==========================================================================
  // CONFIGURATION
  // ==========================================================================

  /// Configure the pool (call early, before first use)
  void configure(AudioPoolConfig config) {
    _config = config;
  }

  // ==========================================================================
  // ACQUIRE / RELEASE
  // ==========================================================================

  /// Acquire a voice for playback
  ///
  /// Returns voice ID that can be used with FFI.
  /// If pool has available voice, reuses it (fast).
  /// Otherwise creates new voice (slower).
  /// pan: -1.0 = full left, 0.0 = center, +1.0 = full right
  int acquire({
    required String eventKey,
    required String audioPath,
    required int busId,
    double volume = 1.0,
    double pan = 0.0,
  }) {
    _totalAcquires++;

    // Normalize event key
    final normalizedKey = _normalizeKey(eventKey);

    // Try to get from pool
    final pool = _pools[normalizedKey] ??= [];

    // Find idle voice in pool
    _PooledVoice? voice;
    for (final v in pool) {
      if (v.isIdle && v.busId == busId) {
        voice = v;
        break;
      }
    }

    if (voice != null) {
      // Pool hit - reuse existing voice
      _poolHits++;
      voice.markPlaying();
      voice.lastPan = pan;
      _playVoice(voice.voiceId, audioPath, volume, pan, busId);
      return voice.voiceId;
    }

    // Pool miss - create new voice
    _poolMisses++;

    // Check max limit
    if (pool.length >= _config.maxVoicesPerEvent) {
      // Steal oldest idle voice if possible
      // P1.10: int comparison is allocation-free
      pool.sort((a, b) => a.lastUsedMs.compareTo(b.lastUsedMs));
      for (final v in pool) {
        if (v.isIdle) {
          v.markPlaying();
          v.lastPan = pan;
          _playVoice(v.voiceId, audioPath, volume, pan, busId);
          return v.voiceId;
        }
      }
      // P0.4 FIX: All voices busy - create overflow voice WITH tracking
      final tempVoiceId = _createAndPlayVoice(audioPath, volume, pan, busId);
      if (tempVoiceId > 0) {
        _overflowCount++;
        _overflowVoices[tempVoiceId] = _OverflowVoice(
          voiceId: tempVoiceId,
          eventKey: normalizedKey,
          busId: busId,
          // P1.10: Use int milliseconds instead of Duration
          estimatedDurationMs: 2000,
        );
      }
      return tempVoiceId;
    }

    // Create new pooled voice
    final newVoiceId = _createAndPlayVoice(audioPath, volume, pan, busId);
    final newVoice = _PooledVoice(
      voiceId: newVoiceId,
      eventKey: normalizedKey,
      busId: busId,
      lastPan: pan,
    )..markPlaying();

    pool.add(newVoice);
    _activeVoices[newVoiceId] = newVoice;

    return newVoiceId;
  }

  /// Release a voice back to pool
  void release(int voiceId) {
    final voice = _activeVoices[voiceId];
    if (voice != null) {
      voice.markStopped();
      // Stop playback
      try {
        NativeFFI.instance.playbackStopOneShot(voiceId);
      } catch (e) { /* ignored */ }
    }
  }

  /// Force-stop a voice (for urgent interrupts)
  void forceStop(int voiceId) {
    release(voiceId);
  }

  /// Stop all voices for an event key
  void stopAllForEvent(String eventKey) {
    final normalizedKey = _normalizeKey(eventKey);
    final pool = _pools[normalizedKey];
    if (pool == null) return;

    for (final voice in pool) {
      if (voice.isPlaying) {
        release(voice.voiceId);
      }
    }
  }

  /// Stop all pooled voices (including overflow)
  void stopAll() {
    // Stop pooled voices
    for (final pool in _pools.values) {
      for (final voice in pool) {
        if (voice.isPlaying) {
          try {
            NativeFFI.instance.playbackStopOneShot(voice.voiceId);
            voice.markStopped();
          } catch (e) { /* ignored */ }
        }
      }
    }
    // P0.4: Also stop overflow voices
    for (final voiceId in _overflowVoices.keys.toList()) {
      try {
        NativeFFI.instance.playbackStopOneShot(voiceId);
      } catch (e) {
        // Voice may already be stopped
      }
    }
    _overflowVoices.clear();
  }

  // ==========================================================================
  // PRELOADING
  // ==========================================================================

  /// Preload voices for common events
  /// Call this after EventRegistry is populated
  void preloadCommonEvents(List<String> eventKeys, int busId) {
    for (final key in eventKeys) {
      _ensurePoolSize(key, _config.minVoicesPerEvent, busId);
    }
  }

  /// Preload voices for slot lab events
  void preloadSlotLabEvents() {
    const slotEvents = [
      'REEL_STOP_0',
      'REEL_STOP_1',
      'REEL_STOP_2',
      'REEL_STOP_3',
      'REEL_STOP_4',
      'REEL_STOP',
      'CASCADE_STEP',
      'ROLLUP_TICK',
      'WIN_LINE_SHOW',
    ];

    for (final event in slotEvents) {
      _ensurePoolSize(event, _config.minVoicesPerEvent, 0); // Bus 0 = SFX
    }
  }

  // ==========================================================================
  // AUDIO FILE PRELOADING (FFI parallel load)
  // ==========================================================================

  /// Preload audio files in parallel using Rust rayon thread pool.
  /// This decodes and caches audio data for instant playback.
  /// Returns result map: {total, loaded, cached, failed, duration_ms}
  Map<String, dynamic> preloadAudioFiles(List<String> paths) {
    if (paths.isEmpty) {
      return {'total': 0, 'loaded': 0, 'cached': 0, 'failed': 0, 'duration_ms': 0};
    }

    final uniquePaths = paths.toSet().toList(); // Remove duplicates

    final result = NativeFFI.instance.cachePreloadFiles(uniquePaths);

    if (result.containsKey('error')) {
    } else {
    }

    return result;
  }

  /// Check if all paths are already cached (fast check)
  bool allAudioFilesCached(List<String> paths) {
    if (paths.isEmpty) return true;
    return NativeFFI.instance.cacheAllLoaded(paths);
  }

  /// Check if single path is cached
  bool isAudioFileCached(String path) {
    return NativeFFI.instance.cacheIsLoaded(path);
  }

  /// Get audio cache statistics
  Map<String, dynamic> getCacheStats() {
    return NativeFFI.instance.cacheStats();
  }

  void _ensurePoolSize(String eventKey, int minSize, int busId) {
    final normalizedKey = _normalizeKey(eventKey);
    final pool = _pools[normalizedKey] ??= [];

    while (pool.length < minSize) {
      // Create dummy voice IDs - actual audio will be loaded on acquire
      final voiceId = _nextVoiceId++;
      final voice = _PooledVoice(
        voiceId: voiceId,
        eventKey: normalizedKey,
        busId: busId,
      );
      pool.add(voice);
      _activeVoices[voiceId] = voice;
    }
  }

  // ==========================================================================
  // INTERNAL HELPERS
  // ==========================================================================

  int _nextVoiceId = 10000; // Start high to avoid conflicts with engine IDs

  String _normalizeKey(String key) => key.toUpperCase().trim();

  int _createAndPlayVoice(String audioPath, double volume, double pan, int busId) {
    try {
      // Use Rust PlaybackEngine one-shot system
      final voiceId = NativeFFI.instance.playbackPlayToBus(
        audioPath,
        volume: volume.clamp(0.0, 1.0),
        pan: pan.clamp(-1.0, 1.0),
        busId: busId,
      );
      return voiceId;
    } catch (e) {
      return -1;
    }
  }

  void _playVoice(int voiceId, String audioPath, double volume, double pan, int busId) {
    try {
      // For reused voices, we still need to trigger new playback
      // The engine handles voice reuse internally
      NativeFFI.instance.playbackPlayToBus(
        audioPath,
        volume: volume.clamp(0.0, 1.0),
        pan: pan.clamp(-1.0, 1.0),
        busId: busId,
      );
    } catch (e) { /* ignored */ }
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      Duration(milliseconds: _config.idleTimeoutMs ~/ 2),
      (_) => _cleanupIdleVoices(),
    );
  }

  /// P1.10 FIX: Use int milliseconds comparison (no Duration allocation)
  void _cleanupIdleVoices() {
    final timeoutMs = _config.idleTimeoutMs;
    int cleaned = 0;

    for (final pool in _pools.values) {
      pool.removeWhere((voice) {
        if (voice.isIdle && voice.idleDurationMs > timeoutMs) {
          _activeVoices.remove(voice.voiceId);
          cleaned++;
          return true;
        }
        return false;
      });
    }

    if (cleaned > 0) {
    }
  }

  // P0.4 FIX: Separate cleanup for overflow voices
  void _startOverflowCleanupTimer() {
    _overflowCleanupTimer?.cancel();
    // Check overflow voices every 500ms for quick cleanup
    _overflowCleanupTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _cleanupOverflowVoices(),
    );
  }

  void _cleanupOverflowVoices() {
    if (_overflowVoices.isEmpty) return;

    final toRemove = <int>[];

    for (final entry in _overflowVoices.entries) {
      if (entry.value.shouldCleanup) {
        toRemove.add(entry.key);
        // Stop the voice to free engine resources
        try {
          NativeFFI.instance.playbackStopOneShot(entry.key);
        } catch (e) {
          // Voice may already be stopped, ignore
        }
      }
    }

    for (final voiceId in toRemove) {
      _overflowVoices.remove(voiceId);
    }

    if (toRemove.isNotEmpty) {
    }
  }

  /// Manually release an overflow voice (call when audio completes)
  void releaseOverflow(int voiceId) {
    final overflow = _overflowVoices.remove(voiceId);
    if (overflow != null) {
      try {
        NativeFFI.instance.playbackStopOneShot(voiceId);
      } catch (e) {
        // Voice may already be stopped
      }
    }
  }

  // ==========================================================================
  // STATS
  // ==========================================================================

  int get totalAcquires => _totalAcquires;
  int get poolHits => _poolHits;
  int get poolMisses => _poolMisses;
  int get overflowCount => _overflowCount;  // P0.4: Track overflow events
  int get pendingOverflowVoices => _overflowVoices.length;  // P0.4: Current overflow count
  double get hitRate => _totalAcquires > 0 ? _poolHits / _totalAcquires : 0.0;

  int get totalPooledVoices => _pools.values.fold(0, (sum, pool) => sum + pool.length);
  int get activeVoiceCount => _activeVoices.values.where((v) => v.isPlaying).length;

  Map<String, int> get poolSizes => {
    for (final entry in _pools.entries) entry.key: entry.value.length,
  };

  String get statsString {
    return 'AudioPool: acquires=$_totalAcquires, hits=$_poolHits, misses=$_poolMisses, '
        'hitRate=${(hitRate * 100).toStringAsFixed(1)}%, '
        'pooled=$totalPooledVoices, active=$activeVoiceCount, '
        'overflow=$_overflowCount (pending: ${_overflowVoices.length})';
  }

  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _overflowCleanupTimer?.cancel();  // P0.4: Cancel overflow timer
    stopAll();
    _stopAllOverflowVoices();  // P0.4: Clean up overflow voices
    _pools.clear();
    _activeVoices.clear();
    _overflowVoices.clear();  // P0.4: Clear overflow tracking
    super.dispose();
  }

  /// P0.4: Stop all overflow voices
  void _stopAllOverflowVoices() {
    for (final voiceId in _overflowVoices.keys) {
      try {
        NativeFFI.instance.playbackStopOneShot(voiceId);
      } catch (e) {
        // Voice may already be stopped
      }
    }
    _overflowVoices.clear();
  }

  /// Reset pool (for testing or memory cleanup)
  void reset() {
    stopAll();
    _stopAllOverflowVoices();  // P0.4: Clear overflow voices
    _pools.clear();
    _activeVoices.clear();
    _overflowVoices.clear();  // P0.4: Clear overflow tracking
    _totalAcquires = 0;
    _poolHits = 0;
    _poolMisses = 0;
    _overflowCount = 0;  // P0.4: Reset overflow counter
  }
}
