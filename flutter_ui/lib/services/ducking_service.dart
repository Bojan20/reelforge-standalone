/// FluxForge Ducking Service
///
/// Automatic volume ducking based on bus activity.
/// When audio plays on source bus, target buses are ducked.
///
/// Example: Win SFX plays → Music ducks by -6dB
///
/// Features:
/// - Attack/release smoothing
/// - Per-rule enable/disable
/// - Curve types (linear, exponential, logarithmic)
library;

import 'dart:async';
import 'dart:math' as math;
import '../models/middleware_models.dart';

/// Service for automatic audio ducking
class DuckingService {
  static final DuckingService _instance = DuckingService._();
  static DuckingService get instance => _instance;

  DuckingService._();

  /// Whether service is initialized
  bool _initialized = false;

  /// Initialize the ducking service
  void init() {
    if (_initialized) return;
    _initialized = true;
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  // Active ducking rules
  final Map<int, DuckingRule> _rules = {};

  // Current duck levels per target bus (0.0 = no duck, 1.0 = full duck)
  final Map<int, double> _currentDuckLevels = {};

  // Active sources (buses currently playing)
  final Set<int> _activeSources = {};

  // Timer for smooth transitions
  Timer? _updateTimer;

  /// Add a ducking rule
  void addRule(DuckingRule rule) {
    _rules[rule.id] = rule;
    _currentDuckLevels.putIfAbsent(rule.targetBusId, () => 0.0);
  }

  /// Remove a ducking rule
  void removeRule(int ruleId) {
    _rules.remove(ruleId);
  }

  /// Update a ducking rule
  void updateRule(DuckingRule rule) {
    _rules[rule.id] = rule;
  }

  /// Get all rules
  List<DuckingRule> get allRules => _rules.values.toList();

  /// Notify that a bus started playing
  void notifyBusActive(int busId) {
    if (_activeSources.contains(busId)) return;

    _activeSources.add(busId);
    _startUpdateLoop();

    // Apply instant duck for relevant rules
    for (final rule in _rules.values) {
      if (rule.enabled && rule.sourceBusId == busId) {
      }
    }
  }

  /// Notify that a bus stopped playing
  void notifyBusInactive(int busId) {
    _activeSources.remove(busId);

    // Check if we need to release any ducks
    for (final rule in _rules.values) {
      if (rule.enabled && rule.sourceBusId == busId) {
      }
    }
  }

  /// Get current duck multiplier for a bus (0.0-1.0, where 1.0 = no ducking)
  double getDuckMultiplier(int busId) {
    final duckLevel = _currentDuckLevels[busId] ?? 0.0;
    if (duckLevel == 0.0) return 1.0;

    // Convert dB reduction to linear multiplier
    // duckLevel * duckAmountDb gives us the current dB reduction
    // We need to find the strongest duck affecting this bus
    double maxDuckDb = 0.0;
    for (final rule in _rules.values) {
      if (rule.enabled && rule.targetBusId == busId && _activeSources.contains(rule.sourceBusId)) {
        if (rule.duckAmountDb < maxDuckDb) {
          maxDuckDb = rule.duckAmountDb;
        }
      }
    }

    if (maxDuckDb >= 0.0) return 1.0;

    // Apply current duck level (smoothed)
    final currentDuckDb = duckLevel * maxDuckDb;
    return _dbToLinear(currentDuckDb);
  }

  /// Convert dB to linear multiplier
  double _dbToLinear(double db) {
    return math.pow(10.0, db / 20.0).toDouble();
  }

  /// Start smooth update loop for attack/release
  void _startUpdateLoop() {
    if (_updateTimer != null) return;

    const updateInterval = Duration(milliseconds: 16); // ~60fps
    _updateTimer = Timer.periodic(updateInterval, (_) => _updateDuckLevels(16.0));
  }

  /// Stop update loop when no ducking is active
  void _stopUpdateLoop() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  /// Update duck levels with attack/release smoothing
  void _updateDuckLevels(double deltaMs) {
    bool anyActive = false;

    for (final rule in _rules.values) {
      if (!rule.enabled) continue;

      final targetBusId = rule.targetBusId;
      final currentLevel = _currentDuckLevels[targetBusId] ?? 0.0;
      final isSourceActive = _activeSources.contains(rule.sourceBusId);

      double targetLevel = isSourceActive ? 1.0 : 0.0;
      double newLevel;

      if (isSourceActive) {
        // Attack - move towards 1.0
        final attackRate = deltaMs / rule.attackMs;
        newLevel = (currentLevel + attackRate).clamp(0.0, 1.0);
        anyActive = true;
      } else {
        // Release - move towards 0.0
        final releaseRate = deltaMs / rule.releaseMs;
        newLevel = (currentLevel - releaseRate).clamp(0.0, 1.0);
        if (newLevel > 0.001) anyActive = true;
      }

      _currentDuckLevels[targetBusId] = newLevel;
    }

    if (!anyActive) {
      _stopUpdateLoop();
    }
  }

  /// Clear all rules and state
  void clear() {
    _stopUpdateLoop();
    _rules.clear();
    _currentDuckLevels.clear();
    _activeSources.clear();
  }

  /// Dispose resources
  void dispose() {
    clear();
  }
}
