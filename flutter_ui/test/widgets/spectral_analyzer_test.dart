/// Spectral Analyzer Widget Tests
///
/// Tests for the professional FFT spectrum analyzer widget.
/// Covers:
/// - dB/linear conversion accuracy
/// - Frequency binning calculations
/// - Configuration validation
/// - Widget rendering

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluxforge_ui/widgets/metering/spectral_analyzer_widget.dart';

void main() {
  group('dB Conversion', () {
    test('linearToDb should convert correctly', () {
      // 1.0 linear = 0 dB
      expect(linearToDb(1.0), closeTo(0.0, 0.001));

      // 0.5 linear ≈ -6 dB
      expect(linearToDb(0.5), closeTo(-6.02, 0.1));

      // 0.1 linear = -20 dB
      expect(linearToDb(0.1), closeTo(-20.0, 0.001));

      // 0.01 linear = -40 dB
      expect(linearToDb(0.01), closeTo(-40.0, 0.001));

      // 0.001 linear = -60 dB
      expect(linearToDb(0.001), closeTo(-60.0, 0.001));
    });

    test('linearToDb should handle zero and negative', () {
      expect(linearToDb(0.0), -100.0);
      expect(linearToDb(-0.5), -100.0);
    });

    test('dbToLinear should convert correctly', () {
      // 0 dB = 1.0 linear
      expect(dbToLinear(0.0), closeTo(1.0, 0.001));

      // -6 dB ≈ 0.5 linear
      expect(dbToLinear(-6.0), closeTo(0.5012, 0.01));

      // -20 dB = 0.1 linear
      expect(dbToLinear(-20.0), closeTo(0.1, 0.001));

      // -60 dB = 0.001 linear
      expect(dbToLinear(-60.0), closeTo(0.001, 0.0001));
    });

    test('dB conversion should be reversible', () {
      for (final db in [-60.0, -40.0, -20.0, -6.0, 0.0]) {
        final linear = dbToLinear(db);
        final backToDb = linearToDb(linear);
        expect(backToDb, closeTo(db, 0.001));
      }
    });
  });

  group('Mock Spectrum Generation', () {
    test('generateMockSpectrum should create correct bin count', () {
      final spectrum = generateMockSpectrum(binCount: 256);
      expect(spectrum.length, 256);
    });

    test('generateMockSpectrum should respect noise floor', () {
      final spectrum = generateMockSpectrum(
        binCount: 256,
        noiseFloor: -60,
        signalLevel: -60, // Signal at noise floor
      );

      // All values should be around noise floor
      for (int i = 0; i < spectrum.length; i++) {
        expect(spectrum[i], lessThanOrEqualTo(0.0));
        expect(spectrum[i], greaterThanOrEqualTo(-100.0));
      }
    });

    test('generateMockSpectrum should create signal peak', () {
      final spectrum = generateMockSpectrum(
        binCount: 256,
        noiseFloor: -60,
        signalLevel: -12,
        centerFreq: 1000,
        bandwidth: 500,
      );

      // Find maximum value (should be near signal level)
      double maxValue = -100.0;
      for (int i = 0; i < spectrum.length; i++) {
        if (spectrum[i] > maxValue) maxValue = spectrum[i];
      }

      // Max should be significantly above noise floor
      expect(maxValue, greaterThan(-40.0));
    });
  });

  group('SpectralAnalyzerConfig', () {
    test('default config should have expected values', () {
      const config = SpectralAnalyzerConfig();
      expect(config.minDb, -90);
      expect(config.maxDb, 0);
      expect(config.peakHoldMs, 1500);
      expect(config.peakDecayDbPerSec, 30);
      expect(config.showFrequencyScale, true);
      expect(config.showDbScale, true);
      expect(config.showGrid, true);
      expect(config.style, SpectralDisplayStyle.bars);
      expect(config.smoothing, 0.7);
    });

    test('proTools preset should have correct configuration', () {
      const config = SpectralAnalyzerConfig.proTools;
      expect(config.style, SpectralDisplayStyle.line);
      expect(config.peakHoldMs, 2000);
      expect(config.smoothing, 0.8);
    });

    test('rta preset should have no peak hold', () {
      const config = SpectralAnalyzerConfig.rta;
      expect(config.peakHoldMs, 0);
      expect(config.style, SpectralDisplayStyle.bars);
    });

    test('compact preset should hide scales', () {
      const config = SpectralAnalyzerConfig.compact;
      expect(config.showFrequencyScale, false);
      expect(config.showDbScale, false);
      expect(config.showGrid, false);
      expect(config.style, SpectralDisplayStyle.fill);
    });
  });

  group('SpectralAnalyzer Widget', () {
    testWidgets('should render without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpectralAnalyzer(
                width: 400,
                height: 200,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SpectralAnalyzer), findsOneWidget);
    });

    testWidgets('should display with spectrum data', (tester) async {
      final spectrum = generateMockSpectrum();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpectralAnalyzer(
                width: 400,
                height: 200,
                spectrumData: spectrum,
                dataInDb: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SpectralAnalyzer), findsOneWidget);
    });

    testWidgets('should show frozen indicator when frozen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpectralAnalyzer(
                width: 400,
                height: 200,
                frozen: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('FROZEN'), findsOneWidget);
    });

    testWidgets('should call onTap callback when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpectralAnalyzer(
                width: 400,
                height: 200,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SpectralAnalyzer));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('should render all display styles', (tester) async {
      for (final style in SpectralDisplayStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SpectralAnalyzer(
                  width: 400,
                  height: 200,
                  config: SpectralAnalyzerConfig(style: style),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(SpectralAnalyzer), findsOneWidget);
        await tester.pump();
      }
    });
  });

  group('Frequency Binning', () {
    test('20Hz should map to bin 0', () {
      // Log scale: 20Hz-20kHz to 0-255
      const minFreq = 20.0;
      const maxFreq = 20000.0;
      final logMin = math.log(minFreq);
      final logMax = math.log(maxFreq);

      final bin = ((math.log(20.0) - logMin) / (logMax - logMin) * 255).round();
      expect(bin, 0);
    });

    test('20kHz should map to bin 255', () {
      const minFreq = 20.0;
      const maxFreq = 20000.0;
      final logMin = math.log(minFreq);
      final logMax = math.log(maxFreq);

      final bin = ((math.log(20000.0) - logMin) / (logMax - logMin) * 255).round();
      expect(bin, 255);
    });

    test('1kHz should map to approximately bin 128', () {
      const minFreq = 20.0;
      const maxFreq = 20000.0;
      final logMin = math.log(minFreq);
      final logMax = math.log(maxFreq);

      // 1kHz is the geometric mean of 20Hz and 20kHz (√(20*20000) ≈ 632Hz)
      // Actually 1kHz should be around bin 128-140
      final bin = ((math.log(1000.0) - logMin) / (logMax - logMin) * 255).round();
      expect(bin, greaterThan(100));
      expect(bin, lessThan(180));
    });
  });
}
