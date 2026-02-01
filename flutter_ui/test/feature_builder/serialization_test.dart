// ============================================================================
// FluxForge Studio — Feature Builder Serialization Tests
// ============================================================================
// P13.8.8: Unit tests for preset serialization in Feature Builder.
// Tests verify that presets can be saved, loaded, and migrated correctly.
// ============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/feature_builder/feature_preset.dart';
import 'package:fluxforge_ui/blocks/anticipation_block.dart';
import 'package:fluxforge_ui/blocks/wild_features_block.dart';
import 'package:fluxforge_ui/blocks/game_core_block.dart';
import 'package:fluxforge_ui/blocks/grid_block.dart';
import 'package:fluxforge_ui/blocks/free_spins_block.dart';

void main() {
  group('FeaturePreset toJson', () {
    test('serializes preset to JSON correctly', () {
      final preset = FeaturePreset(
        id: 'test_preset_001',
        name: 'Test Preset',
        description: 'A test preset for unit testing',
        category: PresetCategory.video,
        tags: ['test', 'unit'],
        blocks: {
          'game_core': const BlockPresetData(
            isEnabled: true,
            options: {'payModel': 'lines', 'volatility': 'medium'},
          ),
          'grid': const BlockPresetData(
            isEnabled: true,
            options: {'reelCount': 5, 'rowCount': 3},
          ),
          'free_spins': const BlockPresetData(
            isEnabled: true,
            options: {'baseSpinsCount': 10, 'hasMultiplier': true},
          ),
        },
      );

      final json = preset.toJson();

      expect(json['id'], 'test_preset_001');
      expect(json['name'], 'Test Preset');
      expect(json['description'], 'A test preset for unit testing');
      expect(json['category'], 'video');
      expect(json['tags'], ['test', 'unit']);
      expect(json['blocks'], isA<Map>());
      expect(json['blocks']['game_core']['isEnabled'], true);
      expect(json['blocks']['grid']['options']['reelCount'], 5);
    });

    test('serializes to JSON string with pretty print', () {
      final preset = FeaturePreset(
        id: 'test_001',
        name: 'Simple Test',
        category: PresetCategory.classic,
        blocks: const {},
      );

      final jsonString = preset.toJsonString(pretty: true);

      expect(jsonString.contains('\n'), isTrue);
      expect(jsonString.contains('  '), isTrue);
    });
  });

  group('FeaturePreset fromJson', () {
    test('deserializes preset from JSON correctly', () {
      final json = {
        'id': 'loaded_preset_002',
        'name': 'Loaded Preset',
        'description': 'Loaded from JSON',
        'category': 'megaways',
        'schemaVersion': '1.0.0',
        'createdAt': '2026-02-01T12:00:00.000Z',
        'modifiedAt': '2026-02-01T14:30:00.000Z',
        'author': 'Test Author',
        'tags': ['loaded', 'json'],
        'blocks': {
          'game_core': {
            'isEnabled': true,
            'options': {'payModel': 'megaways'},
          },
          'cascades': {
            'isEnabled': true,
            'options': {'maxCascades': 10},
          },
        },
        'isBuiltIn': false,
        'isFavorite': true,
        'usageCount': 5,
      };

      final preset = FeaturePreset.fromJson(json);

      expect(preset.id, 'loaded_preset_002');
      expect(preset.name, 'Loaded Preset');
      expect(preset.description, 'Loaded from JSON');
      expect(preset.category, PresetCategory.megaways);
      expect(preset.author, 'Test Author');
      expect(preset.tags, ['loaded', 'json']);
      expect(preset.isFavorite, isTrue);
      expect(preset.usageCount, 5);
      expect(preset.blocks['game_core']?.isEnabled, isTrue);
      expect(preset.blocks['cascades']?.options['maxCascades'], 10);
    });

    test('handles missing optional fields gracefully', () {
      final json = {
        'id': 'minimal_preset',
        'name': 'Minimal',
        'category': 'custom',
        'blocks': <String, dynamic>{},
      };

      final preset = FeaturePreset.fromJson(json);

      expect(preset.id, 'minimal_preset');
      expect(preset.name, 'Minimal');
      expect(preset.description, isNull);
      expect(preset.author, isNull);
      expect(preset.tags, isEmpty);
      expect(preset.isBuiltIn, isFalse);
      expect(preset.isFavorite, isFalse);
      expect(preset.usageCount, 0);
    });
  });

  group('Preset Version Migration', () {
    test('handles v1.0.0 schema version', () {
      final json = {
        'id': 'v1_preset',
        'name': 'Version 1 Preset',
        'category': 'video',
        'schemaVersion': '1.0.0',
        'blocks': {
          'game_core': {
            'isEnabled': true,
            'options': {},
          },
        },
      };

      final preset = FeaturePreset.fromJson(json);

      expect(preset.schemaVersion, '1.0.0');
    });

    test('defaults to 1.0.0 when schemaVersion is missing', () {
      final json = {
        'id': 'old_preset',
        'name': 'Old Preset',
        'category': 'classic',
        'blocks': <String, dynamic>{},
      };

      final preset = FeaturePreset.fromJson(json);

      expect(preset.schemaVersion, '1.0.0');
    });
  });

  group('AnticipationBlock Serialization', () {
    test('serializes anticipation block options correctly', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      block.setOptionValue('pattern', 'tip_b');
      block.setOptionValue('triggerSymbol', 'scatter');
      block.setOptionValue('minSymbolsToTrigger', 3);
      block.setOptionValue('tensionEscalationEnabled', true);
      block.setOptionValue('tensionLevels', 4);
      block.setOptionValue('perReelAudio', true);

      final json = block.toJson();

      expect(json['id'], 'anticipation');
      expect(json['isEnabled'], true);
      expect(json['options']['pattern'], 'tip_b');
      expect(json['options']['minSymbolsToTrigger'], 3);
      expect(json['options']['tensionLevels'], 4);
    });

    test('deserializes anticipation block from JSON', () {
      final block = AnticipationBlock();

      final json = {
        'id': 'anticipation',
        'isEnabled': true,
        'schemaVersion': '1.0.0',
        'options': {
          'pattern': 'tip_a',
          'triggerSymbol': 'bonus',
          'minSymbolsToTrigger': 2,
          'tensionEscalationEnabled': false,
          'audioProfile': 'dramatic',
        },
      };

      block.fromJson(json);

      expect(block.isEnabled, true);
      expect(block.getOptionValue<String>('pattern'), 'tip_a');
      expect(block.getOptionValue<String>('triggerSymbol'), 'bonus');
      expect(block.getOptionValue<int>('minSymbolsToTrigger'), 2);
      expect(block.getOptionValue<bool>('tensionEscalationEnabled'), false);
      expect(block.getOptionValue<String>('audioProfile'), 'dramatic');
    });
  });

  group('WildFeaturesBlock Serialization', () {
    test('serializes wild features block options correctly', () {
      final block = WildFeaturesBlock();
      block.isEnabled = true;
      block.setOptionValue('expansion', 'full_reel');
      block.setOptionValue('sticky_duration', 5);
      block.setOptionValue('walking_direction', 'left');
      block.setOptionValue('multiplier_range', [2, 3, 5, 10]);
      block.setOptionValue('stack_height', 4);

      final json = block.toJson();

      expect(json['id'], 'wild_features');
      expect(json['isEnabled'], true);
      expect(json['options']['expansion'], 'full_reel');
      expect(json['options']['sticky_duration'], 5);
      expect(json['options']['walking_direction'], 'left');
      expect(json['options']['multiplier_range'], [2, 3, 5, 10]);
      expect(json['options']['stack_height'], 4);
    });

    test('deserializes wild features block from JSON', () {
      final block = WildFeaturesBlock();

      final json = {
        'id': 'wild_features',
        'isEnabled': true,
        'schemaVersion': '1.0.0',
        'options': {
          'expansion': 'cross',
          'sticky_duration': 3,
          'walking_direction': 'bidirectional',
          'multiplier_range': [2, 5],
          'stack_height': 5,
          'has_expansion_sound': true,
          'has_sticky_sound': false,
        },
      };

      block.fromJson(json);

      expect(block.isEnabled, true);
      expect(block.getOptionValue<String>('expansion'), 'cross');
      expect(block.getOptionValue<num>('sticky_duration'), 3);
      expect(block.getOptionValue<String>('walking_direction'), 'bidirectional');
      expect(block.getOptionValue<List<dynamic>>('multiplier_range'), [2, 5]);
      expect(block.getOptionValue<bool>('has_expansion_sound'), true);
      expect(block.getOptionValue<bool>('has_sticky_sound'), false);
    });
  });

  group('Preset Round Trip', () {
    test('toJson → fromJson produces equivalent preset', () {
      final original = FeaturePreset(
        id: 'roundtrip_test',
        name: 'Round Trip Test',
        description: 'Testing serialization round trip',
        category: PresetCategory.holdWin,
        tags: ['test', 'roundtrip', 'serialization'],
        blocks: {
          'game_core': const BlockPresetData(
            isEnabled: true,
            options: {
              'payModel': 'ways',
              'volatility': 'high',
              'targetRtp': 96.5,
            },
          ),
          'grid': const BlockPresetData(
            isEnabled: true,
            options: {
              'reelCount': 6,
              'rowCount': 4,
              'paylineCount': 50,
            },
          ),
          'hold_and_win': const BlockPresetData(
            isEnabled: true,
            options: {
              'respinCount': 3,
              'hasGrandJackpot': true,
            },
          ),
          'anticipation': const BlockPresetData(
            isEnabled: true,
            options: {
              'pattern': 'tip_a',
              'tensionLevels': 4,
            },
          ),
          'wild_features': const BlockPresetData(
            isEnabled: true,
            options: {
              'expansion': 'full_reel',
              'multiplier_range': [2, 3, 5],
            },
          ),
        },
        isFavorite: true,
        usageCount: 10,
      );

      // Serialize to JSON and back
      final json = original.toJson();
      final restored = FeaturePreset.fromJson(json);

      // Verify all fields match
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.category, original.category);
      expect(restored.tags, original.tags);
      expect(restored.isFavorite, original.isFavorite);
      expect(restored.usageCount, original.usageCount);

      // Verify blocks
      expect(restored.enabledBlockIds.length, original.enabledBlockIds.length);
      for (final blockId in original.blocks.keys) {
        expect(restored.blocks[blockId]?.isEnabled,
            original.blocks[blockId]?.isEnabled);
        expect(restored.blocks[blockId]?.options,
            original.blocks[blockId]?.options);
      }
    });

    test('JSON string round trip preserves data', () {
      final original = FeaturePreset(
        id: 'string_roundtrip',
        name: 'String Round Trip',
        category: PresetCategory.video,
        blocks: {
          'free_spins': const BlockPresetData(
            isEnabled: true,
            options: {
              'baseSpinsCount': 15,
              'hasMultiplier': true,
              'baseMultiplier': 3,
            },
          ),
        },
      );

      // Serialize to JSON string and back
      final jsonString = original.toJsonString();
      final restored = FeaturePreset.fromJsonString(jsonString);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.blocks['free_spins']?.options['baseSpinsCount'], 15);
    });
  });

  group('Invalid Preset Handling', () {
    test('handles corrupt JSON gracefully', () {
      // Missing required 'id' field
      final invalidJson = {
        'name': 'Invalid Preset',
        'category': 'video',
        'blocks': {},
      };

      expect(
        () => FeaturePreset.fromJson(invalidJson),
        throwsA(isA<TypeError>()),
      );
    });

    test('handles invalid category gracefully', () {
      final json = {
        'id': 'invalid_category',
        'name': 'Invalid Category',
        'category': 'nonexistent_category',
        'blocks': <String, dynamic>{},
      };

      final preset = FeaturePreset.fromJson(json);

      // Should fallback to custom
      expect(preset.category, PresetCategory.custom);
    });

    test('handles invalid block options gracefully', () {
      final block = FreeSpinsBlock();

      final json = {
        'id': 'free_spins',
        'isEnabled': true,
        'options': {
          'nonExistentOption': 'some_value',
          'baseSpinsCount': 'not_a_number', // Wrong type
        },
      };

      // Should not throw, just ignore invalid options
      expect(() => block.fromJson(json), returnsNormally);
    });
  });
}
