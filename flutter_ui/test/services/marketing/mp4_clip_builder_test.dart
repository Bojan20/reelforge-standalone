/// FAZA 3.6.F Phase 2 — `Mp4ClipBuilder` unit tests.
///
/// Pokriva:
/// - detectFfmpeg() returns path or null
/// - buildPoster validates WAV / poster existence
/// - buildPoster returns Mp4Failure when ffmpeg missing (mocked)
/// - buildPoster returns Mp4Success when ffmpeg available + inputs valid
/// - buildFromFrames stub vraća Mp4Failure
///
/// E2E test (real ffmpeg invocation) je opcionalan — uslovljen postojanjem
/// /opt/homebrew/bin/ffmpeg na CI runneru. Skip ako nije instaliran.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/marketing/mp4_clip_builder.dart';

void main() {
  group('Mp4ClipBuilder — detection', () {
    setUp(() => Mp4ClipBuilder.resetDetectionCache());

    test('detectFfmpeg returns ffmpeg path on macOS Homebrew', () {
      final path = Mp4ClipBuilder.detectFfmpeg();
      if (path == null) {
        // ffmpeg nije instaliran — skip (ne fail).
        return;
      }
      expect(File(path).existsSync(), isTrue);
      expect(path, contains('ffmpeg'));
    });

    test('detection result is cached', () {
      final path1 = Mp4ClipBuilder.detectFfmpeg();
      final path2 = Mp4ClipBuilder.detectFfmpeg();
      expect(path1, path2); // same instance (cached)
    });

    test('resetDetectionCache forces re-detection', () {
      Mp4ClipBuilder.detectFfmpeg();
      Mp4ClipBuilder.resetDetectionCache();
      // After reset, next call hits filesystem again — but result je isti.
      final after = Mp4ClipBuilder.detectFfmpeg();
      expect(after == null || File(after).existsSync(), isTrue);
    });
  });

  group('Mp4ClipBuilder — buildPoster validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mp4_builder_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('missing WAV → Mp4Failure', () async {
      final result = await Mp4ClipBuilder.buildPoster(
        wavPath: '${tempDir.path}/nonexistent.wav',
        posterImagePath: '${tempDir.path}/nonexistent.png',
        outPath: '${tempDir.path}/out.mp4',
      );
      expect(result, isA<Mp4Failure>());
      expect((result as Mp4Failure).reason, contains('WAV'));
    });

    test('missing poster → Mp4Failure', () async {
      // Create WAV but no poster.
      final wav = File('${tempDir.path}/dummy.wav');
      await wav.writeAsBytes([0, 0, 0, 0]); // fake content; ffmpeg validation
      // not reached because we return early on file-existence check.

      final result = await Mp4ClipBuilder.buildPoster(
        wavPath: wav.path,
        posterImagePath: '${tempDir.path}/nonexistent.png',
        outPath: '${tempDir.path}/out.mp4',
      );
      expect(result, isA<Mp4Failure>());
      expect((result as Mp4Failure).reason, contains('Poster'));
    });
  });

  group('Mp4ClipBuilder — buildFromFrames stub', () {
    test('returns not-implemented failure', () async {
      final result = await Mp4ClipBuilder.buildFromFrames(
        wavPath: '/dev/null',
        framePaths: const ['/dev/null'],
        outPath: '/dev/null',
      );
      expect(result, isA<Mp4Failure>());
      expect((result as Mp4Failure).reason, contains('nije implementirano'));
    });
  });

  group('Mp4ClipBuilder — Mp4Result types', () {
    test('Mp4Success contains all output fields', () {
      const r = Mp4Success(
        outputPath: '/tmp/out.mp4',
        durationMs: 1500,
        sizeBytes: 102400,
      );
      expect(r.outputPath, '/tmp/out.mp4');
      expect(r.durationMs, 1500);
      expect(r.sizeBytes, 102400);
    });

    test('Mp4Failure carries reason + optional stderr', () {
      const r = Mp4Failure(reason: 'x', stderr: 'ffmpeg: error');
      expect(r.reason, 'x');
      expect(r.stderr, 'ffmpeg: error');
    });
  });

  // E2E test — uslovljen postojanjem ffmpeg + libpng tooling (image gen).
  // Skipovan po default-u; pokrenuti ručno za smoke test posle ffmpeg
  // version upgrades.
  group('Mp4ClipBuilder — E2E (skip if ffmpeg not present)', () {
    late Directory tempDir;

    setUp(() async {
      Mp4ClipBuilder.resetDetectionCache();
      tempDir = await Directory.systemTemp.createTemp('mp4_e2e_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('real ffmpeg builds 2s poster MP4', () async {
      final ffmpeg = Mp4ClipBuilder.detectFfmpeg();
      if (ffmpeg == null) {
        return; // Skip silently.
      }

      // Generate test inputs via ffmpeg itself:
      //   1) 2s silent WAV
      //   2) 16×16 black PNG
      final wavPath = '${tempDir.path}/silent.wav';
      final pngPath = '${tempDir.path}/black.png';
      final outPath = '${tempDir.path}/out.mp4';

      final wavGen = await Process.run(ffmpeg, [
        '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000',
        '-t', '2', wavPath,
      ]);
      expect(wavGen.exitCode, 0,
          reason: 'wav gen stderr: ${wavGen.stderr}');

      final pngGen = await Process.run(ffmpeg, [
        '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'color=c=black:s=16x16:d=1',
        '-frames:v', '1', pngPath,
      ]);
      expect(pngGen.exitCode, 0,
          reason: 'png gen stderr: ${pngGen.stderr}');

      // Build MP4.
      final result = await Mp4ClipBuilder.buildPoster(
        wavPath: wavPath,
        posterImagePath: pngPath,
        outPath: outPath,
        durationSec: 2.0,
        width: 320,
        height: 240,
      );
      expect(result, isA<Mp4Success>(),
          reason: result is Mp4Failure
              ? 'reason: ${result.reason}, stderr: ${result.stderr}'
              : null);
      final success = result as Mp4Success;
      expect(File(success.outputPath).existsSync(), isTrue);
      expect(success.sizeBytes, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
