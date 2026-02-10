// Win Tier Evaluation Integration Tests (P5 System)
//
// Tests: All 4 presets, tier boundary evaluation, big win detection,
// stage name generation, JSON export/import roundtrip, custom tier
// creation, edge cases (0 bet, 0 win, negative, very large).
//
// Pure Dart logic — NO FFI, NO Flutter widgets.
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/win_tier_config.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // WIN TIER DEFINITION
  // ═══════════════════════════════════════════════════════════════════════

  group('WinTierDefinition', () {
    test('stage name generation for special tiers', () {
      const low = WinTierDefinition(
        tierId: -1, fromMultiplier: 0, toMultiplier: 1,
        displayLabel: '', rollupDurationMs: 0, rollupTickRate: 0,
      );
      const equal = WinTierDefinition(
        tierId: 0, fromMultiplier: 1, toMultiplier: 1.001,
        displayLabel: 'PUSH', rollupDurationMs: 500, rollupTickRate: 20,
      );

      expect(low.stageName, 'WIN_LOW');
      expect(low.presentStageName, 'WIN_PRESENT_LOW');
      expect(low.rollupStartStageName, isNull);
      expect(low.rollupTickStageName, isNull);
      expect(low.rollupEndStageName, isNull);

      expect(equal.stageName, 'WIN_EQUAL');
      expect(equal.presentStageName, 'WIN_PRESENT_EQUAL');
      expect(equal.rollupStartStageName, 'ROLLUP_START_EQUAL');
      expect(equal.rollupTickStageName, 'ROLLUP_TICK_EQUAL');
      expect(equal.rollupEndStageName, 'ROLLUP_END_EQUAL');
    });

    test('stage name generation for regular tiers', () {
      for (int i = 1; i <= 5; i++) {
        final tier = WinTierDefinition(
          tierId: i, fromMultiplier: i.toDouble(),
          toMultiplier: (i + 1).toDouble(),
          displayLabel: 'WIN $i',
          rollupDurationMs: 1000 * i,
          rollupTickRate: 15,
        );
        expect(tier.stageName, 'WIN_$i');
        expect(tier.presentStageName, 'WIN_PRESENT_$i');
        expect(tier.rollupStartStageName, 'ROLLUP_START_$i');
        expect(tier.rollupTickStageName, 'ROLLUP_TICK_$i');
        expect(tier.rollupEndStageName, 'ROLLUP_END_$i');
      }
    });

    test('matches() returns true for multiplier in range', () {
      const tier = WinTierDefinition(
        tierId: 2, fromMultiplier: 2.0, toMultiplier: 5.0,
        displayLabel: 'WIN 2', rollupDurationMs: 1500, rollupTickRate: 13,
      );
      // 3x bet = win of 30 on bet of 10
      expect(tier.matches(30, 10), true);
      // Exactly at lower bound
      expect(tier.matches(20, 10), true);
      // Below lower bound
      expect(tier.matches(19, 10), false);
      // At upper bound (exclusive)
      expect(tier.matches(50, 10), false);
    });

    test('matches() returns false for zero bet', () {
      const tier = WinTierDefinition(
        tierId: 1, fromMultiplier: 1.0, toMultiplier: 2.0,
        displayLabel: 'WIN 1', rollupDurationMs: 1000, rollupTickRate: 15,
      );
      expect(tier.matches(100, 0), false);
      expect(tier.matches(0, 0), false);
    });

    test('matches() with negative bet', () {
      const tier = WinTierDefinition(
        tierId: 1, fromMultiplier: 1.0, toMultiplier: 2.0,
        displayLabel: 'WIN 1', rollupDurationMs: 1000, rollupTickRate: 15,
      );
      expect(tier.matches(10, -5), false);
    });

    test('JSON roundtrip', () {
      const tier = WinTierDefinition(
        tierId: 3, fromMultiplier: 4.0, toMultiplier: 8.0,
        displayLabel: 'WIN 3', rollupDurationMs: 2000, rollupTickRate: 12,
        particleBurstCount: 12,
      );
      final json = tier.toJson();
      final restored = WinTierDefinition.fromJson(json);
      expect(restored.tierId, 3);
      expect(restored.fromMultiplier, 4.0);
      expect(restored.toMultiplier, 8.0);
      expect(restored.displayLabel, 'WIN 3');
      expect(restored.rollupDurationMs, 2000);
      expect(restored.rollupTickRate, 12);
      expect(restored.particleBurstCount, 12);
    });

    test('copyWith creates independent copy', () {
      const original = WinTierDefinition(
        tierId: 1, fromMultiplier: 1.0, toMultiplier: 2.0,
        displayLabel: 'WIN 1', rollupDurationMs: 1000, rollupTickRate: 15,
      );
      final copy = original.copyWith(displayLabel: 'MODIFIED');
      expect(copy.displayLabel, 'MODIFIED');
      expect(original.displayLabel, 'WIN 1');
      expect(copy.tierId, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BIG WIN TIER DEFINITION
  // ═══════════════════════════════════════════════════════════════════════

  group('BigWinTierDefinition', () {
    test('stage name generation', () {
      const tier = BigWinTierDefinition(
        tierId: 3, fromMultiplier: 100, toMultiplier: 250,
      );
      expect(tier.stageName, 'BIG_WIN_TIER_3');
    });

    test('matches() for infinity boundary', () {
      const tier = BigWinTierDefinition(
        tierId: 5, fromMultiplier: 500, toMultiplier: double.infinity,
      );
      expect(tier.matches(5000, 10), true); // 500x
      expect(tier.matches(50000, 10), true); // 5000x
      expect(tier.matches(4999, 10), false); // 499.9x
    });

    test('JSON roundtrip with infinity', () {
      const tier = BigWinTierDefinition(
        tierId: 5, fromMultiplier: 500, toMultiplier: double.infinity,
        displayLabel: 'BIG WIN TIER 5',
        durationMs: 4000, rollupTickRate: 4,
        visualIntensity: 2.0, particleMultiplier: 3.0, audioIntensity: 1.5,
      );
      final json = tier.toJson();
      expect(json['toMultiplier'], 'infinity');

      final restored = BigWinTierDefinition.fromJson(json);
      expect(restored.toMultiplier, double.infinity);
      expect(restored.visualIntensity, 2.0);
      expect(restored.particleMultiplier, 3.0);
      expect(restored.audioIntensity, 1.5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // REGULAR WIN TIER CONFIG
  // ═══════════════════════════════════════════════════════════════════════

  group('RegularWinTierConfig', () {
    test('default config has 7 tiers', () {
      final config = RegularWinTierConfig.defaultConfig();
      // WIN_LOW, WIN_EQUAL, WIN_1..5 = 7
      expect(config.tiers.length, 7);
      expect(config.tiers.first.tierId, -1);
      expect(config.tiers.last.tierId, 5);
    });

    test('default config validates (no gaps, no overlaps)', () {
      final config = RegularWinTierConfig.defaultConfig();
      expect(config.validate(), true);
      expect(config.getValidationErrors(), isEmpty);
    });

    test('getTierForWin finds correct tier', () {
      final config = RegularWinTierConfig.defaultConfig();
      // 0.5x bet -> WIN_LOW
      final low = config.getTierForWin(5, 10);
      expect(low?.tierId, -1);

      // 1.5x bet -> WIN_1
      final win1 = config.getTierForWin(15, 10);
      expect(win1?.tierId, 1);

      // 3x bet -> WIN_2
      final win2 = config.getTierForWin(30, 10);
      expect(win2?.tierId, 2);

      // 14x bet -> WIN_5
      final win5 = config.getTierForWin(140, 10);
      expect(win5?.tierId, 5);
    });

    test('getTierForWin returns null beyond range', () {
      final config = RegularWinTierConfig.defaultConfig();
      // 25x bet is beyond WIN_5 (max 20x)
      final result = config.getTierForWin(250, 10);
      expect(result, isNull);
    });

    test('validation detects gaps', () {
      final config = RegularWinTierConfig(
        configId: 'bad',
        name: 'Bad',
        source: WinTierConfigSource.manual,
        tiers: [
          const WinTierDefinition(
            tierId: 1, fromMultiplier: 1.0, toMultiplier: 5.0,
            displayLabel: 'W1', rollupDurationMs: 1000, rollupTickRate: 15,
          ),
          // GAP: 5.0 to 10.0 missing
          const WinTierDefinition(
            tierId: 2, fromMultiplier: 10.0, toMultiplier: 20.0,
            displayLabel: 'W2', rollupDurationMs: 1500, rollupTickRate: 12,
          ),
        ],
      );
      expect(config.validate(), false);
      expect(config.getValidationErrors(), isNotEmpty);
    });

    test('validation detects overlaps', () {
      final config = RegularWinTierConfig(
        configId: 'bad',
        name: 'Bad',
        source: WinTierConfigSource.manual,
        tiers: [
          const WinTierDefinition(
            tierId: 1, fromMultiplier: 1.0, toMultiplier: 8.0,
            displayLabel: 'W1', rollupDurationMs: 1000, rollupTickRate: 15,
          ),
          const WinTierDefinition(
            tierId: 2, fromMultiplier: 5.0, toMultiplier: 15.0,
            displayLabel: 'W2', rollupDurationMs: 1500, rollupTickRate: 12,
          ),
        ],
      );
      expect(config.validate(), false);
    });

    test('JSON roundtrip', () {
      final config = RegularWinTierConfig.defaultConfig();
      final json = config.toJson();
      final restored = RegularWinTierConfig.fromJson(json);
      expect(restored.configId, config.configId);
      expect(restored.name, config.name);
      expect(restored.tiers.length, config.tiers.length);
      expect(restored.source, config.source);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BIG WIN CONFIG
  // ═══════════════════════════════════════════════════════════════════════

  group('BigWinConfig', () {
    test('default config has 5 tiers with 20x threshold', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.tiers.length, 5);
      expect(config.threshold, 20.0);
      expect(config.tiers.first.tierId, 1);
      expect(config.tiers.last.tierId, 5);
    });

    test('isBigWin detects correctly', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.isBigWin(200, 10), true);   // 20x
      expect(config.isBigWin(199, 10), false);   // 19.9x
      expect(config.isBigWin(500, 10), true);    // 50x
    });

    test('isBigWin with zero/negative bet', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.isBigWin(100, 0), false);
      expect(config.isBigWin(100, -5), false);
    });

    test('getMaxTierForWin returns correct tier', () {
      final config = BigWinConfig.defaultConfig();
      // 25x -> Tier 1 (20-50)
      expect(config.getMaxTierForWin(250, 10), 1);
      // 75x -> Tier 2 (50-100)
      expect(config.getMaxTierForWin(750, 10), 2);
      // 150x -> Tier 3 (100-250)
      expect(config.getMaxTierForWin(1500, 10), 3);
      // 300x -> Tier 4 (250-500)
      expect(config.getMaxTierForWin(3000, 10), 4);
      // 600x -> Tier 5 (500+)
      expect(config.getMaxTierForWin(6000, 10), 5);
    });

    test('getMaxTierForWin returns 0 for non-big-win', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.getMaxTierForWin(100, 10), 0);
    });

    test('getTierById returns correct tier', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.getTierById(3)?.tierId, 3);
      expect(config.getTierById(99), isNull);
    });

    test('getTiersForWin returns escalation tiers', () {
      final config = BigWinConfig.defaultConfig();
      // 150x -> Tiers 1, 2, 3
      final tiers = config.getTiersForWin(1500, 10);
      expect(tiers.length, 3);
      expect(tiers.map((t) => t.tierId).toList(), [1, 2, 3]);
    });

    test('static stage names', () {
      expect(BigWinConfig.introStageName, 'BIG_WIN_INTRO');
      expect(BigWinConfig.endStageName, 'BIG_WIN_END');
      expect(BigWinConfig.fadeOutStageName, 'BIG_WIN_FADE_OUT');
      expect(BigWinConfig.rollupTickStageName, 'BIG_WIN_ROLLUP_TICK');
    });

    test('getTotalDurationMs calculates correctly', () {
      final config = BigWinConfig.defaultConfig();
      // 25x -> Tier 1 only
      final dur = config.getTotalDurationMs(250, 10);
      // intro(500) + tier1(4000) + end(4000) + fadeOut(1000) = 9500
      expect(dur, 500 + 4000 + 4000 + 1000);
    });

    test('validate checks tier 1 starts at threshold', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.validate(), true);
    });

    test('JSON roundtrip', () {
      final config = BigWinConfig.defaultConfig();
      final json = config.toJson();
      final restored = BigWinConfig.fromJson(json);
      expect(restored.threshold, config.threshold);
      expect(restored.tiers.length, config.tiers.length);
      expect(restored.introDurationMs, config.introDurationMs);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SLOT WIN CONFIGURATION (COMBINED)
  // ═══════════════════════════════════════════════════════════════════════

  group('SlotWinConfiguration', () {
    test('default config combines regular + big win', () {
      final config = SlotWinConfiguration.defaultConfig();
      expect(config.regularWins.tiers.length, 7);
      expect(config.bigWins.tiers.length, 5);
    });

    test('getRegularTier returns null for big wins', () {
      final config = SlotWinConfiguration.defaultConfig();
      expect(config.getRegularTier(250, 10), isNull); // 25x -> big win
    });

    test('getRegularTier returns tier for regular wins', () {
      final config = SlotWinConfiguration.defaultConfig();
      final tier = config.getRegularTier(30, 10);
      expect(tier, isNotNull);
      expect(tier!.tierId, 2); // 3x bet
    });

    test('getAllStageNames includes all stage types', () {
      final config = SlotWinConfiguration.defaultConfig();
      final stages = config.getAllStageNames();

      // Regular stages
      expect(stages, contains('WIN_LOW'));
      expect(stages, contains('WIN_EQUAL'));
      expect(stages, contains('WIN_1'));
      expect(stages, contains('WIN_5'));
      expect(stages, contains('WIN_PRESENT_1'));
      expect(stages, contains('ROLLUP_TICK_1'));

      // Big win stages
      expect(stages, contains('BIG_WIN_INTRO'));
      expect(stages, contains('BIG_WIN_TIER_1'));
      expect(stages, contains('BIG_WIN_TIER_5'));
      expect(stages, contains('BIG_WIN_END'));
      expect(stages, contains('BIG_WIN_FADE_OUT'));
      expect(stages, contains('BIG_WIN_ROLLUP_TICK'));
    });

    test('allStageNames getter matches method', () {
      final config = SlotWinConfiguration.defaultConfig();
      expect(config.allStageNames, config.getAllStageNames());
    });

    test('JSON string roundtrip', () {
      final config = SlotWinConfiguration.defaultConfig();
      final str = config.toJsonString();
      final restored = SlotWinConfiguration.fromJsonString(str);
      expect(restored.regularWins.tiers.length, config.regularWins.tiers.length);
      expect(restored.bigWins.tiers.length, config.bigWins.tiers.length);
    });

    test('JSON roundtrip via Map', () {
      final config = SlotWinConfiguration.defaultConfig();
      final json = config.toJson();
      final jsonStr = jsonEncode(json);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = SlotWinConfiguration.fromJson(decoded);
      expect(restored.bigWins.threshold, config.bigWins.threshold);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PRESETS
  // ═══════════════════════════════════════════════════════════════════════

  group('SlotWinConfigurationPresets', () {
    test('standard preset: 7 regular tiers, 20x threshold', () {
      final config = SlotWinConfigurationPresets.standard;
      expect(config.regularWins.tiers.length, 7);
      expect(config.bigWins.threshold, 20.0);
      expect(config.regularWins.configId, 'standard');
    });

    test('highVolatility preset: 5 regular tiers, 25x threshold', () {
      final config = SlotWinConfigurationPresets.highVolatility;
      expect(config.regularWins.tiers.length, 5); // LOW, WIN_1..4
      expect(config.bigWins.threshold, 25.0);
    });

    test('jackpotFocus preset: 3 regular tiers, 15x threshold', () {
      final config = SlotWinConfigurationPresets.jackpotFocus;
      expect(config.regularWins.tiers.length, 3);
      expect(config.bigWins.threshold, 15.0);
    });

    test('mobileOptimized preset: 4 regular tiers, 20x threshold', () {
      final config = SlotWinConfigurationPresets.mobileOptimized;
      expect(config.regularWins.tiers.length, 4);
      expect(config.bigWins.threshold, 20.0);
    });

    test('all presets have 5 big win tiers', () {
      final presets = [
        SlotWinConfigurationPresets.standard,
        SlotWinConfigurationPresets.highVolatility,
        SlotWinConfigurationPresets.jackpotFocus,
        SlotWinConfigurationPresets.mobileOptimized,
      ];
      for (final config in presets) {
        expect(config.bigWins.tiers.length, 5,
            reason: 'All presets must have 5 big win tiers');
      }
    });

    test('all presets survive JSON roundtrip', () {
      final presets = [
        SlotWinConfigurationPresets.standard,
        SlotWinConfigurationPresets.highVolatility,
        SlotWinConfigurationPresets.jackpotFocus,
        SlotWinConfigurationPresets.mobileOptimized,
      ];
      for (final config in presets) {
        final json = config.toJsonString();
        final restored = SlotWinConfiguration.fromJsonString(json);
        expect(restored.regularWins.tiers.length,
            config.regularWins.tiers.length);
        expect(restored.bigWins.threshold, config.bigWins.threshold);
        expect(restored.bigWins.tiers.length, config.bigWins.tiers.length);
      }
    });

    test('highVolatility has longer big win durations', () {
      final standard = SlotWinConfigurationPresets.standard;
      final high = SlotWinConfigurationPresets.highVolatility;
      // High vol tier 1 should have longer duration
      expect(high.bigWins.tiers[0].durationMs,
          greaterThanOrEqualTo(standard.bigWins.tiers[0].durationMs));
    });

    test('mobileOptimized has shorter rollup durations', () {
      final standard = SlotWinConfigurationPresets.standard;
      final mobile = SlotWinConfigurationPresets.mobileOptimized;
      // Mobile WIN_1 should have shorter rollup than standard WIN_1
      final stdWin1 = standard.regularWins.tiers
          .firstWhere((t) => t.tierId == 1);
      final mobWin1 = mobile.regularWins.tiers
          .firstWhere((t) => t.tierId == 1);
      expect(mobWin1.rollupDurationMs,
          lessThanOrEqualTo(stdWin1.rollupDurationMs));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('very large win amount (1000x)', () {
      final config = SlotWinConfiguration.defaultConfig();
      expect(config.isBigWin(10000, 10), true);
      expect(config.getBigWinMaxTier(10000, 10), 5);
    });

    test('zero win amount', () {
      final config = SlotWinConfiguration.defaultConfig();
      final tier = config.getRegularTier(0, 10);
      expect(tier?.tierId, -1); // WIN_LOW (0/10 = 0x)
    });

    test('win equals bet exactly', () {
      final config = SlotWinConfiguration.defaultConfig();
      final tier = config.getRegularTier(10, 10);
      expect(tier?.tierId, 0); // WIN_EQUAL (1x)
    });

    test('empty regular config is invalid', () {
      const config = RegularWinTierConfig(
        configId: 'empty', name: 'Empty',
        tiers: [], source: WinTierConfigSource.manual,
      );
      expect(config.validate(), false);
      expect(config.getValidationErrors(), isNotEmpty);
    });

    test('single-tier config is valid', () {
      const config = RegularWinTierConfig(
        configId: 'single', name: 'Single',
        tiers: [
          WinTierDefinition(
            tierId: 1, fromMultiplier: 0, toMultiplier: 20,
            displayLabel: 'WIN', rollupDurationMs: 1000, rollupTickRate: 15,
          ),
        ],
        source: WinTierConfigSource.manual,
      );
      expect(config.validate(), true);
    });
  });
}
