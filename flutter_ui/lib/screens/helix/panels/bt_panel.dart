// HELIX dock — Behavior Tree visual editor panel (Sprint 15 Faza 4.C split #3).
//
// 22 BT node types across 5 categories (Composite, Decorator, Action,
// Condition, Audio).  Visual canvas with drag-to-position, click-to-connect,
// bezier edge rendering, node palette, delete.
//
// Extracted from `helix_screen.dart` 2026-05-11 — part of monolith split.
//
// Content:
//   • `_BehaviorTreePanel(State)` — root widget + canvas state
//   • `_BtConnectionPainter`       — CustomPainter za bezier edges

part of '../../helix_screen.dart';

// ── 3.2 Behavior Tree Visual Editor ─────────────────────────────────────────

class _BehaviorTreePanel extends StatefulWidget {
  const _BehaviorTreePanel();
  @override
  State<_BehaviorTreePanel> createState() => _BehaviorTreePanelState();
}

class _BehaviorTreePanelState extends State<_BehaviorTreePanel> {
  // Node types from architecture: 22 types across 5 categories
  static const _nodeCategories = {
    'COMPOSITE': [
      ('Sequence', Icons.arrow_forward_rounded, 'Execute children L→R, fail on first fail'),
      ('Selector', Icons.call_split_rounded, 'Execute children L→R, succeed on first success'),
      ('Parallel', Icons.view_column_rounded, 'Execute all children simultaneously'),
      ('RandomSelector', Icons.shuffle_rounded, 'Pick random child to execute'),
      ('WeightedSelector', Icons.balance_rounded, 'Pick child by weighted probability'),
    ],
    'DECORATOR': [
      ('Inverter', Icons.swap_vert_rounded, 'Invert child result'),
      ('Repeater', Icons.repeat_rounded, 'Repeat child N times'),
      ('UntilFail', Icons.block_rounded, 'Repeat child until it fails'),
      ('Timeout', Icons.timer_rounded, 'Fail if child exceeds time limit'),
      ('Cooldown', Icons.hourglass_empty_rounded, 'Delay between executions'),
      ('Guard', Icons.shield_rounded, 'Conditional execution gate'),
    ],
    'ACTION': [
      ('PlayAudio', Icons.volume_up_rounded, 'Trigger composite event playback'),
      ('StopAudio', Icons.stop_rounded, 'Stop event playback'),
      ('SetRTPC', Icons.tune_rounded, 'Set RTPC parameter value'),
      ('TransitionStage', Icons.swap_horiz_rounded, 'Force game stage transition'),
      ('Wait', Icons.schedule_rounded, 'Wait for duration'),
      ('LogMessage', Icons.message_rounded, 'Log debug message'),
    ],
    'CONDITION': [
      ('IsStage', Icons.flag_rounded, 'Check if game is in target stage'),
      ('RTPCCheck', Icons.analytics_rounded, 'Compare RTPC value'),
      ('PlayerState', Icons.person_rounded, 'Check player behavior state'),
      ('RandomChance', Icons.casino_rounded, 'Succeed with probability P'),
    ],
    'AUDIO': [
      ('CrossFade', Icons.compare_arrows_rounded, 'Crossfade between two events'),
    ],
  };

  String _selectedCategory = 'COMPOSITE';
  late final HelixBtCanvasProvider _canvas;

  @override
  void initState() {
    super.initState();
    _canvas = GetIt.instance<HelixBtCanvasProvider>();
    _canvas.addListener(_onCanvasChanged);
  }

  @override
  void dispose() {
    _canvas.removeListener(_onCanvasChanged);
    super.dispose();
  }

  void _onCanvasChanged() {
    if (mounted) setState(() {});
  }

  void _addNode(String category, String name) {
    _canvas.addNode(category, name);
  }

  void _deleteSelectedNode() {
    final sel = _canvas.selectedNodeId;
    if (sel == null) return;
    _canvas.deleteNode(sel);
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _canvas.nodes;
    final edges = _canvas.edges;
    final selectedId = _canvas.selectedNodeId;

    return Row(
      children: [
        // Left: Node palette
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentOrange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('NODE PALETTE', color: FluxForgeTheme.accentOrange),
                  const Spacer(),
                  if (nodes.isNotEmpty)
                    GestureDetector(
                      onTap: () => _canvas.autoLayout(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: const Text('AUTO', style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                          color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  const SizedBox(width: 4),
                  if (nodes.isNotEmpty)
                    GestureDetector(
                      onTap: () => _canvas.clear(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentPink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: const Text('CLEAR', style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                          color: FluxForgeTheme.accentPink, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                // Category tabs
                SizedBox(
                  height: 24,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _nodeCategories.keys.map((cat) {
                      final catColor = _categoryColor(cat);
                      final isActive = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: isActive ? catColor.withValues(alpha: 0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive ? catColor.withValues(alpha: 0.55) : FluxForgeTheme.borderSubtle,
                            ),
                          ),
                          child: Text(cat, style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                            color: isActive ? catColor : FluxForgeTheme.textTertiary,
                            fontWeight: FontWeight.w600)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // Node list for selected category
                Expanded(
                  child: ListView(
                    children: (_nodeCategories[_selectedCategory] ?? []).map((node) {
                      final (name, icon, desc) = node;
                      return GestureDetector(
                        onTap: () => _addNode(_selectedCategory, name),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: FluxForgeTheme.borderSubtle),
                          ),
                          child: Row(children: [
                            Icon(icon, size: 14, color: _categoryColor(_selectedCategory)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                                  color: _categoryColor(_selectedCategory), fontWeight: FontWeight.w600)),
                                Text(desc, style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                                  color: FluxForgeTheme.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            const Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.textTertiary),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Center: Canvas area
        Expanded(
          flex: 4,
          child: _DockCard(
            accent: FluxForgeTheme.accentOrange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DockLabel('BEHAVIOR TREE CANVAS', color: FluxForgeTheme.accentOrange),
                  if (_canvas.isDirty) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentYellow,
                        shape: BoxShape.circle)),
                  ],
                  const Spacer(),
                  Text('${nodes.length} nodes  ${edges.length} edges',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
                  const SizedBox(width: 12),
                  if (selectedId != null)
                    GestureDetector(
                      onTap: _deleteSelectedNode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentPink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: const Text('DELETE', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: FluxForgeTheme.accentPink, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      color: FluxForgeTheme.bgVoid,
                      child: nodes.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.hub_rounded, size: 48, color: FluxForgeTheme.accentOrange.withValues(alpha: 0.15)),
                            const SizedBox(height: 12),
                            const Text('Click a node in the palette to add it',
                              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                            const SizedBox(height: 4),
                            Text('Click two nodes to connect them',
                              style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6))),
                          ]))
                        : CustomPaint(
                            painter: _BtConnectionPainter(nodes, edges),
                            child: Stack(
                              children: nodes.map((node) {
                                final selected = selectedId == node.id;
                                return Positioned(
                                  left: node.position.dx,
                                  top: node.position.dy,
                                  child: GestureDetector(
                                    onTap: () {
                                      if (selectedId != null && selectedId != node.id) {
                                        _canvas.connect(selectedId, node.id);
                                      }
                                      _canvas.selectNode(node.id);
                                    },
                                    onPanUpdate: (d) {
                                      _canvas.moveNode(node.id, d.delta);
                                    },
                                    child: Container(
                                      width: 100, height: 44,
                                      decoration: BoxDecoration(
                                        color: _categoryColor(node.category).withValues(alpha: selected ? 0.2 : 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected ? _categoryColor(node.category) : _categoryColor(node.category).withValues(alpha: 0.4),
                                          width: selected ? 2 : 1),
                                      ),
                                      child: Center(child: Text(node.name,
                                        style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                                          color: _categoryColor(node.category), fontWeight: FontWeight.w600),
                                        textAlign: TextAlign.center)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _categoryColor(String cat) => switch (cat) {
    'COMPOSITE' => FluxForgeTheme.accentBlue,
    'DECORATOR' => FluxForgeTheme.accentPurple,
    'ACTION'    => FluxForgeTheme.accentGreen,
    'CONDITION' => FluxForgeTheme.accentYellow,
    'AUDIO'     => FluxForgeTheme.accentCyan,
    _ => FluxForgeTheme.textTertiary,
  };
}

class _BtConnectionPainter extends CustomPainter {
  final List<BtCanvasNode> nodes;
  final Set<BtCanvasEdge> edges;
  final int _nodeHash;
  final int _edgeHash;
  _BtConnectionPainter(this.nodes, this.edges)
    : _nodeHash = Object.hashAll(nodes.map((n) => Object.hash(n.id, n.position.dx, n.position.dy))),
      _edgeHash = Object.hashAll(edges.map((e) => Object.hash(e.fromId, e.toId)));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.accentOrange.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final fromNode = nodes.where((n) => n.id == edge.fromId).firstOrNull;
      final toNode = nodes.where((n) => n.id == edge.toId).firstOrNull;
      if (fromNode != null && toNode != null) {
        final from = fromNode.position + const Offset(50, 44);
        final to = toNode.position + const Offset(50, 0);
        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(from.dx, from.dy + 30, to.dx, to.dy - 30, to.dx, to.dy);
        canvas.drawPath(path, paint);
        // Arrow head
        final arrow = Paint()..color = FluxForgeTheme.accentOrange.withValues(alpha: 0.5)..style = PaintingStyle.fill;
        canvas.drawPath(
          Path()..moveTo(to.dx, to.dy)..lineTo(to.dx - 4, to.dy - 6)..lineTo(to.dx + 4, to.dy - 6)..close(),
          arrow,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BtConnectionPainter old) =>
    old._nodeHash != _nodeHash || old._edgeHash != _edgeHash;
}
