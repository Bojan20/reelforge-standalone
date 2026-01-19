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

class _PooledVoice {
  final int voiceId;
  final String eventKey;
  final int busId;
  bool isPlaying;
  DateTime lastUsed;

  _PooledVoice({
    required this.voiceId,
    required this.eventKey,
    required this.busId,
    this.isPlaying = false,
  }) : lastUsed = DateTime.now();

  void markPlaying() {
    isPlaying = true;
    lastUsed = DateTime.now();
  }

  void markStopped() {
    isPlaying = false;
    lastUsed = DateTime.now();
  }

  bool get isIdle => !isPlaying;

  Duration get idleDuration => DateTime.now().difference(lastUsed);
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

  // Stats
  int _totalAcquires = 0;
  int _poolHits = 0;
  int _poolMisses = 0;

  // Cleanup timer
  Timer? _cleanupTimer;

  AudioPool._() {
    _startCleanupTimer();
  }

  // ==========================================================================
  // CONFIGURATION
  // ==========================================================================

  /// Configure the pool (call early, before first use)
  void configure(AudioPoolConfig config) {
    _config = config;
    debugPrint('[AudioPool] Configured: min=${config.minVoicesPerEvent}, max=${config.maxVoicesPerEvent}');
  }

  // ==========================================================================
  // ACQUIRE / RELEASE
  // ==========================================================================

  /// Acquire a voice for playback
  ///
  /// Returns voice ID that can be used with FFI.
  /// If pool has available voice, reuses it (fast).
  /// Otherwise creates new voice (slower).
  int acquire({
    required String eventKey,
    required String audioPath,
    required int busId,
    double volume = 1.0,
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
      _playVoice(voice.voiceId, audioPath, volume, busId);
      debugPrint('[AudioPool] HIT: $normalizedKey (voice ${voice.voiceId})');
      return voice.voiceId;
    }

    // Pool miss - create new voice
    _poolMisses++;

    // Check max limit
    if (pool.length >= _config.maxVoicesPerEvent) {
      // Steal oldest idle voice if possible
      pool.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
      for (final v in pool) {
        if (v.isIdle) {
          v.markPlaying();
          _playVoice(v.voiceId, audioPath, volume, busId);
          debugPrint('[AudioPool] RECYCLE: $normalizedKey (voice ${v.voiceId})');
          return v.voiceId;
        }
      }
      // All voices busy - play anyway but don't pool
      final tempVoiceId = _createAndPlayVoice(audioPath, volume, busId);
      debugPrint('[AudioPool] OVERFLOW: $normalizedKey (temp voice $tempVoiceId)');
      return tempVoiceId;
    }

    // Create new pooled voice
    final newVoiceId = _createAndPlayVoice(audioPath, volume, busId);
    final newVoice = _PooledVoice(
      voiceId: newVoiceId,
      eventKey: normalizedKey,
      busId: busId,
    )..markPlaying();

    pool.add(newVoice);
    _activeVoices[newVoiceId] = newVoice;

    debugPrint('[AudioPool] MISS: $normalizedKey (new voice $newVoiceId, pool size: ${pool.length})');
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
      } catch (e) {
        debugPrint('[AudioPool] Release error: $e');
      }
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

  /// Stop all pooled voices
  void stopAll() {
    for (final pool in _pools.values) {
      for (final voice in pool) {
        if (voice.isPlaying) {
          try {
            NativeFFI.instance.playbackStopOneShot(voice.voiceId);
            voice.markStopped();
          } catch (e) {
            debugPrint('[AudioPool] StopAll error: $e');
          }
        }
      }
    }
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
    debugPrint('[AudioPool] Preloaded ${eventKeys.length} event types');
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
    debugPrint('[AudioPool] Preloaded Slot Lab events');
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

  int _createAndPlayVoice(String audioPath, double volume, int busId) {
    try {
      // Use Rust PlaybackEngine one-shot system
      final voiceId = NativeFFI.instance.playbackPlayToBus(
        audioPath,
        volume: volume.clamp(0.0, 1.0),
        busId: busId,
      );
      return voiceId;
    } catch (e) {
      debugPrint('[AudioPool] Create voice error: $e');
      return -1;
    }
  }

  void _playVoice(int voiceId, String audioPath, double volume, int busId) {
    try {
      // For reused voices, we still need to trigger new playback
      // The engine handles voice reuse internally
      NativeFFI.instance.playbackPlayToBus(
        audioPath,
        volume: volume.clamp(0.0, 1.0),
        busId: busId,
      );
    } catch (e) {
      debugPrint('[AudioPool] Play voice error: $e');
    }
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

  void _cleanupIdleVoices() {
    final timeout = Duration(milliseconds: _config.idleTimeoutMs);
    int cleaned = 0;

    for (final pool in _pools.values) {
      pool.removeWhere((voice) {
        if (voice.isIdle && voice.idleDuration > timeout) {
          _activeVoices.remove(voice.voiceId);
          cleaned++;
          return true;
        }
        return false;
      });
    }

    if (cleaned > 0) {
      debugPrint('[AudioPool] Cleaned $cleaned idle voices');
    }
  }

  // ==========================================================================
  // STATS
  // ==========================================================================

  int get totalAcquires => _totalAcquires;
  int get poolHits => _poolHits;
  int get poolMisses => _poolMisses;
  double get hitRate => _totalAcquires > 0 ? _poolHits / _totalAcquires : 0.0;

  int get totalPooledVoices => _pools.values.fold(0, (sum, pool) => sum + pool.length);
  int get activeVoiceCount => _activeVoices.values.where((v) => v.isPlaying).length;

  Map<String, int> get poolSizes => {
    for (final entry in _pools.entries) entry.key: entry.value.length,
  };

  String get statsString {
    return 'AudioPool: acquires=$_totalAcquires, hits=$_poolHits, misses=$_poolMisses, '
        'hitRate=${(hitRate * 100).toStringAsFixed(1)}%, '
        'pooled=$totalPooledVoices, active=$activeVoiceCount';
  }

  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    stopAll();
    _pools.clear();
    _activeVoices.clear();
    super.dispose();
  }

  /// Reset pool (for testing or memory cleanup)
  void reset() {
    stopAll();
    _pools.clear();
    _activeVoices.clear();
    _totalAcquires = 0;
    _poolHits = 0;
    _poolMisses = 0;
    debugPrint('[AudioPool] Reset');
  }
}
