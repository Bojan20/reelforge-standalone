// audio_graph_painter.dart — GPU-Accelerated Graph Rendering
// Part of P10.1.7 — CustomPainter with advanced visual effects

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/audio_graph_models.dart';

/// Custom painter for audio graph visualization
/// Uses GPU-accelerated Canvas operations for 120fps rendering
class AudioGraphPainter extends CustomPainter {
  final AudioGraphState graphState;
  final Map<String, int> pdcMap;  // Node ID → total PDC in samples
  final bool showPDCIndicators;
  final bool showMeters;

  AudioGraphPainter({
    required this.graphState,
    required this.pdcMap,
    this.showPDCIndicators = true,
    this.showMeters = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Apply zoom and pan transform
    canvas.save();
    canvas.translate(graphState.panOffset.dx, graphState.panOffset.dy);
    canvas.scale(graphState.zoomLevel);

    // Draw in order: grid → edges → nodes → PDC indicators
    _drawGrid(canvas, size);
    _drawEdges(canvas);
    _drawNodes(canvas);
    if (showPDCIndicators) {
      _drawPDCIndicators(canvas);
    }

    canvas.restore();
  }

  /// Draw background grid
  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const gridSpacing = 50.0;
    final gridWidth = size.width / graphState.zoomLevel + graphState.panOffset.dx.abs() / graphState.zoomLevel;
    final gridHeight = size.height / graphState.zoomLevel + graphState.panOffset.dy.abs() / graphState.zoomLevel;

    // Vertical lines
    for (double x = 0; x < gridWidth; x += gridSpacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, gridHeight),
        gridPaint,
      );
    }

    // Horizontal lines
    for (double y = 0; y < gridHeight; y += gridSpacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(gridWidth, y),
        gridPaint,
      );
    }
  }

  /// Draw all edges with Bezier curves
  void _drawEdges(Canvas canvas) {
    for (final edge in graphState.edges) {
      final sourceNode = graphState.findNode(edge.sourceNodeId);
      final targetNode = graphState.findNode(edge.targetNodeId);

      if (sourceNode == null || targetNode == null) continue;

      _drawEdge(canvas, edge, sourceNode, targetNode);
    }
  }

  /// Draw single edge with smooth Bezier curve
  void _drawEdge(
    Canvas canvas,
    AudioGraphEdge edge,
    AudioGraphNode source,
    AudioGraphNode target,
  ) {
    // Calculate connection points (right side of source, left side of target)
    final sourcePoint = source.position + Offset(source.size.width, source.size.height / 2);
    final targetPoint = target.position + Offset(0, target.size.height / 2);

    // Control points for smooth curve
    final distance = (targetPoint - sourcePoint).dx;
    final curvature = math.min(distance / 3, 100.0);

    final cp1 = sourcePoint + Offset(curvature, 0);
    final cp2 = targetPoint - Offset(curvature, 0);

    // Draw path
    final path = Path()
      ..moveTo(sourcePoint.dx, sourcePoint.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, targetPoint.dx, targetPoint.dy);

    // Edge paint with glow effect
    final edgePaint = Paint()
      ..color = edge.color.withOpacity(edge.isSelected ? 1.0 : 0.7)
      ..strokeWidth = edge.isSelected ? 3.0 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow layer for selected edges
    if (edge.isSelected || edge.isHighlighted) {
      final glowPaint = Paint()
        ..color = edge.color.withOpacity(0.3)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      canvas.drawPath(path, glowPaint);
    }

    canvas.drawPath(path, edgePaint);

    // Draw arrow head at target
    _drawArrowHead(canvas, cp2, targetPoint, edge.color);

    // Draw gain label for non-unity gains
    if ((edge.gain - 1.0).abs() > 0.01) {
      _drawEdgeLabel(canvas, sourcePoint, targetPoint, edge.gainDb);
    }
  }

  /// Draw arrow head at edge target
  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    const arrowSize = 8.0;
    final direction = (to - from) / (to - from).distance;
    final perpendicular = Offset(-direction.dy, direction.dx);

    final tip = to;
    final left = to - direction * arrowSize + perpendicular * (arrowSize / 2);
    final right = to - direction * arrowSize - perpendicular * (arrowSize / 2);

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, arrowPaint);
  }

  /// Draw gain label on edge
  void _drawEdgeLabel(Canvas canvas, Offset start, Offset end, double gainDb) {
    final midPoint = (start + end) / 2;
    final text = '${gainDb.toStringAsFixed(1)} dB';

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Background rectangle
    final bgRect = Rect.fromCenter(
      center: midPoint,
      width: textPainter.width + 8,
      height: textPainter.height + 4,
    );

    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      bgPaint,
    );

    // Draw text
    textPainter.paint(canvas, midPoint - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  /// Draw all nodes
  void _drawNodes(Canvas canvas) {
    for (final node in graphState.nodes) {
      _drawNode(canvas, node);
    }
  }

  /// Draw single node with rounded rectangle and effects
  void _drawNode(Canvas canvas, AudioGraphNode node) {
    final rect = Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      node.size.width,
      node.size.height,
    );

    // Shadow for depth
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(const Offset(0, 2)), const Radius.circular(8)),
      shadowPaint,
    );

    // Node background with gradient
    final gradient = ui.Gradient.linear(
      rect.topCenter,
      rect.bottomCenter,
      [
        node.color.withOpacity(0.9),
        node.color.withOpacity(0.7),
      ],
    );

    final nodePaint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      nodePaint,
    );

    // Border (thicker if selected)
    final borderPaint = Paint()
      ..color = node.isSelected ? Colors.white : node.color.withOpacity(0.5)
      ..strokeWidth = node.isSelected ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      borderPaint,
    );

    // Glow effect for selected nodes
    if (node.isSelected) {
      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        glowPaint,
      );
    }

    // Node label
    _drawNodeLabel(canvas, node, rect);

    // Status badges (mute, solo, bypass)
    _drawNodeBadges(canvas, node, rect);

    // Meter overlay
    if (showMeters && node.outputLevel != null) {
      _drawNodeMeters(canvas, node, rect);
    }
  }

  /// Draw node label text
  void _drawNodeLabel(Canvas canvas, AudioGraphNode node, Rect rect) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: rect.width - 16);

    final textOffset = Offset(
      rect.center.dx - textPainter.width / 2,
      rect.center.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, textOffset);
  }

  /// Draw status badges (M/S/B indicators)
  void _drawNodeBadges(Canvas canvas, AudioGraphNode node, Rect rect) {
    final badges = <String>[];
    if (node.isMuted) badges.add('M');
    if (node.isSoloed) badges.add('S');
    if (node.isBypassed) badges.add('B');

    if (badges.isEmpty) return;

    const badgeSize = 14.0;
    const badgeSpacing = 16.0;
    final startX = rect.right - (badges.length * badgeSpacing) - 4;
    final y = rect.top + 4;

    for (int i = 0; i < badges.length; i++) {
      final x = startX + i * badgeSpacing;
      final badgeRect = Rect.fromLTWH(x, y, badgeSize, badgeSize);

      // Badge background
      final bgPaint = Paint()
        ..color = Colors.red.withOpacity(0.8)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
        bgPaint,
      );

      // Badge text
      final textPainter = TextPainter(
        text: TextSpan(
          text: badges[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        badgeRect.center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  /// Draw level meters on node
  void _drawNodeMeters(Canvas canvas, AudioGraphNode node, Rect rect) {
    final meterHeight = 4.0;
    final meterRect = Rect.fromLTWH(
      rect.left + 8,
      rect.bottom - meterHeight - 8,
      rect.width - 16,
      meterHeight,
    );

    // Background
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(meterRect, const Radius.circular(2)),
      bgPaint,
    );

    // Level bar
    if (node.outputLevel != null && node.outputLevel! > 0.001) {
      final level = node.outputLevel!.clamp(0.0, 1.0);
      final levelWidth = meterRect.width * level;

      final levelColor = _getLevelColor(level);
      final levelPaint = Paint()
        ..shader = ui.Gradient.linear(
          meterRect.centerLeft,
          meterRect.centerRight,
          [levelColor.withOpacity(0.8), levelColor],
        )
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(meterRect.left, meterRect.top, levelWidth, meterRect.height),
          const Radius.circular(2),
        ),
        levelPaint,
      );
    }
  }

  /// Get meter color based on level (green → yellow → red)
  Color _getLevelColor(double level) {
    if (level < 0.7) return const Color(0xFF40FF90);  // Green
    if (level < 0.9) return const Color(0xFFFFFF40);  // Yellow
    return const Color(0xFFFF4060);  // Red
  }

  /// Draw PDC indicators on edges
  void _drawPDCIndicators(Canvas canvas) {
    for (final edge in graphState.edges) {
      final sourceNode = graphState.findNode(edge.sourceNodeId);
      final targetNode = graphState.findNode(edge.targetNodeId);

      if (sourceNode == null || targetNode == null) continue;

      final sourcePdc = pdcMap[sourceNode.id] ?? 0;
      final targetPdc = pdcMap[targetNode.id] ?? 0;
      final pdcDelta = targetPdc - sourcePdc;

      if (pdcDelta > 100) {  // Only show if >2ms @ 48kHz
        final midPoint = (sourceNode.position + targetNode.position) / 2;
        final pdcMs = pdcDelta / 48.0;

        _drawPDCBadge(canvas, midPoint, pdcMs);
      }
    }
  }

  /// Draw PDC badge showing delay in ms
  void _drawPDCBadge(Canvas canvas, Offset position, double delayMs) {
    final text = '${delayMs.toStringAsFixed(1)}ms';

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final badgeRect = Rect.fromCenter(
      center: position,
      width: textPainter.width + 12,
      height: textPainter.height + 6,
    );

    // Badge background (orange for delay)
    final bgPaint = Paint()
      ..color = const Color(0xFFFF9040)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
      bgPaint,
    );

    // Border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
      borderPaint,
    );

    // Text
    textPainter.paint(
      canvas,
      position - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(AudioGraphPainter oldDelegate) {
    return graphState != oldDelegate.graphState ||
        pdcMap != oldDelegate.pdcMap ||
        showPDCIndicators != oldDelegate.showPDCIndicators ||
        showMeters != oldDelegate.showMeters;
  }
}
