/// Correlation Meter Widget — Mono Compatibility Analyzer
///
/// Professional phase correlation meter with:
/// - Range: -1 (out of phase) to +1 (mono)
/// - Color zones for quick visual feedback
/// - Numeric display with peak hold
/// - Compact horizontal bar design
/// - GPU-accelerated CustomPainter rendering
///
/// Target: 60fps smooth rendering with < 0.5ms paint time

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Correlation meter configuration
@immutable
class CorrelationMeterConfig {
  /// Smoothing factor for correlation value (0.0 = none, 1.0 = max)
  final double smoothing;

  /// Peak hold time in milliseconds (0 = no hold)
  final int peakHoldMs;

  /// Show numeric value display
  final bool showValue;

  /// Show zone labels (+1, 0, -1)
  final bool showLabels;

  /// Vertical orientation (default false = horizontal)
  final bool vertical;

  const CorrelationMeterConfig({
    this.smoothing = 0.85,
    this.peakHoldMs = 2000,
    this.showValue = true,
    this.showLabels = true,
    this.vertical = false,
  });

  /// Pro Tools style configuration
  static const proTools = CorrelationMeterConfig(
    smoothing: 0.9,
    peakHoldMs: 2000,
    showValue: true,
    showLabels: true,
    vertical: false,
  );

  /// Compact display configuration
  static const compact = CorrelationMeterConfig(
    smoothing: 0.8,
    peakHoldMs: 1000,
    showValue: false,
    showLabels: false,
    vertical: false,
  );
}

/// Correlation zone classification
enum CorrelationZone {
  /// +1.0 to +0.5: Good mono compatibility
  good,

  /// +0.5 to 0.0: Partial correlation (OK)
  partial,

  /// 0.0 to -1.0: Phase issues (warning/error)
  phaseIssues,
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Professional phase correlation meter widget
class CorrelationMeter extends StatefulWidget {
  /// Current correlation value (-1 to +1)
  /// Can be provided directly or calculated from samples
  final double? correlation;

  /// Left channel samples (for auto-calculation)
  final Float32List? leftSamples;

  /// Right channel samples (for auto-calculation)
  final Float32List? rightSamples;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Configuration
  final CorrelationMeterConfig config;

  /// Callback when tapped (e.g., reset peaks)
  final VoidCallback? onTap;

  const CorrelationMeter({
    super.key,
    this.correlation,
    this.leftSamples,
    this.rightSamples,
    this.width = 200,
    this.height = 24,
    this.config = const CorrelationMeterConfig(),
    this.onTap,
  });

  /// Create a simple correlation meter with direct value input
  const CorrelationMeter.simple({
    super.key,
    required double value,
    this.width = 200,
    this.height = 20,
    this.onTap,
  })  : correlation = value,
        leftSamples = null,
        rightSamples = null,
        config = CorrelationMeterConfig.compact;

  @override
  State<CorrelationMeter> createState() => _CorrelationMeterState();
}

class _CorrelationMeterState extends State<CorrelationMeter>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // Smoothed values
  double _smoothedCorrelation = 1.0;

  // Peak hold tracking
  double _peakMin = 1.0;
  double _peakMax = 1.0;
  DateTime _peakMinTime = DateTime.now();
  DateTime _peakMaxTime = DateTime.now();

  // Last frame time
  Duration _lastFrameTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final deltaMs = (elapsed - _lastFrameTime).inMicroseconds / 1000.0;
    _lastFrameTime = elapsed;

    if (deltaMs < 1 || deltaMs > 100) return;

    _updateCorrelation(deltaMs);
    _updatePeakHold(deltaMs);

    if (mounted) setState(() {});
  }

  void _updateCorrelation(double deltaMs) {
    final target = widget.correlation ?? _calculateCorrelation();
    final smoothingFactor = 1.0 - math.exp(-deltaMs / (100.0 * widget.config.smoothing + 10.0));
    _smoothedCorrelation += (target - _smoothedCorrelation) * smoothingFactor;
  }

  double _calculateCorrelation() {
    final left = widget.leftSamples;
    final right = widget.rightSamples;

    if (left == null || right == null || left.isEmpty || right.isEmpty) {
      return 1.0;
    }

    return calculateCorrelationFromSamples(left, right);
  }

  void _updatePeakHold(double deltaMs) {
    if (widget.config.peakHoldMs <= 0) return;

    final now = DateTime.now();

    // Update minimum peak
    if (_smoothedCorrelation < _peakMin) {
      _peakMin = _smoothedCorrelation;
      _peakMinTime = now;
    } else if (now.difference(_peakMinTime).inMilliseconds > widget.config.peakHoldMs) {
      // Decay towards current value
      _peakMin += (_smoothedCorrelation - _peakMin) * 0.1;
    }

    // Update maximum peak
    if (_smoothedCorrelation > _peakMax) {
      _peakMax = _smoothedCorrelation;
      _peakMaxTime = now;
    } else if (now.difference(_peakMaxTime).inMilliseconds > widget.config.peakHoldMs) {
      _peakMax += (_smoothedCorrelation - _peakMax) * 0.1;
    }
  }

  void _resetPeaks() {
    setState(() {
      _peakMin = _smoothedCorrelation;
      _peakMax = _smoothedCorrelation;
    });
  }

  CorrelationZone _getZone(double correlation) {
    if (correlation >= 0.5) return CorrelationZone.good;
    if (correlation >= 0.0) return CorrelationZone.partial;
    return CorrelationZone.phaseIssues;
  }

  Color _getZoneColor(CorrelationZone zone) {
    switch (zone) {
      case CorrelationZone.good:
        return FluxForgeTheme.accentGreen;
      case CorrelationZone.partial:
        return FluxForgeTheme.accentYellow;
      case CorrelationZone.phaseIssues:
        return FluxForgeTheme.accentRed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final zone = _getZone(_smoothedCorrelation);
    final zoneColor = _getZoneColor(zone);

    return GestureDetector(
      onTap: () {
        widget.onTap?.call();
        _resetPeaks();
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: widget.config.vertical
            ? _buildVerticalLayout(zone, zoneColor)
            : _buildHorizontalLayout(zone, zoneColor),
      ),
    );
  }

  Widget _buildHorizontalLayout(CorrelationZone zone, Color zoneColor) {
    return Row(
      children: [
        // Left label
        if (widget.config.showLabels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '-1',
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),

        // Meter bar
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CorrelationMeterPainter(
                  correlation: _smoothedCorrelation,
                  peakMin: _peakMin,
                  peakMax: _peakMax,
                  zoneColor: zoneColor,
                  showPeakHold: widget.config.peakHoldMs > 0,
                ),
                willChange: true,
              ),
            ),
          ),
        ),

        // Right label
        if (widget.config.showLabels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '+1',
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),

        // Numeric value
        if (widget.config.showValue)
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _formatCorrelation(_smoothedCorrelation),
              textAlign: TextAlign.right,
              style: FluxForgeTheme.monoSmall.copyWith(
                color: zoneColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVerticalLayout(CorrelationZone zone, Color zoneColor) {
    return Column(
      children: [
        // Top label
        if (widget.config.showLabels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '+1',
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),

        // Meter bar
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CorrelationMeterPainter(
                  correlation: _smoothedCorrelation,
                  peakMin: _peakMin,
                  peakMax: _peakMax,
                  zoneColor: zoneColor,
                  showPeakHold: widget.config.peakHoldMs > 0,
                  vertical: true,
                ),
                willChange: true,
              ),
            ),
          ),
        ),

        // Bottom label
        if (widget.config.showLabels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '-1',
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),

        // Numeric value
        if (widget.config.showValue)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              _formatCorrelation(_smoothedCorrelation),
              style: FluxForgeTheme.monoSmall.copyWith(
                color: zoneColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  String _formatCorrelation(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — GPU Optimized
// ═══════════════════════════════════════════════════════════════════════════

class _CorrelationMeterPainter extends CustomPainter {
  final double correlation;
  final double peakMin;
  final double peakMax;
  final Color zoneColor;
  final bool showPeakHold;
  final bool vertical;

  // Pre-computed gradient
  static LinearGradient? _cachedGradientH;
  static LinearGradient? _cachedGradientV;

  _CorrelationMeterPainter({
    required this.correlation,
    required this.peakMin,
    required this.peakMax,
    required this.zoneColor,
    required this.showPeakHold,
    this.vertical = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background with zone colors
    _drawBackground(canvas, size);

    // Center marker (0 point)
    _drawCenterMarker(canvas, size);

    // Correlation indicator
    _drawIndicator(canvas, size);

    // Peak hold markers
    if (showPeakHold) {
      _drawPeakHold(canvas, size);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    final gradient = vertical ? _getVerticalGradient() : _getHorizontalGradient();

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      Paint()..shader = gradient.createShader(Offset.zero & size),
    );
  }

  void _drawCenterMarker(Canvas canvas, Size size) {
    final centerPaint = Paint()
      ..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    if (vertical) {
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), centerPaint);
    } else {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), centerPaint);
    }
  }

  void _drawIndicator(Canvas canvas, Size size) {
    // Correlation: -1 to +1 → normalized: 0 to 1
    final normalized = (correlation + 1.0) / 2.0;

    final indicatorPaint = Paint()
      ..color = zoneColor
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = zoneColor.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    if (vertical) {
      final y = size.height * (1 - normalized);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(2, y - 2, size.width - 4, 4),
        const Radius.circular(2),
      );

      canvas.drawRRect(rect, glowPaint);
      canvas.drawRRect(rect, indicatorPaint);
    } else {
      final x = size.width * normalized;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, 2, 4, size.height - 4),
        const Radius.circular(2),
      );

      canvas.drawRRect(rect, glowPaint);
      canvas.drawRRect(rect, indicatorPaint);
    }
  }

  void _drawPeakHold(Canvas canvas, Size size) {
    final peakPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Min peak (usually the problematic one)
    final minNormalized = (peakMin + 1.0) / 2.0;
    // Max peak
    final maxNormalized = (peakMax + 1.0) / 2.0;

    if (vertical) {
      final yMin = size.height * (1 - minNormalized);
      final yMax = size.height * (1 - maxNormalized);
      canvas.drawLine(Offset(0, yMin), Offset(size.width, yMin), peakPaint);
      canvas.drawLine(Offset(0, yMax), Offset(size.width, yMax), peakPaint);
    } else {
      final xMin = size.width * minNormalized;
      final xMax = size.width * maxNormalized;
      canvas.drawLine(Offset(xMin, 0), Offset(xMin, size.height), peakPaint);
      canvas.drawLine(Offset(xMax, 0), Offset(xMax, size.height), peakPaint);
    }
  }

  LinearGradient _getHorizontalGradient() {
    _cachedGradientH ??= const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0x40FF4040), // Red (out of phase) -1
        Color(0x40FF9040), // Orange (phase issues)
        Color(0x40FFFF40), // Yellow (partial) 0
        Color(0x4040FF90), // Green (good) +0.5
        Color(0x4040FF90), // Green (mono) +1
      ],
      stops: [0.0, 0.25, 0.5, 0.75, 1.0],
    );
    return _cachedGradientH!;
  }

  LinearGradient _getVerticalGradient() {
    _cachedGradientV ??= const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0x40FF4040), // Red (out of phase) -1
        Color(0x40FF9040), // Orange (phase issues)
        Color(0x40FFFF40), // Yellow (partial) 0
        Color(0x4040FF90), // Green (good) +0.5
        Color(0x4040FF90), // Green (mono) +1
      ],
      stops: [0.0, 0.25, 0.5, 0.75, 1.0],
    );
    return _cachedGradientV!;
  }

  @override
  bool shouldRepaint(_CorrelationMeterPainter oldDelegate) {
    const threshold = 0.005;
    return (correlation - oldDelegate.correlation).abs() > threshold ||
        (peakMin - oldDelegate.peakMin).abs() > threshold ||
        (peakMax - oldDelegate.peakMax).abs() > threshold ||
        zoneColor != oldDelegate.zoneColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Calculate correlation coefficient from L/R sample arrays
///
/// Formula: correlation = (L · R) / sqrt((L · L) * (R · R))
///
/// Returns:
/// - +1.0: Mono (identical signals)
/// - 0.0: Uncorrelated (independent signals)
/// - -1.0: Out of phase (inverted signals)
double calculateCorrelationFromSamples(Float32List left, Float32List right) {
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
