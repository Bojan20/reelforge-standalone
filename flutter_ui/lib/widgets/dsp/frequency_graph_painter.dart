/// Frequency Graph Custom Painter
///
/// GPU-accelerated CustomPainter for DSP transfer function visualization.
/// Renders:
/// - EQ frequency response curves (log frequency scale)
/// - Dynamics transfer curves (linear input/output dB scale)
/// - Grid lines (major/minor)
/// - Labels (frequency, dB)
/// - Interactive elements (threshold markers, current position)
///
/// Visual style: FF-Q inspired
/// - Anti-aliased curves
/// - Smooth gradients
/// - Color-coded by processor type

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/frequency_graph_data.dart';
import '../../services/dsp_frequency_calculator.dart';
import '../fabfilter/fabfilter_theme.dart';

// =============================================================================
// FREQUENCY GRAPH PAINTER
// =============================================================================

/// Custom painter for frequency response visualization
class FrequencyGraphPainter extends CustomPainter {
  /// Response data to visualize
  final FrequencyResponseData data;

  /// Display settings
  final FrequencyGraphSettings settings;

  /// Accent color for the curve
  final Color accentColor;

  /// Whether to show individual band curves (for EQ)
  final bool showBandCurves;

  /// Current input level for marker (optional)
  final double? currentInput;

  /// Whether the processor is bypassed
  final bool bypassed;

  FrequencyGraphPainter({
    required this.data,
    this.settings = const FrequencyGraphSettings(),
    Color? accentColor,
    this.showBandCurves = true,
    this.currentInput,
    this.bypassed = false,
  }) : accentColor = accentColor ?? _defaultColorForType(data.type);

  static Color _defaultColorForType(FrequencyProcessorType type) {
    return switch (type) {
      FrequencyProcessorType.eq => FabFilterColors.blue,
      FrequencyProcessorType.compressor => FabFilterColors.orange,
      FrequencyProcessorType.limiter => FabFilterColors.red,
      FrequencyProcessorType.gate => FabFilterColors.cyan,
      FrequencyProcessorType.expander => FabFilterColors.purple,
      FrequencyProcessorType.filter => FabFilterColors.blue,
      FrequencyProcessorType.reverb => FabFilterColors.cyan,
      FrequencyProcessorType.unknown => FabFilterColors.textSecondary,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Clip to bounds
    canvas.clipRect(rect);

    // Draw background
    _drawBackground(canvas, size);

    // Draw grid
    if (settings.showGrid) {
      _drawGrid(canvas, size);
    }

    // Draw content based on processor type
    if (data.isDynamics) {
      _drawDynamicsCurve(canvas, size);
    } else if (data.type == FrequencyProcessorType.reverb) {
      _drawReverbDecay(canvas, size);
    } else {
      _drawFrequencyResponse(canvas, size);
    }

    // Draw current input marker
    if (currentInput != null) {
      _drawCurrentInputMarker(canvas, size, currentInput!);
    }

    // Draw bypassed overlay
    if (bypassed) {
      _drawBypassedOverlay(canvas, size);
    }
  }

  // ===========================================================================
  // BACKGROUND
  // ===========================================================================

  void _drawBackground(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          FabFilterColors.bgVoid,
          FabFilterColors.bgDeep,
        ],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);
  }

  // ===========================================================================
  // GRID DRAWING
  // ===========================================================================

  void _drawGrid(Canvas canvas, Size size) {
    if (data.isDynamics) {
      _drawDynamicsGrid(canvas, size);
    } else if (data.type == FrequencyProcessorType.reverb) {
      _drawReverbGrid(canvas, size);
    } else {
      _drawFrequencyGrid(canvas, size);
    }
  }

  /// Draw frequency response grid (log scale X, linear dB Y)
  void _drawFrequencyGrid(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    final minorPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Vertical lines (frequency)
    final freqMarkers = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    final majorFreqs = {100, 1000, 10000};

    for (final freq in freqMarkers) {
      final x = _freqToX(freq.toDouble(), size.width);
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          majorFreqs.contains(freq) ? majorPaint : minorPaint,
        );

        // Labels
        if (settings.showFrequencyLabels && majorFreqs.contains(freq)) {
          _drawLabel(
            canvas,
            _formatFrequency(freq.toDouble()),
            Offset(x, size.height - 2),
            align: TextAlign.center,
            color: FabFilterColors.textTertiary,
            fontSize: 8,
          );
        }
      }
    }

    // Horizontal lines (dB)
    final dbRange = settings.maxDb - settings.minDb;
    final dbStep = dbRange <= 24 ? 6 : (dbRange <= 48 ? 12 : 24);

    for (var db = settings.minDb.ceil(); db <= settings.maxDb.floor(); db++) {
      if (db % dbStep != 0) continue;
      final y = _dbToY(db.toDouble(), size.height);

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        db == 0 ? majorPaint : minorPaint,
      );

      // Labels
      if (settings.showDbLabels) {
        _drawLabel(
          canvas,
          '${db >= 0 ? '+' : ''}$db',
          Offset(2, y - 10),
          color: db == 0 ? FabFilterColors.textSecondary : FabFilterColors.textTertiary,
          fontSize: 8,
        );
      }
    }

    // 0dB reference line (white dashed)
    if (settings.minDb <= 0 && settings.maxDb >= 0) {
      final y = _dbToY(0.0, size.height);
      final dashPaint = Paint()
        ..color = FabFilterColors.textMuted.withValues(alpha: 0.5)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), dashPaint, 4, 4);
    }
  }

  /// Draw dynamics transfer curve grid (linear X and Y, both in dB)
  void _drawDynamicsGrid(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    final minorPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Grid lines every 12dB
    for (var db = -60; db <= 6; db += 6) {
      // Vertical (input dB)
      final x = _inputDbToX(db.toDouble(), size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        db % 12 == 0 ? majorPaint : minorPaint,
      );

      // Horizontal (output dB)
      final y = _outputDbToY(db.toDouble(), size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        db % 12 == 0 ? majorPaint : minorPaint,
      );

      // Labels
      if (db % 12 == 0 && settings.showDbLabels) {
        // Input (bottom)
        _drawLabel(
          canvas,
          '$db',
          Offset(x, size.height - 2),
          align: TextAlign.center,
          fontSize: 8,
        );
        // Output (left)
        _drawLabel(
          canvas,
          '$db',
          Offset(2, y - 10),
          fontSize: 8,
        );
      }
    }

    // 1:1 diagonal reference line (dashed)
    final diagPaint = Paint()
      ..color = FabFilterColors.textMuted.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;
    _drawDashedLine(
      canvas,
      Offset(0, size.height),
      Offset(size.width, 0),
      diagPaint,
      4,
      4,
    );

    // Threshold line (vertical, orange)
    if (data.threshold != null) {
      final threshX = _inputDbToX(data.threshold!, size.width);
      final threshPaint = Paint()
        ..color = FabFilterColors.orange.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(threshX, 0), Offset(threshX, size.height), threshPaint);

      // Threshold label
      _drawLabel(
        canvas,
        '${data.threshold!.toStringAsFixed(0)}dB',
        Offset(threshX + 4, 12),
        color: FabFilterColors.orange,
        fontSize: 9,
      );
    }
  }

  /// Draw reverb decay grid
  void _drawReverbGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    // Frequency bands on X axis
    final bandFreqs = data.decayFrequencies ?? Float64List.fromList(DspFrequencyCalculator.reverbBandFrequencies);
    for (int i = 0; i < bandFreqs.length; i++) {
      final x = (i + 0.5) / bandFreqs.length * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Labels
      if (settings.showFrequencyLabels) {
        _drawLabel(
          canvas,
          _formatFrequency(bandFreqs[i]),
          Offset(x, size.height - 2),
          align: TextAlign.center,
          fontSize: 7,
        );
      }
    }

    // Decay time on Y axis (0 to 10 seconds)
    for (var sec = 0; sec <= 10; sec += 2) {
      final y = size.height * (1 - sec / 10.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      if (settings.showDbLabels) {
        _drawLabel(
          canvas,
          '${sec}s',
          Offset(2, y - 10),
          fontSize: 8,
        );
      }
    }
  }


  // ===========================================================================
  // FREQUENCY RESPONSE CURVE (EQ/FILTER)
  // ===========================================================================

  void _drawFrequencyResponse(Canvas canvas, Size size) {
    if (data.frequencies.isEmpty) return;

    // Draw individual band curves (semi-transparent)
    if (showBandCurves && data.bandMagnitudes != null) {
      for (final entry in data.bandMagnitudes!.entries) {
        final bandIdx = entry.key;
        final bandMags = entry.value;

        if (data.bands != null &&
            bandIdx < data.bands!.length &&
            data.bands![bandIdx].enabled) {
          final band = data.bands![bandIdx];
          final isBoost = band.gain >= 0;
          final bandColor =
              isBoost ? FabFilterColors.orange.withValues(alpha: 0.3) : FabFilterColors.cyan.withValues(alpha: 0.3);

          _drawResponseCurve(
            canvas,
            size,
            data.frequencies,
            bandMags,
            bandColor,
            strokeWidth: 1.0,
            fillBelow: true,
            fillColor: bandColor.withValues(alpha: 0.1),
          );
        }
      }
    }

    // Draw combined response curve
    _drawResponseCurve(
      canvas,
      size,
      data.frequencies,
      data.magnitudes,
      accentColor,
      strokeWidth: 2.5,
      glow: true,
    );
  }

  void _drawResponseCurve(
    Canvas canvas,
    Size size,
    List<double> frequencies,
    List<double> magnitudes,
    Color color, {
    double strokeWidth = 2.0,
    bool glow = false,
    bool fillBelow = false,
    Color? fillColor,
  }) {
    if (frequencies.length != magnitudes.length || frequencies.isEmpty) return;

    final path = Path();
    bool first = true;

    for (int i = 0; i < frequencies.length; i++) {
      final x = _freqToX(frequencies[i], size.width);
      final y = _dbToY(magnitudes[i], size.height);

      if (x.isNaN || y.isNaN || x.isInfinite || y.isInfinite) continue;

      if (first) {
        path.moveTo(x, y.clamp(0, size.height));
        first = false;
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    // Draw fill below curve
    if (fillBelow && fillColor != null) {
      final fillPath = Path.from(path);
      // Close the path to the zero line
      final zeroY = _dbToY(0.0, size.height);
      fillPath.lineTo(size.width, zeroY);
      fillPath.lineTo(0, zeroY);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
    }

    // Draw glow
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Draw curve
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ===========================================================================
  // DYNAMICS TRANSFER CURVE
  // ===========================================================================

  void _drawDynamicsCurve(Canvas canvas, Size size) {
    if (data.frequencies.isEmpty) return;

    final path = Path();
    bool first = true;

    for (int i = 0; i < data.frequencies.length; i++) {
      final inputDb = data.frequencies[i];
      final outputDb = data.magnitudes[i];

      final x = _inputDbToX(inputDb, size.width);
      final y = _outputDbToY(outputDb, size.height);

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw knee region fill
    if (data.kneeWidth != null && data.kneeWidth! > 0 && data.threshold != null) {
      _drawKneeRegion(canvas, size);
    }

    // Draw glow
    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Draw curve
    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawKneeRegion(Canvas canvas, Size size) {
    final threshold = data.threshold!;
    final kneeWidth = data.kneeWidth!;
    final halfKnee = kneeWidth / 2;

    final kneeStartX = _inputDbToX(threshold - halfKnee, size.width);
    final kneeEndX = _inputDbToX(threshold + halfKnee, size.width);

    final kneePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTRB(kneeStartX, 0, kneeEndX, size.height),
      kneePaint,
    );
  }

  // ===========================================================================
  // REVERB DECAY VISUALIZATION
  // ===========================================================================

  void _drawReverbDecay(Canvas canvas, Size size) {
    final decayTimes = data.decayTimes ?? data.magnitudes;
    final numBands = decayTimes.length;

    if (numBands == 0) return;

    final bandWidth = size.width / numBands;
    final maxDecay = 10.0; // Max RT60 display

    for (int i = 0; i < numBands; i++) {
      final decay = decayTimes[i].clamp(0, maxDecay);
      final barHeight = size.height * (decay / maxDecay);

      final x = i * bandWidth;
      final rect = Rect.fromLTWH(
        x + 2,
        size.height - barHeight,
        bandWidth - 4,
        barHeight,
      );

      // Bar gradient
      final gradient = ui.Gradient.linear(
        Offset(x, size.height),
        Offset(x, size.height - barHeight),
        [
          FabFilterColors.cyan.withValues(alpha: 0.8),
          FabFilterColors.blue.withValues(alpha: 0.8),
        ],
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..shader = gradient,
      );

      // Value label
      _drawLabel(
        canvas,
        '${decay.toStringAsFixed(1)}',
        Offset(x + bandWidth / 2, size.height - barHeight - 12),
        align: TextAlign.center,
        fontSize: 8,
        color: FabFilterColors.textSecondary,
      );
    }
  }

  // ===========================================================================
  // CURRENT INPUT MARKER
  // ===========================================================================

  void _drawCurrentInputMarker(Canvas canvas, Size size, double inputDb) {
    if (data.isDynamics) {
      // Find output for current input
      final outputDb = data.getMagnitudeAt(inputDb);

      final x = _inputDbToX(inputDb, size.width);
      final y = _outputDbToY(outputDb, size.height);

      // Draw crosshairs
      final linePaint = Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.5)
        ..strokeWidth = 1;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

      // Draw dot
      canvas.drawCircle(
        Offset(x, y),
        6,
        Paint()..color = FabFilterColors.yellow,
      );
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()..color = FabFilterColors.bgVoid,
      );
    }
  }

  // ===========================================================================
  // BYPASSED OVERLAY
  // ===========================================================================

  void _drawBypassedOverlay(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = FabFilterColors.bgVoid.withValues(alpha: 0.6),
    );

    _drawLabel(
      canvas,
      'BYPASSED',
      Offset(size.width / 2, size.height / 2 - 6),
      align: TextAlign.center,
      fontSize: 12,
      color: FabFilterColors.orange,
    );
  }

  // ===========================================================================
  // COORDINATE CONVERSIONS
  // ===========================================================================

  /// Convert frequency (Hz) to X coordinate (log scale)
  double _freqToX(double freq, double width) {
    if (!settings.logFrequencyScale) {
      return width * (freq - settings.minFrequency) / (settings.maxFrequency - settings.minFrequency);
    }

    final logMin = math.log(settings.minFrequency);
    final logMax = math.log(settings.maxFrequency);
    final logFreq = math.log(freq.clamp(settings.minFrequency, settings.maxFrequency));

    return width * (logFreq - logMin) / (logMax - logMin);
  }

  /// Convert dB to Y coordinate
  double _dbToY(double db, double height) {
    final normalized = (db - settings.minDb) / (settings.maxDb - settings.minDb);
    return height * (1 - normalized);
  }

  /// Convert input dB to X coordinate (for dynamics curves)
  double _inputDbToX(double db, double width) {
    const minDb = -60.0;
    const maxDb = 6.0;
    return width * (db - minDb) / (maxDb - minDb);
  }

  /// Convert output dB to Y coordinate (for dynamics curves)
  double _outputDbToY(double db, double height) {
    const minDb = -60.0;
    const maxDb = 6.0;
    return height * (1 - (db - minDb) / (maxDb - minDb));
  }

  // ===========================================================================
  // HELPER METHODS
  // ===========================================================================

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset position, {
    TextAlign align = TextAlign.left,
    Color color = FabFilterColors.textTertiary,
    double fontSize = 9,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    Offset finalPos;
    switch (align) {
      case TextAlign.center:
        finalPos = Offset(position.dx - painter.width / 2, position.dy);
        break;
      case TextAlign.right:
        finalPos = Offset(position.dx - painter.width, position.dy);
        break;
      default:
        finalPos = position;
    }

    painter.paint(canvas, finalPos);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    final unitDx = dx / length;
    final unitDy = dy / length;

    var currentLength = 0.0;
    var drawDash = true;

    while (currentLength < length) {
      final segmentLength = drawDash ? dashLength : gapLength;
      final nextLength = math.min(currentLength + segmentLength, length);

      if (drawDash) {
        canvas.drawLine(
          Offset(
            start.dx + unitDx * currentLength,
            start.dy + unitDy * currentLength,
          ),
          Offset(
            start.dx + unitDx * nextLength,
            start.dy + unitDy * nextLength,
          ),
          paint,
        );
      }

      currentLength = nextLength;
      drawDash = !drawDash;
    }
  }

  String _formatFrequency(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(freq >= 10000 ? 0 : 1)}k';
    }
    return freq.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant FrequencyGraphPainter oldDelegate) {
    return data != oldDelegate.data ||
        settings != oldDelegate.settings ||
        accentColor != oldDelegate.accentColor ||
        showBandCurves != oldDelegate.showBandCurves ||
        currentInput != oldDelegate.currentInput ||
        bypassed != oldDelegate.bypassed;
  }
}

// =============================================================================
// DYNAMICS CURVE PAINTER (SIMPLIFIED)
// =============================================================================

/// Simplified painter specifically for dynamics transfer curves
class DynamicsCurvePainter extends CustomPainter {
  final double threshold;
  final double ratio;
  final double kneeWidth;
  final double? currentInput;
  final Color curveColor;
  final bool showGrid;
  final bool bypassed;

  DynamicsCurvePainter({
    required this.threshold,
    required this.ratio,
    this.kneeWidth = 6.0,
    this.currentInput,
    this.curveColor = FabFilterColors.orange,
    this.showGrid = true,
    this.bypassed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
        ),
    );

    // Grid
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // Knee region fill
    if (kneeWidth > 0) {
      _drawKneeRegion(canvas, size);
    }

    // Transfer curve
    _drawCurve(canvas, size);

    // Current input marker
    if (currentInput != null) {
      _drawMarker(canvas, size, currentInput!);
    }

    // Bypassed overlay
    if (bypassed) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = FabFilterColors.bgVoid.withValues(alpha: 0.6),
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    // Grid every 12dB
    for (var db = -60; db <= 6; db += 12) {
      final x = _dbToX(db.toDouble(), size.width);
      final y = _dbToY(db.toDouble(), size.height);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 1:1 diagonal (dashed)
    final diagPaint = Paint()
      ..color = FabFilterColors.textMuted.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagPaint);

    // Threshold line
    final threshX = _dbToX(threshold, size.width);
    canvas.drawLine(
      Offset(threshX, 0),
      Offset(threshX, size.height),
      Paint()
        ..color = curveColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  void _drawKneeRegion(Canvas canvas, Size size) {
    final halfKnee = kneeWidth / 2;
    final x1 = _dbToX(threshold - halfKnee, size.width);
    final x2 = _dbToX(threshold + halfKnee, size.width);

    canvas.drawRect(
      Rect.fromLTRB(x1, 0, x2, size.height),
      Paint()..color = curveColor.withValues(alpha: 0.1),
    );
  }

  void _drawCurve(Canvas canvas, Size size) {
    final path = Path();
    final halfKnee = kneeWidth / 2;

    const minDb = -60.0;
    const maxDb = 6.0;
    const numPoints = 256;

    for (int i = 0; i < numPoints; i++) {
      final inputDb = minDb + (maxDb - minDb) * i / (numPoints - 1);
      double outputDb;

      if (inputDb < threshold - halfKnee) {
        outputDb = inputDb;
      } else if (inputDb > threshold + halfKnee) {
        outputDb = threshold + (inputDb - threshold) / ratio;
      } else {
        // Soft knee
        final xg = inputDb - threshold;
        final halfRatio = (1.0 / ratio - 1.0) / 2.0;
        outputDb = inputDb + halfRatio * math.pow(xg + kneeWidth / 2.0, 2) / kneeWidth;
      }

      final x = _dbToX(inputDb, size.width);
      final y = _dbToY(outputDb, size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Glow
    canvas.drawPath(
      path,
      Paint()
        ..color = curveColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Curve
    canvas.drawPath(
      path,
      Paint()
        ..color = curveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawMarker(Canvas canvas, Size size, double inputDb) {
    double outputDb;
    final halfKnee = kneeWidth / 2;

    if (inputDb < threshold - halfKnee) {
      outputDb = inputDb;
    } else if (inputDb > threshold + halfKnee) {
      outputDb = threshold + (inputDb - threshold) / ratio;
    } else {
      final xg = inputDb - threshold;
      final halfRatio = (1.0 / ratio - 1.0) / 2.0;
      outputDb = inputDb + halfRatio * math.pow(xg + kneeWidth / 2.0, 2) / kneeWidth;
    }

    final x = _dbToX(inputDb, size.width);
    final y = _dbToY(outputDb, size.height);

    // Crosshairs
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );

    // Dot
    canvas.drawCircle(Offset(x, y), 5, Paint()..color = FabFilterColors.yellow);
  }

  double _dbToX(double db, double width) {
    return width * (db + 60) / 66; // -60 to +6
  }

  double _dbToY(double db, double height) {
    return height * (1 - (db + 60) / 66);
  }

  @override
  bool shouldRepaint(covariant DynamicsCurvePainter oldDelegate) {
    return threshold != oldDelegate.threshold ||
        ratio != oldDelegate.ratio ||
        kneeWidth != oldDelegate.kneeWidth ||
        currentInput != oldDelegate.currentInput ||
        bypassed != oldDelegate.bypassed;
  }
}

// Note: DspFrequencyCalculator.reverbBandFrequencies is used for reverb grid
// Import: '../../services/dsp_frequency_calculator.dart'
