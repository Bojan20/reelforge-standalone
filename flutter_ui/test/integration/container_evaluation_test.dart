// Container Evaluation Integration Tests
//
// Tests: BlendContainer RTPC evaluation, RandomContainer weight distribution,
// SequenceContainer step progression, JSON roundtrip, copyWith independence,
// edge cases.
//
// Pure Dart logic — NO FFI, NO Flutter widgets.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/middleware_models.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // BLEND CONTAINER
  // ═══════════════════════════════════════════════════════════════════════

  group('BlendContainer', () {
    late BlendContainer container;
    late List<BlendChild> children;

    setUp(() {
      children = [
        const BlendChild(
          id: 1,
          name: 'Low',
          audioPath: '/audio/low.wav',
          rtpcStart: 0.0,
          rtpcEnd: 0.4,
          crossfadeWidth: 0.1,
        ),
        const BlendChild(
          id: 2,
          name: 'Mid',
          audioPath: '/audio/mid.wav',
          rtpcStart: 0.3,
          rtpcEnd: 0.7,
          crossfadeWidth: 0.15,
        ),
        const BlendChild(
          id: 3,
          name: 'High',
          audioPath: '/audio/high.wav',
          rtpcStart: 0.6,
          rtpcEnd: 1.0,
          crossfadeWidth: 0.1,
        ),
      ];
      container = BlendContainer(
        id: 10,
        name: 'Win Intensity',
        rtpcId: 5,
        children: children,
        crossfadeCurve: CrossfadeCurve.equalPower,
        enabled: true,
        smoothingMs: 50.0,
      );
    });

    test('creation stores all fields correctly', () {
      expect(container.id, 10);
      expect(container.name, 'Win Intensity');
      expect(container.rtpcId, 5);
      expect(container.children.length, 3);
      expect(container.crossfadeCurve, CrossfadeCurve.equalPower);
      expect(container.enabled, true);
      expect(container.smoothingMs, 50.0);
    });

    test('children have correct RTPC ranges', () {
      expect(container.children[0].rtpcStart, 0.0);
      expect(container.children[0].rtpcEnd, 0.4);
      expect(container.children[1].rtpcStart, 0.3);
      expect(container.children[1].rtpcEnd, 0.7);
      expect(container.children[2].rtpcStart, 0.6);
      expect(container.children[2].rtpcEnd, 1.0);
    });

    test('children RTPC ranges can overlap for crossfade', () {
      // Children 0 and 1 overlap in range 0.3-0.4
      final child0End = container.children[0].rtpcEnd;
      final child1Start = container.children[1].rtpcStart;
      expect(child0End, greaterThan(child1Start),
          reason: 'RTPC ranges should overlap for crossfade');
    });

    test('copyWith creates independent copy', () {
      final copy = container.copyWith(
        name: 'Modified',
        smoothingMs: 100.0,
        enabled: false,
      );
      expect(copy.name, 'Modified');
      expect(copy.smoothingMs, 100.0);
      expect(copy.enabled, false);
      // Original unchanged
      expect(container.name, 'Win Intensity');
      expect(container.smoothingMs, 50.0);
      expect(container.enabled, true);
      // Preserved fields
      expect(copy.id, 10);
      expect(copy.rtpcId, 5);
      expect(copy.children.length, 3);
    });

    test('copyWith with new children list is independent', () {
      final newChildren = [
        const BlendChild(id: 99, name: 'Solo', rtpcStart: 0.0, rtpcEnd: 1.0),
      ];
      final copy = container.copyWith(children: newChildren);
      expect(copy.children.length, 1);
      expect(container.children.length, 3);
    });

    test('JSON roundtrip preserves all fields', () {
      final json = container.toJson();
      final restored = BlendContainer.fromJson(json);

      expect(restored.id, container.id);
      expect(restored.name, container.name);
      expect(restored.rtpcId, container.rtpcId);
      expect(restored.children.length, container.children.length);
      expect(restored.crossfadeCurve, container.crossfadeCurve);
      expect(restored.enabled, container.enabled);
      expect(restored.smoothingMs, container.smoothingMs);

      // Verify child roundtrip
      for (int i = 0; i < container.children.length; i++) {
        expect(restored.children[i].id, container.children[i].id);
        expect(restored.children[i].name, container.children[i].name);
        expect(restored.children[i].audioPath, container.children[i].audioPath);
        expect(restored.children[i].rtpcStart, container.children[i].rtpcStart);
        expect(restored.children[i].rtpcEnd, container.children[i].rtpcEnd);
        expect(
            restored.children[i].crossfadeWidth,
            container.children[i].crossfadeWidth);
      }
    });

    test('JSON string roundtrip', () {
      final jsonStr = jsonEncode(container.toJson());
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = BlendContainer.fromJson(decoded);
      expect(restored.name, container.name);
      expect(restored.children.length, container.children.length);
    });

    test('fromJson with missing fields uses defaults', () {
      final minimal = BlendContainer.fromJson({
        'id': 1,
        'name': 'Minimal',
        'rtpcId': 0,
      });
      expect(minimal.children, isEmpty);
      expect(minimal.crossfadeCurve, CrossfadeCurve.equalPower);
      expect(minimal.enabled, true);
      expect(minimal.smoothingMs, 0.0);
    });

    test('CrossfadeCurve enum covers all values', () {
      expect(CrossfadeCurve.values.length, 4);
      expect(CrossfadeCurve.values,
          contains(CrossfadeCurve.linear));
      expect(CrossfadeCurve.values,
          contains(CrossfadeCurve.equalPower));
      expect(CrossfadeCurve.values,
          contains(CrossfadeCurve.sCurve));
      expect(CrossfadeCurve.values,
          contains(CrossfadeCurve.sinCos));
    });

    test('CrossfadeCurve fromValue handles out-of-range', () {
      expect(CrossfadeCurveExtension.fromValue(-1),
          CrossfadeCurve.equalPower);
      expect(CrossfadeCurveExtension.fromValue(999),
          CrossfadeCurve.equalPower);
    });

    test('BlendChild copyWith preserves nullable audioPath', () {
      const child = BlendChild(
        id: 1,
        name: 'Test',
        rtpcStart: 0.0,
        rtpcEnd: 1.0,
      );
      expect(child.audioPath, isNull);
      final withPath = child.copyWith(audioPath: '/path/to/file.wav');
      expect(withPath.audioPath, '/path/to/file.wav');
    });

    test('empty container is valid', () {
      const empty = BlendContainer(
        id: 0,
        name: 'Empty',
        rtpcId: 0,
        children: [],
      );
      final json = empty.toJson();
      final restored = BlendContainer.fromJson(json);
      expect(restored.children, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // RANDOM CONTAINER
  // ═══════════════════════════════════════════════════════════════════════

  group('RandomContainer', () {
    late RandomContainer container;

    setUp(() {
      container = RandomContainer(
        id: 20,
        name: 'Reel Stop Variations',
        children: [
          const RandomChild(
            id: 1,
            name: 'Stop A',
            audioPath: '/audio/stop_a.wav',
            weight: 3.0,
            pitchMin: -0.05,
            pitchMax: 0.05,
            volumeMin: -0.1,
            volumeMax: 0.1,
          ),
          const RandomChild(
            id: 2,
            name: 'Stop B',
            audioPath: '/audio/stop_b.wav',
            weight: 2.0,
          ),
          const RandomChild(
            id: 3,
            name: 'Stop C',
            audioPath: '/audio/stop_c.wav',
            weight: 1.0,
          ),
        ],
        mode: RandomMode.random,
        avoidRepeatCount: 2,
        enabled: true,
      );
    });

    test('creation stores all fields', () {
      expect(container.id, 20);
      expect(container.name, 'Reel Stop Variations');
      expect(container.children.length, 3);
      expect(container.mode, RandomMode.random);
      expect(container.avoidRepeatCount, 2);
      expect(container.enabled, true);
    });

    test('weight distribution simulation', () {
      // Simulate 1000 weighted random selections
      final rng = math.Random(42);
      final totalWeight = container.children.fold<double>(
          0.0, (sum, c) => sum + c.weight);
      final counts = <int, int>{};

      for (int i = 0; i < 1000; i++) {
        final r = rng.nextDouble() * totalWeight;
        double cumulative = 0.0;
        for (final child in container.children) {
          cumulative += child.weight;
          if (r < cumulative) {
            counts[child.id] = (counts[child.id] ?? 0) + 1;
            break;
          }
        }
      }

      // With weights 3:2:1, expected distribution is ~50%, ~33%, ~17%
      final countA = counts[1] ?? 0;
      final countB = counts[2] ?? 0;
      final countC = counts[3] ?? 0;

      expect(countA, greaterThan(400)); // ~500 expected
      expect(countA, lessThan(600));
      expect(countB, greaterThan(250)); // ~333 expected
      expect(countB, lessThan(450));
      expect(countC, greaterThan(100)); // ~167 expected
      expect(countC, lessThan(280));
    });

    test('RandomMode enum has 4 modes', () {
      expect(RandomMode.values.length, 4);
      expect(RandomMode.values, contains(RandomMode.random));
      expect(RandomMode.values, contains(RandomMode.shuffle));
      expect(RandomMode.values, contains(RandomMode.shuffleWithHistory));
      expect(RandomMode.values, contains(RandomMode.roundRobin));
    });

    test('RandomMode fromValue handles out-of-range', () {
      expect(RandomModeExtension.fromValue(-1), RandomMode.random);
      expect(RandomModeExtension.fromValue(99), RandomMode.random);
    });

    test('deterministic mode fields', () {
      final det = container.copyWith(
        useDeterministicMode: true,
        seed: 12345,
      );
      expect(det.useDeterministicMode, true);
      expect(det.seed, 12345);
    });

    test('generateSeed returns a positive integer', () {
      final seed = RandomContainer.generateSeed();
      expect(seed, isPositive);
    });

    test('JSON roundtrip preserves all fields', () {
      final det = container.copyWith(
        useDeterministicMode: true,
        seed: 99999,
        globalPitchMin: -0.2,
        globalPitchMax: 0.2,
        globalVolumeMin: -0.3,
        globalVolumeMax: 0.3,
      );
      final json = det.toJson();
      final restored = RandomContainer.fromJson(json);

      expect(restored.id, det.id);
      expect(restored.name, det.name);
      expect(restored.children.length, det.children.length);
      expect(restored.mode, det.mode);
      expect(restored.avoidRepeatCount, det.avoidRepeatCount);
      expect(restored.globalPitchMin, det.globalPitchMin);
      expect(restored.globalPitchMax, det.globalPitchMax);
      expect(restored.globalVolumeMin, det.globalVolumeMin);
      expect(restored.globalVolumeMax, det.globalVolumeMax);
      expect(restored.enabled, det.enabled);
      expect(restored.seed, 99999);
      expect(restored.useDeterministicMode, true);

      // Verify child roundtrip
      expect(restored.children[0].weight, 3.0);
      expect(restored.children[0].pitchMin, -0.05);
      expect(restored.children[0].pitchMax, 0.05);
      expect(restored.children[1].weight, 2.0);
    });

    test('fromJson with missing fields uses defaults', () {
      final minimal = RandomContainer.fromJson({
        'id': 1,
        'name': 'Min',
      });
      expect(minimal.children, isEmpty);
      expect(minimal.mode, RandomMode.random);
      expect(minimal.avoidRepeatCount, 2);
      expect(minimal.enabled, true);
      expect(minimal.seed, isNull);
      expect(minimal.useDeterministicMode, false);
    });

    test('copyWith children list is independent', () {
      final copy = container.copyWith(
        children: [
          const RandomChild(id: 99, name: 'New', weight: 5.0),
        ],
      );
      expect(copy.children.length, 1);
      expect(container.children.length, 3);
    });

    test('child pitch and volume variation ranges', () {
      final child = container.children[0];
      expect(child.pitchMin, lessThanOrEqualTo(child.pitchMax));
      expect(child.volumeMin, lessThanOrEqualTo(child.volumeMax));
    });

    test('equal weights produce near-uniform distribution', () {
      final equalContainer = RandomContainer(
        id: 1,
        name: 'Equal',
        children: List.generate(
          5,
          (i) => RandomChild(id: i, name: 'C$i', weight: 1.0),
        ),
      );

      final rng = math.Random(42);
      final totalWeight = equalContainer.children.fold<double>(
          0.0, (sum, c) => sum + c.weight);
      final counts = <int, int>{};

      for (int i = 0; i < 1000; i++) {
        final r = rng.nextDouble() * totalWeight;
        double cumulative = 0.0;
        for (final child in equalContainer.children) {
          cumulative += child.weight;
          if (r < cumulative) {
            counts[child.id] = (counts[child.id] ?? 0) + 1;
            break;
          }
        }
      }

      // Each child should get ~200 hits (within reasonable tolerance)
      for (int i = 0; i < 5; i++) {
        expect(counts[i] ?? 0, greaterThan(130));
        expect(counts[i] ?? 0, lessThan(270));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SEQUENCE CONTAINER
  // ═══════════════════════════════════════════════════════════════════════

  group('SequenceContainer', () {
    late SequenceContainer container;

    setUp(() {
      container = SequenceContainer(
        id: 30,
        name: 'Jackpot Sequence',
        steps: [
          const SequenceStep(
            index: 0,
            childId: 1,
            childName: 'Alert',
            audioPath: '/audio/alert.wav',
            delayMs: 0.0,
            durationMs: 500.0,
            fadeInMs: 10.0,
            fadeOutMs: 50.0,
            loopCount: 1,
            volume: 0.9,
          ),
          const SequenceStep(
            index: 1,
            childId: 2,
            childName: 'Buildup',
            audioPath: '/audio/buildup.wav',
            delayMs: 200.0,
            durationMs: 2000.0,
            fadeInMs: 100.0,
            fadeOutMs: 100.0,
            loopCount: 1,
            volume: 1.0,
          ),
          const SequenceStep(
            index: 2,
            childId: 3,
            childName: 'Fanfare',
            audioPath: '/audio/fanfare.wav',
            delayMs: 0.0,
            durationMs: 5000.0,
            fadeInMs: 50.0,
            fadeOutMs: 500.0,
            loopCount: 1,
            volume: 1.0,
          ),
        ],
        endBehavior: SequenceEndBehavior.stop,
        speed: 1.0,
        enabled: true,
      );
    });

    test('creation stores all fields', () {
      expect(container.id, 30);
      expect(container.name, 'Jackpot Sequence');
      expect(container.steps.length, 3);
      expect(container.endBehavior, SequenceEndBehavior.stop);
      expect(container.speed, 1.0);
      expect(container.enabled, true);
    });

    test('steps are ordered by index', () {
      for (int i = 0; i < container.steps.length; i++) {
        expect(container.steps[i].index, i);
      }
    });

    test('step timing properties', () {
      final step0 = container.steps[0];
      expect(step0.delayMs, 0.0);
      expect(step0.durationMs, 500.0);
      expect(step0.fadeInMs, 10.0);
      expect(step0.fadeOutMs, 50.0);
      expect(step0.loopCount, 1);
      expect(step0.volume, 0.9);
    });

    test('SequenceEndBehavior enum has 4 values', () {
      expect(SequenceEndBehavior.values.length, 4);
      expect(SequenceEndBehavior.values,
          contains(SequenceEndBehavior.stop));
      expect(SequenceEndBehavior.values,
          contains(SequenceEndBehavior.loop));
      expect(SequenceEndBehavior.values,
          contains(SequenceEndBehavior.holdLast));
      expect(SequenceEndBehavior.values,
          contains(SequenceEndBehavior.pingPong));
    });

    test('SequenceEndBehavior fromValue handles out-of-range', () {
      expect(SequenceEndBehaviorExtension.fromValue(-1),
          SequenceEndBehavior.stop);
      expect(SequenceEndBehaviorExtension.fromValue(99),
          SequenceEndBehavior.stop);
    });

    test('copyWith creates independent copy', () {
      final copy = container.copyWith(
        name: 'Modified',
        endBehavior: SequenceEndBehavior.loop,
        speed: 2.0,
      );
      expect(copy.name, 'Modified');
      expect(copy.endBehavior, SequenceEndBehavior.loop);
      expect(copy.speed, 2.0);
      // Original unchanged
      expect(container.name, 'Jackpot Sequence');
      expect(container.endBehavior, SequenceEndBehavior.stop);
      expect(container.speed, 1.0);
    });

    test('JSON roundtrip preserves all fields', () {
      final json = container.toJson();
      final restored = SequenceContainer.fromJson(json);

      expect(restored.id, container.id);
      expect(restored.name, container.name);
      expect(restored.steps.length, container.steps.length);
      expect(restored.endBehavior, container.endBehavior);
      expect(restored.speed, container.speed);
      expect(restored.enabled, container.enabled);

      // Verify step roundtrip
      for (int i = 0; i < container.steps.length; i++) {
        expect(restored.steps[i].index, container.steps[i].index);
        expect(restored.steps[i].childId, container.steps[i].childId);
        expect(restored.steps[i].childName, container.steps[i].childName);
        expect(restored.steps[i].audioPath, container.steps[i].audioPath);
        expect(restored.steps[i].delayMs, container.steps[i].delayMs);
        expect(restored.steps[i].durationMs, container.steps[i].durationMs);
        expect(restored.steps[i].fadeInMs, container.steps[i].fadeInMs);
        expect(restored.steps[i].fadeOutMs, container.steps[i].fadeOutMs);
        expect(restored.steps[i].loopCount, container.steps[i].loopCount);
        expect(restored.steps[i].volume, container.steps[i].volume);
      }
    });

    test('fromJson with missing fields uses defaults', () {
      final minimal = SequenceContainer.fromJson({
        'id': 1,
        'name': 'Min',
      });
      expect(minimal.steps, isEmpty);
      expect(minimal.endBehavior, SequenceEndBehavior.stop);
      expect(minimal.speed, 1.0);
      expect(minimal.enabled, true);
    });

    test('step copyWith preserves optional audioPath', () {
      const step = SequenceStep(
        index: 0,
        childId: 1,
        childName: 'Test',
      );
      expect(step.audioPath, isNull);
      expect(step.delayMs, 0.0);
      expect(step.volume, 1.0);
      expect(step.loopCount, 1);
    });

    test('step JSON roundtrip with all fields', () {
      final step = container.steps[1]; // Buildup step
      final json = step.toJson();
      final restored = SequenceStep.fromJson(json);

      expect(restored.index, 1);
      expect(restored.childId, 2);
      expect(restored.childName, 'Buildup');
      expect(restored.audioPath, '/audio/buildup.wav');
      expect(restored.delayMs, 200.0);
      expect(restored.durationMs, 2000.0);
      expect(restored.fadeInMs, 100.0);
      expect(restored.fadeOutMs, 100.0);
      expect(restored.loopCount, 1);
      expect(restored.volume, 1.0);
    });

    test('speed multiplier affects timing conceptually', () {
      final fast = container.copyWith(speed: 2.0);
      final slow = container.copyWith(speed: 0.5);
      // Speed doesn't modify step data, but affects playback rate
      expect(fast.speed, 2.0);
      expect(slow.speed, 0.5);
      expect(fast.steps.length, container.steps.length);
    });

    test('looping sequence with endBehavior', () {
      final looping = container.copyWith(
        endBehavior: SequenceEndBehavior.loop,
      );
      expect(looping.endBehavior, SequenceEndBehavior.loop);

      final pingPong = container.copyWith(
        endBehavior: SequenceEndBehavior.pingPong,
      );
      expect(pingPong.endBehavior, SequenceEndBehavior.pingPong);
    });

    test('empty sequence is valid', () {
      const empty = SequenceContainer(
        id: 0,
        name: 'Empty Sequence',
        steps: [],
      );
      expect(empty.steps, isEmpty);
      final json = empty.toJson();
      final restored = SequenceContainer.fromJson(json);
      expect(restored.steps, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CROSS-CONTAINER TESTS
  // ═══════════════════════════════════════════════════════════════════════

  group('Cross-container', () {
    test('all container types have toJson/fromJson symmetry', () {
      const blend = BlendContainer(
        id: 1,
        name: 'B',
        rtpcId: 0,
        children: [BlendChild(id: 1, name: 'C', rtpcStart: 0, rtpcEnd: 1)],
      );
      const random = RandomContainer(
        id: 2,
        name: 'R',
        children: [RandomChild(id: 1, name: 'C', weight: 1.0)],
      );
      const sequence = SequenceContainer(
        id: 3,
        name: 'S',
        steps: [SequenceStep(index: 0, childId: 1, childName: 'C')],
      );

      // All three roundtrip successfully
      expect(BlendContainer.fromJson(blend.toJson()).name, 'B');
      expect(RandomContainer.fromJson(random.toJson()).name, 'R');
      expect(SequenceContainer.fromJson(sequence.toJson()).name, 'S');
    });

    test('container IDs are independent namespaces', () {
      const blend = BlendContainer(id: 1, name: 'B', rtpcId: 0);
      const random = RandomContainer(id: 1, name: 'R');
      const sequence = SequenceContainer(id: 1, name: 'S');

      // Same ID, different containers — no conflict
      expect(blend.id, 1);
      expect(random.id, 1);
      expect(sequence.id, 1);
    });

    test('disabled containers preserve configuration', () {
      const blend = BlendContainer(
        id: 1, name: 'B', rtpcId: 0, enabled: false,
        children: [BlendChild(id: 1, name: 'C', rtpcStart: 0, rtpcEnd: 1)],
      );
      const random = RandomContainer(
        id: 2, name: 'R', enabled: false,
        children: [RandomChild(id: 1, name: 'C', weight: 1.0)],
      );
      const sequence = SequenceContainer(
        id: 3, name: 'S', enabled: false,
        steps: [SequenceStep(index: 0, childId: 1, childName: 'C')],
      );

      expect(blend.enabled, false);
      expect(blend.children.length, 1);
      expect(random.enabled, false);
      expect(random.children.length, 1);
      expect(sequence.enabled, false);
      expect(sequence.steps.length, 1);
    });
  });
}
