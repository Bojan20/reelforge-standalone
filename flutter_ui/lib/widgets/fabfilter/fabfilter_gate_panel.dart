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
    final success = _ffi.gateCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      _initialized = true;
      _applyAllParameters();
    }
  }

  void _applyAllParameters() {
    if (!_initialized) return;
    _ffi.gateSetThreshold(widget.trackId, _threshold);
    _ffi.gateSetRange(widget.trackId, _range);
    _ffi.gateSetAttack(widget.trackId, _attack);
    _ffi.gateSetHold(widget.trackId, _hold);
    _ffi.gateSetRelease(widget.trackId, _release);
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    if (_initialized) {
      _ffi.gateRemove(widget.trackId);
    }
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
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Display section
                  if (!_compactView) ...[
                    _buildDisplaySection(),
                    const SizedBox(height: 16),
                  ],

                  // Main controls
                  _buildMainControls(),
                  const SizedBox(height: 16),

                  // Mode selection
                  _buildModeSection(),
                  const SizedBox(height: 16),

                  // Sidechain
                  _buildSidechainSection(),

                  // Expert controls
                  if (showExpertMode) ...[
                    const SizedBox(height: 16),
                    _buildExpertSection(),
                  ],
                ],
              ),
            ),
          ),
          buildBottomBar(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPLAY SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDisplaySection() {
    return Row(
      children: [
        // Level display
        Expanded(
          flex: 3,
          child: Container(
            height: 140,
            decoration: FabFilterDecorations.display(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CustomPaint(
                painter: _GateDisplayPainter(
                  history: _levelHistory,
                  threshold: _threshold,
                  hysteresis: _hysteresis,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Gate state indicator
        SizedBox(
          width: 80,
          height: 140,
          child: _buildGateStateIndicator(),
        ),

        const SizedBox(width: 12),

        // Level meters
        SizedBox(
          width: 60,
          height: 140,
          child: _buildLevelMeters(),
        ),
      ],
    );
  }

  Widget _buildGateStateIndicator() {
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
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large gate indicator
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stateColor.withValues(alpha: 0.2),
              border: Border.all(color: stateColor, width: 3),
              boxShadow: [
                BoxShadow(
                  color: stateColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 30 * _gateOpen,
                height: 30 * _gateOpen,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stateColor,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            stateLabel,
            style: TextStyle(
              color: stateColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          // Gate open percentage
          Text(
            '${(_gateOpen * 100).toStringAsFixed(0)}%',
            style: FabFilterTextStyles.value.copyWith(
              color: FabFilterColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelMeters() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('IN', style: FabFilterTextStyles.label),
              Text('OUT', style: FabFilterTextStyles.label),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildVerticalMeter(_currentInputLevel, FabFilterColors.textMuted)),
                const SizedBox(width: 2),
                Expanded(child: _buildVerticalMeter(_currentOutputLevel, FabFilterColors.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(double levelDb, Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final normalized = ((levelDb + 60) / 60).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: double.infinity,
              height: constraints.maxHeight * normalized,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN CONTROLS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMainControls() {
    return buildSection(
      'GATE',
      Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          // Threshold
          FabFilterKnob(
            value: (_threshold + 80) / 80,
            label: 'THRESHOLD',
            display: '${_threshold.toStringAsFixed(1)} dB',
            color: FabFilterColors.green,
            onChanged: (v) {
              setState(() => _threshold = v * 80 - 80);
              _ffi.gateSetThreshold(widget.trackId, _threshold);
            },
          ),

          // Range
          FabFilterKnob(
            value: (_range + 80) / 80,
            label: 'RANGE',
            display: '${_range.toStringAsFixed(0)} dB',
            color: FabFilterColors.orange,
            onChanged: (v) {
              setState(() => _range = v * 80 - 80);
              _ffi.gateSetRange(widget.trackId, _range);
            },
          ),

          // Attack
          FabFilterKnob(
            value: math.log(_attack / 0.01) / math.log(100 / 0.01),
            label: 'ATTACK',
            display: _attack < 1
                ? '${(_attack * 1000).toStringAsFixed(0)} µs'
                : '${_attack.toStringAsFixed(1)} ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _attack = 0.01 * math.pow(100 / 0.01, v).toDouble());
              _ffi.gateSetAttack(widget.trackId, _attack);
            },
          ),

          // Hold
          FabFilterKnob(
            value: _hold / 500,
            label: 'HOLD',
            display: '${_hold.toStringAsFixed(0)} ms',
            color: FabFilterColors.blue,
            onChanged: (v) {
              setState(() => _hold = v * 500);
              _ffi.gateSetHold(widget.trackId, _hold);
            },
          ),

          // Release
          FabFilterKnob(
            value: math.log(_release / 1) / math.log(1000 / 1),
            label: 'RELEASE',
            display: _release >= 100
                ? '${(_release / 1000).toStringAsFixed(2)} s'
                : '${_release.toStringAsFixed(0)} ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _release = 1 * math.pow(1000 / 1, v).toDouble());
              _ffi.gateSetRelease(widget.trackId, _release);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MODE SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildModeSection() {
    return buildSection(
      'MODE',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode buttons
          Row(
            children: GateMode.values.map((mode) {
              final isSelected = _mode == mode;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _mode = mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: isSelected
                        ? FabFilterDecorations.toggleActive(FabFilterColors.green)
                        : FabFilterDecorations.toggleInactive(),
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        color: isSelected
                            ? FabFilterColors.green
                            : FabFilterColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          Text(
            _mode.description,
            style: FabFilterTextStyles.label.copyWith(
              color: FabFilterColors.textMuted,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              buildToggle(
                'Compact',
                _compactView,
                (v) => setState(() => _compactView = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SIDECHAIN SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSidechainSection() {
    return buildSection(
      'SIDECHAIN',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildToggle(
                'Enable',
                _sidechainEnabled,
                (v) => setState(() => _sidechainEnabled = v),
              ),
              const SizedBox(width: 24),

              // HPF
              Expanded(
                child: _buildSimpleSlider(
                  'HP',
                  math.log(_sidechainHpf / 20) / math.log(500 / 20),
                  '${_sidechainHpf.toStringAsFixed(0)} Hz',
                  FabFilterColors.cyan,
                  _sidechainEnabled
                      ? (v) => setState(
                          () => _sidechainHpf = 20 * math.pow(500 / 20, v).toDouble())
                      : null,
                ),
              ),
              const SizedBox(width: 16),

              // LPF
              Expanded(
                child: _buildSimpleSlider(
                  'LP',
                  math.log(_sidechainLpf / 1000) / math.log(20000 / 1000),
                  _sidechainLpf >= 1000
                      ? '${(_sidechainLpf / 1000).toStringAsFixed(1)}k'
                      : '${_sidechainLpf.toStringAsFixed(0)} Hz',
                  FabFilterColors.cyan,
                  _sidechainEnabled
                      ? (v) => setState(() =>
                          _sidechainLpf = 1000 * math.pow(20000 / 1000, v).toDouble())
                      : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_sidechainEnabled)
            buildToggle(
              'Audition Sidechain',
              _sidechainAudition,
              (v) => setState(() => _sidechainAudition = v),
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleSlider(
    String label,
    double value,
    String display,
    Color color,
    ValueChanged<double>? onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 25,
          child: Text(label, style: FabFilterTextStyles.label),
        ),
        Expanded(
          child: SliderTheme(
            data: fabFilterSliderTheme(color),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            display,
            style: FabFilterTextStyles.value.copyWith(color: color),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPERT SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildExpertSection() {
    return buildSection(
      'ADVANCED',
      Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          // Hysteresis
          FabFilterKnob(
            value: _hysteresis / 12,
            label: 'HYSTERESIS',
            display: '${_hysteresis.toStringAsFixed(1)} dB',
            color: FabFilterColors.purple,
            onChanged: (v) => setState(() => _hysteresis = v * 12),
          ),

          // Lookahead
          FabFilterKnob(
            value: _lookahead / 10,
            label: 'LOOKAHEAD',
            display: '${_lookahead.toStringAsFixed(1)} ms',
            color: FabFilterColors.blue,
            onChanged: (v) => setState(() => _lookahead = v * 10),
          ),

          // Ratio (for expander mode)
          if (_mode == GateMode.expand)
            FabFilterKnob(
              value: _ratio / 100,
              label: 'RATIO',
              display: '${_ratio.toStringAsFixed(0)}%',
              color: FabFilterColors.orange,
              onChanged: (v) => setState(() => _ratio = v * 100),
            ),
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
