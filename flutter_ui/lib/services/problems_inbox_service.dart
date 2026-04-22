/// PHASE 10e — Problems Inbox service
///
/// Captures snapshots of the live mix when the user hits "Mark Problem"
/// on the Live Play orb, persists them locally, and exposes the list to
/// a review panel later.
///
/// Storage: flat JSON array at
///   <app support>/FluxForge Studio/problems_inbox.json
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

    final problem = MixProblem(
      id: DateTime.now().millisecondsSinceEpoch,
      markedAt: DateTime.now(),
      note: note,
      fsmState: fsmState,
      bet: bet,
      busPeaks: busPeaks,
      voices: voiceData,
      spectrumBands: snapshot.spectrumBands.toList(growable: false),
      alerts: alerts,
    );

    _problems.insert(0, problem);
    while (_problems.length > maxEntries) {
      _problems.removeLast();
    }
    notifyListeners();
    await _persistAsync();
    return problem;
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
    );
    notifyListeners();
    await _persistAsync();
  }

  /// Remove one problem by id.
  Future<void> remove(int id) async {
    _problems.removeWhere((p) => p.id == id);
    notifyListeners();
    await _persistAsync();
  }

  /// Remove everything (after user has reviewed / addressed them all).
  Future<void> clearAll() async {
    if (_problems.isEmpty) return;
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
