// Timeline Grid Painter — Precision Grid Rendering
//
// Renders beat/millisecond/frame grid lines with auto-density adjustment.
// Grid density increases with zoom for better precision.

import 'package:flutter/material.dart';
import '../../../models/timeline/timeline_state.dart';

/// Grid line definition
class GridLine {
  final double position;      // 0.0-1.0 (normalized timeline position)
  final bool isMajor;        // Major tick (thicker, labeled)
  final String? label;       // Time label

  const GridLine({
    required this.position,
    required this.isMajor,
    this.label,
  });
}

/// Timeline grid painter with pre-allocated paints
class TimelineGridPainter extends CustomPainter {
  final double zoom;
  final double duration;
  final GridMode gridMode;
  final int millisecondInterval;
  final int frameRate;
  final bool snapEnabled;

  // Pre-allocated paints
  late final Paint _majorPaint;
  late final Paint _minorPaint;

  // Cached grid lines
  late final List<GridLine> _gridLines;

  TimelineGridPainter({
    required this.zoom,
    required this.duration,
    this.gridMode = GridMode.millisecond,
    this.millisecondInterval = 100,
    this.frameRate = 60,
    this.snapEnabled = false,
  }) {
    final baseOpacity = snapEnabled ? 0.20 : 0.10;

    _majorPaint = Paint()
      ..color = Colors.white.withOpacity(baseOpacity)
      ..strokeWidth = 1.0;

    _minorPaint = Paint()
      ..color = Colors.white.withOpacity(baseOpacity * 0.5)
      ..strokeWidth = 0.5;

    _gridLines = _generateGridLines();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in _gridLines) {
      final x = line.position * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        line.isMajor ? _majorPaint : _minorPaint,
      );
    }
  }

  /// Generate grid lines based on mode
  List<GridLine> _generateGridLines() {
    switch (gridMode) {
      case GridMode.millisecond:
        return _generateMillisecondGrid();
      case GridMode.frame:
        return _generateFrameGrid();
      case GridMode.beat:
        return _generateBeatGrid();
      case GridMode.free:
        return const [];
    }
  }

  /// Millisecond grid (10ms, 50ms, 100ms, 250ms, 500ms)
  List<GridLine> _generateMillisecondGrid() {
    final lines = <GridLine>[];
    final intervalSeconds = millisecondInterval / 1000.0;

    int majorEvery = 10;
    if (zoom < 0.5) {
      majorEvery = 20;
    } else if (zoom > 4.0) {
      majorEvery = 5;
    }

    int lineIndex = 0;
    for (double time = 0; time <= duration; time += intervalSeconds) {
      final isMajor = lineIndex % majorEvery == 0;
      final position = time / duration;

      lines.add(GridLine(
        position: position,
        isMajor: isMajor,
        label: isMajor ? '${(time * 1000).toInt()}ms' : null,
      ));

      lineIndex++;
    }

    return lines;
  }

  /// Frame grid (24fps, 30fps, 60fps)
  List<GridLine> _generateFrameGrid() {
    final lines = <GridLine>[];
    final frameSeconds = 1.0 / frameRate;
    final framesPerSecond = frameRate;

    int frameIndex = 0;
    for (double time = 0; time <= duration; time += frameSeconds) {
      final isMajor = frameIndex % framesPerSecond == 0;
      final position = time / duration;

      lines.add(GridLine(
        position: position,
        isMajor: isMajor,
        label: isMajor ? '${(time).toStringAsFixed(1)}s' : null,
      ));

      frameIndex++;
    }

    return lines;
  }

  /// Beat grid (requires tempo — placeholder)
  List<GridLine> _generateBeatGrid() {
    final lines = <GridLine>[];
    const tempo = 120.0;
    final beatSeconds = 60.0 / tempo;

    int beatIndex = 0;
    for (double time = 0; time <= duration; time += beatSeconds) {
      final isMajor = beatIndex % 4 == 0;
      final position = time / duration;

      lines.add(GridLine(
        position: position,
        isMajor: isMajor,
        label: isMajor ? '${(beatIndex ~/ 4) + 1}.1.1' : null,
      ));

      beatIndex++;
    }

    return lines;
  }

  @override
  bool shouldRepaint(TimelineGridPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.duration != duration ||
        oldDelegate.gridMode != gridMode ||
        oldDelegate.millisecondInterval != millisecondInterval ||
        oldDelegate.frameRate != frameRate ||
        oldDelegate.snapEnabled != snapEnabled;
  }
}
