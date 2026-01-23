/// FabFilter Pro-G Style Gate Panel
///
/// Inspired by Pro-G's interface:
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
          title: 'Gate',
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
  void initState() {
    super.initState();

    // Initialize FFI gate
    _initializeProcessor();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);

    _meterController.repeat();
  }

  void _initializeProcessor() {
    // Use DspChainProvider instead of ghost gateCreate()
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Find existing gate node or add one
    DspNode? gateNode;
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.gate) {
        gateNode = node;
        break;
      }
    }

    if (gateNode == null) {
      // Add gate to insert chain (this calls insertLoadProcessor FFI)
      dsp.addNode(widget.trackId, DspNodeType.gate);
      final updatedChain = dsp.getChain(widget.trackId);
      if (updatedChain.nodes.isNotEmpty) {
        gateNode = updatedChain.nodes.last;
      }
    }

    if (gateNode != null) {
      _nodeId = gateNode.id;
      _slotIndex = dsp.getChain(widget.trackId).nodes.indexWhere((n) => n.id == _nodeId);
      _initialized = true;
      _applyAllParameters();
    }
  }

  void _applyAllParameters() {
    if (!_initialized || _slotIndex < 0) return;
    // GateWrapper param indices: 0=Threshold, 1=Range, 2=Attack, 3=Hold, 4=Release
    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);  // Threshold (dB)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _range);      // Range (dB)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _attack);     // Attack (ms)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _hold);       // Hold (ms)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);    // Release (ms)
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
    setState(() {
      // Simulate input level (would come from metering FFI)
      final random = math.Random();
      _currentInputLevel = -50 + random.nextDouble() * 30 + (random.nextDouble() > 0.7 ? 20 : 0);

      // Calculate gate state
      final isAboveThreshold = _currentInputLevel > _threshold;
      final isAboveHysteresis = _currentInputLevel > (_threshold - _hysteresis);

      // Simple gate state machine
      if (_currentState == GateState.closed) {
        if (isAboveThreshold) {
          _currentState = GateState.opening;
        }
      } else if (_currentState == GateState.opening) {
        _gateOpen = (_gateOpen + 0.1).clamp(0.0, 1.0);
        if (_gateOpen >= 1.0) {
          _currentState = GateState.open;
        }
      } else if (_currentState == GateState.open) {
        if (!isAboveHysteresis) {
          _currentState = GateState.closing;
        }
      } else if (_currentState == GateState.closing) {
        _gateOpen = (_gateOpen - 0.05).clamp(0.0, 1.0);
        if (_gateOpen <= 0.0) {
          _currentState = GateState.closed;
        }
      }

      // Calculate output
      final attenuation = _range * (1 - _gateOpen);
      _currentOutputLevel = _currentInputLevel + attenuation;

      // Add to history
      _levelHistory.add(GateLevelSample(
        input: _currentInputLevel,
        output: _currentOutputLevel,
        state: _currentState,
        timestamp: DateTime.now(),
      ));

      // Trim history
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
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          // Compact header
          _buildCompactHeader(),
          // Main content — horizontal layout, no scroll
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT: Gate state indicator
                  _buildCompactGateState(),
                  const SizedBox(width: 12),
                  // CENTER: Main knobs
                  Expanded(flex: 3, child: _buildCompactControls()),
                  const SizedBox(width: 12),
                  // RIGHT: Sidechain + options
                  _buildCompactOptions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
      onTap: () => setState(() => _mode = mode),
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

  Widget _buildCompactAB() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMiniButton('A', !isStateB, () { if (isStateB) toggleAB(); }),
        const SizedBox(width: 2),
        _buildMiniButton('B', isStateB, () { if (!isStateB) toggleAB(); }),
      ],
    );
  }

  Widget _buildMiniButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: active ? widget.accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? widget.accentColor : FabFilterColors.border),
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? widget.accentColor : FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _buildCompactBypass() {
    return GestureDetector(
      onTap: toggleBypass,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bypassed ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: bypassed ? FabFilterColors.orange : FabFilterColors.border),
        ),
        child: Text('BYP', style: TextStyle(color: bypassed ? FabFilterColors.orange : FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCompactGateState() {
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

    return SizedBox(
      width: 70,
      child: Container(
        decoration: FabFilterDecorations.display(),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gate indicator
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stateColor.withValues(alpha: 0.2),
                border: Border.all(color: stateColor, width: 2),
              ),
              child: Center(
                child: Container(
                  width: 24 * _gateOpen,
                  height: 24 * _gateOpen,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(stateLabel, style: TextStyle(color: stateColor, fontSize: 8, fontWeight: FontWeight.bold)),
            Text('${(_gateOpen * 100).toStringAsFixed(0)}%', style: FabFilterText.paramValue(FabFilterColors.textSecondary).copyWith(fontSize: 10)),
          ],
        ),
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
          _buildOptionRow('SC', _sidechainEnabled, (v) => setState(() => _sidechainEnabled = v)),
          const SizedBox(height: 4),
          if (_sidechainEnabled) ...[
            _buildMiniSlider('HP', math.log(_sidechainHpf / 20) / math.log(500 / 20), '${_sidechainHpf.toStringAsFixed(0)}', (v) => setState(() => _sidechainHpf = 20 * math.pow(500 / 20, v).toDouble())),
            const SizedBox(height: 2),
            _buildMiniSlider('LP', math.log(_sidechainLpf / 1000) / math.log(20000 / 1000), '${(_sidechainLpf / 1000).toStringAsFixed(0)}k', (v) => setState(() => _sidechainLpf = 1000 * math.pow(20000 / 1000, v).toDouble())),
            const SizedBox(height: 4),
            _buildOptionRow('Aud', _sidechainAudition, (v) => setState(() => _sidechainAudition = v)),
          ],
          const Flexible(child: SizedBox(height: 8)), // Flexible gap - can shrink to 0
          if (showExpertMode)
            _buildMiniSlider('Look', _lookahead / 10, '${_lookahead.toStringAsFixed(0)}ms', (v) => setState(() => _lookahead = v * 10)),
        ],
      ),
    );
  }

  Widget _buildOptionRow(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: value ? widget.accentColor.withValues(alpha: 0.15) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? widget.accentColor.withValues(alpha: 0.5) : FabFilterColors.border),
        ),
        child: Row(
          children: [
            Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 9)),
            const Spacer(),
            Icon(value ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: value ? widget.accentColor : FabFilterColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniSlider(String label, double value, String display, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: FabFilterColors.cyan,
                inactiveTrackColor: FabFilterColors.bgVoid,
                thumbColor: FabFilterColors.cyan,
              ),
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
          ),
          SizedBox(width: 24, child: Text(display, style: FabFilterText.paramLabel.copyWith(fontSize: 8), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

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
