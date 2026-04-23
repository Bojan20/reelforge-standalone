/// PHASE 10e — Problems Inbox service
///
/// Captures snapshots of the live mix when the user hits "Mark Problem"
/// on the Live Play orb, persists them locally, and exposes the list to
/// a review panel later.
///
/// Storage: flat JSON array at
///   `<app support>/FluxForge Studio/problems_inbox.json`
///
/// Capped at 200 entries — oldest dropped when full. Typical session
/// produces 5-15 markers, so the cap is really a safety net.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/mix_problem.dart';
import '../providers/orb_mixer_provider.dart';
import '../src/rust/native_ffi.dart' show NativeFFI;
import 'shared_meter_reader.dart';

/// Singleton inbox — GetIt-free so it's easy to call from any widget.
class ProblemsInboxService extends ChangeNotifier {
  ProblemsInboxService._();
  static final ProblemsInboxService instance = ProblemsInboxService._();

  /// Maximum problems retained. Oldest evicted on overflow.
  static const int maxEntries = 200;

  /// Storage file (lazy-resolved on first save/load).
  File? _storageFile;

  /// In-memory list (newest first).
  final List<MixProblem> _problems = [];

  List<MixProblem> get problems => List.unmodifiable(_problems);
  int get count => _problems.length;

  bool _initialized = false;

  /// Initialize + hydrate from disk. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // Mirror the pattern used by waveform_cache_service / cortex_vision:
      //   ~/Library/Application Support/FluxForge Studio/
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;
      final dir = Directory(
          '$home/Library/Application Support/FluxForge Studio');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _storageFile = File('${dir.path}/problems_inbox.json');
      if (await _storageFile!.exists()) {
        final raw = await _storageFile!.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            _problems.clear();
            for (final entry in decoded) {
              try {
                _problems.add(MixProblem.fromJson(
                    (entry as Map).cast<String, dynamic>()));
              } catch (_) {
                // Skip malformed entries — don't break the whole inbox.
              }
            }
          }
        }
      }
      notifyListeners();
    } catch (_) {
      // Storage fail is not fatal — service runs in memory-only mode.
    }
  }

  /// Phase 10e-2: seconds of master audio exported alongside each mark.
  static const double clipSeconds = 5.0;

  /// Directory for per-problem WAV clips (lazy-created on first capture).
  Directory? _clipsDir;

  Future<Directory?> _ensureClipsDir() async {
    if (_clipsDir != null) return _clipsDir;
    final storage = _storageFile;
    if (storage == null) return null;
    final dir = Directory('${storage.parent.path}/problem_clips');
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _clipsDir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Build + store a new problem from current provider state.
  Future<MixProblem> capture({
    required OrbMixerProvider orb,
    required SharedMeterSnapshot snapshot,
    required String? fsmState,
    required double bet,
    String note = '',
  }) async {
    // Flatten per-bus peaks (6 buses × 2 channels).
    final busPeaks = <double>[];
    for (final b in OrbBusId.values) {
      final idx = b.engineIndex;
      if (idx * 2 + 1 < snapshot.channelPeaks.length) {
        busPeaks.add(snapshot.channelPeaks[idx * 2]);
        busPeaks.add(snapshot.channelPeaks[idx * 2 + 1]);
      } else {
        busPeaks.add(0);
        busPeaks.add(0);
      }
    }

    // Flatten voices: 6 floats per voice.
    final voiceData = <double>[];
    for (final v in orb.allVoices) {
      voiceData.add(v.voiceId.toDouble());
      voiceData.add(v.bus.engineIndex.toDouble());
      voiceData.add(v.peakL);
      voiceData.add(v.peakR);
      voiceData.add(v.volume);
      voiceData.add(v.isLooping ? 1.0 : 0.0);
    }

    final alerts = orb.activeAlerts
        .map((a) => MixAlertSnapshot(
              type: a.type.name,
              severity: a.severity.name,
              busName: a.bus?.name,
              otherBusName: a.otherBus?.name,
            ))
        .toList(growable: false);

    final id = DateTime.now().millisecondsSinceEpoch;
    final clip = await _captureClipFor(id);

    final problem = MixProblem(
      id: id,
      markedAt: DateTime.now(),
      note: note,
      fsmState: fsmState,
      bet: bet,
      busPeaks: busPeaks,
      voices: voiceData,
      spectrumBands: snapshot.spectrumBands.toList(growable: false),
      alerts: alerts,
      audioClipPath: clip?.path,
      audioClipFrames: clip?.frames ?? 0,
      audioClipSampleRate: clip?.sampleRate ?? 0,
    );

    _problems.insert(0, problem);
    while (_problems.length > maxEntries) {
      _problems.removeLast();
    }
    notifyListeners();
    await _persistAsync();
    return problem;
  }

  /// Best-effort audio clip capture for a new problem. Returns null if the
  /// engine hasn't produced any audio yet or if any step fails.
  Future<_CapturedClip?> _captureClipFor(int id) async {
    try {
      final dir = await _ensureClipsDir();
      if (dir == null) return null;
      final ffi = NativeFFI.instance;
      if (ffi.orbRingFramesWritten() == 0) return null;
      final path = '${dir.path}/$id.wav';
      final n = ffi.orbCaptureLastNSeconds(path, seconds: clipSeconds);
      if (n <= 0) return null;
      // Audio thread may have played less than clipSeconds so far — derive SR
      // from frames/seconds actually grabbed.
      final sr = (n / clipSeconds).round().clamp(1, 384000);
      return _CapturedClip(path: path, frames: n, sampleRate: sr);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteClipFile(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {/* non-fatal */}
  }

  /// Update a problem's free-text note (user tag).
  Future<void> setNote(int id, String note) async {
    final idx = _problems.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final old = _problems[idx];
    _problems[idx] = MixProblem(
      id: old.id,
      markedAt: old.markedAt,
      note: note,
      fsmState: old.fsmState,
      bet: old.bet,
      busPeaks: old.busPeaks,
      voices: old.voices,
      spectrumBands: old.spectrumBands,
      alerts: old.alerts,
      audioClipPath: old.audioClipPath,
      audioClipFrames: old.audioClipFrames,
      audioClipSampleRate: old.audioClipSampleRate,
    );
    notifyListeners();
    await _persistAsync();
  }

  /// Remove one problem by id. Also deletes its audio clip file, if any.
  Future<void> remove(int id) async {
    final idx = _problems.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      await _deleteClipFile(_problems[idx].audioClipPath);
    }
    _problems.removeWhere((p) => p.id == id);
    notifyListeners();
    await _persistAsync();
  }

  /// Remove everything (after user has reviewed / addressed them all).
  /// Also deletes all captured audio clip files.
  Future<void> clearAll() async {
    if (_problems.isEmpty) return;
    for (final p in _problems) {
      await _deleteClipFile(p.audioClipPath);
    }
    _problems.clear();
    notifyListeners();
    await _persistAsync();
  }

  Future<void> _persistAsync() async {
    final file = _storageFile;
    if (file == null) return;
    try {
      final jsonStr = jsonEncode(_problems.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (_) {
      // Write failures are non-fatal.
    }
  }
}

class _CapturedClip {
  final String path;
  final int frames;
  final int sampleRate;
  const _CapturedClip({
    required this.path,
    required this.frames,
    required this.sampleRate,
  });
}
