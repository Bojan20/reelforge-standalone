// ============================================================================
// FluxForge Studio — Dependency Graph Dialog
// ============================================================================
// P13.8: Visual dependency graph for Feature Builder blocks.
// Shows block nodes with dependency arrows, highlights cycles in red.
// Uses CustomPainter for graph rendering with auto-layout positioning.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/feature_builder/block_category.dart';
import '../../models/feature_builder/block_dependency.dart';
import '../../models/feature_builder/feature_block.dart';
import '../../services/dependency_resolver.dart';
import '../../providers/feature_builder_provider.dart';

/// Shows a visual dependency graph for Feature Builder blocks.
class DependencyGraphDialog extends StatefulWidget {
  final FeatureBuilderProvider provider;

  const DependencyGraphDialog({
    super.key,
    required this.provider,
  });

  /// Show the dialog.
  static Future<void> show(BuildContext context, FeatureBuilderProvider provider) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => DependencyGraphDialog(provider: provider),
    );
  }

  @override
  State<DependencyGraphDialog> createState() => _DependencyGraphDialogState();
}

class _DependencyGraphDialogState extends State<DependencyGraphDialog> {
  late ResolverGraphData _graphData;
  late ResolverResult _resolverResult;
  final Map<String, Offset> _nodePositions = {};
  String? _hoveredNodeId;
  String? _selectedNodeId;
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;

  // Layout constants
  static const double _nodeWidth = 140.0;
  static const double _nodeHeight = 60.0;
  static const double _horizontalSpacing = 180.0;
  static const double _verticalSpacing = 100.0;

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  void _loadGraphData() {
    final blocks = widget.provider.allBlocks
        .whereType<FeatureBlockBase>()
        .toList();
    _graphData = DependencyResolver.instance.getVisualizationData(blocks);
    _resolverResult = DependencyResolver.instance.resolve(blocks);
    _calculateLayout();
  }

  void _calculateLayout() {
    // Group nodes by category for layered layout
    final categoryNodes = <BlockCategory, List<ResolverGraphNode>>{};

    for (final node in _graphData.nodes) {
      categoryNodes.putIfAbsent(node.category, () => []).add(node);
    }

    // Layout order: Core -> Feature -> Presentation -> Bonus
    final categoryOrder = [
      BlockCategory.core,
      BlockCategory.feature,
      BlockCategory.presentation,
      BlockCategory.bonus,
    ];

    double currentX = 50.0;

    for (final category in categoryOrder) {
      final nodes = categoryNodes[category] ?? [];
      if (nodes.isEmpty) continue;

      double currentY = 50.0;
      for (final node in nodes) {
        _nodePositions[node.id] = Offset(currentX, currentY);
        currentY += _verticalSpacing;
      }
      currentX += _horizontalSpacing;
    }
  }

  Set<String> _getCycleNodeIds() {
    final cycleNodes = <String>{};
    for (final cycle in _resolverResult.cycles) {
      cycleNodes.addAll(cycle.path);
    }
    return cycleNodes;
  }

  @override
  Widget build(BuildContext context) {
    final cycleNodeIds = _getCycleNodeIds();
    final hasIssues = _resolverResult.hasIssues;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 900,
        height: 650,
        decoration: BoxDecoration(
          color: const Color(0xFF121218),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF4A9EFF).withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A9EFF).withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(hasIssues, cycleNodeIds),

            // Graph canvas
            Expanded(
              child: _buildGraphCanvas(cycleNodeIds),
            ),

            // Legend and controls
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool hasIssues, Set<String> cycleNodeIds) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A22), Color(0xFF242430)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF4A9EFF), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_tree,
              color: Color(0xFF4A9EFF),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // Title
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEPENDENCY GRAPH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Visual representation of block dependencies',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Status badges
          if (cycleNodeIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4040).withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFF4040)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Color(0xFFFF4040), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${_resolverResult.cycles.length} cycle(s)',
                    style: const TextStyle(
                      color: Color(0xFFFF4040),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hasIssues
                  ? const Color(0xFFFF9040).withOpacity(0.2)
                  : const Color(0xFF40FF90).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasIssues
                    ? const Color(0xFFFF9040)
                    : const Color(0xFF40FF90),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasIssues ? Icons.warning : Icons.check_circle,
                  color: hasIssues
                      ? const Color(0xFFFF9040)
                      : const Color(0xFF40FF90),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  hasIssues
                      ? '${_resolverResult.missingDependencies.length + _resolverResult.conflicts.length} issue(s)'
                      : 'Valid',
                  style: TextStyle(
                    color: hasIssues
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF40FF90),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildGraphCanvas(Set<String> cycleNodeIds) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _panOffset += details.delta;
        });
      },
      onScaleUpdate: (details) {
        setState(() {
          _scale = (_scale * details.scale).clamp(0.5, 2.0);
        });
      },
      child: ClipRect(
        child: Container(
          color: const Color(0xFF0A0A0C),
          child: CustomPaint(
            painter: _DependencyGraphPainter(
              nodes: _graphData.nodes,
              edges: _graphData.edges,
              positions: _nodePositions,
              cycleNodeIds: cycleNodeIds,
              hoveredNodeId: _hoveredNodeId,
              selectedNodeId: _selectedNodeId,
              panOffset: _panOffset,
              scale: _scale,
              nodeWidth: _nodeWidth,
              nodeHeight: _nodeHeight,
            ),
            child: Stack(
              children: [
                // Interactive node overlays
                for (final node in _graphData.nodes)
                  if (_nodePositions.containsKey(node.id))
                    _buildNodeOverlay(node, cycleNodeIds),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeOverlay(ResolverGraphNode node, Set<String> cycleNodeIds) {
    final pos = _nodePositions[node.id]!;
    final scaledPos = Offset(
      pos.dx * _scale + _panOffset.dx,
      pos.dy * _scale + _panOffset.dy,
    );

    return Positioned(
      left: scaledPos.dx,
      top: scaledPos.dy,
      width: _nodeWidth * _scale,
      height: _nodeHeight * _scale,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredNodeId = node.id),
        onExit: (_) => setState(() => _hoveredNodeId = null),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedNodeId = _selectedNodeId == node.id ? null : node.id;
            });
          },
          child: Tooltip(
            message: _buildNodeTooltip(node, cycleNodeIds),
            preferBelow: false,
            child: Container(
              // Transparent hit area
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  String _buildNodeTooltip(ResolverGraphNode node, Set<String> cycleNodeIds) {
    final buffer = StringBuffer();
    buffer.writeln(node.name);
    buffer.writeln('Status: ${node.isEnabled ? "Enabled" : "Disabled"}');
    buffer.writeln('Category: ${node.category.displayName}');

    if (cycleNodeIds.contains(node.id)) {
      buffer.writeln('⚠️ Part of circular dependency');
    }

    // Show dependencies
    final incoming = _graphData.getIncomingEdges(node.id);
    final outgoing = _graphData.getOutgoingEdges(node.id);

    if (outgoing.isNotEmpty) {
      buffer.writeln('\nDepends on:');
      for (final edge in outgoing.where((e) => e.type == DependencyType.requires)) {
        buffer.writeln('  → ${edge.to}');
      }
    }

    if (incoming.isNotEmpty) {
      final dependents = incoming.where((e) => e.type == DependencyType.requires);
      if (dependents.isNotEmpty) {
        buffer.writeln('\nRequired by:');
        for (final edge in dependents) {
          buffer.writeln('  ← ${edge.from}');
        }
      }
    }

    return buffer.toString().trim();
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A22),
        border: Border(
          top: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          // Legend
          _buildLegendItem(const Color(0xFF40FF90), 'Enabled'),
          const SizedBox(width: 16),
          _buildLegendItem(Colors.grey, 'Disabled'),
          const SizedBox(width: 16),
          _buildLegendItem(const Color(0xFFFF4040), 'Cycle'),

          const SizedBox(width: 24),
          Container(width: 1, height: 20, color: Colors.white24),
          const SizedBox(width: 24),

          // Edge legend
          _buildEdgeLegendItem(const Color(0xFF4A9EFF), 'Requires', false),
          const SizedBox(width: 16),
          _buildEdgeLegendItem(const Color(0xFF40FF90), 'Enables', true),
          const SizedBox(width: 16),
          _buildEdgeLegendItem(const Color(0xFFFFD700), 'Modifies', true),
          const SizedBox(width: 16),
          _buildEdgeLegendItem(const Color(0xFFFF4060), 'Conflicts', false),

          const Spacer(),

          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white54, size: 20),
            onPressed: () => setState(() => _scale = (_scale - 0.1).clamp(0.5, 2.0)),
            tooltip: 'Zoom out',
          ),
          Text(
            '${(_scale * 100).toInt()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white54, size: 20),
            onPressed: () => setState(() => _scale = (_scale + 0.1).clamp(0.5, 2.0)),
            tooltip: 'Zoom in',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.center_focus_strong, color: Colors.white54, size: 20),
            onPressed: () => setState(() {
              _panOffset = Offset.zero;
              _scale = 1.0;
            }),
            tooltip: 'Reset view',
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildEdgeLegendItem(Color color, String label, bool dashed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 2,
          child: CustomPaint(
            painter: _EdgeLegendPainter(color: color, dashed: dashed),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

/// CustomPainter for rendering the dependency graph.
class _DependencyGraphPainter extends CustomPainter {
  final List<ResolverGraphNode> nodes;
  final List<ResolverGraphEdge> edges;
  final Map<String, Offset> positions;
  final Set<String> cycleNodeIds;
  final String? hoveredNodeId;
  final String? selectedNodeId;
  final Offset panOffset;
  final double scale;
  final double nodeWidth;
  final double nodeHeight;

  _DependencyGraphPainter({
    required this.nodes,
    required this.edges,
    required this.positions,
    required this.cycleNodeIds,
    required this.hoveredNodeId,
    required this.selectedNodeId,
    required this.panOffset,
    required this.scale,
    required this.nodeWidth,
    required this.nodeHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    // Draw edges first (below nodes)
    _drawEdges(canvas);

    // Draw nodes
    _drawNodes(canvas);

    canvas.restore();
  }

  void _drawEdges(Canvas canvas) {
    for (final edge in edges) {
      final fromPos = positions[edge.from];
      final toPos = positions[edge.to];
      if (fromPos == null || toPos == null) continue;

      final color = _getEdgeColor(edge.type);
      final isDashed = edge.type == DependencyType.enables ||
          edge.type == DependencyType.modifies;

      // Calculate connection points (from right side to left side)
      final startPoint = Offset(
        fromPos.dx + nodeWidth,
        fromPos.dy + nodeHeight / 2,
      );
      final endPoint = Offset(
        toPos.dx,
        toPos.dy + nodeHeight / 2,
      );

      // Check if both nodes are in a cycle
      final isInCycle = cycleNodeIds.contains(edge.from) &&
          cycleNodeIds.contains(edge.to) &&
          edge.type == DependencyType.requires;

      final edgeColor = isInCycle ? const Color(0xFFFF4040) : color;

      _drawArrow(canvas, startPoint, endPoint, edgeColor, isDashed, isInCycle);
    }
  }

  Color _getEdgeColor(DependencyType type) {
    switch (type) {
      case DependencyType.requires:
        return const Color(0xFF4A9EFF);
      case DependencyType.enables:
        return const Color(0xFF40FF90);
      case DependencyType.modifies:
        return const Color(0xFFFFD700);
      case DependencyType.conflicts:
        return const Color(0xFFFF4060);
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    bool dashed,
    bool highlight,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = highlight ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Calculate control points for curved arrow
    final dx = end.dx - start.dx;
    final midX = start.dx + dx / 2;

    if (dashed) {
      // Draw dashed line
      _drawDashedPath(canvas, start, end, midX, paint);
    } else {
      // Draw solid curved line
      path.moveTo(start.dx, start.dy);
      path.cubicTo(
        midX, start.dy,
        midX, end.dy,
        end.dx, end.dy,
      );
      canvas.drawPath(path, paint);
    }

    // Draw arrowhead
    _drawArrowhead(canvas, end, color, highlight);
  }

  void _drawDashedPath(Canvas canvas, Offset start, Offset end, double midX, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 3.0;

    // Approximate the curve with line segments
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final dashPath = metric.extractPath(
          distance,
          math.min(distance + dashLength, metric.length),
        );
        canvas.drawPath(dashPath, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset tip, Color color, bool highlight) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowSize = 8.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - arrowSize, tip.dy - arrowSize / 2)
      ..lineTo(tip.dx - arrowSize, tip.dy + arrowSize / 2)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawNodes(Canvas canvas) {
    for (final node in nodes) {
      final pos = positions[node.id];
      if (pos == null) continue;

      final rect = Rect.fromLTWH(pos.dx, pos.dy, nodeWidth, nodeHeight);
      final isHovered = node.id == hoveredNodeId;
      final isSelected = node.id == selectedNodeId;
      final isInCycle = cycleNodeIds.contains(node.id);

      // Determine node color
      Color borderColor;
      Color fillColor;

      if (isInCycle) {
        borderColor = const Color(0xFFFF4040);
        fillColor = const Color(0xFFFF4040).withOpacity(0.15);
      } else if (node.isEnabled) {
        borderColor = Color(node.category.colorValue);
        fillColor = Color(node.category.colorValue).withOpacity(0.15);
      } else {
        borderColor = Colors.grey;
        fillColor = Colors.grey.withOpacity(0.1);
      }

      // Draw shadow for hovered/selected
      if (isHovered || isSelected) {
        final shadowPaint = Paint()
          ..color = borderColor.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(8)),
          shadowPaint,
        );
      }

      // Draw node background
      final bgPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        bgPaint,
      );

      // Draw node border
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : (isHovered ? 2.0 : 1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        borderPaint,
      );

      // Draw node text
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.name,
          style: TextStyle(
            color: node.isEnabled ? Colors.white : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        textAlign: TextAlign.center,
      );
      textPainter.layout(maxWidth: nodeWidth - 16);
      textPainter.paint(
        canvas,
        Offset(
          pos.dx + (nodeWidth - textPainter.width) / 2,
          pos.dy + (nodeHeight - textPainter.height) / 2,
        ),
      );

      // Draw status indicator
      if (isInCycle) {
        _drawStatusIcon(canvas, pos, const Color(0xFFFF4040), Icons.error);
      } else if (!node.isEnabled) {
        _drawStatusIcon(canvas, pos, Colors.grey, Icons.visibility_off);
      }
    }
  }

  void _drawStatusIcon(Canvas canvas, Offset nodePos, Color color, IconData icon) {
    // Draw a small indicator in the top-right corner
    final iconPos = Offset(nodePos.dx + nodeWidth - 16, nodePos.dy + 4);
    final iconPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(iconPos.translate(6, 6), 8, iconPaint);
  }

  @override
  bool shouldRepaint(covariant _DependencyGraphPainter oldDelegate) {
    return oldDelegate.hoveredNodeId != hoveredNodeId ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.scale != scale;
  }
}

/// Small painter for edge legend items.
class _EdgeLegendPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  _EdgeLegendPainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (dashed) {
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset(math.min(x + 4, size.width), size.height / 2),
          paint,
        );
        x += 6;
      }
    } else {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }

    // Small arrowhead
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width, size.height / 2)
      ..lineTo(size.width - 4, 0)
      ..lineTo(size.width - 4, size.height)
      ..close();
    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
