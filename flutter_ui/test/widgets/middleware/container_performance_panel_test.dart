import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_studio/widgets/middleware/container_performance_panel.dart';
import 'package:fluxforge_studio/services/container_metering_service.dart';

void main() {
  group('ContainerPerformancePanel', () {
    testWidgets('renders header and summary cards', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: ContainerPerformancePanel(),
            ),
          ),
        ),
      );

      // Header should be present
      expect(find.text('CONTAINER PERFORMANCE'), findsOneWidget);

      // Summary cards should show container types
      expect(find.text('Blend'), findsOneWidget);
      expect(find.text('Random'), findsOneWidget);
      expect(find.text('Sequence'), findsOneWidget);
    });

    testWidgets('shows performance graph when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: ContainerPerformancePanel(showGraph: true),
            ),
          ),
        ),
      );

      // Graph header should be present
      expect(find.text('LATENCY HISTORY'), findsOneWidget);
    });

    testWidgets('shows container details when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: ContainerPerformancePanel(showDetails: true),
            ),
          ),
        ),
      );

      // Details header should be present
      expect(find.text('CONTAINER DETAILS'), findsOneWidget);
    });

    testWidgets('compact mode shows minimal UI', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 60,
              child: ContainerPerformancePanel(compactMode: true),
            ),
          ),
        ),
      );

      // Should show avg latency
      expect(find.textContaining('Avg:'), findsOneWidget);

      // Should NOT show full header
      expect(find.text('CONTAINER PERFORMANCE'), findsNothing);
    });

    testWidgets('pause button toggles refresh', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: ContainerPerformancePanel(),
            ),
          ),
        ),
      );

      // Find pause button
      final pauseButton = find.byTooltip('Pause');
      expect(pauseButton, findsOneWidget);

      // Tap to pause
      await tester.tap(pauseButton);
      await tester.pump();

      // Should now show resume tooltip
      expect(find.byTooltip('Resume'), findsOneWidget);
    });

    testWidgets('clear button resets data', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: ContainerPerformancePanel(),
            ),
          ),
        ),
      );

      // Find clear button
      final clearButton = find.byTooltip('Clear');
      expect(clearButton, findsOneWidget);

      // Tap should not throw
      await tester.tap(clearButton);
      await tester.pump();
    });
  });

  group('ContainerMeteringService', () {
    late ContainerMeteringService service;

    setUp(() {
      service = ContainerMeteringService.instance;
      service.clearAll();
    });

    test('recordEvaluation adds metrics', () {
      final metrics = ContainerEvaluationMetrics(
        containerId: 1,
        type: ContainerType.blend,
        timestamp: DateTime.now(),
        evaluationTimeMicros: 500,
        specificMetrics: {},
      );

      service.recordEvaluation(metrics);

      expect(service.trackedContainers, contains(1));
    });

    test('getStats returns null for untracked container', () {
      expect(service.getStats(999), isNull);
    });

    test('clearStats removes specific container', () {
      final metrics = ContainerEvaluationMetrics(
        containerId: 1,
        type: ContainerType.blend,
        timestamp: DateTime.now(),
        evaluationTimeMicros: 500,
        specificMetrics: {},
      );

      service.recordEvaluation(metrics);
      expect(service.trackedContainers, contains(1));

      service.clearStats(1);
      expect(service.trackedContainers, isNot(contains(1)));
    });

    test('clearAll removes all containers', () {
      service.recordEvaluation(ContainerEvaluationMetrics(
        containerId: 1,
        type: ContainerType.blend,
        timestamp: DateTime.now(),
        evaluationTimeMicros: 500,
        specificMetrics: {},
      ));

      service.recordEvaluation(ContainerEvaluationMetrics(
        containerId: 2,
        type: ContainerType.random,
        timestamp: DateTime.now(),
        evaluationTimeMicros: 300,
        specificMetrics: {},
      ));

      expect(service.trackedContainers.length, equals(2));

      service.clearAll();
      expect(service.trackedContainers, isEmpty);
    });

    test('getSummary returns correct structure', () {
      final summary = service.getSummary();

      expect(summary, containsPair('total_containers', isA<int>()));
      expect(summary, containsPair('total_evaluations', isA<int>()));
      expect(summary, containsPair('avg_latency_ms', isA<double>()));
    });
  });

  group('ContainerEvaluationMetrics', () {
    test('evaluationTimeMs converts correctly', () {
      final metrics = ContainerEvaluationMetrics(
        containerId: 1,
        type: ContainerType.blend,
        timestamp: DateTime.now(),
        evaluationTimeMicros: 1500, // 1.5ms
        specificMetrics: {},
      );

      expect(metrics.evaluationTimeMs, closeTo(1.5, 0.01));
    });
  });

  group('ContainerMeteringStats', () {
    test('p50Latency calculates correctly', () {
      final stats = ContainerMeteringStats(
        containerId: 1,
        type: ContainerType.blend,
      );

      // Add 10 samples
      for (var i = 1; i <= 10; i++) {
        stats.recordEvaluation(ContainerEvaluationMetrics(
          containerId: 1,
          type: ContainerType.blend,
          timestamp: DateTime.now(),
          evaluationTimeMicros: i * 100, // 0.1, 0.2, ... 1.0 ms
          specificMetrics: {},
        ));
      }

      // P50 should be around 0.5ms (5th of 10 sorted values)
      expect(stats.p50Latency, closeTo(0.5, 0.1));
    });

    test('avgEvaluationMs calculates rolling average', () {
      final stats = ContainerMeteringStats(
        containerId: 1,
        type: ContainerType.blend,
      );

      // Add samples: 100, 200, 300 microseconds
      for (final micros in [100, 200, 300]) {
        stats.recordEvaluation(ContainerEvaluationMetrics(
          containerId: 1,
          type: ContainerType.blend,
          timestamp: DateTime.now(),
          evaluationTimeMicros: micros,
          specificMetrics: {},
        ));
      }

      // Average should be 200 microseconds = 0.2ms
      expect(stats.avgEvaluationMs, closeTo(0.2, 0.01));
    });
  });
}
