/// RTPC Auto Configurator
///
/// Configures Real-Time Parameter Control (RTPC) definitions from template.
/// Sets up winMultiplier and other game-driven parameters with curves.
///
/// P3-12: Template Gallery
library;

import 'package:flutter/foundation.dart';

import '../../models/middleware_models.dart';
import '../../models/template_models.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../service_locator.dart';

/// Configures RTPC system from template
class RtpcAutoConfigurator {
  // Track created RTPC IDs for updating
  final Map<String, int> _rtpcIdMap = {};

  /// Configure all RTPC definitions from template
  ///
  /// Returns the number of RTPCs configured
  int configureAll(BuiltTemplate template) {
    final rtpcProvider = sl<RtpcSystemProvider>();
    int count = 0;

    // Clear existing RTPC definitions first
    rtpcProvider.clear();
    _rtpcIdMap.clear();

    // Add the winMultiplier RTPC from template
    final winRtpc = template.source.winMultiplierRtpc;
    try {
      final volumeCurve = _buildCurve(winRtpc.volumeCurve);

      final rtpcDef = RtpcDefinition(
        id: count,
        name: winRtpc.name,
        min: winRtpc.min,
        max: winRtpc.max,
        defaultValue: winRtpc.defaultValue,
        slewRate: 10.0, // 100ms interpolation
        curve: volumeCurve,
      );

      rtpcProvider.registerRtpc(rtpcDef);
      _rtpcIdMap['winMultiplier'] = count;
      count++;
    } catch (e) {
      debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add winMultiplier RTPC: $e');
    }

    // Add additional default RTPCs
    count += _addDefaultRtpcs(rtpcProvider, template);

    // Configure RTPC bindings
    _configureDefaultBindings(rtpcProvider);

    debugPrint('[RtpcAutoConfigurator] Configured $count RTPC definitions');
    return count;
  }

  /// Build RtpcCurve from template curve points
  RtpcCurve? _buildCurve(List<TemplateRtpcPoint> points) {
    if (points.isEmpty) return null;

    return RtpcCurve(
      points: points.map((p) => RtpcCurvePoint(
        x: p.x,
        y: p.y,
        shape: RtpcCurveShape.linear,
      )).toList(),
    );
  }

  /// Add default RTPC definitions based on template win tiers
  int _addDefaultRtpcs(RtpcSystemProvider provider, BuiltTemplate template) {
    int count = 0;
    int nextId = 0;

    // winMultiplier RTPC (0.0 = no win, 1.0 = max configured win tier)
    try {
      final curvePoints = <RtpcCurvePoint>[];

      // Add curve points based on win tiers
      final winTiers = template.source.winTiers;
      if (winTiers.isNotEmpty) {
        // Sort tiers by threshold
        final sortedTiers = List<WinTierConfig>.from(winTiers)
          ..sort((a, b) => a.threshold.compareTo(b.threshold));

        final maxThreshold = sortedTiers.last.threshold;

        // Create normalized curve points
        curvePoints.add(const RtpcCurvePoint(x: 0.0, y: 0.0));
        for (int i = 0; i < sortedTiers.length; i++) {
          final tier = sortedTiers[i];
          final normalizedInput = tier.threshold / maxThreshold;
          final normalizedOutput = (i + 1) / sortedTiers.length;
          curvePoints.add(RtpcCurvePoint(x: normalizedInput, y: normalizedOutput));
        }
      } else {
        // Default linear curve
        curvePoints.addAll(const [
          RtpcCurvePoint(x: 0.0, y: 0.0),
          RtpcCurvePoint(x: 0.5, y: 0.5),
          RtpcCurvePoint(x: 1.0, y: 1.0),
        ]);
      }

      provider.registerRtpc(RtpcDefinition(
        id: nextId,
        name: 'Win Multiplier',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.0,
        slewRate: 10.0, // 100ms interpolation
        curve: RtpcCurve(points: curvePoints),
      ));
      _rtpcIdMap['winMultiplier'] = nextId;
      nextId++;
      count++;
    } catch (e) {
      debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add winMultiplier RTPC: $e');
    }

    // spinEnergy RTPC (builds during spin, resets at result)
    try {
      provider.registerRtpc(RtpcDefinition(
        id: nextId,
        name: 'Spin Energy',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.0,
        slewRate: 20.0, // 50ms interpolation
        curve: const RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: 0.0),
          RtpcCurvePoint(x: 1.0, y: 1.0),
        ]),
      ));
      _rtpcIdMap['spinEnergy'] = nextId;
      nextId++;
      count++;
    } catch (e) {
      debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add spinEnergy RTPC: $e');
    }

    // cascadeDepth RTPC (for cascade/tumble games)
    if (template.source.modules.any((f) => f.type == FeatureModuleType.cascade)) {
      try {
        provider.registerRtpc(RtpcDefinition(
          id: nextId,
          name: 'Cascade Depth',
          min: 0.0,
          max: 10.0,
          defaultValue: 0.0,
          slewRate: 33.0, // 30ms interpolation
          curve: RtpcCurve(points: [
            const RtpcCurvePoint(x: 0.0, y: 0.0),
            const RtpcCurvePoint(x: 0.3, y: 0.1),
            const RtpcCurvePoint(x: 0.5, y: 0.25),
            const RtpcCurvePoint(x: 0.7, y: 0.5),
            const RtpcCurvePoint(x: 1.0, y: 1.0),
          ]),
        ));
        _rtpcIdMap['cascadeDepth'] = nextId;
        nextId++;
        count++;
      } catch (e) {
        debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add cascadeDepth RTPC: $e');
      }
    }

    // featureProgress RTPC (0-1 progress through feature)
    if (template.source.modules.isNotEmpty) {
      try {
        provider.registerRtpc(RtpcDefinition(
          id: nextId,
          name: 'Feature Progress',
          min: 0.0,
          max: 1.0,
          defaultValue: 0.0,
          slewRate: 5.0, // 200ms interpolation
          curve: RtpcCurve(points: [
            const RtpcCurvePoint(x: 0.0, y: 0.0),
            const RtpcCurvePoint(x: 0.25, y: 0.1),
            const RtpcCurvePoint(x: 0.5, y: 0.5),
            const RtpcCurvePoint(x: 0.75, y: 0.9),
            const RtpcCurvePoint(x: 1.0, y: 1.0),
          ]),
        ));
        _rtpcIdMap['featureProgress'] = nextId;
        nextId++;
        count++;
      } catch (e) {
        debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add featureProgress RTPC: $e');
      }
    }

    // anticipationLevel RTPC (for near-miss/anticipation)
    try {
      provider.registerRtpc(RtpcDefinition(
        id: nextId,
        name: 'Anticipation Level',
        min: 0.0,
        max: 4.0, // L1-L4 tension levels
        defaultValue: 0.0,
        slewRate: 6.67, // 150ms interpolation
        curve: const RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: 0.0),
          RtpcCurvePoint(x: 0.25, y: 0.25),
          RtpcCurvePoint(x: 0.5, y: 0.5),
          RtpcCurvePoint(x: 0.75, y: 0.75),
          RtpcCurvePoint(x: 1.0, y: 1.0),
        ]),
      ));
      _rtpcIdMap['anticipationLevel'] = nextId;
      nextId++;
      count++;
    } catch (e) {
      debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add anticipationLevel RTPC: $e');
    }

    // rollupSpeed RTPC (controls rollup tick rate)
    try {
      provider.registerRtpc(RtpcDefinition(
        id: nextId,
        name: 'Rollup Speed',
        min: 0.5,
        max: 2.0, // 0.5x to 2x speed
        defaultValue: 1.0,
        slewRate: 20.0, // 50ms interpolation
        curve: const RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: 0.5),
          RtpcCurvePoint(x: 0.5, y: 1.0),
          RtpcCurvePoint(x: 1.0, y: 2.0),
        ]),
      ));
      _rtpcIdMap['rollupSpeed'] = nextId;
      nextId++;
      count++;
    } catch (e) {
      debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to add rollupSpeed RTPC: $e');
    }

    return count;
  }

  /// Configure default RTPC bindings for audio parameters
  void _configureDefaultBindings(RtpcSystemProvider provider) {
    // Bind winMultiplier to music bus volume (bus ID 1 = music)
    final winMultiplierId = _rtpcIdMap['winMultiplier'];
    if (winMultiplierId != null) {
      try {
        provider.createBinding(
          winMultiplierId,
          RtpcTargetParameter.busVolume,
          busId: 1, // Music bus
        );
      } catch (e) {
        debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to bind winMultiplier to music: $e');
      }
    }

    // Bind spinEnergy to ambience bus volume (bus ID 4 = ambience)
    final spinEnergyId = _rtpcIdMap['spinEnergy'];
    if (spinEnergyId != null) {
      try {
        provider.createBinding(
          spinEnergyId,
          RtpcTargetParameter.busVolume,
          busId: 4, // Ambience bus
        );
      } catch (e) {
        debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to bind spinEnergy to ambience: $e');
      }
    }

    // Bind anticipationLevel to low-pass filter on music bus
    final anticipationId = _rtpcIdMap['anticipationLevel'];
    if (anticipationId != null) {
      try {
        provider.createBinding(
          anticipationId,
          RtpcTargetParameter.lowPassFilter,
          busId: 1, // Music bus
        );
      } catch (e) {
        debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to bind anticipationLevel: $e');
      }
    }

    // Bind cascadeDepth to pitch (for cascade events)
    final cascadeId = _rtpcIdMap['cascadeDepth'];
    if (cascadeId != null) {
      try {
        provider.createBinding(
          cascadeId,
          RtpcTargetParameter.pitch,
        );
      } catch (e) {
        debugPrint('[RtpcAutoConfigurator] ⚠️ Failed to bind cascadeDepth: $e');
      }
    }
  }

  /// Get RTPC ID by name (for external updates)
  int? getRtpcId(String name) => _rtpcIdMap[name];
}
