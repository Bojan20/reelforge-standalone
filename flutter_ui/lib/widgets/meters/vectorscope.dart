/// Stereo Vectorscope
///
/// Professional goniometer/vectorscope display showing:
/// - Stereo image visualization (L/R to M/S)
/// - Phase correlation indicator
/// - Balance indicator
/// - Lissajous display
///
/// Based on studio hardware (SSL, Neve consoles)

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Vectorscope configuration
class VectorscopeConfig {
  /// Dot size
  final double dotSize;

  /// Trail length (number of samples to display)
  final int trailLength;

  /// Trail opacity decay
  final double trailDecay;

  /// Show grid (crosshairs)
  final bool showGrid;

  /// Show phase meter below
  final bool showPhaseMeter;

  /// Show balance indicator
  final bool showBalance;

  /// Rotation (0 = standard, 45 = tilted like some analyzers)
  final double rotation;

  /// Primary color
  final Color primaryColor;

  /// Background color
  final Color backgroundColor;

  /// Grid color
  final Color gridColor;

  const VectorscopeConfig({
    this.dotSize = 2.0,
    this.trailLength = 512,
    this.trailDecay = 0.98,
    this.showGrid = true,
    this.showPhaseMeter = true,
    this.showBalance = true,
    this.rotation = 0,
    this.primaryColor = ReelForgeTheme.accentCyan,
    this.backgroundColor = ReelForgeTheme.bgDeepest,
    this.gridColor = ReelForgeTheme.borderSubtle,
  });
}

/// Vectorscope widget
class Vectorscope extends StatefulWidget {
  /// Left channel samples
  final Float64List? leftSamples;

  /// Right channel samples
  final Float64List? rightSamples;

  /// Configuration
  final VectorscopeConfig config;

  const Vectorscope({
    super.key,
    this.leftSamples,
    this.rightSamples,
    this.config = const VectorscopeConfig(),
  });

  @override
  State<Vectorscope> createState() => _VectorscopeState();
}

class _VectorscopeState extends State<Vectorscope>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Trail buffer (circular buffer of points)
  final List<Offset> _trail = [];
  final List<double> _trailOpacity = [];

  // Metering values
  double _phaseCorrelation = 0.0;
  double _balance = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_update);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    final left = widget.leftSamples;
    final right = widget.rightSamples;

    if (left == null || right == null || left.isEmpty || right.isEmpty) {
      // Decay trail
      for (int i = 0; i < _trailOpacity.length; i++) {
        _trailOpacity[i] *= widget.config.trailDecay;
      }
      _trailOpacity.removeWhere((o) => o < 0.01);
      if (_trail.length > _trailOpacity.length) {
        _trail.removeRange(_trailOpacity.length, _trail.length);
      }

      // Decay meters
      _phaseCorrelation *= 0.95;
      _balance *= 0.95;

      setState(() {});
      return;
    }

    final sampleCount = math.min(left.length, right.length);

    // Calculate phase correlation and balance
    double sumLR = 0, sumLL = 0, sumRR = 0;
    double sumL = 0, sumR = 0;

    for (int i = 0; i < sampleCount; i++) {
      final l = left[i];
      final r = right[i];

      sumLR += l * r;
      sumLL += l * l;
      sumRR += r * r;

      sumL += l.abs();
      sumR += r.abs();
    }

    // Correlation coefficient (-1 to +1)
    final denom = math.sqrt(sumLL * sumRR);
    if (denom > 0.0001) {
      final newCorr = sumLR / denom;
      _phaseCorrelation = _phaseCorrelation * 0.9 + newCorr * 0.1;
    }

    // Balance (-1 = left, +1 = right)
    final totalLevel = sumL + sumR;
    if (totalLevel > 0.0001) {
      final newBalance = (sumR - sumL) / totalLevel;
      _balance = _balance * 0.9 + newBalance * 0.1;
    }

    // Add points to trail (M/S encoding)
    // M = (L+R)/2, S = (L-R)/2
    // For display: X = S (width), Y = M (height)
    final rotRad = widget.config.rotation * math.pi / 180;
    final cosRot = math.cos(rotRad);
    final sinRot = math.sin(rotRad);

    for (int i = 0; i < sampleCount; i++) {
      final l = left[i];
      final r = right[i];

      // M/S encoding
      final m = (l + r) * 0.5;
      final s = (l - r) * 0.5;

      // Apply rotation
      final x = s * cosRot - m * sinRot;
      final y = m * cosRot + s * sinRot;

      _trail.add(Offset(x, y));
      _trailOpacity.add(1.0);
    }

    // Limit trail length
    while (_trail.length > widget.config.trailLength) {
      _trail.removeAt(0);
      _trailOpacity.removeAt(0);
    }

    // Decay trail opacity
    for (int i = 0; i < _trailOpacity.length; i++) {
      _trailOpacity[i] *= widget.config.trailDecay;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final phaseMeterHeight = widget.config.showPhaseMeter ? 24.0 : 0.0;
        final balanceHeight = widget.config.showBalance ? 12.0 : 0.0;
        final scopeSize = size - phaseMeterHeight - balanceHeight - 8;

        return Container(
          color: widget.config.backgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vectorscope display
              SizedBox(
                width: scopeSize,
                height: scopeSize,
                child: CustomPaint(
                  painter: _VectorscopePainter(
                    trail: _trail,
                    trailOpacity: _trailOpacity,
                    config: widget.config,
                  ),
                ),
              ),

              // Balance indicator
              if (widget.config.showBalance)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _BalanceIndicator(balance: _balance, width: scopeSize),
                ),

              // Phase correlation meter
              if (widget.config.showPhaseMeter)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _PhaseMeter(
                    correlation: _phaseCorrelation,
                    width: scopeSize,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VectorscopePainter extends CustomPainter {
  final List<Offset> trail;
  final List<double> trailOpacity;
  final VectorscopeConfig config;

  _VectorscopePainter({
    required this.trail,
    required this.trailOpacity,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = config.backgroundColor,
    );

    // Grid
    if (config.showGrid) {
      _drawGrid(canvas, center, radius);
    }

    // Clip to circle
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    // Draw trail
    for (int i = 0; i < trail.length && i < trailOpacity.length; i++) {
      final point = trail[i];
      final opacity = trailOpacity[i];

      // Map normalized coordinates to screen
      final screenX = center.dx + point.dx * radius;
      final screenY = center.dy - point.dy * radius; // Y inverted

      canvas.drawCircle(
        Offset(screenX, screenY),
        config.dotSize,
        Paint()..color = config.primaryColor.withAlpha((255 * opacity).round()),
      );
    }

    canvas.restore();

    // Border circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = config.gridColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawGrid(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = config.gridColor.withAlpha(77)
      ..strokeWidth = 1;

    // Crosshairs
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );

    // Diagonal lines (L and R channels)
    final diagLen = radius * 0.707; // 45 degree
    canvas.drawLine(
      Offset(center.dx - diagLen, center.dy - diagLen),
      Offset(center.dx + diagLen, center.dy + diagLen),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - diagLen, center.dy + diagLen),
      Offset(center.dx + diagLen, center.dy - diagLen),
      paint,
    );

    // Labels
    final textStyle = TextStyle(
      color: config.gridColor,
      fontSize: 10,
    );

    _drawLabel(canvas, 'M', Offset(center.dx, center.dy - radius - 12), textStyle);
    _drawLabel(canvas, 'S', Offset(center.dx + radius + 8, center.dy), textStyle);
    _drawLabel(canvas, 'L', Offset(center.dx - radius * 0.707 - 10, center.dy - radius * 0.707 - 6), textStyle);
    _drawLabel(canvas, 'R', Offset(center.dx + radius * 0.707 + 4, center.dy - radius * 0.707 - 6), textStyle);
  }

  void _drawLabel(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _VectorscopePainter oldDelegate) {
    return trail != oldDelegate.trail;
  }
}

class _BalanceIndicator extends StatelessWidget {
  final double balance;
  final double width;

  const _BalanceIndicator({
    required this.balance,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 8,
      child: CustomPaint(
        painter: _BalancePainter(balance: balance),
      ),
    );
  }
}

class _BalancePainter extends CustomPainter {
  final double balance;

  _BalancePainter({required this.balance});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;

    // Background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(2),
      ),
      Paint()..color = ReelForgeTheme.bgMid,
    );

    // Center line
    canvas.drawLine(
      Offset(center, 0),
      Offset(center, size.height),
      Paint()
        ..color = ReelForgeTheme.textSecondary
        ..strokeWidth = 1,
    );

    // Balance indicator
    final indicatorX = center + balance.clamp(-1, 1) * (size.width / 2 - 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(indicatorX, size.height / 2),
          width: 4,
          height: size.height - 2,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = ReelForgeTheme.accentBlue,
    );
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) {
    return balance != oldDelegate.balance;
  }
}

class _PhaseMeter extends StatelessWidget {
  final double correlation;
  final double width;

  const _PhaseMeter({
    required this.correlation,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 16,
      child: CustomPaint(
        painter: _PhaseMeterPainter(correlation: correlation),
      ),
    );
  }
}

class _PhaseMeterPainter extends CustomPainter {
  final double correlation;

  _PhaseMeterPainter({required this.correlation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final meterHeight = 8.0;
    final meterY = (size.height - meterHeight) / 2;

    // Background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, meterY, size.width, meterHeight),
        const Radius.circular(2),
      ),
      Paint()..color = ReelForgeTheme.bgMid,
    );

    // Gradient for meter
    // -1 (out of phase, red) to +1 (in phase, green)
    final gradient = LinearGradient(
      colors: const [
        ReelForgeTheme.errorRed,
        ReelForgeTheme.accentOrange,
        ReelForgeTheme.accentGreen,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    // Fill from center based on correlation
    final fillWidth = correlation.abs() * (size.width / 2);
    final fillX = correlation >= 0 ? center : center - fillWidth;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(fillX, meterY, fillWidth, meterHeight),
        const Radius.circular(2),
      ),
      Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Center line
    canvas.drawLine(
      Offset(center, meterY),
      Offset(center, meterY + meterHeight),
      Paint()
        ..color = Colors.white.withAlpha(128)
        ..strokeWidth = 1,
    );

    // Labels
    final textStyle = TextStyle(
      color: ReelForgeTheme.textSecondary,
      fontSize: 8,
    );

    _drawLabel(canvas, '-1', Offset(4, size.height - 4), textStyle);
    _drawLabel(canvas, '+1', Offset(size.width - 14, size.height - 4), textStyle);

    // Correlation value
    final valueStyle = TextStyle(
      color: _getCorrelationColor(correlation),
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );
    _drawLabel(
      canvas,
      correlation.toStringAsFixed(2),
      Offset(center - 12, size.height - 4),
      valueStyle,
    );
  }

  Color _getCorrelationColor(double corr) {
    if (corr >= 0.5) return ReelForgeTheme.accentGreen;
    if (corr >= 0) return ReelForgeTheme.accentOrange;
    return ReelForgeTheme.errorRed;
  }

  void _drawLabel(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _PhaseMeterPainter oldDelegate) {
    return correlation != oldDelegate.correlation;
  }
}

/// Demo widget for testing
class VectorscopeDemo extends StatefulWidget {
  const VectorscopeDemo({super.key});

  @override
  State<VectorscopeDemo> createState() => _VectorscopeDemoState();
}

class _VectorscopeDemoState extends State<VectorscopeDemo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Float64List _left = Float64List(256);
  Float64List _right = Float64List(256);
  final _random = math.Random();
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_generateData);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _generateData() {
    _phase += 0.1;

    for (int i = 0; i < 256; i++) {
      final t = i / 256.0;
      final freq1 = 440.0;
      final freq2 = 442.0; // Slight detuning for stereo effect

      // Generate stereo signal with some width
      final mono = math.sin(2 * math.pi * freq1 * t + _phase);
      final stereo = math.sin(2 * math.pi * freq2 * t + _phase * 1.02);

      // Add some noise
      final noise = (_random.nextDouble() - 0.5) * 0.1;

      _left[i] = (mono * 0.7 + stereo * 0.3 + noise) * 0.8;
      _right[i] = (mono * 0.3 + stereo * 0.7 + noise) * 0.8;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeepest,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Vectorscope(
          leftSamples: _left,
          rightSamples: _right,
        ),
      ),
    );
  }
}
