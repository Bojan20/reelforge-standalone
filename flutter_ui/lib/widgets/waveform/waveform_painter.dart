/// Professional Waveform Painter
///
/// GPU-accelerated waveform rendering with:
/// - Min/Max/RMS display
/// - Stereo L/R split view (Cubase/Logic style)
/// - Smooth anti-aliased bezier curves
/// - Selection overlay
/// - Playhead cursor
/// - Grid overlay
/// - Gradient fills for professional look
///
/// Display modes:
/// - Mono: Single centered waveform
/// - Stereo: L channel top, R channel bottom
/// - Stereo Overlapped: L/R overlaid with different colors

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

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

/// Stereo waveform data containing L/R channels
class StereoWaveformData {
  final List<WaveformPoint> left;
  final List<WaveformPoint> right;

  const StereoWaveformData({
    required this.left,
    required this.right,
  });

  bool get isEmpty => left.isEmpty && right.isEmpty;
  int get length => math.max(left.length, right.length);

  /// Create from mono data (duplicates to both channels)
  factory StereoWaveformData.fromMono(List<WaveformPoint> mono) {
    return StereoWaveformData(left: mono, right: mono);
  }

  /// Create from interleaved stereo samples
  factory StereoWaveformData.fromInterleaved(List<WaveformPoint> interleaved) {
    final left = <WaveformPoint>[];
    final right = <WaveformPoint>[];

    for (int i = 0; i < interleaved.length; i += 2) {
      left.add(interleaved[i]);
      if (i + 1 < interleaved.length) {
        right.add(interleaved[i + 1]);
      }
    }

    return StereoWaveformData(left: left, right: right);
  }
}

/// Display mode for stereo waveforms
enum WaveformDisplayMode {
  /// Single centered waveform (mono or summed stereo)
  mono,
  /// L channel on top, R channel on bottom (Cubase style)
  stereoSplit,
  /// L/R overlapped with different colors (Logic style)
  stereoOverlapped,
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
      ..color = FluxForgeTheme.bgDeepest
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
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawRect(Offset.zero & size, borderPaint);
  }

  void _drawGrid(Canvas canvas, Size size, double centerY) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

    // Center line (0dB)
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      gridPaint,
    );

    // -6dB lines
    final db6 = size.height * 0.25;
    gridPaint.color = gridPaint.color.withValues(alpha: 0.2);
    canvas.drawLine(
      Offset(0, centerY - db6),
      Offset(size.width, centerY - db6),
      gridPaint,
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
      ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX, size.height),
      selectionPaint,
    );

    // Selection edges
    final edgePaint = Paint()
      ..color = FluxForgeTheme.accentBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
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
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path();
    final pixelsPerSample = size.width / (visibleEnd - visibleStart);

    for (int i = visibleStart; i < visibleEnd; i++) {
      final x = (i - visibleStart) * pixelsPerSample;
      final point = data[i];
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
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
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
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
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
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(rmsPath, rmsFillPaint);
    }

    // Draw peak outline
    final peakStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawPath(peakPath, peakStrokePaint);
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final x = playheadPosition * size.width;

    // Glow
    final glowPaint = Paint()
      ..color = FluxForgeTheme.textPrimary.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..isAntiAlias = true;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);

    // Line
    final linePaint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Triangle head
    final headPaint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
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

// ═══════════════════════════════════════════════════════════════════════════
// STEREO WAVEFORM DISPLAY - Professional L/R Split View
// ═══════════════════════════════════════════════════════════════════════════

/// Professional stereo waveform display widget
///
/// Supports multiple display modes:
/// - Split: L channel on top, R channel on bottom (Cubase style)
/// - Overlapped: L/R overlaid with different colors (Logic style)
/// - Mono: Summed to single waveform
class StereoWaveformDisplay extends StatelessWidget {
  /// Stereo waveform data (L/R channels)
  final StereoWaveformData stereoData;

  /// Base track color (L channel uses this, R uses complementary)
  final Color color;

  /// Display mode
  final WaveformDisplayMode displayMode;

  /// Current playhead position (0-1)
  final double playheadPosition;

  /// Selection range (start, end) normalized 0-1
  final (double, double)? selection;

  /// Zoom level
  final double zoom;

  /// Scroll offset (normalized 0-1)
  final double scrollOffset;

  /// Show grid lines
  final bool showGrid;

  /// Show RMS as filled area
  final bool showRms;

  /// Height of the widget
  final double height;

  /// Show channel labels (L/R)
  final bool showChannelLabels;

  const StereoWaveformDisplay({
    super.key,
    required this.stereoData,
    this.color = const Color(0xFF4A9EFF),
    this.displayMode = WaveformDisplayMode.stereoSplit,
    this.playheadPosition = 0,
    this.selection,
    this.zoom = 1,
    this.scrollOffset = 0,
    this.showGrid = true,
    this.showRms = true,
    this.height = 80,
    this.showChannelLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          painter: _StereoWaveformPainter(
            stereoData: stereoData,
            color: color,
            displayMode: displayMode,
            playheadPosition: playheadPosition,
            selection: selection,
            zoom: zoom,
            scrollOffset: scrollOffset,
            showGrid: showGrid,
            showRms: showRms,
            showChannelLabels: showChannelLabels,
          ),
          size: Size(double.infinity, height),
        ),
      ),
    );
  }
}

class _StereoWaveformPainter extends CustomPainter {
  final StereoWaveformData stereoData;
  final Color color;
  final WaveformDisplayMode displayMode;
  final double playheadPosition;
  final (double, double)? selection;
  final double zoom;
  final double scrollOffset;
  final bool showGrid;
  final bool showRms;
  final bool showChannelLabels;

  // Channel colors - L is base color, R is complementary cyan
  late final Color leftColor;
  late final Color rightColor;

  _StereoWaveformPainter({
    required this.stereoData,
    required this.color,
    required this.displayMode,
    required this.playheadPosition,
    this.selection,
    required this.zoom,
    required this.scrollOffset,
    required this.showGrid,
    required this.showRms,
    required this.showChannelLabels,
  }) {
    // Professional DAW colors: L = base, R = cyan tint
    leftColor = color;
    rightColor = Color.lerp(color, FluxForgeTheme.accentCyan, 0.5) ?? color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (stereoData.isEmpty) return;

    // Background with subtle gradient
    _drawBackground(canvas, size);

    // Selection overlay
    if (selection != null) {
      _drawSelection(canvas, size);
    }

    switch (displayMode) {
      case WaveformDisplayMode.mono:
        _drawMonoWaveform(canvas, size);
        break;
      case WaveformDisplayMode.stereoSplit:
        _drawStereoSplitWaveform(canvas, size);
        break;
      case WaveformDisplayMode.stereoOverlapped:
        _drawStereoOverlappedWaveform(canvas, size);
        break;
    }

    // Grid lines (draw after waveform for visibility)
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // Playhead
    _drawPlayhead(canvas, size);

    // Border
    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawRect(Offset.zero & size, borderPaint);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Subtle gradient background for depth
    final bgGradient = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      [
        FluxForgeTheme.bgDeep,
        FluxForgeTheme.bgDeepest,
        FluxForgeTheme.bgDeep,
      ],
      [0.0, 0.5, 1.0],
    );

    final bgPaint = Paint()
      ..shader = bgGradient
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);
  }

  /// Draw mono waveform (summed L+R or mono source)
  void _drawMonoWaveform(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final halfHeight = size.height / 2 - 2;

    _drawChannelWaveform(
      canvas, size, stereoData.left,
      centerY, halfHeight, leftColor,
    );
  }

  /// Draw stereo split view - L on top, R on bottom (Cubase/Pro Tools style)
  void _drawStereoSplitWaveform(Canvas canvas, Size size) {
    final halfHeight = size.height / 2;
    final channelHeight = halfHeight - 2;

    // Draw center divider line with gradient
    final dividerPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, halfHeight),
        Offset(size.width, halfHeight),
        [
          FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
          FluxForgeTheme.borderSubtle.withValues(alpha: 0.6),
          FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
        ],
        [0.0, 0.5, 1.0],
      )
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawLine(
      Offset(0, halfHeight),
      Offset(size.width, halfHeight),
      dividerPaint,
    );

    // L channel (top half) - draw upward from center
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, halfHeight));
    _drawChannelWaveformSplit(
      canvas, size, stereoData.left,
      halfHeight - 1, channelHeight - 2, leftColor, true,
    );
    canvas.restore();

    // R channel (bottom half) - draw downward from center
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, halfHeight, size.width, halfHeight));
    _drawChannelWaveformSplit(
      canvas, size, stereoData.right,
      halfHeight + 1, channelHeight - 2, rightColor, false,
    );
    canvas.restore();

    // Channel labels
    if (showChannelLabels) {
      _drawChannelLabel(canvas, 'L', 4, 3, leftColor);
      _drawChannelLabel(canvas, 'R', 4, halfHeight + 3, rightColor);
    }
  }

  /// Draw stereo overlapped view - L/R overlaid with transparency (Logic style)
  void _drawStereoOverlappedWaveform(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final halfHeight = size.height / 2 - 2;

    // Draw R channel first (behind)
    _drawChannelWaveform(
      canvas, size, stereoData.right,
      centerY, halfHeight, rightColor.withValues(alpha: 0.5),
    );

    // Draw L channel on top
    _drawChannelWaveform(
      canvas, size, stereoData.left,
      centerY, halfHeight, leftColor.withValues(alpha: 0.8),
    );

    // Channel labels
    if (showChannelLabels) {
      _drawChannelLabel(canvas, 'L', 4, 3, leftColor);
      _drawChannelLabel(canvas, 'R', 18, 3, rightColor);
    }
  }

  /// Draw a single channel waveform centered with smooth curves
  void _drawChannelWaveform(
    Canvas canvas,
    Size size,
    List<WaveformPoint> data,
    double centerY,
    double halfHeight,
    Color channelColor,
  ) {
    if (data.isEmpty) return;

    final visibleStart = (scrollOffset * data.length).round();
    final visibleSamples = (data.length / zoom).round();
    final visibleEnd = math.min(visibleStart + visibleSamples, data.length);
    final samplesPerPixel = visibleSamples / size.width;

    if (samplesPerPixel <= 1) {
      _drawSampleLinesChannel(
        canvas, size, data, centerY, halfHeight,
        visibleStart, visibleEnd, channelColor,
      );
    } else {
      _drawEnvelopeChannel(
        canvas, size, data, centerY, halfHeight,
        visibleStart, visibleEnd, samplesPerPixel, channelColor,
      );
    }
  }

  /// Draw channel waveform for split view (one direction only) with smoothing
  void _drawChannelWaveformSplit(
    Canvas canvas,
    Size size,
    List<WaveformPoint> data,
    double baseY,
    double maxHeight,
    Color channelColor,
    bool drawUpward,
  ) {
    if (data.isEmpty) return;

    final visibleStart = (scrollOffset * data.length).round();
    final visibleSamples = (data.length / zoom).round();
    final samplesPerPixel = visibleSamples / size.width;

    // Collect peak and RMS values
    final List<double> peakValues = [];
    final List<double> rmsValues = [];

    for (double x = 0; x < size.width; x++) {
      final sampleIndex = visibleStart + (x * samplesPerPixel).round();
      if (sampleIndex >= data.length) break;

      final endIndex = math.min(sampleIndex + samplesPerPixel.ceil(), data.length);
      double peakVal = 0;
      double rmsSum = 0;
      int count = 0;

      for (int i = sampleIndex; i < endIndex; i++) {
        final point = data[i];
        peakVal = math.max(peakVal, math.max(point.max.abs(), point.min.abs()));
        rmsSum += point.rms * point.rms;
        count++;
      }

      peakValues.add(peakVal);
      rmsValues.add(count > 0 ? math.sqrt(rmsSum / count) : 0);
    }

    if (peakValues.isEmpty) return;

    final direction = drawUpward ? -1.0 : 1.0;

    // Build smooth peak path using quadratic bezier curves
    final peakPath = Path();
    peakPath.moveTo(0, baseY);

    for (int i = 0; i < peakValues.length; i++) {
      final x = i.toDouble();
      final peakY = baseY + direction * peakValues[i] * maxHeight;

      if (i == 0) {
        peakPath.lineTo(x, peakY);
      } else if (i < peakValues.length - 1) {
        // Smooth curve using quadratic bezier
        final prevY = baseY + direction * peakValues[i - 1] * maxHeight;
        final nextY = baseY + direction * peakValues[i + 1] * maxHeight;
        final controlY = (prevY + peakY * 2 + nextY) / 4;
        peakPath.quadraticBezierTo(x - 0.5, controlY, x, peakY);
      } else {
        peakPath.lineTo(x, peakY);
      }
    }

    // Complete path back to baseline
    peakPath.lineTo(peakValues.length - 1, baseY);
    peakPath.close();

    // Draw peak fill with gradient
    final peakGradient = ui.Gradient.linear(
      Offset(0, baseY),
      Offset(0, baseY + direction * maxHeight),
      [
        channelColor.withValues(alpha: 0.5),
        channelColor.withValues(alpha: 0.15),
      ],
    );

    final peakFillPaint = Paint()
      ..shader = peakGradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(peakPath, peakFillPaint);

    // Draw RMS fill with smoother curves
    if (showRms && rmsValues.isNotEmpty) {
      final rmsPath = Path();
      rmsPath.moveTo(0, baseY);

      for (int i = 0; i < rmsValues.length; i++) {
        final x = i.toDouble();
        final rmsY = baseY + direction * rmsValues[i] * maxHeight;

        if (i == 0) {
          rmsPath.lineTo(x, rmsY);
        } else if (i < rmsValues.length - 1) {
          final prevY = baseY + direction * rmsValues[i - 1] * maxHeight;
          final nextY = baseY + direction * rmsValues[i + 1] * maxHeight;
          final controlY = (prevY + rmsY * 2 + nextY) / 4;
          rmsPath.quadraticBezierTo(x - 0.5, controlY, x, rmsY);
        } else {
          rmsPath.lineTo(x, rmsY);
        }
      }

      rmsPath.lineTo(rmsValues.length - 1, baseY);
      rmsPath.close();

      final rmsFillPaint = Paint()
        ..color = channelColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(rmsPath, rmsFillPaint);
    }

    // Draw peak outline with anti-aliasing
    final peakStrokePaint = Paint()
      ..color = channelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(peakPath, peakStrokePaint);
  }

  void _drawSampleLinesChannel(
    Canvas canvas,
    Size size,
    List<WaveformPoint> data,
    double centerY,
    double halfHeight,
    int visibleStart,
    int visibleEnd,
    Color channelColor,
  ) {
    final path = Path();
    final pixelsPerSample = size.width / (visibleEnd - visibleStart);

    for (int i = visibleStart; i < visibleEnd; i++) {
      final x = (i - visibleStart) * pixelsPerSample;
      final point = data[i];
      final maxY = centerY - point.max * halfHeight;

      if (i == visibleStart) {
        path.moveTo(x, maxY);
      } else {
        path.lineTo(x, maxY);
      }
    }

    for (int i = visibleEnd - 1; i >= visibleStart; i--) {
      final x = (i - visibleStart) * pixelsPerSample;
      final point = data[i];
      final minY = centerY - point.min * halfHeight;
      path.lineTo(x, minY);
    }
    path.close();

    // Gradient fill
    final fillGradient = ui.Gradient.linear(
      Offset(0, centerY - halfHeight),
      Offset(0, centerY + halfHeight),
      [
        channelColor.withValues(alpha: 0.6),
        channelColor.withValues(alpha: 0.3),
        channelColor.withValues(alpha: 0.6),
      ],
      [0.0, 0.5, 1.0],
    );

    final fillPaint = Paint()
      ..shader = fillGradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = channelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
  }

  void _drawEnvelopeChannel(
    Canvas canvas,
    Size size,
    List<WaveformPoint> data,
    double centerY,
    double halfHeight,
    int visibleStart,
    int visibleEnd,
    double samplesPerPixel,
    Color channelColor,
  ) {
    final peakPath = Path();
    final rmsPath = Path();
    bool firstPoint = true;
    List<double> rmsTopPoints = [];
    List<double> rmsBottomPoints = [];
    List<double> maxPoints = [];

    for (double x = 0; x < size.width; x++) {
      final sampleIndex = visibleStart + (x * samplesPerPixel).round();
      if (sampleIndex >= data.length) break;

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

      if (firstPoint) {
        peakPath.moveTo(x, maxY);
        firstPoint = false;
      } else {
        peakPath.lineTo(x, maxY);
      }

      maxPoints.add(maxY);
      rmsTopPoints.add(centerY - rmsVal * halfHeight);
      rmsBottomPoints.add(centerY + rmsVal * halfHeight);
    }

    // Complete peak path with smooth bottom
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

    // Peak fill with gradient
    final peakGradient = ui.Gradient.linear(
      Offset(0, centerY - halfHeight),
      Offset(0, centerY + halfHeight),
      [
        channelColor.withValues(alpha: 0.4),
        channelColor.withValues(alpha: 0.2),
        channelColor.withValues(alpha: 0.4),
      ],
      [0.0, 0.5, 1.0],
    );

    final peakFillPaint = Paint()
      ..shader = peakGradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(peakPath, peakFillPaint);

    // RMS fill with smoothing
    if (showRms && rmsTopPoints.isNotEmpty) {
      rmsPath.moveTo(0, rmsTopPoints.first);
      for (int i = 1; i < rmsTopPoints.length; i++) {
        // Smooth using simple averaging
        if (i < rmsTopPoints.length - 1) {
          final controlY = (rmsTopPoints[i - 1] + rmsTopPoints[i] * 2 + rmsTopPoints[i + 1]) / 4;
          rmsPath.quadraticBezierTo(i - 0.5, controlY, i.toDouble(), rmsTopPoints[i]);
        } else {
          rmsPath.lineTo(i.toDouble(), rmsTopPoints[i]);
        }
      }
      for (int i = rmsBottomPoints.length - 1; i >= 0; i--) {
        if (i > 0 && i < rmsBottomPoints.length - 1) {
          final controlY = (rmsBottomPoints[i - 1] + rmsBottomPoints[i] * 2 + rmsBottomPoints[i + 1]) / 4;
          rmsPath.quadraticBezierTo(i + 0.5, controlY, i.toDouble(), rmsBottomPoints[i]);
        } else {
          rmsPath.lineTo(i.toDouble(), rmsBottomPoints[i]);
        }
      }
      rmsPath.close();

      final rmsFillPaint = Paint()
        ..color = channelColor.withValues(alpha: 0.65)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(rmsPath, rmsFillPaint);
    }

    // Peak outline
    final peakStrokePaint = Paint()
      ..color = channelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(peakPath, peakStrokePaint);
  }

  void _drawChannelLabel(Canvas canvas, String label, double x, double y, Color labelColor) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'JetBrains Mono',
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Background pill for readability
    final bgPaint = Paint()
      ..color = FluxForgeTheme.bgDeepest.withValues(alpha: 0.85)
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y - 1, textPainter.width + 4, textPainter.height + 2),
        const Radius.circular(3),
      ),
      bgPaint,
    );

    textPainter.paint(canvas, Offset(x, y));
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

    // Center line (0dB) - only for non-split modes
    if (displayMode != WaveformDisplayMode.stereoSplit) {
      final centerY = size.height / 2;
      gridPaint.color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.25);
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        gridPaint,
      );
    }

    // -6dB lines
    gridPaint.color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.12);
    final db6 = size.height * 0.25;
    canvas.drawLine(
      Offset(0, db6),
      Offset(size.width, db6),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height - db6),
      Offset(size.width, size.height - db6),
      gridPaint,
    );
  }

  void _drawSelection(Canvas canvas, Size size) {
    final (start, end) = selection!;
    final startX = start * size.width;
    final endX = end * size.width;

    // Selection fill with gradient
    final selectionGradient = ui.Gradient.linear(
      Offset(startX, 0),
      Offset(endX, 0),
      [
        FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
        FluxForgeTheme.accentBlue.withValues(alpha: 0.25),
        FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
      ],
      [0.0, 0.5, 1.0],
    );

    final selectionPaint = Paint()
      ..shader = selectionGradient
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX, size.height),
      selectionPaint,
    );

    // Selection edges with glow
    final edgeGlowPaint = Paint()
      ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
      ..strokeWidth = 2
      ..isAntiAlias = true;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), edgeGlowPaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), edgeGlowPaint);

    final edgePaint = Paint()
      ..color = FluxForgeTheme.accentBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), edgePaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), edgePaint);
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final x = playheadPosition * size.width;

    // Glow
    final glowPaint = Paint()
      ..color = FluxForgeTheme.textPrimary.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
      ..isAntiAlias = true;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);

    // Line
    final linePaint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Triangle head
    final headPaint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final headPath = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 6)
      ..close();
    canvas.drawPath(headPath, headPaint);
  }

  @override
  bool shouldRepaint(_StereoWaveformPainter oldDelegate) =>
      stereoData != oldDelegate.stereoData ||
      color != oldDelegate.color ||
      displayMode != oldDelegate.displayMode ||
      playheadPosition != oldDelegate.playheadPosition ||
      selection != oldDelegate.selection ||
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      showChannelLabels != oldDelegate.showChannelLabels;
}
