import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/state_gate_provider.dart';
import '../../../providers/slot_lab/priority_engine_provider.dart';
import '../../../providers/slot_lab/emotional_state_provider.dart';
import '../../../providers/slot_lab/orchestration_engine_provider.dart';
import '../../../providers/aurexis_provider.dart';
import '../../../providers/subsystems/voice_pool_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-2: FLOW View — 10-Layer Pipeline Visualization
///
/// Visual representation of the middleware signal flow:
/// Hook → Gate → Behavior → Priority → Emotional → Orchestration
/// → AUREXIS → Voice → DSP → Analytics
class MwuiFlowView extends StatefulWidget {
  const MwuiFlowView({super.key});

  @override
  State<MwuiFlowView> createState() => _MwuiFlowViewState();
}

class _MwuiFlowViewState extends State<MwuiFlowView> {
  StateGateProvider? _gate;
  PriorityEngineProvider? _priority;
  EmotionalStateProvider? _emotional;
  OrchestrationEngineProvider? _orchestration;
  AurexisProvider? _aurexis;
  VoicePoolProvider? _voicePool;

  int _hoveredLayer = -1;

  @override
  void initState() {
    super.initState();
    _tryGet<StateGateProvider>((p) => _gate = p);
    _tryGet<PriorityEngineProvider>((p) => _priority = p);
    _tryGet<EmotionalStateProvider>((p) => _emotional = p);
    _tryGet<OrchestrationEngineProvider>((p) => _orchestration = p);
    _tryGet<AurexisProvider>((p) => _aurexis = p);
    _tryGet<VoicePoolProvider>((p) => _voicePool = p);
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
    _gate?.removeListener(_onUpdate);
    _priority?.removeListener(_onUpdate);
    _emotional?.removeListener(_onUpdate);
    _orchestration?.removeListener(_onUpdate);
    _aurexis?.removeListener(_onUpdate);
    _voicePool?.removeListener(_onUpdate);
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
        Expanded(
          child: Row(
            children: [
              // Pipeline diagram (left)
              Expanded(
                flex: 2,
                child: _buildPipelineDiagram(),
              ),
              VerticalDivider(width: 1, color: FluxForgeTheme.borderSubtle),
              // Detail panel (right)
              SizedBox(
                width: 260,
                child: _buildDetailPanel(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.route, size: 14, color: Color(0xFF4FC3F7)),
          const SizedBox(width: 6),
          Text('Middleware Pipeline Flow', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('10 Layers', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildPipelineDiagram() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (int i = 0; i < _layers.length; i++) ...[
            _buildLayerNode(i),
            if (i < _layers.length - 1) _buildConnector(i),
          ],
        ],
      ),
    );
  }

  Widget _buildLayerNode(int index) {
    final layer = _layers[index];
    final isHovered = _hoveredLayer == index;
    final isActive = _isLayerActive(index);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredLayer = index),
      onExit: (_) => setState(() => _hoveredLayer = -1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isHovered
              ? layer.color.withOpacity(0.15)
              : layer.color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? layer.color : layer.color.withOpacity(0.3),
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: layer.color.withOpacity(isActive ? 0.3 : 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(color: layer.color, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.name,
                    style: TextStyle(
                      color: isActive ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    layer.description,
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
                  ),
                ],
              ),
            ),
            Icon(
              layer.icon,
              size: 14,
              color: layer.color.withOpacity(isActive ? 0.8 : 0.4),
            ),
            const SizedBox(width: 6),
            _buildLayerStatus(index, layer),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerStatus(int index, _FlowLayer layer) {
    final status = _getLayerStatusText(index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: layer.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        status,
        style: TextStyle(color: layer.color.withOpacity(0.7), fontSize: 7, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildConnector(int index) {
    return SizedBox(
      height: 16,
      child: Center(
        child: Container(
          width: 1,
          height: 16,
          color: Colors.white.withOpacity(0.1),
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
    if (_hoveredLayer < 0 || _hoveredLayer >= _layers.length) {
      return Center(
        child: Text('Hover a layer for details', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
      );
    }

    final layer = _layers[_hoveredLayer];
    final params = _getLayerParams(_hoveredLayer);

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(layer.icon, size: 14, color: layer.color),
                    const SizedBox(width: 6),
                    Text(layer.name, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(layer.detailDescription, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                Text('PARAMETERS', style: TextStyle(color: layer.color.withOpacity(0.6), fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 4),
                for (final p in params)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(p.key, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9)),
                        ),
                        Text(p.value, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isLayerActive(int index) {
    switch (index) {
      case 1: return _gate != null;
      case 3: return _priority != null;
      case 4: return _emotional != null;
      case 5: return _orchestration != null;
      case 6: return _aurexis?.enabled == true;
      case 7: return _voicePool != null;
      default: return true;
    }
  }

  String _getLayerStatusText(int index) {
    switch (index) {
      case 0: return 'LISTEN';
      case 1: return _gate?.currentSubstate.name ?? 'IDLE';
      case 2: return 'DISPATCH';
      case 3: return '${_priority?.activeBehaviors.length ?? 0} active';
      case 4: return _emotional?.state.name ?? 'neutral';
      case 5: return '${_orchestration?.decisions.length ?? 0} decisions';
      case 6: return _aurexis?.enabled == true ? 'ON' : 'OFF';
      case 7: return '${_voicePool?.activeCount ?? 0} voices';
      case 8: return 'PROCESS';
      case 9: return 'COLLECT';
      default: return '';
    }
  }

  List<MapEntry<String, String>> _getLayerParams(int index) {
    switch (index) {
      case 1:
        return [
          MapEntry('Substate', _gate?.currentSubstate.name ?? 'unknown'),
          MapEntry('Autoplay', '${_gate?.isAutoplay ?? false}'),
          MapEntry('Turbo', '${_gate?.isTurbo ?? false}'),
        ];
      case 3:
        return [
          MapEntry('Active', '${_priority?.activeBehaviors.length ?? 0}'),
          MapEntry('Resolutions', '${_priority?.resolutionLog.length ?? 0}'),
        ];
      case 4:
        return [
          MapEntry('State', _emotional?.state.name ?? 'neutral'),
          MapEntry('Intensity', '${((_emotional?.intensity ?? 0) * 100).toStringAsFixed(0)}%'),
          MapEntry('Tension', '${((_emotional?.tension ?? 0) * 100).toStringAsFixed(0)}%'),
        ];
      case 5:
        return [
          MapEntry('Escalation', _orchestration?.context.escalationIndex.toStringAsFixed(2) ?? '?'),
          MapEntry('Decisions', '${_orchestration?.decisions.length ?? 0}'),
        ];
      case 6:
        return [
          MapEntry('Enabled', '${_aurexis?.enabled ?? false}'),
          MapEntry('Volatility', _aurexis?.volatility.toStringAsFixed(3) ?? '?'),
          MapEntry('RTP', '${_aurexis?.rtp.toStringAsFixed(2) ?? "?"}%'),
          MapEntry('Fatigue', _aurexis?.fatigueLevel.name ?? '?'),
        ];
      case 7:
        return [
          MapEntry('Active', '${_voicePool?.activeCount ?? 0}'),
          MapEntry('Max', '${_voicePool?.engineMaxVoices ?? 0}'),
          MapEntry('Stolen', '${_voicePool?.stealCount ?? 0}'),
          MapEntry('Virtual', '${_voicePool?.virtualCount ?? 0}'),
        ];
      default:
        return [MapEntry('Status', 'Active')];
    }
  }

  static const _layers = [
    _FlowLayer('Engine Trigger', 'Game hooks from engine', 'Receives raw hook events from game engine via FFI', Icons.input, Color(0xFFEF5350)),
    _FlowLayer('State Gate', 'Filters by game state', 'State machine filtering: only allows hooks valid in current state', Icons.filter_alt, Color(0xFFFF7043)),
    _FlowLayer('Behavior Event', 'Maps to behaviors', 'Translates filtered hooks into behavior node activations', Icons.account_tree, Color(0xFFFFB74D)),
    _FlowLayer('Priority Engine', 'Resolves conflicts', 'DPM scoring, conflict resolution, voice survival decisions', Icons.sort, Color(0xFFFFEE58)),
    _FlowLayer('Emotional State', 'Mood modulation', 'Emotional weight multipliers, state transitions', Icons.mood, Color(0xFF66BB6A)),
    _FlowLayer('Orchestration', 'Context decisions', 'Game-mode-aware orchestration, context overrides', Icons.auto_awesome, Color(0xFF26C6DA)),
    _FlowLayer('AUREXIS Modifier', 'Intelligence layer', 'Parameter map generation, volatility/RTP-based modification', Icons.psychology, Color(0xFF42A5F5)),
    _FlowLayer('Voice Allocation', 'Voice pool mgmt', 'Voice budget enforcement, stealing, virtual voices', Icons.graphic_eq, Color(0xFF7E57C2)),
    _FlowLayer('DSP Execution', 'Audio processing', 'Actual audio rendering: EQ, dynamics, spatial, effects', Icons.surround_sound, Color(0xFFAB47BC)),
    _FlowLayer('Analytics', 'Feedback loop', 'Performance metrics, coverage tracking, profiler data', Icons.analytics, Color(0xFF78909C)),
  ];
}

class _FlowLayer {
  final String name;
  final String description;
  final String detailDescription;
  final IconData icon;
  final Color color;
  const _FlowLayer(this.name, this.description, this.detailDescription, this.icon, this.color);
}
