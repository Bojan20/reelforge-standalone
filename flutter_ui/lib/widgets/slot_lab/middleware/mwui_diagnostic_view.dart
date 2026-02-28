import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/state_gate_provider.dart';
import '../../../providers/slot_lab/priority_engine_provider.dart';
import '../../../providers/slot_lab/emotional_state_provider.dart';
import '../../../providers/slot_lab/orchestration_engine_provider.dart';
import '../../../providers/subsystems/voice_pool_provider.dart';
import '../../../providers/subsystems/state_groups_provider.dart';
import '../../../providers/subsystems/rtpc_system_provider.dart';
import '../../../providers/subsystems/ducking_system_provider.dart';
import '../../../providers/subsystems/event_profiler_provider.dart';
import '../../../providers/aurexis_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-4: DIAGNOSTIC View — Raw State + Provider Values + Timing
///
/// 4 sub-tabs:
/// - Raw State: All provider current values
/// - Provider Values: Decomposed middleware subsystems
/// - Pipeline Timing: Latency per stage
/// - Voice Pool: Active/virtual/stolen/budget
class MwuiDiagnosticView extends StatefulWidget {
  const MwuiDiagnosticView({super.key});

  @override
  State<MwuiDiagnosticView> createState() => _MwuiDiagnosticViewState();
}

enum _DiagTab { rawState, providers, timing, voicePool }

class _MwuiDiagnosticViewState extends State<MwuiDiagnosticView> {
  _DiagTab _activeTab = _DiagTab.rawState;

  StateGateProvider? _gate;
  PriorityEngineProvider? _priority;
  EmotionalStateProvider? _emotional;
  OrchestrationEngineProvider? _orchestration;
  VoicePoolProvider? _voicePool;
  StateGroupsProvider? _stateGroups;
  RtpcSystemProvider? _rtpc;
  DuckingSystemProvider? _ducking;
  EventProfilerProvider? _profiler;
  AurexisProvider? _aurexis;

  @override
  void initState() {
    super.initState();
    _tryGet<StateGateProvider>((p) => _gate = p);
    _tryGet<PriorityEngineProvider>((p) => _priority = p);
    _tryGet<EmotionalStateProvider>((p) => _emotional = p);
    _tryGet<OrchestrationEngineProvider>((p) => _orchestration = p);
    _tryGet<VoicePoolProvider>((p) => _voicePool = p);
    _tryGet<StateGroupsProvider>((p) => _stateGroups = p);
    _tryGet<RtpcSystemProvider>((p) => _rtpc = p);
    _tryGet<DuckingSystemProvider>((p) => _ducking = p);
    _tryGet<EventProfilerProvider>((p) => _profiler = p);
    _tryGet<AurexisProvider>((p) => _aurexis = p);
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
    _voicePool?.removeListener(_onUpdate);
    _stateGroups?.removeListener(_onUpdate);
    _rtpc?.removeListener(_onUpdate);
    _ducking?.removeListener(_onUpdate);
    _profiler?.removeListener(_onUpdate);
    _aurexis?.removeListener(_onUpdate);
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
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_mode, size: 14, color: Color(0xFFFF7043)),
          const SizedBox(width: 6),
          Text('Diagnostics', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('RAW', style: TextStyle(color: const Color(0xFFFF7043).withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: _DiagTab.values.map((tab) {
          final isActive = _activeTab == tab;
          return GestureDetector(
            onTap: () => setState(() => _activeTab = tab),
            child: Container(
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? Colors.white.withOpacity(0.06) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                border: isActive
                    ? Border(bottom: BorderSide(color: const Color(0xFFFF7043), width: 1.5))
                    : null,
              ),
              child: Text(
                _tabName(tab),
                style: TextStyle(
                  color: isActive ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.4),
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case _DiagTab.rawState: return _buildRawState();
      case _DiagTab.providers: return _buildProviders();
      case _DiagTab.timing: return _buildTiming();
      case _DiagTab.voicePool: return _buildVoicePool();
    }
  }

  Widget _buildRawState() {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _diagSection('STATE GATE', [
          _diagRow('substate', _gate?.currentSubstate.name ?? 'n/a'),
          _diagRow('autoplay', '${_gate?.isAutoplay ?? false}'),
          _diagRow('turbo', '${_gate?.isTurbo ?? false}'),
        ]),
        _diagSection('PRIORITY ENGINE', [
          _diagRow('active_behaviors', '${_priority?.activeBehaviors.length ?? 0}'),
          _diagRow('resolutions', '${_priority?.resolutionLog.length ?? 0}'),
        ]),
        _diagSection('EMOTIONAL STATE', [
          _diagRow('state', _emotional?.state.name ?? 'n/a'),
          _diagRow('intensity', (_emotional?.intensity ?? 0).toStringAsFixed(4)),
          _diagRow('tension', (_emotional?.tension ?? 0).toStringAsFixed(4)),
        ]),
        _diagSection('ORCHESTRATION', [
          _diagRow('escalation', _orchestration?.context.escalationIndex.toStringAsFixed(3) ?? 'n/a'),
          _diagRow('decisions', '${_orchestration?.decisions.length ?? 0}'),
        ]),
        _diagSection('AUREXIS', [
          _diagRow('enabled', '${_aurexis?.enabled ?? false}'),
          _diagRow('initialized', '${_aurexis?.initialized ?? false}'),
          _diagRow('volatility', _aurexis?.volatility.toStringAsFixed(6) ?? 'n/a'),
          _diagRow('rtp', _aurexis?.rtp.toStringAsFixed(4) ?? 'n/a'),
          _diagRow('win_multiplier', _aurexis?.winMultiplier.toStringAsFixed(6) ?? 'n/a'),
          _diagRow('jackpot_proximity', _aurexis?.jackpotProximity.toStringAsFixed(6) ?? 'n/a'),
          _diagRow('fatigue_level', _aurexis?.fatigueLevel.name ?? 'n/a'),
          _diagRow('ticking', '${_aurexis?.isTicking ?? false}'),
        ]),
      ],
    );
  }

  Widget _buildProviders() {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _diagSection('STATE GROUPS', [
          _diagRow('groups', '${_stateGroups?.stateGroups.length ?? 0}'),
        ]),
        _diagSection('RTPC', [
          _diagRow('parameters', '${_rtpc?.rtpcCount ?? 0}'),
          _diagRow('bindings', '${_rtpc?.rtpcBindings.length ?? 0}'),
          _diagRow('macros', '${_rtpc?.macroCount ?? 0}'),
          _diagRow('dsp_bindings', '${_rtpc?.dspBindingCount ?? 0}'),
        ]),
        _diagSection('DUCKING', [
          _diagRow('rules', '${_ducking?.ruleCount ?? 0}'),
          _diagRow('assigned_nodes', '${_ducking?.assignedBehaviorNodes.length ?? 0}'),
        ]),
        _diagSection('VOICE POOL', [
          _diagRow('active', '${_voicePool?.activeCount ?? 0}'),
          _diagRow('virtual', '${_voicePool?.virtualCount ?? 0}'),
          _diagRow('stolen', '${_voicePool?.stealCount ?? 0}'),
          _diagRow('max', '${_voicePool?.engineMaxVoices ?? 0}'),
          _diagRow('utilization', '${((_voicePool?.engineUtilization ?? 0) * 100).toStringAsFixed(1)}%'),
        ]),
      ],
    );
  }

  Widget _buildTiming() {
    final profiler = _profiler;
    if (profiler == null) {
      return Center(
        child: Text('Profiler not available', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _sectionLabel('PROFILER STATS'),
        const SizedBox(height: 6),
        _diagRow('total_events', '${profiler.totalEvents}'),
        _diagRow('events/sec', '${profiler.eventsPerSecond}'),
        _diagRow('peak_events/sec', '${profiler.peakEventsPerSecond}'),
        _diagRow('avg_latency', '${profiler.avgLatencyUs.toStringAsFixed(1)} us'),
        _diagRow('max_latency', '${profiler.maxLatencyUs.toStringAsFixed(1)} us'),
        _diagRow('dsp_load', '${(profiler.dspLoad * 100).toStringAsFixed(1)}%'),
        _diagRow('voice_starts', '${profiler.voiceStarts}'),
        _diagRow('voice_stops', '${profiler.voiceStops}'),
        _diagRow('voice_steals', '${profiler.voiceSteals}'),
        _diagRow('errors', '${profiler.errors}'),
        _diagRow('overloads', '${profiler.overloadCount}'),
        const SizedBox(height: 12),
        _sectionLabel('STAGE BREAKDOWN'),
        const SizedBox(height: 4),
        for (final entry in profiler.stageBreakdown.entries)
          _diagRow(entry.key, '${entry.value.toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _buildVoicePool() {
    final vp = _voicePool;
    if (vp == null) {
      return Center(
        child: Text('Voice pool not available', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
      );
    }

    final util = vp.engineUtilization / 100.0;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _sectionLabel('VOICE POOL STATUS'),
        const SizedBox(height: 6),
        Row(
          children: [
            _bigMetric('Active', '${vp.activeCount}', const Color(0xFF42A5F5)),
            _bigMetric('Virtual', '${vp.virtualCount}', const Color(0xFF7E57C2)),
            _bigMetric('Stolen', '${vp.stealCount}', const Color(0xFFEF5350)),
            _bigMetric('Max', '${vp.engineMaxVoices}', const Color(0xFF66BB6A)),
          ],
        ),
        const SizedBox(height: 12),
        _sectionLabel('POOL BREAKDOWN'),
        const SizedBox(height: 6),
        for (final entry in vp.allPoolStats.entries)
          _poolRow(entry.value),
        const SizedBox(height: 12),
        _sectionLabel('UTILIZATION'),
        const SizedBox(height: 4),
        SizedBox(
          height: 8,
          child: LinearProgressIndicator(
            value: util.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation(
              util > 0.9
                  ? const Color(0xFFEF5350)
                  : util > 0.7
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFF66BB6A),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${vp.engineUtilization.toStringAsFixed(1)}% voice budget used',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9),
        ),
        const SizedBox(height: 12),
        _sectionLabel('BY SOURCE'),
        const SizedBox(height: 4),
        _diagRow('DAW', '${vp.dawVoices}'),
        _diagRow('SlotLab', '${vp.slotLabVoices}'),
        _diagRow('Middleware', '${vp.middlewareVoices}'),
        _diagRow('Browser', '${vp.browserVoices}'),
        const SizedBox(height: 8),
        _sectionLabel('BY BUS'),
        const SizedBox(height: 4),
        _diagRow('SFX', '${vp.sfxVoices}'),
        _diagRow('Music', '${vp.musicVoices}'),
        _diagRow('Voice', '${vp.voiceVoices}'),
        _diagRow('Ambience', '${vp.ambienceVoices}'),
        _diagRow('Aux', '${vp.auxVoices}'),
        _diagRow('Master', '${vp.masterVoices}'),
      ],
    );
  }

  Widget _poolRow(PoolTypeStats pool) {
    final ratio = pool.maxVoices > 0 ? (pool.activeVoices / pool.maxVoices).clamp(0.0, 1.0) : 0.0;
    final color = ratio > 0.9 ? const Color(0xFFEF5350) :
                  ratio > 0.6 ? const Color(0xFFFFB74D) : const Color(0xFF66BB6A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(pool.type.displayName, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
          ),
          Expanded(
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: ratio,
                backgroundColor: Colors.white.withOpacity(0.06),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${pool.activeVoices}/${pool.maxVoices}',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigMetric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8)),
        ],
      ),
    );
  }

  Widget _diagSection(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(title),
          const SizedBox(height: 3),
          ...rows,
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: const Color(0xFFFF7043).withOpacity(0.6),
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, fontFamily: 'monospace')),
          ),
          Text(value, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  String _tabName(_DiagTab tab) {
    switch (tab) {
      case _DiagTab.rawState: return 'Raw State';
      case _DiagTab.providers: return 'Providers';
      case _DiagTab.timing: return 'Timing';
      case _DiagTab.voicePool: return 'Voice Pool';
    }
  }
}
