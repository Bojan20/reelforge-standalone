// Timeline Waveform Painter — Multi-LOD Waveform Rendering
//
// Professional waveform rendering with 4 LOD levels:
// - LOD 0: Min/Max peaks (< 1x zoom)
// - LOD 1: RMS + peaks (1x-4x zoom)
// - LOD 2: Half-wave (4x-16x zoom)
// - LOD 3: Full samples (> 16x zoom)
//
// Supports multiple styles: peaks, rms, halfWave, filled, outline

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

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

/// Timeline waveform painter
class TimelineWaveformPainter extends CustomPainter {
  final List<double>? waveformData;  // From Rust FFI (Float32List)
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
    required this.waveformData,
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
    if (waveformData == null || waveformData!.isEmpty) {
      // No waveform data — paint placeholder
      _paintPlaceholder(canvas, size);
      return;
    }

    // Select LOD based on zoom
    final lod = _selectLOD(zoom);

    // Select color based on state
    final waveColor = isMuted
        ? colors.muted
        : (isSelected ? colors.selected : colors.normal);

    // Paint waveform based on style
    switch (style) {
      case WaveformStyle.peaks:
        _paintPeaks(canvas, size, waveColor, lod);
        break;
      case WaveformStyle.rms:
        _paintRMS(canvas, size, waveColor, lod);
        break;
      case WaveformStyle.halfWave:
        _paintHalfWave(canvas, size, waveColor, lod);
        break;
      case WaveformStyle.filled:
        _paintFilled(canvas, size, waveColor, lod);
        break;
      case WaveformStyle.outline:
        _paintOutline(canvas, size, waveColor, lod);
        break;
    }
  }

  /// Select LOD level based on zoom
  int _selectLOD(double zoom) {
    if (zoom < 1.0) return 0;  // LOD 0: Min/Max peaks
    if (zoom < 4.0) return 1;  // LOD 1: RMS + peaks
    if (zoom < 16.0) return 2; // LOD 2: Half-wave
    return 3;                  // LOD 3: Full samples
  }

  /// Paint placeholder when no waveform data
  void _paintPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw center line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    // Draw "Loading..." text
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

  /// Paint peaks (default style)
  void _paintPeaks(Canvas canvas, Size size, Color waveColor, int lod) {
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

      // Find min/max in this pixel range
      double min = 0.0;
      double max = 0.0;

      for (int i = startSample; i < endSample && i < data.length; i += step) {
        final sample = data[i].clamp(-1.0, 1.0);
        if (sample < min) min = sample;
        if (sample > max) max = sample;
      }

      // Draw vertical line for this pixel
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

  /// Paint RMS envelope
  void _paintRMS(Canvas canvas, Size size, Color waveColor, int lod) {
    final paint = Paint()
      ..color = waveColor.withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final scaleY = size.height / 2;

    final data = waveformData!;
    final samplesPerPixel = data.length / size.width;

    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) break;

      // Calculate RMS for this pixel range
      double sumSquares = 0.0;
      int count = 0;

      for (int i = startSample; i < endSample && i < data.length; i++) {
        final sample = data[i].clamp(-1.0, 1.0);
        sumSquares += sample * sample;
        count++;
      }

      final rms = count > 0 ? (sumSquares / count) : 0.0;
      final rmsValue = rms > 0 ? rms : 0.0;

      final y = centerY - (rmsValue * scaleY);

      if (x == 0) {
        path.moveTo(x.toDouble(), centerY);
      }

      path.lineTo(x.toDouble(), y);
    }

    canvas.drawPath(path, paint);
  }

  /// Paint half-wave (Pro Tools style)
  void _paintHalfWave(Canvas canvas, Size size, Color waveColor, int lod) {
    final paint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerY = size.height / 2;
    final scaleY = size.height / 2;

    final data = waveformData!;
    final samplesPerPixel = data.length / size.width;

    path.moveTo(0, centerY);

    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) break;

      // Find max (positive only)
      double max = 0.0;

      for (int i = startSample; i < endSample && i < data.length; i++) {
        final sample = data[i].clamp(-1.0, 1.0).abs();
        if (sample > max) max = sample;
      }

      final y = centerY - (max * scaleY);
      path.lineTo(x.toDouble(), y);
    }

    // Close path back to center line
    path.lineTo(size.width, centerY);
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Paint filled waveform
  void _paintFilled(Canvas canvas, Size size, Color waveColor, int lod) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          waveColor.withOpacity(0.8),
          waveColor.withOpacity(0.3),
        ],
      )
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerY = size.height / 2;
    final scaleY = size.height / 2;

    final data = waveformData!;
    final samplesPerPixel = data.length / size.width;

    path.moveTo(0, centerY);

    // Top half
    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) break;

      double max = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final sample = data[i].clamp(-1.0, 1.0);
        if (sample > max) max = sample;
      }

      final y = centerY - (max * scaleY);
      path.lineTo(x.toDouble(), y);
    }

    // Bottom half (reverse)
    for (int x = size.width.toInt() - 1; x >= 0; x--) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) continue;

      double min = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final sample = data[i].clamp(-1.0, 1.0);
        if (sample < min) min = sample;
      }

      final y = centerY - (min * scaleY);
      path.lineTo(x.toDouble(), y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  /// Paint outline only
  void _paintOutline(Canvas canvas, Size size, Color waveColor, int lod) {
    final paint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final scaleY = size.height / 2;

    final data = waveformData!;
    final samplesPerPixel = data.length / size.width;

    // Top outline
    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) break;

      double max = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final sample = data[i].clamp(-1.0, 1.0);
        if (sample > max) max = sample;
      }

      final y = centerY - (max * scaleY);

      if (x == 0) {
        path.moveTo(x.toDouble(), y);
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    // Bottom outline (reverse)
    for (int x = size.width.toInt() - 1; x >= 0; x--) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);

      if (startSample >= data.length) continue;

      double min = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final sample = data[i].clamp(-1.0, 1.0);
        if (sample < min) min = sample;
      }

      final y = centerY - (min * scaleY);
      path.lineTo(x.toDouble(), y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TimelineWaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.style != style ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.isMuted != isMuted ||
        oldDelegate.zoom != zoom ||
        oldDelegate.trimStart != trimStart ||
        oldDelegate.trimEnd != trimEnd;
  }
}
