/// Event Dependency Graph — P12.1.6
///
/// Node-based event flow visualization showing the Stage→Event→Audio chain.
/// Provides a visual representation of how stages trigger events and how
/// events are connected to audio layers.
///
/// Features:
/// - Node-based graph layout
/// - Stage→Event→Audio chain visualization
/// - Drag-drop node repositioning
/// - Export to image
/// - Interactive selection and highlighting
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../services/event_registry.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// EVENT DEPENDENCY NODE TYPES
// =============================================================================

/// Types of nodes in the dependency graph
enum EventNodeType {
  stage,   // Stage trigger (input)
  event,   // Audio event (processing)
  audio,   // Audio layer (output)
}

/// A node in the event dependency graph
class EventGraphNode {
  final String id;
  final String label;
  final EventNodeType type;
  final Color color;
  Offset position;
  final List<String> connectedTo; // IDs of nodes this connects to
  final Map<String, dynamic>? metadata;

  EventGraphNode({
    required this.id,
    required this.label,
    required this.type,
    required this.color,
    required this.position,
    this.connectedTo = const [],
    this.metadata,
  });

  EventGraphNode copyWith({
    String? id,
    String? label,
    EventNodeType? type,
    Color? color,
    Offset? position,
    List<String>? connectedTo,
    Map<String, dynamic>? metadata,
  }) {
    return EventGraphNode(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      color: color ?? this.color,
      position: position ?? this.position,
      connectedTo: connectedTo ?? this.connectedTo,
      metadata: metadata ?? this.metadata,
    );
  }
}

// =============================================================================
// EVENT DEPENDENCY GRAPH WIDGET
// =============================================================================

/// Visual graph showing Stage→Event→Audio dependencies
class EventDependencyGraph extends StatefulWidget {
  /// Events to display in the graph
  final List<AudioEvent> events;

  /// Callback when a node is selected
  final ValueChanged<EventGraphNode?>? onNodeSelected;

  /// Callback when graph layout changes (for persistence)
  final ValueChanged<Map<String, Offset>>? onLayoutChanged;

  /// Initial node positions (for loading saved layout)
  final Map<String, Offset>? initialPositions;

  /// Whether to allow drag repositioning
  final bool allowDragReposition;

  /// Accent color for highlights
  final Color accentColor;

  const EventDependencyGraph({
    super.key,
    required this.events,
    this.onNodeSelected,
    this.onLayoutChanged,
    this.initialPositions,
    this.allowDragReposition = true,
    this.accentColor = const Color(0xFF4A9EFF),
  });

  @override
  State<EventDependencyGraph> createState() => EventDependencyGraphState();
}

class EventDependencyGraphState extends State<EventDependencyGraph>
    with SingleTickerProviderStateMixin {
  // Graph state
  late List<EventGraphNode> _nodes;
  String? _selectedNodeId;
  String? _hoveredNodeId;
  String? _draggedNodeId;

  // Canvas transform
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Layout constants
  static const double _nodeWidth = 120.0;
  static const double _nodeHeight = 40.0;
  static const double _horizontalSpacing = 180.0;
  static const double _verticalSpacing = 70.0;
  static const double _columnPadding = 60.0;

  // Global key for export
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _buildGraph();
  }

  @override
  void didUpdateWidget(EventDependencyGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != oldWidget.events) {
      _buildGraph();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _buildGraph() {
    _nodes = [];
    final stageConfig = StageConfigurationService.instance;

    // Column positions
    const stageX = _columnPadding;
    const eventX = _columnPadding + _horizontalSpacing;
    const audioX = _columnPadding + _horizontalSpacing * 2;

    // Track unique stages and create nodes
    final stageNodes = <String, EventGraphNode>{};
    final eventNodes = <String, EventGraphNode>{};
    final audioNodes = <String, EventGraphNode>{};

    int eventRow = 0;
    for (final event in widget.events) {
      // Create stage node if not exists
      final stageName = event.stage.toUpperCase();
      if (!stageNodes.containsKey(stageName)) {
        final stageCategory = stageConfig.getStage(stageName)?.category;
        stageNodes[stageName] = EventGraphNode(
          id: 'stage_$stageName',
          label: stageName,
          type: EventNodeType.stage,
          color: _getStageColor(stageCategory),
          position: widget.initialPositions?['stage_$stageName'] ??
              Offset(stageX, _verticalSpacing + stageNodes.length * _verticalSpacing),
          connectedTo: [],
        );
      }

      // Create event node
      final eventId = 'event_${event.id}';
      final eventNode = EventGraphNode(
        id: eventId,
        label: event.name.length > 15 ? '${event.name.substring(0, 12)}...' : event.name,
        type: EventNodeType.event,
        color: FluxForgeTheme.accentBlue,
        position: widget.initialPositions?[eventId] ??
            Offset(eventX, _verticalSpacing + eventRow * _verticalSpacing),
        connectedTo: event.layers.map((l) => 'audio_${l.id}').toList(),
        metadata: {'eventId': event.id, 'fullName': event.name},
      );
      eventNodes[event.id] = eventNode;

      // Connect stage to event
      stageNodes[stageName] = stageNodes[stageName]!.copyWith(
        connectedTo: [...stageNodes[stageName]!.connectedTo, eventId],
      );

      // Create audio layer nodes
      int audioRow = 0;
      for (final layer in event.layers) {
        final audioId = 'audio_${layer.id}';
        if (!audioNodes.containsKey(layer.id)) {
          final fileName = layer.audioPath.split('/').last;
          audioNodes[layer.id] = EventGraphNode(
            id: audioId,
            label: fileName.length > 15 ? '${fileName.substring(0, 12)}...' : fileName,
            type: EventNodeType.audio,
            color: FluxForgeTheme.accentGreen,
            position: widget.initialPositions?[audioId] ??
                Offset(audioX, _verticalSpacing + (eventRow + audioRow * 0.5) * _verticalSpacing),
            metadata: {'path': layer.audioPath, 'volume': layer.volume},
          );
          audioRow++;
        }
      }
      eventRow++;
    }

    _nodes = [
      ...stageNodes.values,
      ...eventNodes.values,
      ...audioNodes.values,
    ];
    setState(() {});
  }

  Color _getStageColor(StageCategory? category) {
    if (category == null) return FluxForgeTheme.textSecondary;
    return Color(category.color);
  }

  /// Export graph as image
  Future<ui.Image?> exportToImage() async {
    try {
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      return await boundary.toImage(pixelRatio: 2.0);
    } catch (e) {
      debugPrint('[EventDependencyGraph] Export failed: $e');
      return null;
    }
  }

  void _handleNodeTap(EventGraphNode node) {
    setState(() {
      _selectedNodeId = _selectedNodeId == node.id ? null : node.id;
    });
    widget.onNodeSelected?.call(_selectedNodeId != null ? node : null);
  }

  void _handleNodeDragStart(EventGraphNode node) {
    if (!widget.allowDragReposition) return;
    setState(() {
      _draggedNodeId = node.id;
    });
  }

  void _handleNodeDragUpdate(EventGraphNode node, Offset delta) {
    if (!widget.allowDragReposition || _draggedNodeId != node.id) return;

    final index = _nodes.indexWhere((n) => n.id == node.id);
    if (index >= 0) {
      setState(() {
        _nodes[index] = node.copyWith(
          position: node.position + delta / _scale,
        );
      });
    }
  }

  void _handleNodeDragEnd() {
    if (_draggedNodeId != null) {
      _draggedNodeId = null;
      // Notify layout changed
      final positions = <String, Offset>{};
      for (final node in _nodes) {
        positions[node.id] = node.position;
      }
      widget.onLayoutChanged?.call(positions);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RepaintBoundary(
              key: _repaintBoundaryKey,
              child: GestureDetector(
                onPanUpdate: (details) {
                  if (_draggedNodeId == null) {
                    setState(() {
                      _offset += details.delta;
                    });
                  }
                },
                child: ClipRect(
                  child: CustomPaint(
                    painter: _ConnectionPainter(
                      nodes: _nodes,
                      scale: _scale,
                      offset: _offset,
                      selectedNodeId: _selectedNodeId,
                      accentColor: widget.accentColor,
                      animationValue: _pulseAnimation.value,
                    ),
                    child: Stack(
                      children: [
                        // Column labels
                        _buildColumnLabel('STAGES', _columnPadding),
                        _buildColumnLabel('EVENTS', _columnPadding + _horizontalSpacing),
                        _buildColumnLabel('AUDIO', _columnPadding + _horizontalSpacing * 2),

                        // Nodes
                        for (final node in _nodes)
                          _buildNode(node),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree, size: 16, color: widget.accentColor),
          const SizedBox(width: 8),
          const Text(
            'Event Dependency Graph',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${_nodes.where((n) => n.type == EventNodeType.stage).length} stages  '
            '${_nodes.where((n) => n.type == EventNodeType.event).length} events  '
            '${_nodes.where((n) => n.type == EventNodeType.audio).length} audio',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 12),
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 16),
            onPressed: () => setState(() => _scale = (_scale - 0.1).clamp(0.5, 2.0)),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Text(
            '${(_scale * 100).round()}%',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 16),
            onPressed: () => setState(() => _scale = (_scale + 0.1).clamp(0.5, 2.0)),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong, size: 16),
            onPressed: () => setState(() {
              _scale = 1.0;
              _offset = Offset.zero;
            }),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Reset view',
          ),
        ],
      ),
    );
  }

  Widget _buildColumnLabel(String label, double x) {
    return Positioned(
      left: x * _scale + _offset.dx,
      top: 8,
      child: Text(
        label,
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 10 * _scale,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildNode(EventGraphNode node) {
    final isSelected = node.id == _selectedNodeId;
    final isHovered = node.id == _hoveredNodeId;
    final isDragged = node.id == _draggedNodeId;

    return Positioned(
      left: node.position.dx * _scale + _offset.dx,
      top: node.position.dy * _scale + _offset.dy,
      child: GestureDetector(
        onTap: () => _handleNodeTap(node),
        onPanStart: (_) => _handleNodeDragStart(node),
        onPanUpdate: (details) => _handleNodeDragUpdate(node, details.delta),
        onPanEnd: (_) => _handleNodeDragEnd(),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hoveredNodeId = node.id),
          onExit: (_) => setState(() => _hoveredNodeId = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _nodeWidth * _scale,
            height: _nodeHeight * _scale,
            decoration: BoxDecoration(
              color: isSelected
                  ? node.color.withOpacity(0.3)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(6 * _scale),
              border: Border.all(
                color: isSelected
                    ? widget.accentColor
                    : isHovered
                        ? node.color
                        : FluxForgeTheme.borderSubtle,
                width: isSelected || isHovered ? 2 : 1,
              ),
              boxShadow: isDragged
                  ? [
                      BoxShadow(
                        color: node.color.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Type indicator
                Container(
                  width: 4 * _scale,
                  decoration: BoxDecoration(
                    color: node.color,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(5 * _scale),
                      bottomLeft: Radius.circular(5 * _scale),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Icon
                Icon(
                  _getNodeIcon(node.type),
                  size: 14 * _scale,
                  color: node.color,
                ),
                const SizedBox(width: 4),
                // Label
                Expanded(
                  child: Text(
                    node.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10 * _scale,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getNodeIcon(EventNodeType type) {
    switch (type) {
      case EventNodeType.stage:
        return Icons.flag;
      case EventNodeType.event:
        return Icons.event;
      case EventNodeType.audio:
        return Icons.audiotrack;
    }
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(Icons.flag, 'Stage', FluxForgeTheme.accentOrange),
          const SizedBox(width: 16),
          _buildLegendItem(Icons.event, 'Event', FluxForgeTheme.accentBlue),
          const SizedBox(width: 16),
          _buildLegendItem(Icons.audiotrack, 'Audio', FluxForgeTheme.accentGreen),
          const Spacer(),
          Text(
            'Drag to reposition  |  Click to select',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

// =============================================================================
// CONNECTION PAINTER
// =============================================================================

class _ConnectionPainter extends CustomPainter {
  final List<EventGraphNode> nodes;
  final double scale;
  final Offset offset;
  final String? selectedNodeId;
  final Color accentColor;
  final double animationValue;

  _ConnectionPainter({
    required this.nodes,
    required this.scale,
    required this.offset,
    this.selectedNodeId,
    required this.accentColor,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};

    for (final node in nodes) {
      for (final targetId in node.connectedTo) {
        final target = nodeMap[targetId];
        if (target == null) continue;

        final isHighlighted = node.id == selectedNodeId || targetId == selectedNodeId;

        final paint = Paint()
          ..color = isHighlighted
              ? accentColor.withOpacity(animationValue)
              : FluxForgeTheme.textSecondary.withOpacity(0.3)
          ..strokeWidth = isHighlighted ? 2.0 : 1.0
          ..style = PaintingStyle.stroke;

        final start = Offset(
          (node.position.dx + EventDependencyGraphState._nodeWidth) * scale + offset.dx,
          (node.position.dy + EventDependencyGraphState._nodeHeight / 2) * scale + offset.dy,
        );
        final end = Offset(
          target.position.dx * scale + offset.dx,
          (target.position.dy + EventDependencyGraphState._nodeHeight / 2) * scale + offset.dy,
        );

        // Draw bezier curve
        final controlPoint1 = Offset(start.dx + 40 * scale, start.dy);
        final controlPoint2 = Offset(end.dx - 40 * scale, end.dy);

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            controlPoint1.dx, controlPoint1.dy,
            controlPoint2.dx, controlPoint2.dy,
            end.dx, end.dy,
          );

        canvas.drawPath(path, paint);

        // Draw arrow head
        if (isHighlighted) {
          _drawArrowHead(canvas, end, controlPoint2, paint);
        }
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset from, Paint paint) {
    const arrowSize = 8.0;
    final direction = (tip - from).direction;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - arrowSize * math.cos(direction - 0.5),
        tip.dy - arrowSize * math.sin(direction - 0.5),
      )
      ..lineTo(
        tip.dx - arrowSize * math.cos(direction + 0.5),
        tip.dy - arrowSize * math.sin(direction + 0.5),
      )
      ..close();

    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_ConnectionPainter oldDelegate) {
    return nodes != oldDelegate.nodes ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        selectedNodeId != oldDelegate.selectedNodeId ||
        animationValue != oldDelegate.animationValue;
  }
}
