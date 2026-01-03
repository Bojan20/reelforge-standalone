/// Professional Audio Knob Widget
///
/// Rotary control with:
/// - Smooth arc visualization
/// - Value tooltip on drag
/// - Double-tap to reset
/// - Bipolar mode for pan

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

class MiniKnob extends StatefulWidget {
  /// Current value (0-1 for unipolar, -1 to 1 for bipolar)
  final double value;

  /// Called when value changes
  final ValueChanged<double>? onChanged;

  /// Knob size (diameter)
  final double size;

  /// Bipolar mode (center is zero)
  final bool bipolar;

  /// Accent color for the arc
  final Color? accentColor;

  /// Default value for double-tap reset
  final double defaultValue;

  /// Show value label on drag
  final bool showValueOnDrag;

  const MiniKnob({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 40,
    this.bipolar = false,
    this.accentColor,
    this.defaultValue = 0,
    this.showValueOnDrag = true,
  });

  @override
  State<MiniKnob> createState() => _MiniKnobState();
}

class _MiniKnobState extends State<MiniKnob>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  bool _isHovered = false;
  double _dragStartValue = 0;
  double _dragStartY = 0;

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? ReelForgeTheme.accentBlue;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onDoubleTap: () {
          widget.onChanged?.call(widget.defaultValue);
        },
        onVerticalDragStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartValue = widget.value;
            _dragStartY = details.globalPosition.dy;
          });
        },
        onVerticalDragUpdate: (details) {
          if (widget.onChanged == null) return;

          final delta = (_dragStartY - details.globalPosition.dy) / 100;
          double newValue;

          if (widget.bipolar) {
            newValue = (_dragStartValue + delta).clamp(-1.0, 1.0);
          } else {
            newValue = (_dragStartValue + delta).clamp(0.0, 1.0);
          }

          widget.onChanged!(newValue);
        },
        onVerticalDragEnd: (_) {
          setState(() => _isDragging = false);
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _KnobPainter(
              value: widget.value,
              bipolar: widget.bipolar,
              color: color,
              isHovered: _isHovered,
              isDragging: _isDragging,
            ),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final bool bipolar;
  final Color color;
  final bool isHovered;
  final bool isDragging;

  static const double startAngle = 135 * math.pi / 180;
  static const double sweepAngle = 270 * math.pi / 180;

  _KnobPainter({
    required this.value,
    required this.bipolar,
    required this.color,
    required this.isHovered,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background circle
    final bgPaint = Paint()
      ..color = ReelForgeTheme.bgDeepest
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Track arc (background)
    final trackPaint = Paint()
      ..color = ReelForgeTheme.bgElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    if (bipolar) {
      // Bipolar: draw from center
      final centerAngle = startAngle + sweepAngle / 2;
      final valueAngle = value * (sweepAngle / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4),
        centerAngle,
        valueAngle,
        false,
        valuePaint,
      );
    } else {
      // Unipolar: draw from start
      final valueAngle = value * sweepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4),
        startAngle,
        valueAngle,
        false,
        valuePaint,
      );
    }

    // Indicator dot
    final normalizedValue = bipolar ? (value + 1) / 2 : value;
    final indicatorAngle = startAngle + normalizedValue * sweepAngle;
    final indicatorRadius = radius - 4;
    final indicatorPos = Offset(
      center.dx + indicatorRadius * math.cos(indicatorAngle),
      center.dy + indicatorRadius * math.sin(indicatorAngle),
    );

    final indicatorPaint = Paint()
      ..color = ReelForgeTheme.textPrimary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(indicatorPos, isDragging ? 4 : 3, indicatorPaint);

    // Glow when dragging
    if (isDragging || isHovered) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, radius, glowPaint);
    }

    // Border
    final borderPaint = Paint()
      ..color = isDragging
          ? color
          : isHovered
              ? ReelForgeTheme.borderMedium
              : ReelForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) =>
      value != oldDelegate.value ||
      isHovered != oldDelegate.isHovered ||
      isDragging != oldDelegate.isDragging;
}

/// Large knob with label and value display
class LargeKnob extends StatefulWidget {
  final String label;
  final double value;
  final String? valueText;
  final ValueChanged<double>? onChanged;
  final double size;
  final bool bipolar;
  final Color? accentColor;

  const LargeKnob({
    super.key,
    required this.label,
    required this.value,
    this.valueText,
    this.onChanged,
    this.size = 60,
    this.bipolar = false,
    this.accentColor,
  });

  @override
  State<LargeKnob> createState() => _LargeKnobState();
}

class _LargeKnobState extends State<LargeKnob> {
  bool _isDragging = false;

  String get _displayValue {
    if (widget.valueText != null) return widget.valueText!;

    if (widget.bipolar) {
      final percent = (widget.value * 100).round();
      if (percent == 0) return 'C';
      return percent > 0 ? 'R$percent' : 'L${percent.abs()}';
    } else {
      return '${(widget.value * 100).round()}%';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: ReelForgeTheme.label),
        const SizedBox(height: 4),
        GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          child: MiniKnob(
            value: widget.value,
            onChanged: widget.onChanged,
            size: widget.size,
            bipolar: widget.bipolar,
            accentColor: widget.accentColor,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedDefaultTextStyle(
          duration: ReelForgeTheme.fastDuration,
          style: ReelForgeTheme.monoSmall.copyWith(
            color: _isDragging
                ? (widget.accentColor ?? ReelForgeTheme.accentBlue)
                : ReelForgeTheme.textSecondary,
          ),
          child: Text(_displayValue),
        ),
      ],
    );
  }
}
