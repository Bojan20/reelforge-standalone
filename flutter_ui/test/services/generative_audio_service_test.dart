// FAZA 5.1.3 — Dart-side unit tests for the request layer of
// GenerativeAudioService.
//
// We can't exercise the FFI roundtrip from `flutter test` (the rf-bridge
// dylib isn't loaded in unit-test contexts), so the integration test for
// the actual native call lives in `rf-bridge::generative_ffi::tests`. Here
// we lock the *contract* the Rust side reads — JSON shape, enum wire
// names, edge cases — so a future drift on either side trips a test
// instead of a runtime FFI error.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/generative_audio_service.dart';

void main() {
  group('GenerationRequest JSON encoding', () {
    test('minimal request emits required fields', () {
      const req = GenerationRequest(
        prompt: 'small win',
        durationSeconds: 1.5,
      );
      final json = jsonDecode(jsonEncode(req.toJson())) as Map<String, dynamic>;
      expect(json['prompt'], 'small win');
      expect(json['duration_seconds'], 1.5);
      expect(json['sample_rate_hz'], 0);
      expect(json.containsKey('seed'), isFalse,
          reason: 'null seed must be omitted, not encoded as null');
      expect(json['style'], isA<Map<String, dynamic>>());
    });

    test('full request round-trips with all fields', () {
      const req = GenerationRequest(
        prompt: 'mega win',
        durationSeconds: 3.0,
        sampleRateHz: 48000,
        seed: 1234,
        style: GenerationStyle(
          stageHint: SlotStageHint.winMega,
          emotionalArc: EmotionalArc([
            EmotionalArcPoint(t: 0.0, intensity: 0.1),
            EmotionalArcPoint(t: 0.5, intensity: 0.6),
            EmotionalArcPoint(t: 1.0, intensity: 1.0),
          ]),
          tags: ['brassy', 'wide'],
        ),
      );
      final json = jsonDecode(jsonEncode(req.toJson())) as Map<String, dynamic>;
      expect(json['prompt'], 'mega win');
      expect(json['duration_seconds'], 3.0);
      expect(json['sample_rate_hz'], 48000);
      expect(json['seed'], 1234);
      final style = json['style'] as Map<String, dynamic>;
      expect(style['stage_hint'], 'win_mega');
      final arc = style['emotional_arc'] as Map<String, dynamic>;
      final points = arc['points'] as List<dynamic>;
      expect(points.length, 3);
      expect(points.first, {'t': 0.0, 'intensity': 0.1});
      expect(points.last, {'t': 1.0, 'intensity': 1.0});
      expect(style['tags'], ['brassy', 'wide']);
    });

    test('empty tags / null emotional arc are omitted from style', () {
      const req = GenerationRequest(
        prompt: 'idle hum',
        durationSeconds: 0.5,
        style: GenerationStyle(stageHint: SlotStageHint.idle),
      );
      final style = (jsonDecode(jsonEncode(req.toJson()))
          as Map<String, dynamic>)['style'] as Map<String, dynamic>;
      expect(style.containsKey('emotional_arc'), isFalse);
      expect(style.containsKey('tags'), isFalse);
      expect(style['stage_hint'], 'idle');
    });
  });

  group('SlotStageHint.wireName', () {
    test('every variant uses snake_case', () {
      // Lock the exact strings the Rust side deserializes.
      const expected = {
        SlotStageHint.idle: 'idle',
        SlotStageHint.anticipation: 'anticipation',
        SlotStageHint.reelStop: 'reel_stop',
        SlotStageHint.winSmall: 'win_small',
        SlotStageHint.winMedium: 'win_medium',
        SlotStageHint.winBig: 'win_big',
        SlotStageHint.winMega: 'win_mega',
        SlotStageHint.bonusTrigger: 'bonus_trigger',
        SlotStageHint.freeSpinStart: 'free_spin_start',
        SlotStageHint.jackpotHit: 'jackpot_hit',
        SlotStageHint.cascade: 'cascade',
        SlotStageHint.gameOver: 'game_over',
      };
      for (final entry in expected.entries) {
        expect(entry.key.wireName, entry.value,
            reason: 'mismatch for ${entry.key}');
      }
      // Ratchet: every enum variant must have a mapping. If a new variant
      // is added on the Dart side without updating the map, this fails.
      expect(SlotStageHint.values.length, expected.length);
    });
  });

  group('GenerationMetadata.fromJson', () {
    test('parses full payload', () {
      final json = jsonDecode('''{
        "backend_id": "mock",
        "model_id": "none",
        "seed": 7,
        "generated_at_utc": "2026-05-11T15:30:00Z",
        "duration_seconds": 1.25,
        "frame_count": 60000
      }''') as Map<String, dynamic>;
      final md = GenerationMetadata.fromJson(json);
      expect(md.backendId, 'mock');
      expect(md.modelId, 'none');
      expect(md.seed, 7);
      expect(md.generatedAtUtc, '2026-05-11T15:30:00Z');
      expect(md.durationSeconds, 1.25);
      expect(md.frameCount, 60000);
    });

    test('handles missing seed gracefully', () {
      final md = GenerationMetadata.fromJson({
        'backend_id': 'mock',
        'model_id': 'none',
        'generated_at_utc': '2026-05-11T00:00:00Z',
        'duration_seconds': 0.5,
        'frame_count': 24000,
      });
      expect(md.seed, isNull);
    });

    test('falls back when fields are absent', () {
      final md = GenerationMetadata.fromJson({});
      expect(md.backendId, 'unknown');
      expect(md.modelId, 'none');
      expect(md.seed, isNull);
      expect(md.generatedAtUtc, '');
      expect(md.durationSeconds, 0.0);
      expect(md.frameCount, 0);
    });
  });

  group('GenerationException', () {
    test('toString surfaces message', () {
      final e = GenerationException('duration out of range');
      expect(e.toString(), contains('duration out of range'));
    });
  });

  group('GenerationResult.frameCount', () {
    test('mono yields pcm.length frames', () {
      final res = GenerationResult(
        pcm: Float32List.fromList([0.1, 0.2, 0.3]),
        sampleRateHz: 48000,
        channels: 1,
        latencyMs: 1,
        metadata: const GenerationMetadata(
          backendId: 'mock',
          modelId: 'none',
          seed: null,
          generatedAtUtc: '',
          durationSeconds: 0.0,
          frameCount: 3,
        ),
      );
      expect(res.frameCount, 3);
    });

    test('stereo halves pcm.length', () {
      final res = GenerationResult(
        pcm: Float32List.fromList([0, 1, 2, 3, 4, 5]),
        sampleRateHz: 48000,
        channels: 2,
        latencyMs: 1,
        metadata: const GenerationMetadata(
          backendId: 'mock',
          modelId: 'none',
          seed: null,
          generatedAtUtc: '',
          durationSeconds: 0.0,
          frameCount: 3,
        ),
      );
      expect(res.frameCount, 3);
    });

    test('zero channels yields zero frames', () {
      final res = GenerationResult(
        pcm: Float32List(0),
        sampleRateHz: 0,
        channels: 0,
        latencyMs: 0,
        metadata: const GenerationMetadata(
          backendId: 'mock',
          modelId: 'none',
          seed: null,
          generatedAtUtc: '',
          durationSeconds: 0.0,
          frameCount: 0,
        ),
      );
      expect(res.frameCount, 0);
    });
  });
}
