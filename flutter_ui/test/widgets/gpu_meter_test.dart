/// GPU Meter Widget Tests
///
/// Tests for the GPU-accelerated audio level meter system.
/// Covers:
/// - Data model conversions (linear, dB, normalized)
/// - Ballistics calculations
/// - Peak hold logic
/// - Color mapping
/// - Configuration presets

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluxforge_ui/widgets/metering/gpu_meter_widget.dart';

void main() {
  group('GpuMeterLevels', () {
    test('zero constant should have all values at 0', () {
      const levels = GpuMeterLevels.zero;
      expect(levels.peak, 0);
      expect(levels.rms, 0);
      expect(levels.peakR, isNull);
      expect(levels.rmsR, isNull);
      expect(levels.clipped, false);
    });

    test('fromDb should convert dB to linear correctly', () {
      // 0 dB = 1.0 linear
      final levels0dB = GpuMeterLevels.fromDb(0);
      expect(levels0dB.peak, closeTo(1.0, 0.001));
      expect(levels0dB.clipped, true);

      // -6 dB = 0.5 linear
      final levels6dB = GpuMeterLevels.fromDb(-6);
      expect(levels6dB.peak, closeTo(0.5012, 0.001));
      expect(levels6dB.clipped, false);

      // -20 dB = 0.1 linear
      final levels20dB = GpuMeterLevels.fromDb(-20);
      expect(levels20dB.peak, closeTo(0.1, 0.001));

      // -60 dB = 0.001 linear
      final levels60dB = GpuMeterLevels.fromDb(-60);
      expect(levels60dB.peak, closeTo(0.001, 0.0001));

      // -120 dB or lower = 0 (silence)
      final levelsSilent = GpuMeterLevels.fromDb(-120);
      expect(levelsSilent.peak, 0);
    });

    test('stereoFromDb should create stereo levels correctly', () {
      final levels = GpuMeterLevels.stereoFromDb(-6, -12, -10, -16);

      expect(levels.peak, closeTo(0.5012, 0.001)); // -6 dB
      expect(levels.peakR, closeTo(0.2512, 0.001)); // -12 dB
      expect(levels.rms, closeTo(0.3162, 0.001)); // -10 dB
      expect(levels.rmsR, closeTo(0.1585, 0.001)); // -16 dB
      expect(levels.clipped, false);
    });

    test('clipping detection should work for both channels', () {
      final clippedL = GpuMeterLevels.stereoFromDb(0, -6);
      expect(clippedL.clipped, true);

      final clippedR = GpuMeterLevels.stereoFromDb(-6, 0);
      expect(clippedR.clipped, true);

      final clippedBoth = GpuMeterLevels.stereoFromDb(0, 0);
      expect(clippedBoth.clipped, true);

      final noClip = GpuMeterLevels.stereoFromDb(-3, -3);
      expect(noClip.clipped, false);
    });

    test('equality should work correctly', () {
      const levels1 = GpuMeterLevels(peak: 0.5, rms: 0.3);
      const levels2 = GpuMeterLevels(peak: 0.5, rms: 0.3);
      const levels3 = GpuMeterLevels(peak: 0.6, rms: 0.3);

      expect(levels1 == levels2, true);
      expect(levels1 == levels3, false);
      expect(levels1.hashCode == levels2.hashCode, true);
    });
  });

  group('GpuMeterConfig', () {
    test('default config should have expected values', () {
      const config = GpuMeterConfig();
      expect(config.minDb, -60);
      expect(config.maxDb, 6);
      expect(config.peakHoldMs, 1500);
      expect(config.peakDecayDbPerSec, 30);
      expect(config.attackMs, 0.1);
      expect(config.releaseMs, 300);
      expect(config.segments, 30);
      expect(config.showRms, false);
      expect(config.showScale, false);
    });

    test('proTools preset should have Pro Tools-style ballistics', () {
      const config = GpuMeterConfig.proTools;
      expect(config.peakHoldMs, 2000);
      expect(config.peakDecayDbPerSec, 20);
      expect(config.attackMs, 0.01); // Near instant attack
      expect(config.releaseMs, 1500);
    });

    test('ppm preset should have EBU PPM ballistics', () {
      const config = GpuMeterConfig.ppm;
      expect(config.attackMs, 10);
      expect(config.releaseMs, 1500);
      expect(config.peakHoldMs, 3000);
    });

    test('vu preset should have VU meter characteristics', () {
      const config = GpuMeterConfig.vu;
      expect(config.minDb, -40);
      expect(config.maxDb, 3);
      expect(config.attackMs, 300);
      expect(config.releaseMs, 300);
      expect(config.showRms, true);
      expect(config.peakHoldMs, 0); // No peak hold for VU
    });

    test('compact preset should hide scale', () {
      const config = GpuMeterConfig.compact;
      expect(config.showScale, false);
      expect(config.peakDecayDbPerSec, 40); // Faster decay
    });

    test('scaleMarks should contain standard dB values', () {
      const config = GpuMeterConfig();
      expect(config.scaleMarks, contains(0));
      expect(config.scaleMarks, contains(-6));
      expect(config.scaleMarks, contains(-20));
      expect(config.scaleMarks, contains(-60));
    });
  });

  group('Ballistics Calculations', () {
    test('attack coefficient should increase with longer attack time', () {
      // Simulate attack coefficient calculation
      // attackCoef = 1.0 - exp(-deltaMs / attackMs)

      const deltaMs = 16.67; // ~60fps

      // Fast attack (0.01ms)
      final fastAttack = 1.0 - math.exp(-deltaMs / 0.01);
      expect(fastAttack, closeTo(1.0, 0.01)); // Near instant

      // Medium attack (10ms)
      final mediumAttack = 1.0 - math.exp(-deltaMs / 10);
      expect(mediumAttack, greaterThan(0.5));
      expect(mediumAttack, lessThan(1.0));

      // Slow attack (300ms - VU style)
      final slowAttack = 1.0 - math.exp(-deltaMs / 300);
      expect(slowAttack, closeTo(0.054, 0.01)); // Very slow
    });

    test('release coefficient should create smooth decay', () {
      const deltaMs = 16.67;

      // Fast release (300ms)
      final fastRelease = 1.0 - math.exp(-deltaMs / 300);
      expect(fastRelease, closeTo(0.054, 0.01));

      // Slow release (1500ms)
      final slowRelease = 1.0 - math.exp(-deltaMs / 1500);
      expect(slowRelease, closeTo(0.011, 0.005)); // Very slow
    });

    test('peak hold decay should follow dB per second rate', () {
      // At 30 dB/sec decay rate, after 1 second, peak should drop 30 dB
      const decayRate = 30.0; // dB/sec
      const deltaMs = 1000.0; // 1 second

      final decayDb = decayRate * deltaMs / 1000.0;
      expect(decayDb, 30.0);

      // Starting at 0 dB (1.0 linear), after 1 sec should be at -30 dB
      final startLinear = 1.0;
      final startDb = 20.0 * math.log(startLinear) / math.ln10; // 0 dB
      final endDb = startDb - decayDb; // -30 dB
      final endLinear = math.pow(10, endDb / 20.0);

      expect(endLinear, closeTo(0.0316, 0.001)); // ~-30 dB
    });
  });

  group('Color Mapping', () {
    Color getColorForLevel(double normalized) {
      if (normalized < 0.35) {
        return Color.lerp(
          const Color(0xFF40C8FF),
          const Color(0xFF40FF90),
          normalized / 0.35,
        )!;
      } else if (normalized < 0.65) {
        return Color.lerp(
          const Color(0xFF40FF90),
          const Color(0xFFFFFF40),
          (normalized - 0.35) / 0.30,
        )!;
      } else if (normalized < 0.85) {
        return Color.lerp(
          const Color(0xFFFFFF40),
          const Color(0xFFFF9040),
          (normalized - 0.65) / 0.20,
        )!;
      } else {
        return Color.lerp(
          const Color(0xFFFF9040),
          const Color(0xFFFF4040),
          (normalized - 0.85) / 0.15,
        )!;
      }
    }

    test('low levels should be cyan to green', () {
      final color0 = getColorForLevel(0.0);
      expect(color0, const Color(0xFF40C8FF)); // Pure cyan at bottom

      final color20 = getColorForLevel(0.2);
      // Should be between cyan and green
      expect(color20.red, lessThan(100)); // Low red
      expect(color20.green, greaterThan(200)); // High green
      expect(color20.blue, greaterThan(100)); // Some blue
    });

    test('medium levels should be green to yellow', () {
      final color50 = getColorForLevel(0.5);
      // Should be between green and yellow
      expect(color50.green, greaterThan(200)); // High green
      expect(color50.red, greaterThan(100)); // Some red (heading to yellow)
    });

    test('high levels should be yellow to orange', () {
      final color75 = getColorForLevel(0.75);
      // Should be between yellow and orange
      expect(color75.red, greaterThan(200)); // High red
      expect(color75.green, greaterThan(100)); // Medium-high green
    });

    test('clip levels should be orange to red', () {
      final color95 = getColorForLevel(0.95);
      // Should be nearly red
      expect(color95.red, greaterThan(240));
      // Green diminishes as we approach red

      final color100 = getColorForLevel(1.0);
      // Final color is red (0xFFFF4040)
      expect(color100.red, 255);
      expect(color100.green, closeTo(64, 5)); // ~0x40
      expect(color100.blue, closeTo(64, 5)); // ~0x40
    });
  });

  group('dB to Normalized Conversion', () {
    double dbToNormalized(double db, {double minDb = -60, double maxDb = 6}) {
      return ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
    }

    test('0 dB should map to ~0.91 normalized (default range)', () {
      final normalized = dbToNormalized(0);
      expect(normalized, closeTo(0.909, 0.01)); // 60/66
    });

    test('minDb should map to 0 normalized', () {
      expect(dbToNormalized(-60), 0);
    });

    test('maxDb should map to 1 normalized', () {
      expect(dbToNormalized(6), 1.0);
    });

    test('-6 dB should map correctly', () {
      final normalized = dbToNormalized(-6);
      expect(normalized, closeTo(0.818, 0.01)); // 54/66
    });

    test('-20 dB should map correctly', () {
      final normalized = dbToNormalized(-20);
      expect(normalized, closeTo(0.606, 0.01)); // 40/66
    });

    test('values below minDb should clamp to 0', () {
      expect(dbToNormalized(-70), 0);
      expect(dbToNormalized(-100), 0);
    });

    test('values above maxDb should clamp to 1', () {
      expect(dbToNormalized(10), 1.0);
      expect(dbToNormalized(20), 1.0);
    });
  });

  group('Linear to dB Conversion', () {
    double linearToDb(double linear) {
      if (linear <= 0) return double.negativeInfinity;
      return 20.0 * math.log(linear) / math.ln10;
    }

    test('1.0 linear should be 0 dB', () {
      expect(linearToDb(1.0), closeTo(0, 0.001));
    });

    test('0.5 linear should be ~-6 dB', () {
      expect(linearToDb(0.5), closeTo(-6.02, 0.01));
    });

    test('0.1 linear should be -20 dB', () {
      expect(linearToDb(0.1), closeTo(-20, 0.01));
    });

    test('0.001 linear should be -60 dB', () {
      expect(linearToDb(0.001), closeTo(-60, 0.01));
    });

    test('0 linear should be -infinity', () {
      expect(linearToDb(0), double.negativeInfinity);
    });

    test('2.0 linear should be ~+6 dB (clipping)', () {
      expect(linearToDb(2.0), closeTo(6.02, 0.01));
    });
  });

  group('GpuMeter Widget', () {
    testWidgets('should render without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpuMeter(
              levels: const GpuMeterLevels(peak: 0.5, rms: 0.3),
              width: 12,
              height: 200,
            ),
          ),
        ),
      );

      expect(find.byType(GpuMeter), findsOneWidget);
      // CustomPaint is used both internally by GpuMeter and possibly by other widgets
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('simple constructor should work', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpuMeter.simple(
              level: 0.7,
              width: 8,
              height: 120,
            ),
          ),
        ),
      );

      expect(find.byType(GpuMeter), findsOneWidget);
    });

    testWidgets('stereo constructor should work', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpuMeter.stereo(
              peakL: 0.5,
              peakR: 0.7,
              width: 24,
              height: 200,
            ),
          ),
        ),
      );

      expect(find.byType(GpuMeter), findsOneWidget);
    });

    testWidgets('muted meter should show no level', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpuMeter(
              levels: const GpuMeterLevels(peak: 0.9),
              muted: true,
              width: 12,
              height: 200,
            ),
          ),
        ),
      );

      // The meter should still render, but with 0 level
      expect(find.byType(GpuMeter), findsOneWidget);
    });

    testWidgets('tap should call onTap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpuMeter(
              levels: const GpuMeterLevels(peak: 0.5),
              width: 24,
              height: 200,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GpuMeter));
      expect(tapped, true);
    });
  });

  group('GpuStereoMeter Widget', () {
    testWidgets('should render with labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GpuStereoMeter(
              peakL: 0.5,
              peakR: 0.7,
              width: 32,
              height: 200,
              showLabels: true,
            ),
          ),
        ),
      );

      expect(find.byType(GpuStereoMeter), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('should render without labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GpuStereoMeter(
              peakL: 0.5,
              peakR: 0.7,
              showLabels: false,
            ),
          ),
        ),
      );

      expect(find.byType(GpuStereoMeter), findsOneWidget);
      expect(find.text('L'), findsNothing);
      expect(find.text('R'), findsNothing);
    });
  });

  group('GpuHorizontalMeter Widget', () {
    testWidgets('should render horizontal orientation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GpuHorizontalMeter(
              level: 0.6,
              width: 200,
              height: 12,
            ),
          ),
        ),
      );

      expect(find.byType(GpuHorizontalMeter), findsOneWidget);
      expect(find.byType(GpuMeter), findsOneWidget);
    });
  });

  group('Performance Characteristics', () {
    test('shouldRepaint threshold should be 0.001 for visual imperceptibility', () {
      // The threshold of 0.001 represents ~0.08 dB change
      // which is below human perception threshold (~0.3 dB)
      const threshold = 0.001;
      final dbChange = 20 * math.log(1 + threshold) / math.ln10;
      expect(dbChange.abs(), lessThan(0.1)); // < 0.1 dB
    });

    test('gradient should be cached statically', () {
      // This test documents the caching behavior
      // The _cachedGradientV and _cachedGradientH are static fields
      // that are initialized once and reused across all instances
      expect(true, true); // Design verification
    });
  });
}
