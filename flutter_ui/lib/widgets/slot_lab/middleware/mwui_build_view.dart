import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../models/behavior_tree_models.dart';
import '../../../providers/slot_lab/behavior_tree_provider.dart';
import '../../../providers/slot_lab/behavior_coverage_provider.dart';
import '../../../providers/slot_lab/trigger_layer_provider.dart';
import '../../../providers/slot_lab/slot_stage_provider.dart';
import '../../../theme/fluxforge_theme.dart';
import '../behavior_tree_widget.dart';

/// MWUI-1: BUILD View — Primary 90% Workflow
///
/// Three-pane layout:
/// - Left: Behavior tree (node selection, coverage indicators)
/// - Center: Node editor (properties, transitions, audio assignment)
/// - Right: Stage assignment + AutoBind panel
class MwuiBuildView extends StatefulWidget {
  const MwuiBuildView({super.key});

  @override
  State<MwuiBuildView> createState() => _MwuiBuildViewState();
}

class _MwuiBuildViewState extends State<MwuiBuildView> {
  BehaviorTreeProvider? _treeProvider;
  BehaviorCoverageProvider? _coverageProvider;
  TriggerLayerProvider? _triggerProvider;
  SlotStageProvider? _stageProvider;

  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _tryGet<BehaviorTreeProvider>((p) => _treeProvider = p);
    _tryGet<BehaviorCoverageProvider>((p) => _coverageProvider = p);
    _tryGet<TriggerLayerProvider>((p) => _triggerProvider = p);
    _tryGet<SlotStageProvider>((p) => _stageProvider = p);
  }

  void _tryGet<T extends ChangeNotifier>(void Function(T) assign) {
    try {
      final p = GetIt.instance<T>();
      assign(p);
      p.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _treeProvider?.removeListener(_onUpdate);
    _coverageProvider?.removeListener(_onUpdate);
    _triggerProvider?.removeListener(_onUpdate);
    _stageProvider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Behavior Tree
        SizedBox(
          width: 240,
          child: _buildTreePane(),
        ),
        VerticalDivider(width: 1, color: FluxForgeTheme.borderSubtle),
        // Center: Node Editor
        Expanded(
          flex: 3,
          child: _buildNodeEditor(),
        ),
        VerticalDivider(width: 1, color: FluxForgeTheme.borderSubtle),
        // Right: Stage + AutoBind
        SizedBox(
          width: 220,
          child: _buildStagePanel(),
        ),
      ],
    );
  }

  Widget _buildTreePane() {
    return Column(
      children: [
        _paneHeader('Behavior Tree', Icons.account_tree, FluxForgeTheme.accentBlue),
        Expanded(
          child: BehaviorTreeWidget(
            showCoverage: true,
            showRuntimeState: false,
            onNodeSelected: (nodeId) {
              setState(() => _selectedNodeId = nodeId);
            },
          ),
        ),
        _buildCoverageBar(),
      ],
    );
  }

  Widget _buildCoverageBar() {
    final cov = _coverageProvider;
    final pct = cov != null ? (cov.overallCoverage * 100) : 0.0;
    final color = pct >= 80 ? FluxForgeTheme.accentGreen :
                  pct >= 50 ? const Color(0xFFFFB74D) : const Color(0xFFEF5350);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('Coverage', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: pct / 100,
                backgroundColor: Colors.white.withOpacity(0.06),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('${pct.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildNodeEditor() {
    final nodeId = _selectedNodeId;
    if (nodeId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 32, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text('Select a behavior node', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12)),
          ],
        ),
      );
    }

    final node = _treeProvider?.allNodes.cast<BehaviorNode?>().firstWhere((n) => n?.id == nodeId, orElse: () => null);
    if (node == null) {
      return Center(
        child: Text('Node not found: $nodeId', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
      );
    }

    return Column(
      children: [
        _paneHeader('Node: ${node.nodeType.displayName}', Icons.edit, _categoryColor(node.category)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPropertySection(node),
                const SizedBox(height: 12),
                _buildAudioSection(node),
                const SizedBox(height: 12),
                _buildTransitionSection(node),
                const SizedBox(height: 12),
                _buildTriggerSection(nodeId),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPropertySection(BehaviorNode node) {
    return _section('Properties', [
      _propRow('ID', node.id),
      _propRow('Category', node.category.displayName),
      _propRow('Priority', node.basicParams.priorityClass.name),
      _propRow('State', node.state),
      _propRow('Layer Group', node.basicParams.layerGroup),
    ]);
  }

  Widget _buildAudioSection(BehaviorNode node) {
    final hasSound = node.soundAssignments.isNotEmpty;
    return _section('Audio Assignment', [
      _propRow('Sound Group', node.soundGroup),
      _propRow('Assignments', '${node.soundAssignments.length}'),
      _propRow('Gain', '${node.basicParams.gain.toStringAsFixed(1)} dB'),
      _propRow('Output Bus', node.basicParams.busRoute),
      _propRow('Has Audio', hasSound ? 'Yes' : 'No'),
    ]);
  }

  Widget _buildTransitionSection(BehaviorNode node) {
    return _section('Playback', [
      _propRow('Mode', node.playbackMode.name),
      _propRow('Escalation', node.escalationPolicy),
      _propRow('Emotional Wt', node.emotionalWeight.toStringAsFixed(2)),
      _propRow('Variants', '${node.variantCount}'),
    ]);
  }

  Widget _buildTriggerSection(String nodeId) {
    final triggers = _triggerProvider;
    if (triggers == null) return const SizedBox.shrink();
    final hookNames = triggers.getHooksForNode(nodeId);
    return _section('Bindings (${hookNames.length})', [
      if (hookNames.isEmpty)
        Text('No bindings', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
      for (final hookName in hookNames.take(10))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              Icon(Icons.link, size: 10, color: FluxForgeTheme.accentGreen),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  hookName,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _buildStagePanel() {
    return Column(
      children: [
        _paneHeader('Stage Assignment', Icons.layers, const Color(0xFF7E57C2)),
        Expanded(
          child: _buildStageList(),
        ),
        _buildAutoBindSection(),
      ],
    );
  }

  Widget _buildStageList() {
    final stages = _stageProvider;
    if (stages == null) {
      return Center(
        child: Text('Stage provider not available', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
      );
    }

    final allStages = stages.lastStages;
    if (allStages.isEmpty) {
      return Center(
        child: Text('No stages defined', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(6),
      itemCount: allStages.length,
      itemBuilder: (context, index) {
        final stage = allStages[index];
        final isActive = stages.currentStageIndex == index;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF7E57C2).withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF7E57C2) : Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stage.stageType,
                  style: TextStyle(
                    color: isActive ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${stage.timestampMs.toStringAsFixed(0)}ms',
                style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 7),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAutoBindSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high, size: 12, color: FluxForgeTheme.accentGreen.withOpacity(0.7)),
              const SizedBox(width: 4),
              Text('AutoBind', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Drop audio folder to auto-bind by naming convention',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _paneHeader(String title, IconData icon, Color color) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _propRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(BehaviorCategory cat) {
    switch (cat) {
      case BehaviorCategory.reels: return const Color(0xFF42A5F5);
      case BehaviorCategory.cascade: return const Color(0xFF66BB6A);
      case BehaviorCategory.win: return const Color(0xFFFFB74D);
      case BehaviorCategory.feature: return const Color(0xFF7E57C2);
      case BehaviorCategory.jackpot: return const Color(0xFFEF5350);
      case BehaviorCategory.ui: return const Color(0xFF78909C);
      case BehaviorCategory.system: return const Color(0xFF90A4AE);
    }
  }
}
