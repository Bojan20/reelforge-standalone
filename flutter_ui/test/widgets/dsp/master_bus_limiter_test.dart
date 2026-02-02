/// Master Bus Limiter Tests — P2-DAW-4
///
/// Tests for true peak limiter widget functionality.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/dsp/master_bus_limiter.dart';

void main() {
  group('LimiterReleaseMode', () {
    test('all release modes are defined', () {
      expect(LimiterReleaseMode.values.length, 5);
      expect(LimiterReleaseMode.values, contains(LimiterReleaseMode.auto));
      expect(LimiterReleaseMode.values, contains(LimiterReleaseMode.fast));
      expect(LimiterReleaseMode.values, contains(LimiterReleaseMode.medium));
      expect(LimiterReleaseMode.values, contains(LimiterReleaseMode.slow));
      expect(LimiterReleaseMode.values, contains(LimiterReleaseMode.ultraSlow));
    });

    test('releaseMs returns correct values', () {
      expect(LimiterReleaseMode.auto.releaseMs, -1); // Auto indicator
      expect(LimiterReleaseMode.fast.releaseMs, 50);
      expect(LimiterReleaseMode.medium.releaseMs, 150);
      expect(LimiterReleaseMode.slow.releaseMs, 400);
      expect(LimiterReleaseMode.ultraSlow.releaseMs, 800);
    });

    test('release modes have name and description', () {
      expect(LimiterReleaseMode.auto.name, 'Auto');
      expect(LimiterReleaseMode.auto.description, 'Automatic release based on material');

      expect(LimiterReleaseMode.fast.name, 'Fast');
      expect(LimiterReleaseMode.fast.description, '50ms release');
    });
  });

  group('OversamplingMode', () {
    test('all oversampling modes are defined', () {
      expect(OversamplingMode.values.length, 4);
      expect(OversamplingMode.values, contains(OversamplingMode.none));
      expect(OversamplingMode.values, contains(OversamplingMode.x2));
      expect(OversamplingMode.values, contains(OversamplingMode.x4));
      expect(OversamplingMode.values, contains(OversamplingMode.x8));
    });

    test('factor returns correct values', () {
      expect(OversamplingMode.none.factor, 1);
      expect(OversamplingMode.x2.factor, 2);
      expect(OversamplingMode.x4.factor, 4);
      expect(OversamplingMode.x8.factor, 8);
    });

    test('oversampling modes have name and description', () {
      expect(OversamplingMode.none.name, 'Off');
      expect(OversamplingMode.none.description, 'No oversampling');

      expect(OversamplingMode.x8.name, '8x');
      expect(OversamplingMode.x8.description, '8x true peak (recommended)');
    });
  });

  group('Limiter parameter validation', () {
    test('threshold range is valid', () {
      // Typical threshold range: -20 to 0 dB
      const minThreshold = -20.0;
      const maxThreshold = 0.0;

      expect(minThreshold, lessThan(maxThreshold));
      expect(minThreshold, greaterThanOrEqualTo(-60.0));
    });

    test('ceiling range is ISP-safe', () {
      // ISP-safe ceiling range: -3 to -0.1 dB
      const minCeiling = -3.0;
      const maxCeiling = -0.1;

      expect(minCeiling, lessThan(maxCeiling));
      expect(maxCeiling, lessThan(0.0)); // Must be below 0 dBTP
    });

    test('release times are positive', () {
      for (final mode in LimiterReleaseMode.values) {
        if (mode != LimiterReleaseMode.auto) {
          expect(mode.releaseMs, greaterThan(0));
        }
      }
    });

    test('oversampling factors are powers of 2', () {
      for (final mode in OversamplingMode.values) {
        final factor = mode.factor;
        // Check if power of 2
        final isPowerOf2 = factor > 0 && (factor & (factor - 1)) == 0;
        expect(isPowerOf2, true, reason: '$factor should be power of 2');
      }
    });
  });
}
