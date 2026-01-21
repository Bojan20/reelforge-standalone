/// Timeline Grid Overlay Widget
///
/// Draws vertical grid lines on the timeline when snap-to-grid is enabled.
/// Grid interval is controlled by TimelineDragController.

import 'package:flutter/material.dart';
import '../../controllers/slot_lab/timeline_drag_controller.dart';

/// Paints vertical grid lines at regular intervals
class TimelineGridOverlay extends StatelessWidget {
  /// Pixels per second (zoom level)
  final double pixelsPerSecond;

  /// Total duration in seconds to draw grid for
  final double durationSeconds;

  /// The drag controller (for snap state and interval)
  final TimelineDragController dragController;

  /// Height of the grid area
  final double height;

  const TimelineGridOverlay({
    super.key,
    required this.pixelsPerSecond,
    required this.durationSeconds,
    required this.dragController,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dragController,
      builder: (context, _) {
        if (!dragController.snapEnabled) {
          return const SizedBox.shrink();
        }

        return CustomPaint(
          size: Size(durationSeconds * pixelsPerSecond, height),
          painter: _GridPainter(
            pixelsPerSecond: pixelsPerSecond,
            durationSeconds: durationSeconds,
            gridInterval: dragController.gridInterval,
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double durationSeconds;
  final GridInterval gridInterval;

  _GridPainter({
    required this.pixelsPerSecond,
    required this.durationSeconds,
    required this.gridInterval,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final intervalSeconds = gridInterval.seconds;
    final intervalPixels = intervalSeconds * pixelsPerSecond;

    // Skip if interval too small to draw (< 4 pixels)
    if (intervalPixels < 4) return;

    final majorPaint = Paint()
      ..color = Colors.white.withAlpha(40)
      ..strokeWidth = 1.0;

    final minorPaint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..strokeWidth = 0.5;

    // Calculate how many grid lines to draw
    final lineCount = (durationSeconds / intervalSeconds).ceil() + 1;

    for (int i = 0; i < lineCount; i++) {
      final x = i * intervalPixels;
      if (x > size.width) break;

      // Every 10th line is major (bolder)
      final isMajor = i % 10 == 0;
      final paint = isMajor ? majorPaint : minorPaint;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        durationSeconds != oldDelegate.durationSeconds ||
        gridInterval != oldDelegate.gridInterval;
  }
}
