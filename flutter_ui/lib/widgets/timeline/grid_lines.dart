/// Grid Lines Widget
///
/// Canvas-based grid rendering with:
/// - Major/minor lines based on tempo
/// - Zoom-adaptive density
/// - High performance for 120fps

import 'package:flutter/material.dart';

class GridLines extends StatelessWidget {
  final double width;
  final double height;
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;

  const GridLines({
    super.key,
    required this.width,
    required this.height,
    required this.zoom,
    required this.scrollOffset,
    this.tempo = 120,
    this.timeSignatureNum = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridLinesPainter(
            zoom: zoom,
            scrollOffset: scrollOffset,
            tempo: tempo,
            timeSignatureNum: timeSignatureNum,
          ),
          size: Size(width, height),
        ),
      ),
    );
  }
}

class _GridLinesPainter extends CustomPainter {
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;

  _GridLinesPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.tempo,
    required this.timeSignatureNum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Calculate beat/bar durations
    final beatsPerSecond = tempo / 60;
    final beatDuration = 1 / beatsPerSecond;
    final barDuration = beatDuration * timeSignatureNum;

    // Determine grid density based on zoom
    double majorInterval;
    double minorInterval;

    if (zoom < 15) {
      majorInterval = barDuration * 4;
      minorInterval = barDuration;
    } else if (zoom < 40) {
      majorInterval = barDuration;
      minorInterval = beatDuration;
    } else if (zoom < 100) {
      majorInterval = beatDuration;
      minorInterval = beatDuration / 2;
    } else {
      majorInterval = beatDuration;
      minorInterval = beatDuration / 4;
    }

    // Visible time range
    final visibleDuration = size.width / zoom;
    final startTime = scrollOffset;
    final endTime = scrollOffset + visibleDuration;

    // Draw minor grid lines
    final minorPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 1;

    final firstMinor = (startTime / minorInterval).floor() * minorInterval;
    for (double t = firstMinor; t <= endTime; t += minorInterval) {
      // Skip if it's a major line
      if ((t % majorInterval).abs() < 0.0001) continue;

      final x = ((t - scrollOffset) * zoom).roundToDouble() + 0.5;
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          minorPaint,
        );
      }
    }

    // Draw major grid lines
    final majorPaint = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..strokeWidth = 1;

    final firstMajor = (startTime / majorInterval).floor() * majorInterval;
    for (double t = firstMajor; t <= endTime; t += majorInterval) {
      final x = ((t - scrollOffset) * zoom).roundToDouble() + 0.5;
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          majorPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter oldDelegate) =>
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      tempo != oldDelegate.tempo ||
      timeSignatureNum != oldDelegate.timeSignatureNum;
}
