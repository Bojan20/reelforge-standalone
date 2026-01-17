/// Volatility Dial Widget for Slot Lab
///
/// Premium analog-style dial for controlling slot volatility:
/// - Visual scale: Casual → Medium → High → Insane
/// - Color gradient: green → yellow → orange → red
/// - Animated glow on current value
/// - Affects spin outcome probabilities

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Volatility levels
enum VolatilityLevel {
  casual(0, 'CASUAL', Color(0xFF40FF90)),
  low(1, 'LOW', Color(0xFF80FF60)),
  medium(2, 'MEDIUM', Color(0xFFF1C40F)),
  high(3, 'HIGH', Color(0xFFFF9040)),
  insane(4, 'INSANE', Color(0xFFFF4040));

  final int value;
  final String label;
  final Color color;

  const VolatilityLevel(this.value, this.label, this.color);
}

/// Volatility Dial Widget
class VolatilityDial extends StatefulWidget {
  final VolatilityLevel initialLevel;
  final ValueChanged<VolatilityLevel>? onChanged;
  final double size;

  const VolatilityDial({
    super.key,
    this.initialLevel = VolatilityLevel.medium,
    this.onChanged,
    this.size = 120,
  });

  @override
  State<VolatilityDial> createState() => _VolatilityDialState();
}

class _VolatilityDialState extends State<VolatilityDial> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late VolatilityLevel _currentLevel;
  double _dragAngle = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentLevel = widget.initialLevel;
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _updateFromDrag(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    // Calculate angle from center
    double angle = math.atan2(dy, dx);

    // Convert to 0-360 range starting from top
    angle = (angle + math.pi / 2) % (2 * math.pi);
    if (angle < 0) angle += 2 * math.pi;

    // Map angle to volatility (use 270 degree arc from -45 to 225 degrees)
    // Normalize angle to 0-1 range within the valid arc
    const startAngle = -math.pi / 4; // -45 degrees
    const endAngle = 5 * math.pi / 4; // 225 degrees
    const arcRange = endAngle - startAngle;

    double normalizedAngle = ((angle + math.pi / 2 - startAngle) % (2 * math.pi)) / arcRange;
    normalizedAngle = normalizedAngle.clamp(0.0, 1.0);

    // Map to volatility level
    final levelIndex = (normalizedAngle * 4).round().clamp(0, 4);
    final newLevel = VolatilityLevel.values[levelIndex];

    if (newLevel != _currentLevel) {
      setState(() {
        _currentLevel = newLevel;
      });
      widget.onChanged?.call(newLevel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Dial
        GestureDetector(
          onTapDown: (details) {
            // Allow tap to set level directly
            _updateFromDrag(details.localPosition, Size(widget.size, widget.size));
          },
          onPanStart: (details) {
            setState(() => _isDragging = true);
          },
          onPanUpdate: (details) {
            _updateFromDrag(details.localPosition, Size(widget.size, widget.size));
          },
          onPanEnd: (details) {
            setState(() => _isDragging = false);
          },
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _currentLevel.color.withOpacity(0.3 + _glowController.value * 0.2),
                      blurRadius: 20 + _glowController.value * 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _VolatilityDialPainter(
                    level: _currentLevel,
                    glowValue: _glowController.value,
                    isDragging: _isDragging,
                  ),
                  size: Size(widget.size, widget.size),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Label (tappable to show level selector)
        GestureDetector(
          onTap: () => _showLevelSelector(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _currentLevel.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _currentLevel.color.withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentLevel.label,
                  style: TextStyle(
                    color: _currentLevel.color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 16, color: _currentLevel.color),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Quick level buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: VolatilityLevel.values.map((level) {
            final isSelected = level == _currentLevel;
            return GestureDetector(
              onTap: () {
                setState(() => _currentLevel = level);
                widget.onChanged?.call(level);
              },
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected ? level.color : level.color.withOpacity(0.3),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: level.color.withOpacity(0.5), blurRadius: 6)]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showLevelSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Select Volatility', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: VolatilityLevel.values.map((level) {
            return ListTile(
              onTap: () {
                setState(() => _currentLevel = level);
                widget.onChanged?.call(level);
                Navigator.of(ctx).pop();
              },
              leading: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: level.color,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(level.label, style: TextStyle(color: level.color, fontSize: 12)),
              selected: level == _currentLevel,
              selectedTileColor: level.color.withOpacity(0.1),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Custom painter for the volatility dial
class _VolatilityDialPainter extends CustomPainter {
  final VolatilityLevel level;
  final double glowValue;
  final bool isDragging;

  _VolatilityDialPainter({
    required this.level,
    required this.glowValue,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background ring
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A22)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius + 5, bgPaint);

    // Outer ring
    final outerRingPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, radius + 3, outerRingPaint);

    // Arc segments for each volatility level
    const startAngle = -math.pi * 3 / 4; // Start at -135 degrees
    const sweepPerSegment = math.pi * 1.5 / 5; // 270 degrees / 5 levels

    for (int i = 0; i < 5; i++) {
      final segmentColor = VolatilityLevel.values[i].color;
      final isActive = i <= level.value;

      final arcPaint = Paint()
        ..color = isActive ? segmentColor : segmentColor.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 5),
        startAngle + i * sweepPerSegment + 0.05,
        sweepPerSegment - 0.1,
        false,
        arcPaint,
      );
    }

    // Tick marks
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i <= 5; i++) {
      final angle = startAngle + i * sweepPerSegment;
      final innerRadius = radius - 20;
      final outerRadius = radius - 12;

      final innerPoint = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final outerPoint = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );

      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }

    // Knob center
    final knobGradient = RadialGradient(
      colors: [
        const Color(0xFF3A3A45),
        const Color(0xFF2A2A35),
        const Color(0xFF1A1A25),
      ],
    );

    final knobPaint = Paint()
      ..shader = knobGradient.createShader(
        Rect.fromCircle(center: center, radius: radius - 25),
      );

    canvas.drawCircle(center, radius - 25, knobPaint);

    // Knob highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 27),
      -math.pi,
      math.pi,
      false,
      highlightPaint,
    );

    // Pointer
    final pointerAngle = startAngle + level.value * sweepPerSegment + sweepPerSegment / 2;
    final pointerLength = radius - 35;

    final pointerPaint = Paint()
      ..color = level.color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final pointerEnd = Offset(
      center.dx + pointerLength * math.cos(pointerAngle),
      center.dy + pointerLength * math.sin(pointerAngle),
    );

    canvas.drawLine(center, pointerEnd, pointerPaint);

    // Center dot
    canvas.drawCircle(
      center,
      8,
      Paint()..color = level.color,
    );
    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.white,
    );

    // Dragging indicator
    if (isDragging) {
      canvas.drawCircle(
        center,
        radius + 8,
        Paint()
          ..color = level.color.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolatilityDialPainter oldDelegate) {
    return oldDelegate.level != level ||
           oldDelegate.glowValue != glowValue ||
           oldDelegate.isDragging != isDragging;
  }
}

/// Compact volatility indicator (for toolbars)
class VolatilityIndicator extends StatelessWidget {
  final VolatilityLevel level;
  final VoidCallback? onTap;

  const VolatilityIndicator({
    super.key,
    required this.level,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: level.color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: level.color.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini dial icon
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: level.color, width: 2),
              ),
              child: CustomPaint(
                painter: _MiniDialPainter(level: level),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              level.label,
              style: TextStyle(
                color: level.color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini dial painter for indicator
class _MiniDialPainter extends CustomPainter {
  final VolatilityLevel level;

  _MiniDialPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Pointer
    const startAngle = -math.pi * 3 / 4;
    const sweepPerSegment = math.pi * 1.5 / 5;
    final pointerAngle = startAngle + level.value * sweepPerSegment + sweepPerSegment / 2;

    final pointerEnd = Offset(
      center.dx + 5 * math.cos(pointerAngle),
      center.dy + 5 * math.sin(pointerAngle),
    );

    canvas.drawLine(
      center,
      pointerEnd,
      Paint()
        ..color = level.color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
