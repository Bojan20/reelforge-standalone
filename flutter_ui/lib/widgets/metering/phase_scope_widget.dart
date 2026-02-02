/// Phase Scope / Goniometer Widget — Pro Tools-Level Stereo Field Analyzer
///
/// Professional Lissajous stereo field visualizer with:
/// - Real-time L vs R plotting (Lissajous curve)
/// - Correlation coefficient display (-1 to +1)
/// - Grid overlay (±45°, ±90° reference lines)
/// - Mono/stereo/out-of-phase indicators
/// - Freeze frame mode for analysis
/// - GPU-accelerated CustomPainter rendering
///
/// Target: 60fps smooth rendering with < 1ms paint time

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Phase scope display configuration
@immutable
class PhaseScopeConfig {
  /// Number of sample points to display (ring buffer size)
  final int sampleCount;

  /// Decay rate for trail fade (0.0 = instant, 1.0 = no decay)
  final double trailDecay;

  /// Line width for Lissajous curve
  final double lineWidth;

  /// Show grid overlay
  final bool showGrid;

  /// Show correlation readout
  final bool showCorrelation;

  /// Show phase indicators
  final bool showIndicators;

  /// Glow intensity (0.0 = none, 1.0 = full)
  final double glowIntensity;

  const PhaseScopeConfig({
    this.sampleCount = 512,
    this.trailDecay = 0.92,
    this.lineWidth = 1.5,
    this.showGrid = true,
    this.showCorrelation = true,
    this.showIndicators = true,
    this.glowIntensity = 0.6,
  });

  /// Pro Tools style configuration
  static const proTools = PhaseScopeConfig(
    sampleCount: 512,
    trailDecay: 0.94,
    lineWidth: 1.5,
    showGrid: true,
    showCorrelation: true,
    showIndicators: true,
    glowIntensity: 0.5,
  );

  /// Compact display configuration
  static const compact = PhaseScopeConfig(
    sampleCount: 256,
    trailDecay: 0.90,
    lineWidth: 1.0,
    showGrid: true,
    showCorrelation: false,
    showIndicators: false,
    glowIntensity: 0.4,
  );
}

/// Phase state classification
enum PhaseState {
  /// Highly correlated (0.7 to 1.0) - mono compatible
  mono,

  /// Moderately correlated (0.3 to 0.7) - good stereo
  stereo,

  /// Low correlation (0.0 to 0.3) - wide stereo
  wide,

  /// Negative correlation (-0.3 to 0.0) - phase issues
  phaseIssues,

  /// Out of phase (-1.0 to -0.3) - serious phase problems
  outOfPhase,
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Professional goniometer/phase scope widget
class PhaseScope extends StatefulWidget {
  /// Left channel samples (normalized -1 to +1)
  final Float32List? leftSamples;

  /// Right channel samples (normalized -1 to +1)
  final Float32List? rightSamples;

  /// Pre-computed correlation coefficient (-1 to +1)
  final double? correlation;

  /// Widget size
  final double size;

  /// Configuration
  final PhaseScopeConfig config;

  /// Freeze display (for analysis)
  final bool frozen;

  /// Callback when tapped (e.g., toggle freeze)
  final VoidCallback? onTap;

  const PhaseScope({
    super.key,
    this.leftSamples,
    this.rightSamples,
    this.correlation,
    this.size = 200,
    this.config = const PhaseScopeConfig(),
    this.frozen = false,
    this.onTap,
  });

  @override
  State<PhaseScope> createState() => _PhaseScopeState();
}

class _PhaseScopeState extends State<PhaseScope>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // Ring buffer for sample history
  late List<Offset> _sampleHistory;
  late List<double> _alphaHistory;
  int _writeIndex = 0;

  // Smoothed correlation for display
  double _smoothedCorrelation = 1.0;
  double _peakCorrelationMin = 1.0;
  double _peakCorrelationMax = 1.0;
  DateTime _peakResetTime = DateTime.now();

  // Last frame time
  Duration _lastFrameTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeBuffers();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _initializeBuffers() {
    final count = widget.config.sampleCount;
    _sampleHistory = List.filled(count, Offset.zero);
    _alphaHistory = List.filled(count, 0.0);
    _writeIndex = 0;
  }

  @override
  void didUpdateWidget(PhaseScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.sampleCount != widget.config.sampleCount) {
      _initializeBuffers();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (widget.frozen) return;

    final deltaMs = (elapsed - _lastFrameTime).inMicroseconds / 1000.0;
    _lastFrameTime = elapsed;

    if (deltaMs < 1 || deltaMs > 100) return;

    // Process new samples
    _processSamples();

    // Update correlation smoothing
    _updateCorrelation(deltaMs);

    // Decay trail alpha values
    _decayTrail();

    if (mounted) setState(() {});
  }

  void _processSamples() {
    final left = widget.leftSamples;
    final right = widget.rightSamples;

    if (left == null || right == null || left.isEmpty || right.isEmpty) return;

    final sampleCount = math.min(left.length, right.length);
    final step = math.max(1, sampleCount ~/ 32); // Sample 32 points per frame

    for (int i = 0; i < sampleCount; i += step) {
      final l = left[i].clamp(-1.0, 1.0);
      final r = right[i].clamp(-1.0, 1.0);

      // Convert to M/S for goniometer display
      // Mid = (L + R) / 2 (vertical axis)
      // Side = (L - R) / 2 (horizontal axis)
      final mid = (l + r) / 2.0;
      final side = (l - r) / 2.0;

      _sampleHistory[_writeIndex] = Offset(side, mid);
      _alphaHistory[_writeIndex] = 1.0;
      _writeIndex = (_writeIndex + 1) % widget.config.sampleCount;
    }
  }

  void _updateCorrelation(double deltaMs) {
    final target = widget.correlation ?? _calculateCorrelation();
    final smoothingFactor = 1.0 - math.exp(-deltaMs / 100.0);
    _smoothedCorrelation += (target - _smoothedCorrelation) * smoothingFactor;

    // Update peak hold
    final now = DateTime.now();
    if (_smoothedCorrelation < _peakCorrelationMin) {
      _peakCorrelationMin = _smoothedCorrelation;
      _peakResetTime = now;
    }
    if (_smoothedCorrelation > _peakCorrelationMax) {
      _peakCorrelationMax = _smoothedCorrelation;
      _peakResetTime = now;
    }

    // Reset peaks after 3 seconds
    if (now.difference(_peakResetTime).inMilliseconds > 3000) {
      _peakCorrelationMin = _smoothedCorrelation;
      _peakCorrelationMax = _smoothedCorrelation;
    }
  }

  double _calculateCorrelation() {
    final left = widget.leftSamples;
    final right = widget.rightSamples;

    if (left == null || right == null || left.isEmpty || right.isEmpty) {
      return 1.0;
    }

    final count = math.min(left.length, right.length);
    double sumLR = 0.0;
    double sumLL = 0.0;
    double sumRR = 0.0;

    for (int i = 0; i < count; i++) {
      final l = left[i];
      final r = right[i];
      sumLR += l * r;
      sumLL += l * l;
      sumRR += r * r;
    }

    final denominator = math.sqrt(sumLL * sumRR);
    if (denominator < 1e-10) return 1.0;

    return (sumLR / denominator).clamp(-1.0, 1.0);
  }

  void _decayTrail() {
    final decay = widget.config.trailDecay;
    for (int i = 0; i < _alphaHistory.length; i++) {
      _alphaHistory[i] *= decay;
    }
  }

  PhaseState _getPhaseState(double correlation) {
    if (correlation >= 0.7) return PhaseState.mono;
    if (correlation >= 0.3) return PhaseState.stereo;
    if (correlation >= 0.0) return PhaseState.wide;
    if (correlation >= -0.3) return PhaseState.phaseIssues;
    return PhaseState.outOfPhase;
  }

  Color _getPhaseColor(PhaseState state) {
    switch (state) {
      case PhaseState.mono:
        return FluxForgeTheme.accentGreen;
      case PhaseState.stereo:
        return FluxForgeTheme.accentCyan;
      case PhaseState.wide:
        return FluxForgeTheme.accentYellow;
      case PhaseState.phaseIssues:
        return FluxForgeTheme.accentOrange;
      case PhaseState.outOfPhase:
        return FluxForgeTheme.accentRed;
    }
  }

  String _getPhaseLabel(PhaseState state) {
    switch (state) {
      case PhaseState.mono:
        return 'MONO';
      case PhaseState.stereo:
        return 'STEREO';
      case PhaseState.wide:
        return 'WIDE';
      case PhaseState.phaseIssues:
        return 'PHASE';
      case PhaseState.outOfPhase:
        return 'OUT';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _getPhaseState(_smoothedCorrelation);
    final stateColor = _getPhaseColor(state);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Stack(
          children: [
            // Main scope display
            RepaintBoundary(
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _PhaseScopePainter(
                  sampleHistory: _sampleHistory,
                  alphaHistory: _alphaHistory,
                  config: widget.config,
                  stateColor: stateColor,
                ),
                willChange: !widget.frozen,
                isComplex: true,
              ),
            ),

            // Correlation readout
            if (widget.config.showCorrelation)
              Positioned(
                top: 4,
                left: 4,
                right: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'r = ${_smoothedCorrelation.toStringAsFixed(2)}',
                      style: FluxForgeTheme.monoSmall.copyWith(
                        color: stateColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: stateColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        _getPhaseLabel(state),
                        style: FluxForgeTheme.labelTiny.copyWith(
                          color: stateColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Phase indicators
            if (widget.config.showIndicators)
              Positioned(
                bottom: 4,
                left: 4,
                right: 4,
                child: _buildPhaseIndicator(state, stateColor),
              ),

            // Frozen indicator
            if (widget.frozen)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    'FROZEN',
                    style: FluxForgeTheme.labelTiny.copyWith(
                      color: FluxForgeTheme.accentOrange,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseIndicator(PhaseState state, Color color) {
    return Row(
      children: [
        // Left label
        Text(
          'L',
          style: FluxForgeTheme.labelTiny.copyWith(
            color: FluxForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 4),
        // Correlation bar
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(3),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Correlation: -1 (left) to +1 (right), 0 = center
                final normalized =
                    (_smoothedCorrelation + 1.0) / 2.0; // 0 to 1
                final indicatorX =
                    normalized * constraints.maxWidth;

                return Stack(
                  children: [
                    // Center marker
                    Positioned(
                      left: constraints.maxWidth / 2 - 0.5,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
                    // Indicator dot
                    Positioned(
                      left: indicatorX - 3,
                      top: 0,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Right label
        Text(
          'R',
          style: FluxForgeTheme.labelTiny.copyWith(
            color: FluxForgeTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — GPU Optimized
// ═══════════════════════════════════════════════════════════════════════════

class _PhaseScopePainter extends CustomPainter {
  final List<Offset> sampleHistory;
  final List<double> alphaHistory;
  final PhaseScopeConfig config;
  final Color stateColor;

  _PhaseScopePainter({
    required this.sampleHistory,
    required this.alphaHistory,
    required this.config,
    required this.stateColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Draw grid
    if (config.showGrid) {
      _drawGrid(canvas, center, radius);
    }

    // Draw Lissajous curve
    _drawLissajous(canvas, center, radius);
  }

  void _drawGrid(Canvas canvas, Offset center, double radius) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final axisPaint = Paint()
      ..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Circle boundary
    canvas.drawCircle(center, radius, gridPaint);

    // Main axes (vertical = M, horizontal = S)
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      axisPaint,
    );

    // 45° diagonal lines (L and R axes)
    final diag = radius * math.sqrt(2) / 2;
    canvas.drawLine(
      Offset(center.dx - diag, center.dy - diag),
      Offset(center.dx + diag, center.dy + diag),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx + diag, center.dy - diag),
      Offset(center.dx - diag, center.dy + diag),
      gridPaint,
    );

    // Inner circles (50% and 25%)
    canvas.drawCircle(center, radius * 0.5, gridPaint);
    canvas.drawCircle(center, radius * 0.25, gridPaint);

    // Axis labels
    final labelStyle = TextStyle(
      color: FluxForgeTheme.textTertiary,
      fontSize: 8,
      fontFamily: FluxForgeTheme.fontFamily,
    );

    _drawLabel(canvas, 'M', Offset(center.dx + 2, center.dy - radius - 2), labelStyle);
    _drawLabel(canvas, 'S', Offset(center.dx + radius + 2, center.dy - 4), labelStyle);
    _drawLabel(canvas, 'L', Offset(center.dx - diag - 10, center.dy - diag - 2), labelStyle);
    _drawLabel(canvas, 'R', Offset(center.dx + diag + 2, center.dy - diag - 2), labelStyle);
  }

  void _drawLabel(Canvas canvas, String text, Offset position, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  void _drawLissajous(Canvas canvas, Offset center, double radius) {
    if (sampleHistory.isEmpty) return;

    // Draw glow layer first
    if (config.glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = stateColor.withValues(alpha: config.glowIntensity * 0.3)
        ..strokeWidth = config.lineWidth * 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      _drawSamplePath(canvas, center, radius, glowPaint, alphaMultiplier: 0.5);
    }

    // Draw main curve
    final mainPaint = Paint()
      ..strokeWidth = config.lineWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _drawSamplePath(canvas, center, radius, mainPaint, useAlpha: true);
  }

  void _drawSamplePath(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    bool useAlpha = false,
    double alphaMultiplier = 1.0,
  }) {
    for (int i = 0; i < sampleHistory.length; i++) {
      final alpha = alphaHistory[i];
      if (alpha < 0.01) continue;

      final sample = sampleHistory[i];
      // sample.dx = side (horizontal), sample.dy = mid (vertical)
      final x = center.dx + sample.dx * radius;
      final y = center.dy - sample.dy * radius; // Flip Y for screen coords

      final effectiveAlpha = useAlpha ? alpha * alphaMultiplier : alphaMultiplier;

      if (effectiveAlpha > 0.01) {
        paint.color = stateColor.withValues(alpha: effectiveAlpha);
        canvas.drawCircle(Offset(x, y), config.lineWidth * 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PhaseScopePainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Calculate correlation coefficient from L/R sample arrays
double calculateCorrelation(Float32List left, Float32List right) {
  if (left.isEmpty || right.isEmpty) return 1.0;

  final count = math.min(left.length, right.length);
  double sumLR = 0.0;
  double sumLL = 0.0;
  double sumRR = 0.0;

  for (int i = 0; i < count; i++) {
    final l = left[i];
    final r = right[i];
    sumLR += l * r;
    sumLL += l * l;
    sumRR += r * r;
  }

  final denominator = math.sqrt(sumLL * sumRR);
  if (denominator < 1e-10) return 1.0;

  return (sumLR / denominator).clamp(-1.0, 1.0);
}
