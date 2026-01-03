/// Professional Waveform Painter
///
/// GPU-accelerated waveform rendering with:
/// - Min/Max/RMS display
/// - Smooth anti-aliasing
/// - Selection overlay
/// - Playhead cursor
/// - Grid overlay

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Waveform data point with min, max, and RMS values
class WaveformPoint {
  final double min;
  final double max;
  final double rms;

  const WaveformPoint({
    required this.min,
    required this.max,
    this.rms = 0,
  });

  factory WaveformPoint.zero() => const WaveformPoint(min: 0, max: 0, rms: 0);
}

/// Waveform display widget
class WaveformDisplay extends StatelessWidget {
  /// Waveform data points
  final List<WaveformPoint> data;

  /// Track color
  final Color color;

  /// Current playhead position (0-1)
  final double playheadPosition;

  /// Selection range (start, end) normalized 0-1
  final (double, double)? selection;

  /// Zoom level (samples per pixel)
  final double zoom;

  /// Scroll offset (normalized 0-1)
  final double scrollOffset;

  /// Show grid lines
  final bool showGrid;

  /// Show RMS as filled area
  final bool showRms;

  /// Height of the widget
  final double height;

  const WaveformDisplay({
    super.key,
    required this.data,
    this.color = const Color(0xFF4A9EFF),
    this.playheadPosition = 0,
    this.selection,
    this.zoom = 1,
    this.scrollOffset = 0,
    this.showGrid = true,
    this.showRms = true,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          painter: _WaveformPainter(
            data: data,
            color: color,
            playheadPosition: playheadPosition,
            selection: selection,
            zoom: zoom,
            scrollOffset: scrollOffset,
            showGrid: showGrid,
            showRms: showRms,
          ),
          size: Size(double.infinity, height),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<WaveformPoint> data;
  final Color color;
  final double playheadPosition;
  final (double, double)? selection;
  final double zoom;
  final double scrollOffset;
  final bool showGrid;
  final bool showRms;

  _WaveformPainter({
    required this.data,
    required this.color,
    required this.playheadPosition,
    this.selection,
    required this.zoom,
    required this.scrollOffset,
    required this.showGrid,
    required this.showRms,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final centerY = size.height / 2;
    final halfHeight = size.height / 2 - 2;

    // Background
    final bgPaint = Paint()
      ..color = ReelForgeTheme.bgDeepest
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Grid lines
    if (showGrid) {
      _drawGrid(canvas, size, centerY);
    }

    // Selection overlay
    if (selection != null) {
      _drawSelection(canvas, size);
    }

    // Calculate visible range
    final visibleStart = (scrollOffset * data.length).round();
    final visibleSamples = (data.length / zoom).round();
    final visibleEnd = math.min(visibleStart + visibleSamples, data.length);
    final samplesPerPixel = visibleSamples / size.width;

    // Draw waveform
    if (samplesPerPixel <= 1) {
      // High zoom: draw individual samples as lines
      _drawSampleLines(canvas, size, centerY, halfHeight, visibleStart, visibleEnd);
    } else {
      // Low zoom: draw min/max envelope
      _drawEnvelope(canvas, size, centerY, halfHeight, visibleStart, visibleEnd, samplesPerPixel);
    }

    // Playhead
    _drawPlayhead(canvas, size);

    // Border
    final borderPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, borderPaint);
  }

  void _drawGrid(Canvas canvas, Size size, double centerY) {
    final gridPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Center line (0dB)
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      gridPaint,
    );

    // -6dB lines
    final db6 = size.height * 0.25;
    canvas.drawLine(
      Offset(0, centerY - db6),
      Offset(size.width, centerY - db6),
      gridPaint..color = gridPaint.color.withValues(alpha: 0.2),
    );
    canvas.drawLine(
      Offset(0, centerY + db6),
      Offset(size.width, centerY + db6),
      gridPaint,
    );
  }

  void _drawSelection(Canvas canvas, Size size) {
    final (start, end) = selection!;
    final startX = start * size.width;
    final endX = end * size.width;

    final selectionPaint = Paint()
      ..color = ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX, size.height),
      selectionPaint,
    );

    // Selection edges
    final edgePaint = Paint()
      ..color = ReelForgeTheme.accentBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), edgePaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), edgePaint);
  }

  void _drawSampleLines(
    Canvas canvas,
    Size size,
    double centerY,
    double halfHeight,
    int visibleStart,
    int visibleEnd,
  ) {
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final pixelsPerSample = size.width / (visibleEnd - visibleStart);

    for (int i = visibleStart; i < visibleEnd; i++) {
      final x = (i - visibleStart) * pixelsPerSample;
      final point = data[i];

      final minY = centerY - point.min * halfHeight;
      final maxY = centerY - point.max * halfHeight;

      if (i == visibleStart) {
        path.moveTo(x, maxY);
      } else {
        path.lineTo(x, maxY);
      }
    }

    // Draw return path for min values
    for (int i = visibleEnd - 1; i >= visibleStart; i--) {
      final x = (i - visibleStart) * pixelsPerSample;
      final point = data[i];
      final minY = centerY - point.min * halfHeight;
      path.lineTo(x, minY);
    }

    path.close();

    // Fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Stroke
    canvas.drawPath(path, linePaint);
  }

  void _drawEnvelope(
    Canvas canvas,
    Size size,
    double centerY,
    double halfHeight,
    int visibleStart,
    int visibleEnd,
    double samplesPerPixel,
  ) {
    // Waveform paths
    final peakPath = Path();
    final rmsPath = Path();

    bool firstPoint = true;
    List<double> rmsTopPoints = [];
    List<double> rmsBottomPoints = [];

    for (double x = 0; x < size.width; x++) {
      final sampleIndex = visibleStart + (x * samplesPerPixel).round();
      if (sampleIndex >= data.length) break;

      // Get min/max for this pixel column
      final endIndex = math.min(sampleIndex + samplesPerPixel.ceil(), data.length);
      double minVal = 1;
      double maxVal = -1;
      double rmsSum = 0;
      int count = 0;

      for (int i = sampleIndex; i < endIndex; i++) {
        final point = data[i];
        minVal = math.min(minVal, point.min);
        maxVal = math.max(maxVal, point.max);
        rmsSum += point.rms * point.rms;
        count++;
      }

      final rmsVal = count > 0 ? math.sqrt(rmsSum / count) : 0;

      final maxY = centerY - maxVal * halfHeight;
      final minY = centerY - minVal * halfHeight;
      final rmsTopY = centerY - rmsVal * halfHeight;
      final rmsBottomY = centerY + rmsVal * halfHeight;

      if (firstPoint) {
        peakPath.moveTo(x, maxY);
        firstPoint = false;
      } else {
        peakPath.lineTo(x, maxY);
      }

      rmsTopPoints.add(rmsTopY);
      rmsBottomPoints.add(rmsBottomY);
    }

    // Complete peak path with bottom
    for (double x = size.width - 1; x >= 0; x--) {
      final sampleIndex = visibleStart + (x * samplesPerPixel).round();
      if (sampleIndex >= data.length) continue;

      final endIndex = math.min(sampleIndex + samplesPerPixel.ceil(), data.length);
      double minVal = 1;

      for (int i = sampleIndex; i < endIndex; i++) {
        minVal = math.min(minVal, data[i].min);
      }

      final minY = centerY - minVal * halfHeight;
      peakPath.lineTo(x, minY);
    }
    peakPath.close();

    // Draw peak fill
    final peakFillPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawPath(peakPath, peakFillPaint);

    // Draw RMS fill if enabled
    if (showRms && rmsTopPoints.isNotEmpty) {
      rmsPath.moveTo(0, rmsTopPoints.first);
      for (int i = 1; i < rmsTopPoints.length; i++) {
        rmsPath.lineTo(i.toDouble(), rmsTopPoints[i]);
      }
      for (int i = rmsBottomPoints.length - 1; i >= 0; i--) {
        rmsPath.lineTo(i.toDouble(), rmsBottomPoints[i]);
      }
      rmsPath.close();

      final rmsFillPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawPath(rmsPath, rmsFillPaint);
    }

    // Draw peak outline
    final peakStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(peakPath, peakStrokePaint);
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final x = playheadPosition * size.width;

    // Glow
    final glowPaint = Paint()
      ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);

    // Line
    final linePaint = Paint()
      ..color = ReelForgeTheme.textPrimary
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Triangle head
    final headPaint = Paint()
      ..color = ReelForgeTheme.textPrimary
      ..style = PaintingStyle.fill;
    final headPath = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 6)
      ..close();
    canvas.drawPath(headPath, headPaint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      data != oldDelegate.data ||
      color != oldDelegate.color ||
      playheadPosition != oldDelegate.playheadPosition ||
      selection != oldDelegate.selection ||
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset;
}
