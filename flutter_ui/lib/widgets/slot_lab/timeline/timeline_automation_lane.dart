// Timeline Automation Lane — Parameter Automation Editing
//
// Interactive automation curve editing:
// - Click to add points
// - Drag to adjust values
// - Bezier interpolation
// - Volume/Pan/RTPC support

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../models/timeline/automation_lane.dart';

class TimelineAutomationLane extends StatefulWidget {
  final AutomationLane lane;
  final double duration;
  final double zoom;
  final double canvasWidth;
  final Function(AutomationPoint point)? onPointAdded;
  final Function(String pointId, double time, double value)? onPointMoved;
  final Function(String pointId)? onPointDeleted;

  const TimelineAutomationLane({
    super.key,
    required this.lane,
    required this.duration,
    required this.zoom,
    required this.canvasWidth,
    this.onPointAdded,
    this.onPointMoved,
    this.onPointDeleted,
  });

  @override
  State<TimelineAutomationLane> createState() => _TimelineAutomationLaneState();
}

class _TimelineAutomationLaneState extends State<TimelineAutomationLane> {
  String? _draggingPointId;
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C).withOpacity(0.5),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: MouseRegion(
        onHover: (event) {
          setState(() {
            _hoverPosition = event.localPosition;
          });
        },
        onExit: (_) {
          setState(() {
            _hoverPosition = null;
          });
        },
        child: GestureDetector(
          onTapDown: (details) => _handleTap(details.localPosition),
          child: CustomPaint(
            size: Size(widget.canvasWidth, 60),
            painter: _AutomationCurvePainter(
              lane: widget.lane,
              duration: widget.duration,
              hoverPosition: _hoverPosition,
            ),
            child: Stack(
              children: widget.lane.points.map((point) {
                return _buildAutomationPoint(point);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Handle tap to add automation point
  void _handleTap(Offset position) {
    final time = (position.dx / widget.canvasWidth) * widget.duration;
    final normalizedValue = 1.0 - (position.dy / 60.0);

    final point = AutomationPoint(
      id: 'point_${DateTime.now().millisecondsSinceEpoch}',
      time: time.clamp(0.0, widget.duration),
      value: normalizedValue.clamp(0.0, 1.0),
    );

    widget.onPointAdded?.call(point);
  }

  /// Build draggable automation point
  Widget _buildAutomationPoint(AutomationPoint point) {
    final x = (point.time / widget.duration) * widget.canvasWidth;
    final y = (1.0 - point.value) * 60;

    return Positioned(
      left: x - 4,
      top: y - 4,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() {
            _draggingPointId = point.id;
          });
        },
        onPanUpdate: (details) {
          if (_draggingPointId == point.id) {
            final newX = (x + details.delta.dx).clamp(0.0, widget.canvasWidth);
            final newY = (y + details.delta.dy).clamp(0.0, 60.0);

            final newTime = (newX / widget.canvasWidth) * widget.duration;
            final newValue = 1.0 - (newY / 60.0);

            widget.onPointMoved?.call(point.id, newTime, newValue.clamp(0.0, 1.0));
          }
        },
        onPanEnd: (_) {
          setState(() {
            _draggingPointId = null;
          });
        },
        onSecondaryTapDown: (_) {
          // Right-click to delete
          widget.onPointDeleted?.call(point.id);
        },
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _draggingPointId == point.id
                ? const Color(0xFFFF9040)
                : widget.lane.curveColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(
                color: widget.lane.curveColor.withOpacity(0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Automation curve painter
class _AutomationCurvePainter extends CustomPainter {
  final AutomationLane lane;
  final double duration;
  final Offset? hoverPosition;

  const _AutomationCurvePainter({
    required this.lane,
    required this.duration,
    this.hoverPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw center line (zero/default value)
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );

    // Draw automation curve
    if (lane.points.isEmpty) return;

    final curvePaint = Paint()
      ..color = lane.curveColor.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Sort points by time
    final sortedPoints = List<AutomationPoint>.from(lane.points)
      ..sort((a, b) => a.time.compareTo(b.time));

    // Draw interpolated curve
    for (int x = 0; x < size.width.toInt(); x++) {
      final time = (x / size.width) * duration;
      final normalizedValue = _getInterpolatedValue(time, sortedPoints);
      final y = (1.0 - normalizedValue) * size.height;

      if (x == 0) {
        path.moveTo(x.toDouble(), y);
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    canvas.drawPath(path, curvePaint);

    // Draw hover crosshair
    if (hoverPosition != null) {
      _drawHoverCrosshair(canvas, size);
    }
  }

  /// Get interpolated value at time
  double _getInterpolatedValue(double time, List<AutomationPoint> sortedPoints) {
    if (sortedPoints.isEmpty) return 0.5;
    if (sortedPoints.length == 1) return sortedPoints[0].value;

    // Find surrounding points
    AutomationPoint? before;
    AutomationPoint? after;

    for (int i = 0; i < sortedPoints.length; i++) {
      if (sortedPoints[i].time <= time) before = sortedPoints[i];
      if (sortedPoints[i].time >= time && after == null) {
        after = sortedPoints[i];
        break;
      }
    }

    if (before == null) return sortedPoints.first.value;
    if (after == null) return sortedPoints.last.value;
    if (before.time == after.time) return before.value;

    // Interpolate
    final t = (time - before.time) / (after.time - before.time);
    return _interpolate(before, after, t);
  }

  /// Interpolate between two points
  double _interpolate(AutomationPoint a, AutomationPoint b, double t) {
    switch (a.interpolation) {
      case CurveType.step:
        return a.value;
      case CurveType.linear:
        return a.value + (b.value - a.value) * t;
      case CurveType.bezier:
        final cp = (a.value + b.value) / 2;
        final u = 1 - t;
        return u * u * a.value + 2 * u * t * cp + t * t * b.value;
      case CurveType.exponential:
        return a.value + (b.value - a.value) * (t * t);
      case CurveType.logarithmic:
        return a.value + (b.value - a.value) * math.sqrt(t);
    }
  }

  /// Draw hover crosshair
  void _drawHoverCrosshair(Canvas canvas, Size size) {
    if (hoverPosition == null) return;

    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1.0;

    // Vertical line
    canvas.drawLine(
      Offset(hoverPosition!.dx, 0),
      Offset(hoverPosition!.dx, size.height),
      paint,
    );

    // Horizontal line
    canvas.drawLine(
      Offset(0, hoverPosition!.dy),
      Offset(size.width, hoverPosition!.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(_AutomationCurvePainter oldDelegate) {
    return oldDelegate.lane != lane ||
        oldDelegate.duration != duration ||
        oldDelegate.hoverPosition != hoverPosition;
  }
}
