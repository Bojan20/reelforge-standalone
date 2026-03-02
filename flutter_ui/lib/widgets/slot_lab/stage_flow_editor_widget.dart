/// P-DSF Visual Editor — Drag & drop node canvas with connection wires
///
/// Three-panel layout: Palette (left) | Canvas (center) | Inspector (bottom)
/// Supports: pan, zoom, node selection, edge connections, dry-run visualization
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stage_flow_models.dart';
import '../../providers/slot_lab/stage_flow_provider.dart';
import '../../services/stage_configuration_service.dart';
import '../../services/stage_flow_presets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MAIN EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Full-featured stage flow graph editor with canvas, palette, and toolbar.
class StageFlowEditorWidget extends StatefulWidget {
  final StageFlowProvider provider;
  final StageConfigurationService? stageService;

  const StageFlowEditorWidget({
    super.key,
    required this.provider,
    this.stageService,
  });

  @override
  State<StageFlowEditorWidget> createState() => _StageFlowEditorWidgetState();
}

class _StageFlowEditorWidgetState extends State<StageFlowEditorWidget> {
  // Canvas transform
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  static const double _minScale = 0.25;
  static const double _maxScale = 4.0;

  // Interaction state
  bool _isPanning = false;
  Offset? _panStart;
  Offset? _dragNodeStart;
  String? _draggingNodeId;
  String? _connectingFromNodeId;
  Offset? _connectingEndPoint;

  // Palette
  bool _showPalette = true;

  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_onProviderChanged);

    // Load presets if empty
    if (widget.provider.presets.isEmpty) {
      widget.provider.addPresets(StageFlowPresets.getAll());
    }
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  StageFlowProvider get _p => widget.provider;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                if (_showPalette) _buildPalette(),
                Expanded(child: _buildCanvas()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TOOLBAR ──────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      height: 40,
      color: const Color(0xFF1E1E2E),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _toolBtn(Icons.undo, 'Undo', _p.canUndo ? _p.undo : null),
          _toolBtn(Icons.redo, 'Redo', _p.canRedo ? _p.redo : null),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.white24),
          const SizedBox(width: 8),
          _toolBtn(
            _p.isDryRunning ? Icons.stop : Icons.play_arrow,
            _p.isDryRunning ? 'Stop' : 'Dry Run',
            _p.isDryRunning
                ? _p.cancelExecution
                : _p.hasGraph
                    ? () => _p.startDryRun()
                    : null,
          ),
          if (_p.isDryRunning) ...[
            _toolBtn(
              _p.isDryRunPaused ? Icons.play_arrow : Icons.pause,
              _p.isDryRunPaused ? 'Resume' : 'Pause',
              _p.isDryRunPaused ? _p.resumeDryRun : _p.pauseDryRun,
            ),
            _toolBtn(Icons.skip_next, 'Skip', () => _p.skipCurrentNode()),
          ],
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.white24),
          const SizedBox(width: 8),
          _toolBtn(Icons.check_circle_outline, 'Validate',
              _p.hasGraph ? () => _p.revalidate() : null),
          const Spacer(),
          // Preset selector
          if (_p.presets.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Presets',
              onSelected: _p.loadPreset,
              itemBuilder: (ctx) => _p.presets.map((p) {
                return PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(
                        p.isBuiltIn ? Icons.bookmark : Icons.bookmark_border,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Text(p.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_books, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      _p.activePresetId != null
                          ? _p.presets
                                  .where((p) => p.id == _p.activePresetId)
                                  .map((p) => p.name)
                                  .firstOrNull ??
                              'Presets'
                          : 'Presets',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Icon(Icons.arrow_drop_down,
                        size: 16, color: Colors.white70),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          _toolBtn(
            _showPalette ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            'Palette',
            () => setState(() => _showPalette = !_showPalette),
          ),
          const SizedBox(width: 4),
          // Validation status
          if (_p.hasErrors)
            const Tooltip(
              message: 'Validation errors',
              child: Icon(Icons.error, size: 16, color: Colors.redAccent),
            ),
          if (!_p.hasErrors && _p.hasWarnings)
            const Tooltip(
              message: 'Validation warnings',
              child: Icon(Icons.warning, size: 16, color: Colors.amber),
            ),
          if (!_p.hasErrors && !_p.hasWarnings && _p.hasGraph)
            const Tooltip(
              message: 'Valid',
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: 18,
              color: onPressed != null ? Colors.white70 : Colors.white24),
        ),
      ),
    );
  }

  // ─── PALETTE (LEFT PANEL) ─────────────────────────────────────────────

  Widget _buildPalette() {
    return Container(
      width: 160,
      color: const Color(0xFF1A1A2C),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _paletteSection('Logic', [
            _paletteItem('Gate', StageFlowNodeType.gate, Icons.call_split),
            _paletteItem('Fork', StageFlowNodeType.fork, Icons.fork_right),
            _paletteItem('Join', StageFlowNodeType.join, Icons.merge),
            _paletteItem('Delay', StageFlowNodeType.delay, Icons.timer),
            _paletteItem('Group', StageFlowNodeType.group, Icons.folder_open),
          ]),
          const SizedBox(height: 8),
          _paletteSection('Stages', _buildStagePaletteItems()),
        ],
      ),
    );
  }

  Widget _paletteSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(title,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        ...items,
      ],
    );
  }

  Widget _paletteItem(String label, StageFlowNodeType type, IconData icon) {
    return Draggable<_PaletteData>(
      data: _PaletteData(label, type, null),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.white54),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStagePaletteItems() {
    final service = widget.stageService;
    if (service == null) {
      // Fallback — show some common stages
      return [
        _paletteItem('WIN_PRESENT', StageFlowNodeType.stage, Icons.star),
        _paletteItem('ROLLUP_START', StageFlowNodeType.stage, Icons.trending_up),
        _paletteItem('WIN_LINE_SHOW', StageFlowNodeType.stage, Icons.linear_scale),
        _paletteItem('BIG_WIN_INTRO', StageFlowNodeType.stage, Icons.celebration),
      ];
    }

    final stages = service.getAllStages();
    return stages.take(20).map((def) {
      return Draggable<_PaletteData>(
        data: _PaletteData(def.name, StageFlowNodeType.stage, def.name),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color(def.category.color),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(def.name,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Color(def.category.color).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(def.name,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ),
      );
    }).toList();
  }

  // ─── CANVAS ───────────────────────────────────────────────────────────

  Widget _buildCanvas() {
    return DragTarget<_PaletteData>(
      onAcceptWithDetails: (details) {
        final data = details.data;
        // Convert screen position to canvas position
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.offset);
        final canvasPos =
            (local - _offset - Offset(_showPalette ? 160 : 0, 40)) / _scale;

        final nodeId = 'n_${DateTime.now().millisecondsSinceEpoch}';
        final stageId = data.stageId ?? data.label.toUpperCase().replaceAll(' ', '_');

        _p.addNode(StageFlowNode(
          id: nodeId,
          stageId: stageId,
          type: data.type,
          layer: FlowLayer.audioMapping,
          x: canvasPos.dx,
          y: canvasPos.dy,
        ));
      },
      builder: (context, candidateData, rejectedData) {
        return GestureDetector(
          onScaleStart: (d) {
            if (d.pointerCount == 2 || _isPanning) {
              _panStart = d.focalPoint - _offset;
            }
          },
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount == 2) {
                _scale = (_scale * d.scale).clamp(_minScale, _maxScale);
              }
              if (_panStart != null) {
                _offset = d.focalPoint - _panStart!;
              }
            });
          },
          onScaleEnd: (_) {
            _panStart = null;
            _isPanning = false;
          },
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == 4) {
                // Middle mouse → pan
                _isPanning = true;
                _panStart = e.position - _offset;
              }
            },
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(() {
                  final delta = e.scrollDelta.dy > 0 ? 0.9 : 1.1;
                  _scale = (_scale * delta).clamp(_minScale, _maxScale);
                });
              }
            },
            child: ClipRect(
              child: CustomPaint(
                painter: _CanvasPainter(
                  graph: _p.graph,
                  offset: _offset,
                  scale: _scale,
                  selectedNodeId: _p.selectedNodeId,
                  selectedNodeIds: _p.selectedNodeIds,
                  activeNodeId: _p.activeNodeId,
                  completedNodeIds: _p.completedNodeIds,
                  skippedNodeIds: _p.skippedNodeIds,
                  connectingFromNodeId: _connectingFromNodeId,
                  connectingEndPoint: _connectingEndPoint,
                  isDryRunning: _p.isDryRunning,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _onCanvasTapDown,
                  onPanStart: _onCanvasDragStart,
                  onPanUpdate: _onCanvasDragUpdate,
                  onPanEnd: _onCanvasDragEnd,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onCanvasTapDown(TapDownDetails details) {
    final canvasPos = _screenToCanvas(details.localPosition);
    final hitNode = _hitTestNode(canvasPos);

    if (hitNode != null) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isShift) {
        _p.toggleNodeSelection(hitNode.id);
      } else {
        _p.selectNode(hitNode.id);
      }
    } else {
      _p.clearSelection();
    }
  }

  void _onCanvasDragStart(DragStartDetails details) {
    final canvasPos = _screenToCanvas(details.localPosition);
    final hitNode = _hitTestNode(canvasPos);

    if (hitNode != null) {
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      if (isAlt) {
        // Alt+drag = connect
        _connectingFromNodeId = hitNode.id;
        _connectingEndPoint = canvasPos;
      } else {
        // Normal drag = move node
        _draggingNodeId = hitNode.id;
        _dragNodeStart = canvasPos;
        _p.selectNode(hitNode.id);
      }
    } else {
      _isPanning = true;
      _panStart = details.globalPosition - _offset;
    }
  }

  void _onCanvasDragUpdate(DragUpdateDetails details) {
    if (_draggingNodeId != null) {
      final canvasPos = _screenToCanvas(details.localPosition);
      _p.moveNode(_draggingNodeId!, canvasPos.dx, canvasPos.dy);
    } else if (_connectingFromNodeId != null) {
      setState(() {
        _connectingEndPoint = _screenToCanvas(details.localPosition);
      });
    } else if (_isPanning && _panStart != null) {
      setState(() {
        _offset = details.globalPosition - _panStart!;
      });
    }
  }

  void _onCanvasDragEnd(DragEndDetails details) {
    if (_connectingFromNodeId != null && _connectingEndPoint != null) {
      final hitNode = _hitTestNode(_connectingEndPoint!);
      if (hitNode != null && hitNode.id != _connectingFromNodeId) {
        final edgeId =
            'e_${DateTime.now().millisecondsSinceEpoch}';
        _p.addEdge(StageFlowEdge(
          id: edgeId,
          sourceNodeId: _connectingFromNodeId!,
          targetNodeId: hitNode.id,
        ));
      }
    }
    _draggingNodeId = null;
    _dragNodeStart = null;
    _connectingFromNodeId = null;
    _connectingEndPoint = null;
    _isPanning = false;
    _panStart = null;
  }

  Offset _screenToCanvas(Offset screen) {
    return (screen - _offset) / _scale;
  }

  StageFlowNode? _hitTestNode(Offset canvasPos) {
    if (_p.graph == null) return null;
    const nodeW = 140.0;
    const nodeH = 60.0;

    // Reverse order — top nodes first
    for (final node in _p.graph!.nodes.reversed) {
      final rect = Rect.fromLTWH(node.x, node.y, nodeW, nodeH);
      if (rect.contains(canvasPos)) return node;
    }
    return null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // EditableText guard
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final editable = primaryFocus.context!
          .findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Delete selected nodes
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      for (final id in _p.selectedNodeIds.toList()) {
        _p.removeNode(id);
      }
      return KeyEventResult.handled;
    }

    // Ctrl+Z / Ctrl+Shift+Z
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _p.redo();
      } else {
        _p.undo();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PALETTE DATA
// ═══════════════════════════════════════════════════════════════════════════

class _PaletteData {
  final String label;
  final StageFlowNodeType type;
  final String? stageId;

  const _PaletteData(this.label, this.type, this.stageId);
}

// ═══════════════════════════════════════════════════════════════════════════
// CANVAS PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _CanvasPainter extends CustomPainter {
  final StageFlowGraph? graph;
  final Offset offset;
  final double scale;
  final String? selectedNodeId;
  final Set<String> selectedNodeIds;
  final String? activeNodeId;
  final Set<String> completedNodeIds;
  final Set<String> skippedNodeIds;
  final String? connectingFromNodeId;
  final Offset? connectingEndPoint;
  final bool isDryRunning;

  static const double nodeW = 140;
  static const double nodeH = 60;

  _CanvasPainter({
    required this.graph,
    required this.offset,
    required this.scale,
    required this.selectedNodeId,
    required this.selectedNodeIds,
    required this.activeNodeId,
    required this.completedNodeIds,
    required this.skippedNodeIds,
    required this.connectingFromNodeId,
    required this.connectingEndPoint,
    required this.isDryRunning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // Draw grid
    _drawGrid(canvas, size);

    if (graph == null) {
      canvas.restore();
      return;
    }

    // Draw edges
    for (final edge in graph!.edges) {
      _drawEdge(canvas, edge);
    }

    // Draw connecting line
    if (connectingFromNodeId != null && connectingEndPoint != null) {
      final fromNode = graph!.getNode(connectingFromNodeId!);
      if (fromNode != null) {
        final start = Offset(fromNode.x + nodeW, fromNode.y + nodeH / 2);
        final paint = Paint()
          ..color = Colors.white38
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(start, connectingEndPoint!, paint);
      }
    }

    // Draw nodes
    for (final node in graph!.nodes) {
      _drawNode(canvas, node);
    }

    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A3E)
      ..strokeWidth = 0.5;

    const gridSize = 40.0;
    final visibleLeft = -offset.dx / scale;
    final visibleTop = -offset.dy / scale;
    final visibleRight = visibleLeft + size.width / scale;
    final visibleBottom = visibleTop + size.height / scale;

    final startX = (visibleLeft / gridSize).floor() * gridSize;
    final startY = (visibleTop / gridSize).floor() * gridSize;

    for (var x = startX; x <= visibleRight; x += gridSize) {
      canvas.drawLine(Offset(x, visibleTop), Offset(x, visibleBottom), gridPaint);
    }
    for (var y = startY; y <= visibleBottom; y += gridSize) {
      canvas.drawLine(Offset(visibleLeft, y), Offset(visibleRight, y), gridPaint);
    }
  }

  void _drawEdge(Canvas canvas, StageFlowEdge edge) {
    final source = graph!.getNode(edge.sourceNodeId);
    final target = graph!.getNode(edge.targetNodeId);
    if (source == null || target == null) return;

    final start = Offset(source.x + nodeW, source.y + nodeH / 2);
    final end = Offset(target.x, target.y + nodeH / 2);

    Color edgeColor;
    double strokeWidth = 2;
    List<double>? dashPattern;

    switch (edge.type) {
      case EdgeType.normal:
        edgeColor = const Color(0xFF666688);
        break;
      case EdgeType.onTrue:
        edgeColor = Colors.greenAccent;
        break;
      case EdgeType.onFalse:
        edgeColor = Colors.redAccent;
        dashPattern = [6, 4];
        break;
      case EdgeType.parallel:
        edgeColor = const Color(0xFF8888FF);
        strokeWidth = 3;
        break;
      case EdgeType.fallback:
        edgeColor = Colors.white38;
        dashPattern = [3, 3];
        break;
    }

    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Bezier curve for nice routing
    final midX = (start.dx + end.dx) / 2;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);

    if (dashPattern != null) {
      _drawDashedPath(canvas, path, paint, dashPattern);
    } else {
      canvas.drawPath(path, paint);
    }

    // Arrow head
    _drawArrowHead(canvas, end, edgeColor);
  }

  void _drawDashedPath(
      Canvas canvas, Path path, Paint paint, List<double> pattern) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      var drawPhase = true;
      var patternIdx = 0;
      while (distance < metric.length) {
        final len = pattern[patternIdx % pattern.length];
        final next = math.min(distance + len, metric.length);
        if (drawPhase) {
          final segment = metric.extractPath(distance, next);
          canvas.drawPath(segment, paint);
        }
        distance = next;
        drawPhase = !drawPhase;
        patternIdx++;
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Color color) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 8, tip.dy - 4)
      ..lineTo(tip.dx - 8, tip.dy + 4)
      ..close();
    canvas.drawPath(path, arrowPaint);
  }

  void _drawNode(Canvas canvas, StageFlowNode node) {
    final rect = Rect.fromLTWH(node.x, node.y, nodeW, nodeH);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Background
    Color bgColor = const Color(0xFF2A2A3E);
    Color borderColor = const Color(0xFF444466);

    // Type-based coloring
    switch (node.type) {
      case StageFlowNodeType.gate:
        bgColor = const Color(0xFF2A3E2A);
        borderColor = Colors.greenAccent.withValues(alpha: 0.5);
        break;
      case StageFlowNodeType.fork:
        bgColor = const Color(0xFF2A2A4E);
        borderColor = const Color(0xFF8888FF);
        break;
      case StageFlowNodeType.join:
        bgColor = const Color(0xFF2A2A4E);
        borderColor = const Color(0xFF8888FF);
        break;
      case StageFlowNodeType.delay:
        bgColor = const Color(0xFF3E3E2A);
        borderColor = Colors.amber.withValues(alpha: 0.5);
        break;
      default:
        break;
    }

    // Layer-based border
    if (node.layer == FlowLayer.engineCore) {
      borderColor = const Color(0xFF6688CC);
    }

    // Selection highlight
    final isSelected = selectedNodeIds.contains(node.id);
    if (isSelected) {
      borderColor = Colors.cyanAccent;
    }

    // Dry-run states
    if (isDryRunning) {
      if (activeNodeId == node.id) {
        borderColor = Colors.yellowAccent;
        bgColor = const Color(0xFF3E3E1A);
      } else if (completedNodeIds.contains(node.id)) {
        borderColor = Colors.green;
      } else if (skippedNodeIds.contains(node.id)) {
        bgColor = const Color(0xFF1A1A1A);
        borderColor = const Color(0xFF444444);
      }
    }

    // Draw shadow
    canvas.drawRRect(
      rrect.shift(const Offset(2, 2)),
      Paint()..color = Colors.black26,
    );

    // Draw fill
    canvas.drawRRect(rrect, Paint()..color = bgColor);

    // Draw border
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..strokeWidth = isSelected ? 2 : 1
        ..style = PaintingStyle.stroke,
    );

    // Draw text
    final tp = TextPainter(
      text: TextSpan(
        text: node.stageId,
        style: TextStyle(
          color: isDryRunning && skippedNodeIds.contains(node.id)
              ? Colors.white30
              : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    tp.layout(maxWidth: nodeW - 24);
    tp.paint(canvas, Offset(node.x + 8, node.y + 8));

    // Node type / timing info
    final infoTp = TextPainter(
      text: TextSpan(
        text: _nodeInfoText(node),
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    infoTp.layout(maxWidth: nodeW - 16);
    infoTp.paint(canvas, Offset(node.x + 8, node.y + 26));

    // Timing
    if (node.timing.durationMs > 0) {
      final timeTp = TextPainter(
        text: TextSpan(
          text: '${node.timing.delayMs}ms → ${node.timing.durationMs}ms',
          style: const TextStyle(color: Colors.white24, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      );
      timeTp.layout(maxWidth: nodeW - 16);
      timeTp.paint(canvas, Offset(node.x + 8, node.y + 42));
    }

    // Lock icon
    if (node.locked) {
      final lockTp = TextPainter(
        text: const TextSpan(
          text: '\u{1F512}',
          style: TextStyle(fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      lockTp.layout();
      lockTp.paint(canvas, Offset(node.x + nodeW - 18, node.y + 6));
    }

    // Ports (input/output circles)
    final portPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(node.x, node.y + nodeH / 2), 4, portPaint); // Input
    canvas.drawCircle(
        Offset(node.x + nodeW, node.y + nodeH / 2), 4, portPaint); // Output

    // Dry-run checkmark or skip indicator
    if (isDryRunning && completedNodeIds.contains(node.id)) {
      final checkPaint = Paint()
        ..color = Colors.greenAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(node.x + nodeW - 22, node.y + nodeH - 14),
          Offset(node.x + nodeW - 16, node.y + nodeH - 8), checkPaint);
      canvas.drawLine(Offset(node.x + nodeW - 16, node.y + nodeH - 8),
          Offset(node.x + nodeW - 8, node.y + nodeH - 20), checkPaint);
    }
  }

  String _nodeInfoText(StageFlowNode node) {
    return switch (node.type) {
      StageFlowNodeType.gate => 'gate: ${node.enterCondition ?? '?'}',
      StageFlowNodeType.fork => 'fork (parallel)',
      StageFlowNodeType.join => 'join (${node.joinMode.name})',
      StageFlowNodeType.delay => 'delay ${node.timing.delayMs}ms',
      StageFlowNodeType.group => 'group',
      StageFlowNodeType.stage => '[${node.layer.name}]',
    };
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return graph != oldDelegate.graph ||
        offset != oldDelegate.offset ||
        scale != oldDelegate.scale ||
        selectedNodeId != oldDelegate.selectedNodeId ||
        activeNodeId != oldDelegate.activeNodeId ||
        completedNodeIds != oldDelegate.completedNodeIds ||
        connectingEndPoint != oldDelegate.connectingEndPoint ||
        isDryRunning != oldDelegate.isDryRunning;
  }
}
