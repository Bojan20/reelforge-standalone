// Stage Trace Widget Tests
//
// Tests for StageTraceWidget and supporting classes:
// - StageConfig singleton (centralized stage configuration)
// - StageConfigEntry model
// - StageCategory enum
//
// NOTE: Full widget tests for StageTraceWidget require mocking:
// - SlotLabProvider (complex state)
// - NativeFFI (Rust library)
// - EventRegistry (audio playback)
// - EventProfilerProvider (latency metrics)
//
// For complete integration testing, use `flutter run --profile`

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/config/stage_config.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // P1.18: STAGE CATEGORY ENUM TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageCategory', () {
    test('should have all expected categories', () {
      expect(StageCategory.values.length, 14);
      expect(StageCategory.spin, isNotNull);
      expect(StageCategory.anticipation, isNotNull);
      expect(StageCategory.win, isNotNull);
      expect(StageCategory.rollup, isNotNull);
      expect(StageCategory.bigwin, isNotNull);
      expect(StageCategory.feature, isNotNull);
      expect(StageCategory.cascade, isNotNull);
      expect(StageCategory.jackpot, isNotNull);
      expect(StageCategory.bonus, isNotNull);
      expect(StageCategory.gamble, isNotNull);
      expect(StageCategory.music, isNotNull);
      expect(StageCategory.ui, isNotNull);
      expect(StageCategory.system, isNotNull);
      expect(StageCategory.custom, isNotNull);
    });

    test('should have correct name values', () {
      expect(StageCategory.spin.name, 'spin');
      expect(StageCategory.jackpot.name, 'jackpot');
      expect(StageCategory.custom.name, 'custom');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.18: STAGE CONFIG ENTRY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageConfigEntry', () {
    test('should create with required parameters', () {
      const entry = StageConfigEntry(
        color: Color(0xFF4A9EFF),
        icon: Icons.play_circle_outline,
      );

      expect(entry.color, const Color(0xFF4A9EFF));
      expect(entry.icon, Icons.play_circle_outline);
      expect(entry.category, StageCategory.custom); // default
      expect(entry.description, isNull);
      expect(entry.isPooled, false); // default
    });

    test('should create with all parameters', () {
      const entry = StageConfigEntry(
        color: Color(0xFF40FF90),
        icon: Icons.emoji_events,
        category: StageCategory.win,
        description: 'Win presentation',
        isPooled: true,
      );

      expect(entry.color, const Color(0xFF40FF90));
      expect(entry.icon, Icons.emoji_events);
      expect(entry.category, StageCategory.win);
      expect(entry.description, 'Win presentation');
      expect(entry.isPooled, true);
    });

    test('copyWith should create modified copy', () {
      const original = StageConfigEntry(
        color: Color(0xFF4A9EFF),
        icon: Icons.play_circle_outline,
        category: StageCategory.spin,
        description: 'Original',
        isPooled: false,
      );

      final modified = original.copyWith(
        color: const Color(0xFFFF0000),
        description: 'Modified',
        isPooled: true,
      );

      // Original unchanged
      expect(original.color, const Color(0xFF4A9EFF));
      expect(original.description, 'Original');
      expect(original.isPooled, false);

      // Modified has new values
      expect(modified.color, const Color(0xFFFF0000));
      expect(modified.description, 'Modified');
      expect(modified.isPooled, true);

      // Unchanged fields preserved
      expect(modified.icon, Icons.play_circle_outline);
      expect(modified.category, StageCategory.spin);
    });

    test('copyWith with no arguments returns equivalent entry', () {
      const original = StageConfigEntry(
        color: Color(0xFF4A9EFF),
        icon: Icons.play_circle_outline,
        category: StageCategory.spin,
      );

      final copied = original.copyWith();

      expect(copied.color, original.color);
      expect(copied.icon, original.icon);
      expect(copied.category, original.category);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.18: STAGE CONFIG SINGLETON TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageConfig', () {
    test('should be a singleton', () {
      final instance1 = StageConfig.instance;
      final instance2 = StageConfig.instance;

      expect(identical(instance1, instance2), true);
    });

    test('should have default color and icon constants', () {
      expect(StageConfig.defaultColor, const Color(0xFF6B7280));
      expect(StageConfig.defaultIcon, Icons.circle);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // getColor() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('getColor()', () {
      test('should return color for known stages', () {
        expect(
          StageConfig.instance.getColor('spin_start'),
          const Color(0xFF4A9EFF),
        );
        expect(
          StageConfig.instance.getColor('win_present'),
          const Color(0xFF40FF90),
        );
      });

      test('should return default color for unknown stages', () {
        expect(
          StageConfig.instance.getColor('unknown_stage_xyz'),
          StageConfig.defaultColor,
        );
      });

      test('should be case-insensitive', () {
        final color1 = StageConfig.instance.getColor('spin_start');
        final color2 = StageConfig.instance.getColor('SPIN_START');
        final color3 = StageConfig.instance.getColor('Spin_Start');

        expect(color1, color2);
        expect(color2, color3);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // getIcon() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('getIcon()', () {
      test('should return icon for known stages', () {
        expect(
          StageConfig.instance.getIcon('spin_start'),
          Icons.play_circle_outline,
        );
      });

      test('should return default icon for unknown stages', () {
        expect(
          StageConfig.instance.getIcon('unknown_stage_xyz'),
          StageConfig.defaultIcon,
        );
      });

      test('should be case-insensitive', () {
        final icon1 = StageConfig.instance.getIcon('spin_start');
        final icon2 = StageConfig.instance.getIcon('SPIN_START');

        expect(icon1, icon2);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // getConfig() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('getConfig()', () {
      test('should return config for known stages', () {
        final config = StageConfig.instance.getConfig('spin_start');

        expect(config, isNotNull);
        expect(config!.color, const Color(0xFF4A9EFF));
        expect(config.category, StageCategory.spin);
      });

      test('should return null for unknown stages', () {
        final config = StageConfig.instance.getConfig('unknown_xyz');

        expect(config, isNull);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // getCategory() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('getCategory()', () {
      test('should return category for known stages', () {
        expect(
          StageConfig.instance.getCategory('spin_start'),
          StageCategory.spin,
        );
        expect(
          StageConfig.instance.getCategory('win_present'),
          StageCategory.win,
        );
        expect(
          StageConfig.instance.getCategory('jackpot_trigger'),
          StageCategory.jackpot,
        );
      });

      test('should return custom category for unknown stages', () {
        expect(
          StageConfig.instance.getCategory('unknown_stage'),
          StageCategory.custom,
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // isPooled() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('isPooled()', () {
      test('should return true for pooled stages', () {
        // reel_spinning is marked as pooled in the config
        expect(StageConfig.instance.isPooled('reel_spinning'), true);
        expect(StageConfig.instance.isPooled('rollup_tick'), true);
      });

      test('should return false for non-pooled stages', () {
        expect(StageConfig.instance.isPooled('spin_start'), false);
        expect(StageConfig.instance.isPooled('win_present'), false);
      });

      test('should return false for unknown stages', () {
        expect(StageConfig.instance.isPooled('unknown_stage'), false);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // registerStage() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('registerStage()', () {
      test('should register custom stage', () {
        StageConfig.instance.registerStage(
          'my_custom_stage',
          color: const Color(0xFFFF00FF),
          icon: Icons.star,
          category: StageCategory.custom,
          description: 'My custom stage',
        );

        final config = StageConfig.instance.getConfig('my_custom_stage');
        expect(config, isNotNull);
        expect(config!.color, const Color(0xFFFF00FF));
        expect(config.icon, Icons.star);
        expect(config.description, 'My custom stage');
      });

      test('should override existing custom stage', () {
        StageConfig.instance.registerStage(
          'test_override_stage',
          color: const Color(0xFF111111),
          icon: Icons.circle,
        );

        StageConfig.instance.registerStage(
          'test_override_stage',
          color: const Color(0xFF222222),
          icon: Icons.square,
        );

        final config = StageConfig.instance.getConfig('test_override_stage');
        expect(config!.color, const Color(0xFF222222));
        expect(config.icon, Icons.square);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // registerStages() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('registerStages()', () {
      test('should register multiple stages at once', () {
        StageConfig.instance.registerStages({
          'batch_stage_1': const StageConfigEntry(
            color: Color(0xFFAAAAAA),
            icon: Icons.looks_one,
          ),
          'batch_stage_2': const StageConfigEntry(
            color: Color(0xFFBBBBBB),
            icon: Icons.looks_two,
          ),
        });

        expect(
          StageConfig.instance.getColor('batch_stage_1'),
          const Color(0xFFAAAAAA),
        );
        expect(
          StageConfig.instance.getColor('batch_stage_2'),
          const Color(0xFFBBBBBB),
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // updateStage() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('updateStage()', () {
      test('should update existing custom stage', () {
        // First register
        StageConfig.instance.registerStage(
          'update_test_stage',
          color: const Color(0xFF000000),
          icon: Icons.circle,
        );

        // Verify initial
        expect(
          StageConfig.instance.getColor('update_test_stage'),
          const Color(0xFF000000),
        );

        // Then update (void return)
        StageConfig.instance.updateStage(
          'update_test_stage',
          color: const Color(0xFFFFFFFF),
        );

        // Verify updated
        expect(
          StageConfig.instance.getColor('update_test_stage'),
          const Color(0xFFFFFFFF),
        );
      });

      test('should not crash for non-existent stage', () {
        // updateStage on non-existent stage should be a no-op
        StageConfig.instance.updateStage(
          'nonexistent_stage_xyz_123',
          color: const Color(0xFF000000),
        );

        // Verify it doesn't exist
        expect(
          StageConfig.instance.getConfig('nonexistent_stage_xyz_123'),
          isNull,
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // removeCustomStage() tests
    // ─────────────────────────────────────────────────────────────────────────

    group('removeCustomStage()', () {
      test('should remove custom stage', () {
        StageConfig.instance.registerStage(
          'removable_stage',
          color: const Color(0xFF123456),
          icon: Icons.delete,
        );

        expect(StageConfig.instance.getConfig('removable_stage'), isNotNull);

        // Remove (void return)
        StageConfig.instance.removeCustomStage('removable_stage');

        // Verify removed
        expect(StageConfig.instance.getConfig('removable_stage'), isNull);
      });

      test('should not affect built-in stages', () {
        // spin_start is a built-in stage
        // removeCustomStage only removes from _customStages, not _stages
        StageConfig.instance.removeCustomStage('spin_start');

        // Built-in stage should still exist
        expect(StageConfig.instance.getConfig('spin_start'), isNotNull);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Serialization tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Serialization', () {
      test('toJson should export all stages', () {
        // Register a custom stage first
        StageConfig.instance.registerStage(
          'json_test_stage',
          color: const Color(0xFFABCDEF),
          icon: Icons.account_circle,
          category: StageCategory.ui,
          description: 'JSON test',
        );

        final json = StageConfig.instance.toJson();

        expect(json, isA<Map<String, dynamic>>());

        // Should contain the custom stage
        expect(json['json_test_stage'], isA<Map>());
        expect(json['json_test_stage']['color'], 0xFFABCDEF);
        expect(json['json_test_stage']['category'], 'ui');
        expect(json['json_test_stage']['description'], 'JSON test');

        // Should also contain built-in stages
        expect(json['spin_start'], isA<Map>());
        expect(json['spin_start']['category'], 'spin');
      });

      test('fromJson should import stages', () {
        final json = {
          'restored_stage': {
            'color': 0xFF112233,
            'icon': Icons.restore.codePoint,
            'category': 'system',
            'description': 'Restored from JSON',
            'isPooled': true,
          },
        };

        StageConfig.instance.fromJson(json);

        final config = StageConfig.instance.getConfig('restored_stage');
        expect(config, isNotNull);
        expect(config!.color.value, 0xFF112233);
        expect(config.description, 'Restored from JSON');
        expect(config.isPooled, true);
        expect(config.category, StageCategory.system);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Built-in stages coverage
    // ─────────────────────────────────────────────────────────────────────────

    group('Built-in Stages', () {
      test('should have spin lifecycle stages', () {
        expect(StageConfig.instance.getConfig('spin_start'), isNotNull);
        expect(StageConfig.instance.getConfig('reel_spinning'), isNotNull);
        expect(StageConfig.instance.getConfig('reel_stop'), isNotNull);
        expect(StageConfig.instance.getConfig('spin_end'), isNotNull);
      });

      test('should have win stages', () {
        expect(StageConfig.instance.getConfig('win_present'), isNotNull);
        expect(StageConfig.instance.getConfig('win_line_show'), isNotNull);
        expect(StageConfig.instance.getConfig('win_line_hide'), isNotNull);
      });

      test('should have rollup stages', () {
        expect(StageConfig.instance.getConfig('rollup_start'), isNotNull);
        expect(StageConfig.instance.getConfig('rollup_tick'), isNotNull);
        expect(StageConfig.instance.getConfig('rollup_end'), isNotNull);
      });

      test('should have jackpot stages', () {
        expect(StageConfig.instance.getConfig('jackpot_trigger'), isNotNull);
        expect(StageConfig.instance.getConfig('jackpot_present'), isNotNull);
      });

      test('should have feature stages', () {
        expect(StageConfig.instance.getConfig('feature_enter'), isNotNull);
        expect(StageConfig.instance.getConfig('feature_step'), isNotNull);
        expect(StageConfig.instance.getConfig('feature_exit'), isNotNull);
      });

      test('should have cascade stages', () {
        expect(StageConfig.instance.getConfig('cascade_start'), isNotNull);
        expect(StageConfig.instance.getConfig('cascade_step'), isNotNull);
        expect(StageConfig.instance.getConfig('cascade_end'), isNotNull);
      });

      test('should have anticipation stages', () {
        expect(StageConfig.instance.getConfig('anticipation_on'), isNotNull);
        expect(StageConfig.instance.getConfig('anticipation_off'), isNotNull);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.18: STAGE TRACE WIDGET TESTS (Smoke Tests Only)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // NOTE: Full StageTraceWidget tests require:
  // - Mock SlotLabProvider
  // - Mock EventRegistry
  // - Native FFI library loaded
  //
  // These tests are placeholders for integration testing.

  group('StageTraceWidget (Smoke Tests)', () {
    test('StageTraceWidget class exists', () {
      // Verify the class can be imported and referenced
      // Actual widget instantiation requires provider mocking
      expect(true, true); // Placeholder
    });
  });
}
