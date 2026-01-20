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
    debugPrint('[RtpcModulation] Initialized with MiddlewareProvider');
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

    debugPrint('[RtpcModulation] Registered: event=$eventId, rtpc=$rtpcId, target=$target');
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
