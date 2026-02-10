/// FabFilter Panel Tests
///
/// Tests for FabFilter DSP panel helper classes:
/// - Gain-to-dB and dB-to-gain conversions
/// - ABState comparison state management
/// - FabFilterColors constants
/// - FabFilterText styles
/// - Knob value normalization
/// - Slider logarithmic mapping
@Tags(['widget'])
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/fabfilter/fabfilter_panel_base.dart';
import 'package:fluxforge_ui/widgets/fabfilter/fabfilter_theme.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Gain ↔ dB Conversion Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Gain-to-dB conversion', () {
    double gainToDb(double gain) {
      if (gain <= 0.0) return double.negativeInfinity;
      return 20.0 * math.log(gain) / math.ln10;
    }

    test('unity gain (1.0) = 0 dB', () {
      expect(gainToDb(1.0), closeTo(0.0, 0.001));
    });

    test('gain 0.5 = -6.02 dB', () {
      expect(gainToDb(0.5), closeTo(-6.02, 0.01));
    });

    test('gain 2.0 = +6.02 dB', () {
      expect(gainToDb(2.0), closeTo(6.02, 0.01));
    });

    test('gain 0.0 = -infinity', () {
      expect(gainToDb(0.0), double.negativeInfinity);
    });

    test('gain 0.001 ~ -60 dB', () {
      expect(gainToDb(0.001), closeTo(-60.0, 0.1));
    });

    test('gain 10.0 = +20 dB', () {
      expect(gainToDb(10.0), closeTo(20.0, 0.01));
    });

    test('gain 0.1 = -20 dB', () {
      expect(gainToDb(0.1), closeTo(-20.0, 0.01));
    });
  });

  group('dB-to-gain conversion', () {
    double dbToGain(double db) {
      return math.pow(10, db / 20).toDouble();
    }

    test('0 dB = unity gain (1.0)', () {
      expect(dbToGain(0.0), closeTo(1.0, 0.001));
    });

    test('-6 dB ~ 0.5 gain', () {
      expect(dbToGain(-6.0), closeTo(0.5012, 0.01));
    });

    test('+6 dB ~ 2.0 gain', () {
      expect(dbToGain(6.0), closeTo(1.995, 0.01));
    });

    test('-20 dB = 0.1 gain', () {
      expect(dbToGain(-20.0), closeTo(0.1, 0.001));
    });

    test('+20 dB = 10.0 gain', () {
      expect(dbToGain(20.0), closeTo(10.0, 0.001));
    });

    test('roundtrip: gain → dB → gain preserves value', () {
      double gainToDb(double g) => 20.0 * math.log(g) / math.ln10;

      for (final gain in [0.1, 0.5, 1.0, 1.5, 2.0, 4.0]) {
        final db = gainToDb(gain);
        final restored = dbToGain(db);
        expect(restored, closeTo(gain, 0.0001));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Compressor Ratio Display Formatting
  // ═══════════════════════════════════════════════════════════════════════════

  group('Compressor ratio formatting', () {
    String formatRatio(double ratio) {
      if (ratio >= 100) return '∞:1';
      if (ratio >= 10) return '${ratio.round()}:1';
      return '${ratio.toStringAsFixed(1)}:1';
    }

    test('ratio 1.0 formats as 1.0:1', () {
      expect(formatRatio(1.0), '1.0:1');
    });

    test('ratio 4.0 formats as 4.0:1', () {
      expect(formatRatio(4.0), '4.0:1');
    });

    test('ratio 10.0 formats as 10:1 (no decimal)', () {
      expect(formatRatio(10.0), '10:1');
    });

    test('ratio 20.0 formats as 20:1', () {
      expect(formatRatio(20.0), '20:1');
    });

    test('ratio 100+ formats as infinity', () {
      expect(formatRatio(100.0), '∞:1');
      expect(formatRatio(999.0), '∞:1');
    });

    test('ratio 2.5 formats with one decimal', () {
      expect(formatRatio(2.5), '2.5:1');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ABState Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('ABState', () {
    test('initial state: A selected, nothing stored', () {
      final ab = ABState<double>();
      expect(ab.isB, false);
      expect(ab.hasStoredA, false);
      expect(ab.hasStoredB, false);
      expect(ab.current, isNull);
    });

    test('store A and B', () {
      final ab = ABState<double>();
      ab.storeA(0.5);
      expect(ab.hasStoredA, true);
      expect(ab.stateA, 0.5);

      ab.storeB(0.8);
      expect(ab.hasStoredB, true);
      expect(ab.stateB, 0.8);
    });

    test('toggle switches active slot', () {
      final ab = ABState<double>();
      ab.storeA(0.5);
      ab.storeB(0.8);

      expect(ab.isB, false);
      expect(ab.current, 0.5);

      ab.toggle();
      expect(ab.isB, true);
      expect(ab.current, 0.8);

      ab.toggle();
      expect(ab.isB, false);
      expect(ab.current, 0.5);
    });

    test('copyAToB copies A state to B slot', () {
      final ab = ABState<String>();
      ab.storeA('bright');
      ab.copyAToB();
      expect(ab.stateB, 'bright');
      expect(ab.hasStoredB, true);
    });

    test('copyBToA copies B state to A slot', () {
      final ab = ABState<String>();
      ab.storeB('warm');
      ab.copyBToA();
      expect(ab.stateA, 'warm');
      expect(ab.hasStoredA, true);
    });

    test('reset clears all state', () {
      final ab = ABState<double>();
      ab.storeA(1.0);
      ab.storeB(2.0);
      ab.toggle();

      ab.reset();
      expect(ab.stateA, isNull);
      expect(ab.stateB, isNull);
      expect(ab.isB, false);
      expect(ab.hasStoredA, false);
      expect(ab.hasStoredB, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FabFilterColors Constants
  // ═══════════════════════════════════════════════════════════════════════════

  group('FabFilterColors', () {
    test('accent colors are distinct', () {
      final colors = {
        FabFilterColors.blue,
        FabFilterColors.orange,
        FabFilterColors.cyan,
        FabFilterColors.green,
        FabFilterColors.yellow,
        FabFilterColors.red,
        FabFilterColors.purple,
        FabFilterColors.pink,
      };
      expect(colors.length, 8); // All unique
    });

    test('background gradient goes dark to light', () {
      // bgVoid < bgDeep < bgMid < bgSurface < bgElevated
      expect(FabFilterColors.bgVoid.value, lessThan(FabFilterColors.bgDeep.value));
      expect(FabFilterColors.bgDeep.value, lessThan(FabFilterColors.bgMid.value));
      expect(FabFilterColors.bgMid.value, lessThan(FabFilterColors.bgSurface.value));
    });

    test('text hierarchy: primary > secondary > tertiary', () {
      // Primary is brightest, tertiary is dimmest
      expect(
        FabFilterColors.textPrimary.computeLuminance(),
        greaterThan(FabFilterColors.textSecondary.computeLuminance()),
      );
      expect(
        FabFilterColors.textSecondary.computeLuminance(),
        greaterThan(FabFilterColors.textTertiary.computeLuminance()),
      );
    });

    test('spectrum gradient has at least 4 colors', () {
      expect(FabFilterColors.spectrumGradient.length, greaterThanOrEqualTo(4));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FabFilterText Styles
  // ═══════════════════════════════════════════════════════════════════════════

  group('FabFilterText', () {
    test('title style exists and has color', () {
      expect(FabFilterText.title.color, isNotNull);
      expect(FabFilterText.title.fontSize, isNotNull);
    });

    test('sectionHeader style exists', () {
      expect(FabFilterText.sectionHeader, isNotNull);
    });

    test('paramLabel style exists', () {
      expect(FabFilterText.paramLabel, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Knob Value Normalization Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Knob value normalization (0-1 range)', () {
    test('normalize: min=0, max=100, value=50 → 0.5', () {
      double normalize(double value, double min, double max) {
        return (value - min) / (max - min);
      }
      expect(normalize(50, 0, 100), 0.5);
      expect(normalize(0, 0, 100), 0.0);
      expect(normalize(100, 0, 100), 1.0);
    });

    test('denormalize: 0.5 with range 20-20000 Hz', () {
      double denormalize(double normalized, double min, double max) {
        return min + normalized * (max - min);
      }
      expect(denormalize(0.0, 20, 20000), 20.0);
      expect(denormalize(1.0, 20, 20000), 20000.0);
      expect(denormalize(0.5, 20, 20000), 10010.0);
    });

    test('logarithmic normalization for frequency', () {
      double logNormalize(double value, double min, double max) {
        return (math.log(value) - math.log(min)) /
            (math.log(max) - math.log(min));
      }

      double logDenormalize(double normalized, double min, double max) {
        return math.exp(
            math.log(min) + normalized * (math.log(max) - math.log(min)));
      }

      // 1kHz in 20-20000 range should be near 0.5 on log scale
      final normalized = logNormalize(1000, 20, 20000);
      expect(normalized, closeTo(0.57, 0.02));

      // Roundtrip
      final restored = logDenormalize(normalized, 20, 20000);
      expect(restored, closeTo(1000, 1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Limiter True Peak Calculation
  // ═══════════════════════════════════════════════════════════════════════════

  group('True peak helpers', () {
    test('linear to dBTP conversion', () {
      double linearToDbtp(double linear) {
        if (linear <= 0) return -100.0;
        return 20.0 * math.log(linear) / math.ln10;
      }

      expect(linearToDbtp(1.0), closeTo(0.0, 0.001));
      expect(linearToDbtp(0.0), -100.0);
      expect(linearToDbtp(1.12), closeTo(0.98, 0.02)); // Slightly over
    });

    test('check if signal exceeds ceiling', () {
      bool exceedsCeiling(double peakDb, double ceilingDb) {
        return peakDb > ceilingDb;
      }

      expect(exceedsCeiling(0.0, -0.1), true);  // 0 dB exceeds -0.1 ceiling
      expect(exceedsCeiling(-1.0, -0.1), false); // -1 dB below ceiling
      expect(exceedsCeiling(-0.1, -0.1), false); // Exactly at ceiling
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Preset Category Filtering (Pure Logic)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Preset category filtering', () {
    test('filter by category', () {
      final presets = [
        {'name': 'Vocal', 'category': 'Voice'},
        {'name': 'Drum', 'category': 'Drums'},
        {'name': 'Guitar', 'category': 'Guitar'},
        {'name': 'Snare', 'category': 'Drums'},
      ];

      final drums = presets.where((p) => p['category'] == 'Drums').toList();
      expect(drums.length, 2);
    });

    test('search filter by name', () {
      final presets = ['Warm Vocal', 'Bright Vocal', 'Drum Smash', 'Guitar Clean'];

      final results = presets.where(
        (p) => p.toLowerCase().contains('vocal'),
      ).toList();
      expect(results.length, 2);
    });
  });
}
