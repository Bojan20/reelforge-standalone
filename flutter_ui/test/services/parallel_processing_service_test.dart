/// Parallel Processing Service Tests — P2-DAW-1
///
/// Tests for A/B parallel processing paths functionality.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/parallel_processing_service.dart';
import 'package:fluxforge_ui/providers/dsp_chain_provider.dart';

void main() {
  group('ParallelChain', () {
    test('displayName returns correct names', () {
      expect(ParallelChain.a.displayName, 'Chain A');
      expect(ParallelChain.b.displayName, 'Chain B');
      expect(ParallelChain.blend.displayName, 'Blend');
    });

    test('shortName returns correct abbreviations', () {
      expect(ParallelChain.a.shortName, 'A');
      expect(ParallelChain.b.shortName, 'B');
      expect(ParallelChain.blend.shortName, 'A+B');
    });
  });

  group('ParallelTrackConfig', () {
    test('creates config with default values', () {
      final chainA = DspChain(trackId: 0, nodes: []);
      final chainB = DspChain(trackId: 0, nodes: []);

      final config = ParallelTrackConfig(
        trackId: 0,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      expect(config.trackId, 0);
      expect(config.enabled, false);
      expect(config.activeChain, ParallelChain.a);
      expect(config.blend, 0.0);
      expect(config.abLocked, false);
    });

    test('copyWith updates only specified fields', () {
      final chainA = DspChain(trackId: 0, nodes: []);
      final chainB = DspChain(trackId: 0, nodes: []);

      final config = ParallelTrackConfig(
        trackId: 0,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      final updated = config.copyWith(
        enabled: true,
        activeChain: ParallelChain.blend,
        blend: 0.5,
      );

      expect(updated.enabled, true);
      expect(updated.activeChain, ParallelChain.blend);
      expect(updated.blend, 0.5);
      expect(updated.trackId, 0); // Unchanged
    });

    test('currentChain returns correct chain based on activeChain', () {
      final chainA = DspChain(trackId: 0, nodes: []);
      final chainB = DspChain(trackId: 0, nodes: []);

      final configA = ParallelTrackConfig(
        trackId: 0,
        activeChain: ParallelChain.a,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      final configB = ParallelTrackConfig(
        trackId: 0,
        activeChain: ParallelChain.b,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      expect(configA.currentChain, chainA);
      expect(configB.currentChain, chainB);
    });

    test('effectiveBlend returns correct values', () {
      final chainA = DspChain(trackId: 0, nodes: []);
      final chainB = DspChain(trackId: 0, nodes: []);

      final configA = ParallelTrackConfig(
        trackId: 0,
        activeChain: ParallelChain.a,
        blend: 0.5,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      final configB = ParallelTrackConfig(
        trackId: 0,
        activeChain: ParallelChain.b,
        blend: 0.5,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      final configBlend = ParallelTrackConfig(
        trackId: 0,
        activeChain: ParallelChain.blend,
        blend: 0.7,
        chainA: chainA,
        chainB: chainB,
        lastSwitchTime: DateTime.now(),
      );

      expect(configA.effectiveBlend, 0.0);
      expect(configB.effectiveBlend, 1.0);
      expect(configBlend.effectiveBlend, 0.7);
    });
  });

  group('ABComparisonResult', () {
    test('calculates percentage on A correctly', () {
      final result = ABComparisonResult(
        trackId: 0,
        sessionDuration: const Duration(seconds: 100),
        switchCount: 5,
        timeOnA: const Duration(seconds: 60),
        timeOnB: const Duration(seconds: 40),
      );

      expect(result.percentageOnA, closeTo(0.6, 0.01));
      expect(result.percentageOnB, closeTo(0.4, 0.01));
    });

    test('handles zero duration gracefully', () {
      final result = ABComparisonResult(
        trackId: 0,
        sessionDuration: Duration.zero,
        switchCount: 0,
        timeOnA: Duration.zero,
        timeOnB: Duration.zero,
      );

      expect(result.percentageOnA, 0.0);
      expect(result.percentageOnB, 0.0);
    });
  });
}
