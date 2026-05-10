/// FLUX_MASTER_TODO 0.5 E.1 — Marketing Clip Exporter unit tests.
///
/// Pin-uje invariante koji se mogu testirati bez Rust FFI live-a:
///   * MarketingClip JSON shape
///   * Result wrapper success/failure semantike
///   * Clip window konstanta = 60s (mirror MARKETING_CLIP_SECONDS)
///   * `clipWindowSeconds` prilagođen ka 60.0 — Sprint 9 E.4 sync
///
/// FFI integration test (write actual WAV) ne ide ovde — zahteva live
/// audio engine. Pokriven manualnim smoke test-om kroz session recorder.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/marketing_clip_exporter.dart';

void main() {
  group('MarketingClip JSON shape', () {
    test('toJson uključuje sve key-eve + duration computation', () {
      final clip = MarketingClip(
        clipId: 'clip_test',
        exportedAt: DateTime.utc(2026, 5, 10, 3, 0, 0),
        folderPath: '/tmp/clips/clip_test',
        wavPath: '/tmp/clips/clip_test/clip.wav',
        metadataPath: '/tmp/clips/clip_test/metadata.json',
        readmePath: '/tmp/clips/clip_test/README.txt',
        wavFrames: 2_880_000, // 60s @ 48kHz
      );
      final json = clip.toJson();
      expect(json['clip_id'], equals('clip_test'));
      expect(json['exported_at'], equals('2026-05-10T03:00:00.000Z'));
      expect(json['folder_path'], equals('/tmp/clips/clip_test'));
      expect(json['wav_path'], equals('/tmp/clips/clip_test/clip.wav'));
      expect(json['metadata_path'], equals('/tmp/clips/clip_test/metadata.json'));
      expect(json['readme_path'], equals('/tmp/clips/clip_test/README.txt'));
      expect(json['wav_frames'], equals(2_880_000));
      expect(json['duration_seconds'], equals(60.0));
    });

    test('durationSeconds = wavFrames / 48000', () {
      // 24000 frames = 0.5s
      final c = MarketingClip(
        clipId: 'half',
        exportedAt: DateTime.now(),
        folderPath: '/x',
        wavPath: '/x/clip.wav',
        metadataPath: '/x/m.json',
        readmePath: '/x/r.txt',
        wavFrames: 24000,
      );
      expect(c.durationSeconds, equals(0.5));
    });

    test('durationSeconds = 0 za zero-frames', () {
      final c = MarketingClip(
        clipId: 'empty',
        exportedAt: DateTime.now(),
        folderPath: '/x',
        wavPath: '/x/clip.wav',
        metadataPath: '/x/m.json',
        readmePath: '/x/r.txt',
        wavFrames: 0,
      );
      expect(c.durationSeconds, equals(0));
    });
  });

  group('MarketingClipResult semantike', () {
    test('success ima clip + null error', () {
      final clip = MarketingClip(
        clipId: 's',
        exportedAt: DateTime.now(),
        folderPath: '/',
        wavPath: '/',
        metadataPath: '/',
        readmePath: '/',
        wavFrames: 100,
      );
      final r = MarketingClipResult.success(clip);
      expect(r.isSuccess, isTrue);
      expect(r.clip, isNotNull);
      expect(r.error, isNull);
    });

    test('failure ima error + null clip', () {
      const r = MarketingClipResult.failure('boom');
      expect(r.isSuccess, isFalse);
      expect(r.clip, isNull);
      expect(r.error, equals('boom'));
    });
  });

  group('MarketingClipExporter constants', () {
    test('clipWindowSeconds = 60.0 (mirror MARKETING_CLIP_SECONDS)', () {
      expect(MarketingClipExporter.clipWindowSeconds, equals(60.0));
    });

    test('singleton instance je accessible', () {
      expect(MarketingClipExporter.instance, isNotNull);
      expect(MarketingClipExporter.instance,
          same(MarketingClipExporter.instance));
    });
  });
}
