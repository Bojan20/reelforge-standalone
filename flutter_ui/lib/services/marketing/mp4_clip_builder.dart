/// FAZA 3.6.F Phase 2 — MP4 Marketing Clip Builder
///
/// Sastavlja MP4 fajl iz:
///   - clip.wav (60s audio bounce iz `MarketingClipExporter`)
///   - poster slika (CortexEye snapshot ili korisnik-dostavljena PNG)
///   - opcionalna sekvenca frame-ova (future: animated video)
///
/// **Strategija:** koristi sistemski `ffmpeg` binary (provjereno: macOS
/// homebrew default path `/opt/homebrew/bin/ffmpeg`). Ne uvodimo `ffmpeg-
/// next` Rust crate jer:
///   1. Cargo build vreme +30s
///   2. Linkage problem na bundling (`librf_engine.dylib` već fluk-tuje)
///   3. Marketing clip je *user-initiated* akcija, ne audio-thread —
///      latency od ffmpeg subprocess (~500ms) je prihvatljiv.
///
/// **Output:** MP4 sa H.264 video (libx264) + AAC audio. 1920×1080 default
/// (slot UI proporcije), srRate=48k matchira WAV, 30fps. Static poster za
/// MVP — animated frame sequence je future.
///
/// **Graceful degrade:** ako ffmpeg nije instaliran, vraća `Mp4Result.
/// failure` sa porukom "brew install ffmpeg" — caller prikazuje u UI-u
/// i propušta MP4 export.
library;

import 'dart:async';
import 'dart:io';

/// Rezultat MP4 build-a.
sealed class Mp4Result {
  const Mp4Result();
}

class Mp4Success extends Mp4Result {
  final String outputPath;
  final int durationMs;
  final int sizeBytes;
  const Mp4Success({
    required this.outputPath,
    required this.durationMs,
    required this.sizeBytes,
  });
}

class Mp4Failure extends Mp4Result {
  final String reason;
  final String? stderr;
  const Mp4Failure({required this.reason, this.stderr});
}

/// Builder za marketing clip MP4. Stateless — sve preko statičnih method-a.
class Mp4ClipBuilder {
  Mp4ClipBuilder._();

  /// Pretražuje common paths za ffmpeg binary.
  static const List<String> _ffmpegSearchPaths = [
    '/opt/homebrew/bin/ffmpeg', // macOS ARM Homebrew
    '/usr/local/bin/ffmpeg',    // macOS Intel Homebrew
    '/usr/bin/ffmpeg',          // Linux default
  ];

  /// Detektuje da li je ffmpeg dostupan. Cache-uje rezultat za session.
  /// Returns ffmpeg binary path or null.
  static String? _cachedFfmpegPath;
  static bool _detectedOnce = false;

  static String? detectFfmpeg() {
    if (_detectedOnce) return _cachedFfmpegPath;
    _detectedOnce = true;

    // 1. Try `which ffmpeg` (PATH lookup).
    try {
      final result = Process.runSync('which', ['ffmpeg']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          _cachedFfmpegPath = path;
          return path;
        }
      }
    } catch (_) {
      // Skip — try fallback paths.
    }

    // 2. Try known fallback paths.
    for (final p in _ffmpegSearchPaths) {
      if (File(p).existsSync()) {
        _cachedFfmpegPath = p;
        return p;
      }
    }
    return null;
  }

  /// Reset cache — za hermetičke testove.
  static void resetDetectionCache() {
    _cachedFfmpegPath = null;
    _detectedOnce = false;
  }

  /// Build MP4 sa **static poster image + audio** (MVP).
  ///
  /// - `wavPath` — input audio (48kHz stereo PCM, output MarketingClipExporter)
  /// - `posterImagePath` — PNG/JPG za video track (npr. CortexEye snapshot)
  /// - `outPath` — gde da snimi `.mp4`
  /// - `durationSec` — koliko sekundi video traje (default 60s — match WAV)
  /// - `width` / `height` — output rezolucija (default 1920×1080)
  ///
  /// Vraća Mp4Success ili Mp4Failure (sa stderr ako ffmpeg eksplodira).
  static Future<Mp4Result> buildPoster({
    required String wavPath,
    required String posterImagePath,
    required String outPath,
    double durationSec = 60.0,
    int width = 1920,
    int height = 1080,
  }) async {
    // Validate inputs.
    if (!File(wavPath).existsSync()) {
      return Mp4Failure(reason: 'WAV ne postoji: $wavPath');
    }
    if (!File(posterImagePath).existsSync()) {
      return Mp4Failure(reason: 'Poster slika ne postoji: $posterImagePath');
    }

    final ffmpeg = detectFfmpeg();
    if (ffmpeg == null) {
      return const Mp4Failure(
        reason: 'ffmpeg nije instaliran. Instaliraj: brew install ffmpeg',
      );
    }

    // Ensure output dir.
    final outFile = File(outPath);
    final outDir = outFile.parent;
    if (!outDir.existsSync()) {
      try {
        outDir.createSync(recursive: true);
      } catch (e) {
        return Mp4Failure(reason: 'Ne mogu da kreiram output dir: $e');
      }
    }

    // ffmpeg cmd:
    // - loop static image for N seconds
    // - mix with WAV audio (re-encode na AAC 192k)
    // - libx264 preset fast, yuv420p za QuickTime/Safari compat
    // - shortest=stop kad audio završi
    final args = [
      '-loglevel', 'error',
      '-y', // overwrite
      '-loop', '1',
      '-i', posterImagePath,
      '-i', wavPath,
      '-t', durationSec.toStringAsFixed(2),
      '-vf', 'scale=$width:$height:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:black,format=yuv420p',
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-tune', 'stillimage',
      '-r', '30',
      '-c:a', 'aac',
      '-b:a', '192k',
      '-shortest',
      outPath,
    ];

    final stopwatch = Stopwatch()..start();
    try {
      final result = await Process.run(ffmpeg, args);
      stopwatch.stop();

      if (result.exitCode != 0) {
        return Mp4Failure(
          reason: 'ffmpeg exit ${result.exitCode}',
          stderr: result.stderr is String ? result.stderr as String : null,
        );
      }
      if (!outFile.existsSync()) {
        return Mp4Failure(
          reason: 'ffmpeg završio bez greške ali fajl nije kreiran',
        );
      }
      final size = outFile.lengthSync();
      return Mp4Success(
        outputPath: outPath,
        durationMs: stopwatch.elapsedMilliseconds,
        sizeBytes: size,
      );
    } catch (e) {
      return Mp4Failure(reason: 'Process.run threw: $e');
    }
  }

  /// Pokušaj concat sekvence PNG frame-ova + WAV (future). Trenutno
  /// vraća Mp4Failure sa "not implemented" — stub za buduće.
  static Future<Mp4Result> buildFromFrames({
    required String wavPath,
    required List<String> framePaths,
    required String outPath,
    int fps = 30,
  }) async {
    return const Mp4Failure(
      reason: 'buildFromFrames još nije implementirano '
          '(buildPoster pokriva MVP marketing use-case).',
    );
  }
}
