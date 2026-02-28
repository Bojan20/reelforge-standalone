/// SlotLab Middleware Tab — Lower Zone Sub-Tab Content
///
/// Compact panels for all middleware providers:
/// - Behavior: Tree view with coverage stats
/// - Triggers: Hook→Node binding list
/// - Gate: State machine with current substate
/// - Priority: Active resolutions + conflict log
/// - Orchestration: Current decisions + emotion-aware shaping
/// - Emotional: State + decay meter + spin memory
/// - Context: Game mode overrides
/// - Simulation: Mode selector + results

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
import '../../../models/behavior_tree_models.dart';
import '../../lower_zone/lower_zone_types.dart';

class SlotLabMiddlewareTabContent extends StatelessWidget {
  final SlotLabMiddlewareSubTab subTab;

  const SlotLabMiddlewareTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabMiddlewareSubTab.behavior => const _BehaviorPanel(),
      SlotLabMiddlewareSubTab.triggers => const _TriggersPanel(),
      SlotLabMiddlewareSubTab.gate => const _GatePanel(),
      SlotLabMiddlewareSubTab.priority => const _PriorityPanel(),
      SlotLabMiddlewareSubTab.orchestration => const _OrchestrationPanel(),
      SlotLabMiddlewareSubTab.emotional => const _EmotionalPanel(),
      SlotLabMiddlewareSubTab.context => const _ContextPanel(),
      SlotLabMiddlewareSubTab.simulation => const _SimulationPanel(),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BEHAVIOR — Tree view with coverage
// ═══════════════════════════════════════════════════════════════════════════

class _BehaviorPanel extends StatelessWidget {
  const _BehaviorPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<BehaviorTreeProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final tree = provider.tree;
        final nodes = tree.nodes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Behavior Tree', '${nodes.length} nodes — ${nodes.values.where((n) => n.hasAudio).length}/${nodes.length} with audio'),
            Expanded(
              child: nodes.isEmpty
                  ? const Center(child: Text('No behavior nodes defined', style: TextStyle(color: Colors.white38, fontSize: 11)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: BehaviorCategory.values.length,
                      itemBuilder: (ctx, catIdx) {
                        final cat = BehaviorCategory.values[catIdx];
                        final catNodes = nodes.values.where((n) => n.category == cat).toList();
                        if (catNodes.isEmpty) return const SizedBox.shrink();
                        return _CategorySection(category: cat, nodes: catNodes);
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

  const _CategorySection({required this.category, required this.nodes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(category.displayName, style: TextStyle(color: _catColor(category), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ),
        ...nodes.map((n) => _NodeRow(node: n)),
      ],
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

class _NodeRow extends StatelessWidget {
  final BehaviorNode node;
  const _NodeRow({required this.node});

  @override
  Widget build(BuildContext context) {
    final hasSounds = node.hasAudio;
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 1),
      child: Row(
        children: [
          Icon(hasSounds ? Icons.volume_up : Icons.volume_off, size: 10, color: hasSounds ? const Color(0xFF40FF90) : Colors.white24),
          const SizedBox(width: 4),
          Expanded(child: Text(node.nodeType.displayName, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
          Text(node.basicParams.priorityClass.name, style: const TextStyle(color: Colors.white30, fontSize: 9)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGERS — Hook→Node bindings
// ═══════════════════════════════════════════════════════════════════════════

class _TriggersPanel extends StatelessWidget {
  const _TriggersPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<TriggerLayerProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final bindings = provider.bindings.values.toList();
        final unbound = provider.unboundHooks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Trigger Bindings', '${bindings.length} hooks — ${unbound.length} unbound'),
            Expanded(
              child: bindings.isEmpty
                  ? const Center(child: Text('No trigger bindings\nCall initializeMiddleware() to auto-generate', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: bindings.length,
                      itemBuilder: (ctx, i) {
                        final b = bindings[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Icon(b.enabled ? Icons.link : Icons.link_off, size: 10, color: b.enabled ? const Color(0xFF40C8FF) : Colors.white24),
                              const SizedBox(width: 4),
                              Expanded(child: Text(b.hookName, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                              Text('→ ${b.targetNodeIds.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              if (b.delayMs > 0)
                                Padding(padding: const EdgeInsets.only(left: 4), child: Text('+${b.delayMs}ms', style: const TextStyle(color: Colors.orangeAccent, fontSize: 9))),
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
// GATE — State machine
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
        final blockedCount = provider.blockedCount;
        final history = provider.history;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('State Gate', 'Current: ${current.displayName}'),
            // Substate chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: GameplaySubstate.values.map((s) {
                  final isCurrent = s == current;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent ? const Color(0xFF40FF90).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(3),
                      border: isCurrent ? Border.all(color: const Color(0xFF40FF90), width: 1) : null,
                    ),
                    child: Text(s.name, style: TextStyle(color: isCurrent ? const Color(0xFF40FF90) : Colors.white38, fontSize: 10)),
                  );
                }).toList(),
              ),
            ),
            // Blocked count
            if (blockedCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Blocked: $blockedCount hooks', style: const TextStyle(color: Color(0xFFFF4060), fontSize: 10)),
              ),
            // Gate check history
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: history.length.clamp(0, 50),
                itemBuilder: (ctx, i) {
                  final entry = history[history.length - 1 - i]; // reverse
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
// PRIORITY — Resolutions
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
            _header('Priority Engine', '${active.length} active — ${history.length} resolutions'),
            Expanded(
              child: history.isEmpty
                  ? const Center(child: Text('No priority resolutions yet', style: TextStyle(color: Colors.white38, fontSize: 11)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: history.length.clamp(0, 50),
                      itemBuilder: (ctx, i) {
                        final res = history[history.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              _priorityDot(res.action),
                              const SizedBox(width: 4),
                              Expanded(child: Text('${res.winnerId} > ${res.loserId}', style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                              Text(res.action.name, style: TextStyle(color: _priorityColor(res.action), fontSize: 10)),
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

  Widget _priorityDot(PriorityConflictAction action) {
    return Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _priorityColor(action)));
  }

  Color _priorityColor(PriorityConflictAction action) => switch (action) {
    PriorityConflictAction.duck => const Color(0xFFFFD700),
    PriorityConflictAction.delay => const Color(0xFFFF9040),
    PriorityConflictAction.suppress => const Color(0xFFFF4060),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// ORCHESTRATION — Current decisions
// ═══════════════════════════════════════════════════════════════════════════

class _OrchestrationPanel extends StatelessWidget {
  const _OrchestrationPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<OrchestrationEngineProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final decisions = provider.decisions;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Orchestration Engine', '${decisions.length} active decisions'),
            Expanded(
              child: decisions.isEmpty
                  ? const Center(child: Text('No orchestration decisions\nProcess hooks to generate', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: decisions.length,
                      itemBuilder: (ctx, i) {
                        final d = decisions.values.elementAt(i);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(4)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.nodeId, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    _miniBar('Gain', d.gainBiasDb, -12, 6, const Color(0xFF40FF90)),
                                    const SizedBox(width: 8),
                                    _miniBar('Width', d.stereoWidthScale, 0, 2, const Color(0xFF40C8FF)),
                                    const SizedBox(width: 8),
                                    _miniBar('Pan', d.spatialBias, -1, 1, const Color(0xFF9370DB)),
                                  ],
                                ),
                              ],
                            ),
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
// EMOTIONAL — State + decay
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
        final spinHistory = provider.spinHistory;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Emotional State', state.name),
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
                  const SizedBox(width: 8),
                  _miniMeter('Tension', output.tension, const Color(0xFFFF9040)),
                  const SizedBox(width: 8),
                  _miniMeter('Width', (output.stereoWidthMod - 1.0).clamp(0.0, 1.0), const Color(0xFF40C8FF)),
                  const SizedBox(width: 8),
                  _miniMeter('Shimmer', output.hfShimmer, const Color(0xFFFFD700)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Spin history
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'History: ${spinHistory.length} spins | Losses: ${provider.consecutiveLossCount} streak | Cascade: ${provider.cascadeDepth}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
            const Spacer(),
          ],
        );
      },
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
// CONTEXT — Game mode overrides
// ═══════════════════════════════════════════════════════════════════════════

class _ContextPanel extends StatelessWidget {
  const _ContextPanel();

  @override
  Widget build(BuildContext context) {
    final provider = GetIt.instance<ContextLayerProvider>();
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final mode = provider.currentMode;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Context Layer', 'Mode: ${mode.name}'),
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
            // Mode description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Active game mode: ${mode.name} — drop audio overrides per-mode',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
            const Spacer(),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIMULATION — Mode + Results
// ═══════════════════════════════════════════════════════════════════════════

class _SimulationPanel extends StatelessWidget {
  const _SimulationPanel();

  @override
  Widget build(BuildContext context) {
    final sim = GetIt.instance<SimulationEngineProvider>();
    final transition = GetIt.instance<TransitionSystemProvider>();
    final errors = GetIt.instance<ErrorPreventionProvider>();
    return ListenableBuilder(
      listenable: Listenable.merge([sim, transition, errors]),
      builder: (context, _) {
        final validations = errors.issues;
        final errorCount = errors.errorCount;
        final warnCount = errors.warningCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header('Simulation & Validation', 'Mode: ${sim.mode.name}'),
            // Simulation mode selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: SimulationMode.values.map((m) {
                  final isCurrent = m == sim.mode;
                  return GestureDetector(
                    onTap: () => sim.setMode(m),
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
            // Transition rules
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('Transition rules: ${transition.allRules.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ),
            const SizedBox(height: 4),
            // Validation results
            if (validations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Validation: $errorCount errors, $warnCount warnings',
                  style: TextStyle(color: errorCount > 0 ? const Color(0xFFFF4060) : const Color(0xFFFFD700), fontSize: 10),
                ),
              ),
            // Results list
            Expanded(
              child: sim.history.isEmpty
                  ? const Center(child: Text('No simulation results', style: TextStyle(color: Colors.white38, fontSize: 11)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

Widget _header(String title, String subtitle) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
    child: Row(
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(child: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10), overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
