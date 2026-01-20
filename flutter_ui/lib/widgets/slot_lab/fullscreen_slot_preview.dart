/// Fullscreen Slot Preview Mode
///
/// Immersive slot machine experience for testing audio design.
/// - Full screen slot machine (no UI chrome)
/// - SPACE to spin, ESC to exit
/// - D to toggle debug overlay
/// - 1-0 for forced outcomes
/// - State preserved when returning to Slot Lab
///
/// Phase 1: Basic preview mode
/// Phase 2: Premium visuals with particles and animated glow
/// Phase 3: Debug integration (stage trace, audio meter, event indicators)
/// Phase 4: Advanced features (bet controls, balance, session stats)
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart' show ForcedOutcome, SlotLabSpinResult, SlotLabStageEvent;
import '../../theme/fluxforge_theme.dart';
import 'slot_preview_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AMBIENT PARTICLE SYSTEM
// ═══════════════════════════════════════════════════════════════════════════

class _AmbientParticle {
  double x, y;
  double vx, vy;
  double size;
  double opacity;
  double pulsePhase;
  Color color;

  _AmbientParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.pulsePhase,
    required this.color,
  });

  void update() {
    x += vx;
    y += vy;

    // Wrap around screen
    if (x < -0.1) x = 1.1;
    if (x > 1.1) x = -0.1;
    if (y < -0.1) y = 1.1;
    if (y > 1.1) y = -0.1;

    // Subtle vertical drift
    vy += (math.Random().nextDouble() - 0.5) * 0.0001;
    vy = vy.clamp(-0.002, 0.002);
  }
}

class _AmbientParticlePainter extends CustomPainter {
  final List<_AmbientParticle> particles;
  final double time;

  _AmbientParticlePainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Pulsing opacity
      final pulse = (math.sin(time * 2 + p.pulsePhase) + 1) / 2;
      final opacity = p.opacity * (0.3 + pulse * 0.7);

      final paint = Paint()
        ..color = p.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.5);

      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );

      // Core (brighter center)
      final corePaint = Paint()
        ..color = Colors.white.withOpacity((opacity * 0.5).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size * 0.3,
        corePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientParticlePainter oldDelegate) =>
      oldDelegate.time != time;
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI STAGE TRACE WIDGET (Phase 3)
// ═══════════════════════════════════════════════════════════════════════════

class _MiniStageTrace extends StatelessWidget {
  final List<SlotLabStageEvent> stages;
  final int currentIndex;
  final bool isPlaying;

  const _MiniStageTrace({
    required this.stages,
    required this.currentIndex,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calculate total duration
    final maxTime = stages.isNotEmpty
        ? stages.map((s) => s.timestampMs).reduce(math.max)
        : 1000;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(
                isPlaying ? Icons.play_circle : Icons.check_circle,
                color: isPlaying ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'STAGE TRACE',
                style: TextStyle(
                  color: isPlaying ? FluxForgeTheme.accentOrange : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '${stages.length} events',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Timeline bar
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a28),
              borderRadius: BorderRadius.circular(3),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Progress bar
                    if (isPlaying && currentIndex < stages.length)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: constraints.maxWidth *
                            (stages[currentIndex].timestampMs / maxTime).clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [FluxForgeTheme.accentBlue, FluxForgeTheme.accentCyan],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    // Event markers
                    ...stages.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final stage = entry.value;
                      final position = (stage.timestampMs / maxTime).clamp(0.0, 1.0);
                      final isPast = idx < currentIndex;
                      final isCurrent = idx == currentIndex && isPlaying;

                      return Positioned(
                        left: constraints.maxWidth * position - 3,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 6,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? FluxForgeTheme.accentOrange
                                : isPast
                                    ? FluxForgeTheme.accentGreen.withOpacity(0.8)
                                    : Colors.white24,
                            shape: BoxShape.circle,
                            border: isCurrent
                                ? Border.all(color: Colors.white, width: 1)
                                : null,
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Recent events list (last 5)
          ...stages
              .asMap()
              .entries
              .where((e) => e.key >= (currentIndex - 2).clamp(0, stages.length))
              .take(5)
              .map((entry) {
            final idx = entry.key;
            final stage = entry.value;
            final isPast = idx < currentIndex;
            final isCurrent = idx == currentIndex && isPlaying;

            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  // Status indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? FluxForgeTheme.accentOrange
                          : isPast
                              ? FluxForgeTheme.accentGreen
                              : Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: isCurrent
                        ? const Center(
                            child: SizedBox(
                              width: 6,
                              height: 6,
                              child: CircularProgressIndicator(
                                strokeWidth: 1,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // Stage name
                  Expanded(
                    child: Text(
                      stage.stageType.toUpperCase(),
                      style: TextStyle(
                        color: isCurrent
                            ? Colors.white
                            : isPast
                                ? Colors.white54
                                : Colors.white38,
                        fontSize: 9,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Timestamp
                  Text(
                    '${stage.timestampMs}ms',
                    style: TextStyle(
                      color: isCurrent ? FluxForgeTheme.accentOrange : Colors.white38,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO LEVEL METER (Phase 3)
// ═══════════════════════════════════════════════════════════════════════════

class _AudioLevelMeter extends StatefulWidget {
  final bool isPlaying;

  const _AudioLevelMeter({required this.isPlaying});

  @override
  State<_AudioLevelMeter> createState() => _AudioLevelMeterState();
}

class _AudioLevelMeterState extends State<_AudioLevelMeter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _leftLevel = 0.0;
  double _rightLevel = 0.0;
  double _peakLeft = 0.0;
  double _peakRight = 0.0;
  Timer? _decayTimer;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..repeat();
    _controller.addListener(_updateLevels);
  }

  void _updateLevels() {
    if (!mounted) return;

    // Simulate audio levels based on playback state
    // In real implementation, this would read from audio engine
    if (widget.isPlaying) {
      // Simulate activity
      final baseLevel = 0.4 + _random.nextDouble() * 0.3;
      final variation = _random.nextDouble() * 0.2;
      _leftLevel = (baseLevel + variation).clamp(0.0, 1.0);
      _rightLevel = (baseLevel + variation - 0.05).clamp(0.0, 1.0);

      // Update peaks
      if (_leftLevel > _peakLeft) _peakLeft = _leftLevel;
      if (_rightLevel > _peakRight) _peakRight = _rightLevel;
    } else {
      // Decay
      _leftLevel = (_leftLevel * 0.85).clamp(0.0, 1.0);
      _rightLevel = (_rightLevel * 0.85).clamp(0.0, 1.0);
    }

    // Peak decay
    _peakLeft = (_peakLeft * 0.995).clamp(0.0, 1.0);
    _peakRight = (_peakRight * 0.995).clamp(0.0, 1.0);

    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _decayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 120,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a48)),
      ),
      child: Column(
        children: [
          const Text(
            'LEVEL',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                _buildMeterBar(_leftLevel, _peakLeft, 'L'),
                const SizedBox(width: 4),
                _buildMeterBar(_rightLevel, _peakRight, 'R'),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(_leftLevel * -60 + 6).toStringAsFixed(0)}dB',
            style: TextStyle(
              color: _leftLevel > 0.9 ? FluxForgeTheme.accentRed : Colors.white38,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeterBar(double level, double peak, String label) {
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a28),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Level fill
                  FractionallySizedBox(
                    heightFactor: level,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            FluxForgeTheme.accentGreen,
                            FluxForgeTheme.accentCyan,
                            FluxForgeTheme.accentOrange,
                            FluxForgeTheme.accentRed,
                          ],
                          stops: const [0.0, 0.5, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Peak indicator
                  Positioned(
                    bottom: peak * 80, // Approximate height
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      color: peak > 0.9
                          ? FluxForgeTheme.accentRed
                          : Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT TRIGGER INDICATOR (Phase 3)
// ═══════════════════════════════════════════════════════════════════════════

class _EventTriggerIndicator extends StatefulWidget {
  final SlotLabStageEvent? currentEvent;

  const _EventTriggerIndicator({this.currentEvent});

  @override
  State<_EventTriggerIndicator> createState() => _EventTriggerIndicatorState();
}

class _EventTriggerIndicatorState extends State<_EventTriggerIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _flashController;
  String? _lastEventType;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(_EventTriggerIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentEvent?.stageType != _lastEventType) {
      _lastEventType = widget.currentEvent?.stageType;
      if (_lastEventType != null) {
        _flashController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  Color _getEventColor(String? type) {
    if (type == null) return Colors.transparent;
    final t = type.toLowerCase();
    if (t.contains('spin')) return FluxForgeTheme.accentBlue;
    if (t.contains('reel')) return FluxForgeTheme.accentCyan;
    if (t.contains('win')) return FluxForgeTheme.accentGreen;
    if (t.contains('anticipation')) return FluxForgeTheme.accentOrange;
    if (t.contains('jackpot')) return const Color(0xFFFFD700);
    if (t.contains('feature') || t.contains('free')) return const Color(0xFFE040FB);
    if (t.contains('rollup')) return const Color(0xFF40FF90);
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.currentEvent;
    if (event == null) return const SizedBox.shrink();

    final color = _getEventColor(event.stageType);

    return AnimatedBuilder(
      animation: _flashController,
      builder: (context, _) {
        final opacity = 1.0 - _flashController.value * 0.5;
        final scale = 1.0 + (1.0 - _flashController.value) * 0.1;

        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.3 * opacity),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(opacity),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4 * opacity),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.audiotrack, color: color, size: 14),
                const SizedBox(width: 6),
                Text(
                  event.stageType.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(opacity),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SESSION STATS PANEL (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════

class _SessionStatsPanel extends StatelessWidget {
  final int spinCount;
  final double balance;
  final double totalBet;
  final double totalWin;
  final double rtp;
  final int wins;
  final int losses;

  const _SessionStatsPanel({
    required this.spinCount,
    required this.balance,
    required this.totalBet,
    required this.totalWin,
    required this.rtp,
    required this.wins,
    required this.losses,
  });

  @override
  Widget build(BuildContext context) {
    final hitRate = spinCount > 0 ? (wins / spinCount * 100) : 0.0;
    final profit = totalWin - totalBet;
    final isProfitable = profit >= 0;

    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          const Row(
            children: [
              Icon(Icons.analytics, color: Colors.white54, size: 14),
              SizedBox(width: 6),
              Text(
                'SESSION STATS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF3a3a48), height: 12),

          // Balance
          _buildStatRow(
            'BALANCE',
            '\$${balance.toStringAsFixed(0)}',
            Colors.white,
            large: true,
          ),
          const SizedBox(height: 8),

          // Win/Loss counts
          Row(
            children: [
              Expanded(
                child: _buildMiniStat('WINS', '$wins', FluxForgeTheme.accentGreen),
              ),
              Expanded(
                child: _buildMiniStat('LOSS', '$losses', FluxForgeTheme.accentRed),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Stats grid
          _buildStatRow('Spins', '$spinCount', Colors.white54),
          _buildStatRow('Total Bet', '\$${totalBet.toStringAsFixed(0)}', Colors.white54),
          _buildStatRow('Total Win', '\$${totalWin.toStringAsFixed(0)}',
              totalWin > 0 ? FluxForgeTheme.accentGreen : Colors.white54),
          _buildStatRow(
            'Profit',
            '${isProfitable ? '+' : ''}\$${profit.toStringAsFixed(0)}',
            isProfitable ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
          ),
          const Divider(color: Color(0xFF3a3a48), height: 12),
          _buildStatRow('Hit Rate', '${hitRate.toStringAsFixed(1)}%', Colors.white70),
          _buildStatRow(
            'RTP',
            '${rtp.toStringAsFixed(1)}%',
            rtp >= 96 ? FluxForgeTheme.accentGreen : rtp >= 90 ? Colors.white70 : FluxForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color, {bool large = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: large ? 10 : 9,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: large ? 14 : 10,
              fontWeight: large ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BET CONTROLS (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════

class _BetControls extends StatelessWidget {
  final double betAmount;
  final double balance;
  final bool isSpinning;
  final ValueChanged<double> onBetChanged;

  const _BetControls({
    required this.betAmount,
    required this.balance,
    required this.isSpinning,
    required this.onBetChanged,
  });

  static const List<double> betLevels = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0];

  @override
  Widget build(BuildContext context) {
    final currentIndex = betLevels.indexOf(betAmount);
    final canDecrease = currentIndex > 0 && !isSpinning;
    final canIncrease = currentIndex < betLevels.length - 1 &&
        !isSpinning &&
        betLevels[currentIndex + 1] <= balance;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3a3a48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrease button
          _buildBetButton(
            icon: Icons.remove,
            enabled: canDecrease,
            onTap: () {
              if (canDecrease) {
                onBetChanged(betLevels[currentIndex - 1]);
              }
            },
          ),
          const SizedBox(width: 12),
          // Bet amount display
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'BET',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '\$${betAmount.toStringAsFixed(betAmount < 1 ? 2 : 0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Increase button
          _buildBetButton(
            icon: Icons.add,
            enabled: canIncrease,
            onTap: () {
              if (canIncrease) {
                onBetChanged(betLevels[currentIndex + 1]);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBetButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return _FocusableButton(
      enabled: enabled,
      onTap: onTap,
      builder: (context, isFocused) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? FluxForgeTheme.accentBlue.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: isFocused
                ? Colors.white
                : enabled
                    ? FluxForgeTheme.accentBlue.withOpacity(0.6)
                    : Colors.white.withOpacity(0.1),
            width: isFocused ? 2 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: FluxForgeTheme.accentBlue.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white24,
          size: 18,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FOCUSABLE BUTTON WRAPPER (P3 Accessibility - Focus Rings)
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper widget that provides visible focus ring for keyboard navigation
class _FocusableButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool isFocused) builder;

  const _FocusableButton({
    required this.enabled,
    required this.onTap,
    required this.builder,
  });

  @override
  State<_FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<_FocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: widget.enabled,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.space)) {
          if (widget.enabled) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: widget.builder(context, _isFocused),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FULLSCREEN SLOT PREVIEW (Main Widget)
// ═══════════════════════════════════════════════════════════════════════════

/// Fullscreen slot preview for immersive audio testing
class FullscreenSlotPreview extends StatefulWidget {
  final VoidCallback onExit;
  final int reels;
  final int rows;

  const FullscreenSlotPreview({
    super.key,
    required this.onExit,
    this.reels = 5,
    this.rows = 3,
  });

  @override
  State<FullscreenSlotPreview> createState() => _FullscreenSlotPreviewState();
}

class _FullscreenSlotPreviewState extends State<FullscreenSlotPreview>
    with TickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  bool _showDebugOverlay = false;
  bool _showControlHints = true;
  bool _showStatsPanel = false;
  Timer? _hideHintsTimer;

  // Animation controllers
  late AnimationController _hintsController;
  late Animation<double> _hintsOpacity;

  late AnimationController _ambientController;
  late AnimationController _frameGlowController;
  late Animation<double> _frameGlowAnimation;

  late AnimationController _spinButtonPulseController;
  late Animation<double> _spinButtonPulse;

  // Ambient particles
  final List<_AmbientParticle> _particles = [];
  final _random = math.Random();

  // Win state tracking for frame glow
  String _currentWinTier = '';

  // Phase 4: Session tracking
  double _sessionBalance = 1000.0;
  double _totalBet = 0.0;
  double _totalWin = 0.0;
  int _wins = 0;
  int _losses = 0;
  double _currentBet = 1.0;
  double _previousBalance = 1000.0; // Track for glow effect
  late AnimationController _balanceGlowController;
  Color _balanceGlowColor = Colors.transparent;

  // Phase 3: Current stage index for mini trace
  int _currentStageIndex = 0;

  // Free spin mode tracking
  bool _isFreeSpin = false;
  int _freeSpinsRemaining = 0;

  // Jackpot celebration state
  bool _isJackpotCelebration = false;
  String _jackpotTier = ''; // MINI, MINOR, MAJOR, GRAND
  double _jackpotAmount = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeParticles();

    // Auto-hide hints after 5 seconds
    _hideHintsTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _showControlHints) {
        _hintsController.forward();
        setState(() => _showControlHints = false);
      }
    });

    // Request focus after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // Sync bet amount from provider
      final provider = context.read<SlotLabProvider>();
      _currentBet = provider.betAmount;
    });
  }

  void _initializeAnimations() {
    // Hints fade
    _hintsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _hintsOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _hintsController, curve: Curves.easeOut),
    );

    // Ambient particle animation (continuous)
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _ambientController.addListener(_updateParticles);

    // Frame glow animation
    _frameGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _frameGlowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _frameGlowController, curve: Curves.easeInOut),
    );

    // Spin button pulse
    _spinButtonPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _spinButtonPulse = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _spinButtonPulseController, curve: Curves.easeInOut),
    );

    // Balance glow animation (for win/loss visual feedback)
    _balanceGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  void _initializeParticles() {
    // Create ambient floating particles
    final colors = [
      FluxForgeTheme.accentBlue.withOpacity(0.6),
      FluxForgeTheme.accentCyan.withOpacity(0.5),
      const Color(0xFFFFD700).withOpacity(0.4),
      const Color(0xFFE040FB).withOpacity(0.3),
    ];

    for (int i = 0; i < 30; i++) {
      _particles.add(_AmbientParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        vx: (_random.nextDouble() - 0.5) * 0.001,
        vy: (_random.nextDouble() - 0.5) * 0.001,
        size: _random.nextDouble() * 4 + 2,
        opacity: _random.nextDouble() * 0.4 + 0.2,
        pulsePhase: _random.nextDouble() * math.pi * 2,
        color: colors[_random.nextInt(colors.length)],
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    for (final p in _particles) {
      p.update();
    }
  }

  @override
  void dispose() {
    _hideHintsTimer?.cancel();
    _hintsController.dispose();
    _ambientController.dispose();
    _frameGlowController.dispose();
    _spinButtonPulseController.dispose();
    _balanceGlowController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSpin(SlotLabProvider provider) {
    if (provider.isPlayingStages) return;
    if (_sessionBalance < _currentBet) return;

    // Deduct bet
    setState(() {
      _previousBalance = _sessionBalance;
      _sessionBalance -= _currentBet;
      _totalBet += _currentBet;
      _currentStageIndex = 0;
    });

    // Start spin
    provider.spin().then((result) {
      if (result != null && mounted) {
        setState(() {
          final winAmount = result.totalWin * _currentBet;
          _totalWin += winAmount;
          _sessionBalance += winAmount;
          if (result.isWin) {
            _wins++;
          } else {
            _losses++;
          }
          // Trigger balance glow effect
          _triggerBalanceGlow(result.isWin, winAmount);
        });
      }
    });
  }

  void _handleForcedSpin(SlotLabProvider provider, ForcedOutcome outcome) {
    if (provider.isPlayingStages) return;
    if (_sessionBalance < _currentBet) return;

    // Deduct bet
    setState(() {
      _previousBalance = _sessionBalance;
      _sessionBalance -= _currentBet;
      _totalBet += _currentBet;
      _currentStageIndex = 0;
    });

    // Start forced spin
    provider.spinForced(outcome).then((result) {
      if (result != null && mounted) {
        setState(() {
          final winAmount = result.totalWin * _currentBet;
          _totalWin += winAmount;
          _sessionBalance += winAmount;
          if (result.isWin) {
            _wins++;
          } else {
            _losses++;
          }
          // Trigger balance glow effect
          _triggerBalanceGlow(result.isWin, winAmount);
        });
      }
    });
  }

  /// Trigger balance glow visual feedback on win/loss
  void _triggerBalanceGlow(bool isWin, double winAmount) {
    if (isWin && winAmount > 0) {
      // Green glow for wins, intensity based on win amount
      final intensity = (winAmount / _currentBet).clamp(0.5, 1.0);
      _balanceGlowColor = FluxForgeTheme.accentGreen.withOpacity(intensity);
    } else {
      // Subtle red pulse for losses
      _balanceGlowColor = FluxForgeTheme.accentRed.withOpacity(0.3);
    }
    _balanceGlowController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _balanceGlowColor = Colors.transparent;
        });
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final provider = context.read<SlotLabProvider>();

    switch (event.logicalKey) {
      // ESC - Exit preview
      case LogicalKeyboardKey.escape:
        widget.onExit();
        return KeyEventResult.handled;

      // SPACE - Spin
      case LogicalKeyboardKey.space:
        _handleSpin(provider);
        return KeyEventResult.handled;

      // D - Toggle debug overlay
      case LogicalKeyboardKey.keyD:
        setState(() => _showDebugOverlay = !_showDebugOverlay);
        return KeyEventResult.handled;

      // S - Toggle stats panel
      case LogicalKeyboardKey.keyS:
        setState(() => _showStatsPanel = !_showStatsPanel);
        return KeyEventResult.handled;

      // H - Toggle hints
      case LogicalKeyboardKey.keyH:
        setState(() {
          _showControlHints = !_showControlHints;
          if (_showControlHints) {
            _hintsController.reverse();
          } else {
            _hintsController.forward();
          }
        });
        return KeyEventResult.handled;

      // +/- or =/- for bet amount
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
        _adjustBet(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
        _adjustBet(-1);
        return KeyEventResult.handled;

      // 1-0 - Forced outcomes (only in debug/profile mode for testing)
      // In release builds, these keys are ignored to prevent manipulation
      case LogicalKeyboardKey.digit1:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.lose);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit2:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.smallWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit3:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.bigWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit4:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.megaWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit5:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.epicWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit6:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.freeSpins);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit7:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.jackpotGrand);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit8:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.nearMiss);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit9:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.cascade);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit0:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.ultraWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }

  void _adjustBet(int direction) {
    const betLevels = _BetControls.betLevels;
    final currentIndex = betLevels.indexOf(_currentBet);
    if (currentIndex == -1) return;

    final newIndex = (currentIndex + direction).clamp(0, betLevels.length - 1);
    final newBet = betLevels[newIndex];

    if (newBet <= _sessionBalance) {
      setState(() => _currentBet = newBet);
      // Sync to provider
      context.read<SlotLabProvider>().setBetAmount(newBet);
    }
  }

  /// Determine win tier from result using win-to-bet ratio (industry standard)
  /// ULTRA: 100x+, EPIC: 50x+, MEGA: 25x+, BIG: 10x+, SMALL: >0x
  String _getWinTier(SlotLabSpinResult? result) {
    if (result == null || !result.isWin) return '';
    final win = result.totalWin;
    final bet = _currentBet;
    if (bet <= 0) return win > 0 ? 'SMALL' : '';

    final ratio = win / bet;
    if (ratio >= 100) return 'ULTRA';
    if (ratio >= 50) return 'EPIC';
    if (ratio >= 25) return 'MEGA';
    if (ratio >= 10) return 'BIG';
    if (ratio > 0) return 'SMALL';
    return '';
  }

  Color _getWinColor(String tier) {
    return switch (tier) {
      'ULTRA' => const Color(0xFFFF4080),
      'EPIC' => const Color(0xFFE040FB),
      'MEGA' => const Color(0xFFFFD700),
      'BIG' => FluxForgeTheme.accentGreen,
      'SMALL' => FluxForgeTheme.accentGreen,
      _ => FluxForgeTheme.accentBlue,
    };
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SlotLabProvider>();
    final result = provider.lastResult;
    final isSpinning = provider.isPlayingStages;
    final stages = provider.lastStages;

    // Update win tier for glow color
    if (!isSpinning && result != null) {
      _currentWinTier = _getWinTier(result);
    } else if (isSpinning) {
      _currentWinTier = '';
    }

    // Detect free spin mode from stages
    if (stages.isNotEmpty) {
      final hasFeatureEnter = stages.any((s) =>
          s.stageType.toLowerCase().contains('feature') &&
          s.stageType.toLowerCase().contains('enter'));
      final hasFeatureExit = stages.any((s) =>
          s.stageType.toLowerCase().contains('feature') &&
          s.stageType.toLowerCase().contains('exit'));
      if (hasFeatureEnter && !_isFreeSpin) {
        _isFreeSpin = true;
        // Default to 10 free spins (actual count determined by game logic)
        _freeSpinsRemaining = 10;
      } else if (hasFeatureExit && _isFreeSpin) {
        _isFreeSpin = false;
        _freeSpinsRemaining = 0;
      }

      // Detect jackpot events
      final hasJackpotTrigger = stages.any((s) =>
          s.stageType.toLowerCase().contains('jackpot') &&
          s.stageType.toLowerCase().contains('trigger'));
      final hasJackpotEnd = stages.any((s) =>
          s.stageType.toLowerCase().contains('jackpot') &&
          s.stageType.toLowerCase().contains('end'));
      if (hasJackpotTrigger && !_isJackpotCelebration) {
        _isJackpotCelebration = true;
        // Determine jackpot tier from bigWinTier or default to GRAND
        _jackpotTier = result?.bigWinTier?.name.toUpperCase() ?? 'GRAND';
        // Jackpot amount is total win multiplied by bet
        _jackpotAmount = (result?.totalWin ?? 5000) * _currentBet;
      } else if (hasJackpotEnd && _isJackpotCelebration) {
        _isJackpotCelebration = false;
        _jackpotTier = '';
        _jackpotAmount = 0;
      }
    }

    // Get current stage for event indicator
    SlotLabStageEvent? currentStage;
    if (isSpinning && stages.isNotEmpty && _currentStageIndex < stages.length) {
      currentStage = stages[_currentStageIndex];
    }

    // Calculate RTP for session
    final sessionRtp = _totalBet > 0 ? (_totalWin / _totalBet * 100) : 0.0;

    // Check for reduced motion preference (accessibility)
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF0a0a12),
        body: Stack(
          children: [
            // Background gradient with vignette
            _buildBackground(),

            // Ambient particles layer (respects reduced motion preference)
            if (!reduceMotion)
              AnimatedBuilder(
                animation: _ambientController,
                builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _AmbientParticlePainter(
                  particles: _particles,
                  time: _ambientController.value * 10,
                ),
              ),
            ),

            // Centered slot machine with animated frame
            Center(
              child: Semantics(
                label: 'Slot machine grid, ${widget.reels} reels by ${widget.rows} rows',
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
                  ),
                  child: AspectRatio(
                    aspectRatio: widget.reels / widget.rows * 1.2,
                    child: _buildSlotFrame(provider),
                  ),
                ),
              ),
            ),

            // Win tier badge (shows above slot during win)
            if (_currentWinTier.isNotEmpty && !isSpinning)
              Positioned(
                top: MediaQuery.of(context).size.height * 0.12,
                left: 0,
                right: 0,
                child: Semantics(
                  label: '$_currentWinTier win! ${result?.totalWin.toStringAsFixed(0) ?? 0} credits',
                  liveRegion: true,
                  child: _buildWinBadge(),
                ),
              ),

            // Event trigger indicator (Phase 3 - shows current audio event)
            if (isSpinning && currentStage != null)
              Positioned(
                top: MediaQuery.of(context).size.height * 0.15,
                left: 0,
                right: 0,
                child: Center(
                  child: _EventTriggerIndicator(currentEvent: currentStage),
                ),
              ),

            // Balance display (top center)
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Semantics(
                  label: 'Balance: ${_sessionBalance.toStringAsFixed(0)} credits',
                  child: _buildBalanceDisplay(),
                ),
              ),
            ),

            // Free spin counter badge (shows during free spins)
            if (_isFreeSpin)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildFreeSpinBadge(),
                ),
              ),

            // Bet controls (bottom, responsive positioning next to spin button)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BetControls(
                      betAmount: _currentBet,
                      balance: _sessionBalance,
                      isSpinning: isSpinning,
                      onBetChanged: (bet) {
                        setState(() => _currentBet = bet);
                        provider.setBetAmount(bet);
                      },
                    ),
                    const SizedBox(width: 100), // Space for spin button
                  ],
                ),
              ),
            ),

            // SPIN button with pulse
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Semantics(
                  label: isSpinning
                      ? 'Spinning, please wait'
                      : 'Spin button. Current bet: ${_currentBet.toStringAsFixed(0)} credits. Press space to spin.',
                  button: true,
                  enabled: !isSpinning && _currentBet <= _sessionBalance,
                  child: _buildSpinButton(provider),
                ),
              ),
            ),

            // Mini stage trace (Phase 3 - left side)
            if (_showDebugOverlay)
              Positioned(
                top: 70,
                left: 20,
                child: _MiniStageTrace(
                  stages: stages,
                  currentIndex: _currentStageIndex,
                  isPlaying: isSpinning,
                ),
              ),

            // Audio level meter (Phase 3 - left side below trace)
            if (_showDebugOverlay)
              Positioned(
                top: 70 + (stages.isEmpty ? 50 : 200),
                left: 20,
                child: _AudioLevelMeter(isPlaying: isSpinning),
              ),

            // Session stats panel (Phase 4 - right side)
            if (_showStatsPanel)
              Positioned(
                top: 70,
                right: 20,
                child: _SessionStatsPanel(
                  spinCount: _wins + _losses,
                  balance: _sessionBalance,
                  totalBet: _totalBet,
                  totalWin: _totalWin,
                  rtp: sessionRtp,
                  wins: _wins,
                  losses: _losses,
                ),
              ),

            // Debug overlay (basic - right side when stats hidden)
            if (_showDebugOverlay && !_showStatsPanel)
              Positioned(
                top: 70,
                right: 20,
                child: _buildDebugOverlay(provider),
              ),

            // Jackpot celebration overlay
            if (_isJackpotCelebration)
              Positioned.fill(
                child: _buildJackpotCelebration(),
              ),

            // Control hints
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _hintsOpacity,
                builder: (context, child) {
                  return Opacity(
                    opacity: 1.0 - _hintsOpacity.value,
                    child: _buildControlHints(),
                  );
                },
              ),
            ),

            // Exit button (always visible, top-left)
            Positioned(
              top: 20,
              left: 20,
              child: _buildExitButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceDisplay() {
    return AnimatedBuilder(
      animation: _balanceGlowController,
      builder: (context, child) {
        final glowIntensity = _balanceGlowController.value;
        final isGlowing = _balanceGlowColor != Colors.transparent && glowIntensity > 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isGlowing
                  ? _balanceGlowColor.withOpacity(0.8 * (1 - glowIntensity))
                  : const Color(0xFF3a3a48),
              width: isGlowing ? 2 : 1,
            ),
            boxShadow: isGlowing
                ? [
                    BoxShadow(
                      color: _balanceGlowColor.withOpacity(0.5 * (1 - glowIntensity)),
                      blurRadius: 12 * (1 - glowIntensity),
                      spreadRadius: 2 * (1 - glowIntensity),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Text(
                '\$${_sessionBalance.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJackpotCelebration() {
    // Premium jackpot celebration overlay
    final jackpotColor = switch (_jackpotTier) {
      'GRAND' => const Color(0xFFFFD700), // Gold
      'MAJOR' => const Color(0xFFFF4080), // Magenta
      'MINOR' => const Color(0xFF8B5CF6), // Purple
      'MINI' => const Color(0xFF4CAF50), // Green
      _ => const Color(0xFFFFD700),
    };

    return AnimatedBuilder(
      animation: _frameGlowController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.8,
              colors: [
                jackpotColor.withOpacity(0.3 * _frameGlowAnimation.value),
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Jackpot tier badge
                Transform.scale(
                  scale: 0.9 + (_frameGlowAnimation.value * 0.2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          jackpotColor,
                          jackpotColor.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: jackpotColor.withOpacity(0.6 * _frameGlowAnimation.value),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      '$_jackpotTier JACKPOT!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Jackpot amount
                Text(
                  '\$${_jackpotAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    shadows: [
                      Shadow(color: jackpotColor, blurRadius: 20),
                      const Shadow(color: Colors.black54, blurRadius: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFreeSpinBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFE040FB)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE040FB).withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            'FREE SPINS',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_freeSpinsRemaining',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    // Purple-tinted background during free spins
    final bgColors = _isFreeSpin
        ? [
            const Color(0xFF2a1a38), // Purple tint
            const Color(0xFF140a18),
            const Color(0xFF08050a),
          ]
        : [
            const Color(0xFF1a1a28),
            const Color(0xFF0a0a12),
            const Color(0xFF050508),
          ];

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: bgColors,
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      // Vignette overlay
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.5),
            ],
            stops: const [0.4, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotFrame(SlotLabProvider provider) {
    final glowColor = _currentWinTier.isNotEmpty
        ? _getWinColor(_currentWinTier)
        : FluxForgeTheme.accentBlue;

    return AnimatedBuilder(
      animation: _frameGlowAnimation,
      builder: (context, child) {
        final glowIntensity = _currentWinTier.isNotEmpty
            ? _frameGlowAnimation.value
            : 0.3 + _frameGlowAnimation.value * 0.2;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: glowColor.withOpacity(glowIntensity),
              width: _currentWinTier.isNotEmpty ? 4 : 3,
            ),
            boxShadow: [
              // Outer glow
              BoxShadow(
                color: glowColor.withOpacity(glowIntensity * 0.4),
                blurRadius: _currentWinTier.isNotEmpty ? 60 : 40,
                spreadRadius: _currentWinTier.isNotEmpty ? 15 : 10,
              ),
              // Inner shadow
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 60,
                spreadRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SlotPreviewWidget(
              provider: provider,
              reels: widget.reels,
              rows: widget.rows,
            ),
          ),
        );
      },
    );
  }

  Widget _buildWinBadge() {
    final color = _getWinColor(_currentWinTier);
    final tierColors = switch (_currentWinTier) {
      'ULTRA' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'EPIC' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'MEGA' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'BIG' => [const Color(0xFF40FF90), const Color(0xFF88FF88), const Color(0xFFFFEB3B)],
      _ => [FluxForgeTheme.accentGreen, FluxForgeTheme.accentGreen],
    };

    // Colorblind-friendly icons to distinguish win tiers (in addition to color)
    final tierIcon = switch (_currentWinTier) {
      'ULTRA' => Icons.auto_awesome, // Star burst
      'EPIC' => Icons.bolt,          // Lightning bolt
      'MEGA' => Icons.stars,         // Stars
      'BIG' => Icons.celebration,    // Confetti
      _ => Icons.check_circle,       // Check mark
    };

    return AnimatedBuilder(
      animation: _frameGlowAnimation,
      builder: (context, _) {
        final scale = 0.95 + _frameGlowAnimation.value * 0.1;
        return Transform.scale(
          scale: scale,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: tierColors),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.6),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tierIcon,
                    color: Colors.white,
                    size: 24,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$_currentWinTier WIN!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    tierIcon,
                    color: Colors.white,
                    size: 24,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpinButton(SlotLabProvider provider) {
    final isSpinning = provider.isPlayingStages;
    final canSpin = _sessionBalance >= _currentBet && !isSpinning;

    return AnimatedBuilder(
      animation: _spinButtonPulse,
      builder: (context, _) {
        final scale = isSpinning ? 1.0 : _spinButtonPulse.value;

        return Transform.scale(
          scale: scale,
          child: _FocusableButton(
            enabled: canSpin,
            onTap: () => _handleSpin(provider),
            builder: (context, isFocused) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: !canSpin
                      ? [const Color(0xFF3a3a48), const Color(0xFF2a2a38)]
                      : [FluxForgeTheme.accentBlue, const Color(0xFF2060CC)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isFocused
                      ? Colors.white
                      : !canSpin
                          ? const Color(0xFF4a4a58)
                          : FluxForgeTheme.accentBlue.withOpacity(0.8),
                  width: isFocused ? 3 : 2,
                ),
                boxShadow: [
                  if (isFocused)
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  if (canSpin && !isFocused)
                    BoxShadow(
                      color: FluxForgeTheme.accentBlue.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSpinning) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    isSpinning
                        ? 'SPINNING...'
                        : _sessionBalance < _currentBet
                            ? 'NO FUNDS'
                            : 'SPIN',
                    style: TextStyle(
                      color: canSpin ? Colors.white : Colors.white54,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugOverlay(SlotLabProvider provider) {
    final stages = provider.lastStages;
    final result = provider.lastResult;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.bug_report, color: FluxForgeTheme.accentOrange, size: 16),
              const SizedBox(width: 8),
              const Text(
                'DEBUG OVERLAY',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF3a3a48), height: 16),

          // Stage trace
          const Text(
            'STAGE TRACE',
            style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          if (stages.isEmpty)
            const Text(
              'No stages',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            )
          else
            ...stages.take(8).map((stage) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _getStageColor(stage.stageType),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stage.stageType.toUpperCase(),
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${stage.timestampMs}ms',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                )),

          if (stages.length > 8)
            Text(
              '+${stages.length - 8} more...',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),

          const SizedBox(height: 12),

          // Result info
          if (result != null) ...[
            const Text(
              'LAST RESULT',
              style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            _buildResultRow('Win', result.isWin ? 'YES' : 'NO',
                result.isWin ? FluxForgeTheme.accentGreen : Colors.white38),
            _buildResultRow('Total', result.totalWin.toStringAsFixed(0),
                result.totalWin > 0 ? FluxForgeTheme.accentOrange : Colors.white38),
            _buildResultRow('Lines', '${result.lineWins.length}', Colors.white54),
            _buildResultRow('Tier', _currentWinTier.isEmpty ? '-' : _currentWinTier,
                _getWinColor(_currentWinTier)),
          ],
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(value, style: TextStyle(color: valueColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _getStageColor(String stageType) {
    final type = stageType.toLowerCase();
    if (type.contains('spin')) return FluxForgeTheme.accentBlue;
    if (type.contains('reel')) return FluxForgeTheme.accentCyan;
    if (type.contains('win')) return FluxForgeTheme.accentGreen;
    if (type.contains('anticipation')) return FluxForgeTheme.accentOrange;
    if (type.contains('jackpot')) return const Color(0xFFFFD700);
    if (type.contains('feature') || type.contains('free')) return const Color(0xFFE040FB);
    return Colors.white54;
  }

  Widget _buildControlHints() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildHintChip('ESC', 'Exit'),
          const SizedBox(width: 12),
          _buildHintChip('SPACE', 'Spin'),
          const SizedBox(width: 12),
          _buildHintChip('D', 'Debug'),
          const SizedBox(width: 12),
          _buildHintChip('S', 'Stats'),
          const SizedBox(width: 12),
          _buildHintChip('+/-', 'Bet'),
          const SizedBox(width: 12),
          _buildHintChip('1-0', 'Forced'),
          const SizedBox(width: 12),
          _buildHintChip('H', 'Hints'),
        ],
      ),
    );
  }

  Widget _buildHintChip(String key, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2a2a38),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF3a3a48)),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          action,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildExitButton() {
    return _FocusableButton(
      enabled: true,
      onTap: widget.onExit,
      builder: (context, isFocused) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFocused ? Colors.white : const Color(0xFF3a3a48),
            width: isFocused ? 2 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back,
              color: isFocused ? Colors.white : Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              'EXIT',
              style: TextStyle(
                color: isFocused ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
