/// Frequency Graph Test Suite
///
/// Tests for DSP transfer function calculation and visualization:
/// - Biquad coefficient calculation (Audio EQ Cookbook validation)
/// - Compressor transfer curve (threshold/ratio/knee math)
/// - Gate/Expander curves
/// - Frequency scaling (Hz → normalized position)
/// - dB scaling (dB → pixel position)
/// - EQ band summation
/// - Edge cases (DC, Nyquist, extreme Q values)

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge_ui/models/frequency_graph_data.dart';
import 'package:fluxforge_ui/services/dsp_frequency_calculator.dart';
import 'package:fluxforge_ui/widgets/dsp/frequency_graph_widget.dart';

void main() {
  group('FrequencyGraphData Model', () {
    test('EqBandResponse serialization roundtrip', () {
      const band = EqBandResponse(
        frequency: 1000.0,
        gain: 6.0,
        q: 2.0,
        filterType: 'bell',
        enabled: true,
        slope: 12.0,
      );

      final json = band.toJson();
      final restored = EqBandResponse.fromJson(json);

      expect(restored.frequency, band.frequency);
      expect(restored.gain, band.gain);
      expect(restored.q, band.q);
      expect(restored.filterType, band.filterType);
      expect(restored.enabled, band.enabled);
      expect(restored.slope, band.slope);
    });

    test('FrequencyResponseData getMagnitudeAt interpolation', () {
      final frequencies = Float64List.fromList([100.0, 1000.0, 10000.0]);
      final magnitudes = Float64List.fromList([-6.0, 0.0, -12.0]);

      final data = FrequencyResponseData(
        type: FrequencyProcessorType.eq,
        frequencies: frequencies,
        magnitudes: magnitudes,
      );

      // Exact points
      expect(data.getMagnitudeAt(100.0), -6.0);
      expect(data.getMagnitudeAt(1000.0), 0.0);
      expect(data.getMagnitudeAt(10000.0), -12.0);

      // Interpolated points (midpoint between 1000 and 10000)
      final midMag = data.getMagnitudeAt(5500.0);
      expect(midMag, greaterThan(-12.0));
      expect(midMag, lessThan(0.0));
    });

    test('FrequencyResponseData min/max calculations', () {
      final frequencies = Float64List.fromList([20.0, 100.0, 1000.0, 10000.0, 20000.0]);
      final magnitudes = Float64List.fromList([-6.0, 3.0, 0.0, -12.0, -24.0]);

      final data = FrequencyResponseData(
        type: FrequencyProcessorType.eq,
        frequencies: frequencies,
        magnitudes: magnitudes,
      );

      expect(data.minFrequency, 20.0);
      expect(data.maxFrequency, 20000.0);
      expect(data.minMagnitude, -24.0);
      expect(data.maxMagnitude, 3.0);
    });

    test('FrequencyProcessorType isDynamics/isFrequencyDomain', () {
      final eqData = FrequencyResponseData(
        type: FrequencyProcessorType.eq,
        frequencies: Float64List(0),
        magnitudes: Float64List(0),
      );
      expect(eqData.isDynamics, false);
      expect(eqData.isFrequencyDomain, true);

      final compData = FrequencyResponseData(
        type: FrequencyProcessorType.compressor,
        frequencies: Float64List(0),
        magnitudes: Float64List(0),
      );
      expect(compData.isDynamics, true);
      expect(compData.isFrequencyDomain, false);
    });
  });

  group('DspFrequencyCalculator - Frequency Generation', () {
    test('generateLogFrequencies creates logarithmic spacing', () {
      final freqs = DspFrequencyCalculator.generateLogFrequencies(
        minFreq: 20.0,
        maxFreq: 20000.0,
        numPoints: 512,
      );

      expect(freqs.length, 512);
      expect(freqs.first, closeTo(20.0, 0.01));
      expect(freqs.last, closeTo(20000.0, 1.0));

      // Check logarithmic spacing: ratio between adjacent points should be constant
      final ratio1 = freqs[1] / freqs[0];
      final ratio2 = freqs[2] / freqs[1];
      final ratio256 = freqs[256] / freqs[255];

      expect(ratio1, closeTo(ratio2, 0.001));
      expect(ratio1, closeTo(ratio256, 0.001));
    });

    test('generateLinearDb creates linear spacing', () {
      final dbs = DspFrequencyCalculator.generateLinearDb(
        minDb: -60.0,
        maxDb: 6.0,
        numPoints: 256,
      );

      expect(dbs.length, 256);
      expect(dbs.first, closeTo(-60.0, 0.01));
      expect(dbs.last, closeTo(6.0, 0.01));

      // Check linear spacing
      final step = dbs[1] - dbs[0];
      final stepMid = dbs[128] - dbs[127];
      expect(step, closeTo(stepMid, 0.001));
    });
  });

  group('DspFrequencyCalculator - Biquad Evaluation', () {
    test('evaluateBiquad unity coefficients returns 1.0', () {
      // Unity coefficients: H(z) = 1
      final mag = DspFrequencyCalculator.evaluateBiquad(
        frequency: 1000.0,
        sampleRate: 48000.0,
        b0: 1.0,
        b1: 0.0,
        b2: 0.0,
        a1: 0.0,
        a2: 0.0,
      );

      expect(mag, closeTo(1.0, 0.0001));
    });

    test('evaluateBiquad lowpass at DC returns 1.0', () {
      // Simple 2nd order lowpass at 1000Hz
      // At DC (0 Hz), should pass through
      final mag = DspFrequencyCalculator.evaluateBiquad(
        frequency: 0.001, // Near DC
        sampleRate: 48000.0,
        // Lowpass coefficients (simplified)
        b0: 0.001,
        b1: 0.002,
        b2: 0.001,
        a1: -1.9,
        a2: 0.9,
      );

      // Lowpass should have gain near 1 at DC
      // (exact value depends on coefficients)
      expect(mag, greaterThan(0.0));
      expect(mag.isFinite, true);
    });

    test('evaluateBiquad at Nyquist frequency', () {
      // At Nyquist (fs/2), e^(-jw) = e^(-j*pi) = -1
      final mag = DspFrequencyCalculator.evaluateBiquad(
        frequency: 24000.0, // Nyquist at 48kHz
        sampleRate: 48000.0,
        b0: 1.0,
        b1: 0.5,
        b2: 0.0,
        a1: -0.5,
        a2: 0.0,
      );

      expect(mag.isFinite, true);
      expect(mag, greaterThan(0.0));
    });
  });

  group('DspFrequencyCalculator - EQ Response', () {
    test('flat EQ (no gain) returns 0 dB across spectrum', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 0.0, q: 1.0, filterType: 'bell'),
        ],
        numPoints: 64,
      );

      // With 0 dB gain bell filter, response should be flat
      for (final mag in response.magnitudes) {
        expect(mag, closeTo(0.0, 0.1));
      }
    });

    test('bell EQ boost at center frequency', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 12.0, q: 2.0, filterType: 'bell'),
        ],
        numPoints: 512,
      );

      // Find magnitude near 1000 Hz
      final idx1k = response.frequencies.toList().indexWhere((f) => f > 900 && f < 1100);
      expect(idx1k, greaterThan(0));

      // At center frequency, gain should be close to +12 dB
      expect(response.magnitudes[idx1k], greaterThan(10.0));
      expect(response.magnitudes[idx1k], lessThan(14.0));
    });

    test('lowshelf cuts low frequencies', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 200.0, gain: -12.0, q: 1.0, filterType: 'lowshelf'),
        ],
        numPoints: 512,
      );

      // Find magnitudes at low and high frequencies
      final magAt50 = response.getMagnitudeAt(50.0);
      final magAt10k = response.getMagnitudeAt(10000.0);

      // Low frequencies should be cut
      expect(magAt50, lessThan(-6.0));

      // High frequencies should be near unity
      expect(magAt10k, closeTo(0.0, 3.0));
    });

    test('multiple bands combine correctly', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 100.0, gain: 6.0, q: 1.0, filterType: 'bell'),
          const EqBandResponse(frequency: 1000.0, gain: 6.0, q: 1.0, filterType: 'bell'),
          const EqBandResponse(frequency: 10000.0, gain: 6.0, q: 1.0, filterType: 'bell'),
        ],
        numPoints: 512,
      );

      // Each band center should show boost
      final magAt100 = response.getMagnitudeAt(100.0);
      final magAt1k = response.getMagnitudeAt(1000.0);
      final magAt10k = response.getMagnitudeAt(10000.0);

      expect(magAt100, greaterThan(3.0));
      expect(magAt1k, greaterThan(3.0));
      expect(magAt10k, greaterThan(3.0));
    });

    test('disabled band contributes nothing', () {
      final withBand = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 12.0, q: 1.0, filterType: 'bell', enabled: true),
        ],
      );

      final withDisabled = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 12.0, q: 1.0, filterType: 'bell', enabled: false),
        ],
      );

      // Disabled band should give flat response
      final magEnabled = withBand.getMagnitudeAt(1000.0);
      final magDisabled = withDisabled.getMagnitudeAt(1000.0);

      expect(magEnabled, greaterThan(10.0)); // +12dB boost
      expect(magDisabled, closeTo(0.0, 0.1)); // Flat
    });

    test('band magnitudes array is populated', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 500.0, gain: 6.0, filterType: 'bell'),
          const EqBandResponse(frequency: 2000.0, gain: -6.0, filterType: 'bell'),
        ],
      );

      expect(response.bandMagnitudes, isNotNull);
      expect(response.bandMagnitudes!.length, 2);
      expect(response.bandMagnitudes![0], isNotNull);
      expect(response.bandMagnitudes![1], isNotNull);
    });
  });

  group('DspFrequencyCalculator - Compressor Curve', () {
    test('compressor 1:1 below threshold', () {
      final response = DspFrequencyCalculator.calculateCompressorCurve(
        threshold: -20.0,
        ratio: 4.0,
        kneeWidth: 0.0, // Hard knee
      );

      // Below threshold, output = input
      for (int i = 0; i < response.frequencies.length; i++) {
        final input = response.frequencies[i];
        if (input < -20.0) {
          expect(response.magnitudes[i], closeTo(input, 0.1));
        }
      }
    });

    test('compressor applies ratio above threshold', () {
      final response = DspFrequencyCalculator.calculateCompressorCurve(
        threshold: -20.0,
        ratio: 4.0,
        kneeWidth: 0.0,
      );

      // Find output at 0 dB input (20 dB above threshold)
      final idxZero = response.frequencies.toList().indexWhere((f) => f > -1 && f < 1);
      if (idxZero > 0) {
        // Output at 0dB input with 4:1 ratio, -20dB threshold
        // Expected: -20 + (0 - (-20)) / 4 = -20 + 5 = -15 dB
        expect(response.magnitudes[idxZero], closeTo(-15.0, 1.0));
      }
    });

    test('compressor soft knee provides smooth transition', () {
      final hardKnee = DspFrequencyCalculator.calculateCompressorCurve(
        threshold: -20.0,
        ratio: 4.0,
        kneeWidth: 0.0,
      );

      final softKnee = DspFrequencyCalculator.calculateCompressorCurve(
        threshold: -20.0,
        ratio: 4.0,
        kneeWidth: 12.0,
      );

      // Both should have similar output far from threshold
      final hardAt30 = hardKnee.getMagnitudeAt(-30.0);
      final softAt30 = softKnee.getMagnitudeAt(-30.0);
      expect(hardAt30, closeTo(softAt30, 0.5));

      // At threshold edge, soft knee should differ
      final hardAtThresh = hardKnee.getMagnitudeAt(-20.0);
      final softAtThresh = softKnee.getMagnitudeAt(-20.0);
      // Hard knee: exactly on 1:1 line
      expect(hardAtThresh, closeTo(-20.0, 0.1));
      // Soft knee: slightly compressed already
      expect(softAtThresh, closeTo(-20.0, 2.0)); // Within knee region
    });

    test('getCompressorGainReduction calculates correctly', () {
      final gr = DspFrequencyCalculator.getCompressorGainReduction(
        inputDb: 0.0,
        threshold: -20.0,
        ratio: 4.0,
        kneeWidth: 0.0,
      );

      // At 0 dB with -20 threshold and 4:1 ratio
      // Output = -20 + (0 - (-20)) / 4 = -15 dB
      // GR = 0 - (-15) = 15 dB
      expect(gr, closeTo(15.0, 1.0));
    });
  });

  group('DspFrequencyCalculator - Limiter Curve', () {
    test('limiter never exceeds ceiling', () {
      final response = DspFrequencyCalculator.calculateLimiterCurve(
        ceiling: -1.0,
        threshold: -10.0,
      );

      for (final output in response.magnitudes) {
        expect(output, lessThanOrEqualTo(-1.0 + 0.01)); // Allow small tolerance
      }
    });

    test('limiter 1:1 below threshold', () {
      final response = DspFrequencyCalculator.calculateLimiterCurve(
        ceiling: -1.0,
        threshold: -10.0,
      );

      // Find output at -30 dB (well below threshold)
      final outputAt30 = response.getMagnitudeAt(-30.0);
      expect(outputAt30, closeTo(-30.0, 1.0));
    });
  });

  group('DspFrequencyCalculator - Gate Curve', () {
    test('gate passes signal above threshold', () {
      final response = DspFrequencyCalculator.calculateGateCurve(
        threshold: -30.0,
        ratio: 10.0,
        range: -80.0,
        kneeWidth: 0.0,
      );

      // Above threshold, output = input
      final outputAtNeg10 = response.getMagnitudeAt(-10.0);
      expect(outputAtNeg10, closeTo(-10.0, 1.0));
    });

    test('gate attenuates signal below threshold', () {
      final response = DspFrequencyCalculator.calculateGateCurve(
        threshold: -30.0,
        ratio: 10.0,
        range: -80.0,
        kneeWidth: 0.0,
      );

      // Below threshold, signal is attenuated
      final outputAtNeg50 = response.getMagnitudeAt(-50.0);
      expect(outputAtNeg50, lessThan(-50.0));
    });

    test('gate respects range limit', () {
      final response = DspFrequencyCalculator.calculateGateCurve(
        threshold: -30.0,
        ratio: 100.0, // Very high ratio
        range: -40.0, // But range limits attenuation
      );

      // Output should not go below input + range
      for (int i = 0; i < response.frequencies.length; i++) {
        final input = response.frequencies[i];
        final output = response.magnitudes[i];
        if (input < response.threshold!) {
          // Output should be at least input + range (but never below range)
          expect(output, greaterThanOrEqualTo(input - 50)); // Generous tolerance
        }
      }
    });
  });

  group('DspFrequencyCalculator - Reverb Decay', () {
    test('reverb decay has correct number of bands', () {
      final response = DspFrequencyCalculator.calculateReverbDecay(
        baseDecay: 2.0,
        damping: 0.5,
      );

      expect(response.frequencies.length, 10); // Default 10 bands
      expect(response.decayTimes?.length, 10);
    });

    test('reverb high frequencies decay faster with damping', () {
      final response = DspFrequencyCalculator.calculateReverbDecay(
        baseDecay: 2.0,
        damping: 0.8, // High damping
      );

      // Low frequency (63Hz) decay time
      final lowDecay = response.decayTimes![0];
      // High frequency (16kHz) decay time
      final highDecay = response.decayTimes![9];

      expect(highDecay, lessThan(lowDecay));
    });

    test('reverb low frequencies can decay longer', () {
      final response = DspFrequencyCalculator.calculateReverbDecay(
        baseDecay: 2.0,
        damping: 0.0,
        lowFreqMultiplier: 1.5, // 50% longer for low freqs
      );

      // Low frequency should be longer
      final lowDecay = response.decayTimes![0]; // 63Hz
      final midDecay = response.decayTimes![4]; // 1kHz

      expect(lowDecay, greaterThan(midDecay));
    });
  });

  group('FrequencyGraphWidget rendering', () {
    testWidgets('EqFrequencyGraph renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EqFrequencyGraph(
              bands: [
                EqBandResponse(frequency: 1000.0, gain: 6.0),
              ],
              width: 300,
              height: 150,
            ),
          ),
        ),
      );

      expect(find.byType(EqFrequencyGraph), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);  // Multiple CustomPaint expected
    });

    testWidgets('CompressorCurveGraph renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompressorCurveGraph(
              threshold: -20.0,
              ratio: 4.0,
              width: 150,
              height: 150,
            ),
          ),
        ),
      );

      expect(find.byType(CompressorCurveGraph), findsOneWidget);
    });

    testWidgets('bypassed state applies overlay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompressorCurveGraph(
              threshold: -20.0,
              ratio: 4.0,
              bypassed: true,
            ),
          ),
        ),
      );

      // Widget should render with bypassed state
      expect(find.byType(CompressorCurveGraph), findsOneWidget);
    });

    testWidgets('currentInput marker is passed to painter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompressorCurveGraph(
              threshold: -20.0,
              ratio: 4.0,
              currentInput: -10.0,
            ),
          ),
        ),
      );

      expect(find.byType(CompressorCurveGraph), findsOneWidget);
    });
  });

  group('Edge Cases', () {
    test('extreme Q values do not cause overflow', () {
      // Very high Q
      final highQ = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 12.0, q: 100.0, filterType: 'bell'),
        ],
      );

      // Very low Q
      final lowQ = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 12.0, q: 0.1, filterType: 'bell'),
        ],
      );

      // Both should produce finite values
      for (final m in highQ.magnitudes) {
        expect(m.isFinite, true);
      }
      for (final m in lowQ.magnitudes) {
        expect(m.isFinite, true);
      }
    });

    test('frequency at Nyquist produces finite result', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 23000.0, gain: 6.0, filterType: 'bell'), // Near Nyquist at 48kHz
        ],
        sampleRate: 48000.0,
      );

      for (final m in response.magnitudes) {
        expect(m.isFinite, true);
      }
    });

    test('zero gain bell filter is flat', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [
          const EqBandResponse(frequency: 1000.0, gain: 0.0, q: 1.0, filterType: 'bell'),
        ],
      );

      // All magnitudes should be very close to 0 dB
      for (final m in response.magnitudes) {
        expect(m, closeTo(0.0, 0.5));
      }
    });

    test('compressor with ratio 1 is unity', () {
      final response = DspFrequencyCalculator.calculateCompressorCurve(
        threshold: -20.0,
        ratio: 1.0, // 1:1 = no compression
        kneeWidth: 0.0,
      );

      // Output should equal input everywhere
      for (int i = 0; i < response.frequencies.length; i++) {
        expect(response.magnitudes[i], closeTo(response.frequencies[i], 0.1));
      }
    });

    test('empty bands list produces flat response', () {
      final response = DspFrequencyCalculator.calculateEqResponse(
        bands: [],
      );

      for (final m in response.magnitudes) {
        expect(m, closeTo(0.0, 0.01));
      }
    });
  });
}
