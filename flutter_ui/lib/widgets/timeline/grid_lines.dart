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
import '../../theme/reelforge_theme.dart';

/// Grid detail level based on zoom
enum GridDetailLevel {
  bars,        // zoom < 15: only bars visible
  beats,       // zoom 15-50: bars + beats
  subdivisions, // zoom 50-150: + half beats
  fine,        // zoom > 150: + quarter beats
}

class GridLines extends StatelessWidget {
  final double width;
  final double height;
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final int timeSignatureDenom;
  final bool showBeatNumbers;

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

  // Cached paints for performance
  static final Paint _barPaint = Paint()
    ..color = ReelForgeTheme.accentOrange.withValues(alpha: 0.5)
    ..strokeWidth = 2;

  static final Paint _barGlowPaint = Paint()
    ..color = ReelForgeTheme.accentOrange.withValues(alpha: 0.15)
    ..strokeWidth = 6;

  static final Paint _beatPaint = Paint()
    ..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.25)
    ..strokeWidth = 1;

  static final Paint _subdivisionPaint = Paint()
    ..color = const Color(0x12FFFFFF)
    ..strokeWidth = 1;

  static final Paint _finePaint = Paint()
    ..color = const Color(0x08FFFFFF)
    ..strokeWidth = 1;

  _GridLinesPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.tempo,
    required this.timeSignatureNum,
    required this.timeSignatureDenom,
    required this.showBeatNumbers,
  });

  GridDetailLevel _getDetailLevel() {
    if (zoom < 15) return GridDetailLevel.bars;
    if (zoom < 50) return GridDetailLevel.beats;
    if (zoom < 150) return GridDetailLevel.subdivisions;
    return GridDetailLevel.fine;
  }

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

    final detailLevel = _getDetailLevel();

    // Draw from back to front (subdivisions → beats → bars)

    // 1. Fine subdivisions (1/16 notes) - only at high zoom
    if (detailLevel == GridDetailLevel.fine) {
      final fineInterval = beatDuration / 4;
      _drawGridLines(
        canvas, size, startTime, endTime,
        fineInterval, beatDuration / 2, _finePaint,
      );
    }

    // 2. Subdivisions (1/8 notes)
    if (detailLevel.index >= GridDetailLevel.subdivisions.index) {
      final subdivisionInterval = beatDuration / 2;
      _drawGridLines(
        canvas, size, startTime, endTime,
        subdivisionInterval, beatDuration, _subdivisionPaint,
      );
    }

    // 3. Beat lines
    if (detailLevel.index >= GridDetailLevel.beats.index) {
      _drawGridLines(
        canvas, size, startTime, endTime,
        beatDuration, barDuration, _beatPaint,
      );
    }

    // 4. Bar lines (always visible) - with glow effect
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
      showBeatNumbers != oldDelegate.showBeatNumbers;
}
