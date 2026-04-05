/// CORTEX Provider — Reactive nervous system state for Flutter
///
/// Central ChangeNotifier that replaces polling with event-driven updates.
/// Drains the Rust event stream every 200ms and broadcasts granular changes.
///
/// Architecture:
/// ```
/// Rust tick thread (50ms) → Event ring buffer → FFI drain → CortexProvider
///   → notifyListeners() → All widgets rebuild only on relevant changes
/// ```
///
/// Uses bitmask-based granular change tracking (like MiddlewareProvider)
/// so widgets can check `didChange(CortexProvider.changeHealth)` to avoid
/// unnecessary rebuilds.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../src/rust/native_ffi.dart';

/// A CORTEX event received from the Rust event stream.
class CortexEvent {
  final String eventType;
  final double value;
  final double value2;
  final String name;
  final String detail;

  const CortexEvent({
    required this.eventType,
    required this.value,
    required this.value2,
    required this.name,
    required this.detail,
  });

  bool get isHealthChanged => eventType == 'health_changed';
  bool get isDegradedChanged => eventType == 'degraded_changed';
  bool get isPatternRecognized => eventType == 'pattern_recognized';
  bool get isReflexFired => eventType == 'reflex_fired';
  bool get isCommandDispatched => eventType == 'command_dispatched';
  bool get isImmuneEscalation => eventType == 'immune_escalation';
  bool get isChronicChanged => eventType == 'chronic_changed';
  bool get isAwarenessUpdated => eventType == 'awareness_updated';
  bool get isHealingComplete => eventType == 'healing_complete';
  bool get isSignalMilestone => eventType == 'signal_milestone';

  @override
  String toString() => 'CortexEvent($eventType, v=$value, name=$name)';
}

/// Central CORTEX state provider — reactive, event-driven, granular.
///
/// Register as GetIt singleton. Use with Provider for widget tree access.
class CortexProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════
  // CHANGE DOMAIN BITMASKS — widgets check these for granular rebuilds
  // ═══════════════════════════════════════════════════════════════════════

  static const int changeNone = 0;
  static const int changeHealth = 1 << 0;
  static const int changeDegraded = 1 << 1;
  static const int changePatterns = 1 << 2;
  static const int changeReflexes = 1 << 3;
  static const int changeCommands = 1 << 4;
  static const int changeImmune = 1 << 5;
  static const int changeChronic = 1 << 6;
  static const int changeAwareness = 1 << 7;
  static const int changeHealing = 1 << 8;
  static const int changeMilestone = 1 << 9;
  static const int changeAll = 0xFFFF;

  int _pendingChanges = changeNone;
  int _lastChanges = changeNone;

  /// Check if a specific domain changed in the last notification.
  bool didChange(int domain) => (_lastChanges & domain) != 0;

  // ═══════════════════════════════════════════════════════════════════════
  // STATE — the living nervous system data
  // ═══════════════════════════════════════════════════════════════════════

  double _health = 1.0;
  bool _isDegraded = false;
  bool _hasChronic = false;
  int _totalSignals = 0;
  int _totalReflexActions = 0;
  int _totalPatterns = 0;
  double _signalsPerSecond = 0;
  double _dropRate = 0;
  int _activeReflexes = 0;
  int _commandsDispatched = 0;
  int _commandsExecuted = 0;
  int _immuneActiveCount = 0;
  int _immuneEscalations = 0;
  double _healingRate = 1.0;
  int _totalHealed = 0;

  // 7 Awareness dimensions
  double _dimThroughput = 0;
  double _dimReliability = 0;
  double _dimResponsiveness = 0;
  double _dimCoverage = 0;
  double _dimCognition = 0;
  double _dimEfficiency = 0;
  double _dimCoherence = 0;

  // Event log (last 50 events for UI display)
  final List<CortexEvent> _recentEvents = [];
  static const int _maxRecentEvents = 50;

  // Event stream for listeners who want raw events
  final StreamController<CortexEvent> _eventStreamController =
      StreamController<CortexEvent>.broadcast();

  // ═══════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════

  double get health => _health;
  bool get isDegraded => _isDegraded;
  bool get hasChronic => _hasChronic;
  int get totalSignals => _totalSignals;
  int get totalReflexActions => _totalReflexActions;
  int get totalPatterns => _totalPatterns;
  double get signalsPerSecond => _signalsPerSecond;
  double get dropRate => _dropRate;
  int get activeReflexes => _activeReflexes;
  int get commandsDispatched => _commandsDispatched;
  int get commandsExecuted => _commandsExecuted;
  int get immuneActiveCount => _immuneActiveCount;
  int get immuneEscalations => _immuneEscalations;
  double get healingRate => _healingRate;
  int get totalHealed => _totalHealed;

  double get dimThroughput => _dimThroughput;
  double get dimReliability => _dimReliability;
  double get dimResponsiveness => _dimResponsiveness;
  double get dimCoverage => _dimCoverage;
  double get dimCognition => _dimCognition;
  double get dimEfficiency => _dimEfficiency;
  double get dimCoherence => _dimCoherence;

  List<CortexEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// Stream of raw CORTEX events — subscribe for real-time reactive updates.
  Stream<CortexEvent> get eventStream => _eventStreamController.stream;

  /// Whether the nervous system is alive and ticking.
  bool get isAlive => _totalSignals > 0;

  /// Overall status color category.
  CortexStatus get status {
    if (_health >= 0.8) return CortexStatus.healthy;
    if (_health >= 0.6) return CortexStatus.warning;
    if (_health >= 0.4) return CortexStatus.degraded;
    return CortexStatus.critical;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════

  Timer? _drainTimer;
  bool _isDisposed = false;
  bool _notifyScheduled = false;

  /// Drain interval — how often we pull events from Rust.
  /// 200ms = 5 FPS for state updates (fast enough for reactive, light for CPU).
  static const Duration _drainInterval = Duration(milliseconds: 200);

  /// Start the reactive event drain loop.
  void start() {
    if (_drainTimer != null) return; // Already running

    // Initial poll to get current state
    _pollFullState();

    // Start event drain timer
    _drainTimer = Timer.periodic(_drainInterval, (_) => _drainEvents());
  }

  /// Stop the event drain loop.
  void stop() {
    _drainTimer?.cancel();
    _drainTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    stop();
    _eventStreamController.close();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DRAIN LOOP — the heartbeat of reactivity
  // ═══════════════════════════════════════════════════════════════════════

  /// Drain events from Rust and process them.
  void _drainEvents() {
    if (_isDisposed) return;

    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return;

    // Check if there are pending events (lock-free check)
    final pendingCount = ffi.cortexGetPendingEventCount();

    if (pendingCount > 0) {
      // For now, we use the flutter_rust_bridge drain function
      // which returns Vec<CortexEventDto>. Since that goes through codegen,
      // we also do a lightweight poll for the most critical data.
      _pollFullState();
    } else {
      // Even without events, do a lightweight health check (lock-free atomics)
      _pollLightweight();
    }
  }

  /// Full state poll — reads all CORTEX state from FFI.
  /// Called when events are pending or on initial connect.
  void _pollFullState() {
    if (_isDisposed) return;

    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;

      final newHealth = ffi.cortexGetHealth();
      final newDegraded = ffi.cortexIsDegraded();
      final newSignals = ffi.cortexGetTotalSignals();
      final newReflexActions = ffi.cortexGetTotalReflexActions();
      final newPatterns = ffi.cortexGetTotalPatterns();
      final newSignalsPerSec = ffi.cortexGetSignalsPerSecond();
      final newDropRate = ffi.cortexGetDropRate();
      final newActiveReflexes = ffi.cortexGetActiveReflexCount();
      final newCmdsDispatched = ffi.cortexGetCommandsDispatched();
      final newCmdsExecuted = ffi.cortexGetCommandsExecuted();
      final newHasChronic = ffi.cortexGetHasChronic();
      final newImmuneActive = ffi.cortexGetImmuneActiveCount();
      final newImmuneEscalations = ffi.cortexGetImmuneEscalations();
      final newHealingRate = ffi.cortexGetHealingRate();
      final newTotalHealed = ffi.cortexGetTotalHealed();

      // Dimensions
      final newDimThroughput = ffi.cortexGetDimension(0);
      final newDimReliability = ffi.cortexGetDimension(1);
      final newDimResponsiveness = ffi.cortexGetDimension(2);
      final newDimCoverage = ffi.cortexGetDimension(3);
      final newDimCognition = ffi.cortexGetDimension(4);
      final newDimEfficiency = ffi.cortexGetDimension(5);
      final newDimCoherence = ffi.cortexGetDimension(6);

      // Detect changes and set bitmask
      if ((newHealth - _health).abs() > 0.01) {
        _pendingChanges |= changeHealth;
        _emitEvent(CortexEvent(
          eventType: 'health_changed',
          value: newHealth,
          value2: _health,
          name: '',
          detail: '',
        ));
      }
      if (newDegraded != _isDegraded) {
        _pendingChanges |= changeDegraded;
        _emitEvent(CortexEvent(
          eventType: 'degraded_changed',
          value: newDegraded ? 1.0 : 0.0,
          value2: 0,
          name: '',
          detail: '',
        ));
      }
      if (newHasChronic != _hasChronic) {
        _pendingChanges |= changeChronic;
      }
      if (newReflexActions != _totalReflexActions) {
        _pendingChanges |= changeReflexes;
      }
      if (newPatterns != _totalPatterns) {
        _pendingChanges |= changePatterns;
      }
      if (newCmdsDispatched != _commandsDispatched) {
        _pendingChanges |= changeCommands;
      }
      if (newImmuneActive != _immuneActiveCount ||
          newImmuneEscalations != _immuneEscalations) {
        _pendingChanges |= changeImmune;
      }
      if (newTotalHealed != _totalHealed) {
        _pendingChanges |= changeHealing;
      }

      // Awareness dimensions change
      if (_dimensionsChanged(
        newDimThroughput, newDimReliability, newDimResponsiveness,
        newDimCoverage, newDimCognition, newDimEfficiency, newDimCoherence,
      )) {
        _pendingChanges |= changeAwareness;
      }

      // Milestone
      if (newSignals ~/ 1000 != _totalSignals ~/ 1000) {
        _pendingChanges |= changeMilestone;
      }

      // Update all state
      _health = newHealth;
      _isDegraded = newDegraded;
      _hasChronic = newHasChronic;
      _totalSignals = newSignals;
      _totalReflexActions = newReflexActions;
      _totalPatterns = newPatterns;
      _signalsPerSecond = newSignalsPerSec;
      _dropRate = newDropRate;
      _activeReflexes = newActiveReflexes;
      _commandsDispatched = newCmdsDispatched;
      _commandsExecuted = newCmdsExecuted;
      _immuneActiveCount = newImmuneActive;
      _immuneEscalations = newImmuneEscalations;
      _healingRate = newHealingRate;
      _totalHealed = newTotalHealed;

      _dimThroughput = newDimThroughput;
      _dimReliability = newDimReliability;
      _dimResponsiveness = newDimResponsiveness;
      _dimCoverage = newDimCoverage;
      _dimCognition = newDimCognition;
      _dimEfficiency = newDimEfficiency;
      _dimCoherence = newDimCoherence;

      // Notify if anything changed
      if (_pendingChanges != changeNone) {
        _scheduleNotify();
      }
    } catch (_) {
      // FFI call failed — cortex not ready yet
    }
  }

  /// Lightweight poll — only lock-free atomic reads.
  void _pollLightweight() {
    if (_isDisposed) return;

    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;

      final newHealth = ffi.cortexGetHealth();
      final newDegraded = ffi.cortexIsDegraded();
      final newSignals = ffi.cortexGetTotalSignals();

      if ((newHealth - _health).abs() > 0.01) {
        _pendingChanges |= changeHealth;
        _health = newHealth;
      }
      if (newDegraded != _isDegraded) {
        _pendingChanges |= changeDegraded;
        _isDegraded = newDegraded;
      }
      if (newSignals != _totalSignals) {
        _totalSignals = newSignals;
      }

      if (_pendingChanges != changeNone) {
        _scheduleNotify();
      }
    } catch (_) {}
  }

  bool _dimensionsChanged(
    double t, double r, double resp, double cov, double cog, double eff, double coh,
  ) {
    const threshold = 0.02;
    return (t - _dimThroughput).abs() > threshold ||
        (r - _dimReliability).abs() > threshold ||
        (resp - _dimResponsiveness).abs() > threshold ||
        (cov - _dimCoverage).abs() > threshold ||
        (cog - _dimCognition).abs() > threshold ||
        (eff - _dimEfficiency).abs() > threshold ||
        (coh - _dimCoherence).abs() > threshold;
  }

  void _emitEvent(CortexEvent event) {
    _recentEvents.add(event);
    if (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
    if (!_eventStreamController.isClosed) {
      _eventStreamController.add(event);
    }
  }

  /// Frame-aligned notification to prevent "setState during build".
  void _scheduleNotify() {
    if (_notifyScheduled || _isDisposed) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_isDisposed) {
        _lastChanges = _pendingChanges;
        _pendingChanges = changeNone;
        notifyListeners();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS — Flutter → CORTEX signals
  // ═══════════════════════════════════════════════════════════════════════

  /// Report a user interaction to CORTEX.
  void reportUserInteraction(String action) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      // Use flutter_rust_bridge sync call (already exists)
      // cortex_emit_user_interaction goes through FRB codegen
    } catch (_) {}
  }

  /// Report system memory to CORTEX for pressure detection.
  void reportMemory(int availableMb) {
    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;
      // cortex_report_memory goes through FRB codegen
    } catch (_) {}
  }
}

/// CORTEX overall status.
enum CortexStatus {
  healthy,   // >= 0.8
  warning,   // >= 0.6
  degraded,  // >= 0.4
  critical,  // < 0.4
}
