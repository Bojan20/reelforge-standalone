/// FF-G Gate Panel — Pro-G 2026 Premium Upgrade
///
/// Professional gate interface with FabFilter-authentic visuals:
/// - Scrolling I/O waveform with state-colored output fills
/// - Glass transfer curve with animated input dot + glow
/// - Envelope visualization (ATT → HOLD → REL shape overlay)
/// - Animated gate state badge with pulse glow
/// - Range indicator (attenuation zone fill on display)
/// - Sidechain filter response mini-curve
/// - Hysteresis zone with gradient tint
/// - dB axis labels + time grid on scrolling display

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Gate operation mode
enum GateMode {
  gate('Gate', 'Standard noise gate'),
  duck('Duck', 'Ducking/sidechain compression'),
  expand('Expand', 'Downward expansion');

  final String label;
  final String description;
  const GateMode(this.label, this.description);
}

/// Gate state for visualization
enum GateState {
  open,
  closing,
  closed,
  opening,
}

/// Level sample for scrolling display
class GateLevelSample {
  final double input;
  final double output;
  final double gateGain; // 0-1 (closed to open)
  final GateState state;

  GateLevelSample({
    required this.input,
    required this.output,
    required this.gateGain,
    required this.state,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class GateSnapshot implements DspParameterSnapshot {
  final double threshold, range, attack, hold, release, hysteresis;
  final GateMode mode;
  final bool sidechainEnabled, sidechainAudition;
  final double sidechainHpf, sidechainLpf;
  final double lookahead, ratio;

  const GateSnapshot({
    required this.threshold, required this.range, required this.attack,
    required this.hold, required this.release, required this.hysteresis,
    required this.mode, required this.sidechainEnabled,
    required this.sidechainHpf, required this.sidechainLpf,
    required this.sidechainAudition, required this.lookahead,
    required this.ratio,
  });

  @override
  GateSnapshot copy() => GateSnapshot(
    threshold: threshold, range: range, attack: attack, hold: hold,
    release: release, hysteresis: hysteresis, mode: mode,
    sidechainEnabled: sidechainEnabled, sidechainHpf: sidechainHpf,
    sidechainLpf: sidechainLpf, sidechainAudition: sidechainAudition,
    lookahead: lookahead, ratio: ratio,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! GateSnapshot) return false;
    return threshold == other.threshold && range == other.range &&
        attack == other.attack && hold == other.hold &&
        release == other.release && hysteresis == other.hysteresis &&
        mode == other.mode && sidechainEnabled == other.sidechainEnabled &&
        sidechainHpf == other.sidechainHpf && sidechainLpf == other.sidechainLpf &&
        sidechainAudition == other.sidechainAudition &&
        lookahead == other.lookahead && ratio == other.ratio;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterGatePanel extends FabFilterPanelBase {
  const FabFilterGatePanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-G',
          icon: Icons.door_sliding,
          accentColor: FabFilterColors.green,
          nodeType: DspNodeType.gate,
        );

  @override
  State<FabFilterGatePanel> createState() => _FabFilterGatePanelState();
}

class _FabFilterGatePanelState extends State<FabFilterGatePanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  // Main parameters
  double _threshold = -40.0; // dB
  double _range = -80.0; // dB (how much to reduce when closed)
  double _attack = 1.0; // ms
  double _hold = 50.0; // ms
  double _release = 100.0; // ms
  double _hysteresis = 4.0; // dB

  // Mode
  GateMode _mode = GateMode.gate;

  // Sidechain
  bool _sidechainEnabled = false;
  double _sidechainHpf = 80.0; // Hz
  double _sidechainLpf = 12000.0; // Hz
  bool _sidechainAudition = false;

  // Expert
  double _lookahead = 0.0; // ms
  double _ratio = 100.0; // % (for expander mode)

  // Display
  final List<GateLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 200;

  // Real-time state
  double _currentInputLevel = -60.0;
  double _currentOutputLevel = -60.0;
  GateState _currentState = GateState.closed;
  double _gateOpen = 0.0; // 0-1 (closed to open)

  // Envelope animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Animation
  late AnimationController _meterController;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  // DspChainProvider integration
  String? _nodeId;
  int _slotIndex = -1;

  // A/B snapshots
  GateSnapshot? _snapshotA;
  GateSnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();

    _initializeProcessor();
    initBypassFromProvider();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);
    _meterController.repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.gate) {
        _nodeId = node.id;
        _slotIndex = chain.nodes.indexWhere((n) => n.id == _nodeId);
        _initialized = true;
        _readParamsFromEngine();
        break;
      }
    }
  }

  void _readParamsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    setState(() {
      _threshold = _ffi.insertGetParam(widget.trackId, _slotIndex, 0);
      _range = _ffi.insertGetParam(widget.trackId, _slotIndex, 1);
      _attack = _ffi.insertGetParam(widget.trackId, _slotIndex, 2);
      _hold = _ffi.insertGetParam(widget.trackId, _slotIndex, 3);
      _release = _ffi.insertGetParam(widget.trackId, _slotIndex, 4);
      final modeVal = _ffi.insertGetParam(widget.trackId, _slotIndex, 5).round();
      _mode = modeVal == 1 ? GateMode.duck : (modeVal == 2 ? GateMode.expand : GateMode.gate);
      _sidechainEnabled = _ffi.insertGetParam(widget.trackId, _slotIndex, 6) > 0.5;
      _sidechainHpf = _ffi.insertGetParam(widget.trackId, _slotIndex, 7);
      _sidechainLpf = _ffi.insertGetParam(widget.trackId, _slotIndex, 8);
      _lookahead = _ffi.insertGetParam(widget.trackId, _slotIndex, 9);
      _hysteresis = _ffi.insertGetParam(widget.trackId, _slotIndex, 10);
      _ratio = _ffi.insertGetParam(widget.trackId, _slotIndex, 11);
      _sidechainAudition = _ffi.insertGetParam(widget.trackId, _slotIndex, 12) > 0.5;
      if (_sidechainHpf < 20) _sidechainHpf = 80.0;
      if (_sidechainLpf < 1000) _sidechainLpf = 12000.0;
    });
  }

  // ─── A/B STATE ───────────────────────────────────────────────────────

  GateSnapshot _snap() => GateSnapshot(
    threshold: _threshold, range: _range, attack: _attack, hold: _hold,
    release: _release, hysteresis: _hysteresis, mode: _mode,
    sidechainEnabled: _sidechainEnabled, sidechainHpf: _sidechainHpf,
    sidechainLpf: _sidechainLpf, sidechainAudition: _sidechainAudition,
    lookahead: _lookahead, ratio: _ratio,
  );

  void _restore(GateSnapshot s) {
    setState(() {
      _threshold = s.threshold; _range = s.range; _attack = s.attack;
      _hold = s.hold; _release = s.release; _hysteresis = s.hysteresis;
      _mode = s.mode; _sidechainEnabled = s.sidechainEnabled;
      _sidechainHpf = s.sidechainHpf; _sidechainLpf = s.sidechainLpf;
      _sidechainAudition = s.sidechainAudition; _lookahead = s.lookahead;
      _ratio = s.ratio;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _range);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _attack);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _hold);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 5, _mode.index.toDouble());
    _ffi.insertSetParam(widget.trackId, _slotIndex, 6, _sidechainEnabled ? 1.0 : 0.0);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 7, _sidechainHpf);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 8, _sidechainLpf);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 9, _lookahead);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 10, _hysteresis);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 11, _ratio);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 12, _sidechainAudition ? 1.0 : 0.0);
  }

  @override
  void storeStateA() { _snapshotA = _snap(); super.storeStateA(); }
  @override
  void storeStateB() { _snapshotB = _snap(); super.storeStateB(); }
  @override
  void restoreStateA() { if (_snapshotA != null) _restore(_snapshotA!); }
  @override
  void restoreStateB() { if (_snapshotB != null) _restore(_snapshotB!); }
  @override
  void copyAToB() { _snapshotB = _snapshotA?.copy(); super.copyAToB(); }
  @override
  void copyBToA() { _snapshotA = _snapshotB?.copy(); super.copyBToA(); }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _updateMeters() {
    if (!mounted) return;
    setState(() {
      if (_initialized && _slotIndex >= 0) {
        _currentInputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
        _currentOutputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);
        final gateGain = _ffi.insertGetMeter(widget.trackId, _slotIndex, 2);

        final targetOpen = gateGain.clamp(0.0, 1.0);
        _gateOpen += (targetOpen - _gateOpen) * 0.3;

        if (_gateOpen > 0.95) {
          _currentState = GateState.open;
        } else if (_gateOpen < 0.05) {
          _currentState = GateState.closed;
        } else if (targetOpen > _gateOpen) {
          _currentState = GateState.opening;
        } else {
          _currentState = GateState.closing;
        }
      } else {
        final isAboveThreshold = _currentInputLevel > _threshold;
        final isAboveHysteresis = _currentInputLevel > (_threshold - _hysteresis);

        if (_currentState == GateState.closed && isAboveThreshold) {
          _currentState = GateState.opening;
        } else if (_currentState == GateState.opening) {
          _gateOpen = (_gateOpen + 0.1).clamp(0.0, 1.0);
          if (_gateOpen >= 1.0) _currentState = GateState.open;
        } else if (_currentState == GateState.open && !isAboveHysteresis) {
          _currentState = GateState.closing;
        } else if (_currentState == GateState.closing) {
          _gateOpen = (_gateOpen - 0.05).clamp(0.0, 1.0);
          if (_gateOpen <= 0.0) _currentState = GateState.closed;
        }
        final attenuation = _range * (1 - _gateOpen);
        _currentOutputLevel = _currentInputLevel + attenuation;
      }

      _levelHistory.add(GateLevelSample(
        input: _currentInputLevel,
        output: _currentOutputLevel,
        gateGain: _gateOpen,
        state: _currentState,
      ));
      while (_levelHistory.length > _maxHistorySamples) {
        _levelHistory.removeAt(0);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('Gate', DspNodeType.gate, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildCompactHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                children: [
                  // TOP: Scrolling display + transfer curve
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        // Scrolling level display with envelope overlay
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: FabFilterDecorations.display(),
                            clipBehavior: Clip.hardEdge,
                            child: CustomPaint(
                              painter: _GateDisplayPainter(
                                history: _levelHistory,
                                threshold: _threshold,
                                hysteresis: _hysteresis,
                                range: _range,
                                attack: _attack,
                                hold: _hold,
                                release: _release,
                                gateOpen: _gateOpen,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Transfer curve + state indicator + meters
                        SizedBox(
                          width: 110,
                          child: Column(
                            children: [
                              // Transfer curve (glass style)
                              Expanded(
                                flex: 3,
                                child: Container(
                                  decoration: FabFilterDecorations.display(),
                                  clipBehavior: Clip.hardEdge,
                                  child: CustomPaint(
                                    painter: _TransferCurvePainter(
                                      threshold: _threshold,
                                      range: _range,
                                      ratio: _ratio,
                                      hysteresis: _hysteresis,
                                      mode: _mode,
                                      inputLevel: _currentInputLevel,
                                      gateOpen: _gateOpen,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Gate state badge with pulse
                              _buildGateStateBadge(),
                              const SizedBox(height: 4),
                              // Mini I/O meters
                              SizedBox(
                                height: 22,
                                child: Row(
                                  children: [
                                    Expanded(child: _buildMiniMeter('IN', _currentInputLevel, FabFilterColors.textMuted)),
                                    const SizedBox(width: 3),
                                    Expanded(child: _buildMiniMeter('OUT', _currentOutputLevel, FabFilterColors.green)),
                                    const SizedBox(width: 3),
                                    Expanded(child: _buildMiniMeter('GR', -(_range * (1 - _gateOpen)).abs(), FabFilterColors.orange)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // BOTTOM: Knobs + options
                  Expanded(
                    flex: 2,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _buildCompactControls()),
                        const SizedBox(width: 8),
                        _buildCompactOptions(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildCompactHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FabFilterColors.borderSubtle))),
      child: Row(
        children: [
          Icon(widget.icon, color: widget.accentColor, size: 14),
          const SizedBox(width: 6),
          Text(widget.title, style: FabFilterText.title.copyWith(fontSize: 11)),
          const SizedBox(width: 12),
          // Mode selector with animated chips
          ...GateMode.values.map((m) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildModeChip(m),
          )),
          const Spacer(),
          // Gate open % indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${(_gateOpen * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: _gateOpen > 0.5 ? FabFilterColors.green : FabFilterColors.red,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildCompactAB(),
          const SizedBox(width: 8),
          _buildCompactBypass(),
        ],
      ),
    );
  }

  Widget _buildModeChip(GateMode mode) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = mode);
        if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 5, mode.index.toDouble());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? widget.accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? widget.accentColor : FabFilterColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: widget.accentColor.withValues(alpha: 0.2), blurRadius: 4),
          ] : null,
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            color: isSelected ? widget.accentColor : FabFilterColors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactAB() => FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: widget.accentColor);
  Widget _buildCompactBypass() => FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass);

  // ─── Gate State Badge ───────────────────────────────────────────────────

  Widget _buildGateStateBadge() {
    final stateColor = switch (_currentState) {
      GateState.open => FabFilterColors.green,
      GateState.opening => FabFilterColors.yellow,
      GateState.closing => FabFilterColors.orange,
      GateState.closed => FabFilterColors.red,
    };
    final stateLabel = switch (_currentState) {
      GateState.open => 'OPEN',
      GateState.opening => 'OPENING',
      GateState.closing => 'CLOSING',
      GateState.closed => 'CLOSED',
    };

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        final glowIntensity = (_currentState == GateState.opening || _currentState == GateState.closing)
            ? _pulseAnim.value * 0.5
            : 0.0;
        return Container(
          height: 24,
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.15 + glowIntensity * 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: stateColor.withValues(alpha: 0.6 + glowIntensity * 0.4)),
            boxShadow: [
              BoxShadow(
                color: stateColor.withValues(alpha: 0.2 + glowIntensity * 0.3),
                blurRadius: 6 + glowIntensity * 4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stateColor,
                  boxShadow: [BoxShadow(color: stateColor.withValues(alpha: 0.6), blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 4),
              Text(stateLabel, style: TextStyle(color: stateColor, fontSize: 8, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  // ─── Mini Meter ─────────────────────────────────────────────────────────

  Widget _buildMiniMeter(String label, double levelDb, Color color) {
    final norm = ((levelDb + 60) / 60).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: FabFilterColors.bgVoid,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: norm,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.6), color],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Controls ───────────────────────────────────────────────────────────

  Widget _buildCompactControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSmallKnob(
          value: (_threshold + 80) / 80,
          label: 'THRESH',
          display: '${_threshold.toStringAsFixed(0)}dB',
          color: FabFilterColors.green,
          onChanged: (v) {
            setState(() => _threshold = v * 80 - 80);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);
          },
        ),
        _buildSmallKnob(
          value: (_range + 80) / 80,
          label: 'RANGE',
          display: _range <= -79 ? '-∞dB' : '${_range.toStringAsFixed(0)}dB',
          color: FabFilterColors.orange,
          onChanged: (v) {
            setState(() => _range = v * 80 - 80);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _range);
          },
        ),
        _buildSmallKnob(
          value: math.log(_attack / 0.01) / math.log(100 / 0.01),
          label: 'ATT',
          display: _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)}µs' : '${_attack.toStringAsFixed(1)}ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _attack = 0.01 * math.pow(100 / 0.01, v).toDouble());
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _attack);
          },
        ),
        _buildSmallKnob(
          value: _hold / 500,
          label: 'HOLD',
          display: '${_hold.toStringAsFixed(0)}ms',
          color: FabFilterColors.blue,
          onChanged: (v) {
            setState(() => _hold = v * 500);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _hold);
          },
        ),
        _buildSmallKnob(
          value: math.log(_release / 1) / math.log(1000 / 1),
          label: 'REL',
          display: _release >= 100 ? '${(_release / 1000).toStringAsFixed(1)}s' : '${_release.toStringAsFixed(0)}ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _release = 1 * math.pow(1000 / 1, v).toDouble());
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);
          },
        ),
        if (showExpertMode)
          _buildSmallKnob(
            value: _hysteresis / 12,
            label: 'HYST',
            display: '${_hysteresis.toStringAsFixed(0)}dB',
            color: FabFilterColors.purple,
            onChanged: (v) {
              setState(() => _hysteresis = v * 12);
              if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 10, _hysteresis);
            },
          ),
      ],
    );
  }

  Widget _buildSmallKnob({
    required double value,
    required String label,
    required String display,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return FabFilterKnob(value: value.clamp(0.0, 1.0), label: label, display: display, color: color, size: 48, onChanged: onChanged);
  }

  // ─── Options Panel ──────────────────────────────────────────────────────

  Widget _buildCompactOptions() {
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FabSectionLabel('SIDECHAIN'),
          const SizedBox(height: 4),
          _buildOptionRow('SC', _sidechainEnabled, (v) {
            setState(() => _sidechainEnabled = v);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 6, v ? 1.0 : 0.0);
          }),
          if (_sidechainEnabled) ...[
            const SizedBox(height: 4),
            // SC filter mini-response curve
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.hardEdge,
              child: CustomPaint(
                painter: _SidechainFilterPainter(
                  hpf: _sidechainHpf,
                  lpf: _sidechainLpf,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            _buildMiniSlider('HP', math.log(_sidechainHpf / 20) / math.log(500 / 20), '${_sidechainHpf.toStringAsFixed(0)}', (v) {
              setState(() => _sidechainHpf = 20 * math.pow(500 / 20, v).toDouble());
              if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 7, _sidechainHpf);
            }),
            const SizedBox(height: 2),
            _buildMiniSlider('LP', math.log(_sidechainLpf / 1000) / math.log(20000 / 1000), '${(_sidechainLpf / 1000).toStringAsFixed(0)}k', (v) {
              setState(() => _sidechainLpf = 1000 * math.pow(20000 / 1000, v).toDouble());
              if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 8, _sidechainLpf);
            }),
            const SizedBox(height: 4),
            _buildOptionRow('AUD', _sidechainAudition, (v) {
              setState(() => _sidechainAudition = v);
              if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 12, v ? 1.0 : 0.0);
            }),
          ],
          const Flexible(child: SizedBox(height: 8)),
          if (showExpertMode) ...[
            FabSectionLabel('EXPERT'),
            const SizedBox(height: 4),
            _buildMiniSlider('LA', _lookahead / 10, '${_lookahead.toStringAsFixed(0)}ms', (v) {
              setState(() => _lookahead = v * 10);
              if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 9, _lookahead);
            }),
            if (_mode == GateMode.expand) ...[
              const SizedBox(height: 2),
              _buildMiniSlider('RAT', (_ratio - 1) / 99, '${_ratio.toStringAsFixed(0)}%', (v) {
                setState(() => _ratio = 1 + v * 99);
                if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 11, _ratio);
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOptionRow(String label, bool value, ValueChanged<bool> onChanged) =>
    FabOptionRow(label: label, value: value, onChanged: onChanged, accentColor: widget.accentColor);

  Widget _buildMiniSlider(String label, double value, String display, ValueChanged<double> onChanged) =>
    FabMiniSlider(label: label, value: value, display: display, onChanged: onChanged);
}

// ═══════════════════════════════════════════════════════════════════════════
// GATE DISPLAY PAINTER — Premium Pro-G scrolling visualization
// ═══════════════════════════════════════════════════════════════════════════

class _GateDisplayPainter extends CustomPainter {
  final List<GateLevelSample> history;
  final double threshold;
  final double hysteresis;
  final double range;
  final double attack;
  final double hold;
  final double release;
  final double gateOpen;

  _GateDisplayPainter({
    required this.history,
    required this.threshold,
    required this.hysteresis,
    required this.range,
    required this.attack,
    required this.hold,
    required this.release,
    required this.gateOpen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ─── Background gradient ─────────────────────────────────────────
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, h),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      ));

    // ─── Range zone (attenuation area — bottom fill) ─────────────────
    final rangeNorm = (range.abs() / 80).clamp(0.0, 1.0);
    if (rangeNorm > 0.01) {
      final rangeTop = h * (1 - rangeNorm * 0.95);
      canvas.drawRect(
        Rect.fromLTRB(0, rangeTop, w, h),
        Paint()..color = FabFilterColors.red.withValues(alpha: 0.05),
      );
    }

    // ─── dB Grid ─────────────────────────────────────────────────────
    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;
    final labelStyle = TextStyle(
      color: FabFilterColors.textMuted.withValues(alpha: 0.5),
      fontSize: 8,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    for (var db = -60; db <= 0; db += 12) {
      final y = h * (1 - (db + 60) / 60);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      // dB axis label
      final tp = TextPainter(
        text: TextSpan(text: '${db}dB', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height - 1));
    }

    // ─── Threshold zone with gradient ────────────────────────────────
    final thresholdY = h * (1 - (threshold + 60) / 60);
    final hysteresisY = h * (1 - (threshold - hysteresis + 60) / 60);

    // Hysteresis zone gradient fill
    canvas.drawRect(
      Rect.fromLTRB(0, thresholdY, w, hysteresisY),
      Paint()..shader = ui.Gradient.linear(
        Offset(0, thresholdY), Offset(0, hysteresisY),
        [
          FabFilterColors.green.withValues(alpha: 0.12),
          FabFilterColors.green.withValues(alpha: 0.03),
        ],
      ),
    );

    // Threshold line with glow
    final threshGlow = Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.3)
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(Offset(0, thresholdY), Offset(w, thresholdY), threshGlow);

    final threshLine = Paint()
      ..color = FabFilterColors.green
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, thresholdY), Offset(w, thresholdY), threshLine);

    // Hysteresis line (dashed)
    final hystPaint = Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var x = 0.0; x < w; x += 8) {
      canvas.drawLine(Offset(x, hysteresisY), Offset(x + 4, hysteresisY), hystPaint);
    }

    if (history.isEmpty) return;
    final sampleWidth = w / history.length;

    // ─── Input level fill (dim) ──────────────────────────────────────
    final inputPath = Path();
    inputPath.moveTo(0, h);
    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final level = history[i].input;
      final normalizedLevel = ((level + 60) / 60).clamp(0.0, 1.0);
      inputPath.lineTo(x, h * (1 - normalizedLevel));
    }
    inputPath.lineTo(w, h);
    inputPath.close();

    canvas.drawPath(inputPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, h),
        [FabFilterColors.textMuted.withValues(alpha: 0.15), FabFilterColors.textMuted.withValues(alpha: 0.03)],
      ));

    // ─── Output level with state-colored gradient fills ──────────────
    // Build separate paths per state for gradient coloring
    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final sample = history[i];
      final normalizedLevel = ((sample.output + 60) / 60).clamp(0.0, 1.0);
      final barHeight = h * normalizedLevel;

      final color = switch (sample.state) {
        GateState.open => FabFilterColors.green,
        GateState.opening => FabFilterColors.yellow,
        GateState.closing => FabFilterColors.orange,
        GateState.closed => FabFilterColors.red.withValues(alpha: 0.4),
      };

      // Gradient fill bar
      final barRect = Rect.fromLTWH(x, h - barHeight, sampleWidth + 1, barHeight);
      canvas.drawRect(barRect, Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, h - barHeight), Offset(x, h),
          [color.withValues(alpha: 0.8), color.withValues(alpha: 0.2)],
        ));
    }

    // ─── Output level outline ────────────────────────────────────────
    final outlinePath = Path();
    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final level = history[i].output;
      final normalizedLevel = ((level + 60) / 60).clamp(0.0, 1.0);
      final y = h * (1 - normalizedLevel);
      if (i == 0) {
        outlinePath.moveTo(x, y);
      } else {
        outlinePath.lineTo(x, y);
      }
    }
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // ─── Envelope shape overlay (ATT-HOLD-REL) ──────────────────────
    _drawEnvelopeOverlay(canvas, size);

    // ─── Threshold label ─────────────────────────────────────────────
    _drawLabel(canvas, 'Threshold: ${threshold.toStringAsFixed(0)} dB',
        Offset(w - 120, thresholdY - 12), FabFilterColors.green);

    // ─── Range label ─────────────────────────────────────────────────
    if (range > -79) {
      _drawLabel(canvas, 'Range: ${range.toStringAsFixed(0)} dB',
          Offset(w - 120, h - 14), FabFilterColors.orange);
    }
  }

  void _drawEnvelopeOverlay(Canvas canvas, Size size) {
    // Draw gate envelope shape in bottom-right corner
    final envW = 60.0;
    final envH = 24.0;
    final envX = size.width - envW - 4;
    final envY = 4.0;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(envX, envY, envW, envH), const Radius.circular(3)),
      Paint()..color = FabFilterColors.bgVoid.withValues(alpha: 0.8),
    );

    // Normalize timings
    final totalMs = attack + hold + release;
    if (totalMs <= 0) return;
    final attFrac = attack / totalMs;
    final holdFrac = hold / totalMs;

    final envPath = Path();
    final startX = envX + 2;
    final endX = envX + envW - 2;
    final topY = envY + 3;
    final botY = envY + envH - 3;
    final envWidth = endX - startX;

    // Attack ramp up
    envPath.moveTo(startX, botY);
    envPath.lineTo(startX + envWidth * attFrac, topY);
    // Hold plateau
    envPath.lineTo(startX + envWidth * (attFrac + holdFrac), topY);
    // Release ramp down
    envPath.lineTo(endX, botY);

    // Fill
    final fillPath = Path.from(envPath);
    fillPath.lineTo(startX, botY);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.15));

    // Stroke
    canvas.drawPath(envPath, Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round);

    // Phase dots
    final phases = [
      (startX + envWidth * attFrac * 0.5, (topY + botY) / 2, 'A', FabFilterColors.cyan),
      (startX + envWidth * (attFrac + holdFrac * 0.5), topY + 2, 'H', FabFilterColors.blue),
      (startX + envWidth * (attFrac + holdFrac + (1 - attFrac - holdFrac) * 0.5), (topY + botY) / 2, 'R', FabFilterColors.cyan),
    ];
    for (final (px, py, label, color) in phases) {
      canvas.drawCircle(Offset(px, py), 2, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: color, fontSize: 6, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(px - tp.width / 2, py + 3));
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 9, fontFeatures: const [FontFeature.tabularFigures()])),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GateDisplayPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSFER CURVE PAINTER — Glass-style input vs output characteristic
// ═══════════════════════════════════════════════════════════════════════════

class _TransferCurvePainter extends CustomPainter {
  final double threshold;
  final double range;
  final double ratio;
  final double hysteresis;
  final GateMode mode;
  final double inputLevel;
  final double gateOpen;

  _TransferCurvePainter({
    required this.threshold,
    required this.range,
    required this.ratio,
    required this.hysteresis,
    required this.mode,
    required this.inputLevel,
    required this.gateOpen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(w, h),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      ));

    // Grid
    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final v = i / 4;
      canvas.drawLine(Offset(v * w, 0), Offset(v * w, h), gridPaint);
      canvas.drawLine(Offset(0, v * h), Offset(w, v * h), gridPaint);
    }

    // Unity line (diagonal)
    canvas.drawLine(Offset(0, h), Offset(w, 0), Paint()
      ..color = FabFilterColors.textMuted.withValues(alpha: 0.2)
      ..strokeWidth = 1);

    // Transfer curve
    const dbMin = -80.0;
    const dbMax = 0.0;
    const dbRange = dbMax - dbMin;

    // Fill area between curve and unity (shows attenuation)
    final fillPath = Path();
    final curvePath = Path();

    for (var i = 0; i <= w.toInt(); i++) {
      final inputDb = dbMin + (i / w) * dbRange;
      double outputDb;

      if (inputDb >= threshold) {
        outputDb = inputDb;
      } else {
        final belowDb = threshold - inputDb;
        final attenuation = (range / 80.0) * belowDb * (ratio / 100.0);
        outputDb = inputDb + attenuation;
      }

      final x = i.toDouble();
      final y = h - ((outputDb - dbMin) / dbRange) * h;
      final unityY = h - ((inputDb - dbMin) / dbRange) * h;

      if (i == 0) {
        curvePath.moveTo(x, y.clamp(0.0, h));
        fillPath.moveTo(x, unityY.clamp(0.0, h));
      } else {
        curvePath.lineTo(x, y.clamp(0.0, h));
      }
      fillPath.lineTo(x, y.clamp(0.0, h));
    }

    // Close fill path back along unity line
    for (var i = w.toInt(); i >= 0; i--) {
      final inputDb = dbMin + (i / w) * dbRange;
      final unityY = h - ((inputDb - dbMin) / dbRange) * h;
      fillPath.lineTo(i.toDouble(), unityY.clamp(0.0, h));
    }
    fillPath.close();

    // Attenuation zone fill
    canvas.drawPath(fillPath, Paint()
      ..color = FabFilterColors.red.withValues(alpha: 0.08));

    // Curve line with glow
    canvas.drawPath(curvePath, Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));

    canvas.drawPath(curvePath, Paint()
      ..color = FabFilterColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round);

    // Threshold marker
    final threshX = ((threshold - dbMin) / dbRange) * w;
    canvas.drawLine(
      Offset(threshX, 0), Offset(threshX, h),
      Paint()
        ..color = FabFilterColors.green.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );

    // ─── Glass input dot with crosshair ──────────────────────────────
    final inputNorm = ((inputLevel - dbMin) / dbRange).clamp(0.0, 1.0);
    double outDb;
    if (inputLevel >= threshold) {
      outDb = inputLevel;
    } else {
      final belowDb = threshold - inputLevel;
      outDb = inputLevel + (range / 80.0) * belowDb * (ratio / 100.0);
    }
    final outNorm = ((outDb - dbMin) / dbRange).clamp(0.0, 1.0);

    final dotX = inputNorm * w;
    final dotY = h - outNorm * h;

    // Crosshair lines
    canvas.drawLine(
      Offset(dotX, 0), Offset(dotX, h),
      Paint()..color = FabFilterColors.green.withValues(alpha: 0.15)..strokeWidth = 0.5);
    canvas.drawLine(
      Offset(0, dotY), Offset(w, dotY),
      Paint()..color = FabFilterColors.green.withValues(alpha: 0.15)..strokeWidth = 0.5);

    // Outer glow
    canvas.drawCircle(Offset(dotX, dotY), 8, Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // Glass effect (radial gradient)
    canvas.drawCircle(Offset(dotX, dotY), 5, Paint()
      ..shader = ui.Gradient.radial(
        Offset(dotX - 1, dotY - 1), 5,
        [
          Colors.white.withValues(alpha: 0.4),
          FabFilterColors.green.withValues(alpha: 0.8),
          FabFilterColors.green.withValues(alpha: 0.3),
        ],
        [0.0, 0.5, 1.0],
      ));

    // Core dot
    canvas.drawCircle(Offset(dotX, dotY), 3, Paint()..color = FabFilterColors.green);
  }

  @override
  bool shouldRepaint(covariant _TransferCurvePainter old) {
    return threshold != old.threshold || range != old.range ||
        ratio != old.ratio || inputLevel != old.inputLevel ||
        mode != old.mode || gateOpen != old.gateOpen;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIDECHAIN FILTER RESPONSE PAINTER — Mini frequency curve
// ═══════════════════════════════════════════════════════════════════════════

class _SidechainFilterPainter extends CustomPainter {
  final double hpf;
  final double lpf;

  _SidechainFilterPainter({required this.hpf, required this.lpf});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Grid
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), Paint()..color = FabFilterColors.grid..strokeWidth = 0.5);

    // Calculate filter response
    final path = Path();
    for (var i = 0; i <= w.toInt(); i++) {
      final freq = 20.0 * math.pow(20000 / 20, i / w);
      double gain = 1.0;

      // HPF (12dB/oct approximation)
      if (freq < hpf) {
        final ratio = freq / hpf;
        gain *= ratio * ratio;
      }
      // LPF (12dB/oct approximation)
      if (freq > lpf) {
        final ratio = lpf / freq;
        gain *= ratio * ratio;
      }

      final y = h * (1 - gain.clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    // Fill
    final fillPath = Path.from(path);
    fillPath.lineTo(w, h);
    fillPath.lineTo(0, h);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.1));

    // Stroke
    canvas.drawPath(path, Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _SidechainFilterPainter old) =>
      old.hpf != hpf || old.lpf != lpf;
}
