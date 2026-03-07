/// FluxForge Studio — Tempo State Panel
///
/// Wwise-style interactive music tempo state management.
/// Fully wired: auto-init, live rule sync, state add/delete,
/// active state tracking from engine phase changes.
///
/// Layout: Left (State List) | Center (Beat Grid + Crossfade Viz) | Right (Transition Rules)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _TempoStateEntry {
  int id;
  final String name;
  final double targetBpm;
  bool isActive;

  _TempoStateEntry({
    required this.id,
    required this.name,
    required this.targetBpm,
    this.isActive = false,
  });
}

class _TransitionRuleEntry {
  String fromStateName;
  String toStateName;
  int syncMode; // 0=immediate, 1=beat, 2=bar, 3=phrase, 4=downbeat
  int durationBars;
  int rampType; // 0=instant, 1=linear, 2=sCurve
  int fadeCurve; // 0=linear, 1=equalPower, 2=sCurve

  _TransitionRuleEntry({
    this.fromStateName = '',
    this.toStateName = '',
    this.syncMode = 0,
    this.durationBars = 0,
    this.rampType = 0,
    this.fadeCurve = 0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const _kAccent = FluxForgeTheme.accentCyan;
const _kAccentDim = Color(0xFF206880);
const _kBeatActive = Color(0xFF50FF98);
const _kCrossfadeColor = FluxForgeTheme.accentOrange;

const _syncModeLabels = ['Immediate', 'Beat', 'Bar', 'Phrase', 'Downbeat'];
const _rampTypeLabels = ['Instant', 'Linear', 'S-Curve'];
const _fadeCurveLabels = ['Linear', 'Equal Power', 'S-Curve'];

const _stateColors = [
  Color(0xFF5AA8FF), // Blue
  Color(0xFFFF9850), // Orange
  Color(0xFFB080FF), // Purple
  Color(0xFF50FF98), // Green
  Color(0xFFFFE050), // Yellow
  Color(0xFFFF80B0), // Pink
  Color(0xFF50D8FF), // Cyan
  Color(0xFFFF5068), // Red
];

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class TempoStatePanel extends StatefulWidget {
  final double height;

  const TempoStatePanel({super.key, this.height = 350});

  @override
  State<TempoStatePanel> createState() => _TempoStatePanelState();
}

class _TempoStatePanelState extends State<TempoStatePanel> {
  final List<_TempoStateEntry> _states = [];
  final List<_TransitionRuleEntry> _rules = [];
  bool _engineInitialized = false;
  Timer? _pollTimer;

  // Live monitoring
  double _currentBpm = 0;
  double _currentBeat = 0;
  int _currentBar = 0;
  int _enginePhase = 0; // 0=steady, 1=waitSync, 2=crossfading
  double _crossfadeProgress = 0;

  // Track previous phase for detecting crossfade completion
  int _previousPhase = 0;
  String _pendingTargetName = '';

  // Config
  double _sourceBpm = 120.0;
  int _beatsPerBar = 4;

  // Editing
  final _nameController = TextEditingController();
  final _bpmController = TextEditingController();
  int? _selectedRuleIndex;

  @override
  void initState() {
    super.initState();
    _addDefaultStates();
    // Auto-init engine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initEngine();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nameController.dispose();
    _bpmController.dispose();
    if (_engineInitialized) {
      NativeFFI.instance.tempoStateDestroy();
    }
    super.dispose();
  }

  void _addDefaultStates() {
    _states.addAll([
      _TempoStateEntry(id: 0, name: 'Base Game', targetBpm: 100),
      _TempoStateEntry(id: 0, name: 'Free Spins', targetBpm: 130),
      _TempoStateEntry(id: 0, name: 'Bonus', targetBpm: 160),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void _initEngine() {
    final ffi = NativeFFI.instance;
    ffi.tempoStateDestroy();
    _engineInitialized = ffi.tempoStateInit(_sourceBpm, _beatsPerBar, 44100);

    if (!_engineInitialized) return;

    // Register all states
    for (var i = 0; i < _states.length; i++) {
      final id = ffi.tempoStateAdd(_states[i].name, _states[i].targetBpm);
      _states[i].id = id;
    }

    // Set initial state
    if (_states.isNotEmpty) {
      ffi.tempoStateSetInitial(_states[0].name);
      for (final s in _states) {
        s.isActive = (s.name == _states[0].name);
      }
    }

    // Register default transition rule
    ffi.tempoStateSetDefaultTransition(0, 0, 0, 0);

    // Register all custom rules
    for (final rule in _rules) {
      _sendRuleToEngine(rule);
    }

    // Start polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _poll());
    setState(() {});
  }

  void _reinitEngine() {
    _pollTimer?.cancel();
    _initEngine();
  }

  void _poll() {
    if (!_engineInitialized || !mounted) return;
    final ffi = NativeFFI.instance;
    final newPhase = ffi.tempoStateGetPhase();

    setState(() {
      _currentBpm = ffi.tempoStateGetBpm();
      _currentBeat = ffi.tempoStateGetBeat();
      _currentBar = ffi.tempoStateGetBar();
      _enginePhase = newPhase;
      _crossfadeProgress = ffi.tempoStateGetCrossfadeProgress();

      // Detect crossfade completion: phase went from 2 (crossfading) to 0 (steady)
      if (_previousPhase == 2 && newPhase == 0 && _pendingTargetName.isNotEmpty) {
        for (final s in _states) {
          s.isActive = (s.name == _pendingTargetName);
        }
        _pendingTargetName = '';
      }
      _previousPhase = newPhase;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE MANAGEMENT (live-wired)
  // ═══════════════════════════════════════════════════════════════════════════

  void _addState(String name, double bpm) {
    final entry = _TempoStateEntry(id: 0, name: name, targetBpm: bpm);

    if (_engineInitialized) {
      final id = NativeFFI.instance.tempoStateAdd(name, bpm);
      entry.id = id;
    }

    setState(() {
      _states.add(entry);
    });

    // If only state and engine is initialized, make it active
    if (_states.length == 1 && _engineInitialized) {
      NativeFFI.instance.tempoStateSetInitial(name);
      setState(() => entry.isActive = true);
    }
  }

  void _deleteState(int index) {
    final removed = _states[index];
    setState(() {
      _states.removeAt(index);
      // Clean up rules referencing this state
      _rules.removeWhere((r) =>
        r.fromStateName == removed.name || r.toStateName == removed.name);
    });

    // Re-init engine since FFI doesn't have a remove_state function
    if (_engineInitialized) {
      _reinitEngine();
    }
  }

  void _triggerState(String name) {
    if (!_engineInitialized) return;
    NativeFFI.instance.tempoStateTrigger(name);

    // Optimistic: mark as active immediately for cut transitions
    // For crossfade, _pendingTargetName tracks the real completion
    _pendingTargetName = name;
    setState(() {
      for (final s in _states) {
        s.isActive = (s.name == name);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RULE MANAGEMENT (live-wired)
  // ═══════════════════════════════════════════════════════════════════════════

  void _sendRuleToEngine(_TransitionRuleEntry rule) {
    if (!_engineInitialized) return;
    final fromState = _states.where((s) => s.name == rule.fromStateName).firstOrNull;
    final toState = _states.where((s) => s.name == rule.toStateName).firstOrNull;
    if (fromState == null || toState == null) return;
    if (fromState.id == 0 || toState.id == 0) return;

    NativeFFI.instance.tempoStateSetTransition(
      fromState.id, toState.id,
      rule.syncMode, rule.durationBars,
      rule.rampType, rule.fadeCurve,
    );
  }

  void _addRule() {
    setState(() {
      _rules.add(_TransitionRuleEntry());
      _selectedRuleIndex = _rules.length - 1;
    });
  }

  void _deleteRule(int index) {
    setState(() {
      _rules.removeAt(index);
      _selectedRuleIndex = null;
    });
    // Re-send all rules (FFI has no remove_rule)
    if (_engineInitialized) {
      for (final rule in _rules) {
        _sendRuleToEngine(rule);
      }
    }
  }

  void _updateRule(int index, void Function(_TransitionRuleEntry) mutator) {
    final rule = _rules[index];
    mutator(rule);
    _sendRuleToEngine(rule);
    setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 220, child: _buildStateList()),
                _divider(),
                Expanded(child: _buildCenterPanel()),
                _divider(),
                SizedBox(width: 240, child: _buildTransitionRules()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER (40px)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed, size: 16, color: _kAccent),
          const SizedBox(width: 8),
          const Text(
            'TEMPO STATE ENGINE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _kAccent,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 16),
          _headerLabel('SRC'),
          const SizedBox(width: 4),
          _headerValue('${_sourceBpm.toInt()} BPM'),
          const SizedBox(width: 12),
          _headerLabel('SIG'),
          const SizedBox(width: 4),
          _headerValue('$_beatsPerBar/4'),
          const SizedBox(width: 12),
          // Engine status dot
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _engineInitialized ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
              boxShadow: _engineInitialized
                ? [BoxShadow(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5), blurRadius: 4)]
                : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _engineInitialized ? 'LIVE' : 'OFF',
            style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5,
              color: _engineInitialized ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
            ),
          ),
          const Spacer(),
          // Live indicators
          if (_engineInitialized) ...[
            _liveIndicator('BPM', _currentBpm.toStringAsFixed(1), FluxForgeTheme.accentBlue),
            const SizedBox(width: 12),
            _liveIndicator('BAR', '${_currentBar + 1}', FluxForgeTheme.accentGreen),
            const SizedBox(width: 12),
            _liveIndicator('BEAT', _currentBeat.toStringAsFixed(1), FluxForgeTheme.accentYellow),
            const SizedBox(width: 12),
            _phaseIndicator(),
            const SizedBox(width: 16),
          ],
          // Reset button
          _buildActionButton(
            'RESET', Icons.refresh, FluxForgeTheme.accentOrange, _reinitEngine,
          ),
        ],
      ),
    );
  }

  Widget _headerLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary, letterSpacing: 0.5),
  );

  Widget _headerValue(String text) => Text(
    text,
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: FluxForgeTheme.textSecondary),
  );

  Widget _liveIndicator(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.6), letterSpacing: 0.5)),
        const SizedBox(width: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Text(
            value,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _phaseIndicator() {
    final phaseIndex = _enginePhase.clamp(0, 2);
    final phases = ['STEADY', 'SYNC', 'XFADE'];
    final colors = [FluxForgeTheme.accentGreen, FluxForgeTheme.accentYellow, _kCrossfadeColor];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors[phaseIndex].withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colors[phaseIndex].withValues(alpha: 0.4)),
      ),
      child: Text(
        phases[phaseIndex],
        style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.bold, color: colors[phaseIndex], letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT: STATE LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStateList() {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('TEMPO STATES', Icons.library_music),
          _buildSourceBpmRow(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _states.length,
              itemBuilder: (_, i) => _buildStateCard(i),
            ),
          ),
          _buildAddStateRow(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: _kAccent),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _kAccent, letterSpacing: 0.8)),
        ],
      ),
    );
  }

  Widget _buildSourceBpmRow() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
      child: Row(
        children: [
          const Text('Source BPM', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
          const Spacer(),
          SizedBox(
            width: 80,
            child: Slider(
              value: _sourceBpm,
              min: 60, max: 200,
              activeColor: _kAccent,
              inactiveColor: _kAccentDim,
              onChanged: (v) {
                setState(() => _sourceBpm = v.roundToDouble());
              },
              onChangeEnd: (_) {
                // Re-init engine with new source BPM
                if (_engineInitialized) _reinitEngine();
              },
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${_sourceBpm.toInt()}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: FluxForgeTheme.textPrimary, fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard(int index) {
    final state = _states[index];
    final color = _stateColors[index % _stateColors.length];
    final isActive = state.isActive;

    return GestureDetector(
      onTap: _engineInitialized ? () => _triggerState(state.name) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Color dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: isActive ? color : color.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                boxShadow: isActive ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)] : null,
              ),
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              child: Text(
                state.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? color : FluxForgeTheme.textPrimary,
                ),
              ),
            ),
            // BPM badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${state.targetBpm.toInt()} BPM',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.8),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // Stretch factor
            if (_engineInitialized)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '×${(_sourceBpm / state.targetBpm).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary, fontFamily: 'monospace'),
                ),
              ),
            // Delete button
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _deleteState(index),
              child: Icon(Icons.close, size: 12, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddStateRow() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'State name...',
                  hintStyle: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _kAccent)),
                  filled: true,
                  fillColor: FluxForgeTheme.bgSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            height: 26,
            child: TextField(
              controller: _bpmController,
              style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'BPM',
                hintStyle: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _kAccent)),
                filled: true,
                fillColor: FluxForgeTheme.bgSurface,
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              final name = _nameController.text.trim();
              final bpm = double.tryParse(_bpmController.text.trim());
              if (name.isEmpty || bpm == null || bpm < 20 || bpm > 999) return;
              // Check for duplicate name
              if (_states.any((s) => s.name == name)) return;
              _addState(name, bpm);
              _nameController.clear();
              _bpmController.clear();
            },
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.add, size: 14, color: _kAccent),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CENTER: BEAT GRID + CROSSFADE VISUALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCenterPanel() {
    return Container(
      color: FluxForgeTheme.bgDeepest,
      child: Column(
        children: [
          _sectionHeader('BEAT GRID & CROSSFADE', Icons.graphic_eq),
          Expanded(
            child: _engineInitialized
              ? CustomPaint(
                  painter: _BeatGridPainter(
                    currentBeat: _currentBeat,
                    currentBar: _currentBar,
                    beatsPerBar: _beatsPerBar,
                    bpm: _currentBpm,
                    phase: _enginePhase,
                    crossfadeProgress: _crossfadeProgress,
                    states: _states,
                  ),
                  child: const SizedBox.expand(),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed, size: 28, color: _kAccent.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      const Text(
                        'Engine initializing...',
                        style: TextStyle(fontSize: 12, color: FluxForgeTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT: TRANSITION RULES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTransitionRules() {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('TRANSITION RULES', Icons.swap_horiz),
          Expanded(
            child: _rules.isEmpty
              ? Center(
                  child: Text(
                    'No rules — uses default\n(immediate, no crossfade)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(6),
                  itemCount: _rules.length,
                  itemBuilder: (_, i) => _buildRuleCard(i),
                ),
          ),
          _buildAddRuleButton(),
        ],
      ),
    );
  }

  Widget _buildRuleCard(int index) {
    final rule = _rules[index];
    final isSelected = _selectedRuleIndex == index;
    final fromDisplay = rule.fromStateName.isEmpty ? 'Any' : rule.fromStateName;
    final toDisplay = rule.toStateName.isEmpty ? 'Any' : rule.toStateName;

    // Available state names for dropdowns (with empty = Any)
    final stateNames = ['', ..._states.map((s) => s.name)];
    final stateLabels = ['Any', ..._states.map((s) => s.name)];

    return GestureDetector(
      onTap: () => setState(() => _selectedRuleIndex = isSelected ? null : index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? _kCrossfadeColor.withValues(alpha: 0.08) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? _kCrossfadeColor.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // From → To + delete button
            Row(
              children: [
                _ruleBadge(fromDisplay, FluxForgeTheme.accentBlue),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_forward, size: 10, color: FluxForgeTheme.textTertiary),
                ),
                _ruleBadge(toDisplay, _kCrossfadeColor),
                const Spacer(),
                GestureDetector(
                  onTap: () => _deleteRule(index),
                  child: Icon(Icons.close, size: 11, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 8),
              // From state dropdown
              _ruleDropdown('From', rule.fromStateName, stateNames, stateLabels,
                (v) => _updateRule(index, (r) => r.fromStateName = v)),
              const SizedBox(height: 4),
              // To state dropdown
              _ruleDropdown('To', rule.toStateName, stateNames, stateLabels,
                (v) => _updateRule(index, (r) => r.toStateName = v)),
              const SizedBox(height: 6),
              // Sync mode
              _ruleSelect('Sync', _syncModeLabels, rule.syncMode,
                (v) => _updateRule(index, (r) => r.syncMode = v)),
              const SizedBox(height: 4),
              // Duration
              _ruleSlider('Bars', '${rule.durationBars}', rule.durationBars.toDouble(), 0, 8,
                (v) => _updateRule(index, (r) => r.durationBars = v.round())),
              const SizedBox(height: 4),
              // Ramp type
              _ruleSelect('Ramp', _rampTypeLabels, rule.rampType,
                (v) => _updateRule(index, (r) => r.rampType = v)),
              const SizedBox(height: 4),
              // Fade curve
              _ruleSelect('Curve', _fadeCurveLabels, rule.fadeCurve,
                (v) => _updateRule(index, (r) => r.fadeCurve = v)),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                '${_syncModeLabels[rule.syncMode]} · ${rule.durationBars} bars · ${_rampTypeLabels[rule.rampType]}',
                style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ruleBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _ruleDropdown(String label, String value, List<String> values, List<String> labels, ValueChanged<String> onChanged) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary))),
        Expanded(
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: values.contains(value) ? value : '',
                isDense: true,
                isExpanded: true,
                dropdownColor: FluxForgeTheme.bgElevated,
                style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary),
                icon: const Icon(Icons.unfold_more, size: 10, color: FluxForgeTheme.textTertiary),
                items: List.generate(values.length, (i) =>
                  DropdownMenuItem(value: values[i], child: Text(labels[i], style: const TextStyle(fontSize: 10))),
                ),
                onChanged: (v) { if (v != null) onChanged(v); },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ruleSelect(String label, List<String> options, int selected, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary))),
        Expanded(
          child: Wrap(
            spacing: 3,
            children: List.generate(options.length, (i) {
              final isActive = i == selected;
              return GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive ? _kAccent.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: isActive ? _kAccent.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle),
                  ),
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 8, fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? _kAccent : FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _ruleSlider(String label, String valueText, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: _kAccent,
              inactiveTrackColor: _kAccentDim,
              thumbColor: _kAccent,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(value: value, min: min, max: max, divisions: (max - min).round(), onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(valueText, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary, fontFamily: 'monospace'), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _buildAddRuleButton() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: GestureDetector(
        onTap: _addRule,
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _kAccent.withValues(alpha: 0.2)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 12, color: _kAccent),
              SizedBox(width: 4),
              Text('ADD RULE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _kAccent, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BEAT GRID PAINTER (Custom visualization)
// ═══════════════════════════════════════════════════════════════════════════════

class _BeatGridPainter extends CustomPainter {
  final double currentBeat;
  final int currentBar;
  final int beatsPerBar;
  final double bpm;
  final int phase;
  final double crossfadeProgress;
  final List<_TempoStateEntry> states;

  _BeatGridPainter({
    required this.currentBeat,
    required this.currentBar,
    required this.beatsPerBar,
    required this.bpm,
    required this.phase,
    required this.crossfadeProgress,
    required this.states,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    _drawGrid(canvas, w, h);
    _drawBeatIndicators(canvas, w, h);

    if (phase == 2) {
      _drawCrossfade(canvas, w, h);
    }

    _drawBpmDisplay(canvas, w, h);
  }

  void _drawGrid(Canvas canvas, double w, double h) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1A1A24)
      ..strokeWidth = 1;

    for (var i = 0; i <= beatsPerBar; i++) {
      final x = (i / beatsPerBar) * w;
      final isDownbeat = i == 0;
      gridPaint.color = isDownbeat ? const Color(0xFF303040) : const Color(0xFF1A1A24);
      gridPaint.strokeWidth = isDownbeat ? 2 : 1;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    gridPaint.color = const Color(0xFF1A1A24);
    gridPaint.strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), gridPaint);
  }

  void _drawBeatIndicators(Canvas canvas, double w, double h) {
    final indicatorH = 60.0;
    final y = h - indicatorH - 20;

    for (var i = 0; i < beatsPerBar; i++) {
      final x = (i + 0.5) / beatsPerBar * w;
      final isCurrentBeat = currentBeat >= i && currentBeat < i + 1;
      final beatProgress = isCurrentBeat ? (currentBeat - i) : 0.0;

      final radius = isCurrentBeat ? 14.0 : 10.0;
      final color = isCurrentBeat ? _kBeatActive : const Color(0xFF303040);

      if (isCurrentBeat) {
        final glowPaint = Paint()
          ..color = _kBeatActive.withValues(alpha: 0.15 * (1 - beatProgress))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(Offset(x, y + indicatorH / 2), 24, glowPaint);
      }

      final circlePaint = Paint()..color = color;
      canvas.drawCircle(Offset(x, y + indicatorH / 2), radius, circlePaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isCurrentBeat ? const Color(0xFF0A0A0C) : const Color(0xFF606070),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y + indicatorH / 2 - textPainter.height / 2));
    }
  }

  void _drawCrossfade(Canvas canvas, double w, double h) {
    final barH = 12.0;
    final y = 40.0;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(20, y, w - 40, barH),
      const Radius.circular(6),
    );
    canvas.drawRRect(bgRect, Paint()..color = const Color(0xFF1E1E28));

    final fillW = (w - 40) * crossfadeProgress;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(20, y, fillW, barH),
      const Radius.circular(6),
    );
    final gradient = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5AA8FF), Color(0xFFFF9850)],
      ).createShader(Rect.fromLTWH(20, y, w - 40, barH));
    canvas.drawRRect(fillRect, gradient);

    final label = TextPainter(
      text: TextSpan(
        text: 'CROSSFADE ${(crossfadeProgress * 100).toInt()}%',
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB8B8C0), letterSpacing: 0.8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(w / 2 - label.width / 2, y + barH + 4));
  }

  void _drawBpmDisplay(Canvas canvas, double w, double h) {
    final bpmText = TextPainter(
      text: TextSpan(
        text: bpm.toStringAsFixed(1),
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w200,
          color: _kAccent.withValues(alpha: 0.3),
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    bpmText.paint(canvas, Offset(w / 2 - bpmText.width / 2, h / 2 - bpmText.height / 2 - 20));

    final bpmLabel = TextPainter(
      text: TextSpan(
        text: 'BPM',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _kAccent.withValues(alpha: 0.2),
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    bpmLabel.paint(canvas, Offset(w / 2 - bpmLabel.width / 2, h / 2 + bpmText.height / 2 - 20));

    final barText = TextPainter(
      text: TextSpan(
        text: 'BAR ${currentBar + 1}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    barText.paint(canvas, Offset(w / 2 - barText.width / 2, h / 2 + bpmText.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BeatGridPainter oldDelegate) {
    return currentBeat != oldDelegate.currentBeat
        || currentBar != oldDelegate.currentBar
        || bpm != oldDelegate.bpm
        || phase != oldDelegate.phase
        || crossfadeProgress != oldDelegate.crossfadeProgress;
  }
}
