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
library;

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
