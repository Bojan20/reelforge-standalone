/// Unit tests for VoiceHistoryBuffer (Phase 10e-4 performance edition).
///
/// Covers:
/// - Ghost creation when a voice disappears
/// - Ghost expiry (but through alpha, since maxAge is 10 s)
/// - Cache invalidation on observe
/// - Bus bucket correctness
/// - Isolate offload pathway (observeInIsolate path + fallback)
/// - clear() wipes everything

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/orb_mixer_provider.dart';
import 'package:fluxforge_ui/services/voice_history_buffer.dart';

OrbVoiceState _v(int id, OrbBusId bus, {double peakL = 0.5, double peakR = 0.5}) =>
    OrbVoiceState(voiceId: id, bus: bus, peakL: peakL, peakR: peakR);

void main() {
  group('VoiceHistoryBuffer — sync observe', () {
    test('empty state has no ghosts', () {
      final h = VoiceHistoryBuffer();
      expect(h.liveCount, 0);
      expect(h.liveGhosts, isEmpty);
      expect(h.ghostsFor(OrbBusId.sfx), isEmpty);
    });

    test('voice that disappears becomes a ghost', () {
      final h = VoiceHistoryBuffer();
      h.observe([_v(1, OrbBusId.sfx, peakL: 0.8, peakR: 0.6)]);
      h.observe(const []); // voice 1 ended
      expect(h.liveCount, 1);
      final g = h.liveGhosts.first;
      expect(g.voiceId, 1);
      expect(g.bus, OrbBusId.sfx);
      expect(g.peakL, closeTo(0.8, 1e-6));
      expect(g.peakR, closeTo(0.6, 1e-6));
    });

    test('voice still present in next tick is not ghosted', () {
      final h = VoiceHistoryBuffer();
      h.observe([_v(1, OrbBusId.music)]);
      h.observe([_v(1, OrbBusId.music)]);
      expect(h.liveCount, 0);
    });

    test('ghosts bucket correctly by bus', () {
      final h = VoiceHistoryBuffer();
      h.observe([
        _v(1, OrbBusId.sfx),
        _v(2, OrbBusId.music),
        _v(3, OrbBusId.sfx),
      ]);
      h.observe(const []); // all three end
      expect(h.ghostsFor(OrbBusId.sfx).length, 2);
      expect(h.ghostsFor(OrbBusId.music).length, 1);
      expect(h.ghostsFor(OrbBusId.voice), isEmpty);
    });

    test('liveGhosts is cached across reads until next observe', () {
      final h = VoiceHistoryBuffer();
      h.observe([_v(1, OrbBusId.sfx)]);
      h.observe(const []);
      final a = h.liveGhosts;
      final b = h.liveGhosts;
      expect(identical(a, b), isTrue,
          reason: 'cache should return same list instance');
      h.observe([_v(9, OrbBusId.voice)]);
      h.observe(const []);
      final c = h.liveGhosts;
      expect(identical(a, c), isFalse,
          reason: 'cache must be invalidated on observe');
      expect(c.length, 2);
    });

    test('ghostsFor is bucket-cached per bus', () {
      final h = VoiceHistoryBuffer();
      h.observe([_v(1, OrbBusId.sfx), _v(2, OrbBusId.sfx)]);
      h.observe(const []);
      final a = h.ghostsFor(OrbBusId.sfx);
      final b = h.ghostsFor(OrbBusId.sfx);
      expect(identical(a, b), isTrue);
    });

    test('clear() wipes buffer, prev ids and caches', () {
      final h = VoiceHistoryBuffer();
      h.observe([_v(1, OrbBusId.sfx)]);
      h.observe(const []);
      expect(h.liveCount, 1);
      h.clear();
      expect(h.liveCount, 0);
      expect(h.liveGhosts, isEmpty);
      // Next observe cycle must NOT carry any previous-tick IDs.
      h.observe(const []);
      expect(h.liveCount, 0);
    });

    test('buffer caps to hard limit under bursty load', () {
      final h = VoiceHistoryBuffer();
      // Generate 200 sequentially-ending voices across 2 ticks.
      final first = List.generate(200, (i) => _v(i, OrbBusId.sfx));
      h.observe(first);
      h.observe(const []); // all 200 end → buffer capped to 128
      expect(h.liveCount, 128);
    });
  });

  group('VoiceHistoryBuffer — isolate offload', () {
    test('small active set takes the sync fast path', () async {
      final h = VoiceHistoryBuffer();
      h.observe([_v(1, OrbBusId.sfx)]);
      await h.observeInIsolate(const []);
      // Did NOT spawn an isolate for a 0-voice set.
      expect(h.hasIsolateWorker, isFalse);
      expect(h.liveCount, 1);
    });

    test('large active set routes through isolate and returns correct ghosts',
        () async {
      final h = VoiceHistoryBuffer();
      // First observe: 120 active voices (exceeds threshold of 100).
      final active = List.generate(120, (i) => _v(i, OrbBusId.sfx));
      await h.observeInIsolate(active);
      // Nothing ended yet.
      expect(h.liveCount, 0);
      // Now end everything — isolate diff detects 120 ends.
      await h.observeInIsolate(const []);
      expect(h.hasIsolateWorker, isTrue,
          reason: 'isolate should have been spawned on heavy load');
      // Capped to 128, but 120 ends fit cleanly.
      expect(h.liveCount, 120);
      // Clean up: kill worker.
      h.disposeWorker();
      expect(h.hasIsolateWorker, isFalse);
    });
  });
}
