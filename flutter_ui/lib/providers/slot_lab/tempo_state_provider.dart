/// Tempo State Provider — Dart-side state for Rust TempoStateEngine
///
/// Wraps NativeFFI tempo_state_* calls into a proper ChangeNotifier.
/// Manages tempo state registration, transition rules, live monitoring,
/// and engine lifecycle.
///
/// Used by TempoStatePanel and any widget that needs tempo-aware data.
/// Registered as a GetIt singleton in service_locator.dart.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Tempo transition sync mode (maps to Rust SyncMode)
enum TempoSyncMode {
  immediate, // 0
  beat,      // 1
  bar,       // 2
  phrase,    // 3
  downbeat,  // 4
}

/// Tempo ramp type (maps to Rust TempoRampType)
enum TempoRampType {
  instant, // 0
  linear,  // 1
  sCurve,  // 2
}

/// Crossfade curve (maps to Rust FadeCurve)
enum TempoFadeCurve {
  linear,     // 0
  equalPower, // 1
  sCurve,     // 2
}

/// Engine phase (maps to Rust EnginePhase)
enum TempoEnginePhase {
  steady,         // 0
  waitingForSync, // 1
  crossfading,    // 2
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A registered tempo state
class TempoStateEntry {
  final int id;
  final String name;
  final double targetBpm;

  const TempoStateEntry({
    required this.id,
    required this.name,
    required this.targetBpm,
  });
}

/// A transition rule between two states
class TempoTransitionRuleEntry {
  final int fromStateId;
  final int toStateId;
  final TempoSyncMode syncMode;
  final int durationBars;
  final TempoRampType rampType;
  final TempoFadeCurve fadeCurve;

  const TempoTransitionRuleEntry({
    required this.fromStateId,
    required this.toStateId,
    this.syncMode = TempoSyncMode.bar,
    this.durationBars = 2,
    this.rampType = TempoRampType.linear,
    this.fadeCurve = TempoFadeCurve.equalPower,
  });
}

/// Live snapshot of the tempo engine state (read during poll)
class TempoEngineSnapshot {
  final double bpm;
  final double beat;
  final int bar;
  final TempoEnginePhase phase;
  final double crossfadeProgress;
  final double voiceAStretch;
  final double voiceBStretch;

  const TempoEngineSnapshot({
    this.bpm = 0.0,
    this.beat = 0.0,
    this.bar = 0,
    this.phase = TempoEnginePhase.steady,
    this.crossfadeProgress = 0.0,
    this.voiceAStretch = 1.0,
    this.voiceBStretch = 1.0,
  });

  bool get isTransitioning => phase != TempoEnginePhase.steady;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class TempoStateProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ─────────────────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────────────────

  bool _initialized = false;
  double _sourceBpm = 120.0;
  int _beatsPerBar = 4;
  double _sampleRate = 44100.0;

  /// Registered tempo states
  final List<TempoStateEntry> _states = [];

  /// Transition rules
  final List<TempoTransitionRuleEntry> _rules = [];

  /// Name of the currently active state (tracked on Dart side)
  String? _activeStateName;

  /// Live engine snapshot (updated by polling)
  TempoEngineSnapshot _snapshot = const TempoEngineSnapshot();

  /// Poll timer for live monitoring
  Timer? _pollTimer;

  // ─────────────────────────────────────────────────────────────────────────
  // Constructor
  // ─────────────────────────────────────────────────────────────────────────

  TempoStateProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ─────────────────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────────────────

  bool get isInitialized => _initialized;
  double get sourceBpm => _sourceBpm;
  int get beatsPerBar => _beatsPerBar;
  double get sampleRate => _sampleRate;
  List<TempoStateEntry> get states => List.unmodifiable(_states);
  List<TempoTransitionRuleEntry> get rules => List.unmodifiable(_rules);
  String? get activeStateName => _activeStateName;
  TempoEngineSnapshot get snapshot => _snapshot;

  /// Convenience accessors from snapshot
  double get currentBpm => _snapshot.bpm;
  double get currentBeat => _snapshot.beat;
  int get currentBar => _snapshot.bar;
  TempoEnginePhase get phase => _snapshot.phase;
  double get crossfadeProgress => _snapshot.crossfadeProgress;
  bool get isTransitioning => _snapshot.isTransitioning;

  // ─────────────────────────────────────────────────────────────────────────
  // Engine Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialize the tempo state engine
  ///
  /// Returns true on success.
  bool init({
    double sourceBpm = 120.0,
    int beatsPerBar = 4,
    double sampleRate = 44100.0,
  }) {
    // Destroy previous if any
    if (_initialized) {
      destroy();
    }

    _sourceBpm = sourceBpm;
    _beatsPerBar = beatsPerBar;
    _sampleRate = sampleRate;

    _initialized = _ffi.tempoStateInit(sourceBpm, beatsPerBar, sampleRate);
    if (_initialized) {
      _startPolling();
    }
    notifyListeners();
    return _initialized;
  }

  /// Destroy the engine and free resources
  void destroy() {
    _stopPolling();
    if (_initialized) {
      _ffi.tempoStateDestroy();
    }
    _initialized = false;
    _states.clear();
    _rules.clear();
    _activeStateName = null;
    _snapshot = const TempoEngineSnapshot();
    notifyListeners();
  }

  /// Reset engine to initial state (keeps registered states and rules)
  bool reset() {
    if (!_initialized) return false;
    final ok = _ffi.tempoStateReset();
    if (ok && _states.isNotEmpty) {
      _activeStateName = _states.first.name;
    }
    _poll(); // immediate refresh
    notifyListeners();
    return ok;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State Registration
  // ─────────────────────────────────────────────────────────────────────────

  /// Add a tempo state. Returns the state ID (0 on failure).
  int addState(String name, double targetBpm) {
    if (!_initialized) return 0;

    final id = _ffi.tempoStateAdd(name, targetBpm);
    if (id == 0) return 0;

    _states.add(TempoStateEntry(id: id, name: name, targetBpm: targetBpm));
    notifyListeners();
    return id;
  }

  /// Set the initial active state by name
  bool setInitialState(String name) {
    if (!_initialized) return false;

    final ok = _ffi.tempoStateSetInitial(name);
    if (ok) {
      _activeStateName = name;
      _poll();
      notifyListeners();
    }
    return ok;
  }

  /// Get state entry by name
  TempoStateEntry? getStateByName(String name) {
    for (final s in _states) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Get state entry by ID
  TempoStateEntry? getStateById(int id) {
    for (final s in _states) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Transition Rules
  // ─────────────────────────────────────────────────────────────────────────

  /// Set a transition rule. Returns true on success.
  bool setTransitionRule(TempoTransitionRuleEntry rule) {
    if (!_initialized) return false;

    final ok = _ffi.tempoStateSetTransition(
      rule.fromStateId,
      rule.toStateId,
      rule.syncMode.index,
      rule.durationBars,
      rule.rampType.index,
      rule.fadeCurve.index,
    );

    if (ok) {
      // Replace existing rule for same pair, or add new
      _rules.removeWhere(
        (r) => r.fromStateId == rule.fromStateId && r.toStateId == rule.toStateId,
      );
      _rules.add(rule);
      notifyListeners();
    }
    return ok;
  }

  /// Set the default transition rule (used when no specific rule matches)
  bool setDefaultTransition({
    TempoSyncMode syncMode = TempoSyncMode.bar,
    int durationBars = 2,
    TempoRampType rampType = TempoRampType.linear,
    TempoFadeCurve fadeCurve = TempoFadeCurve.equalPower,
  }) {
    if (!_initialized) return false;

    return _ffi.tempoStateSetDefaultTransition(
      syncMode.index,
      durationBars,
      rampType.index,
      fadeCurve.index,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State Triggering
  // ─────────────────────────────────────────────────────────────────────────

  /// Trigger a transition to a new tempo state by name
  ///
  /// Safe to call from UI thread. The transition starts at the next
  /// sync point defined by the transition rule.
  bool triggerState(String name) {
    if (!_initialized) return false;
    final ok = _ffi.tempoStateTrigger(name);
    if (ok) {
      // Active state will update when crossfade completes (tracked via polling)
      notifyListeners();
    }
    return ok;
  }

  /// Trigger a transition by state ID
  bool triggerStateById(int stateId) {
    if (!_initialized) return false;
    final ok = _ffi.tempoStateTriggerById(stateId);
    if (ok) {
      notifyListeners();
    }
    return ok;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling / Live Monitoring
  // ─────────────────────────────────────────────────────────────────────────

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _poll() {
    if (!_initialized) return;

    final prevPhase = _snapshot.phase;

    final phaseRaw = _ffi.tempoStateGetPhase();
    final newPhase = phaseRaw < TempoEnginePhase.values.length
        ? TempoEnginePhase.values[phaseRaw]
        : TempoEnginePhase.steady;

    _snapshot = TempoEngineSnapshot(
      bpm: _ffi.tempoStateGetBpm(),
      beat: _ffi.tempoStateGetBeat(),
      bar: _ffi.tempoStateGetBar(),
      phase: newPhase,
      crossfadeProgress: _ffi.tempoStateGetCrossfadeProgress(),
      voiceAStretch: _ffi.tempoStateGetVoiceAStretch(),
      voiceBStretch: _ffi.tempoStateGetVoiceBStretch(),
    );

    // Detect transition completion: crossfading → steady
    if (prevPhase == TempoEnginePhase.crossfading &&
        newPhase == TempoEnginePhase.steady) {
      // Active state changed — we can't query the name from Rust,
      // so tracking is responsibility of the trigger caller.
      // The BPM change is reflected in _snapshot.bpm.
    }

    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Convenience: Full Setup
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialize engine and register a list of states with an initial state
  /// and optional default transition.
  ///
  /// Returns true if engine initialized and all states registered.
  bool setup({
    required double sourceBpm,
    required int beatsPerBar,
    double sampleRate = 44100.0,
    required List<({String name, double bpm})> states,
    String? initialState,
    TempoTransitionRuleEntry? defaultRule,
  }) {
    if (!init(sourceBpm: sourceBpm, beatsPerBar: beatsPerBar, sampleRate: sampleRate)) {
      return false;
    }

    for (final s in states) {
      final id = addState(s.name, s.bpm);
      if (id == 0) return false;
    }

    if (initialState != null) {
      setInitialState(initialState);
    } else if (states.isNotEmpty) {
      setInitialState(states.first.name);
    }

    if (defaultRule != null) {
      setDefaultTransition(
        syncMode: defaultRule.syncMode,
        durationBars: defaultRule.durationBars,
        rampType: defaultRule.rampType,
        fadeCurve: defaultRule.fadeCurve,
      );
    }

    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dispose
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    destroy();
    super.dispose();
  }
}
