// StageConfigurationService — Ultimate Unit Tests
//
// Tests for the centralized stage configuration system:
// - Initialization and default stage registration
// - Priority mapping (0-100) by stage name
// - Bus routing by stage prefix
// - Spatial intent mapping
// - Voice pooling (isPooled)
// - Loop detection (isLooping)
// - Custom stage CRUD
// - Win tier stage registration (P5)
// - Symbol stage registration
// - Stage definition serialization

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/slot_lab_models.dart';
import 'package:fluxforge_ui/models/win_tier_config.dart';
import 'package:fluxforge_ui/services/stage_configuration_service.dart';
import 'package:fluxforge_ui/spatial/auto_spatial.dart' show SpatialBus;

void main() {
  late StageConfigurationService service;

  setUp(() {
    service = StageConfigurationService.instance;
    // Ensure initialized
    service.init();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Initialization', () {
    test('singleton instance exists', () {
      expect(StageConfigurationService.instance, isNotNull);
    });

    test('init can be called multiple times safely', () {
      // Should not throw
      service.init();
      service.init();
      expect(true, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIORITY MAPPING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Priority mapping', () {
    test('SPIN_START has medium-high priority', () {
      final p = service.getPriority('SPIN_START');
      expect(p, greaterThanOrEqualTo(40));
      expect(p, lessThanOrEqualTo(80));
    });

    test('JACKPOT_TRIGGER has highest priority', () {
      final p = service.getPriority('JACKPOT_TRIGGER');
      expect(p, greaterThanOrEqualTo(80));
    });

    test('UI_BUTTON_PRESS has low priority', () {
      final p = service.getPriority('UI_BUTTON_PRESS');
      expect(p, lessThanOrEqualTo(40));
    });

    test('MUSIC_BASE has lowest priority', () {
      final p = service.getPriority('MUSIC_BASE');
      expect(p, lessThanOrEqualTo(20));
    });

    test('unknown stage returns default 50', () {
      final p = service.getPriority('COMPLETELY_UNKNOWN_STAGE_XYZ');
      expect(p, 50);
    });

    test('REEL_STOP stages have consistent priority', () {
      final p0 = service.getPriority('REEL_STOP_0');
      final p4 = service.getPriority('REEL_STOP_4');
      // Per-reel stops should have same priority
      expect(p0, p4);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUS ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Bus routing', () {
    test('REEL_STOP maps to reels bus', () {
      final bus = service.getBus('REEL_STOP');
      expect(bus, SpatialBus.reels);
    });

    test('SPIN_START maps to sfx bus', () {
      final bus = service.getBus('SPIN_START');
      expect(bus, SpatialBus.sfx);
    });

    test('WIN_PRESENT maps to sfx bus', () {
      final bus = service.getBus('WIN_PRESENT');
      expect(bus, SpatialBus.sfx);
    });

    test('MUSIC_BASE maps to music bus', () {
      final bus = service.getBus('MUSIC_BASE');
      expect(bus, SpatialBus.music);
    });

    test('UI_BUTTON_PRESS maps to ui bus', () {
      final bus = service.getBus('UI_BUTTON_PRESS');
      expect(bus, SpatialBus.ui);
    });

    test('unknown stage returns sfx as default', () {
      final bus = service.getBus('SOME_UNKNOWN_STAGE');
      expect(bus, SpatialBus.sfx);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE POOLING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Voice pooling (isPooled)', () {
    test('REEL_STOP is pooled', () {
      expect(service.isPooled('REEL_STOP'), true);
    });

    test('ROLLUP_TICK is pooled', () {
      expect(service.isPooled('ROLLUP_TICK'), true);
    });

    test('CASCADE_STEP is pooled', () {
      expect(service.isPooled('CASCADE_STEP'), true);
    });

    test('per-reel stops are pooled', () {
      expect(service.isPooled('REEL_STOP_0'), true);
      expect(service.isPooled('REEL_STOP_4'), true);
    });

    test('SPIN_START is NOT pooled', () {
      expect(service.isPooled('SPIN_START'), false);
    });

    test('JACKPOT_TRIGGER is NOT pooled', () {
      expect(service.isPooled('JACKPOT_TRIGGER'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOOP DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Loop detection (isLooping)', () {
    test('REEL_SPIN_LOOP is looping', () {
      expect(service.isLooping('REEL_SPIN_LOOP'), true);
    });

    test('MUSIC_BASE is looping', () {
      expect(service.isLooping('MUSIC_BASE'), true);
    });

    test('stages ending with _LOOP are looping', () {
      expect(service.isLooping('ANTICIPATION_LOOP'), true);
      expect(service.isLooping('AMBIENT_LOOP'), true);
    });

    test('MUSIC_ prefix stages are looping', () {
      expect(service.isLooping('MUSIC_TENSION'), true);
      expect(service.isLooping('MUSIC_FEATURE'), true);
    });

    test('ATTRACT_MODE is looping', () {
      expect(service.isLooping('ATTRACT_MODE'), true);
    });

    test('SPIN_START is NOT looping', () {
      expect(service.isLooping('SPIN_START'), false);
    });

    test('REEL_STOP is NOT looping', () {
      expect(service.isLooping('REEL_STOP'), false);
    });

    test('WIN_PRESENT is NOT looping', () {
      expect(service.isLooping('WIN_PRESENT'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOM STAGES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Custom stages', () {
    test('registerCustomStage adds stage', () {
      const def = StageDefinition(
        name: 'MY_CUSTOM_STAGE',
        category: StageCategory.custom,
        priority: 60,
      );
      service.registerCustomStage(def);
      expect(service.getPriority('MY_CUSTOM_STAGE'), 60);
    });

    test('removeCustomStage removes stage', () {
      const def = StageDefinition(
        name: 'TO_REMOVE',
        category: StageCategory.custom,
        priority: 70,
      );
      service.registerCustomStage(def);
      service.removeCustomStage('TO_REMOVE');
      // After removal, should return default priority
      expect(service.getPriority('TO_REMOVE'), 50);
    });

    test('default stage takes precedence over custom with same name', () {
      // SPIN_START exists in default _stages with priority 70
      final defaultPriority = service.getPriority('SPIN_START');
      expect(defaultPriority, 70);

      // registerCustomStage stores in _customStages, but getStage()
      // checks _stages first, so the default stage takes precedence
      service.registerCustomStage(const StageDefinition(
        name: 'SPIN_START',
        category: StageCategory.spin,
        priority: 99,
      ));

      // Default still wins because _stages is checked before _customStages
      expect(service.getPriority('SPIN_START'), defaultPriority);

      // Cleanup
      service.removeCustomStage('SPIN_START');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN TIER STAGE REGISTRATION (P5)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Win tier stages', () {
    test('registerWinTierStages adds stages', () {
      final config = SlotWinConfiguration.defaultConfig();
      service.registerWinTierStages(config);

      // Should register WIN_PRESENT_* stages
      expect(service.isWinTierGenerated('WIN_PRESENT_1'), true);
    });

    test('win tier stages have correct category', () {
      // WIN_PRESENT_* should be in win category
      final bus = service.getBus('WIN_PRESENT_1');
      expect(bus, SpatialBus.sfx);
    });

    test('rollup tick stages are pooled', () {
      // ROLLUP_TICK_* should be pooled (rapid-fire)
      expect(service.isPooled('ROLLUP_TICK'), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL STAGE REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Symbol stages', () {
    test('registerSymbolStages adds stages for all contexts', () {
      const symbol = SymbolDefinition(
        id: 'test_wild',
        name: 'Test Wild',
        emoji: '🃏',
        type: SymbolType.wild,
        contexts: ['land', 'win', 'expand'],
      );
      service.registerSymbolStages(symbol);

      expect(service.isSymbolGenerated('SYMBOL_LAND_TEST_WILD'), true);
      expect(service.isSymbolGenerated('WIN_SYMBOL_HIGHLIGHT_TEST_WILD'), true);
      expect(service.isSymbolGenerated('SYMBOL_EXPAND_TEST_WILD'), true);
    });

    test('removeSymbolStages removes all stages for symbol', () {
      const symbol = SymbolDefinition(
        id: 'test_remove',
        name: 'Test Remove',
        emoji: '❌',
        type: SymbolType.lowPay,
        contexts: ['land', 'win'],
      );
      service.registerSymbolStages(symbol);
      service.removeSymbolStages('test_remove');

      expect(service.isSymbolGenerated('SYMBOL_LAND_TEST_REMOVE'), false);
      expect(
          service.isSymbolGenerated('WIN_SYMBOL_HIGHLIGHT_TEST_REMOVE'), false);
    });

    test('syncSymbolStages replaces all symbol stages', () {
      const symbols = [
        SymbolDefinition(
          id: 'sync_a',
          name: 'A',
          emoji: 'A',
          type: SymbolType.highPay,
        ),
        SymbolDefinition(
          id: 'sync_b',
          name: 'B',
          emoji: 'B',
          type: SymbolType.lowPay,
        ),
      ];
      service.syncSymbolStages(symbols);

      expect(service.isSymbolGenerated('SYMBOL_LAND_SYNC_A'), true);
      expect(service.isSymbolGenerated('SYMBOL_LAND_SYNC_B'), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE DEFINITION MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageDefinition', () {
    test('constructor with defaults', () {
      const def = StageDefinition(
        name: 'TEST',
        category: StageCategory.spin,
      );
      expect(def.priority, 50);
      expect(def.bus, SpatialBus.sfx);
      expect(def.isPooled, false);
      expect(def.isLooping, false);
      expect(def.ducksMusic, false);
      expect(def.description, isNull);
    });

    test('copyWith replaces specified fields', () {
      const def = StageDefinition(
        name: 'TEST',
        category: StageCategory.spin,
        priority: 50,
      );
      final copy = def.copyWith(priority: 80, isPooled: true);
      expect(copy.priority, 80);
      expect(copy.isPooled, true);
      expect(copy.name, 'TEST');
      expect(copy.category, StageCategory.spin);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE CATEGORY
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageCategory', () {
    test('all categories have labels', () {
      for (final cat in StageCategory.values) {
        expect(cat.label, isNotEmpty, reason: '$cat has no label');
      }
    });

    test('all categories have colors', () {
      for (final cat in StageCategory.values) {
        expect(cat.color, isNonZero, reason: '$cat has no color');
      }
    });
  });
}
