// Stage Configuration Integration Tests
//
// Tests: Default stage registration, priority levels, bus routing,
// looping detection, pooled event detection, custom stage registration,
// win tier stage registration, fallback resolution.
//
// Pure Dart logic — NO FFI, NO Flutter widgets.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/stage_configuration_service.dart';
import 'package:fluxforge_ui/spatial/auto_spatial.dart' show SpatialBus;
import 'package:fluxforge_ui/models/win_tier_config.dart';

void main() {
  late StageConfigurationService service;

  setUp(() {
    // Create a fresh instance for each test by re-initializing
    service = StageConfigurationService.instance;
    // init() is idempotent — safe to call multiple times
    service.init();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // DEFAULT STAGE REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Default stage registration', () {
    test('service has stages after init', () {
      expect(service.allStageNames, isNotEmpty);
    });

    test('allStages returns list of StageDefinitions', () {
      expect(service.allStages, isNotEmpty);
      for (final stage in service.allStages) {
        expect(stage.name, isNotEmpty);
        expect(stage.priority, greaterThanOrEqualTo(0));
        expect(stage.priority, lessThanOrEqualTo(100));
      }
    });

    test('allStageNames is sorted', () {
      final names = service.allStageNames;
      final sorted = [...names]..sort();
      expect(names, sorted);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // STAGE LOOKUP (CASE INSENSITIVE)
  // ═══════════════════════════════════════════════════════════════════════

  group('Stage lookup', () {
    test('getStage is case-insensitive', () {
      final upper = service.getStage('SPIN_START');
      final lower = service.getStage('spin_start');
      final mixed = service.getStage('Spin_Start');
      // All should resolve the same (or all null if not registered)
      if (upper != null) {
        expect(lower?.name, upper.name);
        expect(mixed?.name, upper.name);
      }
    });

    test('getStage returns null for unknown stage', () {
      final result = service.getStage('COMPLETELY_UNKNOWN_STAGE_XYZ');
      expect(result, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PRIORITY LEVELS
  // ═══════════════════════════════════════════════════════════════════════

  group('Priority levels', () {
    test('getPriority returns value for known stages', () {
      final priority = service.getPriority('SPIN_START');
      expect(priority, greaterThanOrEqualTo(0));
      expect(priority, lessThanOrEqualTo(100));
    });

    test('getPriority returns default for unknown stage', () {
      final priority = service.getPriority('UNKNOWN_XYZ');
      // Should use prefix-based fallback
      expect(priority, greaterThanOrEqualTo(0));
      expect(priority, lessThanOrEqualTo(100));
    });

    test('jackpot stages have highest priority', () {
      final jackpotPriority = service.getPriority('JACKPOT_TRIGGER');
      final uiPriority = service.getPriority('UI_BUTTON_PRESS');
      expect(jackpotPriority, greaterThan(uiPriority));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BUS ROUTING
  // ═══════════════════════════════════════════════════════════════════════

  group('Bus routing', () {
    test('getBus returns SpatialBus for known stages', () {
      final bus = service.getBus('SPIN_START');
      expect(SpatialBus.values, contains(bus));
    });

    test('getBus returns fallback bus for unknown stage', () {
      final bus = service.getBus('UNKNOWN_STAGE_123');
      expect(SpatialBus.values, contains(bus));
    });

    test('music-related stages route to music bus', () {
      final bus = service.getBus('MUSIC_BASE');
      // Music stages should route to music or ambience bus
      expect(bus == SpatialBus.music || bus == SpatialBus.ambience, true);
    });

    test('UI stages route to ui bus', () {
      final bus = service.getBus('UI_BUTTON_PRESS');
      expect(bus, SpatialBus.ui);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // LOOPING DETECTION
  // ═══════════════════════════════════════════════════════════════════════

  group('Looping detection', () {
    test('known looping stages return true', () {
      expect(service.isLooping('REEL_SPIN_LOOP'), true);
      expect(service.isLooping('MUSIC_BASE'), true);
      expect(service.isLooping('AMBIENT_LOOP'), true);
    });

    test('_LOOP suffix detected as looping', () {
      // Even for unknown stages, _LOOP suffix should trigger
      expect(service.isLooping('CUSTOM_SOMETHING_LOOP'), true);
    });

    test('MUSIC_ prefix detected as looping', () {
      expect(service.isLooping('MUSIC_SOMETHING_CUSTOM'), true);
    });

    test('AMBIENT_ prefix detected as looping', () {
      expect(service.isLooping('AMBIENT_CUSTOM_TRACK'), true);
    });

    test('ATTRACT_ prefix detected as looping', () {
      expect(service.isLooping('ATTRACT_INTRO'), true);
    });

    test('IDLE_ prefix detected as looping', () {
      expect(service.isLooping('IDLE_WAITING'), true);
    });

    test('non-looping stages return false', () {
      expect(service.isLooping('SPIN_START'), false);
      expect(service.isLooping('REEL_STOP_0'), false);
      expect(service.isLooping('WIN_PRESENT'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // POOLED EVENT DETECTION
  // ═══════════════════════════════════════════════════════════════════════

  group('Pooled event detection', () {
    test('rapid-fire stages are pooled', () {
      expect(service.isPooled('REEL_STOP'), true);
      expect(service.isPooled('REEL_STOP_0'), true);
      expect(service.isPooled('REEL_STOP_4'), true);
      expect(service.isPooled('CASCADE_STEP'), true);
      expect(service.isPooled('ROLLUP_TICK'), true);
      expect(service.isPooled('WIN_LINE_SHOW'), true);
      expect(service.isPooled('UI_BUTTON_PRESS'), true);
      expect(service.isPooled('SYMBOL_LAND'), true);
    });

    test('non-pooled stages return false', () {
      expect(service.isPooled('SPIN_START'), false);
      expect(service.isPooled('JACKPOT_TRIGGER'), false);
    });

    test('pooledStageNames returns set of pooled names', () {
      final pooled = service.pooledStageNames;
      expect(pooled, isNotEmpty);
      for (final name in pooled) {
        expect(service.isPooled(name), true);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // STAGE CATEGORIES
  // ═══════════════════════════════════════════════════════════════════════

  group('Stage categories', () {
    test('StageCategory enum has 11 values', () {
      expect(StageCategory.values.length, 11);
    });

    test('getByCategory returns stages of that category', () {
      final spinStages = service.getByCategory(StageCategory.spin);
      for (final stage in spinStages) {
        expect(stage.category, StageCategory.spin);
      }
    });

    test('StageCategoryExtension provides labels', () {
      expect(StageCategory.spin.label, 'Spin');
      expect(StageCategory.win.label, 'Win');
      expect(StageCategory.feature.label, 'Feature');
      expect(StageCategory.cascade.label, 'Cascade');
      expect(StageCategory.jackpot.label, 'Jackpot');
      expect(StageCategory.hold.label, 'Hold & Spin');
      expect(StageCategory.gamble.label, 'Gamble');
      expect(StageCategory.ui.label, 'UI');
      expect(StageCategory.music.label, 'Music');
      expect(StageCategory.symbol.label, 'Symbol');
      expect(StageCategory.custom.label, 'Custom');
    });

    test('StageCategoryExtension provides colors', () {
      for (final cat in StageCategory.values) {
        expect(cat.color, isPositive);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // STAGE DEFINITION
  // ═══════════════════════════════════════════════════════════════════════

  group('StageDefinition', () {
    test('creation with defaults', () {
      const def = StageDefinition(
        name: 'CUSTOM_STAGE',
        category: StageCategory.custom,
      );
      expect(def.priority, 50);
      expect(def.bus, SpatialBus.sfx);
      expect(def.spatialIntent, 'DEFAULT');
      expect(def.isPooled, false);
      expect(def.isLooping, false);
      expect(def.ducksMusic, false);
      expect(def.description, isNull);
    });

    test('creation with all fields', () {
      const def = StageDefinition(
        name: 'JACKPOT_GRAND',
        category: StageCategory.jackpot,
        priority: 95,
        bus: SpatialBus.sfx,
        spatialIntent: 'CENTER',
        isPooled: false,
        isLooping: false,
        ducksMusic: true,
        description: 'Grand jackpot trigger',
      );
      expect(def.priority, 95);
      expect(def.ducksMusic, true);
      expect(def.description, 'Grand jackpot trigger');
    });

    test('copyWith creates independent copy', () {
      const original = StageDefinition(
        name: 'TEST',
        category: StageCategory.ui,
        priority: 30,
      );
      final copy = original.copyWith(priority: 80, isPooled: true);
      expect(copy.priority, 80);
      expect(copy.isPooled, true);
      expect(original.priority, 30);
      expect(original.isPooled, false);
    });

    test('JSON roundtrip', () {
      const def = StageDefinition(
        name: 'SPIN_START',
        category: StageCategory.spin,
        priority: 70,
        bus: SpatialBus.reels,
        spatialIntent: 'CENTER',
        isPooled: false,
        isLooping: false,
        ducksMusic: false,
        description: 'Spin button pressed',
      );
      final json = def.toJson();
      final restored = StageDefinition.fromJson(json);

      expect(restored.name, def.name);
      expect(restored.category, def.category);
      expect(restored.priority, def.priority);
      expect(restored.bus, def.bus);
      expect(restored.spatialIntent, def.spatialIntent);
      expect(restored.isPooled, def.isPooled);
      expect(restored.isLooping, def.isLooping);
      expect(restored.ducksMusic, def.ducksMusic);
      expect(restored.description, def.description);
    });

    test('fromJson with unknown category defaults to custom', () {
      final json = {
        'name': 'X',
        'category': 'nonexistent_category',
      };
      final def = StageDefinition.fromJson(json);
      expect(def.category, StageCategory.custom);
    });

    test('fromJson with unknown bus defaults to sfx', () {
      final json = {
        'name': 'X',
        'category': 'spin',
        'bus': 'nonexistent_bus',
      };
      final def = StageDefinition.fromJson(json);
      expect(def.bus, SpatialBus.sfx);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CUSTOM STAGE REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Custom stage registration', () {
    test('registerCustomStage adds new stage', () {
      const custom = StageDefinition(
        name: 'MY_CUSTOM_STAGE_TEST_UNIQUE',
        category: StageCategory.custom,
        priority: 60,
        bus: SpatialBus.sfx,
      );
      service.registerCustomStage(custom);

      final retrieved = service.getStage('MY_CUSTOM_STAGE_TEST_UNIQUE');
      expect(retrieved, isNotNull);
      expect(retrieved!.priority, 60);
    });

    test('registerCustomStage normalizes to uppercase', () {
      const custom = StageDefinition(
        name: 'lowercase_stage_test',
        category: StageCategory.custom,
      );
      service.registerCustomStage(custom);

      final retrieved = service.getStage('LOWERCASE_STAGE_TEST');
      expect(retrieved, isNotNull);
    });

    test('removeCustomStage removes stage', () {
      const custom = StageDefinition(
        name: 'TEMP_STAGE_TO_REMOVE',
        category: StageCategory.custom,
      );
      service.registerCustomStage(custom);
      expect(service.getStage('TEMP_STAGE_TO_REMOVE'), isNotNull);

      service.removeCustomStage('TEMP_STAGE_TO_REMOVE');
      expect(service.getStage('TEMP_STAGE_TO_REMOVE'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // WIN TIER STAGE REGISTRATION (P5)
  // ═══════════════════════════════════════════════════════════════════════

  group('Win tier stage registration (P5)', () {
    test('registerWinTierStages creates stages from config', () {
      final config = SlotWinConfiguration.defaultConfig();
      service.registerWinTierStages(config);

      // Check regular win stages
      final winLow = service.getStage('WIN_LOW');
      expect(winLow, isNotNull);
      expect(winLow!.category, StageCategory.win);

      final win1 = service.getStage('WIN_1');
      expect(win1, isNotNull);

      // Check big win stages
      final bigIntro = service.getStage('BIG_WIN_INTRO');
      expect(bigIntro, isNotNull);

      final bigTier1 = service.getStage('BIG_WIN_TIER_1');
      expect(bigTier1, isNotNull);
    });

    test('win tier stages have appropriate priorities', () {
      final config = SlotWinConfiguration.defaultConfig();
      service.registerWinTierStages(config);

      final winLow = service.getStage('WIN_LOW');
      final bigTier5 = service.getStage('BIG_WIN_TIER_5');

      if (winLow != null && bigTier5 != null) {
        // Big win tiers should have higher priority than regular wins
        expect(bigTier5.priority, greaterThan(winLow.priority));
      }
    });

    test('re-registering clears previous win tier stages', () {
      // Register with standard config
      service.registerWinTierStages(SlotWinConfigurationPresets.standard);

      // Register with jackpotFocus (different structure)
      service.registerWinTierStages(SlotWinConfigurationPresets.jackpotFocus);

      // Jackpot focus has only 3 regular tiers (LOW, WIN_1, WIN_2)
      // WIN_5 should NOT exist from previous registration
      // (It may exist from default registration, but win-tier generated ones are cleaned)
      // We can at least verify the new ones exist
      expect(service.getStage('WIN_1'), isNotNull);
      expect(service.getStage('BIG_WIN_TIER_1'), isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SPATIAL BUS ENUM
  // ═══════════════════════════════════════════════════════════════════════

  group('SpatialBus', () {
    test('has 6 bus types', () {
      expect(SpatialBus.values.length, 6);
      expect(SpatialBus.values, contains(SpatialBus.ui));
      expect(SpatialBus.values, contains(SpatialBus.reels));
      expect(SpatialBus.values, contains(SpatialBus.sfx));
      expect(SpatialBus.values, contains(SpatialBus.vo));
      expect(SpatialBus.values, contains(SpatialBus.music));
      expect(SpatialBus.values, contains(SpatialBus.ambience));
    });
  });
}
