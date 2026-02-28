import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../models/behavior_tree_models.dart'
    hide BehaviorCoverageStatus;
import '../../../providers/slot_lab/inspector_context_provider.dart';
import '../../../providers/slot_lab/behavior_tree_provider.dart';
import '../../../providers/slot_lab/behavior_coverage_provider.dart';
import '../../../providers/slot_lab/trigger_layer_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-8: Inspector Panel — 5 Tabs
///
/// Context-sensitive node inspector with tabs:
/// - Properties: Name, category, priority, enabled
/// - Audio: Sound assignment, volume, pan, bus
/// - Behavior: Playback mode, transitions, retrigger
/// - Transitions: State transitions, edge conditions
/// - Debug: FFI trace, latency, voice pool info
class MwuiInspectorPanel extends StatefulWidget {
  const MwuiInspectorPanel({super.key});

  @override
  State<MwuiInspectorPanel> createState() => _MwuiInspectorPanelState();
}

class _MwuiInspectorPanelState extends State<MwuiInspectorPanel> {
  InspectorContextProvider? _inspector;
  BehaviorTreeProvider? _treeProvider;
  BehaviorCoverageProvider? _coverageProvider;
  TriggerLayerProvider? _triggerProvider;

  @override
  void initState() {
    super.initState();
    _tryGet<InspectorContextProvider>((p) => _inspector = p);
    _tryGet<BehaviorTreeProvider>((p) => _treeProvider = p);
    _tryGet<BehaviorCoverageProvider>((p) => _coverageProvider = p);
    _tryGet<TriggerLayerProvider>((p) => _triggerProvider = p);
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
    _inspector?.removeListener(_onUpdate);
    _treeProvider?.removeListener(_onUpdate);
    _coverageProvider?.removeListener(_onUpdate);
    _triggerProvider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildTabBar(),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildHeader() {
    final node = _inspector?.selectedNode;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Color(0xFF42A5F5)),
          const SizedBox(width: 6),
          if (node != null) ...[
            Text(node.nodeType.displayName, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _categoryColor(node.category).withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(node.category.displayName,
                style: TextStyle(color: _categoryColor(node.category), fontSize: 7, fontWeight: FontWeight.w600)),
            ),
          ] else
            Text('Inspector', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
          const Spacer(),
          if (_inspector != null)
            GestureDetector(
              onTap: () => _inspector!.togglePinned(),
              child: Icon(
                _inspector!.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 12,
                color: _inspector!.pinned ? const Color(0xFF42A5F5) : Colors.white.withOpacity(0.3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: InspectorTab.values.map((tab) {
          final isActive = _inspector?.activeTab == tab;
          return GestureDetector(
            onTap: () => _inspector?.setActiveTab(tab),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive == true ? Colors.white.withOpacity(0.06) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                border: isActive == true
                    ? const Border(bottom: BorderSide(color: Color(0xFF42A5F5), width: 1.5))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    IconData(tab.iconCodePoint, fontFamily: 'MaterialIcons'),
                    size: 10,
                    color: isActive == true ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    tab.displayName,
                    style: TextStyle(
                      color: isActive == true ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.4),
                      fontSize: 9,
                      fontWeight: isActive == true ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    if (!(_inspector?.hasSelection ?? false)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 28, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 6),
            Text('Select a behavior node to inspect', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
          ],
        ),
      );
    }

    final node = _inspector!.selectedNode;
    if (node == null) {
      return Center(
        child: Text('Node not found', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
      );
    }

    switch (_inspector!.activeTab) {
      case InspectorTab.parameters: return _buildParametersTab(node);
      case InspectorTab.sounds: return _buildSoundsTab(node);
      case InspectorTab.context: return _buildContextTab(node);
      case InspectorTab.ducking: return _buildDuckingTab(node);
      case InspectorTab.coverage: return _buildCoverageTab(node);
    }
  }

  Widget _buildParametersTab(BehaviorNode node) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('IDENTITY', [
          _propRow('Node ID', node.id),
          _propRow('Display Name', node.nodeType.displayName),
          _propRow('Category', node.category.displayName),
        ]),
        const SizedBox(height: 10),
        _section('PRIORITY', [
          _propRow('Priority Class', node.basicParams.priorityClass.name),
          _propRow('State', node.state),
          _propRow('Layer Group', node.basicParams.layerGroup),
        ]),
        const SizedBox(height: 10),
        _section('AUDIO', [
          _propRow('Gain', '${node.basicParams.gain.toStringAsFixed(1)} dB'),
          _propRow('Output Bus', node.basicParams.busRoute),
        ]),
      ],
    );
  }

  Widget _buildSoundsTab(BehaviorNode node) {
    final assignments = node.soundAssignments;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('SOUND ASSIGNMENTS', [
          if (assignments.isEmpty)
            Text('No sounds assigned', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9))
          else
            for (int i = 0; i < assignments.length; i++)
              _soundRow('Sound ${i + 1}', assignments[i].displayName),
        ]),
        const SizedBox(height: 10),
        _section('SOUND GROUP', [
          _propRow('Group', node.soundGroup),
          _propRow('Variant Count', '${node.variantCount}'),
          _propRow('Has Audio', node.hasAudio ? 'Yes' : 'No'),
        ]),
      ],
    );
  }

  Widget _buildContextTab(BehaviorNode node) {
    final overrides = node.contextOverrides;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('CONTEXT OVERRIDES (${overrides.length})', [
          if (overrides.isEmpty)
            Text('No context overrides', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9))
          else
            for (final co in overrides)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(co.contextId, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w600)),
                    if (co.gainOverride != null)
                      _propRow('  Gain', '${co.gainOverride!.toStringAsFixed(1)} dB'),
                    if (co.busRouteOverride != null)
                      _propRow('  Bus', co.busRouteOverride!),
                    if (co.playbackModeOverride != null)
                      _propRow('  Playback', co.playbackModeOverride!.name),
                    if (co.disabled)
                      _propRow('  Disabled', 'Yes'),
                  ],
                ),
              ),
        ]),
      ],
    );
  }

  Widget _buildDuckingTab(BehaviorNode node) {
    final hookNames = _triggerProvider?.getHooksForNode(node.id) ?? [];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('BINDINGS (${hookNames.length})', [
          if (hookNames.isEmpty)
            Text('No bindings', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9))
          else
            for (final hookName in hookNames)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.link, size: 10, color: const Color(0xFF66BB6A)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(hookName, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9)),
                    ),
                  ],
                ),
              ),
        ]),
        const SizedBox(height: 10),
        _section('PLAYBACK', [
          _propRow('Mode', node.playbackMode.name),
          _propRow('Escalation', node.escalationPolicy),
          _propRow('Emotional Wt', node.emotionalWeight.toStringAsFixed(2)),
        ]),
      ],
    );
  }

  Widget _buildCoverageTab(BehaviorNode node) {
    final stats = _coverageProvider?.getNodeStats(node.id);
    final entries = _coverageProvider?.getEntriesForNode(node.id) ?? [];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('COVERAGE STATS', [
          if (stats != null) ...[
            _propRow('Total Stages', '${stats.totalStages}'),
            _propRow('Tested', '${stats.testedStages}'),
            _propRow('Verified', '${stats.verifiedStages}'),
            _propRow('Coverage', '${stats.totalStages > 0 ? ((stats.testedStages + stats.verifiedStages) / stats.totalStages * 100).toStringAsFixed(0) : 0}%'),
          ] else
            Text('No coverage data', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9)),
        ]),
        const SizedBox(height: 10),
        _section('STAGE ENTRIES', [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  _statusDot(entry.status),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(entry.stageName, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
                  ),
                  Text(
                    entry.triggerCount > 0 ? '${entry.triggerCount}x' : '-',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(
          color: const Color(0xFF42A5F5).withOpacity(0.6),
          fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _propRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10))),
          Expanded(child: Text(value, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10))),
        ],
      ),
    );
  }

  Widget _soundRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10))),
          Icon(Icons.music_note, size: 10, color: Colors.white.withOpacity(0.2)),
          const SizedBox(width: 4),
          Expanded(child: Text(value, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _statusDot(BehaviorCoverageStatus status) {
    final color = status == BehaviorCoverageStatus.verified
        ? const Color(0xFF66BB6A)
        : status == BehaviorCoverageStatus.tested
            ? const Color(0xFFFFB74D)
            : const Color(0xFFEF5350);
    return Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
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
