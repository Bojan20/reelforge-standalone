/// FluxForge RTPC Modulation Service
///
/// Real-time parameter control for audio events.
/// Connects MiddlewareProvider's RTPC system to EventRegistry.
///
/// Usage:
/// 1. Register event for RTPC modulation
/// 2. When event triggers, RTPC values are applied to volume/pitch/filter
/// 3. Bindings define how RTPC affects each parameter
///
/// Supported targets:
/// - Volume (0.0-1.0)
/// - Pitch (-24 to +24 semitones)
/// - LPF (20Hz - 20kHz)
/// - HPF (20Hz - 20kHz)
/// - Pan (-1.0 to +1.0)
/// - PlaybackRate (0.25x to 4.0x for rollup speed modulation)
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';
import '../providers/middleware_provider.dart';

/// Service for RTPC-based audio modulation
class RtpcModulationService {
  static final RtpcModulationService _instance = RtpcModulationService._();
  static RtpcModulationService get instance => _instance;

  RtpcModulationService._();

  // Reference to middleware provider (set during init)
  MiddlewareProvider? _middleware;

  // Event-to-RTPC mappings (eventId → list of RTPC bindings)
  final Map<String, List<_EventRtpcMapping>> _eventMappings = {};

  /// Initialize with middleware provider reference
  void init(MiddlewareProvider middleware) {
    _middleware = middleware;
  }

  /// Register RTPC modulation for an event
  void registerEventModulation({
    required String eventId,
    required int rtpcId,
    required RtpcTargetParameter target,
    double minOutput = 0.0,
    double maxOutput = 1.0,
  }) {
    final mapping = _EventRtpcMapping(
      rtpcId: rtpcId,
      target: target,
      minOutput: minOutput,
      maxOutput: maxOutput,
    );

    _eventMappings.putIfAbsent(eventId, () => []);
    _eventMappings[eventId]!.add(mapping);

  }

  /// Unregister all RTPC modulation for an event
  void unregisterEventModulation(String eventId) {
    _eventMappings.remove(eventId);
  }

  /// Get modulated audio parameters for an event
  /// Returns map of target → value, or empty if no modulation
  Map<RtpcTargetParameter, double> getModulatedParameters(String eventId) {
    final result = <RtpcTargetParameter, double>{};

    final mappings = _eventMappings[eventId];
    if (mappings == null || mappings.isEmpty) return result;
    if (_middleware == null) return result;

    for (final mapping in mappings) {
      // Get current RTPC value from middleware
      final rtpcDef = _middleware!.getRtpc(mapping.rtpcId);
      if (rtpcDef == null) continue;

      // Normalize RTPC value (0-1)
      final normalizedRtpc = rtpcDef.normalizedValue;

      // Map to output range
      final outputValue = _lerp(mapping.minOutput, mapping.maxOutput, normalizedRtpc);
      result[mapping.target] = outputValue;
    }

    return result;
  }

  /// Get modulated volume (1.0 = no change)
  double getModulatedVolume(String eventId, double baseVolume) {
    final params = getModulatedParameters(eventId);
    final volumeMod = params[RtpcTargetParameter.volume];
    if (volumeMod == null) return baseVolume;
    return baseVolume * volumeMod;
  }

  /// Get modulated pitch in semitones (0 = no change)
  double getModulatedPitch(String eventId) {
    final params = getModulatedParameters(eventId);
    return params[RtpcTargetParameter.pitch] ?? 0.0;
  }

  /// Get modulated LPF in Hz (20000 = no filter)
  double getModulatedLPF(String eventId) {
    final params = getModulatedParameters(eventId);
    return params[RtpcTargetParameter.lowPassFilter] ?? 20000.0;
  }

  /// Get modulated HPF in Hz (20 = no filter)
  double getModulatedHPF(String eventId) {
    final params = getModulatedParameters(eventId);
    return params[RtpcTargetParameter.highPassFilter] ?? 20.0;
  }

  /// Get modulated pan (-1 to +1, 0 = center)
  double getModulatedPan(String eventId) {
    final params = getModulatedParameters(eventId);
    return params[RtpcTargetParameter.pan] ?? 0.0;
  }

  /// Get modulated playback rate (1.0 = normal, 2.0 = 2x speed, 0.5 = half speed)
  /// Used for dynamic rollup speed, cascade timing, etc.
  double getModulatedPlaybackRate(String eventId) {
    final params = getModulatedParameters(eventId);
    return params[RtpcTargetParameter.playbackRate] ?? 1.0;
  }

  /// Get rollup speed multiplier from Rollup_Speed RTPC (global, not per-event)
  /// Returns 1.0 if no RTPC binding or middleware not available
  /// Higher value = faster rollup (shorter delay between ticks)
  double getRollupSpeedMultiplier() {
    if (_middleware == null) return 1.0;

    // Find Rollup_Speed RTPC (ID 106 per SlotRtpcIds)
    const rollupSpeedRtpcId = 106; // SlotRtpcIds.rollupSpeed
    final rtpcDef = _middleware!.getRtpc(rollupSpeedRtpcId);
    if (rtpcDef == null) return 1.0;

    // Rollup_Speed range is typically 0.0-1.0 where 1.0 = fastest
    // Map to multiplier: 0.0 → 0.25x (slow), 0.5 → 1.0x (normal), 1.0 → 4.0x (fast)
    // Using exponential curve for perceptual linearity
    final normalized = rtpcDef.normalizedValue.clamp(0.0, 1.0);
    // Formula: 0.25 * 16^normalized = 0.25 at 0, 1.0 at 0.5, 4.0 at 1.0
    return 0.25 * math.pow(16.0, normalized);
  }

  /// P1.2: Get rollup pitch offset based on progress (0.0 to 1.0)
  /// Returns pitch in semitones: 0 at start, up to +12 at end (one octave)
  /// Uses exponential curve for dramatic build-up towards the end
  /// Called from EventRegistry when playing ROLLUP_TICK with progress context
  double getRollupPitch(double progress) {
    // Clamp progress to 0-1 range
    final p = progress.clamp(0.0, 1.0);

    // Exponential curve: rises slowly at first, dramatically at end
    // p^2 curve: at 50% progress, pitch is only 25% of max
    // at 75% progress, pitch is 56% of max
    // at 90% progress, pitch is 81% of max
    final curve = p * p;

    // Max pitch: +12 semitones (one octave up)
    // Can be reduced for subtler effect
    const maxPitchSemitones = 8.0; // +8 semitones for natural sound

    return curve * maxPitchSemitones;
  }

  /// P1.2: Get rollup pitch as playback rate multiplier
  /// More compatible with existing playback API than semitones
  /// Returns: 1.0 at start, up to ~1.5 at end
  double getRollupPitchAsRate(double progress) {
    final semitones = getRollupPitch(progress);
    // Convert semitones to rate: 2^(semitones/12)
    return math.pow(2.0, semitones / 12.0).toDouble();
  }

  /// P1.2: Get rollup volume escalation based on progress
  /// Alternative to pitch when engine doesn't support pitch shifting
  /// Volume increases subtly towards the end for excitement
  /// Returns: 0.85 at start, 1.0 at 50%, 1.15 at end
  double getRollupVolumeEscalation(double progress) {
    final p = progress.clamp(0.0, 1.0);
    // Linear escalation from 0.85 to 1.15
    return 0.85 + (p * 0.30);
  }

  /// P1.2: Get combined rollup modulation (volume + speed adjustment)
  /// Returns multipliers for both volume and tick interval
  /// Usage: Apply volume multiplier, use speed to adjust tick interval
  ({double volume, double speedMultiplier}) getRollupModulation(double progress) {
    return (
      volume: getRollupVolumeEscalation(progress),
      speedMultiplier: 1.0 + (progress * 0.5), // 1.0x → 1.5x speed
    );
  }

  /// P0.4: Get cascade speed multiplier from Cascade_Speed RTPC (global, not per-event)
  /// Returns 1.0 if no RTPC binding or middleware not available
  /// Higher value = faster cascade (shorter delay between steps)
  double getCascadeSpeedMultiplier() {
    if (_middleware == null) return 1.0;

    // Find Cascade_Speed RTPC (ID 107 per SlotRtpcIds)
    const cascadeSpeedRtpcId = 107; // SlotRtpcIds.cascadeSpeed
    final rtpcDef = _middleware!.getRtpc(cascadeSpeedRtpcId);
    if (rtpcDef == null) return 1.0;

    // Cascade_Speed range is typically 0.0-1.0 where 1.0 = fastest
    // Map to multiplier: 0.0 → 0.5x (slow), 0.5 → 1.0x (normal), 1.0 → 2.0x (fast)
    // Using exponential curve for perceptual linearity
    final normalized = rtpcDef.normalizedValue.clamp(0.0, 1.0);
    // Formula: 0.5 * 4^normalized = 0.5 at 0, 1.0 at 0.5, 2.0 at 1.0
    return 0.5 * math.pow(4.0, normalized);
  }

  /// Linear interpolation
  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Get count of registered event mappings (for debugging)
  int get mappingCount => _eventMappings.length;

  /// Check if event has RTPC mappings
  bool hasMapping(String eventId) => _eventMappings.containsKey(eventId);

  /// Clear all mappings
  void clear() {
    _eventMappings.clear();
  }
}

/// Internal mapping of RTPC to event parameter
class _EventRtpcMapping {
  final int rtpcId;
  final RtpcTargetParameter target;
  final double minOutput;
  final double maxOutput;

  const _EventRtpcMapping({
    required this.rtpcId,
    required this.target,
    required this.minOutput,
    required this.maxOutput,
  });
}
