/// FF-L Limiter Panel — Pro-L 2 Ultimate
///
/// Professional brickwall limiter:
/// - Glass scrolling waveform display with GR history
/// - True Peak limiting/metering via FFI (ISP-safe)
/// - LUFS metering (Integrated, Short-term, Momentary)
/// - 8 limiting styles with smooth switching
/// - Multiple meter scales (K-12, K-14, K-20)
/// - A/B comparison with full state snapshots
/// - Real-time I/O + GR metering at 60fps

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
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class LimiterSnapshot implements DspParameterSnapshot {
  final double inputTrim, threshold, output, release, attack, lookahead;
  final double stereoLink, mix;
  final LimitingStyle style;
  final int oversampling, ditherBits, latencyProfile, channelConfig;
  final bool msMode;

  const LimiterSnapshot({
    required this.inputTrim, required this.threshold, required this.output,
    required this.release, required this.attack, required this.lookahead,
    required this.stereoLink, required this.mix, required this.style,
    required this.oversampling, required this.ditherBits,
    required this.latencyProfile, required this.channelConfig,
    required this.msMode,
  });

  @override
  LimiterSnapshot copy() => LimiterSnapshot(
    inputTrim: inputTrim, threshold: threshold, output: output,
    release: release, attack: attack, lookahead: lookahead,
    stereoLink: stereoLink, mix: mix, style: style,
    oversampling: oversampling, ditherBits: ditherBits,
    latencyProfile: latencyProfile, channelConfig: channelConfig,
    msMode: msMode,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! LimiterSnapshot) return false;
    return inputTrim == other.inputTrim && threshold == other.threshold &&
        output == other.output && release == other.release &&
        attack == other.attack && style == other.style &&
        oversampling == other.oversampling && msMode == other.msMode;
  }
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

  // ─── A/B ─────────────────────────────────────────────────────────────
  LimiterSnapshot? _snapshotA;
  LimiterSnapshot? _snapshotB;

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

  // ─── A/B STATE MANAGEMENT ─────────────────────────────────────────────

  LimiterSnapshot _snap() => LimiterSnapshot(
    inputTrim: _inputTrim, threshold: _threshold, output: _output,
    release: _release, attack: _attack, lookahead: _lookahead,
    stereoLink: _stereoLink, mix: _mix, style: _style,
    oversampling: _oversampling, ditherBits: _ditherBits,
    latencyProfile: _latencyProfile, channelConfig: _channelConfig,
    msMode: _msMode,
  );

  void _restore(LimiterSnapshot s) {
    setState(() {
      _inputTrim = s.inputTrim; _threshold = s.threshold; _output = s.output;
      _release = s.release; _attack = s.attack; _lookahead = s.lookahead;
      _stereoLink = s.stereoLink; _mix = s.mix; _style = s.style;
      _oversampling = s.oversampling; _ditherBits = s.ditherBits;
      _latencyProfile = s.latencyProfile; _channelConfig = s.channelConfig;
      _msMode = s.msMode;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.inputTrim, _inputTrim);
    _setParam(_P.threshold, _threshold);
    _setParam(_P.ceiling, _output);
    _setParam(_P.release, _release);
    _setParam(_P.attack, _attack);
    _setParam(_P.lookahead, _lookahead);
    _setParam(_P.style, _style.index.toDouble());
    _setParam(_P.oversampling, _oversampling.toDouble());
    _setParam(_P.stereoLink, _stereoLink);
    _setParam(_P.msMode, _msMode ? 1.0 : 0.0);
    _setParam(_P.mix, _mix);
    _setParam(_P.ditherBits, _ditherBits.toDouble());
    _setParam(_P.latencyProfile, _latencyProfile.toDouble());
    _setParam(_P.channelConfig, _channelConfig.toDouble());
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

  // ─── METERING ─────────────────────────────────────────────────────────

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

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildCompactHeader(),
          // Scrolling waveform display
          SizedBox(
            height: 110,
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

  // ─── DISPLAY (scrolling waveform + GR history) ────────────────────────

  Widget _buildDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Glass scrolling waveform painter
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
            left: 6, top: 4,
            child: _buildLufsOverlay(),
          ),
          // True peak indicator (top-right)
          Positioned(
            right: 6, top: 4,
            child: _buildTruePeakBadge(),
          ),
          // GR value (bottom-right)
          Positioned(
            right: 6, bottom: 4,
            child: _buildGrBadge(),
          ),
          // Meter scale (bottom-left)
          Positioned(
            left: 6, bottom: 4,
            child: _buildScaleSelector(),
          ),
          // Style badge (top-center)
          Positioned(
            left: 0, right: 0, top: 4,
            child: Center(child: _buildStyleBadge()),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.25)),
      ),
      child: Text(
        _style.label.toUpperCase(),
        style: TextStyle(
          color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.5),
          fontSize: 7, fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLufsOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xDD0A0A10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterProcessorColors.limLufs.withValues(alpha: 0.3)),
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
          value > -100 ? value.toStringAsFixed(1) : '-∞',
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
        color: const Color(0xDD0A0A10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _truePeakClipping
              ? FabFilterColors.red.withValues(alpha: 0.6)
              : FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tpColor,
              boxShadow: _truePeakClipping ? [
                BoxShadow(color: FabFilterColors.red.withValues(alpha: 0.5), blurRadius: 4),
              ] : null,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'TP ${outTpMax > -100 ? outTpMax.toStringAsFixed(1) : '-∞'}',
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
        color: const Color(0xDD0A0A10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.3)),
      ),
      child: RichText(text: TextSpan(
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()]),
        children: [
          TextSpan(
            text: 'GR -${grMax.toStringAsFixed(1)}',
            style: TextStyle(color: FabFilterProcessorColors.limGainReduction),
          ),
          TextSpan(
            text: '  pk -${_grMaxHold.toStringAsFixed(1)}',
            style: TextStyle(color: FabFilterColors.textTertiary),
          ),
        ],
      )),
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
              border: isActive ? Border.all(color: FabFilterColors.blue.withValues(alpha: 0.3)) : null,
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

  // ─── STYLE CHIPS ──────────────────────────────────────────────────────

  Widget _buildStyleChips() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: LimitingStyle.values.length,
      separatorBuilder: (_, _a) => const SizedBox(width: 4),
      itemBuilder: (ctx, i) {
        final s = LimitingStyle.values[i];
        final active = _style == s;
        return GestureDetector(
          onTap: () {
            setState(() => _style = s);
            _setParam(_P.style, s.index.toDouble());
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active
                  ? FabFilterProcessorColors.limAccent.withValues(alpha: 0.25)
                  : FabFilterColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? FabFilterProcessorColors.limAccent : FabFilterColors.borderMedium,
                width: active ? 1.5 : 1,
              ),
              boxShadow: active ? [
                BoxShadow(
                  color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 12,
                  color: active ? FabFilterProcessorColors.limAccent : FabFilterColors.textTertiary),
                const SizedBox(width: 3),
                Text(s.label, style: TextStyle(
                  color: active ? FabFilterProcessorColors.limAccent : FabFilterColors.textSecondary,
                  fontSize: 9, fontWeight: active ? FontWeight.bold : FontWeight.w500,
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── OVERSAMPLING CHIP ────────────────────────────────────────────────

  Widget _buildOversamplingChip() {
    final active = _oversampling > 0;
    return GestureDetector(
      onTap: () {
        setState(() => _oversampling = (_oversampling + 1) % 4);
        _setParam(_P.oversampling, _oversampling.toDouble());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? FabFilterColors.green.withValues(alpha: 0.2)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? FabFilterColors.green : FabFilterColors.borderMedium),
          boxShadow: active ? [
            BoxShadow(
              color: FabFilterColors.green.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ] : null,
        ),
        child: Text(
          _oversamplingLabel(),
          style: TextStyle(
            color: active ? FabFilterColors.green : FabFilterColors.textTertiary,
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
        _buildMeters(),
        const SizedBox(width: 8),
        // CENTER: Main knobs
        Expanded(flex: 3, child: _buildKnobs()),
        const SizedBox(width: 8),
        // RIGHT: Options
        SizedBox(width: 100, child: _buildOptions()),
      ],
    );
  }

  // ─── VERTICAL METERS (CustomPainter) ──────────────────────────────────

  Widget _buildMeters() {
    return SizedBox(
      width: 60,
      child: Container(
        decoration: FabFilterDecorations.display(),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildVerticalMeter('IN', _inputPeakL, _inputPeakR, FabFilterColors.blue),
            const SizedBox(width: 2),
            _buildVerticalMeter('OUT', _outputTpL, _outputTpR, FabFilterProcessorColors.limTruePeak),
            const SizedBox(width: 2),
            _buildGrMeter(),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalMeter(String label, double left, double right, Color color) {
    final maxDb = math.max(left, right);
    final normL = ((left + 60) / 60).clamp(0.0, 1.0);
    final normR = ((right + 60) / 60).clamp(0.0, 1.0);

    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(
            color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Container(
                  decoration: BoxDecoration(
                    color: FabFilterColors.bgVoid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: CustomPaint(
                    painter: _VerticalMeterPainter(value: normL, color: color),
                  ),
                )),
                const SizedBox(width: 1),
                Expanded(child: Container(
                  decoration: BoxDecoration(
                    color: FabFilterColors.bgVoid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: CustomPaint(
                    painter: _VerticalMeterPainter(value: normR, color: color),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            maxDb > -100 ? maxDb.toStringAsFixed(0) : '-∞',
            style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _buildGrMeter() {
    final grMax = math.max(_grLeft, _grRight);
    final grNorm = (grMax / 24).clamp(0.0, 1.0);

    return Expanded(
      child: Column(
        children: [
          Text('GR', style: TextStyle(
            color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: CustomPaint(
                painter: _VerticalMeterPainter(
                  value: grNorm,
                  color: FabFilterProcessorColors.limGainReduction,
                  fromTop: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '-${grMax.toStringAsFixed(0)}',
            style: TextStyle(
              color: FabFilterProcessorColors.limGainReduction, fontSize: 7,
              fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  // ─── KNOBS ────────────────────────────────────────────────────────────

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

  // ─── OPTIONS ──────────────────────────────────────────────────────────

  Widget _buildOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stereo link slider
        FabMiniSlider(
          label: 'LNK',
          value: _stereoLink / 100,
          display: '${_stereoLink.toStringAsFixed(0)}%',
          activeColor: FabFilterColors.purple,
          onChanged: (v) {
            setState(() => _stereoLink = v * 100);
            _setParam(_P.stereoLink, _stereoLink);
          },
        ),
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
}

// ═══════════════════════════════════════════════════════════════════════════
// VERTICAL METER PAINTER — gradient fills with glow edge line
// ═══════════════════════════════════════════════════════════════════════════

class _VerticalMeterPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool fromTop;

  _VerticalMeterPainter({
    required this.value, required this.color, this.fromTop = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (value <= 0.001) return;

    final barH = size.height * value;

    if (fromTop) {
      // GR meter — from top, warm gradient
      final rect = Rect.fromLTWH(0, 0, size.width, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..shader = ui.Gradient.linear(
          Offset.zero, Offset(0, barH),
          [
            color.withValues(alpha: 0.5),
            color,
          ],
        ),
      );
      // Glow line at bottom edge
      canvas.drawLine(
        Offset(0, barH), Offset(size.width, barH),
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    } else {
      // Level meter — from bottom, colored gradient
      final rect = Rect.fromLTWH(0, size.height - barH, size.width, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..shader = ui.Gradient.linear(
          Offset(0, size.height), Offset(0, size.height - barH),
          [
            color.withValues(alpha: 0.4),
            color,
          ],
        ),
      );
      // Glow line at top edge
      canvas.drawLine(
        Offset(0, size.height - barH), Offset(size.width, size.height - barH),
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalMeterPainter old) =>
      old.value != value || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// LIMITER DISPLAY PAINTER — Glass scrolling waveform + GR bars
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

    // ── Glass background gradient ──
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [const Color(0xFF0D0D12), const Color(0xFF08080C)],
      ));

    // ── Grid lines ──
    final thinPaint = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    final medPaint = Paint()..color = const Color(0xFF222230)..strokeWidth = 0.5;
    final dbOffset = meterScale.offset.toDouble();
    final totalRange = 48.0 + dbOffset.abs();

    for (var db = -48; db <= 0; db += 6) {
      final y = _dbToY(db.toDouble(), size.height, dbOffset, totalRange);
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(
          Offset(0, y), Offset(size.width, y),
          db % 12 == 0 ? medPaint : thinPaint,
        );
      }
    }

    // 0dB line
    final zeroY = _dbToY(0, size.height, dbOffset, totalRange);
    if (zeroY >= 0 && zeroY <= size.height) {
      canvas.drawLine(
        Offset(0, zeroY), Offset(size.width, zeroY),
        Paint()..color = const Color(0xFF2A2A38)..strokeWidth = 1,
      );
    }

    // ── Ceiling line — 2-layer glow ──
    final ceilingY = _dbToY(ceiling, size.height, dbOffset, totalRange);
    if (ceilingY >= 0 && ceilingY <= size.height) {
      // Outer glow
      canvas.drawLine(
        Offset(0, ceilingY), Offset(size.width, ceilingY),
        Paint()
          ..color = FabFilterProcessorColors.limAccent.withValues(alpha: 0.15)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      // Core line
      canvas.drawLine(
        Offset(0, ceilingY), Offset(size.width, ceilingY),
        Paint()
          ..color = FabFilterProcessorColors.limAccent.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
    }

    // ── Threshold line — dashed with glow ──
    final threshY = _dbToY(threshold, size.height, dbOffset, totalRange);
    if (threshY >= 0 && threshY <= size.height) {
      // Glow
      canvas.drawLine(
        Offset(0, threshY), Offset(size.width, threshY),
        Paint()
          ..color = FabFilterProcessorColors.limCeiling.withValues(alpha: 0.12)
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      // Core dashed
      _drawDashedLine(
        canvas,
        Offset(0, threshY), Offset(size.width, threshY),
        Paint()
          ..color = FabFilterProcessorColors.limCeiling.withValues(alpha: 0.4)
          ..strokeWidth = 1.0,
      );
    }

    if (history.isEmpty) return;

    final sampleWidth = size.width / _maxSamples;
    final startX = size.width - history.length * sampleWidth;

    // ── GR bars from top — per-bar gradient ──
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final gr = history[i].gainReduction.abs();
      final grHeight = (gr / 24).clamp(0.0, 1.0) * size.height * 0.4;
      if (grHeight > 0.5) {
        final barRect = Rect.fromLTWH(x, 0, sampleWidth + 0.5, grHeight);
        canvas.drawRect(barRect, Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, 0), Offset(x, grHeight),
            [
              FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.5),
              FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.12),
            ],
          ));
      }
    }

    // ── GR edge glow (2-layer: blur + core) ──
    final grEdge = Path();
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final grH = (history[i].gainReduction.abs() / 24).clamp(0.0, 1.0) * size.height * 0.4;
      i == 0 || x - sampleWidth < 0
          ? grEdge.moveTo(x, grH)
          : grEdge.lineTo(x, grH);
    }
    canvas.drawPath(grEdge, Paint()
      ..color = FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    canvas.drawPath(grEdge, Paint()
      ..color = FabFilterProcessorColors.limGainReduction
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke);

    // ── Input waveform fill (subtle gray gradient) ──
    final inPath = Path()..moveTo(
      math.max(startX, 0), size.height);
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final y = _dbToY(history[i].inputPeak, size.height, dbOffset, totalRange)
          .clamp(0.0, size.height);
      inPath.lineTo(x, y);
    }
    inPath.lineTo(startX + history.length * sampleWidth, size.height);
    inPath.close();
    canvas.drawPath(inPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height), Offset.zero,
        [
          const Color(0x08808088),
          const Color(0x20808088),
        ],
      ));

    // ── Output waveform fill (limiter accent gradient) ──
    final outPath = Path()..moveTo(
      math.max(startX, 0), size.height);
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final y = _dbToY(history[i].outputPeak, size.height, dbOffset, totalRange)
          .clamp(0.0, size.height);
      outPath.lineTo(x, y);
    }
    outPath.lineTo(startX + history.length * sampleWidth, size.height);
    outPath.close();
    canvas.drawPath(outPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height), Offset.zero,
        [
          FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.05),
          FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.3),
        ],
      ));

    // ── Output stroke line (thin colored) ──
    final outLine = Path();
    bool outStarted = false;
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sampleWidth;
      if (x < 0) continue;
      final y = _dbToY(history[i].outputPeak, size.height, dbOffset, totalRange)
          .clamp(0.0, size.height);
      if (!outStarted) {
        outLine.moveTo(x, y);
        outStarted = true;
      } else {
        outLine.lineTo(x, y);
      }
    }
    if (outStarted) {
      canvas.drawPath(outLine, Paint()
        ..color = FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // ── True peak clip markers (red rectangles) ──
    for (var i = 0; i < history.length; i++) {
      if (history[i].truePeak > ceiling + 0.1) {
        final x = startX + i * sampleWidth;
        if (x < 0) continue;
        final clipY = ceilingY.clamp(0.0, size.height);
        // Glow
        canvas.drawRect(
          Rect.fromLTWH(x - 0.5, clipY - 3, sampleWidth + 1, 6),
          Paint()
            ..color = FabFilterColors.red.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        // Core marker
        canvas.drawRect(
          Rect.fromLTWH(x, clipY - 2, sampleWidth + 0.5, 4),
          Paint()..color = FabFilterColors.red,
        );
      }
    }
  }

  static const int _maxSamples = 200;

  double _dbToY(double db, double height, double dbOffset, double totalRange) {
    return height * (1 - (db + 48 + dbOffset) / totalRange);
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
