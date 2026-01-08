// Spectrum Analyzer Widget
//
// Professional real-time spectrum analyzer showing:
// - 256 bins, log-scaled 20Hz-20kHz
// - Configurable bar or filled display
// - Frequency labels
// - Peak hold with decay
// - Color gradient

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Spectrum display mode
enum SpectrumDisplayMode {
  bars,     // Discrete bars
  filled,   // Filled area
  line,     // Line graph
}

/// Spectrum analyzer configuration
class SpectrumAnalyzerConfig {
  final SpectrumDisplayMode mode;
  final Color lowColor;      // Low frequencies
  final Color midColor;      // Mid frequencies
  final Color highColor;     // High frequencies
  final Color backgroundColor;
  final Color gridColor;
  final Color peakColor;
  final bool showPeakHold;
  final bool showGrid;
  final bool showFreqLabels;
  final bool showDbLabels;
  final double peakHoldTime;    // seconds
  final double peakDecayRate;
  final double minDb;           // Floor
  final double maxDb;           // Ceiling

  const SpectrumAnalyzerConfig({
    this.mode = SpectrumDisplayMode.bars,
    this.lowColor = ReelForgeTheme.accentCyan,
    this.midColor = ReelForgeTheme.accentGreen,
    this.highColor = ReelForgeTheme.accentOrange,
    this.backgroundColor = ReelForgeTheme.bgDeepest,
    this.gridColor = ReelForgeTheme.borderSubtle,
    this.peakColor = ReelForgeTheme.textPrimary,
    this.showPeakHold = true,
    this.showGrid = true,
    this.showFreqLabels = true,
    this.showDbLabels = true,
    this.peakHoldTime = 2.0,
    this.peakDecayRate = 10.0,
    this.minDb = -80.0,
    this.maxDb = 0.0,
  });
}

/// Spectrum Analyzer Widget
class SpectrumAnalyzer extends StatefulWidget {
  /// Spectrum data (256 bins, normalized 0-1)
  final Float32List? spectrumData;

  /// Configuration
  final SpectrumAnalyzerConfig config;

  /// Width
  final double? width;

  /// Height
  final double? height;

  const SpectrumAnalyzer({
    super.key,
    this.spectrumData,
    this.config = const SpectrumAnalyzerConfig(),
    this.width,
    this.height,
  });

  @override
  State<SpectrumAnalyzer> createState() => _SpectrumAnalyzerState();
}

class _SpectrumAnalyzerState extends State<SpectrumAnalyzer> {
  Float32List _peakHold = Float32List(256);
  Float32List _peakTimers = Float32List(256);
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _peakHold = Float32List(256);
    _peakTimers = Float32List(256);
  }

  @override
  void didUpdateWidget(SpectrumAnalyzer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spectrumData != null && widget.config.showPeakHold) {
      _updatePeakHold();
    }
  }

  void _updatePeakHold() {
    final now = DateTime.now();
    final dt = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    _lastUpdate = now;

    final data = widget.spectrumData!;
    for (int i = 0; i < 256 && i < data.length; i++) {
      if (data[i] > _peakHold[i]) {
        _peakHold[i] = data[i];
        _peakTimers[i] = widget.config.peakHoldTime;
      } else if (_peakTimers[i] > 0) {
        _peakTimers[i] -= dt;
      } else {
        _peakHold[i] = math.max(0, _peakHold[i] - widget.config.peakDecayRate * dt);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.config.backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: _SpectrumPainter(
            spectrumData: widget.spectrumData ?? Float32List(256),
            peakHold: widget.config.showPeakHold ? _peakHold : null,
            config: widget.config,
          ),
          size: Size(widget.width ?? 400, widget.height ?? 150),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final Float32List spectrumData;
  final Float32List? peakHold;
  final SpectrumAnalyzerConfig config;

  _SpectrumPainter({
    required this.spectrumData,
    this.peakHold,
    required this.config,
  });

  // Frequency labels for grid
  static const List<double> _freqLabels = [
    20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000
  ];

  // Convert frequency to x position (log scale)
  double _freqToX(double freq, double width) {
    // 20Hz = 0, 20kHz = 1
    final ratio = math.log(freq / 20) / math.log(1000); // log scale 20Hz-20kHz
    return ratio.clamp(0, 1) * width;
  }

  // Get color for frequency bin
  Color _getBarColor(int bin, double value) {
    // Blend from low to high based on bin position
    final ratio = bin / 255.0;

    if (ratio < 0.33) {
      // Low frequencies (20Hz - 200Hz)
      return Color.lerp(config.lowColor, config.midColor, ratio * 3)!;
    } else if (ratio < 0.66) {
      // Mid frequencies (200Hz - 2kHz)
      return Color.lerp(config.midColor, config.highColor, (ratio - 0.33) * 3)!;
    } else {
      // High frequencies (2kHz - 20kHz)
      return config.highColor;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRect(rect, Paint()..color = config.backgroundColor);

    // Grid
    if (config.showGrid) {
      _drawGrid(canvas, size);
    }

    // Spectrum
    switch (config.mode) {
      case SpectrumDisplayMode.bars:
        _drawBars(canvas, size);
        break;
      case SpectrumDisplayMode.filled:
        _drawFilled(canvas, size);
        break;
      case SpectrumDisplayMode.line:
        _drawLine(canvas, size);
        break;
    }

    // Peak hold
    if (peakHold != null && config.showPeakHold) {
      _drawPeakHold(canvas, size);
    }

    // Labels
    if (config.showFreqLabels) {
      _drawFreqLabels(canvas, size);
    }
    if (config.showDbLabels) {
      _drawDbLabels(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = config.gridColor
      ..strokeWidth = 0.5;

    // Horizontal lines (dB)
    for (int db = -60; db <= 0; db += 12) {
      final normalized = (db - config.minDb) / (config.maxDb - config.minDb);
      final y = size.height * (1 - normalized);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines (frequency)
    for (final freq in _freqLabels) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawBars(Canvas canvas, Size size) {
    final barWidth = size.width / spectrumData.length;

    for (int i = 0; i < spectrumData.length; i++) {
      final value = spectrumData[i].clamp(0.0, 1.0);
      if (value < 0.001) continue;

      final barHeight = value * size.height;
      final x = i * barWidth;
      final y = size.height - barHeight;

      final color = _getBarColor(i, value);
      final paint = Paint()..color = color;

      canvas.drawRect(
        Rect.fromLTWH(x, y, barWidth - 1, barHeight),
        paint,
      );
    }
  }

  void _drawFilled(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, size.height);

    for (int i = 0; i < spectrumData.length; i++) {
      final value = spectrumData[i].clamp(0.0, 1.0);
      final x = i * size.width / spectrumData.length;
      final y = size.height * (1 - value);

      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.lineTo(size.width, size.height);
    path.close();

    // Gradient fill
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        config.lowColor.withValues(alpha: 0.3),
        config.midColor.withValues(alpha: 0.5),
        config.highColor.withValues(alpha: 0.7),
      ],
    );

    canvas.drawPath(
      path,
      Paint()..shader = gradient.createShader(Offset.zero & size),
    );

    // Draw outline
    _drawLine(canvas, size);
  }

  void _drawLine(Canvas canvas, Size size) {
    final path = Path();
    bool started = false;

    for (int i = 0; i < spectrumData.length; i++) {
      final value = spectrumData[i].clamp(0.0, 1.0);
      final x = i * size.width / spectrumData.length;
      final y = size.height * (1 - value);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = config.midColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawPeakHold(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = config.peakColor
      ..strokeWidth = 2;

    final barWidth = size.width / peakHold!.length;

    for (int i = 0; i < peakHold!.length; i++) {
      final value = peakHold![i].clamp(0.0, 1.0);
      if (value < 0.001) continue;

      final x = i * barWidth;
      final y = size.height * (1 - value);

      canvas.drawLine(
        Offset(x, y),
        Offset(x + barWidth - 1, y),
        paint,
      );
    }
  }

  void _drawFreqLabels(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: ReelForgeTheme.textTertiary,
      fontSize: 9,
      fontFamily: 'monospace',
    );

    for (final freq in _freqLabels) {
      final x = _freqToX(freq, size.width);
      final label = freq >= 1000 ? '${(freq / 1000).toStringAsFixed(0)}k' : '${freq.toInt()}';

      final textSpan = TextSpan(text: label, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final textX = x - textPainter.width / 2;
      if (textX > 0 && textX + textPainter.width < size.width) {
        textPainter.paint(canvas, Offset(textX, size.height - 12));
      }
    }
  }

  void _drawDbLabels(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: ReelForgeTheme.textTertiary,
      fontSize: 9,
      fontFamily: 'monospace',
    );

    for (int db = -60; db <= 0; db += 24) {
      final normalized = (db - config.minDb) / (config.maxDb - config.minDb);
      final y = size.height * (1 - normalized);

      final label = '${db}dB';
      final textSpan = TextSpan(text: label, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      textPainter.paint(canvas, Offset(2, y - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return true; // Always repaint for real-time display
  }
}
