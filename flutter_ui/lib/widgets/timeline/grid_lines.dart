/// Grid Lines Widget
///
/// Professional DAW-style beat/bar grid with:
/// - Clear bar lines (thick, orange accent)
/// - Beat lines (medium, cyan accent)
/// - Subdivision lines (thin, subtle)
/// - Zoom-adaptive density (LOD)
/// - High performance for 120fps
///
/// Visual hierarchy (Cubase/Logic inspired):
/// - Bars: 2px thick, orange glow
/// - Beats: 1px, cyan tint
/// - Subdivisions: 1px, very subtle

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class GridLines extends StatelessWidget {
  final double width;
  final double height;
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final int timeSignatureDenom;
  final bool showBeatNumbers;
  /// Snap value in beats (0.25 = 1/16, 0.5 = 1/8, 1 = 1/4, etc.)
  /// Grid lines are drawn to match this value.
  final double snapValue;

  const GridLines({
    super.key,
    required this.width,
    required this.height,
    required this.zoom,
    required this.scrollOffset,
    this.tempo = 120,
    this.timeSignatureNum = 4,
    this.timeSignatureDenom = 4,
    this.showBeatNumbers = false,
    this.snapValue = 1,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: Don't wrap in Positioned here - that's the parent's responsibility
    // This allows GridLines to be used inside RepaintBoundary without
    // causing ParentDataWidget errors
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridLinesPainter(
          zoom: zoom,
          scrollOffset: scrollOffset,
          tempo: tempo,
          timeSignatureNum: timeSignatureNum,
          timeSignatureDenom: timeSignatureDenom,
          showBeatNumbers: showBeatNumbers,
          snapValue: snapValue,
        ),
        size: Size(width, height),
      ),
    );
  }
}

class _GridLinesPainter extends CustomPainter {
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final int timeSignatureDenom;
  final bool showBeatNumbers;
  final double snapValue;

  // Cached paints for performance
  static final Paint _barPaint = Paint()
    ..color = FluxForgeTheme.accentOrange.withValues(alpha: 0.5)
    ..strokeWidth = 2;

  static final Paint _barGlowPaint = Paint()
    ..color = FluxForgeTheme.accentOrange.withValues(alpha: 0.15)
    ..strokeWidth = 6;

  static final Paint _beatPaint = Paint()
    ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.25)
    ..strokeWidth = 1;

  static final Paint _subdivisionPaint = Paint()
    ..color = const Color(0x12FFFFFF)
    ..strokeWidth = 1;

  static final Paint _finePaint = Paint()
    ..color = const Color(0x08FFFFFF)
    ..strokeWidth = 1;

  /// Snap grid lines — matches the selected snap resolution
  static final Paint _snapPaint = Paint()
    ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
    ..strokeWidth = 1;

  _GridLinesPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.tempo,
    required this.timeSignatureNum,
    required this.timeSignatureDenom,
    required this.showBeatNumbers,
    required this.snapValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Calculate musical timing
    final beatsPerSecond = tempo / 60;
    final beatDuration = 1 / beatsPerSecond;
    final barDuration = beatDuration * timeSignatureNum;

    // Visible time range
    final visibleDuration = size.width / zoom;
    final startTime = scrollOffset;
    final endTime = scrollOffset + visibleDuration;

    // Cubase-style: grid density driven by snap value
    // snapValue is in beats: 0.0625=1/64, 0.125=1/32, 0.25=1/16, 0.5=1/8, 1=1/4, 2=1/2, 4=bar
    final snapInterval = snapValue * beatDuration; // Convert beats to seconds

    // Draw snap grid lines (finest visible level)
    // Only draw if lines won't be too dense (min ~4px apart)
    final snapPixelGap = snapInterval * zoom;
    if (snapPixelGap >= 4 && snapValue < timeSignatureNum) {
      // skipInterval = next coarser grid level to avoid double-drawing
      final skipInterval = snapValue < 1 ? beatDuration : barDuration;
      _drawGridLines(
        canvas, size, startTime, endTime,
        snapInterval, skipInterval, _snapPaint,
      );
    }

    // Draw beat lines (if snap is finer than beats)
    if (snapValue < 1) {
      _drawGridLines(
        canvas, size, startTime, endTime,
        beatDuration, barDuration, _beatPaint,
      );
    }

    // Bar lines — always visible with glow
    _drawBarLines(canvas, size, startTime, endTime, barDuration);
  }

  void _drawGridLines(
    Canvas canvas,
    Size size,
    double startTime,
    double endTime,
    double interval,
    double skipInterval,
    Paint paint,
  ) {
    final firstLine = (startTime / interval).floor() * interval;

    for (double t = firstLine; t <= endTime; t += interval) {
      // Skip if this line will be drawn by a higher-level grid
      if ((t % skipInterval).abs() < 0.0001) continue;
      if (t < 0) continue;

      final x = ((t - scrollOffset) * zoom).roundToDouble() + 0.5;
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          paint,
        );
      }
    }
  }

  void _drawBarLines(
    Canvas canvas,
    Size size,
    double startTime,
    double endTime,
    double barDuration,
  ) {
    final firstBar = (startTime / barDuration).floor() * barDuration;

    for (double t = firstBar; t <= endTime; t += barDuration) {
      if (t < 0) continue;

      final x = ((t - scrollOffset) * zoom).roundToDouble() + 0.5;
      if (x >= 0 && x <= size.width) {
        // Draw glow first (behind main line)
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          _barGlowPaint,
        );

        // Draw main bar line
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          _barPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter oldDelegate) =>
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      tempo != oldDelegate.tempo ||
      timeSignatureNum != oldDelegate.timeSignatureNum ||
      timeSignatureDenom != oldDelegate.timeSignatureDenom ||
      showBeatNumbers != oldDelegate.showBeatNumbers ||
      snapValue != oldDelegate.snapValue;
}
