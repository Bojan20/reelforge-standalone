/// Session Replay Service
///
/// Records and replays SlotLab sessions with deterministic audio playback.
/// Captures stage events, RNG seeds, and audio parameters for perfect replay.
///
/// Created: 2026-01-30 (P4.9)

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/session_replay_models.dart';
import '../models/stage_models.dart';
import '../src/rust/native_ffi.dart';
import 'event_registry.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SESSION RECORDER
// ═══════════════════════════════════════════════════════════════════════════

/// Records SlotLab sessions for later replay
class SessionRecorder extends ChangeNotifier {
  SessionRecorder._();
  static final instance = SessionRecorder._();

  // Recording state
  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  // Current session data
  String? _sessionId;
  String _gameId = '';
  String _gameName = '';
  DateTime? _startedAt;
  final List<RecordedSpin> _spins = [];
  final List<RecordedAudioEvent> _audioEvents = [];
  SessionConfig _config = const SessionConfig();

  // Current spin tracking
  String? _currentSpinId;
  int _spinIndex = 0;
  double _currentBet = 0.0;
  final List<StageEvent> _currentStageEvents = [];
  final List<SeedSnapshot> _currentSeedSnapshots = [];
  DateTime? _spinStartTime;

  // Audio event tracking
  final Stopwatch _sessionStopwatch = Stopwatch();

  // Getters
  String? get sessionId => _sessionId;
  String get gameId => _gameId;
  int get spinCount => _spins.length;
  bool get isRecording => _state == RecordingState.recording;

  /// Initialize recorder with game info
  void init({
    required String gameId,
    String gameName = '',
    SessionConfig? config,
  }) {
    _gameId = gameId;
    _gameName = gameName;
    _config = config ?? const SessionConfig();
    debugPrint('[SessionRecorder] Initialized for game: $gameId');
  }

  /// Start recording a new session
  void startRecording() {
    if (!_state.canRecord) {
      debugPrint('[SessionRecorder] Cannot start recording in state: $_state');
      return;
    }

    _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _startedAt = DateTime.now();
    _spins.clear();
    _audioEvents.clear();
    _spinIndex = 0;
    _sessionStopwatch.reset();
    _sessionStopwatch.start();

    // Enable seed logging for determinism capture
    try {
      NativeFFI.instance.seedLogEnable(true);
      NativeFFI.instance.seedLogClear();
    } catch (e) {
      debugPrint('[SessionRecorder] Failed to enable seed logging: $e');
    }

    _state = RecordingState.recording;
    notifyListeners();
    debugPrint('[SessionRecorder] Started recording session: $_sessionId');
  }

  /// Pause recording
  void pauseRecording() {
    if (!_state.canPause) return;
    _sessionStopwatch.stop();
    _state = RecordingState.paused;
    notifyListeners();
    debugPrint('[SessionRecorder] Paused recording');
  }

  /// Resume recording
  void resumeRecording() {
    if (!_state.canResume) return;
    _sessionStopwatch.start();
    _state = RecordingState.recording;
    notifyListeners();
    debugPrint('[SessionRecorder] Resumed recording');
  }

  /// Stop recording and finalize session
  RecordedSession? stopRecording() {
    if (!_state.canStop) return null;

    _sessionStopwatch.stop();

    // Disable seed logging
    try {
      NativeFFI.instance.seedLogEnable(false);
    } catch (e) {
      debugPrint('[SessionRecorder] Failed to disable seed logging: $e');
    }

    final session = RecordedSession(
      sessionId: _sessionId ?? 'unknown',
      gameId: _gameId,
      gameName: _gameName,
      startedAt: _startedAt ?? DateTime.now(),
      endedAt: DateTime.now(),
      spins: List.unmodifiable(_spins),
      audioEvents: List.unmodifiable(_audioEvents),
      config: _config,
      statistics: SessionStatistics.compute(_spins, _audioEvents),
    );

    _state = RecordingState.stopped;
    notifyListeners();
    debugPrint(
        '[SessionRecorder] Stopped recording. Total spins: ${_spins.length}');

    return session;
  }

  /// Record start of a spin
  void onSpinStart({
    required String spinId,
    required double betAmount,
  }) {
    if (!isRecording) return;

    _currentSpinId = spinId;
    _currentBet = betAmount;
    _currentStageEvents.clear();
    _currentSeedSnapshots.clear();
    _spinStartTime = DateTime.now();

    debugPrint('[SessionRecorder] Spin started: $spinId, bet: $betAmount');
  }

  /// Record a stage event during spin
  void onStageEvent(StageEvent event) {
    if (!isRecording || _currentSpinId == null) return;
    _currentStageEvents.add(event);
  }

  /// Record end of a spin
  void onSpinEnd({
    required double winAmount,
    List<List<int>>? reelGrid,
    Map<String, dynamic>? metadata,
  }) {
    if (!isRecording || _currentSpinId == null) return;

    // Capture seed snapshots from Rust
    _captureSeedSnapshots();

    final trace = StageTrace(
      traceId: 'trace_${_currentSpinId}',
      gameId: _gameId,
      sessionId: _sessionId,
      spinId: _currentSpinId,
      events: List.from(_currentStageEvents),
      recordedAt: _spinStartTime ?? DateTime.now(),
      timingProfile: _config.timingProfile,
    );

    final spin = RecordedSpin(
      spinId: _currentSpinId!,
      spinIndex: _spinIndex,
      timestamp: _spinStartTime ?? DateTime.now(),
      betAmount: _currentBet,
      winAmount: winAmount,
      reelGrid: reelGrid,
      trace: trace,
      seedSnapshots: List.from(_currentSeedSnapshots),
      metadata: metadata ?? {},
    );

    _spins.add(spin);
    _spinIndex++;

    debugPrint(
        '[SessionRecorder] Spin ended: $_currentSpinId, win: $winAmount, stages: ${_currentStageEvents.length}');

    _currentSpinId = null;
    _currentStageEvents.clear();
    _currentSeedSnapshots.clear();
  }

  /// Record an audio event
  void onAudioEvent({
    required String eventId,
    required String stageName,
    String? audioPath,
    int? voiceId,
    int busId = 0,
    double volume = 1.0,
    double pan = 0.0,
    int latencyUs = 0,
    Map<String, dynamic>? parameters,
  }) {
    if (!isRecording) return;

    final event = RecordedAudioEvent(
      eventId: eventId,
      stageName: stageName,
      timestampMs: _sessionStopwatch.elapsedMilliseconds.toDouble(),
      audioPath: audioPath,
      voiceId: voiceId,
      busId: busId,
      volume: volume,
      pan: pan,
      latencyUs: latencyUs,
      parameters: parameters ?? {},
    );

    _audioEvents.add(event);
  }

  /// Capture RNG seed snapshots from Rust engine
  void _captureSeedSnapshots() {
    try {
      final entries = NativeFFI.instance.seedLogGetAll();
      for (final entry in entries) {
        _currentSeedSnapshots.add(SeedSnapshot(
          tick: entry.tick,
          containerId: entry.containerId,
          seedBefore: entry.seedBefore,
          seedAfter: entry.seedAfter,
          selectedChildId: entry.selectedId,
          pitchOffset: entry.pitchOffset,
          volumeOffset: entry.volumeOffset,
        ));
      }
      // Clear log for next spin
      NativeFFI.instance.seedLogClear();
    } catch (e) {
      debugPrint('[SessionRecorder] Failed to capture seed snapshots: $e');
    }
  }

  /// Reset recorder to initial state
  void reset() {
    _state = RecordingState.idle;
    _sessionId = null;
    _startedAt = null;
    _spins.clear();
    _audioEvents.clear();
    _currentSpinId = null;
    _currentStageEvents.clear();
    _currentSeedSnapshots.clear();
    _spinIndex = 0;
    _sessionStopwatch.reset();
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SESSION REPLAY ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Replays recorded sessions with deterministic audio
class SessionReplayEngine extends ChangeNotifier {
  SessionReplayEngine._();
  static final instance = SessionReplayEngine._();

  // Replay state
  ReplayState _state = ReplayState.idle;
  ReplayState get state => _state;

  // Loaded session
  RecordedSession? _session;
  RecordedSession? get session => _session;

  // Playback position
  ReplayPosition _position = const ReplayPosition();
  ReplayPosition get position => _position;

  // Playback speed
  ReplaySpeed _speed = ReplaySpeed.normal;
  ReplaySpeed get speed => _speed;

  // Playback timer
  Timer? _playbackTimer;
  final Stopwatch _playbackStopwatch = Stopwatch();

  // Event registry for audio playback
  EventRegistry? _eventRegistry;

  // Callbacks
  void Function(RecordedSpin spin)? onSpinStart;
  void Function(RecordedSpin spin)? onSpinEnd;
  void Function(StageEvent event)? onStageEvent;

  // Getters
  bool get isPlaying => _state == ReplayState.playing;
  bool get hasSession => _session != null;
  int get totalSpins => _session?.spinCount ?? 0;
  double get totalDurationMs {
    if (_session == null) return 0.0;
    double total = 0.0;
    for (final spin in _session!.spins) {
      total += spin.trace.durationMs;
    }
    return total;
  }

  /// Set event registry for audio playback
  void setEventRegistry(EventRegistry registry) {
    _eventRegistry = registry;
  }

  /// Load a session for replay
  Future<bool> loadSession(RecordedSession session) async {
    _state = ReplayState.loading;
    notifyListeners();

    try {
      _session = session;
      _position = const ReplayPosition();

      // Restore RNG seeds if deterministic mode was enabled
      if (session.config.deterministicMode) {
        await _restoreInitialSeeds();
      }

      _state = ReplayState.idle;
      notifyListeners();
      debugPrint(
          '[SessionReplay] Loaded session: ${session.sessionId}, spins: ${session.spinCount}');
      return true;
    } catch (e) {
      debugPrint('[SessionReplay] Failed to load session: $e');
      _state = ReplayState.error;
      notifyListeners();
      return false;
    }
  }

  /// Start or resume playback
  void play() {
    if (!_state.canPlay || _session == null) return;

    _state = ReplayState.playing;
    _playbackStopwatch.start();
    _startPlaybackLoop();
    notifyListeners();
    debugPrint('[SessionReplay] Started playback');
  }

  /// Pause playback
  void pause() {
    if (!_state.canPause) return;

    _playbackTimer?.cancel();
    _playbackStopwatch.stop();
    _state = ReplayState.paused;
    notifyListeners();
    debugPrint('[SessionReplay] Paused playback');
  }

  /// Stop playback
  void stop() {
    if (!_state.canStop) return;

    _playbackTimer?.cancel();
    _playbackStopwatch.stop();
    _playbackStopwatch.reset();
    _position = const ReplayPosition();
    _state = ReplayState.stopped;
    notifyListeners();
    debugPrint('[SessionReplay] Stopped playback');
  }

  /// Seek to position
  void seekToSpin(int spinIndex) {
    if (!_state.canSeek || _session == null) return;
    if (spinIndex < 0 || spinIndex >= _session!.spinCount) return;

    final wasPlaying = isPlaying;
    if (wasPlaying) pause();

    _state = ReplayState.seeking;
    notifyListeners();

    _position = ReplayPosition(
      spinIndex: spinIndex,
      stageIndex: 0,
      timeMs: 0.0,
      progress: spinIndex / _session!.spinCount,
    );

    // Restore seeds up to this point for determinism
    _restoreSeedsToSpin(spinIndex);

    _state = wasPlaying ? ReplayState.playing : ReplayState.paused;
    if (wasPlaying) play();
    notifyListeners();
    debugPrint('[SessionReplay] Seeked to spin: $spinIndex');
  }

  /// Set playback speed
  void setSpeed(ReplaySpeed newSpeed) {
    _speed = newSpeed;
    notifyListeners();
    debugPrint('[SessionReplay] Set speed: ${newSpeed.label}');
  }

  /// Unload session
  void unloadSession() {
    stop();
    _session = null;
    _position = const ReplayPosition();
    _state = ReplayState.idle;
    notifyListeners();
  }

  void _startPlaybackLoop() {
    _playbackTimer?.cancel();

    // 60fps playback loop
    const tickInterval = Duration(milliseconds: 16);
    _playbackTimer = Timer.periodic(tickInterval, (_) => _tick());
  }

  void _tick() {
    if (_session == null || !isPlaying) return;

    final spin = _session!.spins.elementAtOrNull(_position.spinIndex);
    if (spin == null) {
      // End of session
      stop();
      return;
    }

    // Advance time based on speed
    final deltaMs = 16.0 * _speed.multiplier;
    final newTimeMs = _position.timeMs + deltaMs;

    // Check for stage events to trigger
    _processStageEvents(spin, _position.timeMs, newTimeMs);

    // Check if spin is complete
    if (newTimeMs >= spin.trace.durationMs) {
      // Move to next spin
      onSpinEnd?.call(spin);

      final nextSpinIndex = _position.spinIndex + 1;
      if (nextSpinIndex >= _session!.spinCount) {
        // End of session
        stop();
        return;
      }

      // Start next spin
      _position = ReplayPosition(
        spinIndex: nextSpinIndex,
        stageIndex: 0,
        timeMs: 0.0,
        progress: nextSpinIndex / _session!.spinCount,
      );

      final nextSpin = _session!.spins[nextSpinIndex];
      _restoreSeedsForSpin(nextSpin);
      onSpinStart?.call(nextSpin);
    } else {
      // Update position within spin
      _position = _position.copyWith(
        timeMs: newTimeMs,
        progress: (_position.spinIndex + (newTimeMs / spin.trace.durationMs)) /
            _session!.spinCount,
      );
    }

    notifyListeners();
  }

  void _processStageEvents(
    RecordedSpin spin,
    double fromMs,
    double toMs,
  ) {
    final events = spin.trace.events;

    for (var i = _position.stageIndex; i < events.length; i++) {
      final event = events[i];
      if (event.timestampMs >= fromMs && event.timestampMs < toMs) {
        // Trigger stage event
        onStageEvent?.call(event);

        // Trigger audio via EventRegistry
        _eventRegistry?.triggerStage(event.stage.typeName);

        _position = _position.copyWith(stageIndex: i + 1);
      } else if (event.timestampMs >= toMs) {
        break;
      }
    }
  }

  Future<void> _restoreInitialSeeds() async {
    if (_session == null || _session!.spins.isEmpty) return;

    final firstSpin = _session!.spins.first;
    _restoreSeedsForSpin(firstSpin);
  }

  void _restoreSeedsToSpin(int spinIndex) {
    if (_session == null) return;

    // Restore all seeds from spin 0 to spinIndex
    for (var i = 0; i <= spinIndex && i < _session!.spins.length; i++) {
      _restoreSeedsForSpin(_session!.spins[i]);
    }
  }

  void _restoreSeedsForSpin(RecordedSpin spin) {
    for (final snapshot in spin.seedSnapshots) {
      try {
        NativeFFI.instance.seedLogReplaySeed(
          snapshot.containerId,
          snapshot.seedBeforeInt,
        );
      } catch (e) {
        debugPrint('[SessionReplay] Failed to restore seed: $e');
      }
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SESSION STORAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Manages session file storage
class SessionStorage {
  SessionStorage._();
  static final instance = SessionStorage._();

  static const String _sessionsDir = 'replay_sessions';
  static const String _extension = '.ffsession';

  Directory? _storageDir;

  /// Initialize storage directory
  Future<void> init() async {
    final basePath = _getBasePath();
    _storageDir = Directory('$basePath/$_sessionsDir');
    if (!await _storageDir!.exists()) {
      await _storageDir!.create(recursive: true);
    }
    debugPrint('[SessionStorage] Initialized at: ${_storageDir!.path}');
  }

  String _getBasePath() {
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Library/Application Support/FluxForge Studio';
    } else if (Platform.isWindows) {
      return '${Platform.environment['APPDATA']}/FluxForge Studio';
    } else {
      return '${Platform.environment['HOME']}/.config/fluxforge-studio';
    }
  }

  String get storagePath => _storageDir?.path ?? _getBasePath();

  /// Save session to file
  Future<String?> saveSession(RecordedSession session) async {
    if (_storageDir == null) await init();

    try {
      final fileName = '${session.sessionId}$_extension';
      final file = File('${_storageDir!.path}/$fileName');
      await file.writeAsString(session.toJsonString(pretty: true));
      debugPrint('[SessionStorage] Saved session: $fileName');
      return file.path;
    } catch (e) {
      debugPrint('[SessionStorage] Failed to save session: $e');
      return null;
    }
  }

  /// Load session from file
  Future<RecordedSession?> loadSession(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[SessionStorage] File not found: $filePath');
        return null;
      }

      final jsonStr = await file.readAsString();
      final session = RecordedSession.fromJsonString(jsonStr);
      debugPrint('[SessionStorage] Loaded session: ${session.sessionId}');
      return session;
    } catch (e) {
      debugPrint('[SessionStorage] Failed to load session: $e');
      return null;
    }
  }

  /// List all saved sessions
  Future<List<SessionSummary>> listSessions() async {
    if (_storageDir == null) await init();

    final summaries = <SessionSummary>[];

    try {
      final files = _storageDir!
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(_extension));

      for (final file in files) {
        try {
          final jsonStr = await file.readAsString();
          final session = RecordedSession.fromJsonString(jsonStr);
          summaries.add(SessionSummary.fromSession(session));
        } catch (e) {
          debugPrint('[SessionStorage] Failed to read ${file.path}: $e');
        }
      }

      // Sort by date, newest first
      summaries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } catch (e) {
      debugPrint('[SessionStorage] Failed to list sessions: $e');
    }

    return summaries;
  }

  /// Delete a session file
  Future<bool> deleteSession(String sessionId) async {
    if (_storageDir == null) await init();

    try {
      final file = File('${_storageDir!.path}/$sessionId$_extension');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[SessionStorage] Deleted session: $sessionId');
        return true;
      }
    } catch (e) {
      debugPrint('[SessionStorage] Failed to delete session: $e');
    }
    return false;
  }

  /// Export session to custom path
  Future<bool> exportSession(RecordedSession session, String path) async {
    try {
      final file = File(path);
      await file.writeAsString(session.toJsonString(pretty: true));
      debugPrint('[SessionStorage] Exported session to: $path');
      return true;
    } catch (e) {
      debugPrint('[SessionStorage] Failed to export session: $e');
      return false;
    }
  }

  /// Import session from custom path
  Future<RecordedSession?> importSession(String path) async {
    return loadSession(path);
  }

  /// Export session to CSV format
  Future<bool> exportSessionToCsv(RecordedSession session, String path) async {
    try {
      final buffer = StringBuffer();

      // Header
      buffer.writeln(
          'spin_index,spin_id,timestamp,bet_amount,win_amount,win_ratio,duration_ms,stage_count,has_feature,has_jackpot');

      // Data rows
      for (final spin in session.spins) {
        buffer.writeln([
          spin.spinIndex,
          _escapeCsv(spin.spinId),
          spin.timestamp.toIso8601String(),
          spin.betAmount,
          spin.winAmount,
          spin.winRatio.toStringAsFixed(2),
          spin.trace.durationMs.toStringAsFixed(1),
          spin.trace.events.length,
          spin.hasFeature ? 1 : 0,
          spin.hasJackpot ? 1 : 0,
        ].join(','));
      }

      final file = File(path);
      await file.writeAsString(buffer.toString());
      debugPrint('[SessionStorage] Exported CSV to: $path');
      return true;
    } catch (e) {
      debugPrint('[SessionStorage] Failed to export CSV: $e');
      return false;
    }
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SESSION VALIDATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Validates session replay determinism
class SessionValidator {
  SessionValidator._();
  static final instance = SessionValidator._();

  /// Validate that replay matches original recording
  ReplayValidationResult validateReplay({
    required RecordedSession original,
    required RecordedSession replay,
  }) {
    final issues = <ReplayValidationIssue>[];
    int matchedStages = 0;
    int totalStages = 0;
    int matchedSeeds = 0;
    int totalSeeds = 0;

    // Check spin count
    if (original.spinCount != replay.spinCount) {
      issues.add(ReplayValidationIssue(
        severity: ReplayValidationSeverity.error,
        message: 'Spin count mismatch',
        expected: original.spinCount.toString(),
        actual: replay.spinCount.toString(),
      ));
    }

    // Validate each spin
    final minSpins =
        original.spinCount < replay.spinCount ? original.spinCount : replay.spinCount;

    for (var i = 0; i < minSpins; i++) {
      final origSpin = original.spins[i];
      final replaySpin = replay.spins[i];

      // Check win amount
      if ((origSpin.winAmount - replaySpin.winAmount).abs() > 0.001) {
        issues.add(ReplayValidationIssue(
          severity: ReplayValidationSeverity.error,
          message: 'Win amount mismatch',
          spinIndex: i,
          expected: origSpin.winAmount.toString(),
          actual: replaySpin.winAmount.toString(),
        ));
      }

      // Check stage events
      final origEvents = origSpin.trace.events;
      final replayEvents = replaySpin.trace.events;
      totalStages += origEvents.length;

      if (origEvents.length != replayEvents.length) {
        issues.add(ReplayValidationIssue(
          severity: ReplayValidationSeverity.warning,
          message: 'Stage event count mismatch',
          spinIndex: i,
          expected: origEvents.length.toString(),
          actual: replayEvents.length.toString(),
        ));
      }

      final minEvents =
          origEvents.length < replayEvents.length ? origEvents.length : replayEvents.length;

      for (var j = 0; j < minEvents; j++) {
        if (origEvents[j].stage.typeName == replayEvents[j].stage.typeName) {
          matchedStages++;
        } else {
          issues.add(ReplayValidationIssue(
            severity: ReplayValidationSeverity.warning,
            message: 'Stage type mismatch',
            spinIndex: i,
            stageIndex: j,
            expected: origEvents[j].stage.typeName,
            actual: replayEvents[j].stage.typeName,
          ));
        }
      }

      // Check seed snapshots
      totalSeeds += origSpin.seedSnapshots.length;
      final minSeeds = origSpin.seedSnapshots.length < replaySpin.seedSnapshots.length
          ? origSpin.seedSnapshots.length
          : replaySpin.seedSnapshots.length;

      for (var k = 0; k < minSeeds; k++) {
        final origSeed = origSpin.seedSnapshots[k];
        final replaySeed = replaySpin.seedSnapshots[k];

        if (origSeed.selectedChildId == replaySeed.selectedChildId) {
          matchedSeeds++;
        } else {
          issues.add(ReplayValidationIssue(
            severity: ReplayValidationSeverity.error,
            message: 'RNG selection mismatch',
            spinIndex: i,
            expected:
                'child ${origSeed.selectedChildId} (seed: ${origSeed.seedBefore})',
            actual:
                'child ${replaySeed.selectedChildId} (seed: ${replaySeed.seedBefore})',
          ));
        }
      }
    }

    final isValid = issues.every((i) => i.severity != ReplayValidationSeverity.error);

    return ReplayValidationResult(
      isValid: isValid,
      issues: issues,
      matchedStages: matchedStages,
      totalStages: totalStages,
      matchedSeeds: matchedSeeds,
      totalSeeds: totalSeeds,
    );
  }
}
