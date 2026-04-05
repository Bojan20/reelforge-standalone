/// Animation Debug Panel (P4.23)
///
/// Debug panel for SlotLab reel animations showing:
/// - Per-reel animation phase (idle/accelerating/spinning/decelerating/bouncing/stopped)
/// - Animation velocities and positions
/// - Timing information
/// - Phase transitions
///
/// Created: 2026-01-30

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Animation phase enum (matches professional_reel_animation.dart)
enum AnimationPhase {
  idle,
  accelerating,
  spinning,
  decelerating,
  bouncing,
  stopped;

  String get displayName {
    switch (this) {
      case AnimationPhase.idle:
        return 'IDLE';
      case AnimationPhase.accelerating:
        return 'ACCEL';
      case AnimationPhase.spinning:
        return 'SPIN';
      case AnimationPhase.decelerating:
        return 'DECEL';
      case AnimationPhase.bouncing:
        return 'BOUNCE';
      case AnimationPhase.stopped:
        return 'STOP';
    }
  }

  Color get color {
    switch (this) {
      case AnimationPhase.idle:
        return FluxForgeTheme.textSecondary;
      case AnimationPhase.accelerating:
        return FluxForgeTheme.accentOrange;
      case AnimationPhase.spinning:
        return FluxForgeTheme.accentBlue;
      case AnimationPhase.decelerating:
        return const Color(0xFFFFD700); // Gold
      case AnimationPhase.bouncing:
        return FluxForgeTheme.accentGreen;
      case AnimationPhase.stopped:
        return FluxForgeTheme.textSecondary;
    }
  }
}

/// Reel animation state snapshot
class ReelAnimationState {
  final int reelIndex;
  final AnimationPhase phase;
  final double scrollOffset;
  final double velocity;
  final double targetPosition;
  final Duration phaseDuration;
  final DateTime phaseStartTime;

  const ReelAnimationState({
    required this.reelIndex,
    required this.phase,
    required this.scrollOffset,
    required this.velocity,
    required this.targetPosition,
    required this.phaseDuration,
    required this.phaseStartTime,
  });

  factory ReelAnimationState.idle(int reelIndex) => ReelAnimationState(
        reelIndex: reelIndex,
        phase: AnimationPhase.idle,
        scrollOffset: 0,
        velocity: 0,
        targetPosition: 0,
        phaseDuration: Duration.zero,
        phaseStartTime: DateTime.now(),
      );

  double get phaseProgress {
    if (phaseDuration.inMilliseconds == 0) return 0;
    final elapsed = DateTime.now().difference(phaseStartTime);
    return (elapsed.inMilliseconds / phaseDuration.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Animation debug monitor singleton
class AnimationDebugMonitor {
  static final AnimationDebugMonitor _instance = AnimationDebugMonitor._();
  static AnimationDebugMonitor get instance => _instance;

  AnimationDebugMonitor._();

  final Map<int, ReelAnimationState> _reelStates = {};
  final _controller = StreamController<Map<int, ReelAnimationState>>.broadcast();
  final List<PhaseTransition> _transitionLog = [];
  static const int _maxTransitions = 50;

  Stream<Map<int, ReelAnimationState>> get stream => _controller.stream;
  Map<int, ReelAnimationState> get reelStates => Map.unmodifiable(_reelStates);
  List<PhaseTransition> get transitionLog => List.unmodifiable(_transitionLog);

  void updateReelState(int reelIndex, ReelAnimationState state) {
    final oldState = _reelStates[reelIndex];

    // Log phase transitions
    if (oldState != null && oldState.phase != state.phase) {
      _logTransition(reelIndex, oldState.phase, state.phase);
    }

    _reelStates[reelIndex] = state;
    _controller.add(Map.unmodifiable(_reelStates));
  }

  void _logTransition(int reelIndex, AnimationPhase from, AnimationPhase to) {
    _transitionLog.add(PhaseTransition(
      reelIndex: reelIndex,
      from: from,
      to: to,
      timestamp: DateTime.now(),
    ));

    while (_transitionLog.length > _maxTransitions) {
      _transitionLog.removeAt(0);
    }
  }

  void reset() {
    _reelStates.clear();
    _transitionLog.clear();
    _controller.add({});
  }

  void dispose() {
    _controller.close();
  }
}

/// Phase transition record for animation debugging
class PhaseTransition {
  final int reelIndex;
  final AnimationPhase from;
  final AnimationPhase to;
  final DateTime timestamp;

  PhaseTransition({
    required this.reelIndex,
    required this.from,
    required this.to,
    required this.timestamp,
  });

  String get formattedTime {
    final t = timestamp;
    return '${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Animation Debug Panel Widget
class AnimationDebugPanel extends StatefulWidget {
  final int reelCount;
  final VoidCallback? onClose;

  const AnimationDebugPanel({
    super.key,
    this.reelCount = 5,
    this.onClose,
  });

  @override
  State<AnimationDebugPanel> createState() => _AnimationDebugPanelState();
}

class _AnimationDebugPanelState extends State<AnimationDebugPanel> {
  late StreamSubscription<Map<int, ReelAnimationState>> _subscription;
  Map<int, ReelAnimationState> _states = {};
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _subscription = AnimationDebugMonitor.instance.stream.listen((states) {
      if (mounted) {
        setState(() => _states = states);
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withAlpha(240),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A35)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildReelGrid(),
                const SizedBox(height: 8),
                _buildToggleRow(),
                if (_showLog) ...[
                  const SizedBox(height: 8),
                  _buildTransitionLog(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.animation,
                size: 14,
                color: FluxForgeTheme.accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                'Animation Debug',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => AnimationDebugMonitor.instance.reset(),
                child: Icon(
                  Icons.refresh,
                  size: 14,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReelGrid() {
    return Column(
      children: [
        // Header row
        Row(
          children: [
            SizedBox(width: 35, child: _buildGridHeader('Reel')),
            Expanded(child: _buildGridHeader('Phase')),
            SizedBox(width: 50, child: _buildGridHeader('Pos')),
            SizedBox(width: 50, child: _buildGridHeader('Vel')),
          ],
        ),
        const SizedBox(height: 4),
        // Reel rows
        ...List.generate(widget.reelCount, (i) => _buildReelRow(i)),
      ],
    );
  }

  Widget _buildGridHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: FluxForgeTheme.textSecondary,
      ),
    );
  }

  Widget _buildReelRow(int reelIndex) {
    final state = _states[reelIndex] ?? ReelAnimationState.idle(reelIndex);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Reel number
          SizedBox(
            width: 35,
            child: Text(
              'R${reelIndex + 1}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Phase badge with progress
          Expanded(child: _buildPhaseBadge(state)),
          // Position
          SizedBox(
            width: 50,
            child: Text(
              state.scrollOffset.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          // Velocity
          SizedBox(
            width: 50,
            child: Text(
              state.velocity.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 10,
                color: state.velocity.abs() > 10
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textSecondary,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseBadge(ReelAnimationState state) {
    return Container(
      height: 18,
      margin: const EdgeInsets.only(right: 4),
      child: Stack(
        children: [
          // Progress background
          Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // Progress fill
          FractionallySizedBox(
            widthFactor: state.phaseProgress,
            child: Container(
              decoration: BoxDecoration(
                color: state.phase.color.withAlpha(60),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Label
          Center(
            child: Text(
              state.phase.displayName,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: state.phase.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Transition Log',
          style: TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _showLog = !_showLog),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _showLog ? FluxForgeTheme.accentBlue.withAlpha(30) : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _showLog ? 'Hide' : 'Show',
              style: TextStyle(
                fontSize: 9,
                color: _showLog ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransitionLog() {
    final transitions = AnimationDebugMonitor.instance.transitionLog;
    if (transitions.isEmpty) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: Text(
          'No transitions yet',
          style: TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      );
    }

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: transitions.length,
        reverse: true,
        itemBuilder: (context, index) {
          final t = transitions[transitions.length - 1 - index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Text(
                  t.formattedTime,
                  style: TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'R${t.reelIndex + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  t.from.displayName,
                  style: TextStyle(
                    fontSize: 9,
                    color: t.from.color,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 10,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
                Text(
                  t.to.displayName,
                  style: TextStyle(
                    fontSize: 9,
                    color: t.to.color,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Compact animation status badge
class AnimationStatusBadge extends StatefulWidget {
  final int reelCount;

  const AnimationStatusBadge({super.key, this.reelCount = 5});

  @override
  State<AnimationStatusBadge> createState() => _AnimationStatusBadgeState();
}

class _AnimationStatusBadgeState extends State<AnimationStatusBadge> {
  late StreamSubscription<Map<int, ReelAnimationState>> _subscription;
  Map<int, ReelAnimationState> _states = {};

  @override
  void initState() {
    super.initState();
    _subscription = AnimationDebugMonitor.instance.stream.listen((states) {
      if (mounted) {
        setState(() => _states = states);
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.reelCount, (i) {
          final state = _states[i] ?? ReelAnimationState.idle(i);
          return Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(left: i > 0 ? 3 : 0),
            decoration: BoxDecoration(
              color: state.phase.color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
