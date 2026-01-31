// P5 Win Tier Configuration System Unit Tests
//
// Tests for WinTierDefinition, BigWinTierDefinition, RegularWinTierConfig,
// BigWinConfig, SlotWinConfiguration, and WinTierResult models.
// These tests do NOT require FFI - they test pure Dart models.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/win_tier_config.dart';

void main() {
  group('WinTierDefinition', () {
    test('stageName generates correct names for tier IDs', () {
      expect(
        const WinTierDefinition(
          tierId: -1,
          fromMultiplier: 0.0,
          toMultiplier: 1.0,
          displayLabel: 'Win',
          rollupDurationMs: 800,
          rollupTickRate: 20,
        ).stageName,
        'WIN_LOW',
      );
      expect(
        const WinTierDefinition(
          tierId: 0,
          fromMultiplier: 1.0,
          toMultiplier: 1.001,
          displayLabel: 'Push',
          rollupDurationMs: 1000,
          rollupTickRate: 15,
        ).stageName,
        'WIN_EQUAL',
      );
      expect(
        const WinTierDefinition(
          tierId: 3,
          fromMultiplier: 5.0,
          toMultiplier: 10.0,
          displayLabel: 'Great Win',
          rollupDurationMs: 2000,
          rollupTickRate: 10,
        ).stageName,
        'WIN_3',
      );
    });

    test('presentStageName generates correct names', () {
      expect(
        const WinTierDefinition(
          tierId: -1,
          fromMultiplier: 0.0,
          toMultiplier: 1.0,
          displayLabel: 'Win',
          rollupDurationMs: 800,
          rollupTickRate: 20,
        ).presentStageName,
        'WIN_PRESENT_LOW',
      );
      expect(
        const WinTierDefinition(
          tierId: 0,
          fromMultiplier: 1.0,
          toMultiplier: 1.001,
          displayLabel: 'Push',
          rollupDurationMs: 1000,
          rollupTickRate: 15,
        ).presentStageName,
        'WIN_PRESENT_EQUAL',
      );
      expect(
        const WinTierDefinition(
          tierId: 2,
          fromMultiplier: 2.0,
          toMultiplier: 5.0,
          displayLabel: 'Good Win',
          rollupDurationMs: 1500,
          rollupTickRate: 12,
        ).presentStageName,
        'WIN_PRESENT_2',
      );
    });

    test('matches returns true for multipliers in range', () {
      final tier = const WinTierDefinition(
        tierId: 2,
        fromMultiplier: 2.0,
        toMultiplier: 5.0,
        displayLabel: 'Good Win',
        rollupDurationMs: 1500,
        rollupTickRate: 12,
      );

      // Win of $30 with bet of $10 = 3x multiplier
      expect(tier.matches(30.0, 10.0), isTrue);

      // Win of $20 with bet of $10 = 2x multiplier (inclusive from)
      expect(tier.matches(20.0, 10.0), isTrue);

      // Win of $49 with bet of $10 = 4.9x multiplier
      expect(tier.matches(49.0, 10.0), isTrue);

      // Win of $50 with bet of $10 = 5x multiplier (exclusive to)
      expect(tier.matches(50.0, 10.0), isFalse);

      // Win of $15 with bet of $10 = 1.5x multiplier (below range)
      expect(tier.matches(15.0, 10.0), isFalse);
    });

    test('serialization roundtrip preserves all fields', () {
      const original = WinTierDefinition(
        tierId: 3,
        fromMultiplier: 5.0,
        toMultiplier: 10.0,
        displayLabel: 'Great Win',
        rollupDurationMs: 2000,
        rollupTickRate: 10,
        particleBurstCount: 50,
      );

      final json = original.toJson();
      final restored = WinTierDefinition.fromJson(json);

      expect(restored.tierId, original.tierId);
      expect(restored.fromMultiplier, original.fromMultiplier);
      expect(restored.toMultiplier, original.toMultiplier);
      expect(restored.displayLabel, original.displayLabel);
      expect(restored.rollupDurationMs, original.rollupDurationMs);
      expect(restored.rollupTickRate, original.rollupTickRate);
      expect(restored.particleBurstCount, original.particleBurstCount);
    });

    test('copyWith creates modified copy', () {
      const original = WinTierDefinition(
        tierId: 1,
        fromMultiplier: 1.0,
        toMultiplier: 2.0,
        displayLabel: 'Nice Win',
        rollupDurationMs: 1200,
        rollupTickRate: 15,
      );

      final modified = original.copyWith(
        displayLabel: 'Updated Label',
        rollupDurationMs: 1500,
      );

      expect(modified.tierId, 1); // Unchanged
      expect(modified.displayLabel, 'Updated Label'); // Changed
      expect(modified.rollupDurationMs, 1500); // Changed
      expect(modified.rollupTickRate, 15); // Unchanged
    });
  });

  group('BigWinTierDefinition', () {
    test('stageName generates correct names', () {
      const tier = BigWinTierDefinition(
        tierId: 3,
        fromMultiplier: 60.0,
        toMultiplier: 100.0,
        displayLabel: 'MEGA WIN',
        durationMs: 8000,
        rollupTickRate: 8,
      );
      expect(tier.stageName, 'BIG_WIN_TIER_3');
    });

    test('matches returns true for multipliers in range', () {
      const tier = BigWinTierDefinition(
        tierId: 1,
        fromMultiplier: 20.0,
        toMultiplier: 40.0,
        displayLabel: 'BIG WIN',
        durationMs: 3500,
        rollupTickRate: 12,
      );

      // 25x multiplier is in range
      expect(tier.matches(250.0, 10.0), isTrue);

      // 20x is inclusive (from)
      expect(tier.matches(200.0, 10.0), isTrue);

      // 40x is exclusive (to)
      expect(tier.matches(400.0, 10.0), isFalse);

      // 15x is below range
      expect(tier.matches(150.0, 10.0), isFalse);
    });

    test('serialization roundtrip preserves all fields', () {
      const original = BigWinTierDefinition(
        tierId: 2,
        fromMultiplier: 40.0,
        toMultiplier: 80.0,
        displayLabel: 'SUPER WIN',
        durationMs: 6000,
        rollupTickRate: 10,
        visualIntensity: 1.3,
        particleMultiplier: 1.5,
        audioIntensity: 1.2,
      );

      final json = original.toJson();
      final restored = BigWinTierDefinition.fromJson(json);

      expect(restored.tierId, original.tierId);
      expect(restored.fromMultiplier, original.fromMultiplier);
      expect(restored.toMultiplier, original.toMultiplier);
      expect(restored.displayLabel, original.displayLabel);
      expect(restored.durationMs, original.durationMs);
      expect(restored.rollupTickRate, original.rollupTickRate);
      expect(restored.visualIntensity, original.visualIntensity);
      expect(restored.particleMultiplier, original.particleMultiplier);
      expect(restored.audioIntensity, original.audioIntensity);
    });
  });

  group('RegularWinTierConfig', () {
    test('getTierForWin returns correct tier', () {
      final config = RegularWinTierConfig(
        configId: 'test',
        name: 'Test Config',
        source: WinTierConfigSource.manual,
        tiers: const [
          WinTierDefinition(
            tierId: -1,
            fromMultiplier: 0.0,
            toMultiplier: 1.0,
            displayLabel: 'Win',
            rollupDurationMs: 800,
            rollupTickRate: 20,
          ),
          WinTierDefinition(
            tierId: 1,
            fromMultiplier: 1.0,
            toMultiplier: 5.0,
            displayLabel: 'Nice',
            rollupDurationMs: 1200,
            rollupTickRate: 15,
          ),
          WinTierDefinition(
            tierId: 2,
            fromMultiplier: 5.0,
            toMultiplier: 10.0,
            displayLabel: 'Great',
            rollupDurationMs: 2000,
            rollupTickRate: 10,
          ),
        ],
      );

      // 0.5x multiplier ($5 win on $10 bet)
      final tier1 = config.getTierForWin(5.0, 10.0);
      expect(tier1?.tierId, -1);
      expect(tier1?.displayLabel, 'Win');

      // 3x multiplier ($30 win on $10 bet)
      final tier2 = config.getTierForWin(30.0, 10.0);
      expect(tier2?.tierId, 1);
      expect(tier2?.displayLabel, 'Nice');

      // 7x multiplier ($70 win on $10 bet)
      final tier3 = config.getTierForWin(70.0, 10.0);
      expect(tier3?.tierId, 2);
      expect(tier3?.displayLabel, 'Great');

      // 15x multiplier (not in config)
      final tier4 = config.getTierForWin(150.0, 10.0);
      expect(tier4, isNull);
    });

    test('validate returns true for valid config', () {
      final config = RegularWinTierConfig(
        configId: 'valid',
        name: 'Valid',
        source: WinTierConfigSource.builtin,
        tiers: const [
          WinTierDefinition(
            tierId: 1,
            fromMultiplier: 0.0,
            toMultiplier: 5.0,
            displayLabel: 'Low',
            rollupDurationMs: 1000,
            rollupTickRate: 15,
          ),
          WinTierDefinition(
            tierId: 2,
            fromMultiplier: 5.0,
            toMultiplier: 10.0,
            displayLabel: 'Med',
            rollupDurationMs: 1500,
            rollupTickRate: 12,
          ),
        ],
      );
      expect(config.validate(), isTrue);
    });

    test('defaultConfig creates valid configuration', () {
      final config = RegularWinTierConfig.defaultConfig();
      expect(config.tiers.isNotEmpty, isTrue);
      expect(config.validate(), isTrue);
    });
  });

  group('BigWinConfig', () {
    test('isBigWin returns true when multiplier >= threshold', () {
      final config = BigWinConfig(
        threshold: 20.0,
        tiers: const [
          BigWinTierDefinition(
            tierId: 1,
            fromMultiplier: 20.0,
            toMultiplier: double.infinity,
            displayLabel: 'BIG',
            durationMs: 4000,
            rollupTickRate: 10,
          ),
        ],
      );

      // 25x is big win
      expect(config.isBigWin(250.0, 10.0), isTrue);

      // 20x is big win (threshold inclusive)
      expect(config.isBigWin(200.0, 10.0), isTrue);

      // 15x is NOT big win
      expect(config.isBigWin(150.0, 10.0), isFalse);
    });

    test('getMaxTierForWin returns highest matching tier', () {
      final config = BigWinConfig(
        threshold: 20.0,
        tiers: const [
          BigWinTierDefinition(
            tierId: 1,
            fromMultiplier: 20.0,
            toMultiplier: 40.0,
            displayLabel: 'BIG',
            durationMs: 3500,
            rollupTickRate: 12,
          ),
          BigWinTierDefinition(
            tierId: 2,
            fromMultiplier: 40.0,
            toMultiplier: 80.0,
            displayLabel: 'SUPER',
            durationMs: 6000,
            rollupTickRate: 10,
          ),
          BigWinTierDefinition(
            tierId: 3,
            fromMultiplier: 80.0,
            toMultiplier: double.infinity,
            displayLabel: 'MEGA',
            durationMs: 10000,
            rollupTickRate: 8,
          ),
        ],
      );

      // 25x matches tier 1
      expect(config.getMaxTierForWin(250.0, 10.0), 1);

      // 50x matches tier 2
      expect(config.getMaxTierForWin(500.0, 10.0), 2);

      // 100x matches tier 3
      expect(config.getMaxTierForWin(1000.0, 10.0), 3);

      // 15x is NOT big win
      expect(config.getMaxTierForWin(150.0, 10.0), 0);
    });

    test('defaultConfig creates 5 tiers', () {
      final config = BigWinConfig.defaultConfig();
      expect(config.tiers.length, 5);
      expect(config.threshold, 20.0);
    });
  });

  group('SlotWinConfiguration', () {
    test('getRegularTier returns null for big win amounts', () {
      final config = SlotWinConfiguration.defaultConfig();

      // 25x is big win, should return null for regular tier
      final tier = config.getRegularTier(250.0, 10.0);
      expect(tier, isNull);
    });

    test('isBigWin delegates to bigWins.isBigWin', () {
      final config = SlotWinConfiguration.defaultConfig();

      expect(config.isBigWin(250.0, 10.0), isTrue);  // 25x
      expect(config.isBigWin(150.0, 10.0), isFalse); // 15x
    });

    test('allStageNames contains all stage names', () {
      final config = SlotWinConfiguration.defaultConfig();
      final stages = config.allStageNames;

      // Should contain BIG_WIN intro/end
      expect(stages.contains('BIG_WIN_INTRO'), isTrue);
      expect(stages.contains('BIG_WIN_END'), isTrue);

      // Should contain tier stages
      expect(stages.any((s) => s.startsWith('WIN_')), isTrue);
      expect(stages.any((s) => s.startsWith('BIG_WIN_TIER_')), isTrue);
    });

    test('serialization roundtrip preserves configuration', () {
      final original = SlotWinConfiguration.defaultConfig();
      final jsonString = original.toJsonString();
      final restored = SlotWinConfiguration.fromJsonString(jsonString);

      expect(
        restored.regularWins.tiers.length,
        original.regularWins.tiers.length,
      );
      expect(
        restored.bigWins.tiers.length,
        original.bigWins.tiers.length,
      );
      expect(restored.bigWins.threshold, original.bigWins.threshold);
    });
  });

  group('WinTierResult', () {
    test('isBigWin correctly identifies big wins', () {
      const bigWinResult = WinTierResult(
        isBigWin: true,
        multiplier: 25.0,
        regularTier: null,
        bigWinTier: BigWinTierDefinition(
          tierId: 1,
          fromMultiplier: 20.0,
          toMultiplier: 40.0,
          displayLabel: 'BIG WIN',
          durationMs: 3500,
          rollupTickRate: 12,
        ),
        bigWinMaxTier: 1,
      );

      expect(bigWinResult.isBigWin, isTrue);
      expect(bigWinResult.displayLabel, 'BIG WIN');
      expect(bigWinResult.primaryStageName, 'BIG_WIN_INTRO');
    });

    test('regularTier provides correct stage name for regular wins', () {
      const regularWinResult = WinTierResult(
        isBigWin: false,
        multiplier: 3.0,
        regularTier: WinTierDefinition(
          tierId: 2,
          fromMultiplier: 2.0,
          toMultiplier: 5.0,
          displayLabel: 'Good Win',
          rollupDurationMs: 1500,
          rollupTickRate: 12,
        ),
        bigWinTier: null,
        bigWinMaxTier: null,
      );

      expect(regularWinResult.isBigWin, isFalse);
      expect(regularWinResult.displayLabel, 'Good Win');
      expect(regularWinResult.primaryStageName, 'WIN_2');
      expect(regularWinResult.rollupDurationMs, 1500);
    });
  });

  group('SlotWinConfigurationPresets', () {
    test('standard preset is valid', () {
      final preset = SlotWinConfigurationPresets.standard;
      expect(preset.regularWins.validate(), isTrue);
      expect(preset.bigWins.validate(), isTrue);
      expect(preset.regularWins.configId, 'standard');
    });

    test('highVolatility preset has higher threshold', () {
      final preset = SlotWinConfigurationPresets.highVolatility;
      expect(preset.bigWins.threshold, 25.0);
      expect(preset.regularWins.configId, 'high_volatility');
    });

    test('jackpotFocus preset has lower threshold', () {
      final preset = SlotWinConfigurationPresets.jackpotFocus;
      expect(preset.bigWins.threshold, 15.0);
      expect(preset.regularWins.configId, 'jackpot');
    });

    test('mobileOptimized preset has faster durations', () {
      final preset = SlotWinConfigurationPresets.mobileOptimized;
      // Mobile should have shorter durations
      final firstRegularTier = preset.regularWins.tiers.first;
      expect(firstRegularTier.rollupDurationMs, lessThan(600));
    });

    test('all presets have exactly 5 big win tiers', () {
      expect(SlotWinConfigurationPresets.standard.bigWins.tiers.length, 5);
      expect(SlotWinConfigurationPresets.highVolatility.bigWins.tiers.length, 5);
      expect(SlotWinConfigurationPresets.jackpotFocus.bigWins.tiers.length, 5);
      expect(SlotWinConfigurationPresets.mobileOptimized.bigWins.tiers.length, 5);
    });
  });
}
