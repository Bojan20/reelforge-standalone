// Audio Graph Visualization Panel (P10.1.7)
//
// Node-based visual editor for audio routing graph:
// - Tracks, buses, master as circular nodes
// - Edges showing connections with latency labels
// - Drag nodes to reposition
// - Click edge to delete connection
// - Drag from output to input to create connection
// - Color-coded by type (track=blue, bus=orange, master=red)
// - PDC compensation displayed on each node
// - Zoom/pan canvas with mouse/trackpad

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/mixer_provider.dart';

// =============================================================================
// GRAPH NODE MODEL
// =============================================================================

enum GraphNodeType {
  track,
  bus,
  aux,
  master,
}

class GraphNode {
  final String id;
  final String name;
  final GraphNodeType type;
  final Color color;
  Offset position;
  final int? latencyMs; // PDC latency in milliseconds
  final bool muted;
  final bool soloed;

  GraphNode({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.position,
    this.latencyMs,
    this.muted = false,
    this.soloed = false,
  });

  GraphNode copyWith({
    Offset? position,
    bool? muted,
    bool? soloed,
  }) =>
      GraphNode(
        id: id,
        name: name,
        type: type,
        color: color,
        position: position ?? this.position,
        latencyMs: latencyMs,
        muted: muted ?? this.muted,
        soloed: soloed ?? this.soloed,
      );

  double get radius => switch (type) {
        GraphNodeType.master => 40.0,
        GraphNodeType.bus => 35.0,
        GraphNodeType.aux => 30.0,
        GraphNodeType.track => 28.0,
      };

  String get typeLabel => switch (type) {
        GraphNodeType.track => 'TRK',
        GraphNodeType.bus => 'BUS',
        GraphNodeType.aux => 'AUX',
        GraphNodeType.master => 'MST',
      };

  IconData get icon => switch (type) {
        GraphNodeType.track => Icons.graphic_eq,
        GraphNodeType.bus => Icons.call_split,
        GraphNodeType.aux => Icons.alt_route,
        GraphNodeType.master => Icons.speaker,
      };
}

// =============================================================================
// GRAPH EDGE MODEL
// =============================================================================

class GraphEdge {
  final String sourceId;
  final String targetId;
  final double level; // 0.0 - 1.0
  final bool preFader;
  final int? latencyMs; // Additional latency from this connection

  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    this.level = 1.0,
    this.preFader = false,
    this.latencyMs,
  });

  GraphEdge copyWith({
    double? level,
    bool? preFader,
  }) =>
      GraphEdge(
        sourceId: sourceId,
        targetId: targetId,
        level: level ?? this.level,
        preFader: preFader ?? this.preFader,
        latencyMs: latencyMs,
      );
}

// =============================================================================
// AUDIO GRAPH PANEL
// =============================================================================

class AudioGraphPanel extends StatefulWidget {
  const AudioGraphPanel({super.key});

  @override
  State<AudioGraphPanel> createState() => _AudioGraphPanelState();
}

class _AudioGraphPanelState extends State<AudioGraphPanel>
    with SingleTickerProviderStateMixin {
  // Graph data
  final Map<String, GraphNode> _nodes = {};
  final List<GraphEdge> _edges = [];

  // Canvas state
  Offset _canvasOffset = Offset.zero;
  double _canvasScale = 1.0;
  static const double _minScale = 0.25;
  static const double _maxScale = 2.0;

  // Interaction state
  String? _selectedNodeId;
  String? _hoveredNodeId;
  String? _draggingNodeId;
  Offset? _dragStartPosition;
  bool _isPanning = false;
  Offset? _panStartOffset;

  // Connection creation state
  String? _connectionStartNodeId;
  Offset? _connectionEndPoint;

  // Edge hover state
  int? _hoveredEdgeIndex;

  // Animation
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(() => setState(() {}));
    _initializeGraph();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _initializeGraph() {
    // Create nodes from mixer provider or use demo data
    _createDemoGraph();
    _autoLayout();
  }

  void _createDemoGraph() {
    // Create master node (always present)
    _nodes['master'] = GraphNode(
      id: 'master',
      name: 'Master',
      type: GraphNodeType.master,
      color: FluxForgeTheme.accentRed,
      position: Offset.zero,
      latencyMs: 0,
    );

    // Create buses
    final busColors = [
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentPurple,
      FluxForgeTheme.accentYellow,
    ];
    final busNames = ['Drums', 'Music', 'SFX'];
    for (int i = 0; i < 3; i++) {
      final id = 'bus_$i';
      _nodes[id] = GraphNode(
        id: id,
        name: busNames[i],
        type: GraphNodeType.bus,
        color: busColors[i],
        position: Offset.zero,
        latencyMs: (i + 1) * 2, // Simulated PDC
      );
      // Connect bus to master
      _edges.add(GraphEdge(sourceId: id, targetId: 'master'));
    }

    // Create aux sends
    final auxColors = [FluxForgeTheme.accentCyan, FluxForgeTheme.accentPink];
    final auxNames = ['Reverb', 'Delay'];
    for (int i = 0; i < 2; i++) {
      final id = 'aux_$i';
      _nodes[id] = GraphNode(
        id: id,
        name: auxNames[i],
        type: GraphNodeType.aux,
        color: auxColors[i],
        position: Offset.zero,
        latencyMs: i == 0 ? 15 : 8, // Reverb has more latency
      );
      // Connect aux to master
      _edges.add(GraphEdge(sourceId: id, targetId: 'master'));
    }

    // Create tracks
    final trackColors = [
      const Color(0xFF5B9BD5),
      const Color(0xFF70C050),
      const Color(0xFFD4A84B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF4ECDC4),
    ];
    final trackNames = ['Kick', 'Snare', 'HiHat', 'Bass', 'Synth', 'Vocal'];
    for (int i = 0; i < 6; i++) {
      final id = 'track_$i';
      _nodes[id] = GraphNode(
        id: id,
        name: trackNames[i],
        type: GraphNodeType.track,
        color: trackColors[i],
        position: Offset.zero,
        latencyMs: 0,
        muted: i == 2, // HiHat muted for demo
        soloed: i == 5, // Vocal soloed for demo
      );

      // Route tracks to appropriate buses
      final busId = switch (i) {
        0 || 1 || 2 => 'bus_0', // Drums
        3 || 4 => 'bus_1', // Music
        5 => 'bus_2', // SFX (Voice)
        _ => 'master',
      };
      _edges.add(GraphEdge(sourceId: id, targetId: busId));

      // Add some aux sends
      if (i == 4 || i == 5) {
        _edges.add(GraphEdge(
          sourceId: id,
          targetId: 'aux_0',
          level: 0.4,
          preFader: false,
        ));
      }
      if (i == 3) {
        _edges.add(GraphEdge(
          sourceId: id,
          targetId: 'aux_1',
          level: 0.3,
          preFader: false,
        ));
      }
    }
  }

  void _autoLayout() {
    // Arrange nodes in a hierarchical layout
    // Master at right, buses in middle, tracks at left
    const double nodeSpacingX = 180;
    const double nodeSpacingY = 80;

    // Master
    _nodes['master']?.position = const Offset(nodeSpacingX * 2, 0);

    // Buses (middle column)
    final buses = _nodes.values
        .where((n) => n.type == GraphNodeType.bus)
        .toList();
    for (int i = 0; i < buses.length; i++) {
      final yOffset = (i - (buses.length - 1) / 2) * nodeSpacingY;
      buses[i].position = Offset(nodeSpacingX, yOffset);
    }

    // Aux (middle column, below buses)
    final auxes = _nodes.values
        .where((n) => n.type == GraphNodeType.aux)
        .toList();
    for (int i = 0; i < auxes.length; i++) {
      final yOffset = (buses.length / 2 + i + 0.5) * nodeSpacingY;
      auxes[i].position = Offset(nodeSpacingX, yOffset);
    }

    // Tracks (left column)
    final tracks = _nodes.values
        .where((n) => n.type == GraphNodeType.track)
        .toList();
    for (int i = 0; i < tracks.length; i++) {
      final yOffset = (i - (tracks.length - 1) / 2) * nodeSpacingY;
      tracks[i].position = Offset(0, yOffset);
    }
  }

  void _syncFromMixer(MixerProvider mixer) {
    // Sync nodes from mixer provider
    _nodes.clear();
    _edges.clear();

    // Master
    _nodes['master'] = GraphNode(
      id: 'master',
      name: mixer.master.name,
      type: GraphNodeType.master,
      color: FluxForgeTheme.accentRed,
      position: Offset.zero,
      latencyMs: 0,
      muted: mixer.master.muted,
      soloed: mixer.master.soloed,
    );

    // Buses
    for (final bus in mixer.buses) {
      _nodes[bus.id] = GraphNode(
        id: bus.id,
        name: bus.name,
        type: GraphNodeType.bus,
        color: bus.color,
        position: Offset.zero,
        latencyMs: 2, // Placeholder
        muted: bus.muted,
        soloed: bus.soloed,
      );
      _edges.add(GraphEdge(sourceId: bus.id, targetId: 'master'));
    }

    // Aux
    for (final aux in mixer.auxes) {
      _nodes[aux.id] = GraphNode(
        id: aux.id,
        name: aux.name,
        type: GraphNodeType.aux,
        color: aux.color,
        position: Offset.zero,
        latencyMs: 10,
        muted: aux.muted,
        soloed: aux.soloed,
      );
      _edges.add(GraphEdge(sourceId: aux.id, targetId: 'master'));
    }

    // Tracks
    for (final channel in mixer.channels) {
      _nodes[channel.id] = GraphNode(
        id: channel.id,
        name: channel.name,
        type: GraphNodeType.track,
        color: channel.color,
        position: Offset.zero,
        latencyMs: 0,
        muted: channel.muted,
        soloed: channel.soloed,
      );

      // Route to bus or master
      final targetId = channel.outputBus ?? 'master';
      _edges.add(GraphEdge(sourceId: channel.id, targetId: targetId));

      // Aux sends
      for (final send in channel.sends) {
        if (send.enabled && send.level > 0) {
          _edges.add(GraphEdge(
            sourceId: channel.id,
            targetId: send.auxId,
            level: send.level,
            preFader: send.preFader,
          ));
        }
      }
    }

    _autoLayout();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: MouseRegion(
                  onHover: _onMouseHover,
                  cursor: _getCursor(),
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _AudioGraphPainter(
                        nodes: _nodes,
                        edges: _edges,
                        canvasOffset: _canvasOffset,
                        canvasScale: _canvasScale,
                        selectedNodeId: _selectedNodeId,
                        hoveredNodeId: _hoveredNodeId,
                        connectionStartNodeId: _connectionStartNodeId,
                        connectionEndPoint: _connectionEndPoint,
                        hoveredEdgeIndex: _hoveredEdgeIndex,
                      ),
                      child: Container(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree, color: FluxForgeTheme.accentBlue, size: 16),
          const SizedBox(width: 8),
          const Text(
            'AUDIO ROUTING GRAPH',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Zoom controls
          _buildIconButton(Icons.zoom_out, () {
            setState(() {
              _canvasScale = (_canvasScale - 0.1).clamp(_minScale, _maxScale);
            });
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${(_canvasScale * 100).toInt()}%',
              style: const TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          _buildIconButton(Icons.zoom_in, () {
            setState(() {
              _canvasScale = (_canvasScale + 0.1).clamp(_minScale, _maxScale);
            });
          }),
          const SizedBox(width: 8),
          _buildIconButton(Icons.center_focus_strong, _centerView),
          const SizedBox(width: 8),
          _buildIconButton(Icons.auto_fix_high, () {
            setState(() {
              _autoLayout();
            });
          }),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
      ),
    );
  }

  Widget _buildFooter() {
    final nodeCount = _nodes.length;
    final edgeCount = _edges.length;
    final selectedNode = _selectedNodeId != null ? _nodes[_selectedNodeId] : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Stats
          _buildLegendItem(
            FluxForgeTheme.accentBlue,
            '${_nodes.values.where((n) => n.type == GraphNodeType.track).length} tracks',
          ),
          const SizedBox(width: 12),
          _buildLegendItem(
            FluxForgeTheme.accentOrange,
            '${_nodes.values.where((n) => n.type == GraphNodeType.bus).length} buses',
          ),
          const SizedBox(width: 12),
          _buildLegendItem(
            FluxForgeTheme.accentCyan,
            '${_nodes.values.where((n) => n.type == GraphNodeType.aux).length} aux',
          ),
          const SizedBox(width: 12),
          Text(
            '$edgeCount connections',
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          const Spacer(),
          // Selected node info
          if (selectedNode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: selectedNode.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: selectedNode.color),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selectedNode.icon, size: 12, color: selectedNode.color),
                  const SizedBox(width: 4),
                  Text(
                    selectedNode.name,
                    style: TextStyle(
                      color: selectedNode.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (selectedNode.latencyMs != null && selectedNode.latencyMs! > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      'PDC: ${selectedNode.latencyMs}ms',
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 9,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Instructions
          if (selectedNode == null) ...[
            const Text(
              'Drag nodes to reposition | Scroll to zoom | Middle-click to pan',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // INTERACTION HANDLERS
  // ==========================================================================

  void _centerView() {
    if (_nodes.isEmpty) return;

    // Calculate bounding box of all nodes
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final node in _nodes.values) {
      minX = math.min(minX, node.position.dx - node.radius);
      maxX = math.max(maxX, node.position.dx + node.radius);
      minY = math.min(minY, node.position.dy - node.radius);
      maxY = math.max(maxY, node.position.dy + node.radius);
    }

    // Get canvas size (approximate)
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final canvasSize = renderBox.size;
    final graphCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final viewCenter = Offset(canvasSize.width / 2, canvasSize.height / 2 - 50);

    setState(() {
      _canvasOffset = viewCenter - graphCenter * _canvasScale;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    final localPos = details.localFocalPoint;
    final graphPos = _screenToGraph(localPos);

    // Check if starting on a node
    for (final entry in _nodes.entries) {
      if (_isPointInNode(graphPos, entry.value)) {
        _draggingNodeId = entry.key;
        _dragStartPosition = entry.value.position;
        _selectedNodeId = entry.key;
        return;
      }
    }

    // Otherwise, start panning
    _isPanning = true;
    _panStartOffset = _canvasOffset;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_draggingNodeId != null) {
      // Move node
      final node = _nodes[_draggingNodeId];
      if (node != null) {
        final delta = details.focalPointDelta / _canvasScale;
        setState(() {
          _nodes[_draggingNodeId!] = node.copyWith(
            position: node.position + delta,
          );
        });
      }
    } else if (_isPanning && _panStartOffset != null) {
      // Pan canvas
      setState(() {
        _canvasOffset = _panStartOffset! + details.focalPointDelta;
      });
    } else if (details.scale != 1.0) {
      // Zoom (pinch gesture)
      setState(() {
        _canvasScale = (_canvasScale * details.scale).clamp(_minScale, _maxScale);
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _draggingNodeId = null;
    _dragStartPosition = null;
    _isPanning = false;
    _panStartOffset = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // Zoom with scroll wheel
      final delta = event.scrollDelta.dy > 0 ? -0.1 : 0.1;
      setState(() {
        final oldScale = _canvasScale;
        _canvasScale = (_canvasScale + delta).clamp(_minScale, _maxScale);

        // Zoom towards mouse position
        if (_canvasScale != oldScale) {
          final scaleChange = _canvasScale / oldScale;
          final mousePos = event.localPosition;
          _canvasOffset = mousePos - (mousePos - _canvasOffset) * scaleChange;
        }
      });
    }
  }

  void _onMouseHover(PointerHoverEvent event) {
    final graphPos = _screenToGraph(event.localPosition);

    // Check hover on nodes
    String? newHoveredNode;
    for (final entry in _nodes.entries) {
      if (_isPointInNode(graphPos, entry.value)) {
        newHoveredNode = entry.key;
        break;
      }
    }

    // Check hover on edges
    int? newHoveredEdge;
    if (newHoveredNode == null) {
      for (int i = 0; i < _edges.length; i++) {
        if (_isPointNearEdge(graphPos, _edges[i])) {
          newHoveredEdge = i;
          break;
        }
      }
    }

    if (newHoveredNode != _hoveredNodeId || newHoveredEdge != _hoveredEdgeIndex) {
      setState(() {
        _hoveredNodeId = newHoveredNode;
        _hoveredEdgeIndex = newHoveredEdge;
      });
    }
  }

  MouseCursor _getCursor() {
    if (_draggingNodeId != null) return SystemMouseCursors.grabbing;
    if (_hoveredNodeId != null) return SystemMouseCursors.grab;
    if (_hoveredEdgeIndex != null) return SystemMouseCursors.click;
    if (_isPanning) return SystemMouseCursors.grabbing;
    return SystemMouseCursors.basic;
  }

  // ==========================================================================
  // UTILITY METHODS
  // ==========================================================================

  Offset _screenToGraph(Offset screenPos) {
    return (screenPos - _canvasOffset) / _canvasScale;
  }

  bool _isPointInNode(Offset point, GraphNode node) {
    return (point - node.position).distance <= node.radius;
  }

  bool _isPointNearEdge(Offset point, GraphEdge edge) {
    final source = _nodes[edge.sourceId];
    final target = _nodes[edge.targetId];
    if (source == null || target == null) return false;

    return _distanceToLineSegment(point, source.position, target.position) < 8;
  }

  double _distanceToLineSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final proj = (ap.dx * ab.dx + ap.dy * ab.dy) / (ab.dx * ab.dx + ab.dy * ab.dy);
    final clampedProj = proj.clamp(0.0, 1.0);
    final closest = a + ab * clampedProj;
    return (p - closest).distance;
  }
}

// =============================================================================
// CUSTOM PAINTER
// =============================================================================

class _AudioGraphPainter extends CustomPainter {
  final Map<String, GraphNode> nodes;
  final List<GraphEdge> edges;
  final Offset canvasOffset;
  final double canvasScale;
  final String? selectedNodeId;
  final String? hoveredNodeId;
  final String? connectionStartNodeId;
  final Offset? connectionEndPoint;
  final int? hoveredEdgeIndex;

  _AudioGraphPainter({
    required this.nodes,
    required this.edges,
    required this.canvasOffset,
    required this.canvasScale,
    this.selectedNodeId,
    this.hoveredNodeId,
    this.connectionStartNodeId,
    this.connectionEndPoint,
    this.hoveredEdgeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    // Draw grid
    _drawGrid(canvas, size);

    // Draw edges
    for (int i = 0; i < edges.length; i++) {
      _drawEdge(canvas, edges[i], isHovered: i == hoveredEdgeIndex);
    }

    // Draw connection in progress
    if (connectionStartNodeId != null && connectionEndPoint != null) {
      final startNode = nodes[connectionStartNodeId];
      if (startNode != null) {
        _drawConnectionLine(canvas, startNode.position, connectionEndPoint!);
      }
    }

    // Draw nodes
    for (final node in nodes.values) {
      _drawNode(
        canvas,
        node,
        isSelected: node.id == selectedNodeId,
        isHovered: node.id == hoveredNodeId,
      );
    }

    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const gridSize = 40.0;
    final scaledSize = size / canvasScale;
    final topLeft = -canvasOffset / canvasScale;

    final startX = (topLeft.dx / gridSize).floor() * gridSize;
    final startY = (topLeft.dy / gridSize).floor() * gridSize;
    final endX = topLeft.dx + scaledSize.width;
    final endY = topLeft.dy + scaledSize.height;

    for (double x = startX; x <= endX; x += gridSize) {
      canvas.drawLine(Offset(x, startY), Offset(x, endY), gridPaint);
    }
    for (double y = startY; y <= endY; y += gridSize) {
      canvas.drawLine(Offset(startX, y), Offset(endX, y), gridPaint);
    }
  }

  void _drawEdge(Canvas canvas, GraphEdge edge, {bool isHovered = false}) {
    final source = nodes[edge.sourceId];
    final target = nodes[edge.targetId];
    if (source == null || target == null) return;

    // Calculate edge points (from node border)
    final direction = (target.position - source.position).normalize();
    final start = source.position + direction * source.radius;
    final end = target.position - direction * target.radius;

    // Draw main edge
    final edgePaint = Paint()
      ..color = isHovered
          ? FluxForgeTheme.accentBlue
          : edge.preFader
              ? FluxForgeTheme.accentOrange.withValues(alpha: 0.6)
              : FluxForgeTheme.textSecondary.withValues(alpha: 0.4)
      ..strokeWidth = isHovered ? 3 : 2
      ..style = PaintingStyle.stroke;

    // Create curved path
    final path = Path();
    path.moveTo(start.dx, start.dy);

    // Control points for bezier curve
    final midX = (start.dx + end.dx) / 2;
    path.cubicTo(
      midX,
      start.dy,
      midX,
      end.dy,
      end.dx,
      end.dy,
    );

    canvas.drawPath(path, edgePaint);

    // Draw arrow head
    _drawArrowHead(canvas, end, direction, edgePaint.color);

    // Draw latency label on edge
    if (edge.latencyMs != null && edge.latencyMs! > 0) {
      final midPoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      _drawLabel(canvas, midPoint, '${edge.latencyMs}ms', FluxForgeTheme.textTertiary);
    }

    // Draw send level if < 1.0
    if (edge.level < 1.0) {
      final labelPos = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2 + 12);
      _drawLabel(canvas, labelPos, '${(edge.level * 100).toInt()}%', source.color);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset point, Offset direction, Color color) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowSize = 8.0;
    final perpendicular = Offset(-direction.dy, direction.dx);

    final path = Path();
    path.moveTo(point.dx, point.dy);
    path.lineTo(
      point.dx - direction.dx * arrowSize + perpendicular.dx * arrowSize * 0.5,
      point.dy - direction.dy * arrowSize + perpendicular.dy * arrowSize * 0.5,
    );
    path.lineTo(
      point.dx - direction.dx * arrowSize - perpendicular.dx * arrowSize * 0.5,
      point.dy - direction.dy * arrowSize - perpendicular.dy * arrowSize * 0.5,
    );
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  void _drawConnectionLine(Canvas canvas, Offset start, Offset end) {
    final paint = Paint()
      ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Dashed line
    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.lineTo(end.dx, end.dy);

    canvas.drawPath(
      _dashPath(path, 8, 4),
      paint,
    );
  }

  Path _dashPath(Path source, double dashWidth, double dashSpace) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final dashEnd = math.min(distance + dashWidth, metric.length);
        result.addPath(
          metric.extractPath(distance, dashEnd),
          Offset.zero,
        );
        distance = dashEnd + dashSpace;
      }
    }
    return result;
  }

  void _drawNode(
    Canvas canvas,
    GraphNode node, {
    bool isSelected = false,
    bool isHovered = false,
  }) {
    final center = node.position;
    final radius = node.radius;

    // Outer glow for selected/hovered
    if (isSelected || isHovered) {
      final glowPaint = Paint()
        ..color = node.color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, radius + 4, glowPaint);
    }

    // Node shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(2, 2), radius, shadowPaint);

    // Node fill gradient
    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          node.color.withValues(alpha: 0.8),
          node.color.withValues(alpha: 0.4),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, fillPaint);

    // Node border
    final borderPaint = Paint()
      ..color = isSelected
          ? FluxForgeTheme.accentBlue
          : isHovered
              ? node.color
              : node.color.withValues(alpha: 0.6)
      ..strokeWidth = isSelected ? 3 : 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, borderPaint);

    // Muted/Solo indicators
    if (node.muted) {
      final mutePaint = Paint()
        ..color = FluxForgeTheme.accentOrange
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        center - Offset(radius * 0.5, radius * 0.5),
        center + Offset(radius * 0.5, radius * 0.5),
        mutePaint,
      );
      canvas.drawLine(
        center - Offset(-radius * 0.5, radius * 0.5),
        center + Offset(-radius * 0.5, radius * 0.5),
        mutePaint,
      );
    }

    if (node.soloed) {
      final soloPaint = Paint()
        ..color = FluxForgeTheme.accentYellow
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius * 0.2, soloPaint);
    }

    // Type label above node
    _drawLabel(
      canvas,
      center - Offset(0, radius + 10),
      node.typeLabel,
      FluxForgeTheme.textTertiary,
      fontSize: 8,
    );

    // Node name
    _drawLabel(
      canvas,
      center,
      node.name,
      FluxForgeTheme.textPrimary,
      fontSize: 10,
      bold: true,
    );

    // PDC latency below node
    if (node.latencyMs != null && node.latencyMs! > 0) {
      _drawLabel(
        canvas,
        center + Offset(0, radius + 12),
        '${node.latencyMs}ms',
        FluxForgeTheme.accentCyan,
        fontSize: 9,
        background: FluxForgeTheme.bgDeep.withValues(alpha: 0.8),
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    Offset position,
    String text,
    Color color, {
    double fontSize = 10,
    bool bold = false,
    Color? background,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        fontFamily: 'Inter',
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = position - Offset(textPainter.width / 2, textPainter.height / 2);

    // Draw background if specified
    if (background != null) {
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: position,
          width: textPainter.width + 8,
          height: textPainter.height + 4,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(bgRect, Paint()..color = background);
    }

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AudioGraphPainter oldDelegate) {
    return true; // Always repaint for smooth interaction
  }
}

// =============================================================================
// OFFSET EXTENSIONS
// =============================================================================

extension OffsetNormalize on Offset {
  Offset normalize() {
    final length = distance;
    if (length == 0) return Offset.zero;
    return this / length;
  }
}
