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
///
/// Note: This is a Dart-only voice tracking system. Actual audio playback
/// is handled by AudioPlaybackService which communicates with the Rust engine.

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';

/// Provider for managing voice pool polyphony
class VoicePoolProvider extends ChangeNotifier {
  /// Internal voice pool
  late VoicePool _voicePool;

  /// Peak voice count (for statistics)
  int _peakVoices = 0;

  /// Total steal count
  int _stealCount = 0;

  VoicePoolProvider({
    VoicePoolConfig config = const VoicePoolConfig(),
  }) {
    _voicePool = VoicePool(config: config);
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

  /// Get pool statistics
  VoicePoolStats getStats() {
    return VoicePoolStats(
      activeVoices: _voicePool.activeCount,
      virtualVoices: _voicePool.virtualCount,
      maxVoices: config.maxVoices,
      peakVoices: _peakVoices,
      stealCount: _stealCount,
    );
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
