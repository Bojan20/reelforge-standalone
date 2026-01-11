/// Waveform Minimap (Overview Bar)
///
/// Cubase/Logic style overview bar showing:
/// - Full project waveform overview
/// - Visible region indicator (draggable)
/// - Playhead position
/// - Loop region
/// - Click to navigate

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

class WaveformMinimap extends StatefulWidget {
  /// All clips in the project
  final List<TimelineClip> clips;

  /// Total project duration in seconds
  final double totalDuration;

  /// Current visible region start (scrollOffset)
  final double visibleStart;

  /// Current visible region duration (based on zoom)
  final double visibleDuration;

  /// Current playhead position in seconds
  final double playheadPosition;

  /// Loop region (optional)
  final LoopRegion? loopRegion;

  /// Loop enabled
  final bool loopEnabled;

  /// Height of the minimap
  final double height;

  /// Called when user clicks/drags to navigate
  final ValueChanged<double>? onNavigate;

  /// Called when visible region is dragged
  final void Function(double newStart)? onVisibleRegionDrag;

  const WaveformMinimap({
    super.key,
    required this.clips,
    required this.totalDuration,
    required this.visibleStart,
    required this.visibleDuration,
    required this.playheadPosition,
    this.loopRegion,
    this.loopEnabled = false,
    this.height = 32,
    this.onNavigate,
    this.onVisibleRegionDrag,
  });

  @override
  State<WaveformMinimap> createState() => _WaveformMinimapState();
}

class _WaveformMinimapState extends State<WaveformMinimap> {
  bool _isDraggingRegion = false;
  double _dragStartX = 0;
  double _dragStartOffset = 0;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          border: Border(
            bottom: BorderSide(color: ReelForgeTheme.borderSubtle, width: 1),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width <= 0 || widget.totalDuration <= 0) {
              return const SizedBox.shrink();
            }

            final pixelsPerSecond = width / widget.totalDuration;

            return GestureDetector(
              onTapDown: (details) => _handleTap(details, pixelsPerSecond),
              onPanStart: (details) => _handlePanStart(details, pixelsPerSecond),
              onPanUpdate: (details) => _handlePanUpdate(details, pixelsPerSecond),
              onPanEnd: (_) => _handlePanEnd(),
              child: CustomPaint(
                painter: _MinimapPainter(
                  clips: widget.clips,
                  totalDuration: widget.totalDuration,
                  visibleStart: widget.visibleStart,
                  visibleDuration: widget.visibleDuration,
                  playheadPosition: widget.playheadPosition,
                  loopRegion: widget.loopRegion,
                  loopEnabled: widget.loopEnabled,
                  isDraggingRegion: _isDraggingRegion,
                ),
                size: Size(width, widget.height),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleTap(TapDownDetails details, double pixelsPerSecond) {
    final time = details.localPosition.dx / pixelsPerSecond;
    widget.onNavigate?.call(time.clamp(0, widget.totalDuration));
  }

  void _handlePanStart(DragStartDetails details, double pixelsPerSecond) {
    final x = details.localPosition.dx;
    final regionStartX = widget.visibleStart * pixelsPerSecond;
    final regionEndX = (widget.visibleStart + widget.visibleDuration) * pixelsPerSecond;

    // Check if starting drag inside visible region
    if (x >= regionStartX && x <= regionEndX) {
      setState(() {
        _isDraggingRegion = true;
        _dragStartX = x;
        _dragStartOffset = widget.visibleStart;
      });
    } else {
      // Click outside region - navigate to that position
      final time = x / pixelsPerSecond;
      widget.onNavigate?.call(time.clamp(0, widget.totalDuration));
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, double pixelsPerSecond) {
    if (_isDraggingRegion) {
      final deltaX = details.localPosition.dx - _dragStartX;
      final deltaTime = deltaX / pixelsPerSecond;
      final newStart = (_dragStartOffset + deltaTime)
          .clamp(0.0, widget.totalDuration - widget.visibleDuration);
      widget.onVisibleRegionDrag?.call(newStart);
    } else {
      // Drag navigation
      final time = details.localPosition.dx / pixelsPerSecond;
      widget.onNavigate?.call(time.clamp(0, widget.totalDuration));
    }
  }

  void _handlePanEnd() {
    setState(() {
      _isDraggingRegion = false;
    });
  }
}

class _MinimapPainter extends CustomPainter {
  final List<TimelineClip> clips;
  final double totalDuration;
  final double visibleStart;
  final double visibleDuration;
  final double playheadPosition;
  final LoopRegion? loopRegion;
  final bool loopEnabled;
  final bool isDraggingRegion;

  _MinimapPainter({
    required this.clips,
    required this.totalDuration,
    required this.visibleStart,
    required this.visibleDuration,
    required this.playheadPosition,
    this.loopRegion,
    required this.loopEnabled,
    required this.isDraggingRegion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDuration <= 0) return;

    final pixelsPerSecond = size.width / totalDuration;

    // Draw clip waveforms (simplified)
    _drawClipWaveforms(canvas, size, pixelsPerSecond);

    // Draw loop region
    if (loopRegion != null && loopEnabled) {
      _drawLoopRegion(canvas, size, pixelsPerSecond);
    }

    // Draw visible region indicator
    _drawVisibleRegion(canvas, size, pixelsPerSecond);

    // Draw playhead
    _drawPlayhead(canvas, size, pixelsPerSecond);
  }

  void _drawClipWaveforms(Canvas canvas, Size size, double pixelsPerSecond) {
    for (final clip in clips) {
      final x = clip.startTime * pixelsPerSecond;
      final width = clip.duration * pixelsPerSecond;

      if (x + width < 0 || x > size.width) continue;

      // Clip background
      final clipRect = Rect.fromLTWH(
        x.clamp(0, size.width),
        2,
        width.clamp(0, size.width - x.clamp(0, size.width)),
        size.height - 4,
      );

      final clipColor = clip.color ?? ReelForgeTheme.accentBlue;
      canvas.drawRect(
        clipRect,
        Paint()..color = clipColor.withValues(alpha: 0.4),
      );

      // Draw simplified waveform if available
      if (clip.waveform != null && clip.waveform!.isNotEmpty) {
        _drawSimplifiedWaveform(
          canvas,
          clipRect,
          clip.waveform!,
          clipColor,
        );
      }

      // Clip border
      canvas.drawRect(
        clipRect,
        Paint()
          ..color = clipColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  void _drawSimplifiedWaveform(
    Canvas canvas,
    Rect rect,
    Float32List waveform,
    Color color,
  ) {
    if (rect.width < 2 || waveform.isEmpty) return;

    final centerY = rect.center.dy;
    final amplitude = (rect.height / 2) * 0.8;
    final samplesPerPixel = waveform.length / rect.width;

    final path = Path();
    bool started = false;

    for (double x = 0; x < rect.width; x += 2) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 2) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double maxVal = 0;
      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i].abs();
        if (s > maxVal) maxVal = s;
      }

      final yTop = centerY - maxVal * amplitude;
      final yBottom = centerY + maxVal * amplitude;

      if (!started) {
        path.moveTo(rect.left + x, yTop);
        started = true;
      } else {
        path.lineTo(rect.left + x, yTop);
      }
    }

    // Return path for bottom
    for (double x = rect.width - 2; x >= 0; x -= 2) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 2) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double maxVal = 0;
      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i].abs();
        if (s > maxVal) maxVal = s;
      }

      final yBottom = centerY + maxVal * amplitude;
      path.lineTo(rect.left + x, yBottom);
    }

    path.close();

    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: 0.7),
    );
  }

  void _drawLoopRegion(Canvas canvas, Size size, double pixelsPerSecond) {
    final startX = loopRegion!.start * pixelsPerSecond;
    final endX = loopRegion!.end * pixelsPerSecond;

    // Loop region fill
    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX, size.height),
      Paint()..color = ReelForgeTheme.accentBlue.withValues(alpha: 0.15),
    );

    // Loop region edges
    final edgePaint = Paint()
      ..color = ReelForgeTheme.accentBlue.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), edgePaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), edgePaint);
  }

  void _drawVisibleRegion(Canvas canvas, Size size, double pixelsPerSecond) {
    final startX = visibleStart * pixelsPerSecond;
    final endX = (visibleStart + visibleDuration) * pixelsPerSecond;

    // Darken areas outside visible region
    canvas.drawRect(
      Rect.fromLTRB(0, 0, startX, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawRect(
      Rect.fromLTRB(endX, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Visible region border
    final borderColor = isDraggingRegion
        ? ReelForgeTheme.accentBlue
        : ReelForgeTheme.textSecondary;

    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX, size.height),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDraggingRegion ? 2 : 1,
    );

    // Resize handles (small rectangles at edges)
    final handlePaint = Paint()..color = borderColor;
    final handleHeight = size.height * 0.4;
    final handleY = (size.height - handleHeight) / 2;

    // Left handle
    canvas.drawRect(
      Rect.fromLTWH(startX - 1, handleY, 3, handleHeight),
      handlePaint,
    );
    // Right handle
    canvas.drawRect(
      Rect.fromLTWH(endX - 2, handleY, 3, handleHeight),
      handlePaint,
    );
  }

  void _drawPlayhead(Canvas canvas, Size size, double pixelsPerSecond) {
    final x = playheadPosition * pixelsPerSecond;

    if (x < 0 || x > size.width) return;

    // Playhead line
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = ReelForgeTheme.accentRed
        ..strokeWidth = 1.5,
    );

    // Playhead triangle at top
    final path = Path()
      ..moveTo(x - 4, 0)
      ..lineTo(x + 4, 0)
      ..lineTo(x, 6)
      ..close();
    canvas.drawPath(path, Paint()..color = ReelForgeTheme.accentRed);
  }

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) =>
      clips != oldDelegate.clips ||
      totalDuration != oldDelegate.totalDuration ||
      visibleStart != oldDelegate.visibleStart ||
      visibleDuration != oldDelegate.visibleDuration ||
      playheadPosition != oldDelegate.playheadPosition ||
      loopRegion != oldDelegate.loopRegion ||
      loopEnabled != oldDelegate.loopEnabled ||
      isDraggingRegion != oldDelegate.isDraggingRegion;
}
