/// Event Dependency Graph Panel
///
/// Interactive visualization of event dependencies:
/// - Node-based graph showing event relationships
/// - RED highlighting for circular dependencies
/// - Zoom/pan canvas
/// - Click nodes to select/highlight
/// - Export graph to JSON
///
/// Uses DFS cycle detection from EventDependencyAnalyzer
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/fluxforge_theme.dart';
import '../../services/event_dependency_analyzer.dart';
import '../../models/slot_audio_events.dart';

/// Event Dependency Graph Panel widget
class EventDependencyGraphPanel extends StatefulWidget {
  final List<SlotCompositeEvent> events;
  final double width;
  final double height;

  const EventDependencyGraphPanel({
    super.key,
    required this.events,
    this.width = 800,
    this.height = 600,
  });

  @override
  State<EventDependencyGraphPanel> createState() => _EventDependencyGraphPanelState();
}

class _EventDependencyGraphPanelState extends State<EventDependencyGraphPanel> {
  late CycleDetectionResult _analysisResult;
  final Map<String, Offset> _nodePositions = {};
  String? _selectedNodeId;
  Offset _canvasOffset = Offset.zero;
  double _zoomLevel = 1.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  @override
  void didUpdateWidget(EventDependencyGraphPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != oldWidget.events) {
      _runAnalysis();
    }
  }

  void _runAnalysis() {
    setState(() => _isLoading = true);

    // Run dependency analysis
    _analysisResult = EventDependencyAnalyzer.analyze(
      events: widget.events,
    );

    // Calculate node positions (force-directed layout)
    _calculateNodePositions();

    setState(() => _isLoading = false);
  }

  void _calculateNodePositions() {
    _nodePositions.clear();

    if (widget.events.isEmpty) return;

    // Simple circular layout
    final center = Offset(widget.width / 2, widget.height / 2);
    final radius = math.min(widget.width, widget.height) / 3;
    final angleStep = (2 * math.pi) / widget.events.length;

    for (int i = 0; i < widget.events.length; i++) {
      final angle = i * angleStep;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      _nodePositions[widget.events[i].id] = Offset(x, y);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: FluxForgeTheme.accentBlue,
        ),
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluxForgeTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header with stats and controls
          _buildHeader(),

          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),

          // Graph canvas
          Expanded(
            child: Stack(
              children: [
                // Background grid
                CustomPaint(
                  size: Size(widget.width, widget.height),
                  painter: _GridPainter(),
                ),

                // Graph rendering
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _canvasOffset += details.delta / _zoomLevel;
                    });
                  },
                  child: CustomPaint(
                    size: Size(widget.width, widget.height),
                    painter: _GraphPainter(
                      nodePositions: _nodePositions,
                      events: widget.events,
                      dependencies: _analysisResult.allDependencies,
                      cycles: _analysisResult.cycles,
                      selectedNodeId: _selectedNodeId,
                      canvasOffset: _canvasOffset,
                      zoomLevel: _zoomLevel,
                    ),
                  ),
                ),

                // Nodes (interactive)
                ..._buildInteractiveNodes(),
              ],
            ),
          ),

          // Footer with legend and actions
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final cycleCount = _analysisResult.cycles.length;
    final hasCycles = _analysisResult.hasCycle;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.account_tree,
            size: 18,
            color: hasCycles ? FluxForgeTheme.errorRed : FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Text(
            'Event Dependency Graph',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),

          // Cycle warning
          if (hasCycles)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.errorRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: FluxForgeTheme.errorRed,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_rounded,
                    size: 16,
                    color: FluxForgeTheme.errorRed,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$cycleCount CYCLE${cycleCount > 1 ? 'S' : ''} DETECTED',
                    style: TextStyle(
                      color: FluxForgeTheme.errorRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.successGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: FluxForgeTheme.successGreen,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: FluxForgeTheme.successGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'NO CYCLES',
                    style: TextStyle(
                      color: FluxForgeTheme.successGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(width: 12),

          // Node count
          _buildStatBadge(
            '${widget.events.length}',
            'Nodes',
            FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),

          // Edge count
          _buildStatBadge(
            '${_analysisResult.allDependencies.length}',
            'Edges',
            FluxForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInteractiveNodes() {
    return widget.events.map((event) {
      final position = _nodePositions[event.id];
      if (position == null) return const SizedBox.shrink();

      final isSelected = _selectedNodeId == event.id;
      final isInCycle = _analysisResult.cycles.any((cycle) => cycle.contains(event.id));

      final scaledPosition = Offset(
        position.dx * _zoomLevel + _canvasOffset.dx,
        position.dy * _zoomLevel + _canvasOffset.dy,
      );

      return Positioned(
        left: scaledPosition.dx - 30,
        top: scaledPosition.dy - 30,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedNodeId = isSelected ? null : event.id;
            });
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isInCycle
                  ? FluxForgeTheme.errorRed
                  : (isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgSurface),
              shape: BoxShape.circle,
              border: Border.all(
                color: isInCycle
                    ? FluxForgeTheme.errorRed
                    : (isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle),
                width: isSelected ? 3 : 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isInCycle ? Icons.error : Icons.event,
                    size: 20,
                    color: isInCycle
                        ? FluxForgeTheme.textPrimary
                        : (isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.name.length > 8 ? '${event.name.substring(0, 8)}...' : event.name,
                    style: TextStyle(
                      color: isInCycle
                          ? FluxForgeTheme.textPrimary
                          : (isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Legend
          _buildLegendItem(Icons.circle, 'Normal', FluxForgeTheme.bgSurface),
          const SizedBox(width: 12),
          _buildLegendItem(Icons.error, 'Cycle', FluxForgeTheme.errorRed),
          const SizedBox(width: 12),
          _buildLegendItem(Icons.arrow_forward, 'Dependency', FluxForgeTheme.accentBlue),

          const Spacer(),

          // Zoom controls
          IconButton(
            icon: Icon(Icons.zoom_out, size: 18, color: FluxForgeTheme.textMuted),
            onPressed: () => setState(() => _zoomLevel = (_zoomLevel - 0.1).clamp(0.5, 2.0)),
            tooltip: 'Zoom Out',
          ),
          Text(
            '${(_zoomLevel * 100).toInt()}%',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          IconButton(
            icon: Icon(Icons.zoom_in, size: 18, color: FluxForgeTheme.textMuted),
            onPressed: () => setState(() => _zoomLevel = (_zoomLevel + 0.1).clamp(0.5, 2.0)),
            tooltip: 'Zoom In',
          ),

          const SizedBox(width: 8),

          // Reset view
          IconButton(
            icon: Icon(Icons.center_focus_strong, size: 18, color: FluxForgeTheme.textMuted),
            onPressed: () {
              setState(() {
                _canvasOffset = Offset.zero;
                _zoomLevel = 1.0;
              });
            },
            tooltip: 'Reset View',
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Graph painter for edges
class _GraphPainter extends CustomPainter {
  final Map<String, Offset> nodePositions;
  final List<SlotCompositeEvent> events;
  final List<EventDependency> dependencies;
  final List<List<String>> cycles;
  final String? selectedNodeId;
  final Offset canvasOffset;
  final double zoomLevel;

  _GraphPainter({
    required this.nodePositions,
    required this.events,
    required this.dependencies,
    required this.cycles,
    this.selectedNodeId,
    required this.canvasOffset,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw edges
    for (final dep in dependencies) {
      final fromPos = nodePositions[dep.fromEventId];
      final toPos = nodePositions[dep.toEventId];

      if (fromPos == null || toPos == null) continue;

      final isInCycle = cycles.any((cycle) =>
          cycle.contains(dep.fromEventId) && cycle.contains(dep.toEventId));

      final scaledFrom = Offset(
        fromPos.dx * zoomLevel + canvasOffset.dx,
        fromPos.dy * zoomLevel + canvasOffset.dy,
      );
      final scaledTo = Offset(
        toPos.dx * zoomLevel + canvasOffset.dx,
        toPos.dy * zoomLevel + canvasOffset.dy,
      );

      _drawArrow(canvas, scaledFrom, scaledTo, isInCycle);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, bool isInCycle) {
    final paint = Paint()
      ..color = isInCycle
          ? FluxForgeTheme.errorRed
          : FluxForgeTheme.accentBlue.withValues(alpha: 0.4)
      ..strokeWidth = isInCycle ? 3 : 2
      ..style = PaintingStyle.stroke;

    // Draw line
    canvas.drawLine(from, to, paint);

    // Draw arrowhead
    final direction = (to - from);
    final length = direction.distance;
    if (length > 0) {
      final normalized = direction / length;
      final arrowSize = 10.0;

      final arrowStart = to - normalized * 30; // Offset from node edge

      final perpendicular = Offset(-normalized.dy, normalized.dx);

      final arrowP1 = arrowStart - normalized * arrowSize + perpendicular * (arrowSize / 2);
      final arrowP2 = arrowStart - normalized * arrowSize - perpendicular * (arrowSize / 2);

      final arrowPath = Path()
        ..moveTo(arrowStart.dx, arrowStart.dy)
        ..lineTo(arrowP1.dx, arrowP1.dy)
        ..lineTo(arrowP2.dx, arrowP2.dy)
        ..close();

      canvas.drawPath(
        arrowPath,
        Paint()
          ..color = isInCycle ? FluxForgeTheme.errorRed : FluxForgeTheme.accentBlue
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) => true;
}

/// Grid painter for background
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    const gridSize = 50.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}
