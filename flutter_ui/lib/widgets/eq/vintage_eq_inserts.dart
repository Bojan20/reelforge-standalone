// Vintage EQ Insert Wrappers
//
// These widgets wrap the standalone EQ widgets and connect them
// to MixerDSPProvider for full FFI integration with Rust engine.
//
// Usage:
//   PultecInsert(busId: 'sfx', insertId: 'insert_123')
//   Api550Insert(busId: 'music', insertId: 'insert_456')
//   Neve1073Insert(busId: 'voice', insertId: 'insert_789')

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/mixer_dsp_provider.dart';
import 'pultec_eq.dart';
import 'api550_eq.dart';
import 'neve1073_eq.dart';

// ============ Pultec Insert Wrapper ============

/// Pultec EQP-1A connected to MixerDSPProvider
class PultecInsert extends StatelessWidget {
  final String busId;
  final String insertId;
  final double? vuLevel;

  const PultecInsert({
    super.key,
    required this.busId,
    required this.insertId,
    this.vuLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerDSPProvider>(
      builder: (context, provider, _) {
        // Get current insert state from provider
        final bus = provider.getBus(busId);
        final insert = bus?.inserts.where((i) => i.id == insertId).firstOrNull;

        if (insert == null) {
          return const Center(child: Text('Insert not found'));
        }

        // Convert provider params to PultecParams
        // Note: PultecParams has more params than Rust supports
        // We only sync the 4 core params to engine
        final params = PultecParams(
          lowBoost: insert.params['lowBoost'] ?? 0,
          lowAtten: insert.params['lowAtten'] ?? 0,
          highBoost: insert.params['highBoost'] ?? 0,
          highAtten: insert.params['highAtten'] ?? 0,
          bypass: insert.bypassed,
        );

        return PultecEq(
          initialParams: params,
          vuLevel: vuLevel,
          onParamsChanged: (newParams) {
            // Sync core parameters to provider (which syncs to Rust engine)
            provider.updateInsertParams(busId, insertId, {
              'lowBoost': newParams.lowBoost,
              'lowAtten': newParams.lowAtten,
              'highBoost': newParams.highBoost,
              'highAtten': newParams.highAtten,
            });

            // Handle bypass separately
            if (newParams.bypass != insert.bypassed) {
              provider.toggleBypass(busId, insertId);
            }
          },
        );
      },
    );
  }
}

// ============ API 550A Insert Wrapper ============

/// API 550A connected to MixerDSPProvider
class Api550Insert extends StatelessWidget {
  final String busId;
  final String insertId;
  final bool? signalPresent;

  const Api550Insert({
    super.key,
    required this.busId,
    required this.insertId,
    this.signalPresent,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerDSPProvider>(
      builder: (context, provider, _) {
        final bus = provider.getBus(busId);
        final insert = bus?.inserts.where((i) => i.id == insertId).firstOrNull;

        if (insert == null) {
          return const Center(child: Text('Insert not found'));
        }

        // Convert provider params to Api550Params
        // Note: Api550Params has more params (freq selection) than Rust gain-only
        final params = Api550Params(
          lowGain: insert.params['lowGain'] ?? 0,
          midGain: insert.params['midGain'] ?? 0,
          highGain: insert.params['highGain'] ?? 0,
          bypass: insert.bypassed,
        );

        return Api550Eq(
          initialParams: params,
          signalPresent: signalPresent,
          onParamsChanged: (newParams) {
            provider.updateInsertParams(busId, insertId, {
              'lowGain': newParams.lowGain,
              'midGain': newParams.midGain,
              'highGain': newParams.highGain,
            });

            if (newParams.bypass != insert.bypassed) {
              provider.toggleBypass(busId, insertId);
            }
          },
        );
      },
    );
  }
}

// ============ Neve 1073 Insert Wrapper ============

/// Neve 1073 connected to MixerDSPProvider
class Neve1073Insert extends StatelessWidget {
  final String busId;
  final String insertId;
  final double? inputLevel;
  final double? outputLevelMeter;

  const Neve1073Insert({
    super.key,
    required this.busId,
    required this.insertId,
    this.inputLevel,
    this.outputLevelMeter,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerDSPProvider>(
      builder: (context, provider, _) {
        final bus = provider.getBus(busId);
        final insert = bus?.inserts.where((i) => i.id == insertId).firstOrNull;

        if (insert == null) {
          return const Center(child: Text('Insert not found'));
        }

        // Convert provider params to Neve1073Params
        // Rust wrapper: 0=hpEnabled, 1=lowGain, 2=highGain
        final params = Neve1073Params(
          hpfEnabled: (insert.params['hpEnabled'] ?? 0) > 0.5,
          lfGain: insert.params['lowGain'] ?? 0,
          hfGain: insert.params['highGain'] ?? 0,
          eqEnabled: !insert.bypassed,
        );

        return Neve1073Eq(
          initialParams: params,
          inputLevel: inputLevel,
          outputLevelMeter: outputLevelMeter,
          onParamsChanged: (newParams) {
            provider.updateInsertParams(busId, insertId, {
              'hpEnabled': newParams.hpfEnabled ? 1.0 : 0.0,
              'lowGain': newParams.lfGain,
              'highGain': newParams.hfGain,
            });

            // eqEnabled is inverse of bypassed
            if (newParams.eqEnabled == insert.bypassed) {
              provider.toggleBypass(busId, insertId);
            }
          },
        );
      },
    );
  }
}

// ============ Generic Insert Widget Factory ============

/// Factory that creates the appropriate EQ insert widget based on plugin ID
class VintageEqInsertFactory {
  /// Create Pultec insert with optional VU meter level
  static Widget createPultecInsert({
    required String busId,
    required String insertId,
    double? vuLevel,
  }) {
    return PultecInsert(
      busId: busId,
      insertId: insertId,
      vuLevel: vuLevel,
    );
  }

  /// Create API 550A insert with optional signal present indicator
  static Widget createApi550Insert({
    required String busId,
    required String insertId,
    bool? signalPresent,
  }) {
    return Api550Insert(
      busId: busId,
      insertId: insertId,
      signalPresent: signalPresent,
    );
  }

  /// Create Neve 1073 insert with optional metering
  static Widget createNeve1073Insert({
    required String busId,
    required String insertId,
    double? inputLevel,
    double? outputLevelMeter,
  }) {
    return Neve1073Insert(
      busId: busId,
      insertId: insertId,
      inputLevel: inputLevel,
      outputLevelMeter: outputLevelMeter,
    );
  }

  /// Create insert widget by plugin ID (without metering)
  static Widget? createInsert({
    required String pluginId,
    required String busId,
    required String insertId,
  }) {
    switch (pluginId) {
      case 'rf-pultec':
        return PultecInsert(busId: busId, insertId: insertId);
      case 'rf-api550':
        return Api550Insert(busId: busId, insertId: insertId);
      case 'rf-neve1073':
        return Neve1073Insert(busId: busId, insertId: insertId);
      default:
        return null;
    }
  }

  /// Check if plugin ID is a vintage EQ
  static bool isVintageEq(String pluginId) {
    return pluginId == 'rf-pultec' ||
        pluginId == 'rf-api550' ||
        pluginId == 'rf-neve1073';
  }
}
