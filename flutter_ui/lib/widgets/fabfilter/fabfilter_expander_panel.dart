/// FF-X Expander Panel — Pro-X Premium Downward Expansion
///
/// Professional expander interface with FabFilter-authentic visuals:
/// - Scrolling I/O waveform with expansion-colored output fills
/// - Glass transfer curve with animated input dot + glow
/// - Envelope visualization (ATT → REL shape overlay)
/// - Animated expansion state badge with pulse glow
/// - Expansion zone fill on display (below threshold)
/// - dB axis labels + time grid on scrolling display

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

/// Expander state for visualization
enum ExpanderState {
  passing,   // Signal above threshold — no expansion
  expanding, // Signal below threshold — gain reduction active
}

/// Level sample for scrolling display
class ExpanderLevelSample {
  final double input;
  final double output;
  final double expansion; // 0-1 (0 = full expansion, 1 = passing)
  final ExpanderState state;

  ExpanderLevelSample({
    required this.input,
    required this.output,
    required this.expansion,
    required this.state,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class ExpanderSnapshot implements DspParameterSnapshot {
  final double threshold, ratio, knee, attack, release;

  const ExpanderSnapshot({
    required this.threshold,
    required this.ratio,
    required this.knee,
    required this.attack,
    required this.release,
  });

  @override
  ExpanderSnapshot copy() => ExpanderSnapshot(
    threshold: threshold, ratio: ratio, knee: knee,
    attack: attack, release: release,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! ExpanderSnapshot) return false;
    return threshold == other.threshold && ratio == other.ratio &&
        knee == other.knee && attack == other.attack &&
        release == other.release;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterExpanderPanel extends FabFilterPanelBase {
  const FabFilterExpanderPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-X',
          icon: Icons.expand,
          accentColor: FabFilterColors.green,
          nodeType: DspNodeType.expander,
        );

  @override
  State<FabFilterExpanderPanel> createState() => _FabFilterExpanderPanelState();
}

class _FabFilterExpanderPanelState extends State<FabFilterExpanderPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  // Main parameters (matching ExpanderWrapper param indices 0-4)
  double _threshold = -30.0; // dB  (param 0)
  double _ratio = 2.0;       // :1  (param 1)
  double _knee = 6.0;        // dB  (param 2)
  double _attack = 5.0;      // ms  (param 3)
  double _release = 100.0;   // ms  (param 4)

  // Display
  final List<ExpanderLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 200;

  // Real-time state
  double _currentInputLevel = -60.0;
  double _currentOutputLevel = -60.0;
  ExpanderState _currentState = ExpanderState.passing;
  double _expansionAmount = 1.0; // 1 = no expansion, 0 = full

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late AnimationController _meterController;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // DspChainProvider integration
  String? _nodeId;
  int _slotIndex = -1;

  // A/B snapshots
  ExpanderSnapshot? _snapshotA;
  ExpanderSnapshot? _snapshotB;

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
      if (node.type == DspNodeType.expander) {
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
      _ratio = _ffi.insertGetParam(widget.trackId, _slotIndex, 1);
      _knee = _ffi.insertGetParam(widget.trackId, _slotIndex, 2);
      _attack = _ffi.insertGetParam(widget.trackId, _slotIndex, 3);
      _release = _ffi.insertGetParam(widget.trackId, _slotIndex, 4);
      // Clamp to valid ranges
      if (_threshold == 0.0 && _ratio == 0.0) {
        // Likely uninitialized — use defaults
        _threshold = -30.0;
        _ratio = 2.0;
        _knee = 6.0;
        _attack = 5.0;
        _release = 100.0;
        _applyAll();
      }
      _ratio = _ratio.clamp(1.0, 20.0);
      _knee = _knee.clamp(0.0, 24.0);
      _attack = _attack.clamp(0.01, 100.0);
      _release = _release.clamp(1.0, 1000.0);
    });
  }

  // ─── A/B STATE ───────────────────────────────────────────────────────

  ExpanderSnapshot _snap() => ExpanderSnapshot(
    threshold: _threshold, ratio: _ratio, knee: _knee,
    attack: _attack, release: _release,
  );

  void _restore(ExpanderSnapshot s) {
    setState(() {
      _threshold = s.threshold; _ratio = s.ratio; _knee = s.knee;
      _attack = s.attack; _release = s.release;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _ratio);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _knee);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _attack);
    _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);
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

        // Compute expansion from levels
        if (_currentInputLevel < _threshold) {
          final belowDb = _threshold - _currentInputLevel;
          final expansionDb = belowDb * (_ratio - 1.0) / _ratio;
          _expansionAmount = (1.0 - (expansionDb / 60.0)).clamp(0.0, 1.0);
        } else {
          _expansionAmount += (1.0 - _expansionAmount) * 0.3;
        }

        _currentState = _expansionAmount < 0.95
            ? ExpanderState.expanding
            : ExpanderState.passing;
      } else {
        // Simulated metering for display when engine not connected
        final isBelow = _currentInputLevel < _threshold;
        if (isBelow) {
          final belowDb = _threshold - _currentInputLevel;
          final expansionDb = belowDb * (_ratio - 1.0) / _ratio;
          _expansionAmount = (1.0 - (expansionDb / 60.0)).clamp(0.0, 1.0);
          _currentOutputLevel = _currentInputLevel - expansionDb;
          _currentState = ExpanderState.expanding;
        } else {
          _expansionAmount = (_expansionAmount + 0.05).clamp(0.0, 1.0);
          _currentOutputLevel = _currentInputLevel;
          _currentState = ExpanderState.passing;
        }
      }

      _levelHistory.add(ExpanderLevelSample(
        input: _currentInputLevel,
        output: _currentOutputLevel,
        expansion: _expansionAmount,
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
      return buildNotLoadedState('Expander', DspNodeType.expander, widget.trackId, () {
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
                        // Scrolling level display
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: FabFilterDecorations.display(),
                            clipBehavior: Clip.hardEdge,
                            child: CustomPaint(
                              painter: _ExpanderDisplayPainter(
                                history: _levelHistory,
                                threshold: _threshold,
                                ratio: _ratio,
                                knee: _knee,
                                attack: _attack,
                                release: _release,
                                expansionAmount: _expansionAmount,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Transfer curve + state + meters
                        SizedBox(
                          width: 110,
                          child: Column(
                            children: [
                              // Transfer curve
                              Expanded(
                                flex: 3,
                                child: Container(
                                  decoration: FabFilterDecorations.display(),
                                  clipBehavior: Clip.hardEdge,
                                  child: CustomPaint(
                                    painter: _ExpanderTransferCurvePainter(
                                      threshold: _threshold,
                                      ratio: _ratio,
                                      knee: _knee,
                                      inputLevel: _currentInputLevel,
                                      expansionAmount: _expansionAmount,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Expansion state badge
                              _buildExpanderStateBadge(),
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
                                    Expanded(child: _buildMiniMeter('GR', -((_currentInputLevel - _currentOutputLevel).abs()), FabFilterColors.orange)),
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
                  // BOTTOM: Knobs + ratio display
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
          const SizedBox(width: 8),
          Flexible(
            child: Text('Downward Expander', style: TextStyle(
              color: FabFilterColors.textTertiary, fontSize: 9,
            ), overflow: TextOverflow.ellipsis),
          ),
          const Spacer(),
          // Expansion amount indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _expansionAmount >= 0.99 ? '0.0 dB'
                  : '-${((1.0 - _expansionAmount) * 60).toStringAsFixed(1)} dB',
              style: TextStyle(
                color: _expansionAmount > 0.95 ? FabFilterColors.green : FabFilterColors.orange,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: widget.accentColor),
          const SizedBox(width: 8),
          FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass),
        ],
      ),
    );
  }

  // ─── Expander State Badge ─────────────────────────────────────────────

  Widget _buildExpanderStateBadge() {
    final stateColor = switch (_currentState) {
      ExpanderState.passing => FabFilterColors.green,
      ExpanderState.expanding => FabFilterColors.orange,
    };
    final stateLabel = switch (_currentState) {
      ExpanderState.passing => 'PASSING',
      ExpanderState.expanding => 'EXPANDING',
    };

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        final glowIntensity = _currentState == ExpanderState.expanding
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
          value: ((_threshold + 80) / 80).clamp(0.0, 1.0),
          label: 'THRESH',
          display: '${_threshold.toStringAsFixed(0)} dB',
          color: FabFilterColors.green,
          onChanged: (v) {
            setState(() => _threshold = v * 80 - 80);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);
          },
        ),
        _buildSmallKnob(
          value: ((_ratio - 1) / 19).clamp(0.0, 1.0),
          label: 'RATIO',
          display: '${_ratio.toStringAsFixed(1)}:1',
          color: FabFilterColors.orange,
          onChanged: (v) {
            setState(() => _ratio = 1.0 + v * 19.0);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _ratio);
          },
        ),
        _buildSmallKnob(
          value: (_knee / 24).clamp(0.0, 1.0),
          label: 'KNEE',
          display: '${_knee.toStringAsFixed(0)} dB',
          color: FabFilterColors.blue,
          onChanged: (v) {
            setState(() => _knee = v * 24);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _knee);
          },
        ),
        _buildSmallKnob(
          value: (math.log(_attack / 0.01) / math.log(100 / 0.01)).clamp(0.0, 1.0),
          label: 'ATT',
          display: _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)} µs' : '${_attack.toStringAsFixed(1)} ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _attack = 0.01 * math.pow(100 / 0.01, v).toDouble());
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _attack);
          },
        ),
        _buildSmallKnob(
          value: (math.log(_release / 1) / math.log(1000 / 1)).clamp(0.0, 1.0),
          label: 'REL',
          display: _release >= 100 ? '${(_release / 1000).toStringAsFixed(1)} s' : '${_release.toStringAsFixed(0)} ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _release = 1 * math.pow(1000 / 1, v).toDouble());
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);
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
          FabSectionLabel('EXPANSION'),
          const SizedBox(height: 6),
          // Ratio display
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FabFilterColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ratio', style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 8)),
                const SizedBox(height: 2),
                Text(
                  '${_ratio.toStringAsFixed(1)}:1',
                  style: TextStyle(
                    color: FabFilterColors.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Threshold indicator
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FabFilterColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Threshold', style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 8)),
                const SizedBox(height: 2),
                Text(
                  '${_threshold.toStringAsFixed(0)} dB',
                  style: TextStyle(
                    color: FabFilterColors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Knee info
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FabFilterColors.border),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Knee', style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 8)),
                    Text(
                      _knee <= 0.5 ? 'Hard' : '${_knee.toStringAsFixed(0)} dB',
                      style: TextStyle(
                        color: FabFilterColors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Knee type icon
                Icon(
                  _knee <= 0.5 ? Icons.show_chart : Icons.timeline,
                  color: FabFilterColors.blue.withValues(alpha: 0.5),
                  size: 16,
                ),
              ],
            ),
          ),
          const Flexible(child: SizedBox(height: 8)),
          if (showExpertMode) ...[
            FabSectionLabel('TIMING'),
            const SizedBox(height: 4),
            FabMiniSlider(
              label: 'A',
              value: (math.log(_attack / 0.01) / math.log(100 / 0.01)).clamp(0.0, 1.0),
              display: '${_attack.toStringAsFixed(1)}ms',
              onChanged: (v) {
                setState(() => _attack = 0.01 * math.pow(100 / 0.01, v).toDouble());
                if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _attack);
              },
            ),
            const SizedBox(height: 2),
            FabMiniSlider(
              label: 'R',
              value: (math.log(_release / 1) / math.log(1000 / 1)).clamp(0.0, 1.0),
              display: '${_release.toStringAsFixed(0)}ms',
              onChanged: (v) {
                setState(() => _release = 1 * math.pow(1000 / 1, v).toDouble());
                if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _release);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPANDER DISPLAY PAINTER — Premium scrolling visualization
// ═══════════════════════════════════════════════════════════════════════════

class _ExpanderDisplayPainter extends CustomPainter {
  final List<ExpanderLevelSample> history;
  final double threshold;
  final double ratio;
  final double knee;
  final double attack;
  final double release;
  final double expansionAmount;

  _ExpanderDisplayPainter({
    required this.history,
    required this.threshold,
    required this.ratio,
    required this.knee,
    required this.attack,
    required this.release,
    required this.expansionAmount,
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

    // ─── Expansion zone (below threshold — subtle fill) ──────────────
    final thresholdY = h * (1 - (threshold + 60) / 60);
    canvas.drawRect(
      Rect.fromLTRB(0, thresholdY, w, h),
      Paint()..color = FabFilterColors.orange.withValues(alpha: 0.04),
    );

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
      final tp = TextPainter(
        text: TextSpan(text: '${db}dB', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height - 1));
    }

    // ─── Threshold line with glow ────────────────────────────────────
    final threshGlow = Paint()
      ..color = FabFilterColors.green.withValues(alpha: 0.3)
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(Offset(0, thresholdY), Offset(w, thresholdY), threshGlow);

    final threshLine = Paint()
      ..color = FabFilterColors.green
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, thresholdY), Offset(w, thresholdY), threshLine);

    // ─── Knee zone (gradient tint around threshold) ──────────────────
    if (knee > 0.5) {
      final kneeHalfDb = knee / 2;
      final kneeTopY = h * (1 - (threshold + kneeHalfDb + 60) / 60);
      final kneeBotY = h * (1 - (threshold - kneeHalfDb + 60) / 60);
      canvas.drawRect(
        Rect.fromLTRB(0, kneeTopY, w, kneeBotY),
        Paint()..color = FabFilterColors.blue.withValues(alpha: 0.05),
      );
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
    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final sample = history[i];
      final normalizedLevel = ((sample.output + 60) / 60).clamp(0.0, 1.0);
      final barHeight = h * normalizedLevel;

      final color = switch (sample.state) {
        ExpanderState.passing => FabFilterColors.green,
        ExpanderState.expanding => FabFilterColors.orange,
      };

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

    // ─── Envelope shape overlay (ATT-REL) ────────────────────────────
    _drawEnvelopeOverlay(canvas, size);

    // ─── Threshold label ─────────────────────────────────────────────
    _drawLabel(canvas, 'Threshold: ${threshold.toStringAsFixed(0)} dB',
        Offset(w - 140, thresholdY - 12), FabFilterColors.green);

    // ─── Ratio label ─────────────────────────────────────────────────
    _drawLabel(canvas, 'Ratio: ${ratio.toStringAsFixed(1)}:1',
        Offset(w - 100, h - 14), FabFilterColors.orange);
  }

  void _drawEnvelopeOverlay(Canvas canvas, Size size) {
    final envW = 50.0;
    final envH = 24.0;
    final envX = size.width - envW - 4;
    final envY = 4.0;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(envX, envY, envW, envH), const Radius.circular(3)),
      Paint()..color = FabFilterColors.bgVoid.withValues(alpha: 0.8),
    );

    // Normalize timings (no hold for expander)
    final totalMs = attack + release;
    if (totalMs <= 0) return;
    final attFrac = attack / totalMs;

    final envPath = Path();
    final startX = envX + 2;
    final endX = envX + envW - 2;
    final topY = envY + 3;
    final botY = envY + envH - 3;
    final envWidth = endX - startX;

    // Attack ramp up
    envPath.moveTo(startX, botY);
    envPath.lineTo(startX + envWidth * attFrac, topY);
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
      (startX + envWidth * (attFrac + (1 - attFrac) * 0.5), (topY + botY) / 2, 'R', FabFilterColors.cyan),
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
  bool shouldRepaint(covariant _ExpanderDisplayPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSFER CURVE PAINTER — Downward expansion characteristic
// ═══════════════════════════════════════════════════════════════════════════

class _ExpanderTransferCurvePainter extends CustomPainter {
  final double threshold;
  final double ratio;
  final double knee;
  final double inputLevel;
  final double expansionAmount;

  _ExpanderTransferCurvePainter({
    required this.threshold,
    required this.ratio,
    required this.knee,
    required this.inputLevel,
    required this.expansionAmount,
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

    // Transfer curve — downward expansion
    const dbMin = -80.0;
    const dbMax = 0.0;
    const dbRange = dbMax - dbMin;

    final fillPath = Path();
    final curvePath = Path();

    for (var i = 0; i <= w.toInt(); i++) {
      final inputDb = dbMin + (i / w) * dbRange;
      double outputDb;

      if (inputDb >= threshold) {
        // Above threshold — unity (pass through)
        outputDb = inputDb;
      } else if (knee > 0.5 && inputDb > threshold - knee) {
        // Knee region — smooth transition
        final kneeRange = knee;
        final belowThresh = threshold - inputDb;
        final kneeBlend = belowThresh / kneeRange;
        final fullExpansion = inputDb - (threshold - inputDb) * (ratio - 1);
        outputDb = inputDb + (fullExpansion - inputDb) * kneeBlend * kneeBlend;
      } else {
        // Below threshold — expand (reduce gain)
        final belowDb = threshold - inputDb;
        outputDb = inputDb - belowDb * (ratio - 1);
      }

      final x = i.toDouble();
      final y = h - ((outputDb - dbMin) / dbRange).clamp(0.0, 1.0) * h;
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

    // Expansion zone fill
    canvas.drawPath(fillPath, Paint()
      ..color = FabFilterColors.orange.withValues(alpha: 0.08));

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
    } else if (knee > 0.5 && inputLevel > threshold - knee) {
      final kneeRange = knee;
      final belowThresh = threshold - inputLevel;
      final kneeBlend = belowThresh / kneeRange;
      final fullExpansion = inputLevel - (threshold - inputLevel) * (ratio - 1);
      outDb = inputLevel + (fullExpansion - inputLevel) * kneeBlend * kneeBlend;
    } else {
      final belowDb = threshold - inputLevel;
      outDb = inputLevel - belowDb * (ratio - 1);
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
  bool shouldRepaint(covariant _ExpanderTransferCurvePainter old) {
    return threshold != old.threshold || ratio != old.ratio ||
        knee != old.knee || inputLevel != old.inputLevel ||
        expansionAmount != old.expansionAmount;
  }
}
