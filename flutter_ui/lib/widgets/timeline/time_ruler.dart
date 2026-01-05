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

class TimeRuler extends StatefulWidget {
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
  final double playheadPosition;
  final ValueChanged<double>? onTimeClick;
  /// Called during scrub/drag on ruler (Cubase-style)
  final ValueChanged<double>? onTimeScrub;
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
    this.playheadPosition = 0,
    this.onTimeClick,
    this.onTimeScrub,
    this.onLoopToggle,
  });

  @override
  State<TimeRuler> createState() => _TimeRulerState();
}

class _TimeRulerState extends State<TimeRuler> {
  bool _isDragging = false;
  bool _isHovering = false;
  double _hoverX = -1;

  double _xToTime(double x) {
    return widget.scrollOffset + x / widget.zoom;
  }

  void _handleTapDown(TapDownDetails details) {
    final x = details.localPosition.dx;
    final y = details.localPosition.dy;
    final time = _xToTime(x);

    // Cubase-style: Upper half is loop region, lower half is position
    // Upper 12px = loop region interaction
    // Lower 16px = position cursor

    if (y < 12 && widget.loopRegion != null && widget.onLoopToggle != null) {
      // Check if click is within loop region (upper zone)
      final loopStartX = (widget.loopRegion!.start - widget.scrollOffset) * widget.zoom;
      final loopEndX = (widget.loopRegion!.end - widget.scrollOffset) * widget.zoom;
      if (x >= loopStartX && x <= loopEndX) {
        widget.onLoopToggle?.call();
        return;
      }
    }

    // Lower zone - set position (Cubase-style immediate position)
    widget.onTimeClick?.call(time.clamp(0, double.infinity));
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() => _isDragging = true);
    final time = _xToTime(details.localPosition.dx);
    // Start scrubbing
    (widget.onTimeScrub ?? widget.onTimeClick)?.call(time.clamp(0, double.infinity));
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final time = _xToTime(details.localPosition.dx);
    // Continue scrubbing (Cubase-style - cursor follows mouse)
    (widget.onTimeScrub ?? widget.onTimeClick)?.call(time.clamp(0, double.infinity));
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() {
        _isHovering = false;
        _hoverX = -1;
      }),
      onHover: (event) => setState(() => _hoverX = event.localPosition.dx),
      cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        child: CustomPaint(
          painter: _TimeRulerPainter(
            zoom: widget.zoom,
            scrollOffset: widget.scrollOffset,
            tempo: widget.tempo,
            timeSignatureNum: widget.timeSignatureNum,
            timeDisplayMode: widget.timeDisplayMode,
            sampleRate: widget.sampleRate,
            loopRegion: widget.loopRegion,
            loopEnabled: widget.loopEnabled,
            playheadPosition: widget.playheadPosition,
            hoverX: _isHovering ? _hoverX : -1,
            isDragging: _isDragging,
          ),
          size: Size(widget.width, 28),
        ),
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
  final double playheadPosition;
  final double hoverX;
  final bool isDragging;

  _TimeRulerPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.tempo,
    required this.timeSignatureNum,
    required this.timeDisplayMode,
    required this.sampleRate,
    this.loopRegion,
    required this.loopEnabled,
    required this.playheadPosition,
    this.hoverX = -1,
    this.isDragging = false,
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

    // Hover indicator (Cubase-style position preview)
    if (hoverX >= 0 && hoverX <= size.width && !isDragging) {
      final hoverPaint = Paint()
        ..color = ReelForgeTheme.textTertiary.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(hoverX, 12),
        Offset(hoverX, size.height),
        hoverPaint,
      );
    }

    // Playhead triangle (Cubase-style at top of ruler)
    final playheadX = (playheadPosition - scrollOffset) * zoom;
    if (playheadX >= 0 && playheadX <= size.width) {
      final playheadPaint = Paint()
        ..color = ReelForgeTheme.accentRed
        ..style = PaintingStyle.fill;

      // Draw inverted triangle at bottom pointing down
      final path = Path()
        ..moveTo(playheadX - 6, size.height - 10)
        ..lineTo(playheadX + 6, size.height - 10)
        ..lineTo(playheadX, size.height)
        ..close();

      canvas.drawPath(path, playheadPaint);

      // Playhead line
      canvas.drawLine(
        Offset(playheadX, size.height - 10),
        Offset(playheadX, 0),
        Paint()
          ..color = ReelForgeTheme.accentRed.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
    }
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
      loopEnabled != oldDelegate.loopEnabled ||
      playheadPosition != oldDelegate.playheadPosition ||
      hoverX != oldDelegate.hoverX ||
      isDragging != oldDelegate.isDragging;
}
