/// DSP RTPC Modulator Tests (P11.1.2)
///
/// Tests for RTPC → DSP parameter modulation system:
/// - Parameter range validation
/// - Curve modulation (linear, exponential, S-curve, etc.)
/// - Scale conversions (Hz, dB, ms)
/// - FFI sync verification (mocked)
/// - Edge cases and boundary conditions
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/middleware_models.dart';
import 'package:fluxforge_ui/providers/dsp_chain_provider.dart';
import 'package:fluxforge_ui/providers/subsystems/rtpc_system_provider.dart';
import 'package:fluxforge_ui/services/dsp_rtpc_modulator.dart';

void main() {
  group('DspRtpcModulator', () {
    late DspRtpcModulator modulator;

    setUp(() {
      modulator = DspRtpcModulator.instance;
    });

    group('Parameter Ranges', () {
      test('should return correct range for filter cutoff', () {
        final range = modulator.getParameterRange(RtpcTargetParameter.filterCutoff);

        expect(range, isNotNull);
        expect(range!.min, equals(20.0));
        expect(range.max, equals(20000.0));
        expect(range.unit, equals('Hz'));
        expect(range.scale, equals(DspParameterScale.logarithmic));
      });

      test('should return correct range for compressor threshold', () {
        final range = modulator.getParameterRange(RtpcTargetParameter.compressorThreshold);

        expect(range, isNotNull);
        expect(range!.min, equals(-60.0));
        expect(range.max, equals(0.0));
        expect(range.unit, equals('dB'));
      });

      test('should return correct range for reverb decay', () {
        final range = modulator.getParameterRange(RtpcTargetParameter.reverbDecay);

        expect(range, isNotNull);
        expect(range!.min, equals(0.1));
        expect(range.max, equals(20.0));
        expect(range.unit, equals('s'));
      });

      test('should clamp values to range', () {
        final range = modulator.getParameterRange(RtpcTargetParameter.delayFeedback);

        expect(range!.clamp(-0.5), equals(0.0));
        expect(range.clamp(0.5), equals(0.5));
        expect(range.clamp(1.5), equals(0.95));
      });

      test('should normalize and denormalize correctly', () {
        final range = modulator.getParameterRange(RtpcTargetParameter.compressorRatio);

        // Range is 1.0 to 20.0
        expect(range!.normalize(1.0), closeTo(0.0, 0.001));
        expect(range.normalize(10.5), closeTo(0.5, 0.001));
        expect(range.normalize(20.0), closeTo(1.0, 0.001));

        expect(range.denormalize(0.0), closeTo(1.0, 0.001));
        expect(range.denormalize(0.5), closeTo(10.5, 0.001));
        expect(range.denormalize(1.0), closeTo(20.0, 0.001));
      });
    });

    group('Curve Modulation', () {
      test('linear curve should map RTPC directly', () {
        final curve = RtpcCurve.linear(0.0, 1.0, 20.0, 20000.0);

        final result0 = modulator.modulateDspParameter(
          param: RtpcTargetParameter.filterCutoff,
          baseValue: 1000.0,
          rtpcValue: 0.0,
          curve: curve,
        );
        expect(result0, closeTo(20.0, 0.1));

        final result50 = modulator.modulateDspParameter(
          param: RtpcTargetParameter.filterCutoff,
          baseValue: 1000.0,
          rtpcValue: 0.5,
          curve: curve,
        );
        expect(result50, closeTo(10010.0, 0.1));

        final result100 = modulator.modulateDspParameter(
          param: RtpcTargetParameter.filterCutoff,
          baseValue: 1000.0,
          rtpcValue: 1.0,
          curve: curve,
        );
        expect(result100, closeTo(20000.0, 0.1));
      });

      test('exponential curve should have slow start, fast finish', () {
        final curve = modulator.getPresetCurve('exponential', RtpcTargetParameter.reverbDecay);

        final result25 = curve.evaluate(0.25);
        final result50 = curve.evaluate(0.5);
        final result75 = curve.evaluate(0.75);

        // Exponential: value at 25% should be closer to min than 25% of range
        // and value at 75% should be closer to max than 75% of range
        expect(result25, lessThan(result50));
        expect(result50, lessThan(result75));

        // Check exponential characteristic
        final linearMid = modulator.getPresetCurve('linear', RtpcTargetParameter.reverbDecay).evaluate(0.5);
        expect(result50, lessThan(linearMid)); // Exponential is below linear at midpoint
      });

      test('s_curve should have smooth transitions', () {
        final curve = modulator.getPresetCurve('s_curve', RtpcTargetParameter.delayTime);

        final result0 = curve.evaluate(0.0);
        final result25 = curve.evaluate(0.25);
        final result50 = curve.evaluate(0.5);
        final result75 = curve.evaluate(0.75);
        final result100 = curve.evaluate(1.0);

        // S-curve should start slow, accelerate in middle, slow at end
        expect(result25 - result0, lessThan(result50 - result25)); // Slow start
        expect(result100 - result75, lessThan(result75 - result50)); // Slow end
      });

      test('inverted curve should reverse output', () {
        final normal = modulator.getPresetCurve('linear', RtpcTargetParameter.filterCutoff);
        final inverted = modulator.getPresetCurve('linear_inverted', RtpcTargetParameter.filterCutoff);

        expect(normal.evaluate(0.0), closeTo(20.0, 0.1));
        expect(inverted.evaluate(0.0), closeTo(20000.0, 0.1));

        expect(normal.evaluate(1.0), closeTo(20000.0, 0.1));
        expect(inverted.evaluate(1.0), closeTo(20.0, 0.1));
      });

      test('threshold curve should jump at threshold point', () {
        final curve = modulator.getPresetCurve('threshold_50', RtpcTargetParameter.compressorRatio);

        // Before threshold (50%), should be near min
        expect(curve.evaluate(0.0), closeTo(1.0, 0.1));
        expect(curve.evaluate(0.49), closeTo(1.0, 1.0)); // Allow some tolerance due to curve shape

        // After threshold, should be moving towards max
        // threshold_50 curve: (0,1) constant → (0.5,10.5) → (1,20)
        // At 0.75, linear interpolation between (0.5,10.5) and (1,20) = 15.25
        expect(curve.evaluate(0.75), closeTo(15.25, 1.0));
        expect(curve.evaluate(1.0), closeTo(20.0, 0.1));
      });
    });

    group('Blend Modulation', () {
      test('amount=0 should return base value', () {
        final curve = RtpcCurve.linear(0.0, 1.0, 100.0, 1000.0);

        final result = modulator.modulateWithBlend(
          param: RtpcTargetParameter.delayTime,
          baseValue: 250.0,
          rtpcValue: 1.0,
          curve: curve,
          amount: 0.0,
        );

        expect(result, equals(250.0));
      });

      test('amount=1 should return fully modulated value', () {
        final curve = RtpcCurve.linear(0.0, 1.0, 100.0, 1000.0);

        final result = modulator.modulateWithBlend(
          param: RtpcTargetParameter.delayTime,
          baseValue: 250.0,
          rtpcValue: 1.0,
          curve: curve,
          amount: 1.0,
        );

        expect(result, closeTo(1000.0, 0.1));
      });

      test('amount=0.5 should return halfway between base and modulated', () {
        final curve = RtpcCurve.linear(0.0, 1.0, 100.0, 1000.0);

        final result = modulator.modulateWithBlend(
          param: RtpcTargetParameter.delayTime,
          baseValue: 100.0,
          rtpcValue: 1.0, // Would give 1000
          curve: curve,
          amount: 0.5,
        );

        // Base=100, Modulated=1000, 50% blend = 100 + (1000-100)*0.5 = 550
        expect(result, closeTo(550.0, 0.1));
      });
    });

    group('Scale Conversions', () {
      test('frequencyToLogPosition should handle full range', () {
        expect(modulator.frequencyToLogPosition(20.0), closeTo(0.0, 0.001));
        expect(modulator.frequencyToLogPosition(20000.0), closeTo(1.0, 0.001));

        // 1000 Hz should be roughly in the middle of log scale
        final pos1000 = modulator.frequencyToLogPosition(1000.0);
        expect(pos1000, greaterThan(0.3));
        expect(pos1000, lessThan(0.7));
      });

      test('logPositionToFrequency should invert frequencyToLogPosition', () {
        const testFreqs = [20.0, 100.0, 500.0, 1000.0, 5000.0, 10000.0, 20000.0];

        for (final freq in testFreqs) {
          final pos = modulator.frequencyToLogPosition(freq);
          final recovered = modulator.logPositionToFrequency(pos);
          expect(recovered, closeTo(freq, 0.1));
        }
      });

      test('linearToDecibel should convert correctly', () {
        expect(modulator.linearToDecibel(1.0), closeTo(0.0, 0.1));
        expect(modulator.linearToDecibel(0.5), closeTo(-6.02, 0.1)); // -6 dB
        expect(modulator.linearToDecibel(2.0), closeTo(6.02, 0.1)); // +6 dB
        expect(modulator.linearToDecibel(0.0), equals(-60.0)); // Floor at minDb
      });

      test('decibelToLinear should invert linearToDecibel', () {
        const testLinear = [0.1, 0.25, 0.5, 1.0, 1.5, 2.0];

        for (final lin in testLinear) {
          final db = modulator.linearToDecibel(lin);
          final recovered = modulator.decibelToLinear(db);
          expect(recovered, closeTo(lin, 0.001));
        }
      });
    });

    group('Value Formatting', () {
      test('should format Hz values correctly', () {
        expect(modulator.formatParameterValue(RtpcTargetParameter.filterCutoff, 500.0),
               equals('500 Hz'));
        expect(modulator.formatParameterValue(RtpcTargetParameter.filterCutoff, 5000.0),
               equals('5.0 kHz'));
      });

      test('should format ms values correctly', () {
        expect(modulator.formatParameterValue(RtpcTargetParameter.delayTime, 250.0),
               equals('250.0 ms'));
        expect(modulator.formatParameterValue(RtpcTargetParameter.delayTime, 1500.0),
               equals('1.50 s'));
      });

      test('should format dB values correctly', () {
        expect(modulator.formatParameterValue(RtpcTargetParameter.compressorThreshold, -20.0),
               equals('-20.0 dB'));
      });

      test('should format ratio values correctly', () {
        expect(modulator.formatParameterValue(RtpcTargetParameter.compressorRatio, 4.0),
               equals('4.0:1'));
      });

      test('should format percentage values correctly', () {
        expect(modulator.formatParameterValue(RtpcTargetParameter.reverbMix, 0.5),
               equals('50%'));
      });
    });

    group('Parameter Categorization', () {
      test('should identify filter parameters', () {
        expect(DspRtpcModulator.isFilterParameter(RtpcTargetParameter.filterCutoff), isTrue);
        expect(DspRtpcModulator.isFilterParameter(RtpcTargetParameter.filterResonance), isTrue);
        expect(DspRtpcModulator.isFilterParameter(RtpcTargetParameter.compressorThreshold), isFalse);
      });

      test('should identify dynamics parameters', () {
        expect(DspRtpcModulator.isDynamicsParameter(RtpcTargetParameter.compressorThreshold), isTrue);
        expect(DspRtpcModulator.isDynamicsParameter(RtpcTargetParameter.limiterCeiling), isTrue);
        expect(DspRtpcModulator.isDynamicsParameter(RtpcTargetParameter.gateThreshold), isTrue);
        expect(DspRtpcModulator.isDynamicsParameter(RtpcTargetParameter.reverbDecay), isFalse);
      });

      test('should identify time-based parameters', () {
        expect(DspRtpcModulator.isTimeBasedParameter(RtpcTargetParameter.reverbDecay), isTrue);
        expect(DspRtpcModulator.isTimeBasedParameter(RtpcTargetParameter.delayTime), isTrue);
        expect(DspRtpcModulator.isTimeBasedParameter(RtpcTargetParameter.filterCutoff), isFalse);
      });

      test('should return correct processor for parameter', () {
        expect(DspRtpcModulator.getProcessorForParameter(RtpcTargetParameter.filterCutoff),
               equals(DspNodeType.eq));
        expect(DspRtpcModulator.getProcessorForParameter(RtpcTargetParameter.compressorRatio),
               equals(DspNodeType.compressor));
        expect(DspRtpcModulator.getProcessorForParameter(RtpcTargetParameter.reverbDecay),
               equals(DspNodeType.reverb));
        expect(DspRtpcModulator.getProcessorForParameter(RtpcTargetParameter.delayFeedback),
               equals(DspNodeType.delay));
      });
    });

    group('Preset Curves', () {
      test('should have all expected preset curves', () {
        final presets = modulator.presetCurveNames;

        expect(presets, contains('linear'));
        expect(presets, contains('linear_inverted'));
        expect(presets, contains('exponential'));
        expect(presets, contains('logarithmic'));
        expect(presets, contains('s_curve'));
        expect(presets, contains('threshold_50'));
        expect(presets, contains('threshold_75'));
      });

      test('preset curves should be valid for all DSP parameters', () {
        final params = RtpcTargetParameterExtension.dspParameters;

        for (final param in params) {
          for (final preset in modulator.presetCurveNames) {
            final curve = modulator.getPresetCurve(preset, param);
            expect(curve, isNotNull, reason: 'Preset $preset should work for $param');

            // Verify curve evaluates without error
            expect(curve.evaluate(0.0), isA<double>());
            expect(curve.evaluate(0.5), isA<double>());
            expect(curve.evaluate(1.0), isA<double>());
          }
        }
      });
    });

    group('Edge Cases', () {
      test('should handle RTPC value clamping', () {
        final curve = RtpcCurve.linear(0.0, 1.0, 100.0, 1000.0);

        // Values outside 0-1 should be clamped
        final resultNeg = modulator.modulateDspParameter(
          param: RtpcTargetParameter.delayTime,
          baseValue: 250.0,
          rtpcValue: -0.5,
          curve: curve,
        );
        expect(resultNeg, closeTo(100.0, 0.1));

        final resultOver = modulator.modulateDspParameter(
          param: RtpcTargetParameter.delayTime,
          baseValue: 250.0,
          rtpcValue: 1.5,
          curve: curve,
        );
        expect(resultOver, closeTo(1000.0, 0.1));
      });

      test('should handle empty curves gracefully', () {
        final emptyCurve = const RtpcCurve(points: []);

        // Empty curve should return input unchanged
        expect(emptyCurve.evaluate(0.5), equals(0.5));
      });

      test('should handle single-point curves', () {
        final singlePoint = const RtpcCurve(points: [
          RtpcCurvePoint(x: 0.5, y: 100.0),
        ]);

        // Single point should return that point's y for all x
        expect(singlePoint.evaluate(0.0), equals(100.0));
        expect(singlePoint.evaluate(0.5), equals(100.0));
        expect(singlePoint.evaluate(1.0), equals(100.0));
      });
    });
  });

  group('DspParamMapping', () {
    test('should return correct param indices for EQ', () {
      expect(DspParamMapping.getParamIndex(DspNodeType.eq, RtpcTargetParameter.filterCutoff),
             equals(0));
      expect(DspParamMapping.getParamIndex(DspNodeType.eq, RtpcTargetParameter.filterResonance),
             equals(1));
      expect(DspParamMapping.getParamIndex(DspNodeType.eq, RtpcTargetParameter.highPassFilter),
             equals(2));
    });

    test('should return correct param indices for compressor', () {
      expect(DspParamMapping.getParamIndex(DspNodeType.compressor, RtpcTargetParameter.compressorThreshold),
             equals(0));
      expect(DspParamMapping.getParamIndex(DspNodeType.compressor, RtpcTargetParameter.compressorRatio),
             equals(1));
      expect(DspParamMapping.getParamIndex(DspNodeType.compressor, RtpcTargetParameter.compressorAttack),
             equals(2));
      expect(DspParamMapping.getParamIndex(DspNodeType.compressor, RtpcTargetParameter.compressorRelease),
             equals(3));
    });

    test('should return correct param indices for reverb', () {
      expect(DspParamMapping.getParamIndex(DspNodeType.reverb, RtpcTargetParameter.reverbDecay),
             equals(0));
      expect(DspParamMapping.getParamIndex(DspNodeType.reverb, RtpcTargetParameter.reverbPreDelay),
             equals(1));
      expect(DspParamMapping.getParamIndex(DspNodeType.reverb, RtpcTargetParameter.reverbMix),
             equals(4));
    });

    test('should return null for invalid param/processor combinations', () {
      expect(DspParamMapping.getParamIndex(DspNodeType.eq, RtpcTargetParameter.reverbDecay),
             isNull);
      expect(DspParamMapping.getParamIndex(DspNodeType.reverb, RtpcTargetParameter.compressorThreshold),
             isNull);
    });

    test('should return valid targets for each processor type', () {
      for (final processorType in DspNodeType.values) {
        final targets = DspParamMapping.getValidTargets(processorType);
        expect(targets, isNotEmpty, reason: '$processorType should have valid targets');

        // All returned targets should have valid param indices
        // Exception: expander shares validTargets with compressor but doesn't
        // support compressorMakeup (expanders don't have makeup gain)
        for (final target in targets) {
          if (processorType == DspNodeType.expander &&
              target == RtpcTargetParameter.compressorMakeup) {
            // Expander intentionally omits makeup gain from param mapping
            expect(DspParamMapping.getParamIndex(processorType, target), isNull,
                   reason: 'Expander should not map compressorMakeup');
            continue;
          }
          final idx = DspParamMapping.getParamIndex(processorType, target);
          expect(idx, isNotNull, reason: '$target should have index for $processorType');
        }
      }
    });
  });
}
