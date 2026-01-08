// Stereo Correlation Meter Widget
//
// Professional phase correlation display showing:
// - Correlation coefficient from -1 (out of phase) to +1 (mono)
// - Peak hold with decay
// - Warning zones for phase issues
// - Multiple display modes (bar, arc)

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Correlation meter display mode
enum CorrelationDisplayMode {
  bar,     // Horizontal bar
  arc,     // Arc/semi-circle
}

/// Correlation meter configuration
class CorrelationMeterConfig {
  final CorrelationDisplayMode mode;
  final Color positiveColor;    // Correlated (good)
  final Color warningColor;     // Low correlation
  final Color negativeColor;    // Anti-phase (bad)
  final Color backgroundColor;
  final Color peakColor;
  final bool showPeakHold;
  final bool showLabels;
  final bool showWarningZones;
  final double peakHoldTime;    // seconds
  final double peakDecayRate;

  const CorrelationMeterConfig({
    this.mode = CorrelationDisplayMode.bar,
    this.positiveColor = ReelForgeTheme.accentGreen,
    this.warningColor = ReelForgeTheme.accentYellow,
    this.negativeColor = ReelForgeTheme.accentRed,
    this.backgroundColor = ReelForgeTheme.bgDeepest,
    this.peakColor = ReelForgeTheme.textPrimary,
    this.showPeakHold = true,
    this.showLabels = true,
    this.showWarningZones = true,
    this.peakHoldTime = 2.0,
    this.peakDecayRate = 0.5,
  });
}

/// Correlation Meter Widget
class CorrelationMeter extends StatefulWidget {
  /// Left channel samples
  final Float64List? leftData;

  /// Right channel samples
  final Float64List? rightData;

  /// Alternatively, provide pre-calculated correlation (-1 to 1)
  final double? correlation;

  /// Configuration
  final CorrelationMeterConfig config;

  /// Width (for bar mode)
  final double? width;

  /// Height
  final double? height;

  const CorrelationMeter({
    super.key,
    this.leftData,
    this.rightData,
    this.correlation,
    this.config = const CorrelationMeterConfig(),
    this.width,
    this.height,
  });

  @override
  State<CorrelationMeter> createState() => _CorrelationMeterState();
}

class _CorrelationMeterState extends State<CorrelationMeter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  double _correlation = 0;
  double _peakMin = 0;
  double _peakMax = 0;
  double _peakMinTimer = 0;
  double _peakMaxTimer = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeter);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateMeter() {
    double newCorrelation;

    if (widget.correlation != null) {
      newCorrelation = widget.correlation!;
    } else if (widget.leftData != null && widget.rightData != null) {
      newCorrelation = _calculateCorrelation(widget.leftData!, widget.rightData!);
    } else {
      return;
    }

    // Smooth the correlation value
    _correlation = _correlation * 0.8 + newCorrelation * 0.2;

    // Update peak hold (min = most negative, max = most positive)
    if (_correlation < _peakMin) {
      _peakMin = _correlation;
      _peakMinTimer = widget.config.peakHoldTime;
    } else if (_peakMinTimer > 0) {
      _peakMinTimer -= 0.016;
    } else {
      _peakMin += widget.config.peakDecayRate * 0.016;
      if (_peakMin > 0) _peakMin = 0;
    }

    if (_correlation > _peakMax) {
      _peakMax = _correlation;
      _peakMaxTimer = widget.config.peakHoldTime;
    } else if (_peakMaxTimer > 0) {
      _peakMaxTimer -= 0.016;
    } else {
      _peakMax -= widget.config.peakDecayRate * 0.016;
      if (_peakMax < 0) _peakMax = 0;
    }

    setState(() {});
  }

  double _calculateCorrelation(Float64List left, Float64List right) {
    final len = math.min(left.length, right.length);
    if (len == 0) return 0;

    double sumL = 0, sumR = 0, sumLR = 0;
    double sumL2 = 0, sumR2 = 0;

    for (int i = 0; i < len; i++) {
      final l = left[i];
      final r = right[i];
      sumL += l;
      sumR += r;
      sumLR += l * r;
      sumL2 += l * l;
      sumR2 += r * r;
    }

    final n = len.toDouble();
    final numerator = n * sumLR - sumL * sumR;
    final denominator = math.sqrt((n * sumL2 - sumL * sumL) * (n * sumR2 - sumR * sumR));

    if (denominator == 0) return 0;
    return (numerator / denominator).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.width ?? constraints.maxWidth;
        final height = widget.height ?? constraints.maxHeight;

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: widget.config.backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: ReelForgeTheme.borderSubtle),
          ),
          child: widget.config.mode == CorrelationDisplayMode.bar
              ? _buildBarMeter(width, height)
              : _buildArcMeter(width, height),
        );
      },
    );
  }

  Widget _buildBarMeter(double width, double height) {
    return CustomPaint(
      size: Size(width, height),
      painter: _BarCorrelationPainter(
        correlation: _correlation,
        peakMin: _peakMin,
        peakMax: _peakMax,
        config: widget.config,
      ),
    );
  }

  Widget _buildArcMeter(double width, double height) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ArcCorrelationPainter(
        correlation: _correlation,
        peakMin: _peakMin,
        peakMax: _peakMax,
        config: widget.config,
      ),
    );
  }
}

class _BarCorrelationPainter extends CustomPainter {
  final double correlation;
  final double peakMin;
  final double peakMax;
  final CorrelationMeterConfig config;

  _BarCorrelationPainter({
    required this.correlation,
    required this.peakMin,
    required this.peakMax,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height - (config.showLabels ? 16 : 0);
    final barTop = 0.0;
    final barWidth = size.width - 16;
    final barLeft = 8.0;
    final center = barLeft + barWidth / 2;

    // Draw warning zones
    if (config.showWarningZones) {
      // Negative zone (red)
      canvas.drawRect(
        Rect.fromLTRB(barLeft, barTop, center, barHeight),
        Paint()..color = config.negativeColor.withAlpha(26),
      );

      // Warning zone (near zero)
      final warningWidth = barWidth * 0.2;
      canvas.drawRect(
        Rect.fromLTRB(center - warningWidth, barTop, center + warningWidth, barHeight),
        Paint()..color = config.warningColor.withAlpha(26),
      );
    }

    // Draw scale marks
    final markPaint = Paint()
      ..color = ReelForgeTheme.borderMedium
      ..strokeWidth = 1;

    for (double v = -1; v <= 1; v += 0.25) {
      final x = center + (v * barWidth / 2);
      canvas.drawLine(Offset(x, barTop), Offset(x, barHeight), markPaint);
    }

    // Draw correlation bar
    final barPaint = Paint();
    if (correlation >= 0) {
      // Positive correlation (green to yellow)
      barPaint.color = Color.lerp(config.warningColor, config.positiveColor, correlation)!;
      canvas.drawRect(
        Rect.fromLTRB(center, barTop + 4, center + correlation * barWidth / 2, barHeight - 4),
        barPaint,
      );
    } else {
      // Negative correlation (yellow to red)
      barPaint.color = Color.lerp(config.warningColor, config.negativeColor, -correlation)!;
      canvas.drawRect(
        Rect.fromLTRB(center + correlation * barWidth / 2, barTop + 4, center, barHeight - 4),
        barPaint,
      );
    }

    // Draw peak hold markers
    if (config.showPeakHold) {
      final peakPaint = Paint()
        ..color = config.peakColor
        ..strokeWidth = 2;

      // Min peak
      if (peakMin < 0) {
        final x = center + peakMin * barWidth / 2;
        canvas.drawLine(Offset(x, barTop + 2), Offset(x, barHeight - 2), peakPaint);
      }

      // Max peak
      if (peakMax > 0) {
        final x = center + peakMax * barWidth / 2;
        canvas.drawLine(Offset(x, barTop + 2), Offset(x, barHeight - 2), peakPaint);
      }
    }

    // Draw center line
    canvas.drawLine(
      Offset(center, barTop),
      Offset(center, barHeight),
      Paint()
        ..color = ReelForgeTheme.textSecondary
        ..strokeWidth = 2,
    );

    // Draw labels
    if (config.showLabels) {
      final textStyle = TextStyle(
        color: ReelForgeTheme.textTertiary,
        fontSize: 9,
      );

      _drawText(canvas, '-1', Offset(barLeft - 2, size.height - 12), textStyle);
      _drawText(canvas, '0', Offset(center - 3, size.height - 12), textStyle);
      _drawText(canvas, '+1', Offset(barLeft + barWidth - 10, size.height - 12), textStyle);
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _BarCorrelationPainter oldDelegate) {
    return correlation != oldDelegate.correlation ||
        peakMin != oldDelegate.peakMin ||
        peakMax != oldDelegate.peakMax;
  }
}

class _ArcCorrelationPainter extends CustomPainter {
  final double correlation;
  final double peakMin;
  final double peakMax;
  final CorrelationMeterConfig config;

  _ArcCorrelationPainter({
    required this.correlation,
    required this.peakMin,
    required this.peakMax,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = math.min(size.width, size.height) * 0.8;

    // Draw arc background
    final bgPaint = Paint()
      ..color = ReelForgeTheme.bgMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    // Draw gradient arc sections
    // Left half (negative - red to yellow)
    final leftGradient = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: math.pi,
        endAngle: math.pi * 1.5,
        colors: [config.negativeColor, config.warningColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi / 2,
      false,
      leftGradient,
    );

    // Right half (positive - yellow to green)
    final rightGradient = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: math.pi * 1.5,
        endAngle: math.pi * 2,
        colors: [config.warningColor, config.positiveColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.5,
      math.pi / 2,
      false,
      rightGradient,
    );

    // Draw needle
    final needleAngle = math.pi + ((correlation + 1) / 2) * math.pi;
    final needleEnd = Offset(
      center.dx + math.cos(needleAngle) * (radius - 15),
      center.dy + math.sin(needleAngle) * (radius - 15),
    );

    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = ReelForgeTheme.textPrimary
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Needle base circle
    canvas.drawCircle(center, 6, Paint()..color = ReelForgeTheme.textPrimary);
    canvas.drawCircle(center, 4, Paint()..color = ReelForgeTheme.borderSubtle);

    // Draw labels
    if (config.showLabels) {
      final textStyle = TextStyle(
        color: ReelForgeTheme.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      );

      _drawText(canvas, '-1', Offset(center.dx - radius - 12, center.dy - 8), textStyle);
      _drawText(canvas, '0', Offset(center.dx - 4, center.dy - radius - 16), textStyle);
      _drawText(canvas, '+1', Offset(center.dx + radius, center.dy - 8), textStyle);
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _ArcCorrelationPainter oldDelegate) {
    return correlation != oldDelegate.correlation;
  }
}
