// Professional Metering Widget
//
// Broadcast-quality metering with:
// - VU meter (analog-style with ballistics)
// - PPM meter (Peak Programme Meter - EBU/BBC)
// - K-System (K-12, K-14, K-20)
// - LUFS (EBU R128 loudness)
// - True Peak (intersample detection)
// - Phase correlation meter
//
// Based on ITU-R BS.1770-4, EBU R128, AES17

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// METER TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Meter mode
enum MeterMode {
  peak,       // Simple peak meter
  vu,         // VU meter with slow ballistics (300ms)
  ppm,        // Peak Programme Meter (BBC/EBU)
  k12,        // K-System K-12 (broadcast)
  k14,        // K-System K-14 (music)
  k20,        // K-System K-20 (cinema/classical)
  lufs,       // EBU R128 loudness
  truePeak,   // Intersample true peak
}

/// Meter scale type
enum MeterScale {
  dbfs,       // 0 dBFS = digital full scale
  dbVu,       // 0 VU = -18 dBFS
  dbK,        // K-System scale
}

/// Meter orientation
enum MeterOrientation {
  vertical,
  horizontal,
}

// ═══════════════════════════════════════════════════════════════════════════════
// METER DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Meter readings
class MeterReadings {
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final double truePeakLeft;
  final double truePeakRight;
  final double lufsShort;    // Short-term LUFS (3s)
  final double lufsMomentary; // Momentary LUFS (400ms)
  final double lufsIntegrated; // Integrated LUFS
  final double lufsRange;    // Loudness range (LRA)
  final double correlation;  // Stereo correlation (-1 to +1)
  final bool clippedLeft;
  final bool clippedRight;

  const MeterReadings({
    this.peakLeft = 0,
    this.peakRight = 0,
    this.rmsLeft = 0,
    this.rmsRight = 0,
    this.truePeakLeft = 0,
    this.truePeakRight = 0,
    this.lufsShort = -70,
    this.lufsMomentary = -70,
    this.lufsIntegrated = -70,
    this.lufsRange = 0,
    this.correlation = 1.0,
    this.clippedLeft = false,
    this.clippedRight = false,
  });

  static const zero = MeterReadings();

  double get peakDb => 20 * math.log(math.max(peakLeft, peakRight).clamp(1e-10, 10)) / math.ln10;
  double get rmsDb => 20 * math.log(math.max(rmsLeft, rmsRight).clamp(1e-10, 10)) / math.ln10;
  double get truePeakDb => 20 * math.log(math.max(truePeakLeft, truePeakRight).clamp(1e-10, 10)) / math.ln10;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRO METER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Professional meter widget
class ProMeter extends StatefulWidget {
  final MeterReadings readings;
  final MeterMode mode;
  final MeterOrientation orientation;
  final double width;
  final double height;
  final bool showLabels;
  final bool showPeakHold;
  final Duration peakHoldTime;
  final VoidCallback? onClipReset;

  const ProMeter({
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
  State<ProMeter> createState() => _ProMeterState();
}

class _ProMeterState extends State<ProMeter> with SingleTickerProviderStateMixin {
  double _peakHoldLeft = 0;
  double _peakHoldRight = 0;
  DateTime _lastPeakUpdateLeft = DateTime.now();
  DateTime _lastPeakUpdateRight = DateTime.now();

  // Smoothed values for VU/PPM ballistics
  double _smoothedLeft = 0;
  double _smoothedRight = 0;

  @override
  void didUpdateWidget(ProMeter oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update peak hold
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

    // Apply ballistics based on meter mode
    _applyBallistics();
  }

  void _applyBallistics() {
    // Ballistics coefficients
    double attackCoeff, releaseCoeff;

    switch (widget.mode) {
      case MeterMode.vu:
        // VU: 300ms integration time
        attackCoeff = 0.3;
        releaseCoeff = 0.3;
        break;
      case MeterMode.ppm:
        // PPM: 10ms attack, 1.5s release
        attackCoeff = 0.7;
        releaseCoeff = 0.05;
        break;
      default:
        // Peak: instant attack, fast release
        attackCoeff = 0.9;
        releaseCoeff = 0.3;
    }

    // Smooth left
    final targetLeft = widget.readings.peakLeft;
    if (targetLeft > _smoothedLeft) {
      _smoothedLeft += (targetLeft - _smoothedLeft) * attackCoeff;
    } else {
      _smoothedLeft += (targetLeft - _smoothedLeft) * releaseCoeff;
    }

    // Smooth right
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
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: _ProMeterPainter(
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _ProMeterPainter extends CustomPainter {
  final MeterReadings readings;
  final MeterMode mode;
  final MeterOrientation orientation;
  final bool showLabels;
  final bool showPeakHold;
  final double peakHoldLeft;
  final double peakHoldRight;
  final double smoothedLeft;
  final double smoothedRight;

  _ProMeterPainter({
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

    // Background
    final bgPaint = Paint()..color = FluxForgeTheme.bgDeepest;
    canvas.drawRect(Rect.fromLTWH(labelWidth, 2, size.width - labelWidth, meterHeight), bgPaint);

    // Draw scale labels
    if (showLabels) {
      _drawScaleLabels(canvas, Size(labelWidth, meterHeight), 2);
    }

    // Left meter
    _drawMeterBar(
      canvas,
      Rect.fromLTWH(labelWidth + 1, 2, meterWidth, meterHeight),
      smoothedLeft,
      peakHoldLeft,
      readings.clippedLeft,
      false, // isRightChannel
    );

    // Right meter
    _drawMeterBar(
      canvas,
      Rect.fromLTWH(labelWidth + meterWidth + 3, 2, meterWidth, meterHeight),
      smoothedRight,
      peakHoldRight,
      readings.clippedRight,
      true, // isRightChannel
    );

    // Clip indicators
    _drawClipIndicators(canvas, size, labelWidth);
  }

  void _paintHorizontal(Canvas canvas, Size size) {
    // TODO: Implement horizontal meter
  }

  void _drawMeterBar(
    Canvas canvas,
    Rect rect,
    double level,
    double peakHold,
    bool clipped,
    bool isRightChannel,
  ) {
    // Convert level to dB and then to normalized position
    final db = 20 * math.log(level.clamp(1e-10, 10)) / math.ln10;
    final normalizedLevel = _dbToNormalized(db);
    final barHeight = rect.height * normalizedLevel;

    // Gradient for meter bar
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: const [
        FluxForgeTheme.accentCyan, // Blue (low)
        FluxForgeTheme.accentGreen, // Green (mid-low)
        FluxForgeTheme.accentYellow, // Yellow (mid)
        FluxForgeTheme.accentOrange, // Orange (high)
        FluxForgeTheme.accentRed, // Red (peak)
      ],
      stops: const [0.0, 0.3, 0.6, 0.85, 1.0],
    ).createShader(rect);

    final meterPaint = Paint()..shader = gradient;

    // Draw meter bar from bottom
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.bottom - barHeight, rect.width, barHeight),
      meterPaint,
    );

    // Draw RMS overlay (darker, showing average level)
    final rmsLevel = isRightChannel ? readings.rmsRight : readings.rmsLeft;
    final rmsDb = 20 * math.log(rmsLevel.clamp(1e-10, 10)) / math.ln10;
    final rmsNormalized = _dbToNormalized(rmsDb);
    final rmsHeight = rect.height * rmsNormalized;

    final rmsPaint = Paint()
      ..color = FluxForgeTheme.textPrimary.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.bottom - rmsHeight, rect.width, rmsHeight),
      rmsPaint,
    );

    // Peak hold line
    if (showPeakHold) {
      final peakDb = 20 * math.log(peakHold.clamp(1e-10, 10)) / math.ln10;
      final peakNormalized = _dbToNormalized(peakDb);
      final peakY = rect.bottom - rect.height * peakNormalized;

      final peakPaint = Paint()
        ..color = peakDb > -3 ? FluxForgeTheme.accentRed : FluxForgeTheme.textPrimary
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(rect.left, peakY),
        Offset(rect.right, peakY),
        peakPaint,
      );
    }

    // Draw segment lines (tick marks)
    final segmentPaint = Paint()
      ..color = FluxForgeTheme.bgDeepest.withValues(alpha: 0.5)
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

  void _drawScaleLabels(Canvas canvas, Size size, double offsetY) {
    final textStyle = ui.TextStyle(
      color: FluxForgeTheme.textTertiary,
      fontSize: 9,
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

  void _drawClipIndicators(Canvas canvas, Size size, double labelWidth) {
    final indicatorSize = 8.0;
    final indicatorY = 2.0;

    // Left clip indicator
    final leftClipRect = Rect.fromLTWH(
      labelWidth + 1,
      indicatorY,
      (size.width - labelWidth - 4) / 2,
      indicatorSize,
    );

    final leftClipPaint = Paint()
      ..color = readings.clippedLeft
          ? FluxForgeTheme.accentRed
          : FluxForgeTheme.bgMid;

    canvas.drawRect(leftClipRect, leftClipPaint);

    // Right clip indicator
    final rightClipRect = Rect.fromLTWH(
      labelWidth + (size.width - labelWidth) / 2 + 1,
      indicatorY,
      (size.width - labelWidth - 4) / 2,
      indicatorSize,
    );

    final rightClipPaint = Paint()
      ..color = readings.clippedRight
          ? FluxForgeTheme.accentRed
          : FluxForgeTheme.bgMid;

    canvas.drawRect(rightClipRect, rightClipPaint);
  }

  Map<double, String> _getScaleLabels() {
    switch (mode) {
      case MeterMode.vu:
        // VU scale (0 VU = -18 dBFS)
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
        // dBFS scale
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
    // Map dB to 0-1 range
    // -60 dB = 0, 0 dB = ~0.9, +3 dB = 1
    final minDb = -60.0;
    final maxDb = 3.0;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_ProMeterPainter oldDelegate) =>
      readings != oldDelegate.readings ||
      smoothedLeft != oldDelegate.smoothedLeft ||
      smoothedRight != oldDelegate.smoothedRight ||
      peakHoldLeft != oldDelegate.peakHoldLeft ||
      peakHoldRight != oldDelegate.peakHoldRight;
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO METER STRIP
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete stereo meter strip with multiple meter types
class StereoMeterStrip extends StatelessWidget {
  final MeterReadings readings;
  final MeterMode primaryMode;
  final bool showCorrelation;
  final bool showLufs;
  final bool showTruePeak;
  final double width;
  final double height;

  const StereoMeterStrip({
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Mode label
          Container(
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: Text(
              _modeName,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),

          // Main meter
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ProMeter(
                readings: readings,
                mode: primaryMode,
                width: width - 8,
              ),
            ),
          ),

          // LUFS display
          if (showLufs) _buildLufsDisplay(),

          // True peak display
          if (showTruePeak) _buildTruePeakDisplay(),

          // Correlation meter
          if (showCorrelation) _buildCorrelationMeter(),
        ],
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

  Widget _buildLufsDisplay() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
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
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
              Text(
                readings.lufsIntegrated > -70
                    ? readings.lufsIntegrated.toStringAsFixed(1)
                    : '-∞',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: readings.lufsIntegrated > -14
                      ? FluxForgeTheme.accentRed
                      : readings.lufsIntegrated > -23
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.textPrimary,
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
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
              Text(
                '${readings.lufsRange.toStringAsFixed(1)} LU',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTruePeakDisplay() {
    final truePeakDb = readings.truePeakDb;
    final isOver = truePeakDb > -1;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isOver
            ? FluxForgeTheme.accentRed.withAlpha(51)
            : FluxForgeTheme.bgDeepest,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TP',
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          Text(
            truePeakDb > -60 ? '${truePeakDb.toStringAsFixed(1)} dB' : '-∞',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: isOver ? FluxForgeTheme.accentRed : FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorrelationMeter() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
      ),
      child: Row(
        children: [
          Text(
            'L',
            style: TextStyle(
              fontSize: 8,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: CustomPaint(
                painter: _CorrelationPainter(correlation: readings.correlation),
                size: const Size(double.infinity, 12),
              ),
            ),
          ),
          Text(
            'R',
            style: TextStyle(
              fontSize: 8,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CORRELATION METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _CorrelationPainter extends CustomPainter {
  final double correlation;

  _CorrelationPainter({required this.correlation});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = FluxForgeTheme.bgMid;
    canvas.drawRect(Rect.fromLTWH(0, 2, size.width, size.height - 4), bgPaint);

    // Center line
    final centerPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );

    // Correlation indicator
    // -1 (out of phase) = left, 0 = center, +1 (in phase) = right
    final normalizedPos = (correlation + 1) / 2; // 0 to 1
    final indicatorX = normalizedPos * size.width;

    final indicatorColor = correlation < 0
        ? FluxForgeTheme.accentRed // Out of phase - red
        : correlation < 0.5
            ? FluxForgeTheme.accentOrange // Low correlation - orange
            : FluxForgeTheme.accentGreen; // Good correlation - green

    final indicatorPaint = Paint()
      ..color = indicatorColor
      ..style = PaintingStyle.fill;

    // Draw indicator as vertical bar
    canvas.drawRect(
      Rect.fromLTWH(indicatorX - 2, 2, 4, size.height - 4),
      indicatorPaint,
    );
  }

  @override
  bool shouldRepaint(_CorrelationPainter oldDelegate) =>
      correlation != oldDelegate.correlation;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LUFS METER
// ═══════════════════════════════════════════════════════════════════════════════

/// EBU R128 loudness meter
class LufsMeter extends StatelessWidget {
  final MeterReadings readings;
  final double width;
  final double height;

  const LufsMeter({
    super.key,
    required this.readings,
    this.width = 120,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: Text(
              'LOUDNESS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),

          // Main LUFS display
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLufsValue('M', readings.lufsMomentary, 'Momentary'),
                  _buildLufsValue('S', readings.lufsShort, 'Short-term'),
                  _buildLufsValue('I', readings.lufsIntegrated, 'Integrated'),
                  _buildLraDisplay(),
                ],
              ),
            ),
          ),

          // Target indicator
          _buildTargetIndicator(),
        ],
      ),
    );
  }

  Widget _buildLufsValue(String label, double value, String description) {
    final isValid = value > -70;
    final color = value > -14
        ? FluxForgeTheme.accentRed
        : value > -23
            ? FluxForgeTheme.accentGreen
            : FluxForgeTheme.textPrimary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: 8,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
        Text(
          isValid ? value.toStringAsFixed(1) : '-∞',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
        Text(
          'LUFS',
          style: TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildLraDisplay() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'LRA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
          Text(
            '${readings.lufsRange.toStringAsFixed(1)} LU',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: FluxForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetIndicator() {
    // EBU R128 target: -23 LUFS
    final isOnTarget = readings.lufsIntegrated >= -24 && readings.lufsIntegrated <= -22;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isOnTarget
            ? FluxForgeTheme.accentGreen.withAlpha(51)
            : FluxForgeTheme.bgDeepest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOnTarget ? Icons.check_circle : Icons.info_outline,
            size: 14,
            color: isOnTarget
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            'Target: -23 LUFS',
            style: TextStyle(
              fontSize: 10,
              color: isOnTarget
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
