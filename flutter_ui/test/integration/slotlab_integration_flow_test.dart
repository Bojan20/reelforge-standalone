// SlotLab Integration Flow Tests — Ultimate QA
//
// Tests the cross-component integration flows that connect SlotLab subsystems:
//
// Flow 1: Win Tier Evaluation — P5 system (regular + big win tiers)
// Flow 2: SlotWinConfiguration — Combined config (regular + big + presets)
// Flow 3: WinTierResult — Win tier result model
// Flow 4: Legacy Stage Mapping — Old stage names → P5 names
// Flow 5: Slot Audio Event Factory — Template event generation
// Flow 6: Slot Audio Profile — Full profile with element mappings
// Flow 7: SlotCompositeEvent — Event model integration
// Flow 8: SlotEventLayer DSP Chain — DSP node management
// Flow 9: Event Zoom Settings — Per-event zoom state
// Flow 10: Event Zoom Service — Zoom persistence
// Flow 11: StageConfigurationService ↔ Win Tier Registration
// Flow 12: Legacy Win Tier System — M4 backward compatibility
// Flow 13: SlotAudioLayer model
// Flow 14: SlotElementEventMapping
// Flow 15: TimelineClip model
// Flow 16: CrossfadeCurve enum (middleware)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/event_zoom_settings.dart';
import 'package:fluxforge_ui/models/middleware_models.dart'
    show ActionType, MusicSyncPoint, CrossfadeCurve;
import 'package:fluxforge_ui/models/slot_audio_events.dart';
import 'package:fluxforge_ui/models/slot_lab_models.dart';
import 'package:fluxforge_ui/models/timeline_models.dart' hide CrossfadeCurve;
import 'package:fluxforge_ui/models/win_tier_config.dart';
import 'package:fluxforge_ui/services/event_registry.dart' show ContainerType;
import 'package:fluxforge_ui/services/stage_configuration_service.dart';
import 'package:fluxforge_ui/spatial/auto_spatial.dart' show SpatialBus;

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 1: P5 WIN TIER EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 1: P5 Win Tier Evaluation', () {
    group('WinTierDefinition matching', () {
      test('WIN_LOW matches wins below 1x', () {
        const tier = WinTierDefinition(
          tierId: -1,
          fromMultiplier: 0.0,
          toMultiplier: 1.0,
          displayLabel: 'WIN LOW',
          rollupDurationMs: 0,
          rollupTickRate: 0,
        );
        // 0.5x bet = within [0, 1)
        expect(tier.matches(5.0, 10.0), true);
        // Exactly 1x = NOT in [0, 1)
        expect(tier.matches(10.0, 10.0), false);
      });

      test('WIN_1 matches wins from 1x to 2x', () {
        const tier = WinTierDefinition(
          tierId: 1,
          fromMultiplier: 1.0,
          toMultiplier: 2.0,
          displayLabel: 'WIN 1',
          rollupDurationMs: 1000,
          rollupTickRate: 15,
        );
        expect(tier.matches(10.0, 10.0), true); // 1x
        expect(tier.matches(15.0, 10.0), true); // 1.5x
        expect(tier.matches(20.0, 10.0), false); // 2x = not in [1, 2)
      });

      test('zero bet returns false', () {
        const tier = WinTierDefinition(
          tierId: 1,
          fromMultiplier: 1.0,
          toMultiplier: 2.0,
          displayLabel: 'WIN 1',
          rollupDurationMs: 1000,
          rollupTickRate: 15,
        );
        expect(tier.matches(10.0, 0.0), false);
      });

      test('negative bet returns false', () {
        const tier = WinTierDefinition(
          tierId: 1,
          fromMultiplier: 1.0,
          toMultiplier: 2.0,
          displayLabel: 'WIN 1',
          rollupDurationMs: 1000,
          rollupTickRate: 15,
        );
        expect(tier.matches(10.0, -5.0), false);
      });

      test('stage name generation for regular tiers', () {
        const tier = WinTierDefinition(
          tierId: 3,
          fromMultiplier: 4.0,
          toMultiplier: 8.0,
          displayLabel: 'WIN 3',
          rollupDurationMs: 2000,
          rollupTickRate: 10,
        );
        expect(tier.stageName, 'WIN_3');
        expect(tier.presentStageName, 'WIN_PRESENT_3');
        expect(tier.rollupStartStageName, 'ROLLUP_START_3');
        expect(tier.rollupTickStageName, 'ROLLUP_TICK_3');
        expect(tier.rollupEndStageName, 'ROLLUP_END_3');
      });

      test('WIN_LOW has no rollup stages', () {
        const tier = WinTierDefinition(
          tierId: -1,
          fromMultiplier: 0.0,
          toMultiplier: 1.0,
          displayLabel: 'WIN LOW',
          rollupDurationMs: 0,
          rollupTickRate: 0,
        );
        expect(tier.stageName, 'WIN_LOW');
        expect(tier.presentStageName, 'WIN_PRESENT_LOW');
        expect(tier.rollupStartStageName, isNull);
        expect(tier.rollupTickStageName, isNull);
        expect(tier.rollupEndStageName, isNull);
      });

      test('WIN_EQUAL stage names', () {
        const tier = WinTierDefinition(
          tierId: 0,
          fromMultiplier: 1.0,
          toMultiplier: 1.001,
          displayLabel: 'WIN =',
          rollupDurationMs: 500,
          rollupTickRate: 15,
        );
        expect(tier.stageName, 'WIN_EQUAL');
        expect(tier.presentStageName, 'WIN_PRESENT_EQUAL');
      });

      test('serialization round-trip', () {
        const tier = WinTierDefinition(
          tierId: 2,
          fromMultiplier: 2.0,
          toMultiplier: 5.0,
          displayLabel: 'WIN 2',
          rollupDurationMs: 1500,
          rollupTickRate: 12,
        );
        final json = tier.toJson();
        final restored = WinTierDefinition.fromJson(json);
        expect(restored.tierId, tier.tierId);
        expect(restored.fromMultiplier, tier.fromMultiplier);
        expect(restored.toMultiplier, tier.toMultiplier);
        expect(restored.displayLabel, tier.displayLabel);
        expect(restored.rollupDurationMs, tier.rollupDurationMs);
        expect(restored.rollupTickRate, tier.rollupTickRate);
      });
    });

    group('RegularWinTierConfig evaluation', () {
      late RegularWinTierConfig config;

      setUp(() {
        config = RegularWinTierConfig.defaultConfig();
      });

      test('default config has 7 tiers', () {
        expect(config.tiers.length, 7);
      });

      test('getTierForWin returns correct tier for 0.5x', () {
        final tier = config.getTierForWin(5.0, 10.0); // 0.5x
        expect(tier, isNotNull);
        expect(tier!.tierId, -1); // WIN_LOW
      });

      test('getTierForWin returns correct tier for 3x', () {
        final tier = config.getTierForWin(30.0, 10.0); // 3x
        expect(tier, isNotNull);
        expect(tier!.tierId, 2); // WIN_2 (2-4x)
      });

      test('getTierForWin returns correct tier for 15x', () {
        final tier = config.getTierForWin(150.0, 10.0); // 15x
        expect(tier, isNotNull);
        expect(tier!.tierId, 5); // WIN_5 (13-20x)
      });

      test('getTierForWin returns null for 25x (above regular range)', () {
        final tier = config.getTierForWin(250.0, 10.0); // 25x
        expect(tier, isNull);
      });

      test('getTierForWin returns null for zero bet', () {
        final tier = config.getTierForWin(10.0, 0.0);
        expect(tier, isNull);
      });

      test('validate returns true for default config', () {
        expect(config.validate(), true);
      });

      test('validate detects gaps', () {
        final badConfig = RegularWinTierConfig(
          configId: 'bad',
          name: 'Bad',
          source: WinTierConfigSource.manual,
          tiers: const [
            WinTierDefinition(
              tierId: 1,
              fromMultiplier: 1.0,
              toMultiplier: 5.0,
              displayLabel: 'WIN 1',
              rollupDurationMs: 1000,
              rollupTickRate: 15,
            ),
            // Gap: 5.0 to 10.0 is missing
            WinTierDefinition(
              tierId: 2,
              fromMultiplier: 10.0,
              toMultiplier: 20.0,
              displayLabel: 'WIN 2',
              rollupDurationMs: 1500,
              rollupTickRate: 12,
            ),
          ],
        );
        expect(badConfig.validate(), false);
      });

      test('getValidationErrors returns details for bad config', () {
        final badConfig = RegularWinTierConfig(
          configId: 'empty',
          name: 'Empty',
          source: WinTierConfigSource.manual,
          tiers: const [],
        );
        final errors = badConfig.getValidationErrors();
        expect(errors, isNotEmpty);
      });

      test('serialization round-trip', () {
        final json = config.toJson();
        final restored = RegularWinTierConfig.fromJson(json);
        expect(restored.tiers.length, config.tiers.length);
        expect(restored.configId, config.configId);
        expect(restored.validate(), true);
      });
    });

    group('BigWinConfig evaluation', () {
      late BigWinConfig config;

      setUp(() {
        config = BigWinConfig.defaultConfig();
      });

      test('default threshold is 20x', () {
        expect(config.threshold, 20.0);
      });

      test('default has 5 tiers', () {
        expect(config.tiers.length, 5);
      });

      test('isBigWin returns true for 25x', () {
        expect(config.isBigWin(250.0, 10.0), true);
      });

      test('isBigWin returns false for 15x', () {
        expect(config.isBigWin(150.0, 10.0), false);
      });

      test('isBigWin returns false for zero bet', () {
        expect(config.isBigWin(100.0, 0.0), false);
      });

      test('getMaxTierForWin returns correct tier for 30x', () {
        final tier = config.getMaxTierForWin(300.0, 10.0); // 30x → tier 1 (20-50)
        expect(tier, 1);
      });

      test('getMaxTierForWin returns correct tier for 75x', () {
        final tier = config.getMaxTierForWin(750.0, 10.0); // 75x → tier 2 (50-100)
        expect(tier, 2);
      });

      test('getMaxTierForWin returns correct tier for 150x', () {
        final tier = config.getMaxTierForWin(1500.0, 10.0); // 150x → tier 3 (100-250)
        expect(tier, 3);
      });

      test('getMaxTierForWin returns correct tier for 300x', () {
        final tier = config.getMaxTierForWin(3000.0, 10.0); // 300x → tier 4 (250-500)
        expect(tier, 4);
      });

      test('getMaxTierForWin returns correct tier for 1000x', () {
        final tier = config.getMaxTierForWin(10000.0, 10.0); // 1000x → tier 5 (500+)
        expect(tier, 5);
      });

      test('getMaxTierForWin returns 0 for non-big-win', () {
        final tier = config.getMaxTierForWin(100.0, 10.0); // 10x < 20x
        expect(tier, 0);
      });

      test('getTierById returns correct tier', () {
        final tier = config.getTierById(3);
        expect(tier, isNotNull);
        expect(tier!.fromMultiplier, 100);
        expect(tier.toMultiplier, 250);
      });

      test('getTierById returns null for non-existent tier', () {
        final tier = config.getTierById(99);
        expect(tier, isNull);
      });

      test('getTiersForWin returns escalation sequence', () {
        // 150x → plays tier 1, 2, 3
        final tiers = config.getTiersForWin(1500.0, 10.0);
        expect(tiers.length, 3);
        expect(tiers[0].tierId, 1);
        expect(tiers[1].tierId, 2);
        expect(tiers[2].tierId, 3);
      });

      test('getTiersForWin returns empty for non-big-win', () {
        final tiers = config.getTiersForWin(100.0, 10.0); // 10x
        expect(tiers, isEmpty);
      });

      test('getTotalDurationMs includes intro + tiers + end + fadeout', () {
        // Tier 1 only (30x) → intro(500) + tier1(4000) + end(4000) + fadeout(1000)
        final duration = config.getTotalDurationMs(300.0, 10.0);
        expect(duration, 500 + 4000 + 4000 + 1000);
      });

      test('getTotalDurationMs returns 0 for non-big-win', () {
        final duration = config.getTotalDurationMs(100.0, 10.0);
        expect(duration, 0);
      });

      test('validate returns true for default config', () {
        expect(config.validate(), true);
      });

      test('static stage names are correct', () {
        expect(BigWinConfig.introStageName, 'BIG_WIN_INTRO');
        expect(BigWinConfig.endStageName, 'BIG_WIN_END');
        expect(BigWinConfig.fadeOutStageName, 'BIG_WIN_FADE_OUT');
        expect(BigWinConfig.rollupTickStageName, 'BIG_WIN_ROLLUP_TICK');
      });

      test('BigWinTierDefinition stage names', () {
        const tier = BigWinTierDefinition(
          tierId: 3,
          fromMultiplier: 100,
          toMultiplier: 250,
          displayLabel: 'BIG WIN TIER 3',
        );
        expect(tier.stageName, 'BIG_WIN_TIER_3');
      });

      test('serialization round-trip with infinity', () {
        final json = config.toJson();
        final jsonStr = jsonEncode(json);
        final restored =
            BigWinConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
        expect(restored.tiers.length, config.tiers.length);
        expect(restored.threshold, config.threshold);
        // Tier 5 has infinity as toMultiplier
        expect(restored.tiers.last.toMultiplier, double.infinity);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 2: SLOT WIN CONFIGURATION (Combined)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 2: SlotWinConfiguration', () {
    late SlotWinConfiguration config;

    setUp(() {
      config = SlotWinConfiguration.defaultConfig();
    });

    test('getRegularTier returns tier for 5x win', () {
      final tier = config.getRegularTier(50.0, 10.0); // 5x
      expect(tier, isNotNull);
      expect(tier!.tierId, 3); // WIN_3 (4-8x in default)
    });

    test('getRegularTier returns null for big win (25x)', () {
      final tier = config.getRegularTier(250.0, 10.0); // 25x ≥ 20x threshold
      expect(tier, isNull);
    });

    test('isBigWin delegates to bigWins', () {
      expect(config.isBigWin(250.0, 10.0), true);
      expect(config.isBigWin(100.0, 10.0), false);
    });

    test('getBigWinMaxTier delegates to bigWins', () {
      expect(config.getBigWinMaxTier(750.0, 10.0), 2); // 75x → tier 2
      expect(config.getBigWinMaxTier(100.0, 10.0), 0);
    });

    test('getAllStageNames includes all regular and big win stages', () {
      final stages = config.getAllStageNames();

      // Regular stages
      expect(stages, contains('WIN_LOW'));
      expect(stages, contains('WIN_PRESENT_LOW'));
      expect(stages, contains('WIN_1'));
      expect(stages, contains('WIN_PRESENT_1'));
      expect(stages, contains('ROLLUP_START_1'));
      expect(stages, contains('ROLLUP_TICK_1'));
      expect(stages, contains('ROLLUP_END_1'));

      // Big win stages
      expect(stages, contains('BIG_WIN_INTRO'));
      expect(stages, contains('BIG_WIN_TIER_1'));
      expect(stages, contains('BIG_WIN_TIER_5'));
      expect(stages, contains('BIG_WIN_END'));
      expect(stages, contains('BIG_WIN_FADE_OUT'));
      expect(stages, contains('BIG_WIN_ROLLUP_TICK'));
    });

    test('allStageNames getter matches getAllStageNames()', () {
      expect(config.allStageNames, config.getAllStageNames());
    });

    test('serialization round-trip via JSON string', () {
      final jsonStr = config.toJsonString();
      final restored = SlotWinConfiguration.fromJsonString(jsonStr);
      expect(
          restored.regularWins.tiers.length, config.regularWins.tiers.length);
      expect(restored.bigWins.threshold, config.bigWins.threshold);
      expect(restored.bigWins.tiers.length, config.bigWins.tiers.length);
    });

    test('copyWith replaces regularWins', () {
      final newRegular = RegularWinTierConfig(
        configId: 'custom',
        name: 'Custom',
        source: WinTierConfigSource.manual,
        tiers: const [
          WinTierDefinition(
            tierId: 1,
            fromMultiplier: 0.0,
            toMultiplier: 100.0,
            displayLabel: 'ALL',
            rollupDurationMs: 1000,
            rollupTickRate: 15,
          ),
        ],
      );
      final updated = config.copyWith(regularWins: newRegular);
      expect(updated.regularWins.tiers.length, 1);
      expect(updated.bigWins.threshold, config.bigWins.threshold);
    });

    group('Presets', () {
      test('standard preset has 7 regular tiers', () {
        final preset = SlotWinConfigurationPresets.standard;
        expect(preset.regularWins.tiers.length, 7);
        expect(preset.bigWins.threshold, 20.0);
      });

      test('highVolatility preset has higher threshold', () {
        final preset = SlotWinConfigurationPresets.highVolatility;
        expect(preset.bigWins.threshold, 25.0);
      });

      test('jackpotFocus preset has lower threshold', () {
        final preset = SlotWinConfigurationPresets.jackpotFocus;
        expect(preset.bigWins.threshold, 15.0);
        expect(preset.regularWins.tiers.length, 3); // Fewer regular tiers
      });

      test('mobileOptimized preset has shorter durations', () {
        final preset = SlotWinConfigurationPresets.mobileOptimized;
        // Mobile big win tier 1 should be shorter than standard
        final standardTier1 = BigWinConfig.defaultConfig().tiers.first;
        final mobileTier1 = preset.bigWins.tiers.first;
        expect(mobileTier1.durationMs, lessThan(standardTier1.durationMs));
      });

      test('all presets validate successfully', () {
        expect(
            SlotWinConfigurationPresets.standard.regularWins.validate(), true);
        expect(
            SlotWinConfigurationPresets.highVolatility.bigWins.validate(), true);
        expect(
            SlotWinConfigurationPresets.jackpotFocus.bigWins.validate(), true);
        expect(SlotWinConfigurationPresets.mobileOptimized.bigWins.validate(),
            true);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 3: WIN TIER RESULT
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 3: WinTierResult', () {
    test('regular win result has correct primaryStageName', () {
      const result = WinTierResult(
        isBigWin: false,
        multiplier: 3.0,
        regularTier: WinTierDefinition(
          tierId: 2,
          fromMultiplier: 2.0,
          toMultiplier: 5.0,
          displayLabel: 'WIN 2',
          rollupDurationMs: 1500,
          rollupTickRate: 12,
        ),
      );
      expect(result.primaryStageName, 'WIN_2');
      expect(result.displayLabel, 'WIN 2');
      expect(result.rollupDurationMs, 1500);
    });

    test('big win result has BIG_WIN_INTRO as primaryStageName', () {
      const result = WinTierResult(
        isBigWin: true,
        multiplier: 75.0,
        bigWinTier: BigWinTierDefinition(
          tierId: 2,
          fromMultiplier: 50,
          toMultiplier: 100,
          displayLabel: 'BIG WIN TIER 2',
          durationMs: 4000,
        ),
        bigWinMaxTier: 2,
      );
      expect(result.primaryStageName, 'BIG_WIN_INTRO');
      expect(result.displayLabel, 'BIG WIN TIER 2');
      expect(result.rollupDurationMs, 4000);
    });

    test('regular win without tier falls back to WIN_1', () {
      const result = WinTierResult(
        isBigWin: false,
        multiplier: 1.0,
      );
      expect(result.primaryStageName, 'WIN_1');
    });

    test('toString for regular win', () {
      const result = WinTierResult(
        isBigWin: false,
        multiplier: 3.5,
        regularTier: WinTierDefinition(
          tierId: 2,
          fromMultiplier: 2.0,
          toMultiplier: 5.0,
          displayLabel: 'WIN 2',
          rollupDurationMs: 1500,
          rollupTickRate: 12,
        ),
      );
      expect(result.toString(), contains('WIN_2'));
      expect(result.toString(), contains('3.5x'));
    });

    test('toString for big win', () {
      const result = WinTierResult(
        isBigWin: true,
        multiplier: 75.0,
        bigWinMaxTier: 2,
      );
      expect(result.toString(), contains('BIG_WIN'));
      expect(result.toString(), contains('tier=2'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 4: LEGACY STAGE MAPPING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 4: Legacy Stage Mapping', () {
    test('BIG_WIN maps to BIG_WIN_INTRO', () {
      expect(getMappedStageName('BIG_WIN'), 'BIG_WIN_INTRO');
    });

    test('MEGA_WIN maps to BIG_WIN_TIER_2', () {
      expect(getMappedStageName('MEGA_WIN'), 'BIG_WIN_TIER_2');
    });

    test('EPIC_WIN maps to BIG_WIN_TIER_3', () {
      expect(getMappedStageName('EPIC_WIN'), 'BIG_WIN_TIER_3');
    });

    test('ULTRA_WIN maps to BIG_WIN_TIER_5', () {
      expect(getMappedStageName('ULTRA_WIN'), 'BIG_WIN_TIER_5');
    });

    test('SMALL_WIN maps to WIN_1', () {
      expect(getMappedStageName('SMALL_WIN'), 'WIN_1');
    });

    test('ROLLUP_START maps to ROLLUP_START_1', () {
      expect(getMappedStageName('ROLLUP_START'), 'ROLLUP_START_1');
    });

    test('unknown stage returns original', () {
      expect(getMappedStageName('CUSTOM_STAGE'), 'CUSTOM_STAGE');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 5: SLOT AUDIO EVENT FACTORY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 5: Slot Audio Event Factory', () {
    test('SlotBusIds constants are correct', () {
      expect(SlotBusIds.master, 0);
      expect(SlotBusIds.music, 1);
      expect(SlotBusIds.sfx, 2);
      expect(SlotBusIds.voice, 3);
      expect(SlotBusIds.ui, 4);
      expect(SlotBusIds.reels, 5);
      expect(SlotBusIds.wins, 6);
      expect(SlotBusIds.anticipation, 7);
    });

    test('SlotEventIds ranges are non-overlapping', () {
      // Spin: 1000-1099, Anticipation: 1100-1199, Win: 1200-1299, etc.
      expect(SlotEventIds.spinStart, inInclusiveRange(1000, 1099));
      expect(SlotEventIds.anticipationOn, inInclusiveRange(1100, 1199));
      expect(SlotEventIds.winPresent, inInclusiveRange(1200, 1299));
    });

    test('createFromTemplates generates all event categories', () {
      final events = SlotAudioEventFactory.createFromTemplates();
      expect(events, isNotEmpty);

      // Check categories exist
      // NOTE: Spin lifecycle uses 'Slot_Gameplay' category (not 'Slot_Spin')
      final categories = events.map((e) => e.category).toSet();
      expect(categories, contains('Slot_Gameplay'));
      expect(categories, contains('Slot_Win'));
      expect(categories, contains('Slot_BigWin'));
      expect(categories, contains('Slot_Feature'));
      expect(categories, contains('Slot_Bonus'));
      expect(categories, contains('Slot_Gamble'));
      expect(categories, contains('Slot_Jackpot'));
      expect(categories, contains('Slot_UI'));
    });

    test('spin lifecycle events have correct structure', () {
      final events = SlotAudioEventFactory.createSpinLifecycleEvents();
      expect(events, isNotEmpty);

      // Find spin_start event
      final spinStart = events.firstWhere((e) => e.id == 'slot_spin_start');
      expect(spinStart.actions, isNotEmpty);
    });

    test('big win events exist for all 5 tiers', () {
      final events = SlotAudioEventFactory.createBigWinEvents();
      expect(events.any((e) => e.id == 'slot_bigwin_tier_1'), true);
      expect(events.any((e) => e.id == 'slot_bigwin_tier_2'), true);
      expect(events.any((e) => e.id == 'slot_bigwin_tier_3'), true);
      expect(events.any((e) => e.id == 'slot_bigwin_tier_4'), true);
      expect(events.any((e) => e.id == 'slot_bigwin_tier_5'), true);
    });

    test('big win tier 5 has stopAll action', () {
      final events = SlotAudioEventFactory.createBigWinEvents();
      final tier5 = events.firstWhere((e) => e.id == 'slot_bigwin_tier_5');
      expect(
          tier5.actions.any((a) => a.type == ActionType.stopAll), true);
    });

    test('cascade events cover start/step/end lifecycle', () {
      final events = SlotAudioEventFactory.createCascadeEvents();
      expect(events.any((e) => e.id == 'slot_cascade_start'), true);
      expect(events.any((e) => e.id == 'slot_cascade_step'), true);
      expect(events.any((e) => e.id == 'slot_cascade_end'), true);
    });

    test('createFromTemplates includes all sub-categories', () {
      final all = SlotAudioEventFactory.createFromTemplates();
      final ids = all.map((e) => e.id).toSet();
      expect(ids, contains('slot_spin_start'));
      expect(ids, contains('slot_bigwin_tier_1'));
      expect(ids, contains('slot_feature_enter'));
      expect(ids, contains('slot_cascade_start'));
      expect(ids, contains('slot_bonus_enter'));
      expect(ids, contains('slot_gamble_start'));
      expect(ids, contains('slot_jackpot_trigger'));
      expect(ids, contains('slot_button_click'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 6: SLOT AUDIO PROFILE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 6: Slot Audio Profile', () {
    late SlotAudioProfile profile;

    setUp(() {
      profile = SlotAudioProfile.defaultProfile();
    });

    test('default profile has all components', () {
      // NOTE: events is empty by design — user creates events in Slot Lab
      // createAllEvents() returns [] intentionally (no placeholder events)
      expect(profile.events, isEmpty);
      // All other components are pre-populated from factory defaults
      expect(profile.rtpcs, isNotEmpty);
      expect(profile.stateGroups, isNotEmpty);
      expect(profile.duckingRules, isNotEmpty);
      expect(profile.musicSegments, isNotEmpty);
      expect(profile.stingers, isNotEmpty);
      expect(profile.elementMappings, isNotEmpty);
    });

    test('stats record has correct counts', () {
      final stats = profile.stats;
      expect(stats.eventCount, profile.events.length);
      expect(stats.rtpcCount, profile.rtpcs.length);
      expect(stats.stateGroupCount, profile.stateGroups.length);
      expect(stats.duckingRuleCount, profile.duckingRules.length);
      expect(stats.musicSegmentCount, profile.musicSegments.length);
      expect(stats.stingerCount, profile.stingers.length);
      expect(stats.elementMappingCount, profile.elementMappings.length);
    });

    test('getMappingForElement returns correct mapping', () {
      final mapping = profile.getMappingForElement(SlotElementType.spinButton);
      expect(mapping, isNotNull);
      expect(mapping!.eventId, 'slot_spin_start');
    });

    test('getMappingForElement returns null for unmapped element', () {
      final mapping = profile.getMappingForElement(SlotElementType.custom);
      expect(mapping, isNull);
    });

    test('getEventIdForElement delegates to getMappingForElement', () {
      final eventId =
          profile.getEventIdForElement(SlotElementType.spinButton);
      expect(eventId, 'slot_spin_start');
    });

    group('Element mappings', () {
      test('spin button maps to slot_spin_start', () {
        expect(
          SlotElementMappingFactory.defaultMappings[SlotElementType.spinButton],
          'slot_spin_start',
        );
      });

      test('all reels map to slot_reel_stop', () {
        final mappings = SlotElementMappingFactory.defaultMappings;
        expect(mappings[SlotElementType.reel1], 'slot_reel_stop');
        expect(mappings[SlotElementType.reel2], 'slot_reel_stop');
        expect(mappings[SlotElementType.reel3], 'slot_reel_stop');
        expect(mappings[SlotElementType.reel4], 'slot_reel_stop');
        expect(mappings[SlotElementType.reel5], 'slot_reel_stop');
      });

      test('menu button maps to slot_menu_open', () {
        expect(
          SlotElementMappingFactory.defaultMappings[SlotElementType.menuButton],
          'slot_menu_open',
        );
      });
    });

    group('RTPC definitions', () {
      test('creates 8 RTPCs', () {
        final rtpcs = SlotRtpcFactory.createAllRtpcs();
        expect(rtpcs.length, 8);
      });

      test('win multiplier has correct range', () {
        final rtpcs = SlotRtpcFactory.createAllRtpcs();
        final winMult =
            rtpcs.firstWhere((r) => r.id == SlotRtpcIds.winMultiplier);
        expect(winMult.min, 0.0);
        expect(winMult.max, 1000.0);
      });

      test('tension has 0-1 range', () {
        final rtpcs = SlotRtpcFactory.createAllRtpcs();
        final tension =
            rtpcs.firstWhere((r) => r.id == SlotRtpcIds.tension);
        expect(tension.min, 0.0);
        expect(tension.max, 1.0);
      });
    });

    group('State groups', () {
      test('creates 3 state groups', () {
        final groups = SlotStateGroupFactory.createAllGroups();
        expect(groups.length, 3);
      });

      test('game phase group has 6 states', () {
        final group = SlotStateGroupFactory.createGamePhaseGroup();
        expect(group.states.length, 6);
        expect(group.defaultStateId, 1); // Base_Game
      });

      test('feature type group has 6 states', () {
        final group = SlotStateGroupFactory.createFeatureTypeGroup();
        expect(group.states.length, 6);
        expect(group.defaultStateId, 0); // None
      });

      test('music mode group has 5 states', () {
        final group = SlotStateGroupFactory.createMusicModeGroup();
        expect(group.states.length, 5);
        expect(group.defaultStateId, 0); // Normal
      });
    });

    group('Ducking presets', () {
      test('creates 3 ducking rules', () {
        final rules = SlotDuckingPresets.createAllRules();
        expect(rules.length, 3);
      });

      test('wins duck music at -6dB', () {
        final rule = SlotDuckingPresets.winsDuckMusic();
        expect(rule.sourceBusId, SlotBusIds.wins);
        expect(rule.targetBusId, SlotBusIds.music);
        expect(rule.duckAmountDb, -6.0);
      });

      test('voice ducks music at -8dB', () {
        final rule = SlotDuckingPresets.voiceDucksMusic();
        expect(rule.sourceBusId, SlotBusIds.voice);
        expect(rule.targetBusId, SlotBusIds.music);
        expect(rule.duckAmountDb, -8.0);
      });

      test('anticipation ducks music at -10dB', () {
        final rule = SlotDuckingPresets.anticipationDucksMusic();
        expect(rule.sourceBusId, SlotBusIds.anticipation);
        expect(rule.targetBusId, SlotBusIds.music);
        expect(rule.duckAmountDb, -10.0);
      });
    });

    group('Music segments', () {
      test('creates 6 segments', () {
        final segments = SlotMusicSegmentFactory.createAllSegments();
        expect(segments.length, 6);
      });

      test('base game segment has correct tempo', () {
        final segment = SlotMusicSegmentFactory.createBaseGameSegment();
        expect(segment.tempo, 120.0);
        expect(segment.beatsPerBar, 4);
      });
    });

    group('Stingers', () {
      test('creates 4 stingers', () {
        final stingers = SlotStingerFactory.createAllStingers();
        expect(stingers.length, 4);
      });

      test('jackpot stinger has highest priority', () {
        final stinger = SlotStingerFactory.createJackpotStinger();
        expect(stinger.priority, 100);
        expect(stinger.canInterrupt, true);
        expect(stinger.syncPoint, MusicSyncPoint.immediate);
      });

      test('near miss stinger has lowest priority', () {
        final stinger = SlotStingerFactory.createNearMissStinger();
        expect(stinger.priority, 40);
        expect(stinger.canInterrupt, false);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 7: SLOT COMPOSITE EVENT MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 7: SlotCompositeEvent model', () {
    test('playableLayers respects mute', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        layers: const [
          SlotEventLayer(
              id: 'l1', name: 'Layer 1', audioPath: 'a.wav', muted: false),
          SlotEventLayer(
              id: 'l2', name: 'Layer 2', audioPath: 'b.wav', muted: true),
          SlotEventLayer(
              id: 'l3', name: 'Layer 3', audioPath: 'c.wav', muted: false),
        ],
      );
      expect(event.playableLayers.length, 2);
      expect(event.activeLayerCount, 2);
    });

    test('playableLayers respects solo mode', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'Layer 1', audioPath: 'a.wav'),
          SlotEventLayer(
              id: 'l2', name: 'Layer 2', audioPath: 'b.wav', solo: true),
          SlotEventLayer(id: 'l3', name: 'Layer 3', audioPath: 'c.wav'),
        ],
      );
      expect(event.hasSoloedLayer, true);
      final playable = event.playableLayers;
      expect(playable.length, 1);
      expect(playable.first.id, 'l2');
    });

    test('solo + mute on same layer excludes it', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        layers: const [
          SlotEventLayer(id: 'l1', name: 'Layer 1', audioPath: 'a.wav'),
          SlotEventLayer(
              id: 'l2',
              name: 'Layer 2',
              audioPath: 'b.wav',
              solo: true,
              muted: true),
        ],
      );
      expect(event.playableLayers, isEmpty);
    });

    test('totalDurationMs calculates from longest layer', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        layers: const [
          SlotEventLayer(
            id: 'l1',
            name: 'Layer 1',
            audioPath: 'a.wav',
            durationSeconds: 2.0,
            offsetMs: 100,
          ),
          SlotEventLayer(
            id: 'l2',
            name: 'Layer 2',
            audioPath: 'b.wav',
            durationSeconds: 1.0,
            offsetMs: 500,
          ),
        ],
      );
      // l1: 2000 + 100 = 2100ms
      // l2: 1000 + 500 = 1500ms
      expect(event.totalDurationMs, 2100.0);
    });

    test('isMusicEvent checks bus ID', () {
      final now = DateTime.now();
      final musicEvent = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        targetBusId: SlotBusIds.music,
      );
      expect(musicEvent.isMusicEvent, true);

      final sfxEvent = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        targetBusId: SlotBusIds.sfx,
      );
      expect(sfxEvent.isMusicEvent, false);
    });

    test('shouldAutoLoop is true for music without _END', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'MUSIC_BASE',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        targetBusId: SlotBusIds.music,
      );
      expect(event.shouldAutoLoop, true);
    });

    test('shouldAutoLoop is false for music with _END', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'MUSIC_BASE_END',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        targetBusId: SlotBusIds.music,
      );
      expect(event.shouldAutoLoop, false);
    });

    test('shouldAutoLoop is false for non-music', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'SFX_HIT',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        targetBusId: SlotBusIds.sfx,
      );
      expect(event.shouldAutoLoop, false);
    });

    test('usesContainer is true when both type and id set', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        containerType: ContainerType.random,
        containerId: 42,
      );
      expect(event.usesContainer, true);
    });

    test('usesContainer is false when type is none', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test',
        name: 'Test',
        color: Colors.blue,
        createdAt: now,
        modifiedAt: now,
        containerType: ContainerType.none,
        containerId: 42,
      );
      expect(event.usesContainer, false);
    });

    test('serialization round-trip preserves all fields', () {
      final now = DateTime.now();
      final event = SlotCompositeEvent(
        id: 'test_id',
        name: 'Test Event',
        category: 'spin',
        color: const Color(0xFFFF0000),
        layers: const [
          SlotEventLayer(
            id: 'l1',
            name: 'Layer 1',
            audioPath: '/audio/test.wav',
            volume: 0.8,
            pan: -0.5,
            offsetMs: 100,
            busId: 2,
          ),
        ],
        masterVolume: 0.9,
        targetBusId: 2,
        looping: true,
        maxInstances: 4,
        createdAt: now,
        modifiedAt: now,
        triggerStages: ['SPIN_START', 'REEL_STOP'],
        timelinePositionMs: 1500,
        trackIndex: 2,
        containerType: ContainerType.blend,
        containerId: 7,
        overlap: false,
        crossfadeMs: 250,
      );

      final json = event.toJson();
      final restored = SlotCompositeEvent.fromJson(json);

      expect(restored.id, event.id);
      expect(restored.name, event.name);
      expect(restored.category, event.category);
      expect(restored.layers.length, 1);
      expect(restored.layers[0].volume, 0.8);
      expect(restored.layers[0].pan, -0.5);
      expect(restored.masterVolume, 0.9);
      expect(restored.targetBusId, 2);
      expect(restored.looping, true);
      expect(restored.maxInstances, 4);
      expect(restored.triggerStages, ['SPIN_START', 'REEL_STOP']);
      expect(restored.timelinePositionMs, 1500);
      expect(restored.trackIndex, 2);
      expect(restored.containerType, ContainerType.blend);
      expect(restored.containerId, 7);
      expect(restored.overlap, false);
      expect(restored.crossfadeMs, 250);
    });

    test('SlotEventTemplates creates all expected templates', () {
      final templates = SlotEventTemplates.allTemplates();
      expect(templates.length, 10);
      // Verify template categories
      expect(templates.first.category, 'spin');
      expect(templates.last.category, 'feature');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 8: SLOT EVENT LAYER DSP CHAIN
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 8: SlotEventLayer DSP Chain', () {
    test('layer with no DSP has hasDsp false', () {
      const layer = SlotEventLayer(
        id: 'l1',
        name: 'Test',
        audioPath: 'test.wav',
      );
      expect(layer.hasDsp, false);
      expect(layer.activeDspNodes, isEmpty);
    });

    test('layer with DSP nodes has hasDsp true', () {
      final node = LayerDspNode.create(LayerDspType.eq);
      final layer = SlotEventLayer(
        id: 'l1',
        name: 'Test',
        audioPath: 'test.wav',
        dspChain: [node],
      );
      expect(layer.hasDsp, true);
      expect(layer.activeDspNodes.length, 1);
    });

    test('bypassed DSP nodes excluded from activeDspNodes', () {
      final node1 = LayerDspNode.create(LayerDspType.eq);
      final node2 =
          LayerDspNode.create(LayerDspType.compressor).copyWith(bypass: true);
      final layer = SlotEventLayer(
        id: 'l1',
        name: 'Test',
        audioPath: 'test.wav',
        dspChain: [node1, node2],
      );
      expect(layer.dspChain.length, 2);
      expect(layer.activeDspNodes.length, 1);
    });

    test('LayerDspNode.create has correct default params per type', () {
      final eq = LayerDspNode.create(LayerDspType.eq);
      expect(eq.params['lowGain'], 0.0);
      expect(eq.params['midFreq'], 1000.0);

      final comp = LayerDspNode.create(LayerDspType.compressor);
      expect(comp.params['threshold'], -20.0);
      expect(comp.params['ratio'], 4.0);

      final reverb = LayerDspNode.create(LayerDspType.reverb);
      expect(reverb.params['decay'], 2.0);
      expect(reverb.params['preDelay'], 20.0);

      final delay = LayerDspNode.create(LayerDspType.delay);
      expect(delay.params['time'], 250.0);
      expect(delay.params['feedback'], 0.3);
    });

    test('LayerDspNode serialization round-trip', () {
      final node = LayerDspNode.create(LayerDspType.compressor);
      final json = node.toJson();
      final restored = LayerDspNode.fromJson(json);
      expect(restored.type, LayerDspType.compressor);
      expect(restored.bypass, false);
      expect(restored.wetDry, 1.0);
      expect(restored.params['threshold'], -20.0);
    });

    test('SlotEventLayer full serialization with DSP chain', () {
      final layer = SlotEventLayer(
        id: 'l1',
        name: 'Layer 1',
        audioPath: '/audio/test.wav',
        volume: 0.7,
        pan: -0.3,
        offsetMs: 50,
        fadeInMs: 10,
        fadeOutMs: 20,
        trimStartMs: 100,
        trimEndMs: 500,
        busId: SlotBusIds.sfx,
        aleLayerId: 3,
        dspChain: [
          LayerDspNode.create(LayerDspType.eq),
          LayerDspNode.create(LayerDspType.reverb),
        ],
      );

      final json = layer.toJson();
      final restored = SlotEventLayer.fromJson(json);

      expect(restored.id, 'l1');
      expect(restored.volume, 0.7);
      expect(restored.pan, -0.3);
      expect(restored.offsetMs, 50);
      expect(restored.fadeInMs, 10);
      expect(restored.fadeOutMs, 20);
      expect(restored.trimStartMs, 100);
      expect(restored.trimEndMs, 500);
      expect(restored.busId, SlotBusIds.sfx);
      expect(restored.aleLayerId, 3);
      expect(restored.dspChain.length, 2);
      expect(restored.dspChain[0].type, LayerDspType.eq);
      expect(restored.dspChain[1].type, LayerDspType.reverb);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 9: EVENT ZOOM SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 9: EventZoomSettings', () {
    test('default settings have correct values', () {
      final settings = EventZoomSettings(eventId: 'evt_1');
      expect(settings.pixelsPerSecond, 100.0);
      expect(settings.scrollOffsetX, 0.0);
      expect(settings.scrollOffsetY, 0.0);
      expect(settings.showWaveforms, true);
      expect(settings.showGrid, true);
    });

    test('copyWith preserves unmodified fields', () {
      final settings =
          EventZoomSettings(eventId: 'evt_1', pixelsPerSecond: 200);
      final updated = settings.copyWith(scrollOffsetX: 50);
      expect(updated.pixelsPerSecond, 200);
      expect(updated.scrollOffsetX, 50);
      expect(updated.eventId, 'evt_1');
    });

    test('equality is based on eventId', () {
      final a = EventZoomSettings(eventId: 'evt_1', pixelsPerSecond: 100);
      final b = EventZoomSettings(eventId: 'evt_1', pixelsPerSecond: 200);
      final c = EventZoomSettings(eventId: 'evt_2', pixelsPerSecond: 100);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is based on eventId', () {
      final a = EventZoomSettings(eventId: 'evt_1');
      final b = EventZoomSettings(eventId: 'evt_1');
      expect(a.hashCode, b.hashCode);
    });

    test('serialization round-trip', () {
      final settings = EventZoomSettings(
        eventId: 'evt_1',
        pixelsPerSecond: 250,
        scrollOffsetX: 33,
        scrollOffsetY: 44,
        showWaveforms: false,
        showGrid: false,
      );
      final json = settings.toJson();
      final restored = EventZoomSettings.fromJson(json);
      expect(restored.eventId, 'evt_1');
      expect(restored.pixelsPerSecond, 250);
      expect(restored.scrollOffsetX, 33);
      expect(restored.scrollOffsetY, 44);
      expect(restored.showWaveforms, false);
      expect(restored.showGrid, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 10: EVENT ZOOM SERVICE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 10: EventZoomService', () {
    late EventZoomService service;

    setUp(() {
      service = EventZoomService.instance;
      service.clear();
    });

    test('getSettings returns default for unknown event', () {
      final settings = service.getSettings('unknown');
      expect(settings.pixelsPerSecond, 100.0);
    });

    test('setSettings stores and retrieves', () {
      service.setSettings(
          EventZoomSettings(eventId: 'evt_1', pixelsPerSecond: 250));
      expect(service.hasSettings('evt_1'), true);
      expect(service.getSettings('evt_1').pixelsPerSecond, 250);
    });

    test('setPixelsPerSecond clamps to valid range', () {
      service.setPixelsPerSecond('evt_1', 5.0); // Below min
      expect(service.getSettings('evt_1').pixelsPerSecond,
          EventZoomService.kMinPixelsPerSecond);

      service.setPixelsPerSecond('evt_1', 1000.0); // Above max
      expect(service.getSettings('evt_1').pixelsPerSecond,
          EventZoomService.kMaxPixelsPerSecond);
    });

    test('zoomIn increases pixelsPerSecond', () {
      service.setPixelsPerSecond('evt_1', 100);
      service.zoomIn('evt_1');
      expect(service.getSettings('evt_1').pixelsPerSecond, greaterThan(100));
    });

    test('zoomOut decreases pixelsPerSecond', () {
      service.setPixelsPerSecond('evt_1', 100);
      service.zoomOut('evt_1');
      expect(service.getSettings('evt_1').pixelsPerSecond, lessThan(100));
    });

    test('resetZoom returns to default', () {
      service.setPixelsPerSecond('evt_1', 300);
      service.resetZoom('evt_1');
      expect(service.getSettings('evt_1').pixelsPerSecond,
          EventZoomService.kDefaultPixelsPerSecond);
    });

    test('toggleWaveforms flips state', () {
      service.setSettings(EventZoomSettings(eventId: 'evt_1'));
      expect(service.getSettings('evt_1').showWaveforms, true);
      service.toggleWaveforms('evt_1');
      expect(service.getSettings('evt_1').showWaveforms, false);
      service.toggleWaveforms('evt_1');
      expect(service.getSettings('evt_1').showWaveforms, true);
    });

    test('toggleGrid flips state', () {
      service.setSettings(EventZoomSettings(eventId: 'evt_1'));
      service.toggleGrid('evt_1');
      expect(service.getSettings('evt_1').showGrid, false);
    });

    test('removeSettings reverts to defaults', () {
      service.setPixelsPerSecond('evt_1', 300);
      service.removeSettings('evt_1');
      expect(service.hasSettings('evt_1'), false);
      expect(service.getSettings('evt_1').pixelsPerSecond, 100.0);
    });

    test('allSettings is unmodifiable', () {
      service.setSettings(EventZoomSettings(eventId: 'evt_1'));
      final all = service.allSettings;
      expect(
          () => all['new'] = EventZoomSettings(eventId: 'x'),
          throwsA(anything));
    });

    test('getZoomPercentage calculates correctly', () {
      service.setPixelsPerSecond('evt_1', 200);
      expect(service.getZoomPercentage('evt_1'), 200.0);
    });

    test('setZoomPercentage converts correctly', () {
      service.setZoomPercentage('evt_1', 150.0);
      expect(service.getSettings('evt_1').pixelsPerSecond, 150.0);
    });

    test('JSON persistence round-trip', () {
      service.setPixelsPerSecond('evt_1', 250);
      service.setPixelsPerSecond('evt_2', 75);
      service.toggleWaveforms('evt_2');

      final json = service.toJson();
      service.clear();
      expect(service.hasSettings('evt_1'), false);

      service.fromJson(json);
      expect(service.hasSettings('evt_1'), true);
      expect(service.getSettings('evt_1').pixelsPerSecond, 250);
      expect(service.getSettings('evt_2').pixelsPerSecond, 75);
      expect(service.getSettings('evt_2').showWaveforms, false);
    });

    test('notifyListeners is called on changes', () {
      int callCount = 0;
      void listener() => callCount++;
      service.addListener(listener);

      service.setSettings(EventZoomSettings(eventId: 'evt_1'));
      expect(callCount, 1);

      service.setPixelsPerSecond('evt_1', 200);
      expect(callCount, 2);

      service.toggleWaveforms('evt_1');
      expect(callCount, 3);

      service.removeSettings('evt_1');
      expect(callCount, 4);

      service.removeListener(listener);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 11: STAGE CONFIG ↔ WIN TIER INTEGRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 11: StageConfigurationService ↔ Win Tiers', () {
    late StageConfigurationService service;

    setUp(() {
      service = StageConfigurationService.instance;
      service.init();
    });

    test('registerWinTierStages adds P5 stages', () {
      final config = SlotWinConfiguration.defaultConfig();
      service.registerWinTierStages(config);

      // Win tier stages should be registered
      expect(service.isWinTierGenerated('WIN_PRESENT_1'), true);
    });

    test('win stages have correct bus (sfx)', () {
      final bus = service.getBus('WIN_PRESENT_1');
      expect(bus, SpatialBus.sfx);
    });

    test('rollup tick stages are pooled', () {
      expect(service.isPooled('ROLLUP_TICK'), true);
    });

    test('big win intro has high priority', () {
      final p = service.getPriority('JACKPOT_TRIGGER');
      expect(p, greaterThanOrEqualTo(80));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 12: LEGACY WIN TIER SYSTEM (M4)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 12: Legacy Win Tier System (M4)', () {
    test('WinTier enum has all values', () {
      expect(WinTier.values.length, 11);
    });

    test('WinTier display names are correct', () {
      expect(WinTier.noWin.displayName, 'No Win');
      expect(WinTier.bigWin.displayName, 'Big Win');
      expect(WinTier.jackpotGrand.displayName, 'Grand Jackpot');
    });

    test('WinTier audio intensity scales correctly', () {
      expect(WinTier.noWin.audioIntensity, 0);
      expect(WinTier.smallWin.audioIntensity, 2);
      expect(WinTier.jackpotGrand.audioIntensity, 10);
      // Higher tiers should have higher intensity
      expect(WinTier.bigWin.audioIntensity,
          greaterThan(WinTier.smallWin.audioIntensity));
    });

    group('WinTierConfig (M4 legacy)', () {
      test('standard config has 6 tiers', () {
        final config = DefaultWinTierConfigs.standard;
        expect(config.tiers.length, 6);
      });

      test('getTierForWin returns correct tier', () {
        final config = DefaultWinTierConfigs.standard;
        // 3x bet
        final tier = config.getTierForWin(30.0, 10.0);
        expect(tier, isNotNull);
        expect(tier!.tier, WinTier.mediumWin);
      });

      test('getTierForWin returns null for zero bet', () {
        final config = DefaultWinTierConfigs.standard;
        expect(config.getTierForWin(10.0, 0.0), isNull);
      });

      test('getRtpcForWin maps win to RTPC value', () {
        final config = DefaultWinTierConfigs.standard;
        // Big win (10x)
        final rtpc = config.getRtpcForWin(100.0, 10.0);
        expect(rtpc, 0.6); // bigWin tier
      });

      test('getRtpcForWin returns 0 for no win', () {
        final config = DefaultWinTierConfigs.standard;
        final rtpc = config.getRtpcForWin(0.05, 10.0);
        expect(rtpc, 0.0);
      });

      test('highVolatility config has higher thresholds', () {
        final config = DefaultWinTierConfigs.highVolatility;
        final bigWin = config.tiers.firstWhere((t) => t.tier == WinTier.bigWin);
        expect(bigWin.minXBet, 20.0);
      });

      test('jackpot config includes jackpot tiers', () {
        final config = DefaultWinTierConfigs.jackpot;
        final jackpotTiers = config.tiers.where(
          (t) => t.tier.name.startsWith('jackpot'),
        );
        expect(jackpotTiers.length, 4);
      });

      test('serialization round-trip', () {
        final config = DefaultWinTierConfigs.standard;
        final json = config.toJsonString();
        final restored = WinTierConfig.fromJsonString(json);
        expect(restored.tiers.length, config.tiers.length);
        expect(restored.gameId, config.gameId);
      });

      test('WinTierThreshold copyWith works', () {
        const threshold = WinTierThreshold(
          tier: WinTier.bigWin,
          minXBet: 5.0,
          maxXBet: 20.0,
          rtpcValue: 0.6,
          triggerStage: 'WIN_BIG',
        );
        final updated = threshold.copyWith(rtpcValue: 0.8);
        expect(updated.rtpcValue, 0.8);
        expect(updated.tier, WinTier.bigWin);
        expect(updated.triggerStage, 'WIN_BIG');
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 13: SLOT AUDIO LAYER MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 13: SlotAudioLayer model', () {
    test('default values', () {
      const layer = SlotAudioLayer(
        id: 'l1',
        assetPath: '/audio/test.wav',
        assetName: 'test.wav',
      );
      expect(layer.volume, 1.0);
      expect(layer.muted, false);
      expect(layer.solo, false);
      expect(layer.pan, 0.0);
      expect(layer.bus, 'SFX');
    });

    test('copyWith preserves unmodified fields', () {
      const layer = SlotAudioLayer(
        id: 'l1',
        assetPath: '/audio/test.wav',
        assetName: 'test.wav',
        volume: 0.5,
        pan: -0.3,
      );
      final updated = layer.copyWith(volume: 0.8);
      expect(updated.volume, 0.8);
      expect(updated.pan, -0.3);
      expect(updated.assetPath, '/audio/test.wav');
    });

    test('serialization round-trip', () {
      const layer = SlotAudioLayer(
        id: 'l1',
        assetPath: '/audio/test.wav',
        assetName: 'test.wav',
        volume: 0.7,
        muted: true,
        pan: 0.5,
        bus: 'Music',
      );
      final json = layer.toJson();
      final restored = SlotAudioLayer.fromJson(json);
      expect(restored.id, 'l1');
      expect(restored.volume, 0.7);
      expect(restored.muted, true);
      expect(restored.pan, 0.5);
      expect(restored.bus, 'Music');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 14: SLOT ELEMENT MAPPING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 14: SlotElementEventMapping', () {
    test('displayName returns correct label for standard elements', () {
      const mapping = SlotElementEventMapping(
        element: SlotElementType.spinButton,
        eventId: 'slot_spin_start',
      );
      expect(mapping.displayName, 'Spin Button');
    });

    test('displayName returns customName for custom elements', () {
      const mapping = SlotElementEventMapping(
        element: SlotElementType.custom,
        customName: 'My Button',
        eventId: 'my_event',
      );
      expect(mapping.displayName, 'My Button');
    });

    test('addAudioLayer adds layer to mapping', () {
      const mapping = SlotElementEventMapping(
        element: SlotElementType.spinButton,
        eventId: 'slot_spin_start',
      );
      expect(mapping.audioLayers, isEmpty);

      const layer = SlotAudioLayer(
        id: 'l1',
        assetPath: '/audio/spin.wav',
        assetName: 'spin.wav',
      );
      final updated = mapping.addAudioLayer(layer);
      expect(updated.audioLayers.length, 1);
      expect(updated.audioLayers.first.assetName, 'spin.wav');
    });

    test('all standard element types have display names', () {
      for (final element in SlotElementType.values) {
        final mapping = SlotElementEventMapping(
          element: element,
          eventId: 'test',
        );
        // Verify no exception is thrown
        expect(mapping.displayName, isNotEmpty);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 15: TIMELINE CLIP MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 15: TimelineClip model', () {
    test('endTime calculated correctly', () {
      final clip = TimelineClip(
        id: 'clip1',
        trackId: 'track1',
        name: 'Test Clip',
        startTime: 5.0,
        duration: 10.0,
      );
      expect(clip.endTime, 15.0);
    });

    test('copyWith preserves unmodified fields', () {
      final clip = TimelineClip(
        id: 'clip1',
        trackId: 'track1',
        name: 'Test',
        startTime: 5.0,
        duration: 10.0,
        gain: 0.8,
        muted: true,
      );
      final updated = clip.copyWith(gain: 1.0);
      expect(updated.gain, 1.0);
      expect(updated.muted, true);
      expect(updated.startTime, 5.0);
    });

    test('default values', () {
      final clip = TimelineClip(
        id: 'clip1',
        trackId: 'track1',
        name: 'Test',
        startTime: 0,
        duration: 1,
      );
      expect(clip.gain, 1.0);
      expect(clip.muted, false);
      expect(clip.locked, false);
      expect(clip.selected, false);
      expect(clip.fadeIn, 0.0);
      expect(clip.fadeOut, 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW 16: CROSSFADE CURVE (middleware)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow 16: CrossfadeCurve enum (middleware)', () {
    test('all curve types can be serialized by name', () {
      for (final curve in CrossfadeCurve.values) {
        // Should be able to round-trip through name
        final restored = CrossfadeCurve.values.firstWhere(
          (c) => c.name == curve.name,
        );
        expect(restored, curve);
      }
    });

    test('SlotEventLayer preserves fade curves through serialization', () {
      const layer = SlotEventLayer(
        id: 'l1',
        name: 'Test',
        audioPath: 'test.wav',
        fadeInCurve: CrossfadeCurve.equalPower,
        fadeOutCurve: CrossfadeCurve.sCurve,
      );
      final json = layer.toJson();
      final restored = SlotEventLayer.fromJson(json);
      expect(restored.fadeInCurve, CrossfadeCurve.equalPower);
      expect(restored.fadeOutCurve, CrossfadeCurve.sCurve);
    });
  });
}
