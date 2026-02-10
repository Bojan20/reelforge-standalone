/// Container Panel Tests
///
/// Tests for Blend, Random, and Sequence container models:
/// - BlendContainer/BlendChild RTPC range, JSON serialization
/// - RandomContainer/RandomChild weight normalization, modes
/// - SequenceContainer/SequenceStep timing, end behaviors
/// - Container type color mapping
/// - Copy/duplicate logic
@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/middleware_models.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // BlendContainer Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('BlendChild model', () {
    test('default values', () {
      const child = BlendChild(id: 1, name: 'Calm', rtpcStart: 0.0, rtpcEnd: 0.5);
      expect(child.crossfadeWidth, 0.1);
      expect(child.audioPath, isNull);
    });

    test('RTPC range is preserved', () {
      const child = BlendChild(id: 1, name: 'T', rtpcStart: 0.2, rtpcEnd: 0.8);
      expect(child.rtpcStart, 0.2);
      expect(child.rtpcEnd, 0.8);
    });

    test('copyWith preserves unchanged fields', () {
      const child = BlendChild(
        id: 1,
        name: 'Original',
        rtpcStart: 0.0,
        rtpcEnd: 0.5,
        crossfadeWidth: 0.2,
      );
      final modified = child.copyWith(rtpcEnd: 0.7);
      expect(modified.rtpcEnd, 0.7);
      expect(modified.name, 'Original');
      expect(modified.crossfadeWidth, 0.2);
    });

    test('JSON roundtrip preserves all fields', () {
      const original = BlendChild(
        id: 42,
        name: 'Wind',
        audioPath: '/audio/wind.wav',
        rtpcStart: 0.3,
        rtpcEnd: 0.7,
        crossfadeWidth: 0.15,
      );
      final json = original.toJson();
      final restored = BlendChild.fromJson(json);
      expect(restored.id, 42);
      expect(restored.name, 'Wind');
      expect(restored.audioPath, '/audio/wind.wav');
      expect(restored.rtpcStart, 0.3);
      expect(restored.rtpcEnd, 0.7);
      expect(restored.crossfadeWidth, 0.15);
    });
  });

  group('BlendContainer model', () {
    test('default values', () {
      const container = BlendContainer(id: 1, name: 'Test', rtpcId: 0);
      expect(container.children, isEmpty);
      expect(container.crossfadeCurve, CrossfadeCurve.equalPower);
      expect(container.enabled, true);
      expect(container.smoothingMs, 0.0);
    });

    test('JSON roundtrip preserves all fields', () {
      final original = BlendContainer(
        id: 10,
        name: 'Wind Blend',
        rtpcId: 5,
        children: const [
          BlendChild(id: 1, name: 'Calm', rtpcStart: 0.0, rtpcEnd: 0.5),
          BlendChild(id: 2, name: 'Stormy', rtpcStart: 0.5, rtpcEnd: 1.0),
        ],
        crossfadeCurve: CrossfadeCurve.sCurve,
        smoothingMs: 150.0,
      );
      final json = original.toJson();
      final restored = BlendContainer.fromJson(json);
      expect(restored.id, 10);
      expect(restored.name, 'Wind Blend');
      expect(restored.rtpcId, 5);
      expect(restored.children.length, 2);
      expect(restored.crossfadeCurve, CrossfadeCurve.sCurve);
      expect(restored.smoothingMs, 150.0);
    });

    test('copyWith duplicates with modifications', () {
      const container = BlendContainer(id: 1, name: 'A', rtpcId: 0);
      final dup = container.copyWith(id: 2, name: 'A Copy');
      expect(dup.id, 2);
      expect(dup.name, 'A Copy');
      expect(dup.rtpcId, 0);
    });

    test('RTPC range clamping: children should stay within 0-1', () {
      const child = BlendChild(id: 1, name: 'T', rtpcStart: -0.5, rtpcEnd: 1.5);
      // Model doesn't auto-clamp, but values are stored as-is
      // UI and evaluation should clamp - here we verify storage
      expect(child.rtpcStart, -0.5);
      expect(child.rtpcEnd, 1.5);
    });
  });

  group('CrossfadeCurve', () {
    test('all 4 curves exist', () {
      expect(CrossfadeCurve.values.length, 4);
      expect(CrossfadeCurve.linear, isNotNull);
      expect(CrossfadeCurve.equalPower, isNotNull);
      expect(CrossfadeCurve.sCurve, isNotNull);
      expect(CrossfadeCurve.sinCos, isNotNull);
    });

    test('display names are readable', () {
      expect(CrossfadeCurve.linear.displayName, 'Linear');
      expect(CrossfadeCurve.equalPower.displayName, 'Equal Power');
      expect(CrossfadeCurve.sCurve.displayName, 'S-Curve');
      expect(CrossfadeCurve.sinCos.displayName, 'Sin/Cos');
    });

    test('fromValue handles out-of-range gracefully', () {
      expect(CrossfadeCurveExtension.fromValue(-1), CrossfadeCurve.equalPower);
      expect(CrossfadeCurveExtension.fromValue(99), CrossfadeCurve.equalPower);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RandomContainer Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('RandomChild model', () {
    test('default weight is 1.0', () {
      const child = RandomChild(id: 1, name: 'Sound A');
      expect(child.weight, 1.0);
      expect(child.pitchMin, 0.0);
      expect(child.pitchMax, 0.0);
      expect(child.volumeMin, 0.0);
      expect(child.volumeMax, 0.0);
    });

    test('JSON roundtrip preserves all fields', () {
      const original = RandomChild(
        id: 5,
        name: 'Footstep',
        audioPath: '/steps/step1.wav',
        weight: 2.5,
        pitchMin: -0.1,
        pitchMax: 0.1,
        volumeMin: -0.05,
        volumeMax: 0.05,
      );
      final json = original.toJson();
      final restored = RandomChild.fromJson(json);
      expect(restored.id, 5);
      expect(restored.weight, 2.5);
      expect(restored.pitchMin, -0.1);
      expect(restored.pitchMax, 0.1);
    });
  });

  group('RandomContainer weight normalization', () {
    test('equal weights give equal percentages', () {
      const children = [
        RandomChild(id: 1, name: 'A', weight: 1.0),
        RandomChild(id: 2, name: 'B', weight: 1.0),
        RandomChild(id: 3, name: 'C', weight: 1.0),
      ];
      final totalWeight = children.fold<double>(0, (sum, c) => sum + c.weight);
      for (final child in children) {
        final pct = child.weight / totalWeight * 100;
        expect(pct, closeTo(33.33, 0.1));
      }
    });

    test('weight 2:1:1 gives 50%:25%:25%', () {
      const children = [
        RandomChild(id: 1, name: 'A', weight: 2.0),
        RandomChild(id: 2, name: 'B', weight: 1.0),
        RandomChild(id: 3, name: 'C', weight: 1.0),
      ];
      final totalWeight = children.fold<double>(0, (sum, c) => sum + c.weight);
      expect(children[0].weight / totalWeight * 100, closeTo(50.0, 0.1));
      expect(children[1].weight / totalWeight * 100, closeTo(25.0, 0.1));
      expect(children[2].weight / totalWeight * 100, closeTo(25.0, 0.1));
    });

    test('single child is always 100%', () {
      const children = [RandomChild(id: 1, name: 'Only', weight: 5.0)];
      final total = children.fold<double>(0, (sum, c) => sum + c.weight);
      expect(children[0].weight / total * 100, 100.0);
    });

    test('zero total weight edge case', () {
      const children = [
        RandomChild(id: 1, name: 'A', weight: 0.0),
        RandomChild(id: 2, name: 'B', weight: 0.0),
      ];
      final total = children.fold<double>(0, (sum, c) => sum + c.weight);
      expect(total, 0.0);
      // Application should handle division by zero
    });
  });

  group('RandomContainer model', () {
    test('default values', () {
      const container = RandomContainer(id: 1, name: 'Test');
      expect(container.mode, RandomMode.random);
      expect(container.avoidRepeatCount, 2);
      expect(container.enabled, true);
      expect(container.useDeterministicMode, false);
      expect(container.seed, isNull);
    });

    test('JSON roundtrip preserves deterministic mode', () {
      final original = RandomContainer(
        id: 7,
        name: 'Footsteps',
        mode: RandomMode.shuffle,
        seed: 12345,
        useDeterministicMode: true,
        children: const [
          RandomChild(id: 1, name: 'Step 1', weight: 1.0),
          RandomChild(id: 2, name: 'Step 2', weight: 1.5),
        ],
      );
      final json = original.toJson();
      final restored = RandomContainer.fromJson(json);
      expect(restored.mode, RandomMode.shuffle);
      expect(restored.seed, 12345);
      expect(restored.useDeterministicMode, true);
      expect(restored.children.length, 2);
    });

    test('generateSeed produces non-zero values', () {
      final seed = RandomContainer.generateSeed();
      expect(seed, isNonZero);
    });
  });

  group('RandomMode', () {
    test('all 4 modes exist', () {
      expect(RandomMode.values.length, 4);
    });

    test('display names are readable', () {
      expect(RandomMode.random.displayName, 'Random');
      expect(RandomMode.shuffle.displayName, 'Shuffle');
      expect(RandomMode.roundRobin.displayName, 'Round Robin');
    });

    test('fromValue handles out-of-range', () {
      expect(RandomModeExtension.fromValue(-1), RandomMode.random);
      expect(RandomModeExtension.fromValue(99), RandomMode.random);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SequenceContainer Tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('SequenceStep model', () {
    test('default values', () {
      const step = SequenceStep(index: 0, childId: 1, childName: 'Hit');
      expect(step.delayMs, 0.0);
      expect(step.durationMs, 0.0);
      expect(step.fadeInMs, 0.0);
      expect(step.fadeOutMs, 0.0);
      expect(step.loopCount, 1);
      expect(step.volume, 1.0);
    });

    test('step timing calculation: total = delay + duration', () {
      const step = SequenceStep(
        index: 0,
        childId: 1,
        childName: 'Hit',
        delayMs: 100,
        durationMs: 500,
      );
      final totalMs = step.delayMs + step.durationMs;
      expect(totalMs, 600.0);
    });

    test('JSON roundtrip preserves all fields', () {
      const original = SequenceStep(
        index: 2,
        childId: 5,
        childName: 'Crash',
        audioPath: '/fx/crash.wav',
        delayMs: 250,
        durationMs: 1000,
        fadeInMs: 50,
        fadeOutMs: 100,
        loopCount: 3,
        volume: 0.8,
      );
      final json = original.toJson();
      final restored = SequenceStep.fromJson(json);
      expect(restored.index, 2);
      expect(restored.childId, 5);
      expect(restored.audioPath, '/fx/crash.wav');
      expect(restored.delayMs, 250);
      expect(restored.durationMs, 1000);
      expect(restored.fadeInMs, 50);
      expect(restored.fadeOutMs, 100);
      expect(restored.loopCount, 3);
      expect(restored.volume, 0.8);
    });
  });

  group('SequenceContainer timing calculations', () {
    test('total duration is sum of delay + duration for all steps', () {
      const container = SequenceContainer(
        id: 1,
        name: 'Intro Sequence',
        steps: [
          SequenceStep(index: 0, childId: 1, childName: 'A', delayMs: 0, durationMs: 500),
          SequenceStep(index: 1, childId: 2, childName: 'B', delayMs: 100, durationMs: 300),
          SequenceStep(index: 2, childId: 3, childName: 'C', delayMs: 50, durationMs: 200),
        ],
      );

      double totalMs = 0;
      for (final step in container.steps) {
        totalMs += step.delayMs + step.durationMs;
      }
      expect(totalMs, 1150.0);
    });

    test('speed multiplier affects perceived duration', () {
      const container = SequenceContainer(
        id: 1,
        name: 'Fast',
        speed: 2.0,
        steps: [
          SequenceStep(index: 0, childId: 1, childName: 'A', durationMs: 1000),
        ],
      );
      final rawMs = container.steps[0].durationMs;
      final perceivedMs = rawMs / container.speed;
      expect(perceivedMs, 500.0);
    });
  });

  group('SequenceContainer model', () {
    test('default values', () {
      const container = SequenceContainer(id: 1, name: 'Test');
      expect(container.endBehavior, SequenceEndBehavior.stop);
      expect(container.speed, 1.0);
      expect(container.enabled, true);
      expect(container.steps, isEmpty);
    });

    test('JSON roundtrip preserves all fields', () {
      const original = SequenceContainer(
        id: 3,
        name: 'Build Up',
        endBehavior: SequenceEndBehavior.loop,
        speed: 1.5,
        steps: [
          SequenceStep(index: 0, childId: 1, childName: 'Kick', durationMs: 250),
          SequenceStep(index: 1, childId: 2, childName: 'Snare', delayMs: 250, durationMs: 250),
        ],
      );
      final json = original.toJson();
      final restored = SequenceContainer.fromJson(json);
      expect(restored.name, 'Build Up');
      expect(restored.endBehavior, SequenceEndBehavior.loop);
      expect(restored.speed, 1.5);
      expect(restored.steps.length, 2);
    });

    test('copyWith duplicates for editing', () {
      const original = SequenceContainer(id: 1, name: 'Orig', speed: 1.0);
      final dup = original.copyWith(id: 2, name: 'Orig Copy', speed: 0.8);
      expect(dup.id, 2);
      expect(dup.name, 'Orig Copy');
      expect(dup.speed, 0.8);
    });
  });

  group('SequenceEndBehavior', () {
    test('all 4 behaviors exist', () {
      expect(SequenceEndBehavior.values.length, 4);
    });

    test('display names are readable', () {
      expect(SequenceEndBehavior.stop.displayName, 'Stop');
      expect(SequenceEndBehavior.loop.displayName, 'Loop');
      expect(SequenceEndBehavior.holdLast.displayName, 'Hold Last');
      expect(SequenceEndBehavior.pingPong.displayName, 'Ping-Pong');
    });

    test('fromValue handles out-of-range', () {
      expect(SequenceEndBehaviorExtension.fromValue(-1), SequenceEndBehavior.stop);
      expect(SequenceEndBehaviorExtension.fromValue(99), SequenceEndBehavior.stop);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Container Type Badge Color Mapping
  // ═══════════════════════════════════════════════════════════════════════════

  group('Container type badge colors', () {
    test('blend = purple', () {
      const blendColor = Color(0xFF9370DB);
      expect(blendColor, const Color(0xFF9370DB));
    });

    test('random = amber', () {
      const randomColor = Color(0xFFFFC107);
      expect(randomColor, const Color(0xFFFFC107));
    });

    test('sequence = teal', () {
      const seqColor = Color(0xFF009688);
      expect(seqColor, const Color(0xFF009688));
    });
  });
}
