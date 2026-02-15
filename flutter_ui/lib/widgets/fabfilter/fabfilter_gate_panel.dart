/// FF-G Gate Panel
///
/// Professional gate interface:
/// - Real-time gate state visualization
/// - Sidechain filtering
/// - Expert timing controls
/// - Multiple gate modes (gate, duck, expand)
/// - Lookahead and hysteresis

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
  final GateState state;
  final DateTime timestamp;

  GateLevelSample({
    required this.input,
    required this.output,
    required this.state,
    required this.timestamp,
  });
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
  bool _compactView = false;
  final List<GateLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 200;

  // Real-time state
  double _currentInputLevel = -60.0;
  double _currentOutputLevel = -60.0;
  GateState _currentState = GateState.closed;
  double _gateOpen = 0.0; // 0-1 (closed to open)

  // Animation
  late AnimationController _meterController;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  // DspChainProvider integration
  String? _nodeId;
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();

    // Initialize FFI gate
    _initializeProcessor();
    initBypassFromProvider();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);

    _meterController.repeat();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);

    // Auto-add gate to chain if not present
    if (!chain.nodes.any((n) => n.type == DspNodeType.gate)) {
      dsp.addNode(widget.trackId, DspNodeType.gate);
      chain = dsp.getChain(widget.trackId);
    }

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

  /// Read current parameter values from engine (preserves live state on tab switch)
  void _readParamsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    setState(() {
      _threshold = _ffi.insertGetParam(widget.trackId, _slotIndex, 0);
      _range = _ffi.insertGetParam(widget.trackId, _slotIndex, 1);
      _attack = _ffi.insertGetParam(widget.trackId, _slotIndex, 2);
      _hold = _ffi.insertGetParam(widget.trackId, _slotIndex, 3);
      _release = _ffi.insertGetParam(widget.trackId, _slotIndex, 4);
      // Extended params (5-9)
      final modeVal = _ffi.insertGetParam(widget.trackId, _slotIndex, 5).round();
      _mode = modeVal == 1 ? GateMode.duck : (modeVal == 2 ? GateMode.expand : GateMode.gate);
      _sidechainEnabled = _ffi.insertGetParam(widget.trackId, _slotIndex, 6) > 0.5;
      _sidechainHpf = _ffi.insertGetParam(widget.trackId, _slotIndex, 7);
      _sidechainLpf = _ffi.insertGetParam(widget.trackId, _slotIndex, 8);
      _lookahead = _ffi.insertGetParam(widget.trackId, _slotIndex, 9);
      // Clamp restored values to valid ranges
      if (_sidechainHpf < 20) _sidechainHpf = 80.0;
      if (_sidechainLpf < 1000) _sidechainLpf = 12000.0;
    });
  }

  void _applyAllParameters() {
    if (!_initialized || _slotIndex < 0) return;
    // GateWrapper param indices: 0-4=Core, 5-9=Extended
    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);      // Threshold (dB)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _range);          // Range (dB)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _attack);         // Attack (ms)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _hold);           // Hold (ms)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);        // Release (ms)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 5, _mode.index.toDouble());  // Mode
    _ffi.insertSetParam(widget.trackId, _slotIndex, 6, _sidechainEnabled ? 1.0 : 0.0);  // SC Enable
    _ffi.insertSetParam(widget.trackId, _slotIndex, 7, _sidechainHpf);   // SC HP Freq
    _ffi.insertSetParam(widget.trackId, _slotIndex, 8, _sidechainLpf);   // SC LP Freq
    _ffi.insertSetParam(widget.trackId, _slotIndex, 9, _lookahead);      // Lookahead
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    // Don't remove from insert chain - node persists
    // Ghost gateRemove() was here, now removed
    super.dispose();
  }

  void _updateMeters() {
    if (!mounted) return;
    setState(() {
      // Read real meters from FFI insert chain
      if (_initialized && _slotIndex >= 0) {
        // insertGetMeter returns: 0=inputLevel, 1=outputLevel, 2=gateGain (0-1)
        _currentInputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
        _currentOutputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);
        final gateGain = _ffi.insertGetMeter(widget.trackId, _slotIndex, 2);

        // Derive gate open from gain (0=closed, 1=open)
        final targetOpen = gateGain.clamp(0.0, 1.0);
        // Smooth transition for visual
        _gateOpen += (targetOpen - _gateOpen) * 0.3;

        // Derive state from gate open
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
        // Fallback: simple state machine when FFI not available
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

      // Add to history
      _levelHistory.add(GateLevelSample(
        input: _currentInputLevel,
        output: _currentOutputLevel,
        state: _currentState,
        timestamp: DateTime.now(),
      ));
      while (_levelHistory.length > _maxHistorySamples) {
        _levelHistory.removeAt(0);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD — Compact horizontal layout, NO scrolling
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          // Compact header
          _buildCompactHeader(),
          // Main content — three zones
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                children: [
                  // TOP: Display area (scrolling waveform + transfer curve)
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        // Scrolling level display
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
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Transfer curve + gate state
                        SizedBox(
                          width: 90,
                          child: Column(
                            children: [
                              // Transfer curve
                              Expanded(
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
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Compact gate state badge
                              _buildGateStateBadge(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // BOTTOM: Knobs row + sidechain options
                  Expanded(
                    flex: 2,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Main knobs
                        Expanded(flex: 3, child: _buildCompactControls()),
                        const SizedBox(width: 8),
                        // Sidechain + options
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
          // Mode selector
          ...GateMode.values.map((m) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildModeChip(m),
          )),
          const Spacer(),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? widget.accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: isSelected ? widget.accentColor : FabFilterColors.border),
        ),
        child: Text(mode.label, style: TextStyle(color: isSelected ? widget.accentColor : FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCompactAB() => FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: widget.accentColor);

  Widget _buildCompactBypass() => FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass);

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

    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: stateColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stateColor,
              boxShadow: [BoxShadow(color: stateColor.withValues(alpha: 0.5), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 4),
          Text(stateLabel, style: TextStyle(color: stateColor, fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

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
          display: '${_range.toStringAsFixed(0)}dB',
          color: FabFilterColors.orange,
          onChanged: (v) {
            setState(() => _range = v * 80 - 80);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _range);
          },
        ),
        _buildSmallKnob(
          value: math.log(_attack / 0.01) / math.log(100 / 0.01),
          label: 'ATT',
          display: _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)}µ' : '${_attack.toStringAsFixed(0)}ms',
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
            onChanged: (v) => setState(() => _hysteresis = v * 12),
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

  Widget _buildCompactOptions() {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOptionRow('SC', _sidechainEnabled, (v) {
            setState(() => _sidechainEnabled = v);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 6, v ? 1.0 : 0.0);
          }),
          const SizedBox(height: 4),
          if (_sidechainEnabled) ...[
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
            _buildOptionRow('Aud', _sidechainAudition, (v) => setState(() => _sidechainAudition = v)),
          ],
          const Flexible(child: SizedBox(height: 8)), // Flexible gap - can shrink to 0
          if (showExpertMode)
            _buildMiniSlider('Look', _lookahead / 10, '${_lookahead.toStringAsFixed(0)}ms', (v) {
              setState(() => _lookahead = v * 10);
              if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 9, _lookahead);
            }),
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
// GATE DISPLAY PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _GateDisplayPainter extends CustomPainter {
  final List<GateLevelSample> history;
  final double threshold;
  final double hysteresis;

  _GateDisplayPainter({
    required this.history,
    required this.threshold,
    required this.hysteresis,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          FabFilterColors.bgVoid,
          FabFilterColors.bgDeep,
        ],
      );
    canvas.drawRect(rect, bgPaint);

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    for (var db = -60; db <= 0; db += 12) {
      final y = size.height * (1 - (db + 60) / 60);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Threshold zone
    final thresholdY = size.height * (1 - (threshold + 60) / 60);
    final hysteresisY = size.height * (1 - (threshold - hysteresis + 60) / 60);

    // Hysteresis zone
    final zonePaint = Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.1);
    canvas.drawRect(
      Rect.fromLTRB(0, thresholdY, size.width, hysteresisY),
      zonePaint,
    );

    // Threshold line
    final thresholdPaint = Paint()
      ..color = FabFilterColors.green
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );

    // Hysteresis line (dashed)
    final hystPaint = Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (var x = 0.0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, hysteresisY),
        Offset(x + 5, hysteresisY),
        hystPaint,
      );
    }

    if (history.isEmpty) return;

    final sampleWidth = size.width / history.length;

    // Input level (gray)
    final inputPath = Path();
    inputPath.moveTo(0, size.height);

    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final level = history[i].input;
      final normalizedLevel = ((level + 60) / 60).clamp(0.0, 1.0);
      final y = size.height * (1 - normalizedLevel);

      inputPath.lineTo(x, y);
    }
    inputPath.lineTo(size.width, size.height);
    inputPath.close();

    canvas.drawPath(
      inputPath,
      Paint()..color = FabFilterColors.textMuted.withValues(alpha: 0.3),
    );

    // Output level with state coloring
    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final sample = history[i];
      final normalizedLevel = ((sample.output + 60) / 60).clamp(0.0, 1.0);
      final barHeight = size.height * normalizedLevel;

      final color = switch (sample.state) {
        GateState.open => FabFilterColors.green,
        GateState.opening => FabFilterColors.yellow,
        GateState.closing => FabFilterColors.orange,
        GateState.closed => FabFilterColors.red.withValues(alpha: 0.5),
      };

      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barHeight, sampleWidth + 1, barHeight),
        Paint()..color = color.withValues(alpha: 0.7),
      );
    }

    // Labels
    _drawLabel(canvas, 'Threshold: ${threshold.toStringAsFixed(0)} dB',
        Offset(4, thresholdY - 12), FabFilterColors.green);
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GateDisplayPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSFER CURVE PAINTER — Input vs Output characteristic
// ═══════════════════════════════════════════════════════════════════════════

class _TransferCurvePainter extends CustomPainter {
  final double threshold;
  final double range;
  final double ratio;
  final double hysteresis;
  final GateMode mode;
  final double inputLevel;

  _TransferCurvePainter({
    required this.threshold,
    required this.range,
    required this.ratio,
    required this.hysteresis,
    required this.mode,
    required this.inputLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRect(Offset.zero & size, Paint()..color = FabFilterColors.bgVoid);

    // Unity line (diagonal — input=output)
    canvas.drawLine(
      Offset(0, h),
      Offset(w, 0),
      Paint()
        ..color = FabFilterColors.grid
        ..strokeWidth = 0.5,
    );

    // Transfer curve
    final curvePath = Path();
    const dbMin = -80.0;
    const dbMax = 0.0;
    const dbRange = dbMax - dbMin;

    for (var i = 0; i <= w.toInt(); i++) {
      final inputDb = dbMin + (i / w) * dbRange;
      double outputDb;

      if (inputDb >= threshold) {
        outputDb = inputDb; // Above threshold — pass through
      } else {
        // Below threshold — apply range
        final belowDb = threshold - inputDb;
        final attenuation = (range / 80.0) * belowDb * (ratio / 100.0);
        outputDb = inputDb + attenuation;
      }

      final x = i.toDouble();
      final y = h - ((outputDb - dbMin) / dbRange) * h;

      if (i == 0) {
        curvePath.moveTo(x, y.clamp(0.0, h));
      } else {
        curvePath.lineTo(x, y.clamp(0.0, h));
      }
    }

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = FabFilterColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Threshold marker
    final threshX = ((threshold - dbMin) / dbRange) * w;
    canvas.drawLine(
      Offset(threshX, 0),
      Offset(threshX, h),
      Paint()
        ..color = FabFilterColors.green.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );

    // Input level dot on curve
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
    canvas.drawCircle(
      Offset(dotX, dotY),
      4,
      Paint()..color = FabFilterColors.green,
    );
    canvas.drawCircle(
      Offset(dotX, dotY),
      4,
      Paint()
        ..color = FabFilterColors.green.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _TransferCurvePainter old) {
    return threshold != old.threshold || range != old.range ||
        ratio != old.ratio || inputLevel != old.inputLevel ||
        mode != old.mode;
  }
}
