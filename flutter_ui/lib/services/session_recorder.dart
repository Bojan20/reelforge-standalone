/// FLUX_MASTER_TODO 3.6.E — Session Recorder + Best Win Detector (MVP).
///
/// Snima N spin-ova zaredom (default 50), čuva po-spin snapshot
/// (`SessionSpinSnapshot`) sa stages + result + win tier + duration.
/// Auto-detektuje "best win moment" preko formule:
///
///     score = winRatio × tierMultiplier × stageDurationMs
///
/// gde je `winRatio` = totalWin/bet (primarna metrika), `tierMultiplier`
/// dolazi iz win-tier classifier-a (LOW=1, WIN_1..5=2..6, BIG=10,
/// MEGA=15, EPIC=25, ULTRA=40), `stageDurationMs` celokupno trajanje
/// stage sequence-a koji daje "drama" (duži presentation = veći peak).
///
/// **Šta MVP NIJE:**
/// - Audio bounce u `MasterRingBuffer` — Rust crate change `expandTo60s()`
///   je future work (3.6.F Marketing Clip Export ga zahteva).  Sad
///   čuvamo samo stage events; audio se može re-render-ovati od
///   stage-ova preko REPLAY mehanizma koji već postoji.
/// - Cross-session export — JSON dump je u-memoriji za sad.
///
/// **API:**
///   - `recordSession(int spinCount)` — async, fire-and-forget
///   - `cancel()` — abort u toku
///   - `recent()` — lista session-a iz aktivnog memorijskog ring-a
///   - `bestWinIn(session)` — vraća snapshot sa highest score
///
/// **Reactivity:**
/// `SessionRecorder` extends ChangeNotifier — UI listening rebuild-uje
/// kad se session lista promeni ili kad pokretanje session-a promeni
/// state (idle / recording / done).
library;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../src/rust/native_ffi.dart' show SlotLabSpinResult, SlotLabStageEvent, SlotLabWinTier;

// ─────────────────────────────────────────────────────────────────────────
// SNAPSHOT MODELS
// ─────────────────────────────────────────────────────────────────────────

/// Single spin snapshot inside a recorded session.
class SessionSpinSnapshot {
  final int sequenceNumber;
  final SlotLabSpinResult result;
  final List<SlotLabStageEvent> stages;
  final DateTime recordedAt;

  const SessionSpinSnapshot({
    required this.sequenceNumber,
    required this.result,
    required this.stages,
    required this.recordedAt,
  });

  /// Highlight score: drama × win × duration.  See Library doc above.
  double get highlightScore {
    final winRatio = result.winRatio;
    final tierMul = _tierMultiplier(result.bigWinTier);
    final durationMs = stages.isEmpty
        ? 0.0
        : stages.last.timestampMs - stages.first.timestampMs;
    // Floor durationMs at 100ms so a single-stage spike doesn't get score 0.
    final durMul = durationMs.clamp(100.0, 8000.0) / 1000.0;
    return winRatio * tierMul * durMul;
  }

  bool get isWin => result.totalWin > 0;
  String get winTierName => result.winTierName;

  static double _tierMultiplier(SlotLabWinTier? tier) {
    return switch (tier) {
      SlotLabWinTier.ultraWin => 40.0,
      SlotLabWinTier.epicWin => 25.0,
      SlotLabWinTier.megaWin => 15.0,
      SlotLabWinTier.bigWin => 10.0,
      SlotLabWinTier.win => 6.0,
      SlotLabWinTier.none || null => 1.0,
    };
  }
}

/// One recorded session — N spin snapshots + metadata.
class RecordedSession {
  final String sessionId;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<SessionSpinSnapshot> snapshots;

  const RecordedSession({
    required this.sessionId,
    required this.startedAt,
    required this.completedAt,
    required this.snapshots,
  });

  int get spinCount => snapshots.length;
  int get winCount => snapshots.where((s) => s.isWin).length;
  double get hitRate => spinCount == 0 ? 0 : winCount / spinCount;
  double get totalWin =>
      snapshots.fold(0.0, (sum, s) => sum + s.result.totalWin);
  double get totalBet =>
      snapshots.fold(0.0, (sum, s) => sum + s.result.bet);
  double get sessionRtp =>
      totalBet > 0 ? totalWin / totalBet * 100.0 : 0.0;

  /// Highest-scoring snapshot — used by Marketing Clip Export (3.6.F).
  SessionSpinSnapshot? get bestWin {
    if (snapshots.isEmpty) return null;
    SessionSpinSnapshot? best;
    double bestScore = double.negativeInfinity;
    for (final s in snapshots) {
      if (!s.isWin) continue;
      if (s.highlightScore > bestScore) {
        bestScore = s.highlightScore;
        best = s;
      }
    }
    return best;
  }

  /// Anticipation density across the session — % spins that fired
  /// `ANTICIPATION_TENSION_*` (mirror 3.6.D heuristic for cross-session
  /// comparison).
  double get anticipationDensity {
    if (snapshots.isEmpty) return 0;
    final n = snapshots.where((s) =>
        s.stages.any((stg) => stg.stageType.toUpperCase().startsWith(
              'ANTICIPATION_',
            ))).length;
    return n / snapshots.length;
  }

  Duration get duration => completedAt.difference(startedAt);
}

// ─────────────────────────────────────────────────────────────────────────
// RECORDER STATE
// ─────────────────────────────────────────────────────────────────────────

enum SessionRecorderState {
  /// Idle — nothing recording, no progress.
  idle,

  /// Currently running spins back-to-back.
  recording,

  /// Just completed; latest session in `_sessions.last`.
  done,

  /// User cancelled mid-session; partial result kept.
  cancelled,

  /// Engine returned null result mid-session; recording aborted with
  /// whatever partial data we got.
  failed,
}

// ─────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────

/// Singleton service.  Listened to via Provider / ListenableBuilder by
/// the future `SessionRecorderPanel` widget.
class SessionRecorder extends ChangeNotifier {
  SessionRecorder._();
  static final SessionRecorder instance = SessionRecorder._();

  /// In-memory session ring buffer — capped to 20 sessions to avoid
  /// runaway memory.  Disk persistence is future work (3.6.F bundles
  /// session data into the marketing clip export).
  static const int _sessionRingCapacity = 20;
  final List<RecordedSession> _sessions = [];

  SessionRecorderState _state = SessionRecorderState.idle;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  bool _cancelRequested = false;

  // ── Public read API ──────────────────────────────────────────────────

  SessionRecorderState get state => _state;
  int get progressCurrent => _progressCurrent;
  int get progressTotal => _progressTotal;
  double get progressFraction =>
      _progressTotal == 0 ? 0 : _progressCurrent / _progressTotal;
  bool get isRecording => _state == SessionRecorderState.recording;

  List<RecordedSession> get sessions => List.unmodifiable(_sessions);
  RecordedSession? get latest => _sessions.isEmpty ? null : _sessions.last;

  // ── Public commands ──────────────────────────────────────────────────

  /// Run [spinCount] spins back-to-back through the live coordinator.
  /// Snapshot per-spin (stages + result), then push the completed
  /// `RecordedSession` into the ring buffer.
  ///
  /// Errors short-circuit the loop (engine returned null) and the
  /// state goes to `failed` with a partial session preserved.
  Future<RecordedSession?> recordSession({int spinCount = 50}) async {
    if (_state == SessionRecorderState.recording) {
      debugPrint('[SessionRecorder] already recording — ignoring start');
      return null;
    }
    if (spinCount <= 0) return null;
    final coord = _resolveCoordinator();
    if (coord == null) {
      debugPrint('[SessionRecorder] no SlotLabCoordinator — aborting');
      _state = SessionRecorderState.failed;
      notifyListeners();
      return null;
    }

    _state = SessionRecorderState.recording;
    _progressCurrent = 0;
    _progressTotal = spinCount;
    _cancelRequested = false;
    notifyListeners();

    final sessionId =
        'session_${DateTime.now().millisecondsSinceEpoch}';
    final startedAt = DateTime.now();
    final snapshots = <SessionSpinSnapshot>[];

    bool failed = false;
    for (int i = 0; i < spinCount; i++) {
      if (_cancelRequested) break;

      SlotLabSpinResult? result;
      try {
        result = await coord.spin();
      } catch (e, st) {
        debugPrint('[SessionRecorder] spin $i threw: $e\n$st');
      }
      if (result == null) {
        debugPrint('[SessionRecorder] spin $i returned null — aborting');
        failed = true;
        break;
      }

      // Pull the just-finalized stage list — coordinator commits stages
      // synchronously inside its onSpinComplete callback (see
      // SlotLabCoordinator._setupCallbacks), so by the time spin()
      // resolves the cache is populated for THIS spin.
      final stages = List<SlotLabStageEvent>.from(coord.stageProvider.lastStages);

      snapshots.add(SessionSpinSnapshot(
        sequenceNumber: i,
        result: result,
        stages: stages,
        recordedAt: DateTime.now(),
      ));

      _progressCurrent = i + 1;
      notifyListeners();

      // Yield to event loop so UI can repaint progress between spins.
      // Without this the whole 50-spin batch runs in a tight loop and
      // the user only sees state flip at the end.
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    final completedAt = DateTime.now();
    final session = RecordedSession(
      sessionId: sessionId,
      startedAt: startedAt,
      completedAt: completedAt,
      snapshots: snapshots,
    );
    _sessions.add(session);
    if (_sessions.length > _sessionRingCapacity) {
      _sessions.removeRange(0, _sessions.length - _sessionRingCapacity);
    }

    _state = failed
        ? SessionRecorderState.failed
        : (_cancelRequested
            ? SessionRecorderState.cancelled
            : SessionRecorderState.done);
    _progressCurrent = snapshots.length;
    _cancelRequested = false;
    notifyListeners();
    return session;
  }

  /// Request cancel — current spin still completes, but the loop exits
  /// before the next one fires.
  void cancel() {
    if (_state != SessionRecorderState.recording) return;
    _cancelRequested = true;
  }

  /// Re-fire the stages from a recorded snapshot through the same path
  /// as the TIMELINE REPLAY quick-action.  Useful for "play this big
  /// win again" UX inside the session list panel.
  void replaySnapshot(SessionSpinSnapshot snap) {
    final coord = _resolveCoordinator();
    if (coord == null) return;
    coord.stageProvider.setStages(
      snap.stages,
      spinId: snap.result.spinId,
      autoPlay: true,
    );
  }

  // ── Internal ─────────────────────────────────────────────────────────

  SlotLabCoordinator? _resolveCoordinator() {
    final sl = GetIt.instance;
    if (!sl.isRegistered<SlotLabCoordinator>()) return null;
    return sl<SlotLabCoordinator>();
  }
}
