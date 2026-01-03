/// Time Ruler Widget
///
/// Cubase-style time ruler with:
/// - Bar/Beat/Timecode/Samples display
/// - Zoom-adaptive tick density
/// - Loop region visualization
/// - Click to set playhead

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

class TimeRuler extends StatelessWidget {
  final double width;
  final double zoom; // pixels per second
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final int timeSignatureDenom;
  final TimeDisplayMode timeDisplayMode;
  final int sampleRate;
  final LoopRegion? loopRegion;
  final bool loopEnabled;
  final ValueChanged<double>? onTimeClick;
  final VoidCallback? onLoopToggle;

  const TimeRuler({
    super.key,
    required this.width,
    required this.zoom,
    required this.scrollOffset,
    this.tempo = 120,
    this.timeSignatureNum = 4,
    this.timeSignatureDenom = 4,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.sampleRate = 48000,
    this.loopRegion,
    this.loopEnabled = true,
    this.onTimeClick,
    this.onLoopToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final x = details.localPosition.dx;
        final time = scrollOffset + x / zoom;

        // Check if click is within loop region
        if (loopRegion != null && onLoopToggle != null) {
          final loopStartX = (loopRegion!.start - scrollOffset) * zoom;
          final loopEndX = (loopRegion!.end - scrollOffset) * zoom;
          if (x >= loopStartX && x <= loopEndX) {
            onLoopToggle?.call();
            return;
          }
        }

        onTimeClick?.call(time.clamp(0, double.infinity));
      },
      child: CustomPaint(
        painter: _TimeRulerPainter(
          zoom: zoom,
          scrollOffset: scrollOffset,
          tempo: tempo,
          timeSignatureNum: timeSignatureNum,
          timeDisplayMode: timeDisplayMode,
          sampleRate: sampleRate,
          loopRegion: loopRegion,
          loopEnabled: loopEnabled,
        ),
        size: Size(width, 28),
      ),
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final TimeDisplayMode timeDisplayMode;
  final int sampleRate;
  final LoopRegion? loopRegion;
  final bool loopEnabled;

  _TimeRulerPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.tempo,
    required this.timeSignatureNum,
    required this.timeDisplayMode,
    required this.sampleRate,
    this.loopRegion,
    required this.loopEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = ReelForgeTheme.bgDeep;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw loop region
    if (loopRegion != null) {
      _drawLoopRegion(canvas, size);
    }

    // Calculate tick interval
    final visibleDuration = size.width / zoom;
    final startTime = scrollOffset;
    final endTime = scrollOffset + visibleDuration;

    double tickInterval = _calculateTickInterval();

    // Draw ticks and labels
    final tickPaint = Paint()
      ..color = ReelForgeTheme.textTertiary
      ..strokeWidth = 1;

    final textStyle = ui.TextStyle(
      color: ReelForgeTheme.textTertiary,
      fontSize: 10,
      fontFamily: 'Inter',
    );

    final firstTick = (startTime / tickInterval).floor() * tickInterval;

    for (double t = firstTick; t <= endTime; t += tickInterval) {
      final x = (t - scrollOffset) * zoom;
      if (x < 0 || x > size.width) continue;

      // Major tick
      canvas.drawLine(
        Offset(x, 16),
        Offset(x, 24),
        tickPaint,
      );

      // Label
      final label = formatTime(
        t,
        timeDisplayMode,
        tempo: tempo,
        timeSignatureNum: timeSignatureNum,
        sampleRate: sampleRate,
      );

      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 10,
      ))
        ..pushStyle(textStyle)
        ..addText(label);

      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 60));

      canvas.drawParagraph(
        paragraph,
        Offset(x - 30, 2),
      );
    }

    // Bottom border
    final borderPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      borderPaint,
    );
  }

  void _drawLoopRegion(Canvas canvas, Size size) {
    final region = loopRegion!;
    final loopStartX = (region.start - scrollOffset) * zoom;
    final loopEndX = (region.end - scrollOffset) * zoom;
    final loopWidth = loopEndX - loopStartX;

    if (loopEnabled) {
      // Active loop - filled
      final fillPaint = Paint()
        ..color = ReelForgeTheme.accentBlue.withValues(alpha: 0.35);
      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopWidth, size.height),
        fillPaint,
      );

      // Top border
      final borderPaint = Paint()
        ..color = ReelForgeTheme.accentBlue.withValues(alpha: 0.9)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(loopStartX, 0),
        Offset(loopEndX, 0),
        borderPaint,
      );

      // Left/right brackets
      canvas.drawLine(
        Offset(loopStartX, 0),
        Offset(loopStartX, size.height),
        borderPaint,
      );
      canvas.drawLine(
        Offset(loopEndX, 0),
        Offset(loopEndX, size.height),
        borderPaint,
      );
    } else {
      // Inactive loop - dimmed
      final fillPaint = Paint()
        ..color = const Color(0xFF646464).withValues(alpha: 0.15);
      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopWidth, size.height),
        fillPaint,
      );

      // Dim border
      final borderPaint = Paint()
        ..color = const Color(0xFF646464).withValues(alpha: 0.4)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(loopStartX, 0),
        Offset(loopEndX, 0),
        borderPaint,
      );
    }
  }

  double _calculateTickInterval() {
    final beatsPerSecond = tempo / 60;
    final beatDuration = 1 / beatsPerSecond;
    final barDuration = beatDuration * timeSignatureNum;

    if (timeDisplayMode == TimeDisplayMode.bars) {
      if (zoom < 20) return barDuration * 4;
      if (zoom < 50) return barDuration;
      if (zoom < 150) return beatDuration;
      return beatDuration / 4;
    } else {
      if (zoom < 10) return 10;
      if (zoom < 30) return 5;
      if (zoom < 80) return 1;
      if (zoom < 200) return 0.5;
      return 0.1;
    }
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) =>
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      tempo != oldDelegate.tempo ||
      loopRegion != oldDelegate.loopRegion ||
      loopEnabled != oldDelegate.loopEnabled;
}
