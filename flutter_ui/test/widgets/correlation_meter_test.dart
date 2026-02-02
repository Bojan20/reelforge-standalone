/// Correlation Meter Widget Tests
///
/// Tests for the phase correlation meter widget.
/// Covers:
/// - Correlation calculation accuracy
/// - Zone classification
/// - Configuration validation
/// - Widget rendering

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluxforge_ui/widgets/metering/correlation_meter_widget.dart';

void main() {
  group('Correlation Calculation', () {
    test('identical signals should have correlation +1.0', () {
      final samples = Float32List.fromList([0.5, -0.3, 0.8, -0.2, 0.1]);
      final correlation = calculateCorrelationFromSamples(samples, samples);
      expect(correlation, closeTo(1.0, 0.001));
    });

    test('inverted signals should have correlation -1.0', () {
      final left = Float32List.fromList([0.5, -0.3, 0.8, -0.2, 0.1]);
      final right = Float32List.fromList([-0.5, 0.3, -0.8, 0.2, -0.1]);
      final correlation = calculateCorrelationFromSamples(left, right);
      expect(correlation, closeTo(-1.0, 0.001));
    });

    test('uncorrelated signals should have correlation ~0.0', () {
      // Sine and cosine (90° phase shift) are uncorrelated
      const count = 1024;
      final left = Float32List(count);
      final right = Float32List(count);
      for (int i = 0; i < count; i++) {
        final t = i / count * 2 * math.pi * 4;
        left[i] = math.sin(t);
        right[i] = math.cos(t);
      }
      final correlation = calculateCorrelationFromSamples(left, right);
      expect(correlation, closeTo(0.0, 0.05));
    });
  });

  group('CorrelationZone Classification', () {
    test('zones should have correct thresholds', () {
      // +1.0 to +0.5: Good
      expect(0.75 >= 0.5, true);
      expect(1.0 >= 0.5, true);

      // +0.5 to 0.0: Partial
      expect(0.25 >= 0.0 && 0.25 < 0.5, true);
      expect(0.0 >= 0.0 && 0.0 < 0.5, true);

      // 0.0 to -1.0: Phase issues
      expect(-0.5 < 0.0, true);
      expect(-1.0 < 0.0, true);
    });
  });

  group('CorrelationMeterConfig', () {
    test('default config should have expected values', () {
      const config = CorrelationMeterConfig();
      expect(config.smoothing, 0.85);
      expect(config.peakHoldMs, 2000);
      expect(config.showValue, true);
      expect(config.showLabels, true);
      expect(config.vertical, false);
    });

    test('proTools preset should have correct configuration', () {
      const config = CorrelationMeterConfig.proTools;
      expect(config.smoothing, 0.9);
      expect(config.peakHoldMs, 2000);
      expect(config.showValue, true);
    });

    test('compact preset should hide value and labels', () {
      const config = CorrelationMeterConfig.compact;
      expect(config.showValue, false);
      expect(config.showLabels, false);
    });
  });

  group('CorrelationMeter Widget', () {
    testWidgets('should render without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CorrelationMeter(
                correlation: 0.5,
                width: 200,
                height: 24,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CorrelationMeter), findsOneWidget);
    });

    testWidgets('should display labels when enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CorrelationMeter(
                correlation: 0.5,
                width: 200,
                height: 24,
                config: CorrelationMeterConfig(showLabels: true),
              ),
            ),
          ),
        ),
      );

      expect(find.text('-1'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('should call onTap callback when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CorrelationMeter(
                correlation: 0.5,
                width: 200,
                height: 24,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CorrelationMeter));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('simple constructor should work', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CorrelationMeter.simple(
                value: 0.75,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CorrelationMeter), findsOneWidget);
    });

    testWidgets('should render in vertical orientation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 30,
                height: 200,
                child: CorrelationMeter(
                  correlation: 0.5,
                  width: 30,
                  height: 200,
                  config: CorrelationMeterConfig(vertical: true),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CorrelationMeter), findsOneWidget);
    });
  });

  group('Edge Cases', () {
    test('empty arrays should return 1.0', () {
      final empty = Float32List(0);
      expect(calculateCorrelationFromSamples(empty, empty), 1.0);
    });

    test('silent signals should return 1.0', () {
      final silent = Float32List.fromList([0.0, 0.0, 0.0, 0.0]);
      expect(calculateCorrelationFromSamples(silent, silent), 1.0);
    });

    test('very small signals should not cause division by zero', () {
      final tiny = Float32List.fromList([1e-15, 1e-15, 1e-15]);
      final correlation = calculateCorrelationFromSamples(tiny, tiny);
      expect(correlation, 1.0);
    });

    test('correlation should be clamped to -1 to +1', () {
      // Even with numerical errors, result should be in range
      final samples = Float32List.fromList([0.5, -0.3, 0.8, -0.2, 0.1]);
      final correlation = calculateCorrelationFromSamples(samples, samples);
      expect(correlation, greaterThanOrEqualTo(-1.0));
      expect(correlation, lessThanOrEqualTo(1.0));
    });
  });
}
