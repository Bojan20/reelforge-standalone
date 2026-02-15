/// FF-L Limiter Panel
///
/// Professional limiter interface:
/// - Real-time scrolling waveform display with GR history
/// - True Peak limiting/metering via FFI
/// - LUFS metering (Integrated, Short-term, Momentary)
/// - 8 limiting styles as visual chips
/// - Multiple meter scales (K-12, K-14, K-20)
/// - Compact layout with activated display painter

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

/// Limiting style (8 styles) with icons for chip selector
enum LimitingStyle {
  transparent('Trans', Icons.lens_blur),
  punchy('Punch', Icons.flash_on),
  dynamic('Dynamic', Icons.equalizer),
  aggressive('Aggro', Icons.bolt),
  bus('Bus', Icons.route),
  safe('Safe', Icons.shield),
  modern('Modern', Icons.auto_awesome),
  allround('All', Icons.circle);

  final String label;
  final IconData icon;
  const LimitingStyle(this.label, this.icon);
}

/// Meter scale options
enum MeterScale {
  normal('0 dB', 0),
  k12('K-12', -12),
  k14('K-14', -14),
  k20('K-20', -20);

  final String label;
  final int offset;
  const MeterScale(this.label, this.offset);
}

/// Level sample for scrolling display
class LimiterLevelSample {
  final double inputPeak;
  final double outputPeak;
  final double gainReduction;
  final double truePeak;

  const LimiterLevelSample({
    required this.inputPeak,
    required this.outputPeak,
    required this.gainReduction,
    required this.truePeak,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// PARAM INDEX CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const inputTrim = 0;
  static const threshold = 1;
  static const ceiling = 2;
  static const release = 3;
  static const attack = 4;
  static const lookahead = 5;
  static const style = 6;
  static const oversampling = 7;
  static const stereoLink = 8;
  static const msMode = 9;
  static const mix = 10;
  static const ditherBits = 11;
  static const latencyProfile = 12;
  static const channelConfig = 13;
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterLimiterPanel extends FabFilterPanelBase {
  const FabFilterLimiterPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-L',
          icon: Icons.graphic_eq,
          accentColor: FabFilterColors.red,
          nodeType: DspNodeType.limiter,
        );

  @override
  State<FabFilterLimiterPanel> createState() => _FabFilterLimiterPanelState();
}

class _FabFilterLimiterPanelState extends State<FabFilterLimiterPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {

  // ─── DSP PARAMETERS ──────────────────────────────────────────────────
  double _inputTrim = 0.0;
  double _threshold = 0.0;
  double _output = -0.3;
  double _release = 100.0;
  double _attack = 0.1;
  double _lookahead = 5.0;
  LimitingStyle _style = LimitingStyle.allround;
  int _oversampling = 1;
  double _stereoLink = 100.0;
  bool _msMode = false;
  double _mix = 100.0;
  int _ditherBits = 0;
  int _latencyProfile = 1;
  int _channelConfig = 0;

  // ─── METERING STATE ──────────────────────────────────────────────────
  MeterScale _meterScale = MeterScale.normal;
  double _grLeft = 0.0;
  double _grRight = 0.0;
  double _inputPeakL = -60.0;
  double _inputPeakR = -60.0;
  double _outputTpL = -60.0;
  double _outputTpR = -60.0;
  double _grMaxHold = 0.0;
  bool _truePeakClipping = false;

  // LUFS readings (from FFI advanced metering)
  double _lufsIntegrated = -24.0;
  double _lufsShortTerm = -24.0;
  double _lufsMomentary = -24.0;

  // ─── DISPLAY HISTORY ─────────────────────────────────────────────────
  final List<LimiterLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 200;

  // ─── ANIMATION & FFI ─────────────────────────────────────────────────
  late AnimationController _meterController;
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;

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
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);
    if (!chain.nodes.any((n) => n.type == DspNodeType.limiter)) {
      dsp.addNode(widget.trackId, DspNodeType.limiter);
      chain = dsp.getChain(widget.trackId);
    }
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.limiter) {
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
    final t = widget.trackId;
    final s = _slotIndex;
    setState(() {
      _inputTrim = _ffi.insertGetParam(t, s, _P.inputTrim);
      _threshold = _ffi.insertGetParam(t, s, _P.threshold);
      _output = _ffi.insertGetParam(t, s, _P.ceiling);
      _release = _ffi.insertGetParam(t, s, _P.release);
      _attack = _ffi.insertGetParam(t, s, _P.attack);
      _lookahead = _ffi.insertGetParam(t, s, _P.lookahead);
      final styleIdx = _ffi.insertGetParam(t, s, _P.style).toInt().clamp(0, 7);
      _style = LimitingStyle.values[styleIdx];
      _oversampling = _ffi.insertGetParam(t, s, _P.oversampling).toInt().clamp(0, 3);
      _stereoLink = _ffi.insertGetParam(t, s, _P.stereoLink);
      _msMode = _ffi.insertGetParam(t, s, _P.msMode) > 0.5;
      _mix = _ffi.insertGetParam(t, s, _P.mix);
      _ditherBits = _ffi.insertGetParam(t, s, _P.ditherBits).toInt().clamp(0, 4);
      _latencyProfile = _ffi.insertGetParam(t, s, _P.latencyProfile).toInt().clamp(0, 2);
      _channelConfig = _ffi.insertGetParam(t, s, _P.channelConfig).toInt().clamp(0, 2);
    });
  }

  void _setParam(int index, double value) {
    if (!_initialized || _slotIndex < 0) return;
    _ffi.insertSetParam(widget.trackId, _slotIndex, index, value);
  }

  @override
  void dispose() {
    _meterController.dispose();
    super.dispose();
  }

  void _updateMeters() {
    if (!mounted || !_initialized || _slotIndex < 0) return;
    setState(() {
      final t = widget.trackId;
      final s = _slotIndex;
      try {
        _grLeft = _ffi.insertGetMeter(t, s, 0);
        _grRight = _ffi.insertGetMeter(t, s, 1);
        _inputPeakL = _ffi.insertGetMeter(t, s, 2);
        _inputPeakR = _ffi.insertGetMeter(t, s, 3);
        _outputTpL = _ffi.insertGetMeter(t, s, 4);
        _outputTpR = _ffi.insertGetMeter(t, s, 5);
        _grMaxHold = _ffi.insertGetMeter(t, s, 6);
      } catch (_) {}

      // LUFS from engine metering API
      try {
        final (mom, st, integ) = _ffi.getLufsMeters();
        _lufsMomentary = mom;
        _lufsShortTerm = st;
        _lufsIntegrated = integ;
      } catch (_) {}

      final outTpMax = math.max(_outputTpL, _outputTpR);
      _truePeakClipping = outTpMax > _output + 0.1;

      // Build scrolling history
      final grDisplay = math.max(_grLeft, _grRight);
      final inPeakMax = math.max(_inputPeakL, _inputPeakR);
      _levelHistory.add(LimiterLevelSample(
        inputPeak: inPeakMax,
        outputPeak: outTpMax,
        gainReduction: grDisplay,
        truePeak: outTpMax,
      ));
      while (_levelHistory.length > _maxHistorySamples) {
        _levelHistory.removeAt(0);
      }
    });
  }

  // ─── BUILD ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildCompactHeader(),
          // Scrolling waveform display
          SizedBox(
            height: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildDisplay(),
            ),
          ),
          // Controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  // Style chips + oversampling
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: [
                        Expanded(child: _buildStyleChips()),
                        const SizedBox(width: 4),
                        _buildOversamplingChip(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Main knobs + meters + options
                  Expanded(child: _buildMainRow()),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // ─── DISPLAY (scrolling waveform + GR history) ───────────────────────

  Widget _buildDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Scrolling waveform painter
          Positioned.fill(
            child: CustomPaint(
              painter: _LimiterDisplayPainter(
                history: _levelHistory,
                ceiling: _output,
                threshold: _threshold,
                meterScale: _meterScale,
              ),
            ),
          ),
          // LUFS overlay (top-left)
          Positioned(
            left: 6,
            top: 4,
            child: _buildLufsOverlay(),
          ),
          // True peak indicator (top-right)
          Positioned(
            right: 6,
            top: 4,
            child: _buildTruePeakBadge(),
          ),
          // GR value (bottom-right)
          Positioned(
            right: 6,
            bottom: 4,
            child: _buildGrBadge(),
          ),
          // Meter scale (bottom-left)
          Positioned(
            left: 6,
            bottom: 4,
            child: _buildScaleSelector(),
          ),
        ],
      ),
    );
  }

  Widget _buildLufsOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _lufsLine('INT', _lufsIntegrated, FabFilterColors.green),
          _lufsLine('S-T', _lufsShortTerm, FabFilterColors.cyan),
          _lufsLine('MOM', _lufsMomentary, FabFilterColors.blue),
        ],
      ),
    );
  }

  Widget _lufsLine(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 8, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Text(
          value > -100 ? '${value.toStringAsFixed(1)}' : '-∞',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildTruePeakBadge() {
    final outTpMax = math.max(_outputTpL, _outputTpR);
    final tpColor = _truePeakClipping
        ? FabFilterColors.red
        : (outTpMax > _output - 0.5 ? FabFilterColors.orange : FabFilterColors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(3),
        border: _truePeakClipping ? Border.all(color: FabFilterColors.red, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tpColor),
          ),
          const SizedBox(width: 3),
          Text(
            'TP ${outTpMax > -100 ? '${outTpMax.toStringAsFixed(1)}' : '-∞'}',
            style: TextStyle(color: tpColor, fontSize: 9, fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _buildGrBadge() {
    final grMax = math.max(_grLeft, _grRight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'GR -${grMax.toStringAsFixed(1)}dB  max -${_grMaxHold.toStringAsFixed(1)}dB',
        style: TextStyle(
          color: FabFilterProcessorColors.limGainReduction,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildScaleSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: MeterScale.values.map((s) {
        final isActive = _meterScale == s;
        return GestureDetector(
          onTap: () => setState(() => _meterScale = s),
          child: Container(
            margin: const EdgeInsets.only(right: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isActive ? FabFilterColors.blue.withValues(alpha: 0.3) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              s.label,
              style: TextStyle(
                color: isActive ? FabFilterColors.blue : FabFilterColors.textTertiary,
                fontSize: 8,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── STYLE CHIPS ─────────────────────────────────────────────────────

  Widget _buildStyleChips() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: LimitingStyle.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (ctx, i) {
        final s = LimitingStyle.values[i];
        final isActive = _style == s;
        return GestureDetector(
          onTap: () {
            setState(() => _style = s);
            _setParam(_P.style, s.index.toDouble());
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? FabFilterProcessorColors.limAccent.withValues(alpha: 0.25)
                  : FabFilterColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? FabFilterProcessorColors.limAccent : FabFilterColors.borderMedium,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 12, color: isActive ? FabFilterProcessorColors.limAccent : FabFilterColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  s.label,
                  style: TextStyle(
                    color: isActive ? FabFilterProcessorColors.limAccent : FabFilterColors.textSecondary,
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── OVERSAMPLING CHIP ───────────────────────────────────────────────

  Widget _buildOversamplingChip() {
    return GestureDetector(
      onTap: () {
        setState(() => _oversampling = (_oversampling + 1) % 4);
        _setParam(_P.oversampling, _oversampling.toDouble());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _oversampling > 0
              ? FabFilterColors.green.withValues(alpha: 0.2)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _oversampling > 0 ? FabFilterColors.green : FabFilterColors.borderMedium),
        ),
        child: Text(
          _oversamplingLabel(),
          style: TextStyle(
            color: _oversampling > 0 ? FabFilterColors.green : FabFilterColors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _oversamplingLabel() => ['1×', '2×', '4×', '8×'][_oversampling.clamp(0, 3)];

  // ─── MAIN ROW: Meters | Knobs | Options ──────────────────────────────

  Widget _buildMainRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT: Vertical meters
        SizedBox(width: 80, child: _buildVerticalMeters()),
        const SizedBox(width: 8),
        // CENTER: Main knobs
        Expanded(flex: 3, child: _buildKnobs()),
        const SizedBox(width: 8),
        // RIGHT: Options
        SizedBox(width: 100, child: _buildOptions()),
      ],
    );
  }

  // ─── VERTICAL INPUT/OUTPUT METERS ────────────────────────────────────

  Widget _buildVerticalMeters() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          // In L/R
          Expanded(child: _buildMeterBar('In', _inputPeakL, _inputPeakR, FabFilterColors.blue)),
          const SizedBox(width: 2),
          // Out L/R
          Expanded(child: _buildMeterBar('Out', _outputTpL, _outputTpR, FabFilterProcessorColors.limTruePeak)),
          const SizedBox(width: 2),
          // GR
          Expanded(child: _buildGrBar()),
        ],
      ),
    );
  }

  Widget _buildMeterBar(String label, double left, double right, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _singleBar(left, color)),
              const SizedBox(width: 1),
              Expanded(child: _singleBar(right, color)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          math.max(left, right) > -100 ? '${math.max(left, right).toStringAsFixed(0)}' : '-∞',
          style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }

  Widget _singleBar(double dbValue, Color color) {
    final norm = ((dbValue + 60) / 60).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final h = constraints.maxHeight;
        final barH = h * norm;
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: double.infinity,
              height: h,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Container(
              width: double.infinity,
              height: barH,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [color.withValues(alpha: 0.5), color],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrBar() {
    final grMax = math.max(_grLeft, _grRight);
    final grNorm = (grMax / 24).clamp(0.0, 1.0);
    return Column(
      children: [
        Text('GR', style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final h = constraints.maxHeight;
            final barH = h * grNorm;
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: double.infinity,
                  height: h,
                  decoration: BoxDecoration(
                    color: FabFilterColors.bgVoid,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                Container(
                  width: double.infinity,
                  height: barH,
                  decoration: BoxDecoration(
                    gradient: FabFilterGradients.grVertical,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 2),
        Text(
          '-${grMax.toStringAsFixed(0)}',
          style: TextStyle(color: FabFilterProcessorColors.limGainReduction, fontSize: 7,
              fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }

  // ─── KNOBS ───────────────────────────────────────────────────────────

  Widget _buildKnobs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _knob(
          value: (_inputTrim + 12) / 24,
          label: 'TRIM',
          display: '${_inputTrim >= 0 ? '+' : ''}${_inputTrim.toStringAsFixed(1)}dB',
          color: FabFilterColors.orange,
          onChanged: (v) {
            setState(() => _inputTrim = v * 24 - 12);
            _setParam(_P.inputTrim, _inputTrim);
          },
        ),
        _knob(
          value: (_threshold + 30) / 30,
          label: 'THRESH',
          display: '${_threshold.toStringAsFixed(1)}dB',
          color: FabFilterProcessorColors.limAccent,
          onChanged: (v) {
            setState(() => _threshold = v * 30 - 30);
            _setParam(_P.threshold, _threshold);
          },
        ),
        _knob(
          value: (_output + 3) / 3,
          label: 'CEILING',
          display: '${_output.toStringAsFixed(1)}dBTP',
          color: FabFilterProcessorColors.limCeiling,
          onChanged: (v) {
            setState(() => _output = v * 3 - 3);
            _setParam(_P.ceiling, _output);
          },
        ),
        _knob(
          value: math.log(_release.clamp(1, 1000) / 1) / math.log(1000),
          label: 'RELEASE',
          display: _release >= 100
              ? '${(_release / 1000).toStringAsFixed(2)}s'
              : '${_release.toStringAsFixed(0)}ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _release = math.pow(1000, v).toDouble().clamp(1, 1000));
            _setParam(_P.release, _release);
          },
        ),
        if (showExpertMode) ...[
          _knob(
            value: math.log(_attack.clamp(0.01, 10) / 0.01) / math.log(10 / 0.01),
            label: 'ATTACK',
            display: _attack < 1
                ? '${(_attack * 1000).toStringAsFixed(0)}µs'
                : '${_attack.toStringAsFixed(1)}ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _attack = (0.01 * math.pow(10 / 0.01, v)).clamp(0.01, 10));
              _setParam(_P.attack, _attack);
            },
          ),
          _knob(
            value: _lookahead / 20,
            label: 'LOOK',
            display: '${_lookahead.toStringAsFixed(1)}ms',
            color: FabFilterColors.purple,
            onChanged: (v) {
              setState(() => _lookahead = v * 20);
              _setParam(_P.lookahead, _lookahead);
            },
          ),
          _knob(
            value: _mix / 100,
            label: 'MIX',
            display: '${_mix.toStringAsFixed(0)}%',
            color: FabFilterColors.green,
            onChanged: (v) {
              setState(() => _mix = v * 100);
              _setParam(_P.mix, _mix);
            },
          ),
        ],
      ],
    );
  }

  Widget _knob({
    required double value,
    required String label,
    required String display,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 48,
      onChanged: onChanged,
    );
  }

  // ─── OPTIONS ─────────────────────────────────────────────────────────

  Widget _buildOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stereo link slider
        _buildLinkSlider(),
        const SizedBox(height: 4),
        FabOptionRow(label: 'M/S', value: _msMode, onChanged: (v) {
          setState(() => _msMode = v);
          _setParam(_P.msMode, v ? 1.0 : 0.0);
        }, accentColor: widget.accentColor),
        if (showExpertMode) ...[
          const SizedBox(height: 4),
          FabEnumSelector(label: 'CH', value: _channelConfig, options: const ['St', 'Dual', 'M/S'], onChanged: (v) {
            setState(() => _channelConfig = v);
            _setParam(_P.channelConfig, v.toDouble());
          }),
          const SizedBox(height: 4),
          FabEnumSelector(label: 'LAT', value: _latencyProfile, options: const ['Zero', 'HQ', 'Off'], onChanged: (v) {
            setState(() => _latencyProfile = v);
            _setParam(_P.latencyProfile, v.toDouble());
          }),
          const SizedBox(height: 4),
          FabEnumSelector(label: 'DTH', value: _ditherBits, options: const ['Off', '8', '12', '16', '24'], onChanged: (v) {
            setState(() => _ditherBits = v);
            _setParam(_P.ditherBits, v.toDouble());
          }),
        ],
        const Flexible(child: SizedBox(height: 8)),
      ],
    );
  }

  Widget _buildLinkSlider() {
    return FabMiniSlider(
      label: 'LNK',
      value: _stereoLink / 100,
      display: '${_stereoLink.toStringAsFixed(0)}%',
      activeColor: FabFilterColors.purple,
      onChanged: (v) {
        setState(() => _stereoLink = v * 100);
        _setParam(_P.stereoLink, _stereoLink);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIMITER DISPLAY PAINTER — Scrolling waveform + GR bars + ceiling/threshold
// ═══════════════════════════════════════════════════════════════════════════

class _LimiterDisplayPainter extends CustomPainter {
  final List<LimiterLevelSample> history;
  final double ceiling;
  final double threshold;
  final MeterScale meterScale;

  _LimiterDisplayPainter({
    required this.history,
    required this.ceiling,
    required this.threshold,
    required this.meterScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background gradient
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      ));

    // Grid lines & labels
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;
    final dbOffset = meterScale.offset.toDouble();
    final totalRange = 48.0 + dbOffset.abs();

    for (var db = -48; db <= 0; db += 6) {
      final y = _dbToY(db.toDouble(), size.height, dbOffset, totalRange);
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Threshold line (yellow dashed)
    final threshY = _dbToY(threshold, size.height, dbOffset, totalRange);
    if (threshY >= 0 && threshY <= size.height) {
      final threshPaint = Paint()
        ..color = FabFilterProcessorColors.limCeiling.withValues(alpha: 0.5)
        ..strokeWidth = 1.0;
      _drawDashedLine(canvas, Offset(0, threshY), Offset(size.width, threshY), threshPaint);
    }

    // Ceiling line (red solid)
    final ceilingY = _dbToY(ceiling, size.height, dbOffset, totalRange);
    if (ceilingY >= 0 && ceilingY <= size.height) {
      canvas.drawLine(
        Offset(0, ceilingY), Offset(size.width, ceilingY),
        Paint()..color = FabFilterProcessorColors.limAccent..strokeWidth = 1.5,
      );
    }

    if (history.isEmpty) return;

    final sampleWidth = size.width / _maxSamples;
    final startX = size.width - history.length * sampleWidth;

    // GR bars (from top, red gradient)
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final gr = history[i].gainReduction.abs();
      final grHeight = (gr / 24).clamp(0.0, 1.0) * size.height * 0.4;
      if (grHeight > 0.5) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, sampleWidth + 0.5, grHeight),
          Paint()..color = FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.3),
        );
      }
    }

    // Input waveform (muted, background)
    _drawWaveform(canvas, size, history.map((s) => s.inputPeak).toList(),
        FabFilterColors.textMuted.withValues(alpha: 0.2), dbOffset, totalRange, startX, sampleWidth);

    // Output waveform (blue, foreground)
    _drawWaveform(canvas, size, history.map((s) => s.outputPeak).toList(),
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.5), dbOffset, totalRange, startX, sampleWidth);

    // True peak clip markers
    for (var i = 0; i < history.length; i++) {
      if (history[i].truePeak > ceiling + 0.1) {
        final x = startX + i * sampleWidth;
        if (x < 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x, ceilingY.clamp(0, size.height) - 2, sampleWidth + 0.5, 4),
          Paint()..color = FabFilterColors.red,
        );
      }
    }
  }

  static const int _maxSamples = 200;

  double _dbToY(double db, double height, double dbOffset, double totalRange) {
    return height * (1 - (db + 48 + dbOffset) / totalRange);
  }

  void _drawWaveform(Canvas canvas, Size size, List<double> levels,
      Color color, double dbOffset, double totalRange, double startX, double sampleWidth) {
    if (levels.isEmpty) return;
    final path = Path();
    path.moveTo(startX, size.height);
    for (var i = 0; i < levels.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final y = _dbToY(levels[i], size.height, dbOffset, totalRange).clamp(0.0, size.height);
      path.lineTo(x, y);
    }
    path.lineTo(startX + levels.length * sampleWidth, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final totalLength = (end - start).distance;
    final dir = (end - start) / totalLength;
    var d = 0.0;
    while (d < totalLength) {
      final segEnd = math.min(d + dashWidth, totalLength);
      canvas.drawLine(start + dir * d, start + dir * segEnd, paint);
      d += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _LimiterDisplayPainter oldDelegate) => true;
}
