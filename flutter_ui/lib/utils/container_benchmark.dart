/// Container FFI Benchmark Utility
///
/// Measures latency of Rust FFI vs Dart container evaluation.
/// Run via debug panel or console command.
library;

import 'dart:math' as math;
import '../models/middleware_models.dart';
import '../services/container_service.dart';
import '../src/rust/native_ffi.dart';

/// Results from a benchmark run
class BenchmarkResult {
  final String name;
  final int iterations;
  final Duration totalTime;
  final Duration minTime;
  final Duration maxTime;
  final Duration avgTime;
  final Duration medianTime;
  final Duration p99Time;

  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.totalTime,
    required this.minTime,
    required this.maxTime,
    required this.avgTime,
    required this.medianTime,
    required this.p99Time,
  });

  double get avgMicroseconds => avgTime.inMicroseconds.toDouble();
  double get avgMilliseconds => avgMicroseconds / 1000.0;

  @override
  String toString() => '''
$name (n=$iterations):
  Total: ${totalTime.inMilliseconds}ms
  Avg:   ${avgMilliseconds.toStringAsFixed(3)}ms (${avgMicroseconds.toStringAsFixed(1)}μs)
  Min:   ${minTime.inMicroseconds}μs
  Max:   ${maxTime.inMicroseconds}μs
  P50:   ${medianTime.inMicroseconds}μs
  P99:   ${p99Time.inMicroseconds}μs''';
}

/// Container FFI Benchmark
class ContainerBenchmark {
  static const int _defaultIterations = 1000;
  static const int _warmupIterations = 100;

  final NativeFFI? _ffi;
  final ContainerService _service;
  final _random = math.Random(42); // Fixed seed for reproducibility

  ContainerBenchmark()
      : _ffi = NativeFFI.instance,
        _service = ContainerService.instance;

  bool get ffiAvailable => _ffi?.isLoaded ?? false;

  /// Run all benchmarks
  Future<Map<String, BenchmarkResult>> runAll({int iterations = _defaultIterations}) async {
    final results = <String, BenchmarkResult>{};

    // Blend evaluation
    final blendRust = await _benchmarkBlendRust(iterations);
    if (blendRust != null) results['blend_rust'] = blendRust;

    final blendDart = await _benchmarkBlendDart(iterations);
    results['blend_dart'] = blendDart;

    // Random selection
    final randomRust = await _benchmarkRandomRust(iterations);
    if (randomRust != null) results['random_rust'] = randomRust;

    final randomDart = await _benchmarkRandomDart(iterations);
    results['random_dart'] = randomDart;

    // Sequence tick (Rust only meaningful for tick, Dart uses Timer)
    final sequenceRust = await _benchmarkSequenceTickRust(iterations);
    if (sequenceRust != null) results['sequence_tick_rust'] = sequenceRust;

    return results;
  }

  /// Benchmark Blend container evaluation via Rust FFI
  Future<BenchmarkResult?> _benchmarkBlendRust(int iterations) async {
    final ffi = _ffi;
    if (ffi == null || !ffi.isLoaded) return null;

    // Create test container in Rust
    final config = _createTestBlendConfig();
    final rustId = ffi.containerCreateBlend(config);
    if (rustId <= 0) return null;

    final times = <int>[];

    // Warmup
    for (int i = 0; i < _warmupIterations; i++) {
      final rtpc = _random.nextDouble();
      ffi.containerEvaluateBlend(rustId, rtpc);
    }

    // Benchmark
    for (int i = 0; i < iterations; i++) {
      final rtpc = _random.nextDouble();
      final sw = Stopwatch()..start();
      ffi.containerEvaluateBlend(rustId, rtpc);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }

    // Cleanup
    ffi.containerRemoveBlend(rustId);

    return _calculateResult('Blend (Rust FFI)', times);
  }

  /// Benchmark Blend container evaluation via Dart
  Future<BenchmarkResult> _benchmarkBlendDart(int iterations) async {
    final container = _createTestBlendContainer();
    final times = <int>[];

    // Warmup
    for (int i = 0; i < _warmupIterations; i++) {
      _evaluateBlendDart(container, _random.nextDouble());
    }

    // Benchmark
    for (int i = 0; i < iterations; i++) {
      final rtpc = _random.nextDouble();
      final sw = Stopwatch()..start();
      _evaluateBlendDart(container, rtpc);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }

    return _calculateResult('Blend (Dart)', times);
  }

  /// Benchmark Random container selection via Rust FFI
  Future<BenchmarkResult?> _benchmarkRandomRust(int iterations) async {
    final ffi = _ffi;
    if (ffi == null || !ffi.isLoaded) return null;

    final config = _createTestRandomConfig();
    final rustId = ffi.containerCreateRandom(config);
    if (rustId <= 0) return null;

    final times = <int>[];

    // Warmup
    for (int i = 0; i < _warmupIterations; i++) {
      ffi.containerSelectRandom(rustId);
    }

    // Benchmark
    for (int i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      ffi.containerSelectRandom(rustId);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }

    // Cleanup
    ffi.containerRemoveRandom(rustId);

    return _calculateResult('Random (Rust FFI)', times);
  }

  /// Benchmark Random container selection via Dart
  Future<BenchmarkResult> _benchmarkRandomDart(int iterations) async {
    final container = _createTestRandomContainer();
    final times = <int>[];

    // Warmup
    for (int i = 0; i < _warmupIterations; i++) {
      _service.selectRandomChild(container);
    }

    // Benchmark
    for (int i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      _service.selectRandomChild(container);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }

    return _calculateResult('Random (Dart)', times);
  }

  /// Benchmark Sequence tick via Rust FFI
  Future<BenchmarkResult?> _benchmarkSequenceTickRust(int iterations) async {
    final ffi = _ffi;
    if (ffi == null || !ffi.isLoaded) return null;

    final config = _createTestSequenceConfig();
    final rustId = ffi.containerCreateSequence(config);
    if (rustId <= 0) return null;

    final times = <int>[];

    // Start sequence
    ffi.containerPlaySequence(rustId);

    // Warmup
    for (int i = 0; i < _warmupIterations; i++) {
      ffi.containerTickSequence(rustId, 16.67); // ~60fps tick
    }

    // Benchmark
    for (int i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      ffi.containerTickSequence(rustId, 16.67);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }

    // Cleanup
    ffi.containerStopSequence(rustId);
    ffi.containerRemoveSequence(rustId);

    return _calculateResult('Sequence Tick (Rust FFI)', times);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pure Dart blend evaluation (mirrors ContainerService logic)
  Map<int, double> _evaluateBlendDart(BlendContainer container, double rtpcValue) {
    final result = <int, double>{};

    for (final child in container.children) {
      if (rtpcValue < child.rtpcStart || rtpcValue > child.rtpcEnd) continue;

      double volume = 1.0;

      if (rtpcValue < child.rtpcStart + child.crossfadeWidth) {
        final fadePos = (rtpcValue - child.rtpcStart) / child.crossfadeWidth;
        volume = math.sqrt(fadePos); // equal power
      } else if (rtpcValue > child.rtpcEnd - child.crossfadeWidth) {
        final fadePos = (child.rtpcEnd - rtpcValue) / child.crossfadeWidth;
        volume = math.sqrt(fadePos);
      }

      result[child.id] = volume.clamp(0.0, 1.0);
    }

    return result;
  }

  BenchmarkResult _calculateResult(String name, List<int> timesUs) {
    timesUs.sort();

    final total = timesUs.fold(0, (a, b) => a + b);
    final avg = total / timesUs.length;
    final median = timesUs[timesUs.length ~/ 2];
    final p99 = timesUs[(timesUs.length * 0.99).floor()];

    return BenchmarkResult(
      name: name,
      iterations: timesUs.length,
      totalTime: Duration(microseconds: total),
      minTime: Duration(microseconds: timesUs.first),
      maxTime: Duration(microseconds: timesUs.last),
      avgTime: Duration(microseconds: avg.round()),
      medianTime: Duration(microseconds: median),
      p99Time: Duration(microseconds: p99),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST DATA GENERATORS
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _createTestBlendConfig() {
    return {
      'id': 9999,
      'name': 'BenchmarkBlend',
      'enabled': true,
      'curve': 1, // equal power
      'rtpc_name': 'benchmark_rtpc',
      'children': List.generate(8, (i) => {
        'id': i + 1,
        'name': 'Child$i',
        'audio_path': '/test/sound_$i.wav',
        'rtpc_start': i * 0.125,
        'rtpc_end': (i + 1) * 0.125,
        'crossfade_width': 0.05,
        'volume': 1.0,
      }),
    };
  }

  BlendContainer _createTestBlendContainer() {
    return BlendContainer(
      id: 9999,
      name: 'BenchmarkBlend',
      rtpcId: 1,
      crossfadeCurve: CrossfadeCurve.equalPower,
      children: List.generate(8, (i) => BlendChild(
        id: i + 1,
        name: 'Child$i',
        audioPath: '/test/sound_$i.wav',
        rtpcStart: i * 0.125,
        rtpcEnd: (i + 1) * 0.125,
        crossfadeWidth: 0.05,
      )),
    );
  }

  Map<String, dynamic> _createTestRandomConfig() {
    return {
      'id': 9998,
      'name': 'BenchmarkRandom',
      'enabled': true,
      'mode': 0, // weighted random
      'avoid_repeat': true,
      'avoid_repeat_count': 2,
      'global_pitch_min': -0.1,
      'global_pitch_max': 0.1,
      'global_volume_min': -0.05,
      'global_volume_max': 0.05,
      'children': List.generate(12, (i) => {
        'id': i + 1,
        'name': 'RandomChild$i',
        'audio_path': '/test/random_$i.wav',
        'weight': 1.0 + (i % 3) * 0.5,
        'pitch_min': -0.05,
        'pitch_max': 0.05,
        'volume_min': 0.9,
        'volume_max': 1.0,
      }),
    };
  }

  RandomContainer _createTestRandomContainer() {
    return RandomContainer(
      id: 9998,
      name: 'BenchmarkRandom',
      mode: RandomMode.random,
      children: List.generate(12, (i) => RandomChild(
        id: i + 1,
        name: 'RandomChild$i',
        audioPath: '/test/random_$i.wav',
        weight: 1.0 + (i % 3) * 0.5,
        pitchMin: -0.05,
        pitchMax: 0.05,
        volumeMin: 0.9,
        volumeMax: 1.0,
      )),
    );
  }

  Map<String, dynamic> _createTestSequenceConfig() {
    return {
      'id': 9997,
      'name': 'BenchmarkSequence',
      'enabled': true,
      'end_behavior': 1, // loop
      'speed': 1.0,
      'steps': List.generate(16, (i) => {
        'index': i,
        'child_id': i + 1,
        'child_name': 'Step$i',
        'audio_path': '/test/step_$i.wav',
        'delay_ms': i * 100.0,
        'duration_ms': 90.0,
        'fade_in_ms': 5.0,
        'fade_out_ms': 5.0,
        'loop_count': 1,
        'volume': 1.0,
      }),
    };
  }

  /// Generate formatted report
  String generateReport(Map<String, BenchmarkResult> results) {
    final buffer = StringBuffer();

    buffer.writeln('╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║         CONTAINER FFI BENCHMARK RESULTS                      ║');
    buffer.writeln('╠══════════════════════════════════════════════════════════════╣');

    // Blend comparison
    if (results.containsKey('blend_rust') && results.containsKey('blend_dart')) {
      final rust = results['blend_rust']!;
      final dart = results['blend_dart']!;
      final speedup = dart.avgMicroseconds / rust.avgMicroseconds;

      buffer.writeln('║ BLEND CONTAINER EVALUATION                                   ║');
      buffer.writeln('╟──────────────────────────────────────────────────────────────╢');
      buffer.writeln('║ Rust FFI:  ${_padLeft(rust.avgMicroseconds.toStringAsFixed(1), 8)}μs avg  (P99: ${_padLeft(rust.p99Time.inMicroseconds.toString(), 6)}μs) ║');
      buffer.writeln('║ Dart:      ${_padLeft(dart.avgMicroseconds.toStringAsFixed(1), 8)}μs avg  (P99: ${_padLeft(dart.p99Time.inMicroseconds.toString(), 6)}μs) ║');
      buffer.writeln('║ Speedup:   ${_padLeft(speedup.toStringAsFixed(1), 8)}x                                  ║');
    }

    // Random comparison
    if (results.containsKey('random_rust') && results.containsKey('random_dart')) {
      final rust = results['random_rust']!;
      final dart = results['random_dart']!;
      final speedup = dart.avgMicroseconds / rust.avgMicroseconds;

      buffer.writeln('╟──────────────────────────────────────────────────────────────╢');
      buffer.writeln('║ RANDOM CONTAINER SELECTION                                   ║');
      buffer.writeln('╟──────────────────────────────────────────────────────────────╢');
      buffer.writeln('║ Rust FFI:  ${_padLeft(rust.avgMicroseconds.toStringAsFixed(1), 8)}μs avg  (P99: ${_padLeft(rust.p99Time.inMicroseconds.toString(), 6)}μs) ║');
      buffer.writeln('║ Dart:      ${_padLeft(dart.avgMicroseconds.toStringAsFixed(1), 8)}μs avg  (P99: ${_padLeft(dart.p99Time.inMicroseconds.toString(), 6)}μs) ║');
      buffer.writeln('║ Speedup:   ${_padLeft(speedup.toStringAsFixed(1), 8)}x                                  ║');
    }

    // Sequence tick
    if (results.containsKey('sequence_tick_rust')) {
      final rust = results['sequence_tick_rust']!;
      buffer.writeln('╟──────────────────────────────────────────────────────────────╢');
      buffer.writeln('║ SEQUENCE TICK (Rust only, Dart uses Timer)                   ║');
      buffer.writeln('╟──────────────────────────────────────────────────────────────╢');
      buffer.writeln('║ Rust FFI:  ${_padLeft(rust.avgMicroseconds.toStringAsFixed(1), 8)}μs avg  (P99: ${_padLeft(rust.p99Time.inMicroseconds.toString(), 6)}μs) ║');
    }

    buffer.writeln('╚══════════════════════════════════════════════════════════════╝');

    return buffer.toString();
  }

  String _padLeft(String s, int width) => s.padLeft(width);
}
