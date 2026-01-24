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
    this.bounceMs = 200,
    this.accelerationMs = 150,
  });

  /// Normal gameplay timing
  static const normal = ReelTimingProfile(
    firstReelStopMs: 800,
    reelStopIntervalMs: 300,
    decelerationMs: 250,
    bounceMs: 150,
    accelerationMs: 100,
  );

  /// Turbo mode - faster but still visible
  static const turbo = ReelTimingProfile(
    firstReelStopMs: 400,
    reelStopIntervalMs: 100,
    decelerationMs: 150,
    bounceMs: 100,
    accelerationMs: 80,
  );

  /// Studio mode - optimized for audio testing
  /// CRITICAL: Must match timing.rs studio() values!
  static const studio = ReelTimingProfile(
    firstReelStopMs: 1000,   // Matches timing.rs: reel_spin_duration_ms
    reelStopIntervalMs: 370, // Matches timing.rs: reel_stop_interval_ms
    decelerationMs: 280,
    bounceMs: 180,
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

  ReelAnimationState(this.reelIndex, this.profile);

  /// Get bounce offset in pixels for visual effect
  double get bounceOffset => overshootAmount * 20.0; // Scale to visible pixels

  /// Get stop time for this reel
  int get stopTime => profile.getReelStopTime(reelIndex);

  /// Update state based on elapsed time since spin start
  void update(int elapsedMs, List<int> targetSymbols) {
    if (phase == ReelPhase.idle || phase == ReelPhase.stopped) return;

    final stopT = stopTime;
    final accelEnd = profile.accelerationMs;
    final decelStart = stopT - profile.decelerationMs;
    final bounceStart = stopT;
    final bounceEnd = stopT + profile.bounceMs;

    if (elapsedMs < accelEnd) {
      // PHASE: Acceleration (0 → max velocity)
      phase = ReelPhase.accelerating;
      phaseProgress = elapsedMs / accelEnd;
      final t = phaseProgress;
      velocity = _easeOutQuad(t) * 1.0; // Max velocity = 1.0
      scrollOffset += velocity * 0.1;
      spinCycles = scrollOffset / 10.0; // Track spin cycles
    } else if (elapsedMs < decelStart) {
      // PHASE: Full-speed spinning
      phase = ReelPhase.spinning;
      velocity = 1.0;
      scrollOffset += velocity * 0.1;
      final spinDuration = decelStart - accelEnd;
      phaseProgress = (elapsedMs - accelEnd) / spinDuration.clamp(1, double.infinity);
      spinCycles = scrollOffset / 10.0; // Track spin cycles for visual effect
    } else if (elapsedMs < bounceStart) {
      // PHASE: Deceleration (max → 0 velocity)
      phase = ReelPhase.decelerating;
      phaseProgress = (elapsedMs - decelStart) / (bounceStart - decelStart);
      final t = phaseProgress;
      velocity = (1.0 - _easeInQuad(t)) * 1.0;
      scrollOffset += velocity * 0.1;

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
  }

  /// Reset to idle
  void reset() {
    phase = ReelPhase.idle;
    velocity = 0;
    bounceProgress = 0;
    overshootAmount = 0;
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

      if (wasStillMoving && state.phase == ReelPhase.bouncing) {
        onReelStop?.call(i);  // Audio triggers at visual landing
      }

      if (state.phase != ReelPhase.stopped && state.phase != ReelPhase.idle) {
        anyStillSpinning = true;
      }
    }

    notifyListeners();

    // Check if all reels stopped (after bounce completes)
    if (!anyStillSpinning && _isSpinning) {
      debugPrint('[ReelAnimController] 🏁 All reels stopped naturally, setting _isSpinning=false');
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
