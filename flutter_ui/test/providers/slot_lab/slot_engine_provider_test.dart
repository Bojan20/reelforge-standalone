// SlotEngineProvider — Pure Dart Unit Tests
//
// Tests for the synthetic slot engine state management provider.
// Covers:
// - Initial state defaults
// - Volatility configuration (slider clamping, preset->slider computation)
// - Bet amount configuration (clamping at boundaries)
// - Feature toggles (cascades, free spins, jackpot, P5 win tier)
// - Win tier configuration
// - Anticipation pre-trigger (clamping 0-200)
// - Grid size changes (notifies only when changed)
// - Derived getters when no result
// - Timing profile configuration
// - Notification behavior (listener count verification)
//
// NOTE: These are PURE DART tests. NO FFI calls.
// SlotEngineProvider depends on NativeFFI which is unavailable in test context.
// We test ONLY the state management logic — setters, getters, clamping,
// notification. FFI-dependent methods (initialize, spin, shutdown) are NOT
// tested here.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/slot_lab/slot_engine_provider.dart';
import 'package:fluxforge_ui/models/win_tier_config.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart'
    show VolatilityPreset, TimingProfileType;

void main() {
  late SlotEngineProvider provider;

  setUp(() {
    provider = SlotEngineProvider();
  });

  tearDown(() {
    provider.dispose();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. INITIAL STATE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Initial state', () {
    test('initialized is false', () {
      expect(provider.initialized, false);
    });

    test('isSpinning is false', () {
      expect(provider.isSpinning, false);
    });

    test('spinCount is 0', () {
      expect(provider.spinCount, 0);
    });

    test('lastResult is null', () {
      expect(provider.lastResult, isNull);
    });

    test('lastStages is empty', () {
      expect(provider.lastStages, isEmpty);
    });

    test('stats is null', () {
      expect(provider.stats, isNull);
    });

    test('rtp is 0.0', () {
      expect(provider.rtp, 0.0);
    });

    test('hitRate is 0.0', () {
      expect(provider.hitRate, 0.0);
    });

    test('volatilitySlider is 0.5', () {
      expect(provider.volatilitySlider, 0.5);
    });

    test('volatilityPreset is medium', () {
      expect(provider.volatilityPreset, VolatilityPreset.medium);
    });

    test('timingProfile is normal', () {
      expect(provider.timingProfile, TimingProfileType.normal);
    });

    test('betAmount is 1.0', () {
      expect(provider.betAmount, 1.0);
    });

    test('cascadesEnabled is true', () {
      expect(provider.cascadesEnabled, true);
    });

    test('freeSpinsEnabled is true', () {
      expect(provider.freeSpinsEnabled, true);
    });

    test('jackpotEnabled is true', () {
      expect(provider.jackpotEnabled, true);
    });

    test('useP5WinTier is true', () {
      expect(provider.useP5WinTier, true);
    });

    test('inFreeSpins is false', () {
      expect(provider.inFreeSpins, false);
    });

    test('freeSpinsRemaining is 0', () {
      expect(provider.freeSpinsRemaining, 0);
    });

    test('totalReels is 5', () {
      expect(provider.totalReels, 5);
    });

    test('totalRows is 3', () {
      expect(provider.totalRows, 3);
    });

    test('engineV2Initialized is false', () {
      expect(provider.engineV2Initialized, false);
    });

    test('currentGameModel is null', () {
      expect(provider.currentGameModel, isNull);
    });

    test('availableScenarios is empty', () {
      expect(provider.availableScenarios, isEmpty);
    });

    test('loadedScenarioId is null', () {
      expect(provider.loadedScenarioId, isNull);
    });

    test('slotWinConfig uses P5 default config', () {
      expect(provider.slotWinConfig.regularWins.configId, 'default');
      expect(provider.slotWinConfig.bigWins.threshold, 20.0);
    });

    test('anticipationPreTriggerMs is 0', () {
      expect(provider.anticipationPreTriggerMs, 0);
    });

    test('timingConfig is null initially (FFI not loaded)', () {
      expect(provider.timingConfig, isNull);
    });

    test('totalAudioOffsetMs defaults to 5.0 when timingConfig is null', () {
      expect(provider.totalAudioOffsetMs, 5.0);
    });

    test('cachedStagesSpinId is null', () {
      expect(provider.cachedStagesSpinId, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. VOLATILITY CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Volatility configuration', () {
    group('setVolatilitySlider', () {
      test('sets slider value', () {
        provider.setVolatilitySlider(0.7);
        expect(provider.volatilitySlider, 0.7);
      });

      test('clamps value at lower bound (0.0)', () {
        provider.setVolatilitySlider(-0.5);
        expect(provider.volatilitySlider, 0.0);
      });

      test('clamps value at upper bound (1.0)', () {
        provider.setVolatilitySlider(1.5);
        expect(provider.volatilitySlider, 1.0);
      });

      test('clamps negative infinity to 0.0', () {
        provider.setVolatilitySlider(double.negativeInfinity);
        expect(provider.volatilitySlider, 0.0);
      });

      test('clamps positive infinity to 1.0', () {
        provider.setVolatilitySlider(double.infinity);
        expect(provider.volatilitySlider, 1.0);
      });

      test('accepts exact lower boundary 0.0', () {
        provider.setVolatilitySlider(0.0);
        expect(provider.volatilitySlider, 0.0);
      });

      test('accepts exact upper boundary 1.0', () {
        provider.setVolatilitySlider(1.0);
        expect(provider.volatilitySlider, 1.0);
      });

      test('preserves precision for mid-range values', () {
        provider.setVolatilitySlider(0.333);
        expect(provider.volatilitySlider, 0.333);
      });

      test('notifies listeners', () {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setVolatilitySlider(0.8);
        expect(notifyCount, 1);
      });
    });

    group('setVolatilityPreset', () {
      test('sets preset to low', () {
        provider.setVolatilityPreset(VolatilityPreset.low);
        expect(provider.volatilityPreset, VolatilityPreset.low);
      });

      test('sets preset to medium', () {
        provider.setVolatilityPreset(VolatilityPreset.medium);
        expect(provider.volatilityPreset, VolatilityPreset.medium);
      });

      test('sets preset to high', () {
        provider.setVolatilityPreset(VolatilityPreset.high);
        expect(provider.volatilityPreset, VolatilityPreset.high);
      });

      test('sets preset to studio', () {
        provider.setVolatilityPreset(VolatilityPreset.studio);
        expect(provider.volatilityPreset, VolatilityPreset.studio);
      });

      test('computes slider = preset.value / 3.0 for low (0/3.0 = 0.0)', () {
        provider.setVolatilityPreset(VolatilityPreset.low);
        expect(provider.volatilitySlider, VolatilityPreset.low.value / 3.0);
        expect(provider.volatilitySlider, 0.0);
      });

      test('computes slider = preset.value / 3.0 for medium (1/3.0)', () {
        provider.setVolatilityPreset(VolatilityPreset.medium);
        expect(provider.volatilitySlider,
            closeTo(VolatilityPreset.medium.value / 3.0, 0.0001));
      });

      test('computes slider = preset.value / 3.0 for high (2/3.0)', () {
        provider.setVolatilityPreset(VolatilityPreset.high);
        expect(provider.volatilitySlider,
            closeTo(VolatilityPreset.high.value / 3.0, 0.0001));
      });

      test('computes slider = preset.value / 3.0 for studio (3/3.0 = 1.0)',
          () {
        provider.setVolatilityPreset(VolatilityPreset.studio);
        expect(provider.volatilitySlider, 1.0);
      });

      test('notifies listeners', () {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setVolatilityPreset(VolatilityPreset.high);
        expect(notifyCount, 1);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. BET AMOUNT CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Bet amount configuration', () {
    test('sets bet amount to valid value', () {
      provider.setBetAmount(5.0);
      expect(provider.betAmount, 5.0);
    });

    test('clamps at lower bound (0.01)', () {
      provider.setBetAmount(0.001);
      expect(provider.betAmount, 0.01);
    });

    test('clamps at upper bound (1000.0)', () {
      provider.setBetAmount(2000.0);
      expect(provider.betAmount, 1000.0);
    });

    test('clamps zero to 0.01', () {
      provider.setBetAmount(0.0);
      expect(provider.betAmount, 0.01);
    });

    test('clamps negative to 0.01', () {
      provider.setBetAmount(-10.0);
      expect(provider.betAmount, 0.01);
    });

    test('accepts exact lower boundary 0.01', () {
      provider.setBetAmount(0.01);
      expect(provider.betAmount, 0.01);
    });

    test('accepts exact upper boundary 1000.0', () {
      provider.setBetAmount(1000.0);
      expect(provider.betAmount, 1000.0);
    });

    test('preserves precision for typical bets', () {
      provider.setBetAmount(0.25);
      expect(provider.betAmount, 0.25);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setBetAmount(10.0);
      expect(notifyCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. FEATURE TOGGLES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Feature toggles', () {
    group('cascadesEnabled', () {
      test('initially true', () {
        expect(provider.cascadesEnabled, true);
      });

      test('can be disabled', () {
        provider.setCascadesEnabled(false);
        expect(provider.cascadesEnabled, false);
      });

      test('can be re-enabled', () {
        provider.setCascadesEnabled(false);
        provider.setCascadesEnabled(true);
        expect(provider.cascadesEnabled, true);
      });

      test('notifies listeners on change', () {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setCascadesEnabled(false);
        expect(notifyCount, 1);
      });

      test('notifies even when setting same value', () {
        // Provider always calls notifyListeners regardless of value change
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setCascadesEnabled(true); // same as default
        expect(notifyCount, 1);
      });
    });

    group('freeSpinsEnabled', () {
      test('initially true', () {
        expect(provider.freeSpinsEnabled, true);
      });

      test('can be disabled', () {
        provider.setFreeSpinsEnabled(false);
        expect(provider.freeSpinsEnabled, false);
      });

      test('can be re-enabled', () {
        provider.setFreeSpinsEnabled(false);
        provider.setFreeSpinsEnabled(true);
        expect(provider.freeSpinsEnabled, true);
      });

      test('notifies listeners on change', () {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setFreeSpinsEnabled(false);
        expect(notifyCount, 1);
      });
    });

    group('jackpotEnabled', () {
      test('initially true', () {
        expect(provider.jackpotEnabled, true);
      });

      test('can be disabled', () {
        provider.setJackpotEnabled(false);
        expect(provider.jackpotEnabled, false);
      });

      test('can be re-enabled', () {
        provider.setJackpotEnabled(false);
        provider.setJackpotEnabled(true);
        expect(provider.jackpotEnabled, true);
      });

      test('notifies listeners on change', () {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setJackpotEnabled(false);
        expect(notifyCount, 1);
      });
    });

    group('useP5WinTier', () {
      test('initially true', () {
        expect(provider.useP5WinTier, true);
      });

      test('can be disabled', () {
        provider.setUseP5WinTier(false);
        expect(provider.useP5WinTier, false);
      });

      test('can be re-enabled', () {
        provider.setUseP5WinTier(false);
        provider.setUseP5WinTier(true);
        expect(provider.useP5WinTier, true);
      });

      test('notifies listeners on change', () {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        provider.setUseP5WinTier(false);
        expect(notifyCount, 1);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. WIN TIER CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Win tier configuration (P5)', () {
    test('default is P5 standard config', () {
      expect(provider.slotWinConfig.regularWins.configId, 'default');
    });

    test('setSlotWinConfig updates config', () {
      final customConfig = SlotWinConfigurationPresets.highVolatility;
      provider.setSlotWinConfig(customConfig);
      expect(provider.slotWinConfig.regularWins.configId, 'high_volatility');
    });

    test('setSlotWinConfig to jackpot config', () {
      provider.setSlotWinConfig(SlotWinConfigurationPresets.jackpotFocus);
      expect(provider.slotWinConfig.regularWins.configId, 'jackpot');
    });

    test('setSlotWinConfig notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setSlotWinConfig(SlotWinConfigurationPresets.highVolatility);
      expect(notifyCount, 1);
    });

    test('P5 config has regular and big win tiers', () {
      final config = provider.slotWinConfig;
      expect(config.regularWins.tiers.length, greaterThan(0));
      // Default preset is the 8-tier ladder; custom presets may use 5.
      expect(config.bigWins.tiers.length, anyOf(5, 8));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. ANTICIPATION PRE-TRIGGER
  // ═══════════════════════════════════════════════════════════════════════════

  group('Anticipation pre-trigger', () {
    test('initially 0', () {
      expect(provider.anticipationPreTriggerMs, 0);
    });

    test('sets valid value', () {
      provider.setAnticipationPreTriggerMs(50);
      expect(provider.anticipationPreTriggerMs, 50);
    });

    test('clamps at lower bound (0)', () {
      provider.setAnticipationPreTriggerMs(-10);
      expect(provider.anticipationPreTriggerMs, 0);
    });

    test('clamps at upper bound (200)', () {
      provider.setAnticipationPreTriggerMs(300);
      expect(provider.anticipationPreTriggerMs, 200);
    });

    test('accepts exact lower boundary 0', () {
      provider.setAnticipationPreTriggerMs(0);
      expect(provider.anticipationPreTriggerMs, 0);
    });

    test('accepts exact upper boundary 200', () {
      provider.setAnticipationPreTriggerMs(200);
      expect(provider.anticipationPreTriggerMs, 200);
    });

    test('accepts mid-range value 100', () {
      provider.setAnticipationPreTriggerMs(100);
      expect(provider.anticipationPreTriggerMs, 100);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setAnticipationPreTriggerMs(75);
      expect(notifyCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. GRID SIZE CHANGES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Grid size changes', () {
    test('default grid is 5x3', () {
      expect(provider.totalReels, 5);
      expect(provider.totalRows, 3);
    });

    test('updateGridSize changes reels', () {
      provider.updateGridSize(6, 3);
      expect(provider.totalReels, 6);
      expect(provider.totalRows, 3);
    });

    test('updateGridSize changes rows', () {
      provider.updateGridSize(5, 4);
      expect(provider.totalReels, 5);
      expect(provider.totalRows, 4);
    });

    test('updateGridSize changes both', () {
      provider.updateGridSize(7, 6);
      expect(provider.totalReels, 7);
      expect(provider.totalRows, 6);
    });

    test('notifies listeners when dimensions change', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.updateGridSize(6, 4);
      expect(notifyCount, 1);
    });

    test('does NOT notify when setting same dimensions', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.updateGridSize(5, 3); // same as default
      expect(notifyCount, 0);
    });

    test('notifies when only reels change', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.updateGridSize(6, 3); // only reels changed
      expect(notifyCount, 1);
    });

    test('notifies when only rows change', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.updateGridSize(5, 4); // only rows changed
      expect(notifyCount, 1);
    });

    test('consecutive updates only notify on actual changes', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.updateGridSize(6, 4); // change -> notify
      provider.updateGridSize(6, 4); // no change -> no notify
      provider.updateGridSize(7, 4); // change -> notify

      expect(notifyCount, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. DERIVED GETTERS (when no result)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Derived getters when no result', () {
    test('currentGrid is null', () {
      expect(provider.currentGrid, isNull);
    });

    test('lastSpinWasWin is false', () {
      expect(provider.lastSpinWasWin, false);
    });

    test('lastWinAmount is 0.0', () {
      expect(provider.lastWinAmount, 0.0);
    });

    test('lastWinRatio is 0.0', () {
      expect(provider.lastWinRatio, 0.0);
    });

    test('lastBigWinTier is null', () {
      expect(provider.lastBigWinTier, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. TIMING PROFILE CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Timing profile configuration', () {
    test('default is normal', () {
      expect(provider.timingProfile, TimingProfileType.normal);
    });

    test('setTimingProfile to turbo', () {
      provider.setTimingProfile(TimingProfileType.turbo);
      expect(provider.timingProfile, TimingProfileType.turbo);
    });

    test('setTimingProfile to mobile', () {
      provider.setTimingProfile(TimingProfileType.mobile);
      expect(provider.timingProfile, TimingProfileType.mobile);
    });

    test('setTimingProfile to studio', () {
      provider.setTimingProfile(TimingProfileType.studio);
      expect(provider.timingProfile, TimingProfileType.studio);
    });

    test('setTimingProfile back to normal', () {
      provider.setTimingProfile(TimingProfileType.studio);
      provider.setTimingProfile(TimingProfileType.normal);
      expect(provider.timingProfile, TimingProfileType.normal);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.setTimingProfile(TimingProfileType.turbo);
      expect(notifyCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. NOTIFICATION BEHAVIOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('Notification behavior', () {
    test('multiple listeners all receive notification', () {
      int listener1Count = 0;
      int listener2Count = 0;
      int listener3Count = 0;

      provider.addListener(() => listener1Count++);
      provider.addListener(() => listener2Count++);
      provider.addListener(() => listener3Count++);

      provider.setBetAmount(5.0);

      expect(listener1Count, 1);
      expect(listener2Count, 1);
      expect(listener3Count, 1);
    });

    test('removed listener does not receive notification', () {
      int activeCount = 0;
      int removedCount = 0;

      void activeListener() => activeCount++;
      void removedListener() => removedCount++;

      provider.addListener(activeListener);
      provider.addListener(removedListener);

      provider.setBetAmount(2.0); // both receive
      expect(activeCount, 1);
      expect(removedCount, 1);

      provider.removeListener(removedListener);
      provider.setBetAmount(3.0); // only active receives

      expect(activeCount, 2);
      expect(removedCount, 1);
    });

    test('each setter independently notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setVolatilitySlider(0.3);
      provider.setBetAmount(2.0);
      provider.setCascadesEnabled(false);
      provider.setFreeSpinsEnabled(false);
      provider.setJackpotEnabled(false);
      provider.setUseP5WinTier(false);
      provider.setAnticipationPreTriggerMs(50);
      provider.setTimingProfile(TimingProfileType.turbo);
      provider.setVolatilityPreset(VolatilityPreset.high);
      provider.setSlotWinConfig(SlotWinConfigurationPresets.highVolatility);

      expect(notifyCount, 10);
    });

    test('updateGridSize does not notify when unchanged', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      // No change from default 5x3
      provider.updateGridSize(5, 3);
      expect(notifyCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 11. WIN TIER HELPERS (state-only, when uninitialized)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Win tier helpers (P5)', () {
    test('getVisualTierForWin returns WIN_LOW for sub-bet win', () {
      provider.setBetAmount(1.0);
      // 0.5x bet → WIN_LOW tier
      final tier = provider.getVisualTierForWin(0.5);
      expect(tier, 'WIN_LOW');
    });

    test('getVisualTierForWin returns WIN_1 for small win', () {
      provider.setBetAmount(1.0);
      // 1.5x bet → WIN_1 tier (1.001x-2x)
      final tier = provider.getVisualTierForWin(1.5);
      expect(tier, 'WIN_1');
    });

    test('getVisualTierForWin returns BIG_WIN_TIER_1 for 25x', () {
      provider.setBetAmount(1.0);
      // 25x → BIG Win Tier 1 (20x-50x)
      final tier = provider.getVisualTierForWin(25.0);
      expect(tier, 'BIG_WIN_TIER_1');
    });

    test('getVisualTierForWin returns BIG_WIN_TIER_2 for 60x', () {
      provider.setBetAmount(1.0);
      // 60x → BIG Win Tier 2 (50x-100x)
      final tier = provider.getVisualTierForWin(60.0);
      expect(tier, 'BIG_WIN_TIER_2');
    });

    test('getVisualTierForWin returns WIN_LOW for 0 win', () {
      // WIN_LOW tier spans 0..1x bet, so a zero win hits it (sub-bet win).
      final tier = provider.getVisualTierForWin(0.0);
      expect(tier, 'WIN_LOW');
    });

    test('getRtpcForWin returns 0.0 for no win', () {
      final rtpc = provider.getRtpcForWin(0.0);
      expect(rtpc, 0.0);
    });

    test('getRtpcForWin returns value for valid win', () {
      provider.setBetAmount(1.0);
      final rtpc = provider.getRtpcForWin(5.0);
      expect(rtpc, greaterThan(0.0));
    });

    test('shouldTriggerCelebration false for regular win', () {
      provider.setBetAmount(1.0);
      expect(provider.shouldTriggerCelebration(5.0), false);
    });

    test('shouldTriggerCelebration true for big win (20x+)', () {
      provider.setBetAmount(1.0);
      expect(provider.shouldTriggerCelebration(25.0), true);
    });

    test('getRollupDurationMs returns WIN_LOW duration for 0 win', () {
      // 0 win is a sub-bet win → WIN_LOW tier which is configured as an
      // instant rollup (rollupDurationMs = 0) to avoid UI hang on zero wins.
      expect(provider.getRollupDurationMs(0.0), 0);
    });

    test('getRollupDurationMs returns tier duration for big wins', () {
      provider.setBetAmount(1.0);
      final dur = provider.getRollupDurationMs(25.0);
      expect(dur, greaterThan(1000));
    });

    test('getTriggerStageForWin returns WIN_PRESENT_LOW for zero win', () {
      // Zero win falls into the WIN_LOW tier (sub-bet). Its present stage
      // is WIN_PRESENT_LOW; UI still shows a muted acknowledgement rather
      // than complete silence.
      expect(provider.getTriggerStageForWin(0.0), 'WIN_PRESENT_LOW');
    });

    test('getTriggerStageForWin returns present stage for valid win', () {
      provider.setBetAmount(1.0);
      final stage = provider.getTriggerStageForWin(1.5);
      expect(stage, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 12. CALLBACK SETUP
  // ═══════════════════════════════════════════════════════════════════════════

  group('Callback setup', () {
    test('onSpinComplete callback is null by default', () {
      expect(provider.onSpinComplete, isNull);
    });

    test('onGridDimensionsChanged callback is null by default', () {
      expect(provider.onGridDimensionsChanged, isNull);
    });

    test('onSpinComplete can be assigned', () {
      bool called = false;
      provider.onSpinComplete = (result, stages) {
        called = true;
      };
      expect(provider.onSpinComplete, isNotNull);
    });

    test('onGridDimensionsChanged can be assigned', () {
      int? receivedCount;
      provider.onGridDimensionsChanged = (count) {
        receivedCount = count;
      };
      expect(provider.onGridDimensionsChanged, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 13. STATE ISOLATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('State isolation', () {
    test('configuration changes are independent', () {
      provider.setVolatilitySlider(0.9);
      provider.setBetAmount(50.0);
      provider.setCascadesEnabled(false);
      provider.setTimingProfile(TimingProfileType.studio);

      // Each value is independently stored
      expect(provider.volatilitySlider, 0.9);
      expect(provider.betAmount, 50.0);
      expect(provider.cascadesEnabled, false);
      expect(provider.timingProfile, TimingProfileType.studio);

      // Other values remain at defaults
      expect(provider.freeSpinsEnabled, true);
      expect(provider.jackpotEnabled, true);
      expect(provider.useP5WinTier, true);
      expect(provider.totalReels, 5);
      expect(provider.totalRows, 3);
    });

    test('multiple instances do not share state', () {
      final provider2 = SlotEngineProvider();

      provider.setBetAmount(100.0);
      provider.setCascadesEnabled(false);

      // Second instance retains defaults
      expect(provider2.betAmount, 1.0);
      expect(provider2.cascadesEnabled, true);

      provider2.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 14. FFI-GUARDED METHODS (when not initialized)
  // ═══════════════════════════════════════════════════════════════════════════

  group('FFI-guarded methods when not initialized', () {
    test('exportConfig returns null when not initialized', () {
      expect(provider.exportConfig(), isNull);
    });

    test('importConfig returns false when not initialized', () {
      expect(provider.importConfig('{}'), false);
    });

    test('resetStats still notifies (even when not initialized)', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.resetStats();
      expect(notifyCount, 1);
    });

    test('seedRng does nothing when not initialized (no crash)', () {
      // Should not throw
      provider.seedRng(42);
    });

    test('shutdown does nothing when not initialized (no crash)', () {
      // Should not throw
      provider.shutdown();
    });
  });
}
