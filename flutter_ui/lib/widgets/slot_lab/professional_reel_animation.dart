/// Professional Reel Animation System
///
/// Industry-standard slot reel animation with:
/// - Phase-based animation (acceleration, spin, deceleration, bounce)
/// - Per-reel precise stop timing for audio sync
/// - Motion blur during high-speed spin
/// - Overshoot + bounce landing (elasticOut curve)
/// - Configurable timing profiles (normal, turbo, studio)
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TIMING CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Timing profile for reel animations
/// MUST match timing.rs values for audio-visual sync!
class ReelTimingProfile {
  /// Time from spin start until first reel stops (ms)
  final int firstReelStopMs;

  /// Interval between subsequent reel stops (ms)
  final int reelStopIntervalMs;

  /// Duration of deceleration phase (ms)
  final int decelerationMs;

  /// Duration of bounce/settle phase (ms)
  final int bounceMs;

  /// Acceleration phase duration (ms)
  final int accelerationMs;

  const ReelTimingProfile({
    required this.firstReelStopMs,
    required this.reelStopIntervalMs,
    this.decelerationMs = 300,
    this.bounceMs = 0,  // No bounce animation by default
    this.accelerationMs = 150,
  });

  /// Normal gameplay timing
  static const normal = ReelTimingProfile(
    firstReelStopMs: 800,
    reelStopIntervalMs: 300,
    decelerationMs: 250,
    bounceMs: 0,  // No bounce animation
    accelerationMs: 100,
  );

  /// Turbo mode - faster but still visible
  static const turbo = ReelTimingProfile(
    firstReelStopMs: 400,
    reelStopIntervalMs: 100,
    decelerationMs: 150,
    bounceMs: 0,  // No bounce animation
    accelerationMs: 80,
  );

  /// Studio mode - optimized for audio testing
  /// CRITICAL: Must match timing.rs studio() values!
  static const studio = ReelTimingProfile(
    firstReelStopMs: 1000,   // Matches timing.rs: reel_spin_duration_ms
    reelStopIntervalMs: 370, // Matches timing.rs: reel_stop_interval_ms
    decelerationMs: 280,
    bounceMs: 0,  // No bounce animation
    accelerationMs: 120,
  );

  /// Calculate stop time for a specific reel
  int getReelStopTime(int reelIndex) {
    return firstReelStopMs + (reelIndex * reelStopIntervalMs);
  }

  /// Calculate total animation duration for all reels
  int getTotalDuration(int reelCount) {
    return getReelStopTime(reelCount - 1) + decelerationMs + bounceMs;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATION PHASES
// ═══════════════════════════════════════════════════════════════════════════════

enum ReelPhase {
  idle,         // Not spinning
  accelerating, // 0 → full speed
  spinning,     // Full speed constant
  decelerating, // Slowing down to target
  bouncing,     // Overshoot + settle
  stopped,      // Final position
}

/// State of a single reel's animation
class ReelAnimationState {
  final int reelIndex;
  final ReelTimingProfile profile;

  ReelPhase phase = ReelPhase.idle;
  double scrollOffset = 0.0;      // Current scroll position (0-1 per symbol)
  double velocity = 0.0;          // Current spin velocity
  double targetSymbolOffset = 0;  // Final symbol position

  // Bounce state
  double bounceProgress = 0.0;
  double overshootAmount = 0.0;

  // Progress tracking
  double phaseProgress = 0.0;     // Progress within current phase (0.0 - 1.0)
  double spinCycles = 0.0;        // Number of full spin cycles during spinning phase

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTICIPATION SYSTEM — Extend spin time dynamically when conditions are met
  // ═══════════════════════════════════════════════════════════════════════════
  int stopTimeExtensionMs = 0;    // Extra time to spin (e.g., 3000ms for anticipation)
  bool isInAnticipation = false;  // Visual indicator for anticipation state

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.2: PER-REEL ANTICIPATION STATE — Industry-standard tension escalation
  // Tension levels L1→L4: Gold→Orange→Red-Orange→Red
  // Each level increases intensity of visual/audio effects
  // ═══════════════════════════════════════════════════════════════════════════
  int tensionLevel = 1;           // 1-4, higher = more intense (L1=Gold, L4=Red)
  String anticipationReason = ''; // 'scatter', 'bonus', 'jackpot', etc.
  double anticipationProgress = 0.0; // 0.0 → 1.0 progress through anticipation phase

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.3: SPEED MULTIPLIER — For anticipation slowdown visual effect
  // ═══════════════════════════════════════════════════════════════════════════
  double speedMultiplier = 1.0;   // 1.0 = normal, 0.3 = slow (30%), 2.0 = fast

  ReelAnimationState(this.reelIndex, this.profile);

  /// Get bounce offset in pixels for visual effect
  double get bounceOffset => overshootAmount * 20.0; // Scale to visible pixels

  /// Get stop time for this reel (base + any extension)
  int get stopTime => profile.getReelStopTime(reelIndex) + stopTimeExtensionMs;

  /// Extend this reel's spin time (for anticipation)
  /// P7.2.2: Now accepts tension level and reason for escalation
  void extendSpinTime(int extensionMs, {int level = 1, String reason = 'scatter'}) {
    stopTimeExtensionMs = extensionMs;
    isInAnticipation = true;
    tensionLevel = level.clamp(1, 4);
    anticipationReason = reason;
    anticipationProgress = 0.0;
  }

  /// Clear anticipation extension
  /// P7.2.2: Reset all anticipation state
  void clearAnticipation() {
    stopTimeExtensionMs = 0;
    isInAnticipation = false;
    tensionLevel = 1;
    anticipationReason = '';
    anticipationProgress = 0.0;
  }

  /// P7.2.2: Update anticipation progress (0.0 → 1.0)
  void updateAnticipationProgress(double progress) {
    anticipationProgress = progress.clamp(0.0, 1.0);
  }

  /// P7.2.2: Set tension level dynamically (for escalation during anticipation)
  void setTensionLevel(int level) {
    tensionLevel = level.clamp(1, 4);
  }

  /// P0.3: Set speed multiplier for anticipation slowdown effect
  void setSpeedMultiplier(double multiplier) {
    speedMultiplier = multiplier.clamp(0.1, 2.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.1: FORCE STOP — Skip remaining spin time and transition to decel/stop
  // Used in sequential anticipation mode after anticipation completes
  // ═══════════════════════════════════════════════════════════════════════════
  bool _forceStopRequested = false;

  /// Force this reel to stop immediately (skips remaining spin time)
  void forceStop() {
    _forceStopRequested = true;
    // Clear any spin time extension
    stopTimeExtensionMs = 0;
    isInAnticipation = false;
    speedMultiplier = 1.0;
  }

  /// Check if force stop was requested
  bool get forceStopRequested => _forceStopRequested;

  /// Clear force stop flag (called when reel actually stops)
  void clearForceStop() {
    _forceStopRequested = false;
  }

  /// Update state based on elapsed time since spin start
  void update(int elapsedMs, List<int> targetSymbols) {
    if (phase == ReelPhase.idle || phase == ReelPhase.stopped) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // P7.2.1: FORCE STOP — Skip to deceleration phase immediately
    // Used in sequential anticipation mode after anticipation completes
    // ═══════════════════════════════════════════════════════════════════════════
    if (_forceStopRequested && phase != ReelPhase.decelerating && phase != ReelPhase.bouncing) {
      _forceStopRequested = false;
      // Jump directly to start of deceleration phase
      phase = ReelPhase.decelerating;
      phaseProgress = 0.0;
      // Continue update with deceleration logic below
    }

    final stopT = stopTime;
    final accelEnd = profile.accelerationMs;
    final decelStart = stopT - profile.decelerationMs;
    final bounceStart = stopT;
    final bounceEnd = stopT + profile.bounceMs;

    // P7.2.1: If force stop triggered, treat as if we're at decelStart
    final effectiveElapsedMs = (_forceStopRequested || phase == ReelPhase.decelerating && phaseProgress < 0.1)
        ? decelStart
        : elapsedMs;

    if (effectiveElapsedMs < accelEnd && phase == ReelPhase.accelerating) {
      // PHASE: Acceleration (0 → max velocity)
      phase = ReelPhase.accelerating;
      phaseProgress = effectiveElapsedMs / accelEnd;
      final t = phaseProgress;
      velocity = _easeOutQuad(t) * 1.0; // Max velocity = 1.0
      scrollOffset += velocity * 0.1 * speedMultiplier; // P0.3: Apply speed multiplier
      spinCycles = scrollOffset / 10.0; // Track spin cycles
    } else if (effectiveElapsedMs < decelStart && phase != ReelPhase.decelerating && phase != ReelPhase.bouncing) {
      // PHASE: Full-speed spinning
      phase = ReelPhase.spinning;
      velocity = 1.0;
      scrollOffset += velocity * 0.1 * speedMultiplier; // P0.3: Apply speed multiplier
      final spinDuration = decelStart - accelEnd;
      phaseProgress = (effectiveElapsedMs - accelEnd) / spinDuration.clamp(1, double.infinity);
      spinCycles = scrollOffset / 10.0; // Track spin cycles for visual effect
    } else if (elapsedMs < bounceStart) {
      // PHASE: Deceleration (max → 0 velocity)
      // NOTE: Removed "|| phase == ReelPhase.decelerating" which caused infinite loop!
      phase = ReelPhase.decelerating;
      phaseProgress = (elapsedMs - decelStart) / (bounceStart - decelStart).clamp(1, double.infinity);
      final t = phaseProgress.clamp(0.0, 1.0);
      velocity = (1.0 - _easeInQuad(t)) * 1.0;
      scrollOffset += velocity * 0.1 * speedMultiplier; // P0.3: Apply speed multiplier

      // Approach target position
      if (t > 0.7) {
        final approach = (t - 0.7) / 0.3;
        scrollOffset = _lerp(scrollOffset, targetSymbolOffset.toDouble(), approach * 0.3);
      }
    } else if (elapsedMs < bounceEnd) {
      // PHASE: Bounce (overshoot + settle)
      phase = ReelPhase.bouncing;
      velocity = 0;

      phaseProgress = (elapsedMs - bounceStart) / (bounceEnd - bounceStart);
      bounceProgress = phaseProgress;

      // Elastic overshoot curve
      // Goes past target by ~15%, then settles back
      final elastic = _elasticOut(phaseProgress);
      overshootAmount = (elastic - 1.0) * 0.15;

      scrollOffset = targetSymbolOffset + overshootAmount;
    } else {
      // PHASE: Stopped
      phase = ReelPhase.stopped;
      velocity = 0;
      scrollOffset = targetSymbolOffset.toDouble();
      overshootAmount = 0;
      bounceProgress = 1.0;
      phaseProgress = 1.0;
    }
  }

  /// Start spinning this reel
  void startSpin(double initialOffset) {
    phase = ReelPhase.accelerating;
    scrollOffset = initialOffset;
    velocity = 0;
    bounceProgress = 0;
    overshootAmount = 0;
    phaseProgress = 0;
    spinCycles = 0;
    // Clear anticipation from previous spin
    stopTimeExtensionMs = 0;
    isInAnticipation = false;
  }

  /// Reset to idle
  void reset() {
    phase = ReelPhase.idle;
    velocity = 0;
    bounceProgress = 0;
    overshootAmount = 0;
    // Clear anticipation
    stopTimeExtensionMs = 0;
    isInAnticipation = false;
  }

  /// Get blur intensity based on current velocity
  double get blurIntensity => velocity.abs() * 0.6;

  /// Get vertical offset for bounce effect (pixels)
  double getBouncePixelOffset(double symbolHeight) {
    return overshootAmount * symbolHeight;
  }

  // Easing functions
  static double _easeOutQuad(double t) => 1 - (1 - t) * (1 - t);
  static double _easeInQuad(double t) => t * t;
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Attempt at elastic out curve for bounce
  static double _elasticOut(double t) {
    if (t == 0 || t == 1) return t;
    const p = 0.3;
    const s = p / 4;
    return math.pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / p) + 1;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REEL ANIMATION CONTROLLER
// ═══════════════════════════════════════════════════════════════════════════════

/// Master controller for professional reel animation
class ProfessionalReelAnimationController extends ChangeNotifier {
  final int reelCount;
  final int rowCount;
  final ReelTimingProfile profile;

  late List<ReelAnimationState> _reelStates;
  List<List<int>> _targetGrid = [];
  List<List<int>> _spinSymbols = [];

  int _startTime = 0;
  bool _isSpinning = false;

  /// Callback when a specific reel stops (for audio sync)
  void Function(int reelIndex)? onReelStop;

  /// Callback when all reels have stopped
  void Function()? onAllReelsStopped;

  final _random = math.Random();

  /// DEBUG: Public access to reel states
  List<ReelAnimationState> get reelStates => _reelStates;

  ProfessionalReelAnimationController({
    required this.reelCount,
    required this.rowCount,
    this.profile = ReelTimingProfile.studio,
  }) {
    _reelStates = List.generate(
      reelCount,
      (i) => ReelAnimationState(i, profile),
    );
    _initializeSymbols();
  }

  void _initializeSymbols() {
    _targetGrid = List.generate(
      reelCount,
      (_) => List.generate(rowCount, (_) => _random.nextInt(10)),
    );
    _spinSymbols = List.generate(
      reelCount,
      (_) => List.generate(30, (_) => _random.nextInt(10)),
    );
  }

  /// Get current state of a reel
  ReelAnimationState getReelState(int index) => _reelStates[index];

  /// Is any reel currently spinning?
  bool get isSpinning => _isSpinning;

  /// Check if all reels have landed (bouncing or stopped)
  bool get allReelsLanded {
    for (final state in _reelStates) {
      if (state.phase != ReelPhase.stopped &&
          state.phase != ReelPhase.idle &&
          state.phase != ReelPhase.bouncing) {
        return false;
      }
    }
    return true;
  }

  /// Get target grid
  List<List<int>> get targetGrid => _targetGrid;

  /// Get spin symbols for visual effect
  List<List<int>> get spinSymbols => _spinSymbols;

  /// Set target grid (from spin result)
  void setTargetGrid(List<List<int>> grid) {
    _targetGrid = grid;
    // Set target offsets for each reel
    for (int i = 0; i < reelCount && i < grid.length; i++) {
      _reelStates[i].targetSymbolOffset = 20.0; // Scroll amount to final position
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTICIPATION SYSTEM — Extend spin time when conditions are met (e.g., 2 scatters)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Extend spin time for a specific reel (for anticipation)
  /// Call this when scatter condition is met (e.g., 2 scatters landed)
  /// P7.2.2: Now accepts tension level and reason
  void extendReelSpinTime(int reelIndex, int extensionMs, {int tensionLevel = 1, String reason = 'scatter'}) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      debugPrint('[ReelAnimController] 🎯 ANTICIPATION: Extending reel $reelIndex spin by ${extensionMs}ms (tension L$tensionLevel, reason: $reason)');
      _reelStates[reelIndex].extendSpinTime(extensionMs, level: tensionLevel, reason: reason);
      notifyListeners();
    }
  }

  /// Check if a reel is in anticipation mode
  bool isReelInAnticipation(int reelIndex) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      return _reelStates[reelIndex].isInAnticipation;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.2: PER-REEL ANTICIPATION STATE ACCESSORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get tension level for a reel (1-4)
  int getReelTensionLevel(int reelIndex) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      return _reelStates[reelIndex].tensionLevel;
    }
    return 1;
  }

  /// Get anticipation reason for a reel
  String getReelAnticipationReason(int reelIndex) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      return _reelStates[reelIndex].anticipationReason;
    }
    return '';
  }

  /// Get anticipation progress for a reel (0.0 → 1.0)
  double getReelAnticipationProgress(int reelIndex) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      return _reelStates[reelIndex].anticipationProgress;
    }
    return 0.0;
  }

  /// Update anticipation progress for a reel
  void updateReelAnticipationProgress(int reelIndex, double progress) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      _reelStates[reelIndex].updateAnticipationProgress(progress);
      notifyListeners();
    }
  }

  /// Set tension level for a reel dynamically
  void setReelTensionLevel(int reelIndex, int level) {
    if (reelIndex >= 0 && reelIndex < reelCount) {
      _reelStates[reelIndex].setTensionLevel(level);
      notifyListeners();
    }
  }

  /// Get all reels currently in anticipation mode
  List<int> getAnticipatingReels() {
    final result = <int>[];
    for (int i = 0; i < reelCount; i++) {
      if (_reelStates[i].isInAnticipation) {
        result.add(i);
      }
    }
    return result;
  }

  /// Clear all anticipation states (called on spin start)
  void clearAllAnticipation() {
    for (final state in _reelStates) {
      state.clearAnticipation();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.3: REEL SPEED MULTIPLIERS — For anticipation slowdown effect
  // ═══════════════════════════════════════════════════════════════════════════

  final Map<int, double> _reelSpeedMultipliers = {};

  /// P0.3: Set speed multiplier for a specific reel (for anticipation slowdown)
  /// multiplier: 1.0 = normal speed, 0.3 = 30% speed (slow), 2.0 = double speed
  void setReelSpeedMultiplier(int reelIndex, double multiplier) {
    final clampedMultiplier = multiplier.clamp(0.1, 2.0);
    _reelSpeedMultipliers[reelIndex] = clampedMultiplier;
    if (reelIndex >= 0 && reelIndex < reelCount) {
      _reelStates[reelIndex].setSpeedMultiplier(clampedMultiplier);
    }
    debugPrint('[ReelAnimController] P0.3: Reel $reelIndex speed = ${(clampedMultiplier * 100).toInt()}%');
    notifyListeners();
  }

  /// P0.3: Get current speed multiplier for a reel
  double getReelSpeedMultiplier(int reelIndex) {
    return _reelSpeedMultipliers[reelIndex] ?? 1.0;
  }

  /// P0.3: Clear all speed multipliers (called on spin start)
  void clearAllSpeedMultipliers() {
    _reelSpeedMultipliers.clear();
    for (final state in _reelStates) {
      state.setSpeedMultiplier(1.0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.1: FORCE STOP REEL — For sequential anticipation mode
  // Forces a specific reel to stop immediately (skips remaining spin time)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Force a specific reel to stop immediately
  /// Used in sequential anticipation mode after anticipation completes
  void forceStopReel(int reelIndex) {
    if (reelIndex < 0 || reelIndex >= reelCount) return;
    if (_reelStates[reelIndex].phase == ReelPhase.stopped) return;

    debugPrint('[ReelAnimController] P7.2.1: FORCE STOP reel $reelIndex');

    // Transition directly to decelerating phase with minimal remaining time
    _reelStates[reelIndex].forceStop();
    notifyListeners();
  }

  /// Start spin animation
  void startSpin() {
    debugPrint('[ReelAnimController] startSpin() called, _isSpinning=$_isSpinning');
    if (_isSpinning) {
      debugPrint('[ReelAnimController] ❌ startSpin BLOCKED: already spinning!');
      return;
    }

    debugPrint('[ReelAnimController] ✅ Starting spin animation');
    _isSpinning = true;
    _startTime = DateTime.now().millisecondsSinceEpoch;

    // Clear any previous anticipation states
    clearAllAnticipation();

    // P0.3: Clear any previous speed multipliers
    clearAllSpeedMultipliers();

    // Regenerate spin symbols
    _spinSymbols = List.generate(
      reelCount,
      (_) => List.generate(30, (_) => _random.nextInt(10)),
    );

    // Start all reels
    for (int i = 0; i < reelCount; i++) {
      _reelStates[i].startSpin(0);
    }

    notifyListeners();
  }

  /// Update animation (call from ticker)
  void tick() {
    if (!_isSpinning) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - _startTime;
    bool anyStillSpinning = false;

    // DEBUG: Log elapsed time and all reel phases periodically
    if (elapsed % 500 < 17) {
      final phases = _reelStates.map((s) => s.phase.name[0].toUpperCase()).join('');
      debugPrint('[tick] elapsed=${elapsed}ms phases=$phases');
    }

    for (int i = 0; i < reelCount; i++) {
      final state = _reelStates[i];
      final previousPhase = state.phase;

      state.update(elapsed, _targetGrid.length > i ? _targetGrid[i] : []);

      // ═══════════════════════════════════════════════════════════════════════════
      // AUDIO SYNC FIX (2026-01-24): Fire onReelStop when entering BOUNCING phase
      // This is the visual "landing" moment — when the reel hits its target position.
      // Previously fired when entering STOPPED (180ms after landing), causing audio lag.
      // The bounce is a visual overshoot effect AFTER landing; audio should play AT landing.
      // ═══════════════════════════════════════════════════════════════════════════
      final wasStillMoving = previousPhase != ReelPhase.bouncing
                          && previousPhase != ReelPhase.stopped
                          && previousPhase != ReelPhase.idle;

      // FIX: Fire callback when reel lands (bouncing OR stopped if bounceMs=0)
      // When bounceMs=0, reel skips bouncing phase and goes directly to stopped
      final reelJustLanded = wasStillMoving &&
          (state.phase == ReelPhase.bouncing || state.phase == ReelPhase.stopped);

      if (reelJustLanded) {
        debugPrint('[ReelAnimController] 🔔 REEL $i → ${state.phase} at ${elapsed}ms (stopTime=${state.stopTime}ms, prev=$previousPhase)');
        onReelStop?.call(i);  // Audio triggers at visual landing
      }

      // ═══════════════════════════════════════════════════════════════════════════
      // FIX (2026-01-31): Include BOUNCING as "landed" state for callback timing
      // BOUNCING is purely visual (overshoot effect AFTER landing) — the reel has
      // already reached its target position, so win evaluation can start.
      // Previously: bouncing was counted as "still spinning", delaying the callback
      // by 200ms and causing win presentation to require manual spin button press.
      // ═══════════════════════════════════════════════════════════════════════════
      final isLanded = state.phase == ReelPhase.stopped ||
                       state.phase == ReelPhase.idle ||
                       state.phase == ReelPhase.bouncing;
      if (!isLanded) {
        anyStillSpinning = true;
      }
    }

    notifyListeners();

    // Check if all reels stopped (after bounce completes)
    if (!anyStillSpinning && _isSpinning) {
      _isSpinning = false;
      onAllReelsStopped?.call();
    }
  }

  /// Stop all reels immediately (for turbo skip / STOP button)
  void stopImmediately() {
    debugPrint('[ReelAnimController] stopImmediately() called, _isSpinning=$_isSpinning');

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: Fire callbacks for each reel that was still spinning
    // This ensures audio plays for all reel stops and win evaluation triggers
    // ═══════════════════════════════════════════════════════════════════════════
    int stillMovingCount = 0;
    for (int i = 0; i < _reelStates.length; i++) {
      final state = _reelStates[i];
      final wasStillMoving = state.phase != ReelPhase.stopped
                          && state.phase != ReelPhase.idle
                          && state.phase != ReelPhase.bouncing;

      state.phase = ReelPhase.stopped;
      state.velocity = 0;

      // Fire callback for reels that were still spinning
      if (wasStillMoving) {
        stillMovingCount++;
        onReelStop?.call(i);
      }
    }

    debugPrint('[ReelAnimController] stopImmediately: $stillMovingCount reels were still moving');
    _isSpinning = false;
    notifyListeners();

    // Fire all-stopped callback
    debugPrint('[ReelAnimController] Firing onAllReelsStopped callback');
    onAllReelsStopped?.call();
  }

  /// Reset to initial state
  void reset() {
    for (final state in _reelStates) {
      state.reset();
    }
    _isSpinning = false;
    _initializeSymbols();
    notifyListeners();
  }

}

// ═══════════════════════════════════════════════════════════════════════════════
// PROFESSIONAL REEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// A single reel with professional animation
class ProfessionalReelWidget extends StatelessWidget {
  final ReelAnimationState state;
  final List<int> spinSymbols;
  final List<int> targetSymbols;
  final int rowCount;
  final double width;
  final double height;
  final Widget Function(int symbolId, bool isWinning) symbolBuilder;
  final Set<int> winningRows;

  const ProfessionalReelWidget({
    super.key,
    required this.state,
    required this.spinSymbols,
    required this.targetSymbols,
    required this.rowCount,
    required this.width,
    required this.height,
    required this.symbolBuilder,
    this.winningRows = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cellHeight = height / rowCount;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            // Symbols
            _buildSymbols(cellHeight),

            // Motion blur overlay
            if (state.blurIntensity > 0.1)
              _buildBlurOverlay(state.blurIntensity),

            // Anticipation glow (if applicable)
            if (state.phase == ReelPhase.spinning || state.phase == ReelPhase.decelerating)
              _buildSpinGlow(),
          ],
        ),
      ),
    );
  }

  Widget _buildSymbols(double cellHeight) {
    final offset = state.scrollOffset;
    final bounceOffset = state.getBouncePixelOffset(cellHeight);

    if (state.phase == ReelPhase.stopped || state.phase == ReelPhase.idle) {
      // Show final symbols
      return Column(
        children: List.generate(rowCount, (row) {
          final symbolId = targetSymbols.length > row ? targetSymbols[row] : 0;
          final isWinning = winningRows.contains(row);
          return SizedBox(
            height: cellHeight,
            child: symbolBuilder(symbolId, isWinning),
          );
        }),
      );
    }

    // Spinning - show scrolling symbols with optional bounce
    return Transform.translate(
      offset: Offset(0, bounceOffset),
      child: Column(
        children: List.generate(rowCount, (row) {
          // Calculate which symbol to show based on scroll offset
          final symbolIndex = (offset.floor() + row) % spinSymbols.length;
          final symbolId = spinSymbols[symbolIndex];
          return SizedBox(
            height: cellHeight,
            child: symbolBuilder(symbolId, false),
          );
        }),
      ),
    );
  }

  Widget _buildBlurOverlay(double intensity) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(intensity * 0.4),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(intensity * 0.4),
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
      ),
    );
  }

  Widget _buildSpinGlow() {
    final glowIntensity = state.velocity * 0.3;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            const Color(0xFF4a9eff).withOpacity(glowIntensity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// USAGE EXAMPLE
// ═══════════════════════════════════════════════════════════════════════════════

/*
Usage in SlotPreviewWidget:

1. Create controller in initState:
   _animController = ProfessionalReelAnimationController(
     reelCount: 5,
     rowCount: 3,
     profile: ReelTimingProfile.studio,
   );

   _animController.onReelStop = (reelIndex) {
     // Trigger REEL_STOP_$reelIndex audio event
     eventRegistry.triggerStage('REEL_STOP_$reelIndex');
   };

   _animController.onAllReelsStopped = () {
     // Trigger win evaluation
   };

2. Create ticker for animation:
   _ticker = createTicker((_) => _animController.tick());
   _ticker.start();

3. When spin starts:
   _animController.setTargetGrid(result.grid);
   _animController.startSpin();
   eventRegistry.triggerStage('SPIN_START');

4. Build reels:
   for (int i = 0; i < 5; i++) {
     ProfessionalReelWidget(
       state: _animController.getReelState(i),
       spinSymbols: _animController.spinSymbols[i],
       targetSymbols: _animController.targetGrid[i],
       rowCount: 3,
       width: reelWidth,
       height: reelHeight,
       symbolBuilder: (id, isWinning) => _buildSymbol(id, isWinning),
       winningRows: _getWinningRowsForReel(i),
     );
   }
*/
