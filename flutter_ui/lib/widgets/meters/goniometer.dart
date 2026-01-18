// Goniometer / Lissajous Display Widget
//
// Professional stereo phase visualization showing:
// - L/R correlation as Lissajous figure
// - Phase relationship between channels
// - Stereo width visualization
// - Peak hold traces
// - Grid with +45/-45 degree lines

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Goniometer configuration
class GoniometerConfig {
  final Color traceColor;
  final Color peakColor;
  final Color gridColor;
  final Color backgroundColor;
  final double lineWidth;
  final double fadeRate;
  final int historyLength;
  final bool showGrid;
  final bool showLabels;
  final bool showPeakHold;

  const GoniometerConfig({
    this.traceColor = const Color(0xFF4AFFFF),
    this.peakColor = const Color(0xFFFF6B4A),
    this.gridColor = const Color(0xFF2A2A35),
    this.backgroundColor = const Color(0xFF0A0A0E),
    this.lineWidth = 1.5,
    this.fadeRate = 0.95,
    this.historyLength = 512,
    this.showGrid = true,
    this.showLabels = true,
    this.showPeakHold = true,
  });
}

/// Goniometer Widget
class Goniometer extends StatefulWidget {
  /// Left channel samples (normalized -1 to 1)
  final Float64List? leftData;

  /// Right channel samples (normalized -1 to 1)
  final Float64List? rightData;

  /// Configuration
  final GoniometerConfig config;

  /// Size
  final double? size;

  const Goniometer({
    super.key,
    this.leftData,
    this.rightData,
    this.config = const GoniometerConfig(),
    this.size,
  });

  @override
  State<Goniometer> createState() => _GoniometerState();
}

class _GoniometerState extends State<Goniometer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // History buffer for persistence effect
  List<List<Offset>> _history = [];

  // Peak hold positions
  double _maxX = 0;
  double _minX = 0;
  double _maxY = 0;
  double _minY = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateDisplay);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateDisplay() {
    if (widget.leftData == null || widget.rightData == null) return;

    final left = widget.leftData!;
    final right = widget.rightData!;
    final len = math.min(left.length, right.length);

    if (len == 0) return;

    // Convert L/R to M/S (rotated 45 degrees)
    final points = <Offset>[];
    for (int i = 0; i < len; i++) {
      final l = left[i];
      final r = right[i];

      // Mid = (L + R) / 2, Side = (L - R) / 2
      // Rotated display: x = Side, y = Mid
      final x = (l - r) / 2; // Side (width)
      final y = (l + r) / 2; // Mid (center)

      points.add(Offset(x, y));

      // Update peak hold
      if (x > _maxX) _maxX = x;
      if (x < _minX) _minX = x;
      if (y > _maxY) _maxY = y;
      if (y < _minY) _minY = y;
    }

    // Add to history
    _history.insert(0, points);
    if (_history.length > widget.config.historyLength ~/ 64) {
      _history.removeLast();
    }

    // Decay peak hold
    _maxX *= 0.999;
    _minX *= 0.999;
    _maxY *= 0.999;
    _minY *= 0.999;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = widget.size ?? math.min(constraints.maxWidth, constraints.maxHeight);

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: widget.config.backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.config.gridColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: CustomPaint(
              size: Size(size, size),
              painter: _GoniometerPainter(
                history: _history,
                maxX: _maxX,
                minX: _minX,
                maxY: _maxY,
                minY: _minY,
                config: widget.config,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoniometerPainter extends CustomPainter {
  final List<List<Offset>> history;
  final double maxX, minX, maxY, minY;
  final GoniometerConfig config;

  _GoniometerPainter({
    required this.history,
    required this.maxX,
    required this.minX,
    required this.maxY,
    required this.minY,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 2.5;

    // Draw grid
    if (config.showGrid) {
      _drawGrid(canvas, size, center, scale);
    }

    // Draw traces with fade effect
    for (int h = 0; h < history.length; h++) {
      final alpha = ((1.0 - h / history.length) * 255 * config.fadeRate).toInt();
      final paint = Paint()
        ..color = config.traceColor.withAlpha(alpha)
        ..strokeWidth = config.lineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final points = history[h];
      if (points.isEmpty) continue;

      final path = Path();
      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final x = center.dx + p.dx * scale;
        final y = center.dy - p.dy * scale;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw peak hold box
    if (config.showPeakHold) {
      final peakPaint = Paint()
        ..color = config.peakColor.withAlpha(128)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      final peakRect = Rect.fromLTRB(
        center.dx + minX * scale,
        center.dy - maxY * scale,
        center.dx + maxX * scale,
        center.dy - minY * scale,
      );

      canvas.drawRect(peakRect, peakPaint);
    }

    // Draw labels
    if (config.showLabels) {
      _drawLabels(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size, Offset center, double scale) {
    final gridPaint = Paint()
      ..color = config.gridColor
      ..strokeWidth = 1;

    // Circle guides
    for (double r = 0.25; r <= 1.0; r += 0.25) {
      canvas.drawCircle(center, r * scale, gridPaint);
    }

    // Cross lines (0 and 90 degrees - L/R and M/S axes)
    canvas.drawLine(
      Offset(center.dx - scale, center.dy),
      Offset(center.dx + scale, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - scale),
      Offset(center.dx, center.dy + scale),
      gridPaint,
    );

    // Diagonal lines (+45 and -45 degrees - L and R)
    final diag = scale * 0.707; // cos(45)
    canvas.drawLine(
      Offset(center.dx - diag, center.dy - diag),
      Offset(center.dx + diag, center.dy + diag),
      gridPaint..color = config.gridColor.withAlpha(77),
    );
    canvas.drawLine(
      Offset(center.dx + diag, center.dy - diag),
      Offset(center.dx - diag, center.dy + diag),
      gridPaint,
    );
  }

  void _drawLabels(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: config.gridColor.withAlpha(200),
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    // L label (top-left diagonal)
    _drawText(canvas, 'L', Offset(8, 8), textStyle);

    // R label (top-right diagonal)
    _drawText(canvas, 'R', Offset(size.width - 16, 8), textStyle);

    // M label (top center)
    _drawText(canvas, 'M', Offset(size.width / 2 - 4, 4), textStyle);

    // S label (right center)
    _drawText(canvas, 'S', Offset(size.width - 14, size.height / 2 - 6), textStyle);

    // +/- labels
    _drawText(canvas, '+', Offset(size.width / 2 - 4, size.height / 2 - size.height / 3), textStyle);
    _drawText(canvas, '-', Offset(size.width / 2 - 4, size.height / 2 + size.height / 3 - 12), textStyle);
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _GoniometerPainter oldDelegate) {
    return history != oldDelegate.history;
  }
}
