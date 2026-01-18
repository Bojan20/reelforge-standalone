/// Glass Pro Meter - Liquid Glass Theme
///
/// Professional broadcast-quality metering with Liquid Glass styling:
/// - Frosted glass background with blur effects
/// - Gradient meters with glow
/// - Translucent overlays and highlights
/// - Glass-styled LUFS and correlation displays

import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../theme/liquid_glass_theme.dart';
import 'pro_meter.dart';

// ═══════════════════════════════════════════════════════════════════════════
// THEME-AWARE PRO METER
// ═══════════════════════════════════════════════════════════════════════════

/// Theme-aware pro meter that switches between Classic and Glass styles
class ThemeAwareProMeter extends StatelessWidget {
  final MeterReadings readings;
  final MeterMode mode;
  final MeterOrientation orientation;
  final double width;
  final double height;
  final bool showLabels;
  final bool showPeakHold;
  final Duration peakHoldTime;
  final VoidCallback? onClipReset;

  const ThemeAwareProMeter({
    super.key,
    required this.readings,
    this.mode = MeterMode.peak,
    this.orientation = MeterOrientation.vertical,
    this.width = 24,
    this.height = 200,
    this.showLabels = true,
    this.showPeakHold = true,
    this.peakHoldTime = const Duration(seconds: 2),
    this.onClipReset,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassProMeter(
        readings: readings,
        mode: mode,
        orientation: orientation,
        width: width,
        height: height,
        showLabels: showLabels,
        showPeakHold: showPeakHold,
        peakHoldTime: peakHoldTime,
        onClipReset: onClipReset,
      );
    }

    return ProMeter(
      readings: readings,
      mode: mode,
      orientation: orientation,
      width: width,
      height: height,
      showLabels: showLabels,
      showPeakHold: showPeakHold,
      peakHoldTime: peakHoldTime,
      onClipReset: onClipReset,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS PRO METER
// ═══════════════════════════════════════════════════════════════════════════

class GlassProMeter extends StatefulWidget {
  final MeterReadings readings;
  final MeterMode mode;
  final MeterOrientation orientation;
  final double width;
  final double height;
  final bool showLabels;
  final bool showPeakHold;
  final Duration peakHoldTime;
  final VoidCallback? onClipReset;

  const GlassProMeter({
    super.key,
    required this.readings,
    this.mode = MeterMode.peak,
    this.orientation = MeterOrientation.vertical,
    this.width = 24,
    this.height = 200,
    this.showLabels = true,
    this.showPeakHold = true,
    this.peakHoldTime = const Duration(seconds: 2),
    this.onClipReset,
  });

  @override
  State<GlassProMeter> createState() => _GlassProMeterState();
}

class _GlassProMeterState extends State<GlassProMeter> {
  double _peakHoldLeft = 0;
  double _peakHoldRight = 0;
  DateTime _lastPeakUpdateLeft = DateTime.now();
  DateTime _lastPeakUpdateRight = DateTime.now();

  double _smoothedLeft = 0;
  double _smoothedRight = 0;

  @override
  void didUpdateWidget(GlassProMeter oldWidget) {
    super.didUpdateWidget(oldWidget);

    final now = DateTime.now();

    // Left channel
    if (widget.readings.peakLeft > _peakHoldLeft) {
      _peakHoldLeft = widget.readings.peakLeft;
      _lastPeakUpdateLeft = now;
    } else if (now.difference(_lastPeakUpdateLeft) > widget.peakHoldTime) {
      _peakHoldLeft = widget.readings.peakLeft;
    }

    // Right channel
    if (widget.readings.peakRight > _peakHoldRight) {
      _peakHoldRight = widget.readings.peakRight;
      _lastPeakUpdateRight = now;
    } else if (now.difference(_lastPeakUpdateRight) > widget.peakHoldTime) {
      _peakHoldRight = widget.readings.peakRight;
    }

    _applyBallistics();
  }

  void _applyBallistics() {
    double attackCoeff, releaseCoeff;

    switch (widget.mode) {
      case MeterMode.vu:
        attackCoeff = 0.3;
        releaseCoeff = 0.3;
        break;
      case MeterMode.ppm:
        attackCoeff = 0.7;
        releaseCoeff = 0.05;
        break;
      default:
        attackCoeff = 0.9;
        releaseCoeff = 0.3;
    }

    final targetLeft = widget.readings.peakLeft;
    if (targetLeft > _smoothedLeft) {
      _smoothedLeft += (targetLeft - _smoothedLeft) * attackCoeff;
    } else {
      _smoothedLeft += (targetLeft - _smoothedLeft) * releaseCoeff;
    }

    final targetRight = widget.readings.peakRight;
    if (targetRight > _smoothedRight) {
      _smoothedRight += (targetRight - _smoothedRight) * attackCoeff;
    } else {
      _smoothedRight += (targetRight - _smoothedRight) * releaseCoeff;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClipReset,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: LiquidGlassTheme.blurLight,
            sigmaY: LiquidGlassTheme.blurLight,
          ),
          child: CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _GlassProMeterPainter(
              readings: widget.readings,
              mode: widget.mode,
              orientation: widget.orientation,
              showLabels: widget.showLabels,
              showPeakHold: widget.showPeakHold,
              peakHoldLeft: _peakHoldLeft,
              peakHoldRight: _peakHoldRight,
              smoothedLeft: _smoothedLeft,
              smoothedRight: _smoothedRight,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _GlassProMeterPainter extends CustomPainter {
  final MeterReadings readings;
  final MeterMode mode;
  final MeterOrientation orientation;
  final bool showLabels;
  final bool showPeakHold;
  final double peakHoldLeft;
  final double peakHoldRight;
  final double smoothedLeft;
  final double smoothedRight;

  _GlassProMeterPainter({
    required this.readings,
    required this.mode,
    required this.orientation,
    required this.showLabels,
    required this.showPeakHold,
    required this.peakHoldLeft,
    required this.peakHoldRight,
    required this.smoothedLeft,
    required this.smoothedRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Glass background
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.06),
        Colors.black.withValues(alpha: 0.2),
      ],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(6),
      ),
      Paint()..shader = bgGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(6),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 1,
    );

    if (orientation == MeterOrientation.vertical) {
      _paintVertical(canvas, size);
    } else {
      _paintHorizontal(canvas, size);
    }
  }

  void _paintVertical(Canvas canvas, Size size) {
    final labelWidth = showLabels ? 24.0 : 0.0;
    final meterWidth = (size.width - labelWidth) / 2 - 2;
    final meterHeight = size.height - 4;

    // Meter backgrounds
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelWidth, 2, size.width - labelWidth, meterHeight),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Draw scale labels
    if (showLabels) {
      _drawGlassScaleLabels(canvas, Size(labelWidth, meterHeight), 2);
    }

    // Left meter
    _drawGlassMeterBar(
      canvas,
      Rect.fromLTWH(labelWidth + 1, 2, meterWidth, meterHeight),
      smoothedLeft,
      peakHoldLeft,
      readings.clippedLeft,
      readings.rmsLeft,
    );

    // Right meter
    _drawGlassMeterBar(
      canvas,
      Rect.fromLTWH(labelWidth + meterWidth + 3, 2, meterWidth, meterHeight),
      smoothedRight,
      peakHoldRight,
      readings.clippedRight,
      readings.rmsRight,
    );

    // Clip indicators
    _drawGlassClipIndicators(canvas, size, labelWidth);
  }

  void _paintHorizontal(Canvas canvas, Size size) {
    // TODO: Implement horizontal meter
  }

  void _drawGlassMeterBar(
    Canvas canvas,
    Rect rect,
    double level,
    double peakHold,
    bool clipped,
    double rmsLevel,
  ) {
    final db = 20 * math.log(level.clamp(1e-10, 10)) / math.ln10;
    final normalizedLevel = _dbToNormalized(db);
    final barHeight = rect.height * normalizedLevel;

    // Gradient for meter bar
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        LiquidGlassTheme.accentCyan,
        LiquidGlassTheme.accentGreen,
        LiquidGlassTheme.accentYellow,
        LiquidGlassTheme.accentOrange,
        LiquidGlassTheme.accentRed,
      ],
      stops: const [0.0, 0.3, 0.6, 0.85, 1.0],
    ).createShader(rect);

    final meterPaint = Paint()..shader = gradient;

    // Draw meter bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.bottom - barHeight, rect.width, barHeight),
        const Radius.circular(2),
      ),
      meterPaint,
    );

    // Glow at top of meter
    if (barHeight > 4) {
      final glowColor = _getColorForLevel(normalizedLevel);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - barHeight, rect.width, 4),
        Paint()
          ..color = glowColor.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // RMS overlay
    final rmsDb = 20 * math.log(rmsLevel.clamp(1e-10, 10)) / math.ln10;
    final rmsNormalized = _dbToNormalized(rmsDb);
    final rmsHeight = rect.height * rmsNormalized;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.bottom - rmsHeight, rect.width, rmsHeight),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.2),
    );

    // Peak hold line
    if (showPeakHold) {
      final peakDb = 20 * math.log(peakHold.clamp(1e-10, 10)) / math.ln10;
      final peakNormalized = _dbToNormalized(peakDb);
      final peakY = rect.bottom - rect.height * peakNormalized;

      canvas.drawLine(
        Offset(rect.left, peakY),
        Offset(rect.right, peakY),
        Paint()
          ..color = peakDb > -3 ? LiquidGlassTheme.accentRed : Colors.white
          ..strokeWidth = 2,
      );

      // Glow for peak hold
      canvas.drawLine(
        Offset(rect.left, peakY),
        Offset(rect.right, peakY),
        Paint()
          ..color = (peakDb > -3 ? LiquidGlassTheme.accentRed : Colors.white)
              .withValues(alpha: 0.5)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // Segment lines
    final segmentPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    final segments = [-60, -48, -36, -24, -18, -12, -6, -3, 0, 3];
    for (final seg in segments) {
      final segNormalized = _dbToNormalized(seg.toDouble());
      final segY = rect.bottom - rect.height * segNormalized;
      canvas.drawLine(
        Offset(rect.left, segY),
        Offset(rect.right, segY),
        segmentPaint,
      );
    }
  }

  void _drawGlassScaleLabels(Canvas canvas, Size size, double offsetY) {
    final textStyle = ui.TextStyle(
      color: LiquidGlassTheme.textTertiary,
      fontSize: 9,
      fontFamily: 'JetBrains Mono',
    );

    final labels = _getScaleLabels();

    for (final entry in labels.entries) {
      final normalized = _dbToNormalized(entry.key);
      final y = offsetY + size.height * (1 - normalized);

      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.right,
          fontSize: 9,
        ),
      )
        ..pushStyle(textStyle)
        ..addText(entry.value);

      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: size.width - 2));

      canvas.drawParagraph(paragraph, Offset(0, y - 5));
    }
  }

  void _drawGlassClipIndicators(Canvas canvas, Size size, double labelWidth) {
    final indicatorSize = 8.0;
    final indicatorY = 2.0;

    // Left clip indicator
    final leftClipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelWidth + 1,
        indicatorY,
        (size.width - labelWidth - 4) / 2,
        indicatorSize,
      ),
      const Radius.circular(2),
    );

    canvas.drawRRect(
      leftClipRect,
      Paint()
        ..color = readings.clippedLeft
            ? LiquidGlassTheme.accentRed
            : Colors.black.withValues(alpha: 0.3),
    );

    if (readings.clippedLeft) {
      canvas.drawRRect(
        leftClipRect,
        Paint()
          ..color = LiquidGlassTheme.accentRed.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Right clip indicator
    final rightClipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelWidth + (size.width - labelWidth) / 2 + 1,
        indicatorY,
        (size.width - labelWidth - 4) / 2,
        indicatorSize,
      ),
      const Radius.circular(2),
    );

    canvas.drawRRect(
      rightClipRect,
      Paint()
        ..color = readings.clippedRight
            ? LiquidGlassTheme.accentRed
            : Colors.black.withValues(alpha: 0.3),
    );

    if (readings.clippedRight) {
      canvas.drawRRect(
        rightClipRect,
        Paint()
          ..color = LiquidGlassTheme.accentRed.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  Color _getColorForLevel(double level) {
    if (level > 0.85) return LiquidGlassTheme.accentRed;
    if (level > 0.6) return LiquidGlassTheme.accentOrange;
    if (level > 0.3) return LiquidGlassTheme.accentYellow;
    return LiquidGlassTheme.accentGreen;
  }

  Map<double, String> _getScaleLabels() {
    switch (mode) {
      case MeterMode.vu:
        return {
          -18: '0',
          -15: '+3',
          -12: '+6',
          -8: '+10',
          -28: '-10',
          -38: '-20',
        };

      case MeterMode.k12:
      case MeterMode.k14:
      case MeterMode.k20:
        final offset = mode == MeterMode.k12
            ? -12
            : mode == MeterMode.k14
                ? -14
                : -20;
        return {
          0.0: '0',
          -3.0: '-3',
          -6.0: '-6',
          -12.0: '-12',
          -18.0: '-18',
          offset.toDouble(): 'K',
        };

      case MeterMode.lufs:
        return {
          -14.0: '-14',
          -18.0: '-18',
          -23.0: '-23',
          -30.0: '-30',
          -40.0: '-40',
        };

      default:
        return {
          0.0: '0',
          -3.0: '-3',
          -6.0: '-6',
          -12.0: '-12',
          -18.0: '-18',
          -24.0: '-24',
          -36.0: '-36',
          -48.0: '-48',
          -60.0: '-60',
        };
    }
  }

  double _dbToNormalized(double db) {
    const minDb = -60.0;
    const maxDb = 3.0;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_GlassProMeterPainter oldDelegate) =>
      readings != oldDelegate.readings ||
      smoothedLeft != oldDelegate.smoothedLeft ||
      smoothedRight != oldDelegate.smoothedRight ||
      peakHoldLeft != oldDelegate.peakHoldLeft ||
      peakHoldRight != oldDelegate.peakHoldRight;
}

// ═══════════════════════════════════════════════════════════════════════════
// THEME-AWARE STEREO METER STRIP
// ═══════════════════════════════════════════════════════════════════════════

class ThemeAwareStereoMeterStrip extends StatelessWidget {
  final MeterReadings readings;
  final MeterMode primaryMode;
  final bool showCorrelation;
  final bool showLufs;
  final bool showTruePeak;
  final double width;
  final double height;

  const ThemeAwareStereoMeterStrip({
    super.key,
    required this.readings,
    this.primaryMode = MeterMode.peak,
    this.showCorrelation = true,
    this.showLufs = true,
    this.showTruePeak = true,
    this.width = 80,
    this.height = 250,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassStereoMeterStrip(
        readings: readings,
        primaryMode: primaryMode,
        showCorrelation: showCorrelation,
        showLufs: showLufs,
        showTruePeak: showTruePeak,
        width: width,
        height: height,
      );
    }

    return StereoMeterStrip(
      readings: readings,
      primaryMode: primaryMode,
      showCorrelation: showCorrelation,
      showLufs: showLufs,
      showTruePeak: showTruePeak,
      width: width,
      height: height,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS STEREO METER STRIP
// ═══════════════════════════════════════════════════════════════════════════

class GlassStereoMeterStrip extends StatelessWidget {
  final MeterReadings readings;
  final MeterMode primaryMode;
  final bool showCorrelation;
  final bool showLufs;
  final bool showTruePeak;
  final double width;
  final double height;

  const GlassStereoMeterStrip({
    super.key,
    required this.readings,
    this.primaryMode = MeterMode.peak,
    this.showCorrelation = true,
    this.showLufs = true,
    this.showTruePeak = true,
    this.width = 80,
    this.height = 250,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurLight,
          sigmaY: LiquidGlassTheme.blurLight,
        ),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.black.withValues(alpha: 0.15),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Mode label
              _buildGlassHeader(),

              // Main meter
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: GlassProMeter(
                    readings: readings,
                    mode: primaryMode,
                    width: width - 8,
                  ),
                ),
              ),

              // LUFS display
              if (showLufs) _buildGlassLufsDisplay(),

              // True peak display
              if (showTruePeak) _buildGlassTruePeakDisplay(),

              // Correlation meter
              if (showCorrelation) _buildGlassCorrelationMeter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassHeader() {
    return Container(
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Text(
        _modeName,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: LiquidGlassTheme.textSecondary,
        ),
      ),
    );
  }

  String get _modeName {
    switch (primaryMode) {
      case MeterMode.vu:
        return 'VU';
      case MeterMode.ppm:
        return 'PPM';
      case MeterMode.k12:
        return 'K-12';
      case MeterMode.k14:
        return 'K-14';
      case MeterMode.k20:
        return 'K-20';
      case MeterMode.lufs:
        return 'LUFS';
      case MeterMode.truePeak:
        return 'TP';
      default:
        return 'PEAK';
    }
  }

  Widget _buildGlassLufsDisplay() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LUFS',
                style: TextStyle(
                  fontSize: 8,
                  color: LiquidGlassTheme.textTertiary,
                ),
              ),
              Text(
                readings.lufsIntegrated > -70
                    ? readings.lufsIntegrated.toStringAsFixed(1)
                    : '-∞',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'JetBrains Mono',
                  color: readings.lufsIntegrated > -14
                      ? LiquidGlassTheme.accentRed
                      : readings.lufsIntegrated > -23
                          ? LiquidGlassTheme.accentOrange
                          : LiquidGlassTheme.textPrimary,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LRA',
                style: TextStyle(
                  fontSize: 8,
                  color: LiquidGlassTheme.textTertiary,
                ),
              ),
              Text(
                '${readings.lufsRange.toStringAsFixed(1)} LU',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'JetBrains Mono',
                  color: LiquidGlassTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassTruePeakDisplay() {
    final truePeakDb = readings.truePeakDb;
    final isOver = truePeakDb > -1;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: isOver
            ? LinearGradient(
                colors: [
                  LiquidGlassTheme.accentRed.withValues(alpha: 0.3),
                  LiquidGlassTheme.accentRed.withValues(alpha: 0.1),
                ],
              )
            : null,
        color: isOver ? null : Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TP',
            style: TextStyle(
              fontSize: 9,
              color: LiquidGlassTheme.textTertiary,
            ),
          ),
          Text(
            truePeakDb > -60 ? '${truePeakDb.toStringAsFixed(1)} dB' : '-∞',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono',
              color: isOver
                  ? LiquidGlassTheme.accentRed
                  : LiquidGlassTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCorrelationMeter() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Text(
            'L',
            style: TextStyle(
              fontSize: 8,
              color: LiquidGlassTheme.textTertiary,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: CustomPaint(
                painter: _GlassCorrelationPainter(
                    correlation: readings.correlation),
                size: const Size(double.infinity, 12),
              ),
            ),
          ),
          Text(
            'R',
            style: TextStyle(
              fontSize: 8,
              color: LiquidGlassTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS CORRELATION PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _GlassCorrelationPainter extends CustomPainter {
  final double correlation;

  _GlassCorrelationPainter({required this.correlation});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 2, size.width, size.height - 4),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Center line
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..strokeWidth = 1,
    );

    // Correlation indicator
    final normalizedPos = (correlation + 1) / 2;
    final indicatorX = normalizedPos * size.width;

    final indicatorColor = correlation < 0
        ? LiquidGlassTheme.accentRed
        : correlation < 0.5
            ? LiquidGlassTheme.accentOrange
            : LiquidGlassTheme.accentGreen;

    // Draw indicator
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(indicatorX - 2, 2, 4, size.height - 4),
        const Radius.circular(2),
      ),
      Paint()..color = indicatorColor,
    );

    // Glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(indicatorX - 3, 1, 6, size.height - 2),
        const Radius.circular(3),
      ),
      Paint()
        ..color = indicatorColor.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_GlassCorrelationPainter oldDelegate) =>
      correlation != oldDelegate.correlation;
}
