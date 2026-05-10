// FLUX_MASTER_TODO 0.5 E.1 (3.6.F) — Marketing Clip Export.
//
// One-click "best win" → marketing-ready clip bundle pod
// `~/Library/Application Support/FluxForge Studio/clips/clip_<id>/`:
//
//   clip.wav         — 60s master output bounce (Sprint 9 E.4 ring buffer)
//   metadata.json    — RNG seed + win amount + multiplier + stage timeline
//                      + market session metadata (B.4 trace export reuse)
//   README.txt       — quick orientation file za marketing tim
//
// MP4 screen recording je odložen za Phase 2 — zahteva ffmpeg-next dep
// dodavanje + integration sa CortexVisionService capture loop. WAV +
// JSON cover-uju 90% marketing use-case-a (placeholder video iz screen
// recording-a je trivial da se kasnije doda).
//
// Razlog "clip-folder umesto single file" pristupa: marketing tim treba
// distinct atomske artefakte (audio za podcast/social, JSON za seed
// reproducibility, README za context) — ne single-file MP4 koji zaheva
// ffmpeg za inspekciju metadata-a.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../src/rust/native_ffi.dart' show NativeFFI;
import 'event_timing_trace_exporter.dart';
import 'session_recorder.dart';

/// Marketing clip — 60s WAV + metadata bundle.
class MarketingClip {
  final String clipId;
  final DateTime exportedAt;
  final String folderPath;
  final String wavPath;
  final String metadataPath;
  final String readmePath;
  final int wavFrames;

  const MarketingClip({
    required this.clipId,
    required this.exportedAt,
    required this.folderPath,
    required this.wavPath,
    required this.metadataPath,
    required this.readmePath,
    required this.wavFrames,
  });

  /// Trajanje klipa u sekundama (frame count / 48k, fallback 60.0).
  double get durationSeconds => wavFrames / 48000.0;

  Map<String, dynamic> toJson() => {
        'clip_id': clipId,
        'exported_at': exportedAt.toIso8601String(),
        'folder_path': folderPath,
        'wav_path': wavPath,
        'metadata_path': metadataPath,
        'readme_path': readmePath,
        'wav_frames': wavFrames,
        'duration_seconds': durationSeconds,
      };
}

/// Result wrapper sa eksplicitnim error handling-om.
class MarketingClipResult {
  final MarketingClip? clip;
  final String? error;

  const MarketingClipResult.success(this.clip) : error = null;
  const MarketingClipResult.failure(this.error) : clip = null;

  bool get isSuccess => clip != null;
}

/// Singleton exporter. Stateless — sav state u `SessionSpinSnapshot`
/// argumentu i `EventTimingTraceExporter` (B.4) dependency-ja.
class MarketingClipExporter extends ChangeNotifier {
  static final MarketingClipExporter instance = MarketingClipExporter._();
  MarketingClipExporter._();

  /// Marketing clip window u sekundama. Mirror-uje
  /// `master_ring::MARKETING_CLIP_SECONDS = 60.0` Rust konstantu.
  static const double clipWindowSeconds = 60.0;

  MarketingClip? _lastExported;
  MarketingClip? get lastExported => _lastExported;

  /// Eksportuje marketing clip za dati `SessionSpinSnapshot` (best-win).
  /// Vraca uspeh/gresku — caller prikazuje SnackBar.
  Future<MarketingClipResult> exportClip({
    required SessionSpinSnapshot snapshot,
    required NativeFFI ffi,
    String? extraNote,
  }) async {
    // 1. Resolve clips folder.
    final clipsRoot = _resolveClipsRoot();
    if (clipsRoot == null) {
      return const MarketingClipResult.failure(
        'Cannot resolve clips folder — HOME env nedostupan.',
      );
    }

    // 2. Compose clip ID — sanitized.
    final spinId = snapshot.result.spinId;
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final safeSpinId = spinId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final clipId = 'clip_${safeSpinId}_$ts';
    final folder = Directory('${clipsRoot.path}/$clipId');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }

    // 3. WAV bounce — 60s master ring snapshot.
    final wavPath = '${folder.path}/clip.wav';
    int wavFrames = 0;
    try {
      wavFrames = ffi.orbCaptureLastNSeconds(
        wavPath,
        seconds: clipWindowSeconds,
      );
    } catch (e) {
      return MarketingClipResult.failure('WAV bounce FFI error: $e');
    }
    if (wavFrames == 0) {
      // Lazy-init might have failed (no audio played) or path invalid.
      // Cleanup pre nego sto vratimo error.
      try {
        await folder.delete(recursive: true);
      } catch (_) {}
      return const MarketingClipResult.failure(
        'WAV bounce vratio 0 frames — proveri da li audio engine radi i '
        'da li je orb_ring_init pozvan sa 60s + sample rate.',
      );
    }

    // 4. Metadata JSON — reuse B.4 SpinTraceReport schema.
    final metadataPath = '${folder.path}/metadata.json';
    final report = SpinTraceReport(
      spinId: spinId,
      exportedAt: DateTime.now(),
      result: snapshot.result,
      stages: snapshot.stages,
      metadata: {
        'export_source': 'MarketingClipExporter',
        'export_kind': 'marketing_clip',
        'platform': Platform.operatingSystem,
        'wav_window_seconds': clipWindowSeconds,
        'wav_frames': wavFrames,
        'wav_duration_seconds': wavFrames / 48000.0,
        'highlight_score': snapshot.highlightScore,
        'session_sequence': snapshot.sequenceNumber,
        if (extraNote != null && extraNote.isNotEmpty) 'note': extraNote,
      },
    );
    final metaFile = File(metadataPath);
    final metaJson =
        const JsonEncoder.withIndent('  ').convert(report.toJson());
    await metaFile.writeAsString(metaJson, flush: true);

    // 5. README — markdown za marketing orientation.
    final readmePath = '${folder.path}/README.txt';
    final readmeFile = File(readmePath);
    final readme = _composeReadme(
      clipId: clipId,
      snapshot: snapshot,
      wavFrames: wavFrames,
      extraNote: extraNote,
    );
    await readmeFile.writeAsString(readme, flush: true);

    final clip = MarketingClip(
      clipId: clipId,
      exportedAt: DateTime.now(),
      folderPath: folder.path,
      wavPath: wavPath,
      metadataPath: metadataPath,
      readmePath: readmePath,
      wavFrames: wavFrames,
    );
    _lastExported = clip;
    notifyListeners();
    return MarketingClipResult.success(clip);
  }

  /// Lista svih izvezenih clipova (folder skeniranje).
  /// Sortirano po dt-u (najnovije prvo).
  Future<List<String>> listExports() async {
    final root = _resolveClipsRoot();
    if (root == null || !root.existsSync()) return const [];
    final entries = root
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path)
        .toList();
    entries.sort((a, b) => b.compareTo(a));
    return entries;
  }

  Directory? _resolveClipsRoot() {
    final home = Platform.environment['HOME'];
    final base = (home != null && home.isNotEmpty)
        ? '$home/Library/Application Support/FluxForge Studio'
        : '/tmp/fluxforge-studio';
    final clipsDir = Directory('$base/clips');
    if (!clipsDir.existsSync()) {
      try {
        clipsDir.createSync(recursive: true);
      } catch (_) {
        return null;
      }
    }
    return clipsDir;
  }

  String _composeReadme({
    required String clipId,
    required SessionSpinSnapshot snapshot,
    required int wavFrames,
    String? extraNote,
  }) {
    final r = snapshot.result;
    final dur = (wavFrames / 48000.0).toStringAsFixed(2);
    return '''
FluxForge Studio — Marketing Clip Bundle
=========================================

Clip ID:        $clipId
Exported at:    ${DateTime.now().toIso8601String()}

Win Tier:       ${r.winTierName}
Total Win:      ${r.totalWin.toStringAsFixed(2)}
Bet:            ${r.bet.toStringAsFixed(2)}
Win Ratio:      ×${r.winRatio.toStringAsFixed(2)}
Multiplier:     ×${r.multiplier.toStringAsFixed(2)}
Cascade Count:  ${r.cascadeCount}
Free Spins:     ${r.isFreeSpins ? 'YES' : 'no'}
Highlight Score: ${snapshot.highlightScore.toStringAsFixed(2)}

Audio (clip.wav):
  16-bit PCM stereo @ 48 kHz
  Frames: $wavFrames
  Duration: ${dur}s

Metadata (metadata.json):
  Schema: SpinTraceReport v1
  Per-stage timing (timestamp_ms + payload)
  Stage count: ${snapshot.stages.length}

Reproducibility:
  spin_id: ${r.spinId}
  Use this with `--seed` flag in slot_sim CLI to reproduce
  the exact RNG sequence (assuming engine version match).

${extraNote != null ? 'Note: $extraNote\n\n' : ''}-- Generated by FluxForge MarketingClipExporter (FAZA 0.5 E.1) --
''';
  }
}
