/// Processor Frequency Graph Widget (P10.1.6)
///
/// FF-Q style frequency response visualization for all DSP processors:
/// - EQ curves with multiple filter types (bell, shelf, cut, notch)
/// - Compressor transfer curve and knee display
/// - Limiter ceiling and gain reduction
/// - Gate threshold visualization
/// - Reverb decay/frequency response
///
/// Features:
/// - Frequency response curve (20Hz - 20kHz logarithmic scale)
/// - dB scale (-24 to +24 dB, configurable)
/// - Real-time update when parameters change
/// - Grid lines (major: 100Hz, 1kHz, 10kHz; minor: 50Hz, 500Hz, 5kHz)
/// - CustomPainter for smooth 60fps rendering
/// - Glow effects and gradient fills

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../fabfilter/fabfilter_theme.dart';
import '../../providers/dsp_chain_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Processor graph display mode
enum ProcessorGraphMode {
  frequencyResponse, // EQ, filter curves
  transferCurve, // Compressor, limiter, gate
  decayResponse, // Reverb decay over frequency
  combined, // Overlay multiple curves
}

/// Filter shape for EQ visualization
enum FilterShape {
  bell,
  lowShelf,
  highShelf,
  lowCut,
  highCut,
  notch,
  bandPass,
  tiltShelf,
  allPass,
}

/// Single EQ band for visualization
class GraphEqBand {
  final double frequency;
  final double gain; // dB
  final double q;
  final FilterShape shape;
  final bool enabled;
  final Color? color;

  const GraphEqBand({
    required this.frequency,
    this.gain = 0.0,
    this.q = 1.0,
    this.shape = FilterShape.bell,
    this.enabled = true,
    this.color,
  });

  GraphEqBand copyWith({
    double? frequency,
    double? gain,
    double? q,
    FilterShape? shape,
    bool? enabled,
    Color? color,
  }) {
    return GraphEqBand(
      frequency: frequency ?? this.frequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      shape: shape ?? this.shape,
      enabled: enabled ?? this.enabled,
      color: color ?? this.color,
    );
  }
}

/// Dynamics processor settings for transfer curve
class GraphDynamicsSettings {
  final double threshold; // dB
  final double ratio; // :1 (e.g., 4.0 for 4:1)
  final double knee; // dB
  final double range; // dB (for gate/expander)
  final double ceiling; // dB (for limiter)
  final bool upward; // Upward compression

  const GraphDynamicsSettings({
    this.threshold = -20.0,
    this.ratio = 4.0,
    this.knee = 6.0,
    this.range = -80.0,
    this.ceiling = -0.3,
    this.upward = false,
  });
}

/// Reverb settings for decay visualization
class GraphReverbSettings {
  final double decayTime; // seconds
  final double preDelay; // ms
  final double highDamping; // Hz
  final double lowDamping; // Hz
  final double density;
  final double diffusion;

  const GraphReverbSettings({
    this.decayTime = 2.0,
    this.preDelay = 20.0,
    this.highDamping = 8000.0,
    this.lowDamping = 200.0,
    this.density = 0.7,
    this.diffusion = 0.8,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// FF-Q style processor frequency graph
class ProcessorGraphWidget extends StatelessWidget {
  /// Display mode
  final ProcessorGraphMode mode;

  /// Processor type for styling
  final DspNodeType? processorType;

  /// EQ bands (for frequency response mode)
  final List<GraphEqBand> eqBands;

  /// Dynamics settings (for transfer curve mode)
  final GraphDynamicsSettings? dynamicsSettings;

  /// Reverb settings (for decay response mode)
  final GraphReverbSettings? reverbSettings;

  /// Show grid lines
  final bool showGrid;

  /// Show frequency labels
  final bool showLabels;

  /// Show filled area under curve
  final bool showFill;

  /// Show glow effect on curve
  final bool showGlow;

  /// dB range (min, max)
  final double minDb;
  final double maxDb;

  /// Frequency range
  final double minFreq;
  final double maxFreq;

  /// Curve color (defaults based on processor type)
  final Color? curveColor;

  /// Selected band index for highlighting
  final int? selectedBandIndex;

  /// Callback when band is tapped
  final void Function(int index)? onBandTap;

  /// Callback when empty area is tapped (create new band)
  final void Function(double frequency, double gain)? onEmptyTap;

  const ProcessorGraphWidget({
    super.key,
    this.mode = ProcessorGraphMode.frequencyResponse,
    this.processorType,
    this.eqBands = const [],
    this.dynamicsSettings,
    this.reverbSettings,
    this.showGrid = true,
    this.showLabels = true,
    this.showFill = true,
    this.showGlow = true,
    this.minDb = -24.0,
    this.maxDb = 24.0,
    this.minFreq = 20.0,
    this.maxFreq = 20000.0,
    this.curveColor,
    this.selectedBandIndex,
    this.onBandTap,
    this.onEmptyTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) => _handleTap(details, constraints.biggest),
          child: CustomPaint(
            painter: _ProcessorGraphPainter(
              mode: mode,
              processorType: processorType,
              eqBands: eqBands,
              dynamicsSettings: dynamicsSettings,
              reverbSettings: reverbSettings,
              showGrid: showGrid,
              showLabels: showLabels,
              showFill: showFill,
              showGlow: showGlow,
              minDb: minDb,
              maxDb: maxDb,
              minFreq: minFreq,
              maxFreq: maxFreq,
              curveColor: curveColor,
              selectedBandIndex: selectedBandIndex,
            ),
            size: constraints.biggest,
          ),
        );
      },
    );
  }

  void _handleTap(TapDownDetails details, Size size) {
    if (mode != ProcessorGraphMode.frequencyResponse) return;

    final position = details.localPosition;

    // Check if clicking on a band marker
    for (int i = 0; i < eqBands.length; i++) {
      final band = eqBands[i];
      if (!band.enabled) continue;

      final x = _freqToX(band.frequency, size.width);
      final y = _dbToY(band.gain, size.height);

      if ((Offset(x, y) - position).distance < 15) {
        onBandTap?.call(i);
        return;
      }
    }

    // Click on empty area
    final freq = _xToFreq(position.dx, size.width);
    final gain = _yToDb(position.dy, size.height);
    onEmptyTap?.call(freq, gain);
  }

  double _freqToX(double freq, double width) {
    final logMin = math.log(minFreq) / math.ln10;
    final logMax = math.log(maxFreq) / math.ln10;
    final logFreq = math.log(freq.clamp(minFreq, maxFreq)) / math.ln10;
    return ((logFreq - logMin) / (logMax - logMin)) * width;
  }

  double _xToFreq(double x, double width) {
    final logMin = math.log(minFreq) / math.ln10;
    final logMax = math.log(maxFreq) / math.ln10;
    return math.pow(10, logMin + (x / width) * (logMax - logMin)).toDouble();
  }

  double _dbToY(double db, double height) {
    final normalized = (db - minDb) / (maxDb - minDb);
    return height - (normalized * height);
  }

  double _yToDb(double y, double height) {
    final normalized = 1.0 - (y / height);
    return minDb + normalized * (maxDb - minDb);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _ProcessorGraphPainter extends CustomPainter {
  final ProcessorGraphMode mode;
  final DspNodeType? processorType;
  final List<GraphEqBand> eqBands;
  final GraphDynamicsSettings? dynamicsSettings;
  final GraphReverbSettings? reverbSettings;
  final bool showGrid;
  final bool showLabels;
  final bool showFill;
  final bool showGlow;
  final double minDb;
  final double maxDb;
  final double minFreq;
  final double maxFreq;
  final Color? curveColor;
  final int? selectedBandIndex;

  _ProcessorGraphPainter({
    required this.mode,
    this.processorType,
    required this.eqBands,
    this.dynamicsSettings,
    this.reverbSettings,
    required this.showGrid,
    required this.showLabels,
    required this.showFill,
    required this.showGlow,
    required this.minDb,
    required this.maxDb,
    required this.minFreq,
    required this.maxFreq,
    this.curveColor,
    this.selectedBandIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    _drawBackground(canvas, size);

    // Grid
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // Draw based on mode
    switch (mode) {
      case ProcessorGraphMode.frequencyResponse:
        _drawFrequencyResponse(canvas, size);
        _drawBandMarkers(canvas, size);
        break;
      case ProcessorGraphMode.transferCurve:
        _drawTransferCurve(canvas, size);
        break;
      case ProcessorGraphMode.decayResponse:
        _drawDecayResponse(canvas, size);
        break;
      case ProcessorGraphMode.combined:
        _drawFrequencyResponse(canvas, size);
        _drawBandMarkers(canvas, size);
        break;
    }

    // Labels
    if (showLabels) {
      _drawLabels(canvas, size);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = FabFilterColors.bgVoid,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final majorGridPaint = Paint()
      ..color = FabFilterColors.borderMedium
      ..strokeWidth = 1.0;

    final minorGridPaint = Paint()
      ..color = FabFilterColors.borderSubtle
      ..strokeWidth = 0.5;

    // Major frequency lines (100Hz, 1kHz, 10kHz)
    final majorFreqs = [100.0, 1000.0, 10000.0];
    for (final freq in majorFreqs) {
      if (freq < minFreq || freq > maxFreq) continue;
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorGridPaint);
    }

    // Minor frequency lines (50Hz, 500Hz, 5kHz)
    final minorFreqs = [50.0, 200.0, 500.0, 2000.0, 5000.0, 20000.0];
    for (final freq in minorFreqs) {
      if (freq < minFreq || freq > maxFreq) continue;
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorGridPaint);
    }

    // Center line (0 dB)
    final centerY = _dbToY(0, size.height);
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      majorGridPaint..color = FabFilterColors.borderMedium.withValues(alpha: 0.8),
    );

    // dB grid lines
    final dbStep = (maxDb - minDb) / 4;
    for (double db = minDb; db <= maxDb; db += dbStep) {
      if (db == 0) continue; // Already drawn
      final y = _dbToY(db, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorGridPaint);
    }
  }

  void _drawLabels(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: FabFilterColors.textTertiary,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    // Frequency labels
    final freqLabels = {
      100.0: '100',
      1000.0: '1k',
      10000.0: '10k',
    };

    for (final entry in freqLabels.entries) {
      if (entry.key < minFreq || entry.key > maxFreq) continue;
      final x = _freqToX(entry.key, size.width);
      final textPainter = TextPainter(
        text: TextSpan(text: entry.value, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - textPainter.height - 2),
      );
    }

    // dB labels
    final dbLabels = [minDb, 0.0, maxDb];
    for (final db in dbLabels) {
      final y = _dbToY(db, size.height);
      final label = db == 0 ? '0' : (db > 0 ? '+${db.toInt()}' : '${db.toInt()}');
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, y - textPainter.height / 2));
    }
  }

  void _drawFrequencyResponse(Canvas canvas, Size size) {
    if (eqBands.isEmpty) {
      // Draw flat line at 0 dB
      final y = _dbToY(0, size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = _getDefaultCurveColor().withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
      return;
    }

    // Calculate combined response
    final path = Path();
    final numPoints = size.width.toInt();
    final centerY = _dbToY(0, size.height);

    for (int i = 0; i <= numPoints; i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);
      double totalDb = 0;

      for (final band in eqBands) {
        if (!band.enabled) continue;
        totalDb += _calculateBandResponse(freq, band);
      }

      final y = _dbToY(totalDb.clamp(minDb - 6, maxDb + 6), size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Fill under curve
    if (showFill) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, centerY)
        ..lineTo(0, centerY)
        ..close();

      final gradient = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          FabFilterColors.orange.withValues(alpha: 0.15),
          FabFilterColors.cyan.withValues(alpha: 0.15),
        ],
        [0.0, 1.0],
      );

      canvas.drawPath(fillPath, Paint()..shader = gradient);
    }

    // Glow effect
    if (showGlow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _getDefaultCurveColor().withValues(alpha: 0.4)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Main curve
    canvas.drawPath(
      path,
      Paint()
        ..color = _getDefaultCurveColor()
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawBandMarkers(Canvas canvas, Size size) {
    for (int i = 0; i < eqBands.length; i++) {
      final band = eqBands[i];
      if (!band.enabled) continue;

      final x = _freqToX(band.frequency, size.width);
      final y = _dbToY(band.gain, size.height);
      final color = band.color ?? _getShapeColor(band.shape);
      final isSelected = i == selectedBandIndex;
      final radius = isSelected ? 10.0 : 7.0;

      // Glow for selected
      if (isSelected) {
        canvas.drawCircle(
          Offset(x, y.clamp(radius, size.height - radius)),
          radius + 5,
          Paint()..color = color.withValues(alpha: 0.3),
        );
      }

      // Band marker
      canvas.drawCircle(
        Offset(x, y.clamp(radius, size.height - radius)),
        radius,
        Paint()..color = color,
      );

      // Selection ring
      if (isSelected) {
        canvas.drawCircle(
          Offset(x, y.clamp(radius, size.height - radius)),
          radius + 3,
          Paint()
            ..color = FabFilterColors.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  void _drawTransferCurve(Canvas canvas, Size size) {
    final settings = dynamicsSettings ?? const GraphDynamicsSettings();
    final color = curveColor ?? _getDefaultCurveColor();

    // Draw 1:1 reference line
    final refPaint = Paint()
      ..color = FabFilterColors.borderMedium
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      refPaint,
    );

    // Draw threshold line
    final thresholdNorm = (settings.threshold - minDb) / (maxDb - minDb);
    final thresholdX = thresholdNorm * size.width;
    final thresholdY = size.height - (thresholdNorm * size.height);

    canvas.drawLine(
      Offset(thresholdX, 0),
      Offset(thresholdX, size.height),
      Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.5)
        ..strokeWidth = 1.0,
    );

    // Draw transfer curve
    final path = Path();
    final numPoints = size.width.toInt();

    for (int i = 0; i <= numPoints; i++) {
      final inputNorm = i / size.width;
      final inputDb = minDb + inputNorm * (maxDb - minDb);
      final outputDb = _calculateCompressorOutput(inputDb, settings);
      final outputNorm = (outputDb - minDb) / (maxDb - minDb);

      final x = i.toDouble();
      final y = size.height - (outputNorm * size.height);

      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    // Glow
    if (showGlow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Main curve
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Knee indicator (if soft knee)
    if (settings.knee > 0) {
      final kneeStartDb = settings.threshold - settings.knee / 2;
      final kneeEndDb = settings.threshold + settings.knee / 2;
      final kneeStartNorm = (kneeStartDb - minDb) / (maxDb - minDb);
      final kneeEndNorm = (kneeEndDb - minDb) / (maxDb - minDb);

      final kneeRect = Rect.fromLTRB(
        kneeStartNorm * size.width,
        0,
        kneeEndNorm * size.width,
        size.height,
      );

      canvas.drawRect(
        kneeRect,
        Paint()..color = FabFilterColors.orange.withValues(alpha: 0.1),
      );
    }
  }

  void _drawDecayResponse(Canvas canvas, Size size) {
    final settings = reverbSettings ?? const GraphReverbSettings();
    final color = curveColor ?? FabFilterColors.purple;

    // Draw decay curve across frequency
    final path = Path();
    final numPoints = size.width.toInt();

    for (int i = 0; i <= numPoints; i++) {
      final freq = _xToFreq(i.toDouble(), size.width);

      // Calculate decay at this frequency
      double decay = settings.decayTime;

      // High frequency damping
      if (freq > settings.highDamping) {
        final damping = (freq - settings.highDamping) / settings.highDamping;
        decay *= math.max(0.1, 1.0 - damping * 0.8);
      }

      // Low frequency damping
      if (freq < settings.lowDamping) {
        final damping = (settings.lowDamping - freq) / settings.lowDamping;
        decay *= math.max(0.2, 1.0 - damping * 0.5);
      }

      // Normalize decay to dB range (0 dB = full decay, negative = shorter)
      final decayDb = (decay / settings.decayTime - 1.0) * 12.0;
      final y = _dbToY(decayDb, size.height);

      if (i == 0) {
        path.moveTo(i.toDouble(), y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    // Fill
    if (showFill) {
      final centerY = _dbToY(0, size.height);
      final fillPath = Path.from(path)
        ..lineTo(size.width, centerY)
        ..lineTo(0, centerY)
        ..close();

      canvas.drawPath(
        fillPath,
        Paint()..color = color.withValues(alpha: 0.1),
      );
    }

    // Glow
    if (showGlow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Main curve
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );
  }

  double _calculateBandResponse(double freq, GraphEqBand band) {
    final ratio = freq / band.frequency;
    final logRatio = math.log(ratio) / math.ln2;

    switch (band.shape) {
      case FilterShape.bell:
        return band.gain * math.exp(-math.pow(logRatio * band.q, 2));

      case FilterShape.lowShelf:
        return band.gain * (1 - 1 / (1 + math.exp(-logRatio * 4)));

      case FilterShape.highShelf:
        return band.gain * (1 / (1 + math.exp(-logRatio * 4)));

      case FilterShape.lowCut:
        if (ratio < 1) {
          final slope = band.q.clamp(0.5, 4.0) * 6; // 6-24 dB/oct
          return -slope * (1 - ratio);
        }
        return 0;

      case FilterShape.highCut:
        if (ratio > 1) {
          final slope = band.q.clamp(0.5, 4.0) * 6;
          return -slope * (ratio - 1);
        }
        return 0;

      case FilterShape.notch:
        return -math.min(30.0, 30 * math.exp(-math.pow(logRatio * band.q * 2, 2)));

      case FilterShape.bandPass:
        return math.exp(-math.pow(logRatio * band.q, 2)) * 12 - 6;

      case FilterShape.tiltShelf:
        return band.gain * logRatio.clamp(-2.0, 2.0) / 2;

      case FilterShape.allPass:
        return 0; // Allpass has flat magnitude response
    }
  }

  double _calculateCompressorOutput(double inputDb, GraphDynamicsSettings settings) {
    if (inputDb < settings.threshold - settings.knee / 2) {
      // Below knee: 1:1
      return inputDb;
    } else if (inputDb > settings.threshold + settings.knee / 2) {
      // Above knee: apply ratio
      final excess = inputDb - settings.threshold;
      return settings.threshold + excess / settings.ratio;
    } else {
      // In knee: smooth transition
      final kneeStart = settings.threshold - settings.knee / 2;
      final kneePos = (inputDb - kneeStart) / settings.knee;
      final curvedRatio = 1.0 + (settings.ratio - 1.0) * kneePos * kneePos;
      final excess = inputDb - settings.threshold;
      return settings.threshold + excess / curvedRatio;
    }
  }

  double _freqToX(double freq, double width) {
    final logMin = math.log(minFreq) / math.ln10;
    final logMax = math.log(maxFreq) / math.ln10;
    final logFreq = math.log(freq.clamp(minFreq, maxFreq)) / math.ln10;
    return ((logFreq - logMin) / (logMax - logMin)) * width;
  }

  double _xToFreq(double x, double width) {
    final logMin = math.log(minFreq) / math.ln10;
    final logMax = math.log(maxFreq) / math.ln10;
    return math.pow(10, logMin + (x / width) * (logMax - logMin)).toDouble();
  }

  double _dbToY(double db, double height) {
    final normalized = (db - minDb) / (maxDb - minDb);
    return height - (normalized * height);
  }

  Color _getDefaultCurveColor() {
    return curveColor ??
        switch (processorType) {
          DspNodeType.eq => FabFilterColors.blue,
          DspNodeType.compressor => FabFilterColors.orange,
          DspNodeType.limiter => FabFilterColors.red,
          DspNodeType.gate => FabFilterColors.green,
          DspNodeType.expander => FabFilterColors.yellow,
          DspNodeType.reverb => FabFilterColors.purple,
          DspNodeType.delay => FabFilterColors.cyan,
          DspNodeType.saturation => FabFilterColors.orange,
          DspNodeType.deEsser => FabFilterColors.pink,
          _ => FabFilterColors.blue,
        };
  }

  Color _getShapeColor(FilterShape shape) {
    return switch (shape) {
      FilterShape.bell => FabFilterColors.blue,
      FilterShape.lowShelf => FabFilterColors.orange,
      FilterShape.highShelf => FabFilterColors.yellow,
      FilterShape.lowCut => FabFilterColors.red,
      FilterShape.highCut => FabFilterColors.red,
      FilterShape.notch => FabFilterColors.pink,
      FilterShape.bandPass => FabFilterColors.green,
      FilterShape.tiltShelf => FabFilterColors.cyan,
      FilterShape.allPass => FabFilterColors.textTertiary,
    };
  }

  @override
  bool shouldRepaint(covariant _ProcessorGraphPainter oldDelegate) {
    return mode != oldDelegate.mode ||
        processorType != oldDelegate.processorType ||
        eqBands != oldDelegate.eqBands ||
        dynamicsSettings != oldDelegate.dynamicsSettings ||
        reverbSettings != oldDelegate.reverbSettings ||
        showGrid != oldDelegate.showGrid ||
        showLabels != oldDelegate.showLabels ||
        showFill != oldDelegate.showFill ||
        showGlow != oldDelegate.showGlow ||
        minDb != oldDelegate.minDb ||
        maxDb != oldDelegate.maxDb ||
        curveColor != oldDelegate.curveColor ||
        selectedBandIndex != oldDelegate.selectedBandIndex;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT VARIANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact frequency response widget for channel strips
class CompactProcessorGraph extends StatelessWidget {
  final List<GraphEqBand> eqBands;
  final DspNodeType? processorType;
  final double width;
  final double height;

  const CompactProcessorGraph({
    super.key,
    this.eqBands = const [],
    this.processorType,
    this.width = 120,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ProcessorGraphWidget(
          mode: ProcessorGraphMode.frequencyResponse,
          processorType: processorType,
          eqBands: eqBands,
          showGrid: false,
          showLabels: false,
          showFill: true,
          showGlow: false,
        ),
      ),
    );
  }
}

/// Compact dynamics transfer curve for channel strips
class CompactTransferCurve extends StatelessWidget {
  final GraphDynamicsSettings settings;
  final DspNodeType processorType;
  final double width;
  final double height;

  const CompactTransferCurve({
    super.key,
    required this.settings,
    this.processorType = DspNodeType.compressor,
    this.width = 80,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ProcessorGraphWidget(
          mode: ProcessorGraphMode.transferCurve,
          processorType: processorType,
          dynamicsSettings: settings,
          showGrid: false,
          showLabels: false,
          showFill: false,
          showGlow: true,
          minDb: -60,
          maxDb: 0,
        ),
      ),
    );
  }
}

/// Full-size processor graph panel with controls
class ProcessorGraphPanel extends StatefulWidget {
  final DspNodeType processorType;
  final List<GraphEqBand> eqBands;
  final GraphDynamicsSettings? dynamicsSettings;
  final GraphReverbSettings? reverbSettings;
  final void Function(int index)? onBandSelected;
  final void Function(double freq, double gain)? onBandCreated;

  const ProcessorGraphPanel({
    super.key,
    required this.processorType,
    this.eqBands = const [],
    this.dynamicsSettings,
    this.reverbSettings,
    this.onBandSelected,
    this.onBandCreated,
  });

  @override
  State<ProcessorGraphPanel> createState() => _ProcessorGraphPanelState();
}

class _ProcessorGraphPanelState extends State<ProcessorGraphPanel> {
  bool _showGrid = true;
  bool _showFill = true;
  int? _selectedIndex;

  ProcessorGraphMode get _mode {
    switch (widget.processorType) {
      case DspNodeType.eq:
        return ProcessorGraphMode.frequencyResponse;
      case DspNodeType.compressor:
      case DspNodeType.limiter:
      case DspNodeType.gate:
      case DspNodeType.expander:
        return ProcessorGraphMode.transferCurve;
      case DspNodeType.reverb:
        return ProcessorGraphMode.decayResponse;
      default:
        return ProcessorGraphMode.frequencyResponse;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FabFilterColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getProcessorIcon(),
                  size: 16,
                  color: _getProcessorColor(),
                ),
                const SizedBox(width: 8),
                Text(
                  _getTitle(),
                  style: FabFilterText.sectionHeader.copyWith(
                    color: _getProcessorColor(),
                  ),
                ),
                const Spacer(),
                // Options
                _buildOption('Grid', _showGrid, (v) => setState(() => _showGrid = v)),
                const SizedBox(width: 12),
                _buildOption('Fill', _showFill, (v) => setState(() => _showFill = v)),
              ],
            ),
          ),

          // Graph
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ProcessorGraphWidget(
                mode: _mode,
                processorType: widget.processorType,
                eqBands: widget.eqBands,
                dynamicsSettings: widget.dynamicsSettings,
                reverbSettings: widget.reverbSettings,
                showGrid: _showGrid,
                showLabels: true,
                showFill: _showFill,
                showGlow: true,
                selectedBandIndex: _selectedIndex,
                onBandTap: (index) {
                  setState(() => _selectedIndex = index);
                  widget.onBandSelected?.call(index);
                },
                onEmptyTap: widget.onBandCreated,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: FabFilterText.paramLabel),
      ],
    );
  }

  IconData _getProcessorIcon() {
    return switch (widget.processorType) {
      DspNodeType.eq => Icons.equalizer,
      DspNodeType.compressor => Icons.compress,
      DspNodeType.limiter => Icons.vertical_align_top,
      DspNodeType.gate => Icons.security,
      DspNodeType.expander => Icons.expand,
      DspNodeType.reverb => Icons.waves,
      DspNodeType.delay => Icons.timer,
      DspNodeType.saturation => Icons.whatshot,
      DspNodeType.deEsser => Icons.speaker_notes_off,
      DspNodeType.pultec => Icons.tune,
      DspNodeType.api550 => Icons.graphic_eq,
      DspNodeType.neve1073 => Icons.surround_sound,
      DspNodeType.multibandSaturation => Icons.whatshot,
    };
  }

  Color _getProcessorColor() {
    return switch (widget.processorType) {
      DspNodeType.eq => FabFilterColors.blue,
      DspNodeType.compressor => FabFilterColors.orange,
      DspNodeType.limiter => FabFilterColors.red,
      DspNodeType.gate => FabFilterColors.green,
      DspNodeType.expander => FabFilterColors.yellow,
      DspNodeType.reverb => FabFilterColors.purple,
      DspNodeType.delay => FabFilterColors.cyan,
      DspNodeType.saturation => FabFilterColors.orange,
      DspNodeType.deEsser => FabFilterColors.pink,
      DspNodeType.pultec => const Color(0xFFD4A574),
      DspNodeType.api550 => FabFilterColors.blue,
      DspNodeType.neve1073 => const Color(0xFF8B4513),
      DspNodeType.multibandSaturation => FabFilterColors.orange,
    };
  }

  String _getTitle() {
    return switch (_mode) {
      ProcessorGraphMode.frequencyResponse => 'FREQUENCY RESPONSE',
      ProcessorGraphMode.transferCurve => 'TRANSFER CURVE',
      ProcessorGraphMode.decayResponse => 'DECAY RESPONSE',
      ProcessorGraphMode.combined => 'COMBINED RESPONSE',
    };
  }
}
