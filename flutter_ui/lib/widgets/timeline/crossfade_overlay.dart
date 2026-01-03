/// Crossfade Overlay Widget
///
/// Visual representation of crossfade between clips with:
/// - X-pattern fade curves (linear, equal-power, S-curve)
/// - Resize handles
/// - Double-click to delete

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

class CrossfadeOverlay extends StatefulWidget {
  final Crossfade crossfade;
  final double zoom;
  final double scrollOffset;
  final double height;
  final ValueChanged<double>? onUpdate;
  final VoidCallback? onDelete;

  const CrossfadeOverlay({
    super.key,
    required this.crossfade,
    required this.zoom,
    required this.scrollOffset,
    required this.height,
    this.onUpdate,
    this.onDelete,
  });

  @override
  State<CrossfadeOverlay> createState() => _CrossfadeOverlayState();
}

class _CrossfadeOverlayState extends State<CrossfadeOverlay> {
  bool _isDragging = false;
  String? _dragEdge;
  double _startDuration = 0;
  double _startX = 0;

  @override
  Widget build(BuildContext context) {
    final left = (widget.crossfade.startTime - widget.scrollOffset) * widget.zoom;
    final width = widget.crossfade.duration * widget.zoom;

    // Don't render if not visible
    if (left + width < 0 || left > 2000) return const SizedBox.shrink();

    return Positioned(
      left: left,
      top: 2,
      width: width.clamp(4, double.infinity),
      height: widget.height - 4,
      child: GestureDetector(
        onDoubleTap: widget.onDelete,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: ReelForgeTheme.accentPurple.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            children: [
              // Crossfade visualization
              Positioned.fill(
                child: CustomPaint(
                  painter: _CrossfadePainter(
                    curveType: widget.crossfade.curveType,
                  ),
                ),
              ),

              // Left resize handle
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragStart: (details) {
                      _startX = details.globalPosition.dx;
                      _startDuration = widget.crossfade.duration;
                      setState(() {
                        _isDragging = true;
                        _dragEdge = 'left';
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_dragEdge == 'left') {
                        final deltaX = details.globalPosition.dx - _startX;
                        final deltaTime = -deltaX / widget.zoom;
                        final newDuration =
                            (_startDuration + deltaTime).clamp(0.1, double.infinity);
                        widget.onUpdate?.call(newDuration);
                      }
                    },
                    onHorizontalDragEnd: (_) {
                      setState(() {
                        _isDragging = false;
                        _dragEdge = null;
                      });
                    },
                    child: Container(
                      color: _isDragging && _dragEdge == 'left'
                          ? ReelForgeTheme.accentPurple.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),

              // Right resize handle
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragStart: (details) {
                      _startX = details.globalPosition.dx;
                      _startDuration = widget.crossfade.duration;
                      setState(() {
                        _isDragging = true;
                        _dragEdge = 'right';
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_dragEdge == 'right') {
                        final deltaX = details.globalPosition.dx - _startX;
                        final deltaTime = deltaX / widget.zoom;
                        final newDuration =
                            (_startDuration + deltaTime).clamp(0.1, double.infinity);
                        widget.onUpdate?.call(newDuration);
                      }
                    },
                    onHorizontalDragEnd: (_) {
                      setState(() {
                        _isDragging = false;
                        _dragEdge = null;
                      });
                    },
                    child: Container(
                      color: _isDragging && _dragEdge == 'right'
                          ? ReelForgeTheme.accentPurple.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrossfadePainter extends CustomPainter {
  final CrossfadeCurve curveType;

  _CrossfadePainter({required this.curveType});

  @override
  void paint(Canvas canvas, Size size) {
    final fadeOutPaint = Paint()
      ..color = const Color(0xCCFF6464)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final fadeInPaint = Paint()
      ..color = const Color(0xCC64FF64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Fade out curve (first clip)
    final fadeOutPath = Path();
    switch (curveType) {
      case CrossfadeCurve.linear:
        fadeOutPath.moveTo(0, size.height * 0.1);
        fadeOutPath.lineTo(size.width, size.height * 0.9);
        break;
      case CrossfadeCurve.equalPower:
        fadeOutPath.moveTo(0, size.height * 0.1);
        fadeOutPath.quadraticBezierTo(
          size.width * 0.5,
          size.height * 0.1,
          size.width,
          size.height * 0.9,
        );
        break;
      case CrossfadeCurve.sCurve:
        fadeOutPath.moveTo(0, size.height * 0.1);
        fadeOutPath.cubicTo(
          size.width * 0.3,
          size.height * 0.1,
          size.width * 0.7,
          size.height * 0.9,
          size.width,
          size.height * 0.9,
        );
        break;
    }
    canvas.drawPath(fadeOutPath, fadeOutPaint);

    // Fade in curve (second clip)
    final fadeInPath = Path();
    switch (curveType) {
      case CrossfadeCurve.linear:
        fadeInPath.moveTo(0, size.height * 0.9);
        fadeInPath.lineTo(size.width, size.height * 0.1);
        break;
      case CrossfadeCurve.equalPower:
        fadeInPath.moveTo(0, size.height * 0.9);
        fadeInPath.quadraticBezierTo(
          size.width * 0.5,
          size.height * 0.9,
          size.width,
          size.height * 0.1,
        );
        break;
      case CrossfadeCurve.sCurve:
        fadeInPath.moveTo(0, size.height * 0.9);
        fadeInPath.cubicTo(
          size.width * 0.3,
          size.height * 0.9,
          size.width * 0.7,
          size.height * 0.1,
          size.width,
          size.height * 0.1,
        );
        break;
    }
    canvas.drawPath(fadeInPath, fadeInPaint);
  }

  @override
  bool shouldRepaint(_CrossfadePainter oldDelegate) =>
      curveType != oldDelegate.curveType;
}
