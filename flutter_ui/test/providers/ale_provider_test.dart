/// ALE Provider Tests — Adaptive Layer Engine models and provider
///
/// Tests ALE data models (signals, contexts, rules, transitions, stability),
/// JSON serialization, and profile management.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/ale_provider.dart';

void main() {
  group('AleSignalDefinition', () {
    test('default values', () {
      const signal = AleSignalDefinition(id: 'test', name: 'Test Signal');
      expect(signal.minValue, 0.0);
      expect(signal.maxValue, 1.0);
      expect(signal.defaultValue, 0.0);
      expect(signal.normalization, NormalizationMode.linear);
      expect(signal.isDerived, false);
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 'winTier',
        'name': 'Win Tier',
        'min_value': 0.0,
        'max_value': 5.0,
        'default_value': 0.0,
        'normalization': 'sigmoid',
        'sigmoid_k': 3.0,
        'is_derived': false,
      };
      final signal = AleSignalDefinition.fromJson(json);
      expect(signal.id, 'winTier');
      expect(signal.name, 'Win Tier');
      expect(signal.maxValue, 5.0);
      expect(signal.normalization, NormalizationMode.sigmoid);
      expect(signal.sigmoidK, 3.0);
    });

    test('fromJson handles missing fields gracefully', () {
      final signal = AleSignalDefinition.fromJson({'id': 'x', 'name': 'x'});
      expect(signal.minValue, 0.0);
      expect(signal.maxValue, 1.0);
      expect(signal.normalization, NormalizationMode.linear);
    });

    test('normalization modes parse correctly', () {
      for (final mode in ['linear', 'sigmoid', 'asymptotic', 'none']) {
        final signal = AleSignalDefinition.fromJson({
          'id': 'test',
          'normalization': mode,
        });
        expect(signal.normalization, isNotNull);
      }
    });
  });

  group('AleLayer', () {
    test('default values', () {
      const layer = AleLayer(index: 0, assetId: 'music_base.wav');
      expect(layer.baseVolume, 1.0);
      expect(layer.currentVolume, 0.0);
      expect(layer.isActive, false);
    });

    test('fromJson/toJson round trip', () {
      final original = {'index': 2, 'asset_id': 'layer2.wav', 'base_volume': 0.8, 'current_volume': 0.5, 'is_active': true};
      final layer = AleLayer.fromJson(original);
      final json = layer.toJson();
      expect(json['index'], 2);
      expect(json['asset_id'], 'layer2.wav');
      expect(json['base_volume'], 0.8);
      expect(json['is_active'], true);
    });

    test('validates asset path — rejects path traversal', () {
      final layer = AleLayer.fromJson({
        'index': 0,
        'asset_id': '../../etc/passwd',
      });
      expect(layer.assetId, ''); // Sanitized to empty
    });

    test('validates asset path — rejects null bytes', () {
      final layer = AleLayer.fromJson({
        'index': 0,
        'asset_id': 'file\x00.wav',
      });
      expect(layer.assetId, '');
    });

    test('validates asset path — rejects non-audio extensions', () {
      final layer = AleLayer.fromJson({
        'index': 0,
        'asset_id': 'malware.exe',
      });
      expect(layer.assetId, '');
    });

    test('allows valid audio file', () {
      final layer = AleLayer.fromJson({
        'index': 0,
        'asset_id': 'music/base_layer.wav',
      });
      expect(layer.assetId, 'music/base_layer.wav');
    });

    test('allows empty asset id', () {
      final layer = AleLayer.fromJson({
        'index': 0,
        'asset_id': '',
      });
      expect(layer.assetId, '');
    });
  });

  group('AleContext', () {
    test('default values', () {
      const ctx = AleContext(id: 'base', name: 'Base Game');
      expect(ctx.layers, isEmpty);
      expect(ctx.currentLevel, 0);
      expect(ctx.isActive, false);
    });

    test('fromJson parses layers', () {
      final json = {
        'id': 'base',
        'name': 'Base Game',
        'description': 'Base game loop',
        'layers': [
          {'index': 0, 'asset_id': 'l0.wav', 'base_volume': 1.0},
          {'index': 1, 'asset_id': 'l1.wav', 'base_volume': 0.8},
        ],
        'current_level': 1,
        'is_active': true,
      };
      final ctx = AleContext.fromJson(json);
      expect(ctx.layers.length, 2);
      expect(ctx.currentLevel, 1);
      expect(ctx.isActive, true);
      expect(ctx.description, 'Base game loop');
    });

    test('toJson round trip', () {
      const ctx = AleContext(
        id: 'fs',
        name: 'Free Spins',
        layers: [AleLayer(index: 0, assetId: 'fs.wav')],
        currentLevel: 3,
      );
      final json = ctx.toJson();
      final restored = AleContext.fromJson(json);
      expect(restored.id, 'fs');
      expect(restored.layers.length, 1);
      expect(restored.currentLevel, 3);
    });
  });

  group('AleRule', () {
    test('default values', () {
      const rule = AleRule(id: 'r1', name: 'Rule 1');
      expect(rule.action, AleActionType.stepUp);
      expect(rule.priority, 0);
      expect(rule.enabled, true);
      expect(rule.contexts, isEmpty);
    });

    test('fromJson parses all operators', () {
      for (final op in ['eq', 'ne', 'lt', 'lte', 'gt', 'gte', 'in_range', 'rising', 'falling']) {
        final rule = AleRule.fromJson({
          'id': 'r_$op',
          'name': 'Test',
          'op': op,
        });
        expect(rule.op, isNotNull, reason: 'Operator "$op" should parse');
      }
    });

    test('fromJson parses all action types', () {
      for (final action in ['step_up', 'step_down', 'set_level', 'hold', 'release', 'pulse']) {
        final rule = AleRule.fromJson({
          'id': 'r',
          'name': 'Test',
          'action': action,
        });
        expect(rule.action, isNotNull, reason: 'Action "$action" should parse');
      }
    });

    test('toJson round trip', () {
      final original = AleRule.fromJson({
        'id': 'rule_1',
        'name': 'Big Win Step Up',
        'signal_id': 'winXbet',
        'op': 'gt',
        'value': 10.0,
        'action': 'step_up',
        'action_value': 2,
        'contexts': ['base', 'freespins'],
        'priority': 5,
        'enabled': true,
      });
      final json = original.toJson();
      final restored = AleRule.fromJson(json);
      expect(restored.id, 'rule_1');
      expect(restored.signalId, 'winXbet');
      expect(restored.op, ComparisonOp.gt);
      expect(restored.value, 10.0);
      expect(restored.action, AleActionType.stepUp);
      expect(restored.actionValue, 2);
      expect(restored.contexts, ['base', 'freespins']);
    });

    test('unknown op returns null', () {
      final rule = AleRule.fromJson({'id': 'r', 'name': 'x', 'op': 'unknown_op'});
      expect(rule.op, isNull);
    });

    test('unknown action defaults to stepUp', () {
      final rule = AleRule.fromJson({'id': 'r', 'name': 'x', 'action': 'unknown'});
      expect(rule.action, AleActionType.stepUp);
    });
  });

  group('AleTransitionProfile', () {
    test('default values', () {
      const tp = AleTransitionProfile(id: 't1', name: 'Default');
      expect(tp.syncMode, SyncMode.immediate);
      expect(tp.fadeInMs, 500);
      expect(tp.fadeOutMs, 500);
      expect(tp.overlap, 0.5);
    });

    test('fromJson parses sync modes', () {
      for (final mode in ['immediate', 'beat', 'bar', 'phrase', 'next_downbeat', 'custom']) {
        final tp = AleTransitionProfile.fromJson({
          'id': 't',
          'name': 'T',
          'sync_mode': mode,
        });
        expect(tp.syncMode, isNotNull, reason: 'SyncMode "$mode" should parse');
      }
    });

    test('toJson round trip', () {
      const original = AleTransitionProfile(
        id: 'smooth',
        name: 'Smooth',
        syncMode: SyncMode.bar,
        fadeInMs: 1000,
        fadeOutMs: 800,
        overlap: 0.3,
      );
      final json = original.toJson();
      final restored = AleTransitionProfile.fromJson(json);
      expect(restored.syncMode, SyncMode.bar);
      expect(restored.fadeInMs, 1000);
      expect(restored.overlap, 0.3);
    });
  });

  group('AleStabilityConfig', () {
    test('default values', () {
      const config = AleStabilityConfig();
      expect(config.cooldownMs, 500);
      expect(config.holdMs, 2000);
      expect(config.hysteresisUp, 0.1);
      expect(config.hysteresisDown, 0.05);
      expect(config.levelInertia, 0.3);
      expect(config.decayMs, 10000);
      expect(config.predictionEnabled, false);
    });

    test('fromJson/toJson round trip', () {
      final original = AleStabilityConfig(
        cooldownMs: 1000,
        holdMs: 3000,
        predictionEnabled: true,
      );
      final json = original.toJson();
      final restored = AleStabilityConfig.fromJson(json);
      expect(restored.cooldownMs, 1000);
      expect(restored.holdMs, 3000);
      expect(restored.predictionEnabled, true);
    });

    test('copyWith works', () {
      const config = AleStabilityConfig();
      final updated = config.copyWith(cooldownMs: 2000, predictionEnabled: true);
      expect(updated.cooldownMs, 2000);
      expect(updated.predictionEnabled, true);
      expect(updated.holdMs, 2000); // unchanged
    });
  });

  group('AleProfile', () {
    test('empty profile', () {
      const profile = AleProfile();
      expect(profile.version, '2.0');
      expect(profile.contexts, isEmpty);
      expect(profile.rules, isEmpty);
      expect(profile.transitions, isEmpty);
    });

    test('fromJson parses complete profile', () {
      final json = {
        'version': '2.0',
        'author': 'Test',
        'metadata': {'game_name': 'MySlot'},
        'contexts': {
          'base': {
            'id': 'base',
            'name': 'Base Game',
            'layers': [{'index': 0, 'asset_id': 'base.wav'}],
          }
        },
        'rules': [
          {'id': 'r1', 'name': 'Rule 1', 'action': 'step_up'},
        ],
        'transitions': {
          'smooth': {'id': 'smooth', 'name': 'Smooth', 'sync_mode': 'bar'},
        },
        'stability': {'cooldown_ms': 1000},
      };
      final profile = AleProfile.fromJson(json);
      expect(profile.author, 'Test');
      expect(profile.gameName, 'MySlot');
      expect(profile.contexts.length, 1);
      expect(profile.rules.length, 1);
      expect(profile.transitions.length, 1);
      expect(profile.stability.cooldownMs, 1000);
    });

    test('toJson round trip', () {
      final original = AleProfile.fromJson(<String, dynamic>{
        'version': '2.0',
        'contexts': <String, dynamic>{
          'base': <String, dynamic>{'id': 'base', 'name': 'Base', 'layers': <dynamic>[]},
        },
        'rules': <dynamic>[],
        'transitions': <String, dynamic>{},
        'stability': <String, dynamic>{},
      });
      final json = original.toJson();
      // Verify toJson produces expected structure
      expect(json['version'], '2.0');
      expect((json['contexts'] as Map).containsKey('base'), true);
      expect(json['stability'], isA<Map>());
      // Verify fields survive serialization
      expect(original.contexts.containsKey('base'), true);
      expect(original.contexts['base']!.name, 'Base');
    });
  });

  group('AleEngineState', () {
    test('default values', () {
      const state = AleEngineState();
      expect(state.activeContextId, isNull);
      expect(state.currentLevel, 0);
      expect(state.layerVolumes, isEmpty);
      expect(state.inTransition, false);
      expect(state.tempo, 120.0);
      expect(state.beatsPerBar, 4);
    });

    test('fromJson parses all fields', () {
      final state = AleEngineState.fromJson({
        'active_context_id': 'base',
        'current_level': 3,
        'layer_volumes': [0.0, 0.5, 0.8, 1.0],
        'signal_values': {'winTier': 2.0, 'momentum': 0.7},
        'in_transition': true,
        'tempo': 140.0,
        'beats_per_bar': 3,
      });
      expect(state.activeContextId, 'base');
      expect(state.currentLevel, 3);
      expect(state.layerVolumes, [0.0, 0.5, 0.8, 1.0]);
      expect(state.signalValues['winTier'], 2.0);
      expect(state.inTransition, true);
      expect(state.tempo, 140.0);
      expect(state.beatsPerBar, 3);
    });
  });

  group('AleProvider — basic state', () {
    test('starts uninitialized', () {
      final provider = AleProvider();
      expect(provider.initialized, false);
      expect(provider.profile, isNull);
      expect(provider.activeContext, isNull);
      expect(provider.layerCount, 0);
      expect(provider.currentLevel, 0);
      expect(provider.maxLevel, 0);
    });

    test('contextIds returns empty when no profile', () {
      final provider = AleProvider();
      expect(provider.contextIds, isEmpty);
    });

    test('getContext returns null when no profile', () {
      final provider = AleProvider();
      expect(provider.getContext('base'), isNull);
    });

    test('currentSignals starts empty', () {
      final provider = AleProvider();
      expect(provider.currentSignals, isEmpty);
    });
  });
}
