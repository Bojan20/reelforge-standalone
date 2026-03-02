/// P-DSF Inspector & Dry-Run Panel — Property editor + execution timeline
///
/// Bottom panel of the Stage Flow Editor:
///   - Node Inspector: timing, conditions, properties for selected node
///   - Dry-Run Timeline: step-by-step execution view with variable watch
///   - Validation Errors: list of all graph validation issues
library;

import 'package:flutter/material.dart';

import '../../models/stage_flow_models.dart';
import '../../providers/slot_lab/stage_flow_provider.dart';
import '../../services/condition_evaluator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INSPECTOR PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Combined inspector panel for node properties, dry-run timeline, and validation.
class StageFlowInspectorWidget extends StatefulWidget {
  final StageFlowProvider provider;

  const StageFlowInspectorWidget({
    super.key,
    required this.provider,
  });

  @override
  State<StageFlowInspectorWidget> createState() =>
      _StageFlowInspectorWidgetState();
}

class _StageFlowInspectorWidgetState extends State<StageFlowInspectorWidget>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.provider.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  StageFlowProvider get _p => widget.provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2C),
        border: Border(top: BorderSide(color: Color(0xFF333355))),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 11),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune, size: 14),
                    const SizedBox(width: 4),
                    Text(_p.selectedNode != null
                        ? _p.selectedNode!.stageId
                        : 'Inspector'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _p.isDryRunning ? Icons.play_arrow : Icons.timeline,
                      size: 14,
                      color: _p.isDryRunning ? Colors.yellowAccent : null,
                    ),
                    const SizedBox(width: 4),
                    const Text('Dry Run'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber,
                        size: 14,
                        color: _p.hasErrors ? Colors.redAccent : null),
                    const SizedBox(width: 4),
                    Text('Issues (${_p.validationErrors.length})'),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNodeInspector(),
                _buildDryRunTimeline(),
                _buildValidationPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── NODE INSPECTOR ───────────────────────────────────────────────────

  Widget _buildNodeInspector() {
    final node = _p.selectedNode;
    if (node == null) {
      return const Center(
        child: Text('Select a node to inspect',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timing section
          Expanded(child: _buildTimingSection(node)),
          const SizedBox(width: 12),
          // Conditions section
          Expanded(child: _buildConditionsSection(node)),
          const SizedBox(width: 12),
          // Properties section
          Expanded(child: _buildPropertiesSection(node)),
        ],
      ),
    );
  }

  Widget _buildTimingSection(StageFlowNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Timing'),
        _infoRow('Mode', node.timing.mode.name),
        _infoRow('Delay', '${node.timing.delayMs}ms'),
        _infoRow('Duration', '${node.timing.durationMs}ms'),
        if (node.timing.minDurationMs > 0)
          _infoRow('Min', '${node.timing.minDurationMs}ms'),
        if (node.timing.maxDurationMs > 0)
          _infoRow('Max', '${node.timing.maxDurationMs}ms'),
        if (node.timing.beatQuantize != null)
          _infoRow('Beat Q', '${node.timing.beatQuantize}'),
        _infoRow('Skip', node.timing.canSkip ? 'Yes' : 'No'),
        _infoRow('Slam Stop', node.timing.canSlamStop ? 'Yes' : 'No'),
      ],
    );
  }

  Widget _buildConditionsSection(StageFlowNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Conditions'),
        _conditionRow('Enter', node.enterCondition),
        _conditionRow('Skip', node.skipCondition),
        _conditionRow('Exit', node.exitCondition),
        const SizedBox(height: 8),
        _sectionHeader('Info'),
        _infoRow('Type', node.type.name),
        _infoRow('Layer', node.layer.name),
        _infoRow('Locked', node.locked ? 'Yes' : 'No'),
        if (node.type == StageFlowNodeType.join)
          _infoRow('Join', node.joinMode.name),
      ],
    );
  }

  Widget _buildPropertiesSection(StageFlowNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Properties'),
        if (node.properties.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('No custom properties',
                style: TextStyle(color: Colors.white24, fontSize: 10)),
          ),
        ...node.properties.entries.map((e) => _infoRow(e.key, '${e.value}')),
        if (node.description != null) ...[
          const SizedBox(height: 8),
          _sectionHeader('Description'),
          Text(node.description!,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ],
    );
  }

  Widget _conditionRow(String label, String? expression) {
    final isValid = expression == null ||
        expression.isEmpty ||
        ConditionEvaluator()
            .validate(expression, BuiltInRuntimeVariables.all)
            .isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ),
          Icon(
            isValid ? Icons.check_circle : Icons.error,
            size: 10,
            color: expression == null
                ? Colors.white12
                : isValid
                    ? Colors.green
                    : Colors.redAccent,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              expression ?? '—',
              style: TextStyle(
                color: expression != null ? Colors.white70 : Colors.white24,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── DRY-RUN TIMELINE ─────────────────────────────────────────────────

  Widget _buildDryRunTimeline() {
    if (!_p.isDryRunning && _p.lastResult == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_outline,
                size: 32, color: Colors.white24),
            const SizedBox(height: 8),
            const Text('Click Dry Run to simulate flow',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            if (_p.lastResult != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last: ${_p.lastResult!.status.name} — ${_p.lastResult!.totalDurationMs}ms',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      );
    }

    final graph = _p.graph;
    if (graph == null) return const SizedBox();

    final sortedNodes = graph.topologicalSort();

    return Row(
      children: [
        // Timeline
        Expanded(
          flex: 3,
          child: ListView.builder(
            padding: const EdgeInsets.all(4),
            itemCount: sortedNodes.length,
            itemBuilder: (ctx, i) {
              final node = sortedNodes[i];
              final isActive = _p.activeNodeId == node.id;
              final isCompleted = _p.completedNodeIds.contains(node.id);
              final isSkipped = _p.skippedNodeIds.contains(node.id);

              IconData statusIcon;
              Color statusColor;
              if (isActive) {
                statusIcon = Icons.play_arrow;
                statusColor = Colors.yellowAccent;
              } else if (isCompleted) {
                statusIcon = Icons.check_circle;
                statusColor = Colors.green;
              } else if (isSkipped) {
                statusIcon = Icons.skip_next;
                statusColor = Colors.white38;
              } else {
                statusIcon = Icons.circle_outlined;
                statusColor = Colors.white24;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        node.timing.delayMs > 0
                            ? '${node.timing.delayMs}ms'
                            : '0ms',
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 9,
                            fontFamily: 'monospace'),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        node.stageId,
                        style: TextStyle(
                          color: isSkipped ? Colors.white30 : Colors.white70,
                          fontSize: 10,
                          decoration: isSkipped
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (node.timing.durationMs > 0)
                      Text(
                        '${node.timing.durationMs}ms',
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 9),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        // Variables watch
        Container(width: 1, color: Colors.white12),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                child: const Text('Variables',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: _p.dryRunVariables.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(e.key,
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 9,
                                    fontFamily: 'monospace')),
                          ),
                          Text('${e.value}',
                              style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 9,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── VALIDATION PANEL ─────────────────────────────────────────────────

  Widget _buildValidationPanel() {
    if (_p.validationErrors.isEmpty) {
      return const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 8),
            Text('No issues found',
                style: TextStyle(color: Colors.green, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: _p.validationErrors.length,
      itemBuilder: (ctx, i) {
        final error = _p.validationErrors[i];
        Color iconColor;
        IconData icon;
        switch (error.severity) {
          case FlowValidationSeverity.error:
            icon = Icons.error;
            iconColor = Colors.redAccent;
            break;
          case FlowValidationSeverity.warning:
            icon = Icons.warning;
            iconColor = Colors.amber;
            break;
          case FlowValidationSeverity.info:
            icon = Icons.info;
            iconColor = Colors.lightBlueAccent;
            break;
        }

        return InkWell(
          onTap: () {
            if (error.nodeId.isNotEmpty) {
              _p.selectNode(error.nodeId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  child: Text(error.code,
                      style: TextStyle(
                          color: iconColor,
                          fontSize: 10,
                          fontFamily: 'monospace')),
                ),
                Expanded(
                  child: Text(error.message,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
