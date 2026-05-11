// HELIX dock — FLOW panel (Sprint 15 Faza 4.C split #1).
//
// Extracted from `helix_screen.dart` on 2026-05-11 as the first concrete
// step of the monolith-split refactor.  Lives as a `part` of helix_screen
// so all `_`-private helpers (HxModeDef, _DockCard, _DockLabel, theme
// shortcuts, GetIt accessors, etc.) stay accessible without exporting
// new public API.
//
// Content (all classes private to helix_screen library scope):
//   • `_FlowPanel`         — StatefulWidget root for the FLOW dock tab
//   • `_FlowPanelState`    — game-flow FSM visualization + force transitions
//   • `_FlowGraphNode`     — render-only node DTO
//   • `_FlowGraphEdge`     — render-only edge DTO
//   • `_FlowGraphPainter`  — CustomPainter for nodes + bezier edges
//
// Why this file exists:
//   `helix_screen.dart` was 14013 LOC; the audit (2026-05-10 Sprint 14)
//   flagged this monolith as the biggest technical-debt risk.  Splitting
//   13 dock panels into one part-file each cuts the root file by ~80 %
//   while keeping all existing privates accessible.  This file is the
//   blueprint other panels follow.

part of '../../helix_screen.dart';

class _FlowPanel extends StatefulWidget {
  const _FlowPanel();

  @override
  State<_FlowPanel> createState() => _FlowPanelState();
}

class _FlowPanelState extends State<_FlowPanel> {
  String? _hoveredNode;
  String? _selectedNode;
  int _flowSubTab = 0; // 0=Stage Flow, 1=Feature Composer

  // ── Static graph definition ────────────────────────────────────────────────
  static const _nodes = <_FlowGraphNode>[
    _FlowGraphNode(id: 'idle',    label: 'IDLE',      icon: Icons.pause_circle_outline,  color: Color(0xFF666688), state: GameFlowState.idle,              pos: Offset(0.04, 0.50)),
    _FlowGraphNode(id: 'base',    label: 'BASE',      icon: Icons.play_arrow_rounded,     color: Color(0xFF4D9FFF), state: GameFlowState.baseGame,          pos: Offset(0.30, 0.50)),
    _FlowGraphNode(id: 'win',     label: 'WIN',       icon: Icons.attach_money_rounded,   color: Color(0xFF5CFF9D), state: null,                            pos: Offset(0.54, 0.14)),
    _FlowGraphNode(id: 'cascade', label: 'CASCADE',   icon: Icons.waterfall_chart,        color: Color(0xFF00E5FF), state: GameFlowState.cascading,         pos: Offset(0.54, 0.38)),
    _FlowGraphNode(id: 'free',    label: 'FREE',      icon: Icons.star_rounded,           color: Color(0xFFFFE033), state: GameFlowState.freeSpins,         pos: Offset(0.54, 0.62)),
    _FlowGraphNode(id: 'bonus',   label: 'BONUS',     icon: Icons.casino_rounded,         color: Color(0xFFAA66FF), state: GameFlowState.bonusGame,         pos: Offset(0.54, 0.86)),
    _FlowGraphNode(id: 'jackpot', label: 'JACKPOT',   icon: Icons.emoji_events_rounded,   color: Color(0xFFFF9900), state: GameFlowState.jackpotPresentation,pos: Offset(0.80, 0.14)),
    _FlowGraphNode(id: 'hold',    label: 'HOLD&WIN',  icon: Icons.lock_rounded,           color: Color(0xFFFF6644), state: GameFlowState.holdAndWin,        pos: Offset(0.80, 0.86)),
  ];

  static const _edges = <_FlowGraphEdge>[
    // Forward: IDLE → BASE
    _FlowGraphEdge(from: 'idle',    to: 'base',    curveDir:  0.0),
    // BASE branches
    _FlowGraphEdge(from: 'base',    to: 'win',     curveDir: -0.3),
    _FlowGraphEdge(from: 'base',    to: 'cascade', curveDir:  0.0),
    _FlowGraphEdge(from: 'base',    to: 'free',    curveDir:  0.0),
    _FlowGraphEdge(from: 'base',    to: 'bonus',   curveDir:  0.3),
    _FlowGraphEdge(from: 'base',    to: 'jackpot', curveDir: -0.5),
    // WIN → IDLE (return arc above)
    _FlowGraphEdge(from: 'win',     to: 'idle',    curveDir: -0.45, dashed: true),
    // Feature returns to BASE (dashed)
    _FlowGraphEdge(from: 'cascade', to: 'base',    curveDir:  0.35, dashed: true),
    _FlowGraphEdge(from: 'free',    to: 'base',    curveDir:  0.45, dashed: true),
    // BONUS → HOLD&WIN → BASE
    _FlowGraphEdge(from: 'bonus',   to: 'hold',    curveDir:  0.0),
    _FlowGraphEdge(from: 'hold',    to: 'base',    curveDir:  0.55, dashed: true),
    // JACKPOT → IDLE (return arc)
    _FlowGraphEdge(from: 'jackpot', to: 'idle',    curveDir: -0.6, dashed: true),
  ];

  String? _activeId(GameFlowState s) {
    for (final n in _nodes) {
      if (n.state == s) return n.id;
    }
    return null;
  }

  void _tapNode(_FlowGraphNode node, GameFlowProvider flow) {
    setState(() => _selectedNode = node.id);
    if (node.state != null) {
      silentRun('flowGraph.forceTransition', () { flow.forceTransition(node.state!); });
    } else if (node.id == 'win') {
      // WIN has no state — trigger WIN_PRESENT_1 stage directly
      silentRun('flowGraph.triggerWinPresent', () { EventRegistry.instance.triggerStage('WIN_PRESENT_1'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Sub-tab switcher: STAGE FLOW | FEATURES
      SizedBox(
        height: 22,
        child: Row(children: [
          _flowSubTabButton('STAGE FLOW', 0, Icons.account_tree_rounded),
          const SizedBox(width: 4),
          _flowSubTabButton('FEATURES', 1, Icons.extension_rounded),
          const Spacer(),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(child: _flowSubTab == 0 ? _buildStageFlow(context) : _buildFeatureComposer()),
    ]);
  }

  Widget _flowSubTabButton(String label, int idx, IconData icon) {
    final active = _flowSubTab == idx;
    return GestureDetector(
      onTap: () => setState(() => _flowSubTab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentBlue.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle)),
        child: Row(children: [
          Icon(icon, size: 10, color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary),
          const SizedBox(width: 4),
          Text(label, style: FluxForgeTheme.dockMono(size: 8,
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
            weight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _buildFeatureComposer() {
    final fc = GetIt.instance<FeatureComposerProvider>();
    return ListenableBuilder(
      listenable: fc,
      builder: (_, _) {
        final mechanics = fc.mechanicStates;
        final stages = fc.composedStages;
        final coreCount = fc.coreStageCount;
        final featureCount = fc.featureStageCount;

        return Row(children: [
          // Left: Mechanic toggles
          Flexible(
            flex: 2,
            child: _DockCard(
              accent: FluxForgeTheme.accentPurple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _DockLabel('MECHANICS', color: FluxForgeTheme.accentPurple),
                    const Spacer(),
                    // Preset buttons
                    _featurePresetBtn('BASIC', () => fc.presetBasic()),
                    const SizedBox(width: 4),
                    _featurePresetBtn('STD', () => fc.presetStandard()),
                    const SizedBox(width: 4),
                    _featurePresetBtn('FULL', () => fc.presetFull()),
                  ]),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      children: mechanics.entries.map((e) {
                        final mechanic = e.key;
                        final enabled = e.value;
                        return GestureDetector(
                          onTap: () => fc.toggleMechanic(mechanic),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            margin: const EdgeInsets.only(bottom: 3),
                            decoration: BoxDecoration(
                              color: enabled
                                  ? _mechanicColor(mechanic).withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: enabled
                                    ? _mechanicColor(mechanic).withValues(alpha: 0.4)
                                    : FluxForgeTheme.borderSubtle)),
                            child: Row(children: [
                              Icon(
                                enabled ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: 13,
                                color: enabled ? _mechanicColor(mechanic) : FluxForgeTheme.textTertiary),
                              const SizedBox(width: 6),
                              Icon(_mechanicIcon(mechanic), size: 12,
                                color: enabled ? _mechanicColor(mechanic) : FluxForgeTheme.textTertiary),
                              const SizedBox(width: 6),
                              Expanded(child: Text(
                                _mechanicLabel(mechanic),
                                style: FluxForgeTheme.dockMono(size: 9,
                                  color: enabled ? _mechanicColor(mechanic) : FluxForgeTheme.textTertiary,
                                  weight: enabled ? FontWeight.w600 : FontWeight.normal),
                              )),
                              if (enabled) ...[
                                // Stage count badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _mechanicColor(mechanic).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3)),
                                  child: Text(
                                    '${fc.stagesByMechanic[mechanic]?.length ?? 0}',
                                    style: FluxForgeTheme.dockMono(size: 7,
                                      color: _mechanicColor(mechanic))),
                                ),
                              ],
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Summary
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(4)),
                    child: Row(children: [
                      Text('$coreCount core', style: FluxForgeTheme.dockMono(
                        size: 8, color: FluxForgeTheme.accentCyan)),
                      Text(' + ', style: FluxForgeTheme.dockMono(
                        size: 8, color: FluxForgeTheme.textTertiary)),
                      Text('$featureCount feature', style: FluxForgeTheme.dockMono(
                        size: 8, color: FluxForgeTheme.accentPurple)),
                      Text(' = ', style: FluxForgeTheme.dockMono(
                        size: 8, color: FluxForgeTheme.textTertiary)),
                      Text('${stages.length} stages', style: FluxForgeTheme.dockMono(
                        size: 8, color: FluxForgeTheme.accentYellow,
                        weight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Right: Composed stages list
          Expanded(
            flex: 3,
            child: _DockCard(
              accent: FluxForgeTheme.accentYellow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _DockLabel('COMPOSED STAGES', color: FluxForgeTheme.accentYellow),
                    const Spacer(),
                    Text('${stages.length} total',
                      style: FluxForgeTheme.dockMono(size: 8,
                        color: FluxForgeTheme.textTertiary)),
                  ]),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      itemCount: stages.length,
                      itemBuilder: (_, i) {
                        final stage = stages[i];
                        final isCore = stage.layer == StageLayer.engineCore;
                        final isAlways = stage.layer == StageLayer.alwaysVisible;
                        final color = isCore
                            ? FluxForgeTheme.accentCyan
                            : isAlways
                                ? FluxForgeTheme.textTertiary
                                : stage.mechanic != null
                                    ? _mechanicColor(stage.mechanic!)
                                    : FluxForgeTheme.accentPurple;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: color.withValues(alpha: 0.15))),
                          child: Row(children: [
                            // Layer indicator
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: isCore ? 0.8 : 0.5),
                                shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            // Stage name
                            Expanded(child: Text(
                              stage.displayName,
                              style: FluxForgeTheme.dockMono(size: 9,
                                color: color, weight: isCore ? FontWeight.w600 : FontWeight.normal),
                              overflow: TextOverflow.ellipsis)),
                            // Bus badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: FluxForgeTheme.bgDeep,
                                borderRadius: BorderRadius.circular(2)),
                              child: Text(stage.suggestedBus.toUpperCase(),
                                style: FluxForgeTheme.dockMono(size: 6,
                                  color: FluxForgeTheme.textTertiary)),
                            ),
                            const SizedBox(width: 4),
                            // Priority badge
                            Text(stage.priority,
                              style: FluxForgeTheme.dockMono(size: 7,
                                color: stage.priority == 'P0' ? FluxForgeTheme.accentRed
                                    : stage.priority == 'P1' ? FluxForgeTheme.accentYellow
                                    : FluxForgeTheme.textTertiary)),
                            if (stage.locked) ...[
                              const SizedBox(width: 3),
                              Icon(Icons.lock_rounded, size: 8, color: color.withValues(alpha: 0.4)),
                            ],
                          ]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _featurePresetBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.borderSubtle)),
        child: Text(label, style: FluxForgeTheme.dockMono(size: 7,
          color: FluxForgeTheme.textTertiary, weight: FontWeight.w600)),
      ),
    );
  }

  Color _mechanicColor(SlotMechanic m) => switch (m) {
    SlotMechanic.cascading      => const Color(0xFF00E5FF),
    SlotMechanic.freeSpins      => const Color(0xFFFFE033),
    SlotMechanic.holdAndWin     => const Color(0xFFFF6644),
    SlotMechanic.pickBonus      => const Color(0xFFAA66FF),
    SlotMechanic.wheelBonus     => const Color(0xFFFF9900),
    SlotMechanic.jackpot        => const Color(0xFFFFD700),
    SlotMechanic.gamble         => const Color(0xFFFF4466),
    SlotMechanic.megaways       => const Color(0xFF44FF88),
    SlotMechanic.nudgeRespin    => const Color(0xFF6699FF),
    SlotMechanic.expandingWilds => const Color(0xFF88FF44),
    SlotMechanic.stickyWilds    => const Color(0xFFFF88CC),
    SlotMechanic.multiplierTrail => const Color(0xFFFFAA33),
  };

  IconData _mechanicIcon(SlotMechanic m) => switch (m) {
    SlotMechanic.cascading      => Icons.waterfall_chart,
    SlotMechanic.freeSpins      => Icons.star_rounded,
    SlotMechanic.holdAndWin     => Icons.lock_rounded,
    SlotMechanic.pickBonus      => Icons.touch_app_rounded,
    SlotMechanic.wheelBonus     => Icons.circle_outlined,
    SlotMechanic.jackpot        => Icons.emoji_events_rounded,
    SlotMechanic.gamble         => Icons.casino_rounded,
    SlotMechanic.megaways       => Icons.grid_view_rounded,
    SlotMechanic.nudgeRespin    => Icons.swap_vert_rounded,
    SlotMechanic.expandingWilds => Icons.open_in_full_rounded,
    SlotMechanic.stickyWilds    => Icons.push_pin_rounded,
    SlotMechanic.multiplierTrail => Icons.trending_up_rounded,
  };

  String _mechanicLabel(SlotMechanic m) => switch (m) {
    SlotMechanic.cascading      => 'Cascading',
    SlotMechanic.freeSpins      => 'Free Spins',
    SlotMechanic.holdAndWin     => 'Hold & Win',
    SlotMechanic.pickBonus      => 'Pick Bonus',
    SlotMechanic.wheelBonus     => 'Wheel Bonus',
    SlotMechanic.jackpot        => 'Jackpot',
    SlotMechanic.gamble         => 'Gamble',
    SlotMechanic.megaways       => 'Megaways',
    SlotMechanic.nudgeRespin    => 'Nudge/Respin',
    SlotMechanic.expandingWilds => 'Expanding Wilds',
    SlotMechanic.stickyWilds    => 'Sticky Wilds',
    SlotMechanic.multiplierTrail => 'Multiplier Trail',
  };

  Widget _buildStageFlow(BuildContext context) {
    return Consumer<GameFlowProvider>(
      builder: (_, flow, _) {
        final activeId = _activeId(flow.currentState);
        final mw = GetIt.instance<MiddlewareProvider>();

        // Build stage → audio map for detail panel
        final stageAudio = <String, List<String>>{};
        for (final e in mw.compositeEvents) {
          for (final stage in e.triggerStages) {
            stageAudio.putIfAbsent(stage.toUpperCase(), () => []).add(e.name);
          }
        }

        // Selected node audio list
        final selNode = _selectedNode != null
            ? _nodes.where((n) => n.id == _selectedNode).firstOrNull
            : null;
        final selAudio = selNode != null ? (stageAudio[selNode.label] ?? []) : <String>[];

        return Row(children: [
          // ── Graph canvas ────────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: _DockCard(
              accent: FluxForgeTheme.accentBlue,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _DockLabel('STAGE FLOW', color: FluxForgeTheme.accentBlue),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2035),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF333355)),
                    ),
                    child: Text('CLICK NODE TO FORCE STATE',
                      style: FluxForgeTheme.dockMono(size: 7,
                        color: FluxForgeTheme.textTertiary, letterSpacing: 0.5)),
                  ),
                ]),
                const SizedBox(height: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      return Stack(clipBehavior: Clip.none, children: [
                        // Edges layer (CustomPaint)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _FlowGraphPainter(
                              nodes: _nodes,
                              edges: _edges,
                              size: Size(w, h),
                              activeId: activeId,
                              hoveredId: _hoveredNode,
                              selectedId: _selectedNode,
                            ),
                          ),
                        ),
                        // Node widgets
                        ..._nodes.map((node) {
                          final isActive = node.id == activeId;
                          final isSelected = node.id == _selectedNode;
                          final isHovered = node.id == _hoveredNode;
                          final x = node.pos.dx * w;
                          final y = node.pos.dy * h;
                          return Positioned(
                            left: x - 24,
                            top: y - 18,
                            child: MouseRegion(
                              onEnter: (_) => setState(() => _hoveredNode = node.id),
                              onExit: (_) => setState(() {
                                if (_hoveredNode == node.id) _hoveredNode = null;
                              }),
                              child: GestureDetector(
                                onTap: () => _tapNode(node, flow),
                                child: AnimatedContainer(
                                  duration: FluxMotion.quick,
                                  width: 48,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isActive
                                      ? node.color.withValues(alpha: 0.22)
                                      : isSelected
                                        ? node.color.withValues(alpha: 0.14)
                                        : isHovered
                                          ? node.color.withValues(alpha: 0.10)
                                          : const Color(0xFF0D0D18),
                                    border: Border.all(
                                      color: isActive
                                        ? node.color
                                        : isSelected
                                          ? node.color.withValues(alpha: 0.7)
                                          : isHovered
                                            ? node.color.withValues(alpha: 0.5)
                                            : node.color.withValues(alpha: 0.25),
                                      width: isActive ? 1.5 : 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: isActive ? [
                                      BoxShadow(color: node.color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 0),
                                    ] : null,
                                  ),
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(node.icon, size: 11,
                                      color: isActive ? node.color : node.color.withValues(alpha: 0.7)),
                                    const SizedBox(height: 2),
                                    Text(node.label,
                                      style: FluxForgeTheme.dockMono(
                                        size: 6.5,
                                        color: isActive ? node.color : node.color.withValues(alpha: 0.7),
                                        weight: isActive ? FontWeight.w700 : FontWeight.w500,
                                        letterSpacing: 0.2),
                                      overflow: TextOverflow.ellipsis),
                                  ]),
                                ),
                              ),
                            ),
                          );
                        }),
                      ]);
                    },
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          // ── Detail panel ─────────────────────────────────────────────────
          SizedBox(
            width: 180,
            child: _DockCard(
              accent: FluxForgeTheme.accentBlue,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DockLabel('NODE DETAIL', color: FluxForgeTheme.accentBlue),
                const SizedBox(height: 8),
                if (selNode == null) ...[
                  Expanded(
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.touch_app_rounded, size: 20,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3)),
                        const SizedBox(height: 6),
                        Text('Tap a node', style: FluxForgeTheme.dockSans(
                          size: 9, color: FluxForgeTheme.textTertiary)),
                      ]),
                    ),
                  ),
                ] else ...[
                  // Node name + color bar
                  Row(children: [
                    Container(width: 3, height: 24, decoration: BoxDecoration(
                      color: selNode.color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(selNode.label, style: FluxForgeTheme.dockMono(
                        size: 11,
                        color: selNode.color, weight: FontWeight.w700)),
                      Text(selNode.state?.displayName ?? 'event trigger',
                        style: FluxForgeTheme.dockSans(size: 8, color: FluxForgeTheme.textTertiary)),
                    ])),
                  ]),
                  const SizedBox(height: 8),
                  // Current state badge
                  if (selNode.id == _activeId(flow.currentState))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selNode.color.withValues(alpha: 0.1),
                        border: Border.all(color: selNode.color.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(4)),
                      child: Text('● ACTIVE NOW',
                        style: FluxForgeTheme.dockMono(size: 8, color: selNode.color)),
                    ),
                  // Audio events
                  Text('AUDIO EVENTS', style: FluxForgeTheme.dockMono(
                    size: 7.5,
                    color: FluxForgeTheme.textTertiary, letterSpacing: 1.0)),
                  const SizedBox(height: 4),
                  if (selAudio.isEmpty)
                    Text('No audio assigned',
                      style: FluxForgeTheme.dockSans(size: 8, color: FluxForgeTheme.textTertiary))
                  else
                    Expanded(
                      child: ListView(children: selAudio.map((name) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(Icons.music_note_rounded, size: 8, color: FluxForgeTheme.accentCyan),
                          const SizedBox(width: 4),
                          Expanded(child: Text(name, style: FluxForgeTheme.dockMono(
                            size: 8,
                            color: FluxForgeTheme.textSecondary),
                            overflow: TextOverflow.ellipsis)),
                        ]),
                      )).toList()),
                    ),
                  const SizedBox(height: 6),
                  // Force state button
                  if (selNode.state != null)
                    GestureDetector(
                      onTap: () => _tapNode(selNode, flow),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: selNode.color.withValues(alpha: 0.1),
                          border: Border.all(color: selNode.color.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text('⚡ FORCE STATE',
                          textAlign: TextAlign.center,
                          style: FluxForgeTheme.dockMono(size: 8,
                            color: selNode.color, weight: FontWeight.w600)),
                      ),
                    ),
                ],
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

// ── Flow graph data types ─────────────────────────────────────────────────────

class _FlowGraphNode {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final GameFlowState? state;
  final Offset pos; // 0.0-1.0 normalized

  const _FlowGraphNode({
    required this.id, required this.label, required this.icon,
    required this.color, required this.state, required this.pos,
  });
}

class _FlowGraphEdge {
  final String from;
  final String to;
  final double curveDir; // positive = arc below, negative = arc above
  final bool dashed;

  const _FlowGraphEdge({required this.from, required this.to, this.curveDir = 0.0, this.dashed = false});
}

// ── Flow graph CustomPainter ──────────────────────────────────────────────────

class _FlowGraphPainter extends CustomPainter {
  final List<_FlowGraphNode> nodes;
  final List<_FlowGraphEdge> edges;
  final Size size;
  final String? activeId;
  final String? hoveredId;
  final String? selectedId;

  const _FlowGraphPainter({
    required this.nodes, required this.edges, required this.size,
    this.activeId, this.hoveredId, this.selectedId,
  });

  Offset _nodeCenter(String id) {
    final n = nodes.firstWhere((n) => n.id == id, orElse: () => nodes.first);
    return Offset(n.pos.dx * size.width, n.pos.dy * size.height);
  }

  Color _nodeColor(String id) {
    final n = nodes.firstWhere((n) => n.id == id, orElse: () => nodes.first);
    return n.color;
  }

  @override
  void paint(Canvas canvas, Size sz) {
    for (final edge in edges) {
      final fromC = _nodeCenter(edge.from);
      final toC = _nodeCenter(edge.to);
      final color = _nodeColor(edge.from);
      final isHighlighted = edge.from == activeId || edge.from == hoveredId || edge.from == selectedId
                         || edge.to   == activeId || edge.to   == hoveredId || edge.to   == selectedId;

      final paint = Paint()
        ..color = isHighlighted ? color.withValues(alpha: 0.7) : const Color(0xFF2A2A44)
        ..strokeWidth = isHighlighted ? 1.5 : 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Control points for bezier — perpendicular offset scales with curveDir
      final mid = (fromC + toC) / 2;
      final dx = toC.dx - fromC.dx;
      final dy = toC.dy - fromC.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      final perp = len > 0
          ? Offset(-dy / len * len * edge.curveDir, dx / len * len * edge.curveDir)
          : Offset.zero;
      final cp1 = mid + perp * 0.6;
      final cp2 = mid + perp * 0.6;

      final path = Path()
        ..moveTo(fromC.dx, fromC.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, toC.dx, toC.dy);

      if (edge.dashed) {
        _drawDashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      // Arrowhead at toC — direction from cp2 to toC
      final dir = (toC - cp2);
      final dirLen = dir.distance;
      if (dirLen > 0) {
        final unit = dir / dirLen;
        _drawArrow(canvas, toC, unit, paint..color = paint.color);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, Offset dir, Paint paint) {
    const arrowLen = 6.0;
    const arrowWid = 3.5;
    final left = Offset(-dir.dy, dir.dx);
    final p1 = tip - dir * arrowLen + left * arrowWid;
    final p2 = tip - dir * arrowLen - left * arrowWid;
    final arrowPath = Path()..moveTo(tip.dx, tip.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close();
    canvas.drawPath(arrowPath, Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashLen = 5.0;
    const gapLen = 4.0;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double dist = 0;
      bool drawing = true;
      while (dist < metric.length) {
        final seg = drawing ? dashLen : gapLen;
        if (drawing) {
          final extracted = metric.extractPath(dist, math.min(dist + seg, metric.length));
          canvas.drawPath(extracted, paint);
        }
        dist += seg;
        drawing = !drawing;
      }
    }
  }

  @override
  bool shouldRepaint(_FlowGraphPainter old) =>
    old.activeId != activeId || old.hoveredId != hoveredId || old.selectedId != selectedId;
}
