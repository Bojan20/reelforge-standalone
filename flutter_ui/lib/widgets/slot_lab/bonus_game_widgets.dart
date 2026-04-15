/// Bonus Game Widgets — Interactive UI for bonus round mechanics
///
/// Contains complete implementations for all bonus game types:
/// - PickGameWidget: Pick-and-click grid with reveal animation
/// - WheelGameWidget: Spinning wheel of fortune
/// - TrailGameWidget: Board game trail with dice roll
/// - LadderGameWidget: Climbing ladder with risk/collect
/// - JackpotTickerWidget: Progressive jackpot value tickers
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/game_flow_models.dart';
import '../../providers/slot_lab/game_flow_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PICK GAME WIDGET — Grid of clickable items that reveal prizes
// ═══════════════════════════════════════════════════════════════════════════

class PickGameWidget extends StatelessWidget {
  final FeatureState state;
  final GameFlowProvider flow;

  const PickGameWidget({
    super.key,
    required this.state,
    required this.flow,
  });

  @override
  Widget build(BuildContext context) {
    final totalPicks = state.customData['totalPicks'] as int? ?? 12;
    final revealedItems = List<int>.from(
        state.customData['revealedItems'] as List<dynamic>? ?? []);
    final columns = totalPicks <= 6 ? 3 : (totalPicks <= 12 ? 4 : 5);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PICK ${state.picksRemaining} MORE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Prize: ${state.accumulatedPrize.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pick grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: totalPicks,
              itemBuilder: (context, index) {
                final isRevealed = revealedItems.contains(index);
                return _PickItem(
                  index: index,
                  isRevealed: isRevealed,
                  canPick: !isRevealed && state.picksRemaining > 0,
                  onPick: () {
                    flow.triggerManual(
                      TransitionTrigger.playerPick,
                      context: {'pickIndex': index},
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PickItem extends StatelessWidget {
  final int index;
  final bool isRevealed;
  final bool canPick;
  final VoidCallback onPick;

  const _PickItem({
    required this.index,
    required this.isRevealed,
    required this.canPick,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (isRevealed) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.star, color: Colors.white, size: 32),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canPick ? onPick : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: canPick
                  ? [const Color(0xFF6A1B9A), const Color(0xFF4A148C)]
                  : [Colors.grey.shade800, Colors.grey.shade900],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: canPick
                  ? const Color(0xFF9C27B0).withValues(alpha: 0.5)
                  : Colors.grey.shade700,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.help_outline,
              color: canPick ? Colors.white70 : Colors.grey.shade600,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WHEEL GAME WIDGET — Spinning wheel of fortune
// ═══════════════════════════════════════════════════════════════════════════

class WheelGameWidget extends StatefulWidget {
  final FeatureState state;
  final GameFlowProvider flow;

  const WheelGameWidget({
    super.key,
    required this.state,
    required this.flow,
  });

  @override
  State<WheelGameWidget> createState() => _WheelGameWidgetState();
}

class _WheelGameWidgetState extends State<WheelGameWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  bool _isSpinning = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _spinWheel() {
    if (_isSpinning) return;
    setState(() => _isSpinning = true);

    _spinController.forward(from: 0).then((_) {
      setState(() => _isSpinning = false);
      widget.flow.triggerManual(
        TransitionTrigger.playerPick,
        context: {'wheelResult': true},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.state.customData['wheelSegments'] as int? ?? 8;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Wheel
        Expanded(
          child: Center(
            child: SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Wheel background
                  AnimatedBuilder(
                    animation: _spinController,
                    builder: (context, child) {
                      final rotations = 3 + _spinController.value * 5;
                      return Transform.rotate(
                        angle: rotations * 2 * math.pi,
                        child: child,
                      );
                    },
                    child: CustomPaint(
                      size: const Size(280, 280),
                      painter: _WheelPainter(segments: segments),
                    ),
                  ),
                  // Center hub
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.star, color: Colors.white, size: 24),
                  ),
                  // Pointer
                  Positioned(
                    top: 0,
                    child: Icon(
                      Icons.arrow_drop_down,
                      color: Colors.red.shade400,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Spin button
        Padding(
          padding: const EdgeInsets.all(24),
          child: ElevatedButton(
            onPressed: _isSpinning ? null : _spinWheel,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9C27B0),
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Text(
              _isSpinning ? 'SPINNING...' : 'SPIN WHEEL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),

        // Level indicator
        Text(
          'Level ${widget.state.currentLevel + 1} / ${widget.state.totalLevels}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final int segments;

  _WheelPainter({required this.segments});

  static const _segmentColors = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFFF44336),
    Color(0xFF00BCD4),
    Color(0xFFFFD700),
    Color(0xFFE91E63),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = 2 * math.pi / segments;

    for (int i = 0; i < segments; i++) {
      final paint = Paint()
        ..color = _segmentColors[i % _segmentColors.length]
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 + (i * segmentAngle),
        segmentAngle,
        true,
        paint,
      );

      // Segment border
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 + (i * segmentAngle),
        segmentAngle,
        true,
        borderPaint,
      );
    }

    // Outer ring
    final ringPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, ringPaint);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.segments != segments;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRAIL GAME WIDGET — Board game trail with dice
// ═══════════════════════════════════════════════════════════════════════════

class TrailGameWidget extends StatelessWidget {
  final FeatureState state;
  final GameFlowProvider flow;

  const TrailGameWidget({
    super.key,
    required this.state,
    required this.flow,
  });

  @override
  Widget build(BuildContext context) {
    final trailLength = state.customData['trailLength'] as int? ?? 20;
    final currentPos = state.customData['trailPosition'] as int? ?? 0;
    final progress = trailLength > 0 ? currentPos / trailLength : 0.0;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'POSITION: ${currentPos + 1} / $trailLength',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Prize: ${state.accumulatedPrize.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Trail visualization
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF4CAF50),
                    ),
                    minHeight: 12,
                  ),
                ),
                const SizedBox(height: 24),

                // Trail dots
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: trailLength.clamp(0, 30),
                    itemBuilder: (context, i) {
                      final isCurrent = i == currentPos;
                      final isPassed = i < currentPos;

                      return Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? const Color(0xFFFFD700)
                              : isPassed
                                  ? const Color(0xFF4CAF50)
                                  : Colors.white.withValues(alpha: 0.15),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFFFD700)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: isCurrent
                            ? const Icon(Icons.person, color: Colors.white, size: 14)
                            : isPassed
                                ? const Icon(Icons.check, color: Colors.white, size: 12)
                                : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Roll button
        Padding(
          padding: const EdgeInsets.all(24),
          child: ElevatedButton.icon(
            onPressed: () => flow.triggerManual(
              TransitionTrigger.playerPick,
              context: {'trailRoll': true},
            ),
            icon: const Icon(Icons.casino, color: Colors.white),
            label: const Text(
              'ROLL DICE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9C27B0),
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LADDER GAME WIDGET — Risk/collect ladder climb
// ═══════════════════════════════════════════════════════════════════════════

class LadderGameWidget extends StatelessWidget {
  final FeatureState state;
  final GameFlowProvider flow;

  const LadderGameWidget({
    super.key,
    required this.state,
    required this.flow,
  });

  @override
  Widget build(BuildContext context) {
    final totalRungs = state.customData['ladderRungs'] as int? ?? 10;
    final currentRung = state.customData['ladderRung'] as int? ?? 0;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'RUNG ${currentRung + 1} / $totalRungs',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),

        // Ladder visualization
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: ListView.builder(
              reverse: true,
              itemCount: totalRungs,
              itemBuilder: (context, index) {
                final rungIndex = totalRungs - 1 - index;
                final isCurrent = rungIndex == currentRung;
                final isPassed = rungIndex < currentRung;

                return Container(
                  height: 36,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isCurrent
                          ? [const Color(0xFFFFD700), const Color(0xFFFF8F00)]
                          : isPassed
                              ? [
                                  const Color(0xFF4CAF50).withValues(alpha: 0.6),
                                  const Color(0xFF4CAF50).withValues(alpha: 0.3),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.08),
                                  Colors.white.withValues(alpha: 0.04),
                                ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: isCurrent
                        ? Border.all(color: const Color(0xFFFFD700), width: 2)
                        : null,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Text(
                        '${rungIndex + 1}',
                        style: TextStyle(
                          color: isCurrent || isPassed
                              ? Colors.white
                              : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (isCurrent)
                        const Icon(Icons.arrow_right, color: Colors.white, size: 20),
                      if (rungIndex == totalRungs - 1)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.emoji_events,
                              color: Color(0xFFFFD700), size: 18),
                        ),
                      const SizedBox(width: 8),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Actions
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Collect
              ElevatedButton(
                onPressed: () => flow.triggerManual(
                  TransitionTrigger.playerCollect,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'COLLECT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Climb
              ElevatedButton(
                onPressed: () => flow.triggerManual(
                  TransitionTrigger.playerPick,
                  context: {'ladderClimb': true},
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF44336),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'CLIMB',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// JACKPOT TICKER WIDGET — Progressive jackpot value display
// ═══════════════════════════════════════════════════════════════════════════

class JackpotTickerWidget extends StatefulWidget {
  final List<({String name, double value})> tiers;

  const JackpotTickerWidget({
    super.key,
    required this.tiers,
  });

  @override
  State<JackpotTickerWidget> createState() => _JackpotTickerWidgetState();
}

class _JackpotTickerWidgetState extends State<JackpotTickerWidget> {
  Timer? _tickerTimer;
  final List<double> _displayValues = [];

  static const _tierColors = [
    Color(0xFF795548), // Mini — bronze
    Color(0xFF9E9E9E), // Minor — silver
    Color(0xFFFFD700), // Major — gold
    Color(0xFFE91E63), // Grand — rose
  ];

  @override
  void initState() {
    super.initState();
    _displayValues.addAll(widget.tiers.map((t) => t.value));

    // Ticker animation — progressive growth per tier.
    // Growth rates are INVERSELY proportional to tier size:
    //   Mini  (i=0) grows fastest  — small jackpot, frequent contribution
    //   Minor (i=1) grows slower
    //   Major (i=2) grows very slow
    //   Grand (i=3) grows slowest  — rare, huge jackpot
    // At 50ms interval: Mini ≈ +0.60/s, Minor ≈ +0.20/s, Major ≈ +0.06/s, Grand ≈ +0.02/s
    const _tierGrowthRates = [0.030, 0.010, 0.003, 0.001];

    _tickerTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _displayValues.length; i++) {
          final rate = i < _tierGrowthRates.length ? _tierGrowthRates[i] : 0.001;
          _displayValues[i] += rate;
        }
      });
    });
  }

  @override
  void didUpdateWidget(JackpotTickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync when tiers update
    while (_displayValues.length < widget.tiers.length) {
      _displayValues.add(widget.tiers[_displayValues.length].value);
    }
    for (int i = 0; i < widget.tiers.length && i < _displayValues.length; i++) {
      if (_displayValues[i] < widget.tiers[i].value) {
        _displayValues[i] = widget.tiers[i].value;
      }
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(widget.tiers.length, (i) {
        final tier = widget.tiers[i];
        final color = i < _tierColors.length ? _tierColors[i] : _tierColors.last;
        final value =
            i < _displayValues.length ? _displayValues[i] : tier.value;

        return _JackpotTierCell(
          name: tier.name,
          value: value,
          color: color,
          isGrand: i == widget.tiers.length - 1,
        );
      }),
    );
  }
}

class _JackpotTierCell extends StatelessWidget {
  final String name;
  final double value;
  final Color color;
  final bool isGrand;

  const _JackpotTierCell({
    required this.name,
    required this.value,
    required this.color,
    this.isGrand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: isGrand ? 11 : 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              color: Colors.white,
              fontSize: isGrand ? 14 : 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
