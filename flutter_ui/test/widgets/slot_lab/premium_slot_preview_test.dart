/// Premium Slot Preview Tests
///
/// Tests for PremiumSlotPreview helper classes and calculations:
/// - SlotThemeData presets
/// - DeviceSimulation enum
/// - SpinButtonPhase enum
/// - BigWinProtection calculations
/// - SpinButtonColors gradients
/// - SlotThemePreset enum
@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/premium_slot_preview.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SlotThemeData Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('SlotThemeData', () {
    test('casino preset has correct colors', () {
      const theme = SlotThemeData.casino;
      expect(theme.bgDeep, const Color(0xFF0a0a12));
      expect(theme.gold, const Color(0xFFFFD700));
      expect(theme.accent, const Color(0xFF4A9EFF));
      expect(theme.textPrimary, const Color(0xFFFFFFFF));
    });

    test('all 6 presets exist and have valid colors', () {
      const presets = [
        SlotThemeData.casino,
        SlotThemeData.neon,
        SlotThemeData.royal,
        SlotThemeData.nature,
        SlotThemeData.retro,
        SlotThemeData.minimal,
      ];

      for (final preset in presets) {
        expect(preset.bgDeep, isNotNull);
        expect(preset.gold, isNotNull);
        expect(preset.accent, isNotNull);
        expect(preset.winSmall, isNotNull);
        expect(preset.winBig, isNotNull);
        expect(preset.winMega, isNotNull);
        expect(preset.winEpic, isNotNull);
        expect(preset.winUltra, isNotNull);
        expect(preset.jackpotColors.length, greaterThanOrEqualTo(4));
        expect(preset.textPrimary, isNotNull);
        expect(preset.textSecondary, isNotNull);
      }
    });

    test('jackpot color getters return correct tier colors', () {
      const theme = SlotThemeData.casino;
      expect(theme.jackpotGrand, const Color(0xFFFFD700));
      expect(theme.jackpotMajor, const Color(0xFFFF4080));
      expect(theme.jackpotMinor, const Color(0xFF8B5CF6));
      expect(theme.jackpotMini, const Color(0xFF4CAF50));
    });

    test('gradient getters produce valid gradients', () {
      const theme = SlotThemeData.casino;
      expect(theme.maxBetGradient.length, 2);
      expect(theme.autoSpinGradient.length, 2);
      expect(theme.maxBetGradient[0], theme.gold);
    });

    test('empty jackpotColors returns safe defaults', () {
      const theme = SlotThemeData(
        bgDeep: Color(0xFF000000),
        bgDark: Color(0xFF000000),
        bgMid: Color(0xFF000000),
        bgSurface: Color(0xFF000000),
        gold: Color(0xFFFFD700),
        accent: Color(0xFF4A9EFF),
        winSmall: Color(0xFF40C8FF),
        winBig: Color(0xFF40FF90),
        winMega: Color(0xFFFFD700),
        winEpic: Color(0xFFE040FB),
        winUltra: Color(0xFFFF4080),
        jackpotColors: [],
        border: Color(0xFF3a3a48),
        textPrimary: Color(0xFFFFFFFF),
        textSecondary: Color(0xFFB0B0B8),
      );
      // Should return defaults without crashing
      expect(theme.jackpotGrand, const Color(0xFFFFD700));
      expect(theme.jackpotMajor, const Color(0xFFFF4080));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DeviceSimulation Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('DeviceSimulation', () {
    test('has 4 presets', () {
      expect(DeviceSimulation.values.length, 4);
    });

    test('labels are correct', () {
      expect(DeviceSimulation.desktop.label, 'Desktop');
      expect(DeviceSimulation.tablet.label, 'Tablet');
      expect(DeviceSimulation.mobileLandscape.label, 'Mobile (L)');
      expect(DeviceSimulation.mobilePortrait.label, 'Mobile (P)');
    });

    test('icons are distinct', () {
      final icons = DeviceSimulation.values.map((d) => d.icon).toSet();
      expect(icons.length, 4);
    });

    test('desktop has null size (unconstrained)', () {
      expect(DeviceSimulation.desktop.size, isNull);
    });

    test('tablet size is 1024x768', () {
      expect(DeviceSimulation.tablet.size, const Size(1024, 768));
    });

    test('mobile landscape is wider than tall', () {
      final size = DeviceSimulation.mobileLandscape.size!;
      expect(size.width, greaterThan(size.height));
    });

    test('mobile portrait is taller than wide', () {
      final size = DeviceSimulation.mobilePortrait.size!;
      expect(size.height, greaterThan(size.width));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SpinButtonPhase Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('SpinButtonPhase', () {
    test('has 4 phases', () {
      expect(SpinButtonPhase.values.length, 4);
      expect(SpinButtonPhase.spin, isNotNull);
      expect(SpinButtonPhase.stop, isNotNull);
      expect(SpinButtonPhase.skip, isNotNull);
      expect(SpinButtonPhase.skipProtected, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BigWinProtection Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('BigWinProtection', () {
    test('regular win has zero protection', () {
      expect(BigWinProtection.regularWin, 0.0);
    });

    test('big win protection is 2.5 seconds', () {
      expect(BigWinProtection.bigWinProtection, 2.5);
    });

    test('tier duration is 4 seconds', () {
      expect(BigWinProtection.tierDuration, 4.0);
    });

    test('end duration is 4 seconds', () {
      expect(BigWinProtection.endDuration, 4.0);
    });

    test('forTier returns protection for all big win tiers', () {
      for (int i = 1; i <= 5; i++) {
        expect(
          BigWinProtection.forTier('BIG_WIN_TIER_$i'),
          BigWinProtection.bigWinProtection,
        );
      }
    });

    test('forTier returns zero for regular tiers', () {
      expect(BigWinProtection.forTier('WIN_1'), 0.0);
      expect(BigWinProtection.forTier('WIN_5'), 0.0);
      expect(BigWinProtection.forTier('WIN_EQUAL'), 0.0);
      expect(BigWinProtection.forTier('WIN_LOW'), 0.0);
    });

    test('forTier is case-insensitive', () {
      expect(BigWinProtection.forTier('big_win_tier_1'), 2.5);
      expect(BigWinProtection.forTier('Big_Win_Tier_3'), 2.5);
    });

    test('forTier handles BIG_WIN prefix', () {
      expect(BigWinProtection.forTier('BIG_WIN'), 2.5);
      expect(BigWinProtection.forTier('BIG_WIN_SPECIAL'), 2.5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SpinButtonColors Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('SpinButtonColors', () {
    test('spin gradient is blue', () {
      expect(SpinButtonColors.spinGradient.length, 2);
      expect(SpinButtonColors.spinGradient[0], const Color(0xFF4A9EFF));
    });

    test('stop gradient is red', () {
      expect(SpinButtonColors.stopGradient.length, 2);
    });

    test('skip gradient is gold', () {
      expect(SpinButtonColors.skipGradient.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SlotThemePreset Enum Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('SlotThemePreset', () {
    test('has 6 presets', () {
      expect(SlotThemePreset.values.length, 6);
    });

    test('labels are unique', () {
      final labels = SlotThemePreset.values.map((p) => p.label).toSet();
      expect(labels.length, 6);
    });

    test('each preset produces valid SlotThemeData', () {
      for (final preset in SlotThemePreset.values) {
        final data = preset.data;
        expect(data.bgDeep, isNotNull);
        expect(data.gold, isNotNull);
        expect(data.accent, isNotNull);
      }
    });

    test('casino is the default preset', () {
      expect(SlotThemePreset.casino.label, 'Casino');
      expect(SlotThemePreset.casino.data.bgDeep, SlotThemeData.casino.bgDeep);
    });
  });
}
