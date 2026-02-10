/// Voice Pool Provider
///
/// Extracted from MiddlewareProvider as part of Provider Decomposition.
/// Manages voice polyphony with stealing, priority, and virtual voices.
///
/// Provides:
/// - Voice allocation with priority-based stealing
/// - Virtual voice tracking (inaudible voices)
/// - Voice parameter updates (volume, pitch, pan)
/// - Pool statistics for monitoring
/// - Real-time engine stats via FFI (syncFromEngine)
///
/// Integration: Syncs with Rust engine via NativeFFI.getVoicePoolStats()

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing voice pool polyphony
class VoicePoolProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Internal voice pool (Dart-side tracking)
  late VoicePool _voicePool;

  /// Cached engine stats from FFI
  NativeVoicePoolStats _engineStats = NativeVoicePoolStats.empty();

  /// Peak voice count (for statistics)
  int _peakVoices = 0;

  /// Total steal count
  int _stealCount = 0;

  VoicePoolProvider({
    required NativeFFI ffi,
    VoicePoolConfig config = const VoicePoolConfig(),
  }) : _ffi = ffi {
    _voicePool = VoicePool(config: config);
    // Initial sync from engine
    syncFromEngine();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get pool configuration
  VoicePoolConfig get config => _voicePool.config;

  /// Number of active voices
  int get activeCount => _voicePool.activeCount;

  /// Number of virtual voices
  int get virtualCount => _voicePool.virtualCount;

  /// Available voice slots
  int get availableSlots => _voicePool.availableSlots;

  /// Get all active voice IDs
  Iterable<int> get activeVoiceIds => _voicePool.activeVoiceIds;

  /// Get first active voice ID or null
  int? get firstActiveVoiceId => _voicePool.firstActiveVoiceId;

  /// Peak voice count
  int get peakVoices => _peakVoices;

  /// Total steal count
  int get stealCount => _stealCount;

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE STATS (FFI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cached engine stats
  NativeVoicePoolStats get engineStats => _engineStats;

  /// Engine active voice count (from FFI)
  int get engineActiveCount => _engineStats.activeCount;

  /// Engine max voices
  int get engineMaxVoices => _engineStats.maxVoices;

  /// Engine looping voice count
  int get engineLoopingCount => _engineStats.loopingCount;

  /// Engine utilization percent (0-100)
  double get engineUtilization => _engineStats.utilizationPercent;

  /// Voices by source
  int get dawVoices => _engineStats.dawVoices;
  int get slotLabVoices => _engineStats.slotLabVoices;
  int get middlewareVoices => _engineStats.middlewareVoices;
  int get browserVoices => _engineStats.browserVoices;

  /// Voices by bus
  int get sfxVoices => _engineStats.sfxVoices;
  int get musicVoices => _engineStats.musicVoices;
  int get voiceVoices => _engineStats.voiceVoices;
  int get ambienceVoices => _engineStats.ambienceVoices;
  int get auxVoices => _engineStats.auxVoices;
  int get masterVoices => _engineStats.masterVoices;

  /// Sync stats from Rust engine via FFI
  void syncFromEngine() {
    try {
      _engineStats = _ffi.getVoicePoolStats();

      // Update peak from engine if higher
      if (_engineStats.activeCount > _peakVoices) {
        _peakVoices = _engineStats.activeCount;
      }

      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE ALLOCATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Request a new voice
  /// Returns voice ID or null if rejected
  int? requestVoice({
    required int soundId,
    required int busId,
    int priority = 50,
    double volume = 1.0,
    double pitch = 1.0,
    double pan = 0.0,
    double? spatialDistance,
  }) {
    final previousCount = _voicePool.activeCount;

    final voiceId = _voicePool.requestVoice(
      soundId: soundId,
      busId: busId,
      priority: priority,
      volume: volume,
      pitch: pitch,
      pan: pan,
      spatialDistance: spatialDistance,
    );

    if (voiceId != null) {
      // Track peak
      if (_voicePool.activeCount > _peakVoices) {
        _peakVoices = _voicePool.activeCount;
      }

      // Track steals (if count didn't increase, we stole)
      if (_voicePool.activeCount <= previousCount) {
        _stealCount++;
      }

      notifyListeners();
    }

    return voiceId;
  }

  /// Release a voice back to the pool
  void releaseVoice(int voiceId) {
    _voicePool.releaseVoice(voiceId);
    notifyListeners();
  }

  /// Release all voices
  void releaseAllVoices() {
    for (final voiceId in _voicePool.activeVoiceIds.toList()) {
      _voicePool.releaseVoice(voiceId);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE PARAMETERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update voice volume
  void setVoiceVolume(int voiceId, double volume) {
    _voicePool.updateVoice(voiceId, volume: volume);
    notifyListeners();
  }

  /// Update voice pitch
  void setVoicePitch(int voiceId, double pitch) {
    _voicePool.updateVoice(voiceId, pitch: pitch);
    notifyListeners();
  }

  /// Update voice pan
  void setVoicePan(int voiceId, double pan) {
    _voicePool.updateVoice(voiceId, pan: pan);
    notifyListeners();
  }

  /// Update multiple voice parameters at once
  void updateVoice(int voiceId, {
    double? volume,
    double? pitch,
    double? pan,
    double? spatialDistance,
  }) {
    _voicePool.updateVoice(
      voiceId,
      volume: volume,
      pitch: pitch,
      pan: pan,
      spatialDistance: spatialDistance,
    );
    notifyListeners();
  }

  /// Get voice info
  ActiveVoice? getVoice(int voiceId) => _voicePool.getVoice(voiceId);

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update pool configuration
  void updateConfig(VoicePoolConfig config) {
    _voicePool = VoicePool(config: config);
    notifyListeners();
  }

  /// Set max voices
  void setMaxVoices(int maxVoices) {
    updateConfig(config.copyWith(maxVoices: maxVoices));
  }

  /// Set stealing mode
  void setStealingMode(VoiceStealingMode mode) {
    updateConfig(config.copyWith(stealingMode: mode));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get pool statistics (combined Dart + Engine)
  VoicePoolStats getStats() {
    // Prefer engine stats if available
    final engineActive = _engineStats.activeCount;
    final dartActive = _voicePool.activeCount;

    return VoicePoolStats(
      activeVoices: engineActive > 0 ? engineActive : dartActive,
      virtualVoices: _voicePool.virtualCount,
      maxVoices: _engineStats.maxVoices > 0 ? _engineStats.maxVoices : config.maxVoices,
      peakVoices: _peakVoices,
      stealCount: _stealCount,
    );
  }

  /// Get extended engine statistics
  Map<String, dynamic> getEngineStatsMap() {
    return {
      'activeCount': _engineStats.activeCount,
      'maxVoices': _engineStats.maxVoices,
      'loopingCount': _engineStats.loopingCount,
      'utilization': _engineStats.utilizationPercent,
      'bySource': {
        'daw': _engineStats.dawVoices,
        'slotLab': _engineStats.slotLabVoices,
        'middleware': _engineStats.middlewareVoices,
        'browser': _engineStats.browserVoices,
      },
      'byBus': {
        'sfx': _engineStats.sfxVoices,
        'music': _engineStats.musicVoices,
        'voice': _engineStats.voiceVoices,
        'ambience': _engineStats.ambienceVoices,
        'aux': _engineStats.auxVoices,
        'master': _engineStats.masterVoices,
      },
      'timestamp': _engineStats.timestamp.toIso8601String(),
    };
  }

  /// Reset statistics
  void resetStats() {
    _peakVoices = _voicePool.activeCount;
    _stealCount = 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export configuration to JSON
  Map<String, dynamic> toJson() {
    return {
      'config': {
        'maxVoices': config.maxVoices,
        'stealingMode': config.stealingMode.index,
        'minPriorityToSteal': config.minPriorityToSteal,
        'stealFadeOutMs': config.stealFadeOutMs,
        'enableVirtualVoices': config.enableVirtualVoices,
        'virtualThreshold': config.virtualThreshold,
      },
      'stats': {
        'peakVoices': _peakVoices,
        'stealCount': _stealCount,
      },
    };
  }

  /// Import configuration from JSON
  void fromJson(Map<String, dynamic> json) {
    final configJson = json['config'] as Map<String, dynamic>?;
    if (configJson != null) {
      updateConfig(VoicePoolConfig(
        maxVoices: configJson['maxVoices'] as int? ?? 48,
        stealingMode: VoiceStealingMode.values[configJson['stealingMode'] as int? ?? 0],
        minPriorityToSteal: configJson['minPriorityToSteal'] as int? ?? 10,
        stealFadeOutMs: configJson['stealFadeOutMs'] as int? ?? 50,
        enableVirtualVoices: configJson['enableVirtualVoices'] as bool? ?? true,
        virtualThreshold: (configJson['virtualThreshold'] as num?)?.toDouble() ?? 0.01,
      ));
    }

    final statsJson = json['stats'] as Map<String, dynamic>?;
    if (statsJson != null) {
      _peakVoices = statsJson['peakVoices'] as int? ?? 0;
      _stealCount = statsJson['stealCount'] as int? ?? 0;
    }

    notifyListeners();
  }

  /// Clear all voices
  void clear() {
    releaseAllVoices();
    resetStats();
  }
}
