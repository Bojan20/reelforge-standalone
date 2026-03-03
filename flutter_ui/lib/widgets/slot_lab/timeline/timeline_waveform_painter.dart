// Timeline Waveform Painter — Multi-LOD Waveform Rendering
//
// Professional waveform rendering using shared WaveformCache (same as DAW):
// - Reads MultiResWaveform from global WaveformCache singleton
// - Automatic LOD selection based on zoom (11 levels from Rust SIMD)
// - Falls back to inline List<double> for legacy/migration data
// - O(width) render time regardless of audio length
//
// Supports multiple styles: peaks, rms, halfWave, filled, outline

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../../services/waveform_cache.dart';

/// Waveform rendering style
enum WaveformStyle {
  peaks,        // Min/Max peaks (default)
  rms,          // RMS envelope
  halfWave,     // Top half only (Pro Tools style)
  filled,       // Solid fill
  outline,      // Outline only
}

/// Waveform color scheme
class WaveformColors {
  final Color normal;     // Default waveform color
  final Color selected;   // Selected region
  final Color muted;      // Muted region
  final Color clipping;   // Clipping samples (> 0dBFS)
  final Color lowLevel;   // Low level samples (< −40dBFS)

  const WaveformColors({
    this.normal = const Color(0xFF4A9EFF),
    this.selected = const Color(0xFFFF9040),
    this.muted = const Color(0xFF808080),
    this.clipping = const Color(0xFFFF4060),
    this.lowLevel = const Color(0xFF40C8FF),
  });
}

/// Timeline waveform painter — uses shared WaveformCache for instant rendering
class TimelineWaveformPainter extends CustomPainter {
  /// Cache key for shared WaveformCache lookup (preferred — instant LOD)
  final String? cacheKey;
  /// Legacy inline data (fallback when cache key not available)
  final List<double>? waveformData;
  final int sampleRate;
  final int channels;
  final WaveformStyle style;
  final WaveformColors colors;
  final bool isSelected;
  final bool isMuted;
  final double zoom;
  final double trimStart;    // Trim offset (seconds)
  final double trimEnd;      // Trim from end (seconds)

  const TimelineWaveformPainter({
    this.cacheKey,
    this.waveformData,
    this.sampleRate = 44100,
    this.channels = 2,
    this.style = WaveformStyle.peaks,
    this.colors = const WaveformColors(),
    this.isSelected = false,
    this.isMuted = false,
    this.zoom = 1.0,
    this.trimStart = 0.0,
    this.trimEnd = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Select color based on state
    final waveColor = isMuted
        ? colors.muted
        : (isSelected ? colors.selected : colors.normal);

    // Try shared cache first (instant LOD — same source as DAW)
    if (cacheKey != null) {
      final multiRes = WaveformCache().getMultiRes(cacheKey!);
      if (multiRes != null) {
        _paintFromMultiRes(canvas, size, waveColor, multiRes);
        return;
      }
    }

    // Fallback: inline waveform data (legacy path)
    if (waveformData != null && waveformData!.isNotEmpty) {
      _paintFromInlineData(canvas, size, waveColor);
      return;
    }

    // No data — placeholder
    _paintPlaceholder(canvas, size);
  }

  /// Paint using MultiResWaveform from shared cache (instant — O(width))
  void _paintFromMultiRes(Canvas canvas, Size size, Color waveColor, MultiResWaveform multiRes) {
    final lod = multiRes.getBestLodLevel(zoom);
    final level = multiRes.getLevel(lod);

    if (level.length == 0) {
      _paintPlaceholder(canvas, size);
      return;
    }

    final paint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    final scaleY = size.height / 2;
    final width = size.width.toInt();

    switch (style) {
      case WaveformStyle.peaks:
      case WaveformStyle.rms:
        _paintPeaksFromLOD(canvas, size, paint, level, centerY, scaleY, width);
        break;
      case WaveformStyle.halfWave:
        _paintHalfWaveFromLOD(canvas, size, waveColor, level, centerY, scaleY, width);
        break;
      case WaveformStyle.filled:
        _paintFilledFromLOD(canvas, size, waveColor, level, centerY, scaleY, width);
        break;
      case WaveformStyle.outline:
        _paintOutlineFromLOD(canvas, size, paint, level, centerY, scaleY, width);
        break;
    }
  }

  /// Paint min/max peaks from pre-computed LOD level — O(width), zero iteration
  void _paintPeaksFromLOD(Canvas canvas, Size size, Paint paint, PeakLevel level,
      double centerY, double scaleY, int width) {
    final path = Path();
    final peaksPerPixel = level.length / width;

    for (int x = 0; x < width; x++) {
      final startPeak = (x * peaksPerPixel).floor();
      final endPeak = ((x + 1) * peaksPerPixel).ceil().clamp(0, level.length);

      if (startPeak >= level.length) break;

      // Find min/max across peak buckets for this pixel
      double minVal = level.minPeaks[startPeak];
      double maxVal = level.maxPeaks[startPeak];

      for (int i = startPeak + 1; i < endPeak; i++) {
        final mn = level.minPeaks[i];
        final mx = level.maxPeaks[i];
        if (mn < minVal) minVal = mn;
        if (mx > maxVal) maxVal = mx;
      }

      final y1 = centerY - (maxVal.clamp(-1.0, 1.0) * scaleY);
      final y2 = centerY - (minVal.clamp(-1.0, 1.0) * scaleY);

      if (x == 0) {
        path.moveTo(x.toDouble(), y1);
      }
      path.lineTo(x.toDouble(), y1);
      path.lineTo(x.toDouble(), y2);
    }

    canvas.drawPath(path, paint);
  }

  /// Paint half-wave from LOD (Pro Tools style)
  void _paintHalfWaveFromLOD(Canvas canvas, Size size, Color waveColor, PeakLevel level,
      double centerY, double scaleY, int width) {
    final paint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final peaksPerPixel = level.length / width;
    path.moveTo(0, centerY);

    for (int x = 0; x < width; x++) {
      final startPeak = (x * peaksPerPixel).floor();
      final endPeak = ((x + 1) * peaksPerPixel).ceil().clamp(0, level.length);
      if (startPeak >= level.length) break;

      double maxAbs = 0.0;
      for (int i = startPeak; i < endPeak; i++) {
        final absMax = level.maxPeaks[i].abs();
        final absMin = level.minPeaks[i].abs();
        final m = absMax > absMin ? absMax : absMin;
        if (m > maxAbs) maxAbs = m;
      }

      final y = centerY - (maxAbs.clamp(0.0, 1.0) * scaleY);
      path.lineTo(x.toDouble(), y);
    }

    path.lineTo(size.width, centerY);
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Paint filled waveform from LOD
  void _paintFilledFromLOD(Canvas canvas, Size size, Color waveColor, PeakLevel level,
      double centerY, double scaleY, int width) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, size.height),
        [waveColor.withOpacity(0.8), waveColor.withOpacity(0.3)],
      )
      ..style = PaintingStyle.fill;

    final path = Path();
    final peaksPerPixel = level.length / width;
    path.moveTo(0, centerY);

    // Top half (max values)
    for (int x = 0; x < width; x++) {
      final startPeak = (x * peaksPerPixel).floor();
      final endPeak = ((x + 1) * peaksPerPixel).ceil().clamp(0, level.length);
      if (startPeak >= level.length) break;

      double maxVal = level.maxPeaks[startPeak];
      for (int i = startPeak + 1; i < endPeak; i++) {
        if (level.maxPeaks[i] > maxVal) maxVal = level.maxPeaks[i];
      }
      path.lineTo(x.toDouble(), centerY - (maxVal.clamp(-1.0, 1.0) * scaleY));
    }

    // Bottom half (min values, reverse)
    for (int x = width - 1; x >= 0; x--) {
      final startPeak = (x * peaksPerPixel).floor();
      final endPeak = ((x + 1) * peaksPerPixel).ceil().clamp(0, level.length);
      if (startPeak >= level.length) continue;

      double minVal = level.minPeaks[startPeak];
      for (int i = startPeak + 1; i < endPeak; i++) {
        if (level.minPeaks[i] < minVal) minVal = level.minPeaks[i];
      }
      path.lineTo(x.toDouble(), centerY - (minVal.clamp(-1.0, 1.0) * scaleY));
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  /// Paint outline from LOD
  void _paintOutlineFromLOD(Canvas canvas, Size size, Paint paint, PeakLevel level,
      double centerY, double scaleY, int width) {
    final outlinePaint = Paint()
      ..color = paint.color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final peaksPerPixel = level.length / width;

    // Top outline
    for (int x = 0; x < width; x++) {
      final startPeak = (x * peaksPerPixel).floor();
      final endPeak = ((x + 1) * peaksPerPixel).ceil().clamp(0, level.length);
      if (startPeak >= level.length) break;

      double maxVal = level.maxPeaks[startPeak];
      for (int i = startPeak + 1; i < endPeak; i++) {
        if (level.maxPeaks[i] > maxVal) maxVal = level.maxPeaks[i];
      }
      final y = centerY - (maxVal.clamp(-1.0, 1.0) * scaleY);
      if (x == 0) {
        path.moveTo(x.toDouble(), y);
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    // Bottom outline (reverse)
    for (int x = width - 1; x >= 0; x--) {
      final startPeak = (x * peaksPerPixel).floor();
      final endPeak = ((x + 1) * peaksPerPixel).ceil().clamp(0, level.length);
      if (startPeak >= level.length) continue;

      double minVal = level.minPeaks[startPeak];
      for (int i = startPeak + 1; i < endPeak; i++) {
        if (level.minPeaks[i] < minVal) minVal = level.minPeaks[i];
      }
      path.lineTo(x.toDouble(), centerY - (minVal.clamp(-1.0, 1.0) * scaleY));
    }

    path.close();
    canvas.drawPath(path, outlinePaint);
  }

  /// Paint from inline waveform data (legacy fallback)
  void _paintFromInlineData(Canvas canvas, Size size, Color waveColor) {
    final paint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final scaleY = size.height / 2;

    final data = waveformData!;
    final samplesPerPixel = data.length / size.width;
    final step = samplesPerPixel < 1 ? 1 : samplesPerPixel.ceil();

    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) break;

      double min = 0.0;
      double max = 0.0;

      for (int i = startSample; i < endSample && i < data.length; i += step) {
        final sample = data[i].clamp(-1.0, 1.0);
        if (sample < min) min = sample;
        if (sample > max) max = sample;
      }

      final y1 = centerY - (max * scaleY);
      final y2 = centerY - (min * scaleY);

      if (x == 0) {
        path.moveTo(x.toDouble(), y1);
      }

      path.lineTo(x.toDouble(), y1);
      path.lineTo(x.toDouble(), y2);
    }

    canvas.drawPath(path, paint);
  }

  /// Paint placeholder when no waveform data
  void _paintPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Loading waveform...',
        style: TextStyle(fontSize: 9, color: Colors.white38),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(TimelineWaveformPainter oldDelegate) {
    return oldDelegate.cacheKey != cacheKey ||
        oldDelegate.waveformData != waveformData ||
        oldDelegate.style != style ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.isMuted != isMuted ||
        oldDelegate.zoom != zoom ||
        oldDelegate.trimStart != trimStart ||
        oldDelegate.trimEnd != trimEnd;
  }
}
