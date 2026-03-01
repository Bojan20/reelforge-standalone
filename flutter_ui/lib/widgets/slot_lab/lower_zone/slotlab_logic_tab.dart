/// SlotLab LOGIC Tab — Core Middleware Panels
///
/// Behavior, Triggers, Gate, Priority, Orchestration,
/// Emotional, Context, Simulation

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/behavior_tree_provider.dart';
import '../../../providers/slot_lab/state_gate_provider.dart';
import '../../../providers/slot_lab/trigger_layer_provider.dart';
import '../../../providers/slot_lab/priority_engine_provider.dart';
import '../../../providers/slot_lab/orchestration_engine_provider.dart';
import '../../../providers/slot_lab/emotional_state_provider.dart';
import '../../../providers/slot_lab/context_layer_provider.dart';
import '../../../providers/slot_lab/simulation_engine_provider.dart';
import '../../../providers/slot_lab/transition_system_provider.dart';
import '../../../providers/slot_lab/error_prevention_provider.dart';
import '../../../providers/slot_lab/behavior_coverage_provider.dart';
import '../../../providers/slot_lab/inspector_context_provider.dart';
import '../../../providers/slot_lab/smart_collapsing_provider.dart';
import '../../../providers/slot_lab/slotlab_notification_provider.dart';
import '../../../models/behavior_tree_models.dart';
import '../../lower_zone/lower_zone_types.dart';

class SlotLabLogicTabContent extends StatelessWidget {
  final SlotLabLogicSubTab subTab;

  const SlotLabLogicTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabLogicSubTab.behavior => const _BehaviorPanel(),
      SlotLabLogicSubTab.triggers => const _TriggersPanel(),
      SlotLabLogicSubTab.gate => const _GatePanel(),
      SlotLabLogicSubTab.priority => const _PriorityPanel(),
      SlotLabLogicSubTab.orchestration => const _OrchestrationPanel(),
      SlotLabLogicSubTab.emotional => const _EmotionalPanel(),
      SlotLabLogicSubTab.context => const _ContextPanel(),
      SlotLabLogicSubTab.simulation => const _SimulationPanel(),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BEHAVIOR — Tree view with select, inspect, coverage, collapsing
// ═══════════════════════════════════════════════════════════════════════════

class _BehaviorPanel extends StatelessWidget {
  const _BehaviorPanel();

  @override
  Widget build(BuildContext context) {
    final tree = GetIt.instance<BehaviorTreeProvider>();
    final coverage = GetIt.instance<BehaviorCoverageProvider>();
    final inspector = GetIt.instance<InspectorContextProvider>();
    final collapsing = GetIt.instance<SmartCollapsingProvider>();

    return ListenableBuilder(
      listenable: Listenable.merge([tree, coverage, collapsing]),
      builder: (context, _) {
        final nodes = tree.tree.nodes;
        final covPct = tree.coveragePercent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Behavior Tree',
              '${nodes.length} nodes — ${(covPct * 100).toStringAsFixed(0)}% coverage',
              actions: [
                _headerBtn(Icons.unfold_less, 'Collapse All', () => collapsing.collapseAll()),
                _headerBtn(Icons.unfold_more, 'Expand All', () => collapsing.expandAll()),
                _headerBtn(Icons.restart_alt, 'Reset States', () => tree.resetAllNodeStates()),
              ],
            ),
            Expanded(
              child: nodes.isEmpty
                  ? _emptyState('No behavior nodes defined')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: BehaviorCategory.values.length,
                      itemBuilder: (ctx, catIdx) {
                        final cat = BehaviorCategory.values[catIdx];
                        final catNodes = nodes.values.where((n) => n.category == cat).toList();
                        if (catNodes.isEmpty) return const SizedBox.shrink();
                        final isCollapsed = collapsing.isCategoryCollapsed(cat);
                        final catCoverage = tree.coverageByCategory[cat];
                        return _CategorySection(
                          category: cat,
                          nodes: catNodes,
                          isCollapsed: isCollapsed,
                          coveragePct: catCoverage?.percent ?? 0,
                          selectedNodeId: tree.selectedNodeId,
                          onToggleCollapse: () => collapsing.toggleCategory(cat),
                          onSelectNode: (node) {
                            tree.selectNode(node.id);
                            inspector.selectNode(node.id, node);
                          },
                          onMarkVerified: (nodeId) {
                            coverage.markVerified(nodeId, 'manual');
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CategorySection extends StatelessWidget {
  final BehaviorCategory category;
  final List<BehaviorNode> nodes;
  final bool isCollapsed;
  final double coveragePct;
  final String? selectedNodeId;
  final VoidCallback onToggleCollapse;
  final ValueChanged<BehaviorNode> onSelectNode;
  final ValueChanged<String> onMarkVerified;

  const _CategorySection({
    required this.category,
    required this.nodes,
    required this.isCollapsed,
    required this.coveragePct,
    required this.selectedNodeId,
    required this.onToggleCollapse,
    required this.onSelectNode,
    required this.onMarkVerified,
  });

  @override
  Widget build(BuildContext context) {
    final color = _catColor(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggleCollapse,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              children: [
                Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more, size: 12, color: color),
                const SizedBox(width: 2),
                Text(category.displayName, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const Spacer(),
                Text('${nodes.length}', style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 9)),
                const SizedBox(width: 6),
                _coverageDot(coveragePct),
              ],
            ),
          ),
        ),
        if (!isCollapsed) ...nodes.map((n) => _InteractiveNodeRow(
          node: n,
          isSelected: n.id == selectedNodeId,
          onSelect: () => onSelectNode(n),
          onMarkVerified: () => onMarkVerified(n.id),
        )),
      ],
    );
  }

  Widget _coverageDot(double pct) {
    final color = pct >= 0.8 ? const Color(0xFF40FF90) : pct >= 0.5 ? const Color(0xFFFFD700) : const Color(0xFFFF4060);
    return Container(
      width: 6, height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Color _catColor(BehaviorCategory cat) => switch (cat) {
    BehaviorCategory.reels => const Color(0xFF40C8FF),
    BehaviorCategory.cascade => const Color(0xFF9370DB),
    BehaviorCategory.win => const Color(0xFFFFD700),
    BehaviorCategory.feature => const Color(0xFF40FF90),
    BehaviorCategory.jackpot => const Color(0xFFFF4060),
    BehaviorCategory.ui => const Color(0xFF9E9E9E),
    BehaviorCategory.system => const Color(0xFF607D8B),
  };
}

class _InteractiveNodeRow extends StatelessWidget {
  final BehaviorNode node;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onMarkVerified;

  const _InteractiveNodeRow({
    required this.node,
    required this.isSelected,
    required this.onSelect,
    required this.onMarkVerified,
  });

  @override
  Widget build(BuildContext context) {
    final hasSounds = node.hasAudio;
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(left: 12, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: isSelected
            ? BoxDecoration(color: const Color(0xFF40C8FF).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2))
            : null,
        child: Row(
          children: [
            Icon(hasSounds ? Icons.volume_up : Icons.volume_off, size: 10, color: hasSounds ? const Color(0xFF40FF90) : Colors.white24),
            const SizedBox(width: 4),
            Expanded(child: Text(node.nodeType.displayName, style: TextStyle(color: isSelected ? const Color(0xFF40C8FF) : Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
            Text(node.basicParams.priorityClass.name, style: const TextStyle(color: Colors.white30, fontSize: 9)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onMarkVerified,
              child: const Icon(Icons.verified_outlined, size: 10, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGERS — AutoBind toggle, enable/disable, binding management
// ═══════════════════════════════════════════════════════════════════════════

class _TriggersPanel extends StatelessWidget {
  const _TriggersPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<TriggerLayerProvider>();
    final notif = GetIt.instance<SlotLabNotificationProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final bindings = provider.bindings.values.toList();
        final unbound = provider.unboundHooks;
        final autoEnabled = provider.autoBindingsEnabled;
        final history = provider.history;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Trigger Bindings',
              '${bindings.length} hooks — ${history.length} fired',
              actions: [
                _toggleChip('Auto', autoEnabled, (v) => provider.setAutoBindingsEnabled(v)),
                const SizedBox(width: 4),
                _headerBtn(Icons.auto_fix_high, 'Generate', () {
                  provider.generateAutoBindings();
                  final bound = provider.bindings.length;
                  notif.pushAutoBindResult(bound, unbound.length, 0);
                }),
                _headerBtn(Icons.clear_all, 'Clear Log', () => provider.clearHistory()),
                _headerBtn(Icons.delete_sweep, 'Clear All', () => provider.clearAllBindings()),
              ],
            ),
            // Bindings list
            Expanded(
              flex: 3,
              child: bindings.isEmpty
                  ? _emptyState('No trigger bindings\nTap Generate to auto-create')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: bindings.length,
                      itemBuilder: (ctx, i) {
                        final b = bindings[i];
                        // Check if this hook recently fired
                        final recentlyFired = history.isNotEmpty && history.last.hookName == b.hookName;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              // Toggle enable/disable
                              GestureDetector(
                                onTap: () => provider.setBindingEnabled(b.hookName, !b.enabled),
                                child: Icon(b.enabled ? Icons.link : Icons.link_off, size: 10, color: b.enabled ? const Color(0xFF40C8FF) : Colors.white24),
                              ),
                              const SizedBox(width: 4),
                              if (recentlyFired)
                                Container(
                                  width: 4, height: 4, margin: const EdgeInsets.only(right: 3),
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF40FF90)),
                                ),
                              Expanded(child: Text(b.hookName, style: TextStyle(color: recentlyFired ? const Color(0xFF40FF90) : (b.enabled ? Colors.white70 : Colors.white30), fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                              Text('→ ${b.targetNodeIds.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              if (b.delayMs > 0)
                                Padding(padding: const EdgeInsets.only(left: 4), child: Text('+${b.delayMs}ms', style: const TextStyle(color: Colors.orangeAccent, fontSize: 9))),
                              const SizedBox(width: 4),
                              // Remove binding
                              GestureDetector(
                                onTap: () => provider.removeBinding(b.hookName),
                                child: const Icon(Icons.close, size: 10, color: Colors.white24),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // Resolution history — real-time hook firings
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
              child: Text('Resolution Log (${history.length})', style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
            ),
            Expanded(
              flex: 2,
              child: history.isEmpty
                  ? _emptyState('No resolutions yet')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: history.length.clamp(0, 30),
                      itemBuilder: (ctx, i) {
                        final r = history[history.length - 1 - i];
                        final activated = r.activatedNodeIds.isNotEmpty;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Row(
                            children: [
                              Icon(activated ? Icons.check_circle : Icons.radio_button_unchecked, size: 10, color: activated ? const Color(0xFF40FF90) : Colors.white24),
                              const SizedBox(width: 4),
                              Expanded(child: Text(r.hookName, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                              Text('${r.activatedNodeIds.length} nodes', style: TextStyle(color: activated ? const Color(0xFF40C8FF) : Colors.white24, fontSize: 9)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // Unbound hooks indicator
            if (unbound.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                child: Text('${unbound.length} unbound: ${unbound.take(3).join(", ")}${unbound.length > 3 ? "..." : ""}',
                    style: const TextStyle(color: Color(0xFFFF9040), fontSize: 9)),
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GATE — State transitions, autoplay/turbo, volatility
// ═══════════════════════════════════════════════════════════════════════════

class _GatePanel extends StatelessWidget {
  const _GatePanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<StateGateProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final current = provider.currentSubstate;
        final history = provider.history;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'State Gate',
              'Current: ${current.displayName}',
              actions: [
                _toggleChip('Auto', provider.isAutoplay, (v) => provider.setAutoplay(v)),
                const SizedBox(width: 2),
                _toggleChip('Turbo', provider.isTurbo, (v) => provider.setTurbo(v)),
                const SizedBox(width: 2),
                _headerBtn(Icons.restart_alt, 'Reset', () {
                  provider.resetToIdle();
                  provider.clearHistory();
                }),
              ],
            ),
            // State chips — clickable for transitions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: GameplaySubstate.values.map((s) {
                  final isCurrent = s == current;
                  return GestureDetector(
                    onTap: isCurrent ? null : () => provider.transitionTo(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF40FF90).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(3),
                        border: isCurrent ? Border.all(color: const Color(0xFF40FF90), width: 1) : null,
                      ),
                      child: Text(s.name, style: TextStyle(color: isCurrent ? const Color(0xFF40FF90) : Colors.white54, fontSize: 10)),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Volatility slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Text('Volatility', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Expanded(
                    child: SliderTheme(
                      data: _compactSlider(const Color(0xFFFF9040)),
                      child: Slider(
                        value: provider.volatilityIndex,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (v) => provider.setVolatilityIndex(v),
                      ),
                    ),
                  ),
                  Text('${(provider.volatilityIndex * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFFFF9040), fontSize: 10)),
                ],
              ),
            ),
            // Blocked/passed counts + last hook indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text('Passed: ${provider.passedCount}', style: const TextStyle(color: Color(0xFF40FF90), fontSize: 10)),
                  const SizedBox(width: 12),
                  Text('Blocked: ${provider.blockedCount}', style: const TextStyle(color: Color(0xFFFF4060), fontSize: 10)),
                  const Spacer(),
                  if (history.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: history.last.result.allowed ? const Color(0xFF40FF90) : const Color(0xFFFF4060),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(history.last.hookName, style: TextStyle(
                          color: history.last.result.allowed ? const Color(0xFF40FF90) : const Color(0xFFFF4060),
                          fontSize: 9, fontFamily: 'monospace',
                        )),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Gate check history
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                itemCount: history.length.clamp(0, 50),
                itemBuilder: (ctx, i) {
                  final entry = history[history.length - 1 - i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Row(
                      children: [
                        Icon(entry.result.allowed ? Icons.check : Icons.block, size: 10, color: entry.result.allowed ? const Color(0xFF40FF90) : const Color(0xFFFF4060)),
                        const SizedBox(width: 4),
                        Expanded(child: Text(entry.hookName, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                        Text(entry.substate.name, style: const TextStyle(color: Colors.white30, fontSize: 9)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIORITY — Active behaviors, conflict log, clear
// ═══════════════════════════════════════════════════════════════════════════

class _PriorityPanel extends StatelessWidget {
  const _PriorityPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<PriorityEngineProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final active = provider.activeBehaviors;
        final history = provider.resolutionLog;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Priority Engine',
              '${active.length} active — ${history.length} resolutions',
              actions: [
                _headerBtn(Icons.clear_all, 'Clear Log', () => provider.clearLog()),
                _headerBtn(Icons.delete_forever, 'Clear All', () => provider.clearAll()),
              ],
            ),
            // Active behaviors
            if (active.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    ...active.values.map((ab) => Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Row(
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _priorityClassColor(ab.priorityClass))),
                          const SizedBox(width: 4),
                          Expanded(child: Text(ab.nodeId, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                          Text(ab.priorityClass.name, style: TextStyle(color: _priorityClassColor(ab.priorityClass), fontSize: 9)),
                          const SizedBox(width: 4),
                          if (ab.currentGain < 1.0)
                            Text('${(20 * _log10(ab.currentGain)).toStringAsFixed(1)}dB', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => provider.removeBehavior(ab.nodeId),
                            child: const Icon(Icons.close, size: 10, color: Colors.white24),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            // Resolution log
            Expanded(
              child: history.isEmpty
                  ? _emptyState('No priority resolutions')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: history.length.clamp(0, 50),
                      itemBuilder: (ctx, i) {
                        final res = history[history.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _actionColor(res.action))),
                              const SizedBox(width: 4),
                              Expanded(child: Text('${res.winnerId} > ${res.loserId}', style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                              Text(res.action.name, style: TextStyle(color: _actionColor(res.action), fontSize: 10)),
                              if (res.action == PriorityConflictAction.duck)
                                Text(' ${res.duckAmountDb.toStringAsFixed(0)}dB', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Color _priorityClassColor(BehaviorPriorityClass pc) => switch (pc) {
    BehaviorPriorityClass.critical => const Color(0xFFFF4060),
    BehaviorPriorityClass.core => const Color(0xFFFF6040),
    BehaviorPriorityClass.high => const Color(0xFFFF9040),
    BehaviorPriorityClass.medium => const Color(0xFFFFD700),
    BehaviorPriorityClass.low => const Color(0xFF40C8FF),
    BehaviorPriorityClass.ambient => const Color(0xFF607D8B),
  };

  Color _actionColor(PriorityConflictAction action) => switch (action) {
    PriorityConflictAction.duck => const Color(0xFFFFD700),
    PriorityConflictAction.delay => const Color(0xFFFF9040),
    PriorityConflictAction.suppress => const Color(0xFFFF4060),
  };

  static double _log10(double x) => x > 0 ? 0.4342944819032518 * _ln(x) : -100;
  static double _ln(double x) {
    if (x <= 0) return -100;
    // Simple ln approximation for display only
    double result = 0;
    double term = (x - 1) / (x + 1);
    double power = term;
    for (int i = 0; i < 20; i++) {
      result += power / (2 * i + 1);
      power *= term * term;
    }
    return 2 * result;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ORCHESTRATION — Context sliders, decisions
// ═══════════════════════════════════════════════════════════════════════════

class _OrchestrationPanel extends StatelessWidget {
  const _OrchestrationPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<OrchestrationEngineProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final ctx = provider.context;
        final decisions = provider.decisions;
        final diagLog = provider.diagnosticLog;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Orchestration',
              '${decisions.length} decisions — ${diagLog.length} logged',
              actions: [
                _headerBtn(Icons.clear_all, 'Clear Log', () => provider.clearLog()),
                _headerBtn(Icons.delete_sweep, 'Clear Decisions', () => provider.clearDecisions()),
              ],
            ),
            // Context parameter sliders
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Column(
                children: [
                  _contextSlider('Escalation', ctx.escalationIndex, 0.0, 1.0, const Color(0xFFFF4060), (v) {
                    provider.updateEscalation(index: v);
                  }),
                  _contextSlider('Chain Depth', ctx.chainDepth.toDouble(), 0, 10, const Color(0xFF9370DB), (v) {
                    provider.updateEscalation(chainDepth: v.round());
                  }),
                  _contextSlider('Win Magnitude', ctx.winMagnitude, 0.0, 100.0, const Color(0xFFFFD700), (v) {
                    provider.updateEscalation(winMagnitude: v);
                  }),
                ],
              ),
            ),
            // Active decisions
            Expanded(
              flex: 3,
              child: decisions.isEmpty
                  ? _emptyState('No orchestration decisions')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      itemCount: decisions.length,
                      itemBuilder: (ctx, i) {
                        final d = decisions.values.elementAt(i);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: d.suppressed ? const Color(0xFFFF4060).withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (d.suppressed)
                                      const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.volume_off, size: 10, color: Color(0xFFFF4060))),
                                    Expanded(child: Text(d.nodeId, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                    if (d.triggerDelayMs > 0) Text('+${d.triggerDelayMs}ms', style: const TextStyle(color: Colors.orangeAccent, fontSize: 9)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    _miniBar('Gain', d.gainBiasDb, -12, 6, const Color(0xFF40FF90)),
                                    const SizedBox(width: 6),
                                    _miniBar('Width', d.stereoWidthScale, 0, 2, const Color(0xFF40C8FF)),
                                    const SizedBox(width: 6),
                                    _miniBar('Pan', d.spatialBias, -1, 1, const Color(0xFF9370DB)),
                                    const SizedBox(width: 6),
                                    _miniBar('Trans', d.transientShaping, -1, 1, const Color(0xFFFFD700)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Diagnostic log — real-time orchestration events
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
              child: Text('Decision Log (${diagLog.length})', style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
            ),
            Expanded(
              flex: 2,
              child: diagLog.isEmpty
                  ? _emptyState('No decisions logged')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: diagLog.length.clamp(0, 20),
                      itemBuilder: (ctx, i) {
                        final entry = diagLog[diagLog.length - 1 - i];
                        final d = entry.decision;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Row(
                            children: [
                              Icon(d.suppressed ? Icons.volume_off : Icons.volume_up, size: 10,
                                color: d.suppressed ? const Color(0xFFFF4060) : const Color(0xFF40FF90)),
                              const SizedBox(width: 4),
                              Expanded(child: Text(entry.nodeId, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                              Text('${d.gainBiasDb > 0 ? "+" : ""}${d.gainBiasDb.toStringAsFixed(1)}dB', style: TextStyle(
                                color: d.gainBiasDb > 0 ? const Color(0xFF40FF90) : (d.gainBiasDb < 0 ? const Color(0xFFFF4060) : Colors.white30),
                                fontSize: 9,
                              )),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                decoration: BoxDecoration(color: _emotionLogColor(entry.emotionalState).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
                                child: Text(entry.emotionalState.name, style: TextStyle(color: _emotionLogColor(entry.emotionalState), fontSize: 8)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Color _emotionLogColor(EmotionalState s) => switch (s) {
    EmotionalState.neutral => const Color(0xFF9E9E9E),
    EmotionalState.build => const Color(0xFF40C8FF),
    EmotionalState.tension => const Color(0xFFFF9040),
    EmotionalState.nearWin => const Color(0xFFFFD700),
    EmotionalState.release => const Color(0xFF40FF90),
    EmotionalState.peak => const Color(0xFFFF4060),
    EmotionalState.afterglow => const Color(0xFF9370DB),
    EmotionalState.recovery => const Color(0xFF607D8B),
  };

  Widget _contextSlider(String label, double value, double min, double max, Color color, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10))),
          Expanded(
            child: SliderTheme(
              data: _compactSlider(color),
              child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
            ),
          ),
          SizedBox(width: 32, child: Text(value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1), style: TextStyle(color: color, fontSize: 10), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _miniBar(String label, double value, double min, double max, Color color) {
    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(1)}', style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9)),
          const SizedBox(height: 1),
          Container(
            height: 3,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(1)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMOTIONAL — Manual event triggers, output meters, reset
// ═══════════════════════════════════════════════════════════════════════════

class _EmotionalPanel extends StatelessWidget {
  const _EmotionalPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<EmotionalStateProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final state = provider.state;
        final output = provider.output;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Emotional State',
              state.name,
              actions: [
                _headerBtn(Icons.restart_alt, 'Reset', () => provider.reset()),
              ],
            ),
            // State display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: EmotionalState.values.map((s) {
                  final isCurrent = s == state;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent ? _emotionColor(s).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(3),
                      border: isCurrent ? Border.all(color: _emotionColor(s), width: 1) : null,
                    ),
                    child: Text(s.name, style: TextStyle(color: isCurrent ? _emotionColor(s) : Colors.white38, fontSize: 10)),
                  );
                }).toList(),
              ),
            ),
            // Output meters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _miniMeter('Intensity', output.intensity, const Color(0xFFFF4060)),
                  const SizedBox(width: 6),
                  _miniMeter('Tension', output.tension, const Color(0xFFFF9040)),
                  const SizedBox(width: 6),
                  _miniMeter('Width', (output.stereoWidthMod - 1.0).clamp(0.0, 1.0), const Color(0xFF40C8FF)),
                  const SizedBox(width: 6),
                  _miniMeter('Shimmer', output.hfShimmer, const Color(0xFFFFD700)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // History stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${provider.spinHistory.length} spins | ${provider.consecutiveLossCount} loss streak | cascade: ${provider.cascadeDepth}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
            const SizedBox(height: 4),
            // Manual event trigger buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Text('Test:', style: TextStyle(color: Colors.white38, fontSize: 9)),
                  const SizedBox(width: 4),
                  _eventBtn('Spin', const Color(0xFF40C8FF), () {
                    provider.onSpinStart();
                    provider.onSpinResult(winAmount: 0, betAmount: 1.0);
                  }),
                  _eventBtn('Win', const Color(0xFF40FF90), () {
                    provider.onSpinResult(winAmount: 10, betAmount: 1.0, multiplier: 10);
                  }),
                  _eventBtn('Cascade', const Color(0xFF9370DB), () {
                    provider.onCascadeStart();
                    provider.onCascadeStep(1);
                  }),
                  _eventBtn('Big Win', const Color(0xFFFFD700), () {
                    provider.onBigWin(3);
                  }),
                  _eventBtn('Antic', const Color(0xFFFF9040), () {
                    provider.onAnticipation(2);
                  }),
                  _eventBtn('Tick', const Color(0xFF607D8B), () {
                    provider.tick(0.5);
                  }),
                ],
              ),
            ),
            const Spacer(),
          ],
        );
      },
    );
  }

  Widget _eventBtn(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
          child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _miniMeter(String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9)),
          const SizedBox(height: 2),
          Container(
            height: 4,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ],
      ),
    );
  }

  Color _emotionColor(EmotionalState s) => switch (s) {
    EmotionalState.neutral => const Color(0xFF9E9E9E),
    EmotionalState.build => const Color(0xFF40C8FF),
    EmotionalState.tension => const Color(0xFFFF9040),
    EmotionalState.nearWin => const Color(0xFFFFD700),
    EmotionalState.release => const Color(0xFF40FF90),
    EmotionalState.peak => const Color(0xFFFF4060),
    EmotionalState.afterglow => const Color(0xFF9370DB),
    EmotionalState.recovery => const Color(0xFF607D8B),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT — Game mode selector + per-node override management
// ═══════════════════════════════════════════════════════════════════════════

class _ContextPanel extends StatelessWidget {
  const _ContextPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<ContextLayerProvider>();
    final tree = GetIt.instance<BehaviorTreeProvider>();
    return ListenableBuilder(
      listenable: Listenable.merge([provider, tree]),
      builder: (context, _) {
        final mode = provider.currentMode;
        final selectedId = tree.selectedNodeId;
        final nodes = tree.tree.nodes;
        // Count total overrides
        int totalOverrides = 0;
        for (final nodeId in nodes.keys) {
          totalOverrides += provider.getOverrideCount(nodeId);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Context Layer',
              'Mode: ${mode.name} — $totalOverrides overrides',
              actions: [
                _headerBtn(Icons.delete_sweep, 'Clear All', () => provider.clearAll()),
              ],
            ),
            // Mode selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: GameMode.values.map((m) {
                  final isCurrent = m == mode;
                  return GestureDetector(
                    onTap: () => provider.setCurrentMode(m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF40C8FF).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(3),
                        border: isCurrent ? Border.all(color: const Color(0xFF40C8FF), width: 1) : null,
                      ),
                      child: Text(m.name, style: TextStyle(color: isCurrent ? const Color(0xFF40C8FF) : Colors.white54, fontSize: 10)),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Node overrides for current mode
            Expanded(
              child: selectedId != null
                  ? _NodeOverrideView(nodeId: selectedId, mode: mode, provider: provider)
                  : _OverrideSummary(nodes: nodes, mode: mode, provider: provider),
            ),
          ],
        );
      },
    );
  }
}

class _NodeOverrideView extends StatelessWidget {
  final String nodeId;
  final GameMode mode;
  final ContextLayerProvider provider;

  const _NodeOverrideView({required this.nodeId, required this.mode, required this.provider});

  @override
  Widget build(BuildContext context) {
    final ovr = provider.getCurrentOverride(nodeId);
    final hasOverride = ovr != null && ovr.hasOverrides;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 10, color: hasOverride ? const Color(0xFF40C8FF) : Colors.white38),
              const SizedBox(width: 4),
              Expanded(child: Text('Overrides for "$nodeId" in ${mode.name}', style: const TextStyle(color: Colors.white54, fontSize: 10))),
              if (hasOverride)
                GestureDetector(
                  onTap: () => provider.removeOverride(nodeId, mode),
                  child: const Icon(Icons.close, size: 10, color: Colors.white38),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (hasOverride) ...[
            if (ovr.gainDb != null) Text('  Gain: ${ovr.gainDb!.toStringAsFixed(1)} dB', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            if (ovr.priority != null) Text('  Priority: ${ovr.priority}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            if (ovr.playbackMode != null) Text('  Playback: ${ovr.playbackMode!.name}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            if (ovr.stereoWidth != null) Text('  Stereo Width: ${ovr.stereoWidth!.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            if (ovr.active != null) Text('  Active: ${ovr.active}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () {
                  provider.setOverride(ContextOverrideSet(
                    behaviorNodeId: nodeId,
                    gameMode: mode,
                    gainDb: 0,
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('+ Add Override', style: TextStyle(color: Colors.white38, fontSize: 10)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverrideSummary extends StatelessWidget {
  final Map<String, BehaviorNode> nodes;
  final GameMode mode;
  final ContextLayerProvider provider;

  const _OverrideSummary({required this.nodes, required this.mode, required this.provider});

  @override
  Widget build(BuildContext context) {
    final nodesWithOverrides = nodes.keys.where((id) => provider.hasOverrides(id)).toList();
    if (nodesWithOverrides.isEmpty) {
      return _emptyState('No context overrides\nSelect a node in Behavior tab to add');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: nodesWithOverrides.length,
      itemBuilder: (ctx, i) {
        final nodeId = nodesWithOverrides[i];
        final count = provider.getOverrideCount(nodeId);
        final hasForMode = provider.getOverride(nodeId, mode) != null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Icon(Icons.tune, size: 10, color: hasForMode ? const Color(0xFF40C8FF) : Colors.white24),
              const SizedBox(width: 4),
              Expanded(child: Text(nodeId, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
              Text('$count modes', style: const TextStyle(color: Colors.white38, fontSize: 10)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => provider.removeAllOverrides(nodeId),
                child: const Icon(Icons.close, size: 10, color: Colors.white24),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIMULATION — Run/step/stop, validation, transition rules
// ═══════════════════════════════════════════════════════════════════════════

class _SimulationPanel extends StatelessWidget {
  const _SimulationPanel();

  @override
  Widget build(BuildContext context) {
    final sim = GetIt.instance<SimulationEngineProvider>();
    final transition = GetIt.instance<TransitionSystemProvider>();
    final errors = GetIt.instance<ErrorPreventionProvider>();
    final tree = GetIt.instance<BehaviorTreeProvider>();
    return ListenableBuilder(
      listenable: Listenable.merge([sim, transition, errors]),
      builder: (context, _) {
        final isRunning = sim.isRunning;
        final errorCount = errors.errorCount;
        final warnCount = errors.warningCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerWithActions(
              'Simulation & Validation',
              isRunning ? '${(sim.progress * 100).toStringAsFixed(0)}% (${sim.currentStep}/${sim.totalSteps})' : 'Mode: ${sim.mode.name}',
              actions: [
                // Validate button
                _headerBtn(
                  errors.isClean ? Icons.check_circle : Icons.warning,
                  'Validate',
                  () => errors.validate(tree.tree),
                  color: errors.isClean ? const Color(0xFF40FF90) : (errorCount > 0 ? const Color(0xFFFF4060) : const Color(0xFFFFD700)),
                ),
                // Run/Stop/Step controls
                if (!isRunning) ...[
                  _headerBtn(Icons.play_arrow, 'Run', () => sim.start(), color: const Color(0xFF40FF90)),
                  _headerBtn(Icons.skip_next, 'Step', () => sim.step()),
                ] else ...[
                  _headerBtn(Icons.stop, 'Stop', () => sim.stop(), color: const Color(0xFFFF4060)),
                ],
                _headerBtn(Icons.restart_alt, 'Reset', () => sim.reset()),
              ],
            ),
            // Simulation mode selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: SimulationMode.values.map((m) {
                  final isCurrent = m == sim.mode;
                  return GestureDetector(
                    onTap: isRunning ? null : () => sim.setMode(m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF9370DB).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(3),
                        border: isCurrent ? Border.all(color: const Color(0xFF9370DB), width: 1) : null,
                      ),
                      child: Text(m.name, style: TextStyle(color: isCurrent ? const Color(0xFF9370DB) : Colors.white54, fontSize: 10)),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Validation summary
            if (errors.issues.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    if (errorCount > 0) ...[
                      Icon(Icons.error, size: 10, color: const Color(0xFFFF4060)),
                      const SizedBox(width: 2),
                      Text('$errorCount errors', style: const TextStyle(color: Color(0xFFFF4060), fontSize: 10)),
                      const SizedBox(width: 8),
                    ],
                    if (warnCount > 0) ...[
                      Icon(Icons.warning, size: 10, color: const Color(0xFFFFD700)),
                      const SizedBox(width: 2),
                      Text('$warnCount warnings', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10)),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: () => errors.clearIssues(),
                      child: const Text('Clear', style: TextStyle(color: Colors.white38, fontSize: 9)),
                    ),
                  ],
                ),
              ),
            // Transition rules count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text('Transition rules: ${transition.allRules.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  const Spacer(),
                  if (transition.isTransitioning)
                    Text('Transitioning ${(transition.activeTransition!.progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Color(0xFF9370DB), fontSize: 10)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => transition.resetDefaults(),
                    child: const Text('Reset Rules', style: TextStyle(color: Colors.white38, fontSize: 9)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Results list
            Expanded(
              child: sim.history.isEmpty
                  ? _emptyState('No simulation results\nSelect a mode and tap Run')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      itemCount: sim.history.length.clamp(0, 20),
                      itemBuilder: (ctx, i) {
                        final r = sim.history[sim.history.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Icon(r.warnings.isEmpty ? Icons.check_circle : Icons.warning, size: 10, color: r.warnings.isEmpty ? const Color(0xFF40FF90) : const Color(0xFFFF9040)),
                              const SizedBox(width: 4),
                              Expanded(child: Text('${r.mode.name} — ${r.totalSpins} spins', style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                              Text('${r.hooksFired} hooks', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              if (r.gateBlocks > 0)
                                Padding(padding: const EdgeInsets.only(left: 4), child: Text('${r.gateBlocks}blk', style: const TextStyle(color: Color(0xFFFF4060), fontSize: 9))),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═══════════════════════════════════════════════════════════════════════════

Widget _headerWithActions(String title, String subtitle, {List<Widget> actions = const []}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
    child: Row(
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Expanded(child: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10), overflow: TextOverflow.ellipsis)),
        ...actions,
      ],
    ),
  );
}

Widget _headerBtn(IconData icon, String tooltip, VoidCallback onTap, {Color color = Colors.white38}) {
  return Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    ),
  );
}

Widget _toggleChip(String label, bool value, ValueChanged<bool> onChanged) {
  return GestureDetector(
    onTap: () => onChanged(!value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF40FF90).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: value ? const Color(0xFF40FF90).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: value ? const Color(0xFF40FF90) : Colors.white38, fontSize: 9, fontWeight: FontWeight.w600)),
    ),
  );
}

Widget _emptyState(String message) {
  return Center(child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white24, fontSize: 11)));
}

SliderThemeData _compactSlider(Color color) {
  return SliderThemeData(
    trackHeight: 2,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
    activeTrackColor: color,
    inactiveTrackColor: color.withValues(alpha: 0.15),
    thumbColor: color,
    overlayColor: color.withValues(alpha: 0.1),
  );
}
