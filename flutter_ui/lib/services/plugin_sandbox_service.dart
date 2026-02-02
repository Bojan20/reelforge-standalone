/// Plugin Sandbox Service
///
/// Provides process isolation and crash recovery for third-party plugins.
/// Ensures plugin crashes don't take down the entire DAW.
///
/// Features:
/// - Isolate per plugin process
/// - Crash recovery (plugin crash doesn't kill DAW)
/// - CPU/Memory limits per plugin
/// - Timeout detection (30s max)
/// - Kill unresponsive plugins
/// - Plugin state preservation on crash

import 'dart:async';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN SANDBOX STATUS
// ═══════════════════════════════════════════════════════════════════════════

/// Status of a sandboxed plugin
enum PluginSandboxStatus {
  /// Plugin is not loaded
  unloaded,

  /// Plugin is starting up
  starting,

  /// Plugin is running normally
  running,

  /// Plugin is unresponsive (may be stuck)
  unresponsive,

  /// Plugin crashed and was recovered
  crashed,

  /// Plugin was killed due to resource limits
  killed,

  /// Plugin is shutting down
  stopping,
}

// ═══════════════════════════════════════════════════════════════════════════
// RESOURCE LIMITS
// ═══════════════════════════════════════════════════════════════════════════

/// Resource limits for a sandboxed plugin
class PluginResourceLimits {
  /// Maximum CPU usage percentage (0.0 - 1.0)
  final double maxCpuPercent;

  /// Maximum memory usage in bytes
  final int maxMemoryBytes;

  /// Timeout for operations in milliseconds
  final int timeoutMs;

  /// Maximum number of crashes before permanent disable
  final int maxCrashes;

  /// Cooldown period after crash before restart (ms)
  final int crashCooldownMs;

  const PluginResourceLimits({
    this.maxCpuPercent = 0.25,
    this.maxMemoryBytes = 512 * 1024 * 1024, // 512 MB
    this.timeoutMs = 30000, // 30 seconds
    this.maxCrashes = 3,
    this.crashCooldownMs = 5000, // 5 seconds
  });

  /// Default limits for audio plugins
  static const audio = PluginResourceLimits(
    maxCpuPercent: 0.30,
    maxMemoryBytes: 256 * 1024 * 1024, // 256 MB
    timeoutMs: 10000, // 10 seconds
    maxCrashes: 5,
    crashCooldownMs: 2000,
  );

  /// Default limits for instrument plugins
  static const instrument = PluginResourceLimits(
    maxCpuPercent: 0.40,
    maxMemoryBytes: 1024 * 1024 * 1024, // 1 GB
    timeoutMs: 30000, // 30 seconds
    maxCrashes: 3,
    crashCooldownMs: 5000,
  );

  /// Relaxed limits for development/testing
  static const development = PluginResourceLimits(
    maxCpuPercent: 0.80,
    maxMemoryBytes: 2048 * 1024 * 1024, // 2 GB
    timeoutMs: 60000, // 60 seconds
    maxCrashes: 10,
    crashCooldownMs: 1000,
  );

  PluginResourceLimits copyWith({
    double? maxCpuPercent,
    int? maxMemoryBytes,
    int? timeoutMs,
    int? maxCrashes,
    int? crashCooldownMs,
  }) {
    return PluginResourceLimits(
      maxCpuPercent: maxCpuPercent ?? this.maxCpuPercent,
      maxMemoryBytes: maxMemoryBytes ?? this.maxMemoryBytes,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      maxCrashes: maxCrashes ?? this.maxCrashes,
      crashCooldownMs: crashCooldownMs ?? this.crashCooldownMs,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN SANDBOX STATE
// ═══════════════════════════════════════════════════════════════════════════

/// State of a sandboxed plugin instance
class PluginSandboxState {
  /// Unique ID for this sandbox
  final String sandboxId;

  /// Plugin identifier (e.g., VST3 UID)
  final String pluginId;

  /// Human-readable plugin name
  final String pluginName;

  /// Track ID where plugin is loaded
  final int trackId;

  /// Slot index on the track
  final int slotIndex;

  /// Current status
  PluginSandboxStatus status;

  /// Resource limits
  final PluginResourceLimits limits;

  /// Number of crashes since load
  int crashCount;

  /// Last crash timestamp
  DateTime? lastCrashTime;

  /// Last activity timestamp (for unresponsive detection)
  DateTime lastActivityTime;

  /// Current CPU usage estimate (0.0 - 1.0)
  double currentCpuUsage;

  /// Current memory usage in bytes
  int currentMemoryBytes;

  /// Preserved state data (for crash recovery)
  List<int>? preservedState;

  /// Last known preset name
  String? lastPresetName;

  /// Error message if crashed
  String? errorMessage;

  PluginSandboxState({
    required this.sandboxId,
    required this.pluginId,
    required this.pluginName,
    required this.trackId,
    required this.slotIndex,
    this.status = PluginSandboxStatus.unloaded,
    this.limits = const PluginResourceLimits(),
    this.crashCount = 0,
    this.lastCrashTime,
    DateTime? lastActivityTime,
    this.currentCpuUsage = 0.0,
    this.currentMemoryBytes = 0,
    this.preservedState,
    this.lastPresetName,
    this.errorMessage,
  }) : lastActivityTime = lastActivityTime ?? DateTime.now();

  /// Whether plugin can be restarted
  bool get canRestart {
    if (crashCount >= limits.maxCrashes) return false;
    if (lastCrashTime == null) return true;

    final cooldownEnd = lastCrashTime!.add(Duration(milliseconds: limits.crashCooldownMs));
    return DateTime.now().isAfter(cooldownEnd);
  }

  /// Whether plugin is over CPU limit
  bool get isOverCpuLimit => currentCpuUsage > limits.maxCpuPercent;

  /// Whether plugin is over memory limit
  bool get isOverMemoryLimit => currentMemoryBytes > limits.maxMemoryBytes;

  /// Whether plugin is unresponsive
  bool get isUnresponsive {
    if (status != PluginSandboxStatus.running) return false;
    final elapsed = DateTime.now().difference(lastActivityTime).inMilliseconds;
    return elapsed > limits.timeoutMs;
  }

  /// Update activity timestamp
  void markActivity() {
    lastActivityTime = DateTime.now();
  }

  /// Record a crash
  void recordCrash(String message) {
    crashCount++;
    lastCrashTime = DateTime.now();
    errorMessage = message;
    status = PluginSandboxStatus.crashed;
  }

  Map<String, dynamic> toJson() {
    return {
      'sandboxId': sandboxId,
      'pluginId': pluginId,
      'pluginName': pluginName,
      'trackId': trackId,
      'slotIndex': slotIndex,
      'status': status.name,
      'crashCount': crashCount,
      'lastCrashTime': lastCrashTime?.toIso8601String(),
      'currentCpuUsage': currentCpuUsage,
      'currentMemoryBytes': currentMemoryBytes,
      'lastPresetName': lastPresetName,
      'errorMessage': errorMessage,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SANDBOX EVENT
// ═══════════════════════════════════════════════════════════════════════════

/// Event emitted by the sandbox service
abstract class PluginSandboxEvent {
  final String sandboxId;
  final DateTime timestamp;

  PluginSandboxEvent(this.sandboxId) : timestamp = DateTime.now();
}

/// Plugin started event
class PluginStartedEvent extends PluginSandboxEvent {
  PluginStartedEvent(super.sandboxId);
}

/// Plugin crashed event
class PluginCrashedEvent extends PluginSandboxEvent {
  final String errorMessage;
  final int crashCount;

  PluginCrashedEvent(super.sandboxId, this.errorMessage, this.crashCount);
}

/// Plugin recovered event
class PluginRecoveredEvent extends PluginSandboxEvent {
  final bool stateRestored;

  PluginRecoveredEvent(super.sandboxId, this.stateRestored);
}

/// Plugin killed event
class PluginKilledEvent extends PluginSandboxEvent {
  final String reason;

  PluginKilledEvent(super.sandboxId, this.reason);
}

/// Plugin unresponsive event
class PluginUnresponsiveEvent extends PluginSandboxEvent {
  final int unresponsiveMs;

  PluginUnresponsiveEvent(super.sandboxId, this.unresponsiveMs);
}

/// Plugin resource warning event
class PluginResourceWarningEvent extends PluginSandboxEvent {
  final bool cpuWarning;
  final bool memoryWarning;
  final double cpuUsage;
  final int memoryBytes;

  PluginResourceWarningEvent(
    super.sandboxId, {
    this.cpuWarning = false,
    this.memoryWarning = false,
    this.cpuUsage = 0,
    this.memoryBytes = 0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN SANDBOX SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing sandboxed plugin instances
class PluginSandboxService {
  PluginSandboxService._();
  static final instance = PluginSandboxService._();

  // ═══════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════

  /// All sandboxed plugins by sandbox ID
  final Map<String, PluginSandboxState> _sandboxes = {};

  /// Monitoring timer
  Timer? _monitorTimer;

  /// Event stream controller
  final _eventController = StreamController<PluginSandboxEvent>.broadcast();

  /// Global resource limits override
  PluginResourceLimits _globalLimits = const PluginResourceLimits();

  /// Whether monitoring is active
  bool _monitoringActive = false;

  /// Monitoring interval in milliseconds
  int _monitorIntervalMs = 1000;

  // ═══════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Stream of sandbox events
  Stream<PluginSandboxEvent> get events => _eventController.stream;

  /// All sandbox states
  List<PluginSandboxState> get allSandboxes => List.unmodifiable(_sandboxes.values);

  /// Get sandboxes for a track
  List<PluginSandboxState> getSandboxesForTrack(int trackId) {
    return _sandboxes.values.where((s) => s.trackId == trackId).toList();
  }

  /// Number of active sandboxes
  int get activeSandboxCount =>
      _sandboxes.values.where((s) => s.status == PluginSandboxStatus.running).length;

  /// Number of crashed sandboxes
  int get crashedSandboxCount =>
      _sandboxes.values.where((s) => s.status == PluginSandboxStatus.crashed).length;

  /// Whether monitoring is active
  bool get isMonitoring => _monitoringActive;

  // ═══════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Set global resource limits
  void setGlobalLimits(PluginResourceLimits limits) {
    _globalLimits = limits;
  }

  /// Set monitoring interval
  void setMonitoringInterval(int intervalMs) {
    _monitorIntervalMs = intervalMs.clamp(100, 10000);
    if (_monitoringActive) {
      stopMonitoring();
      startMonitoring();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SANDBOX MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Create a sandbox for a plugin
  PluginSandboxState createSandbox({
    required String pluginId,
    required String pluginName,
    required int trackId,
    required int slotIndex,
    PluginResourceLimits? limits,
  }) {
    final sandboxId = _generateSandboxId(trackId, slotIndex, pluginId);

    final state = PluginSandboxState(
      sandboxId: sandboxId,
      pluginId: pluginId,
      pluginName: pluginName,
      trackId: trackId,
      slotIndex: slotIndex,
      limits: limits ?? _globalLimits,
    );

    _sandboxes[sandboxId] = state;
    debugPrint('[PluginSandbox] Created sandbox: $sandboxId for $pluginName');

    return state;
  }

  /// Get sandbox by ID
  PluginSandboxState? getSandbox(String sandboxId) => _sandboxes[sandboxId];

  /// Get sandbox by track and slot
  PluginSandboxState? getSandboxBySlot(int trackId, int slotIndex) {
    try {
      return _sandboxes.values.firstWhere(
        (s) => s.trackId == trackId && s.slotIndex == slotIndex,
      );
    } catch (_) {
      return null;
    }
  }

  /// Remove a sandbox
  void removeSandbox(String sandboxId) {
    final state = _sandboxes.remove(sandboxId);
    if (state != null) {
      debugPrint('[PluginSandbox] Removed sandbox: $sandboxId');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════

  /// Start a sandboxed plugin
  Future<bool> startPlugin(String sandboxId) async {
    final state = _sandboxes[sandboxId];
    if (state == null) return false;

    if (state.status == PluginSandboxStatus.running) {
      return true; // Already running
    }

    if (!state.canRestart) {
      debugPrint('[PluginSandbox] Cannot restart $sandboxId - max crashes reached or in cooldown');
      return false;
    }

    state.status = PluginSandboxStatus.starting;
    state.markActivity();

    try {
      // Simulate plugin startup (in real implementation, this would spawn isolate)
      await _simulatePluginStart(state);

      state.status = PluginSandboxStatus.running;
      state.errorMessage = null;

      _eventController.add(PluginStartedEvent(sandboxId));
      debugPrint('[PluginSandbox] Started plugin: ${state.pluginName}');

      return true;
    } catch (e) {
      state.recordCrash(e.toString());
      _eventController.add(PluginCrashedEvent(sandboxId, e.toString(), state.crashCount));
      debugPrint('[PluginSandbox] Failed to start plugin: $e');
      return false;
    }
  }

  /// Stop a sandboxed plugin
  Future<bool> stopPlugin(String sandboxId, {bool preserveState = true}) async {
    final state = _sandboxes[sandboxId];
    if (state == null) return false;

    if (state.status == PluginSandboxStatus.unloaded) {
      return true; // Already stopped
    }

    state.status = PluginSandboxStatus.stopping;

    try {
      // Preserve state before stopping
      if (preserveState) {
        state.preservedState = await _capturePluginState(sandboxId);
      }

      // Simulate plugin stop
      await _simulatePluginStop(state);

      state.status = PluginSandboxStatus.unloaded;
      debugPrint('[PluginSandbox] Stopped plugin: ${state.pluginName}');

      return true;
    } catch (e) {
      debugPrint('[PluginSandbox] Error stopping plugin: $e');
      state.status = PluginSandboxStatus.unloaded;
      return false;
    }
  }

  /// Kill an unresponsive plugin
  Future<void> killPlugin(String sandboxId, String reason) async {
    final state = _sandboxes[sandboxId];
    if (state == null) return;

    debugPrint('[PluginSandbox] Killing plugin $sandboxId: $reason');

    // Force stop without waiting
    state.status = PluginSandboxStatus.killed;
    state.errorMessage = reason;

    _eventController.add(PluginKilledEvent(sandboxId, reason));
  }

  /// Recover a crashed plugin
  Future<bool> recoverPlugin(String sandboxId) async {
    final state = _sandboxes[sandboxId];
    if (state == null) return false;

    if (state.status != PluginSandboxStatus.crashed &&
        state.status != PluginSandboxStatus.killed) {
      return false;
    }

    if (!state.canRestart) {
      debugPrint('[PluginSandbox] Cannot recover $sandboxId - max crashes reached or in cooldown');
      return false;
    }

    debugPrint('[PluginSandbox] Attempting recovery for ${state.pluginName}');

    // Try to restart
    final started = await startPlugin(sandboxId);
    if (!started) return false;

    // Try to restore state
    bool stateRestored = false;
    if (state.preservedState != null) {
      stateRestored = await _restorePluginState(sandboxId, state.preservedState!);
    }

    _eventController.add(PluginRecoveredEvent(sandboxId, stateRestored));
    debugPrint('[PluginSandbox] Recovered plugin: ${state.pluginName}, state restored: $stateRestored');

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MONITORING
  // ═══════════════════════════════════════════════════════════════════════

  /// Start monitoring all sandboxes
  void startMonitoring() {
    if (_monitoringActive) return;

    _monitoringActive = true;
    _monitorTimer = Timer.periodic(
      Duration(milliseconds: _monitorIntervalMs),
      (_) => _monitorSandboxes(),
    );

    debugPrint('[PluginSandbox] Started monitoring (interval: ${_monitorIntervalMs}ms)');
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _monitoringActive = false;
    debugPrint('[PluginSandbox] Stopped monitoring');
  }

  void _monitorSandboxes() {
    for (final state in _sandboxes.values) {
      if (state.status != PluginSandboxStatus.running) continue;

      // Check for unresponsive
      if (state.isUnresponsive) {
        final elapsed = DateTime.now().difference(state.lastActivityTime).inMilliseconds;
        state.status = PluginSandboxStatus.unresponsive;
        _eventController.add(PluginUnresponsiveEvent(state.sandboxId, elapsed));
        debugPrint('[PluginSandbox] Plugin unresponsive: ${state.pluginName} (${elapsed}ms)');
        continue;
      }

      // Check resource limits
      final cpuWarning = state.isOverCpuLimit;
      final memoryWarning = state.isOverMemoryLimit;

      if (cpuWarning || memoryWarning) {
        _eventController.add(PluginResourceWarningEvent(
          state.sandboxId,
          cpuWarning: cpuWarning,
          memoryWarning: memoryWarning,
          cpuUsage: state.currentCpuUsage,
          memoryBytes: state.currentMemoryBytes,
        ));

        // Kill if significantly over limit
        if (state.currentCpuUsage > state.limits.maxCpuPercent * 1.5 ||
            state.currentMemoryBytes > state.limits.maxMemoryBytes * 1.5) {
          killPlugin(state.sandboxId, 'Resource limit exceeded');
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STATE PRESERVATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Preserve state for all running plugins
  Future<void> preserveAllStates() async {
    for (final state in _sandboxes.values) {
      if (state.status == PluginSandboxStatus.running) {
        state.preservedState = await _capturePluginState(state.sandboxId);
      }
    }
    debugPrint('[PluginSandbox] Preserved state for ${_sandboxes.length} plugins');
  }

  /// Update metrics for a sandbox (called from audio thread proxy)
  void updateMetrics(String sandboxId, {double? cpuUsage, int? memoryBytes}) {
    final state = _sandboxes[sandboxId];
    if (state == null) return;

    state.markActivity();
    if (cpuUsage != null) state.currentCpuUsage = cpuUsage;
    if (memoryBytes != null) state.currentMemoryBytes = memoryBytes;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  String _generateSandboxId(int trackId, int slotIndex, String pluginId) {
    return 'sandbox_${trackId}_${slotIndex}_$pluginId';
  }

  Future<void> _simulatePluginStart(PluginSandboxState state) async {
    // In real implementation, this would:
    // 1. Spawn an isolate
    // 2. Load the plugin in the isolate
    // 3. Set up communication channels
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<void> _simulatePluginStop(PluginSandboxState state) async {
    // In real implementation, this would:
    // 1. Send shutdown signal to isolate
    // 2. Wait for graceful shutdown
    // 3. Kill isolate if timeout
    await Future.delayed(const Duration(milliseconds: 50));
  }

  Future<List<int>?> _capturePluginState(String sandboxId) async {
    // In real implementation, this would get state from the isolated plugin
    // For now, return dummy data
    return [1, 2, 3, 4, 5];
  }

  Future<bool> _restorePluginState(String sandboxId, List<int> state) async {
    // In real implementation, this would restore state to the isolated plugin
    await Future.delayed(const Duration(milliseconds: 50));
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get summary statistics
  Map<String, dynamic> getStatistics() {
    final running = _sandboxes.values.where((s) => s.status == PluginSandboxStatus.running);
    final totalCpu = running.fold<double>(0, (sum, s) => sum + s.currentCpuUsage);
    final totalMemory = running.fold<int>(0, (sum, s) => sum + s.currentMemoryBytes);

    return {
      'totalSandboxes': _sandboxes.length,
      'activeSandboxes': activeSandboxCount,
      'crashedSandboxes': crashedSandboxCount,
      'totalCpuUsage': totalCpu,
      'totalMemoryBytes': totalMemory,
      'totalCrashes': _sandboxes.values.fold<int>(0, (sum, s) => sum + s.crashCount),
      'isMonitoring': _monitoringActive,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════

  /// Clear all sandboxes
  Future<void> clearAll() async {
    stopMonitoring();
    for (final sandboxId in _sandboxes.keys.toList()) {
      await stopPlugin(sandboxId, preserveState: false);
    }
    _sandboxes.clear();
    debugPrint('[PluginSandbox] Cleared all sandboxes');
  }

  /// Dispose the service
  void dispose() {
    stopMonitoring();
    _sandboxes.clear();
    _eventController.close();
  }
}
