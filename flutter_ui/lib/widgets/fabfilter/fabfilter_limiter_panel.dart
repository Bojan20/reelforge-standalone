/// FF-L Limiter Panel
///
/// Professional limiter interface:
/// - Real-time scrolling waveform display
/// - True Peak limiting/metering
/// - Loudness metering (LUFS - Integrated, Short-term, Momentary)
/// - 8 limiting styles
/// - Multiple meter scales (K-12, K-14, K-20)
/// - Compact view mode

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

/// Limiting style (8 styles)
enum LimitingStyle {
  transparent('Transparent', 'Clean and transparent limiting'),
  punchy('Punchy', 'Preserves transients and punch'),
  dynamic('Dynamic', 'Dynamic and musical limiting'),
  aggressive('Aggressive', 'Aggressive limiting for EDM'),
  bus('Bus', 'Bus/subgroup limiting'),
  safe('Safe', 'Safe mode for delicate material'),
  modern('Modern', 'Modern sound for contemporary music'),
  allround('Allround', 'Versatile general-purpose mode');

  final String label;
  final String description;
  const LimitingStyle(this.label, this.description);
}

/// Meter scale options
enum MeterScale {
  normal('0 dB', 0),
  k12('K-12', -12),
  k14('K-14', -14),
  k20('K-20', -20),
  loudness('LUFS', 0);

  final String label;
  final int offset;
  const MeterScale(this.label, this.offset);
}

/// LUFS reading types
enum LufsType {
  integrated('Int', 'Integrated loudness (program)'),
  shortTerm('Short', 'Short-term loudness (3s)'),
  momentary('Mom', 'Momentary loudness (400ms)');

  final String label;
  final String description;
  const LufsType(this.label, this.description);
}

/// Level sample for scrolling display
class LimiterLevelSample {
  final double inputPeak;
  final double outputPeak;
  final double gainReduction;
  final double truePeak;
  final DateTime timestamp;

  LimiterLevelSample({
    required this.inputPeak,
    required this.outputPeak,
    required this.gainReduction,
    required this.truePeak,
    required this.timestamp,
  });
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
  // ─────────────────────────────────────────────────────────────────────────
  // STATE — 14 DSP parameters (TruePeakLimiterWrapper indices)
  // ─────────────────────────────────────────────────────────────────────────

  // Param 0: Input Trim (-12..+12 dB)
  double _inputTrim = 0.0;
  // Param 1: Threshold (-30..0 dB)
  double _threshold = 0.0;
  // Param 2: Ceiling (-3..0 dBTP)
  double _output = -0.3;
  // Param 3: Release (1..1000 ms)
  double _release = 100.0;
  // Param 4: Attack (0.01..10 ms)
  double _attack = 0.1;
  // Param 5: Lookahead (0..20 ms)
  double _lookahead = 5.0;
  // Param 6: Style (0..7 enum)
  LimitingStyle _style = LimitingStyle.allround;
  // Param 7: Oversampling (0..5 enum)
  int _oversampling = 1; // 0=X1,1=X2,2=X4,3=X8
  // Param 8: Stereo Link (0..100 %)
  double _stereoLink = 100.0;
  // Param 9: M/S Mode (bool)
  bool _msMode = false;
  // Param 10: Mix (0..100 %)
  double _mix = 100.0;
  // Param 11: Dither Bits (0..4 enum)
  int _ditherBits = 0; // 0=Off,1=8,2=12,3=16,4=24
  // Param 12: Latency Profile (0..2 enum)
  int _latencyProfile = 1; // 0=ZeroLat,1=HQ,2=Offline
  // Param 13: Channel Config (0..2 enum)
  int _channelConfig = 0; // 0=Stereo,1=DualMono,2=MidSide

  // Metering
  MeterScale _meterScale = MeterScale.normal;

  // Display
  final List<LimiterLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 300;

  // Real-time meters (7 meters from TruePeakLimiterWrapper)
  double _grLeft = 0.0;        // Meter 0: GR Left (dB, positive when limiting)
  double _grRight = 0.0;       // Meter 1: GR Right (dB)
  double _inputPeakL = -60.0;  // Meter 2: Input Peak L (dB)
  double _inputPeakR = -60.0;  // Meter 3: Input Peak R (dB)
  double _outputTpL = -60.0;   // Meter 4: Output True Peak L (dBTP)
  double _outputTpR = -60.0;   // Meter 5: Output True Peak R (dBTP)
  double _grMaxHold = 0.0;     // Meter 6: GR Max Hold (dB)
  bool _truePeakClipping = false;

  // Animation
  late AnimationController _meterController;

  // FFI & DspChainProvider integration
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  String? _nodeId;
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);

    _meterController.repeat();
  }

  /// Initialize processor via DspChainProvider
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

  /// Read ALL 14 parameters from engine
  void _readParamsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId;
    final s = _slotIndex;
    setState(() {
      _inputTrim = _ffi.insertGetParam(t, s, 0);
      _threshold = _ffi.insertGetParam(t, s, 1);
      _output = _ffi.insertGetParam(t, s, 2);
      _release = _ffi.insertGetParam(t, s, 3);
      _attack = _ffi.insertGetParam(t, s, 4);
      _lookahead = _ffi.insertGetParam(t, s, 5);
      final styleIdx = _ffi.insertGetParam(t, s, 6).toInt().clamp(0, 7);
      _style = LimitingStyle.values[styleIdx];
      _oversampling = _ffi.insertGetParam(t, s, 7).toInt().clamp(0, 3);
      _stereoLink = _ffi.insertGetParam(t, s, 8);
      _msMode = _ffi.insertGetParam(t, s, 9) > 0.5;
      _mix = _ffi.insertGetParam(t, s, 10);
      _ditherBits = _ffi.insertGetParam(t, s, 11).toInt().clamp(0, 4);
      _latencyProfile = _ffi.insertGetParam(t, s, 12).toInt().clamp(0, 2);
      _channelConfig = _ffi.insertGetParam(t, s, 13).toInt().clamp(0, 2);
    });
  }

  /// Send a single parameter to engine
  void _setParam(int index, double value) {
    if (!_initialized || _slotIndex < 0) return;
    _ffi.insertSetParam(widget.trackId, _slotIndex, index, value);
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    super.dispose();
  }

  /// Read all 7 meters from the insert processor
  void _updateMeters() {
    if (!_initialized || _slotIndex < 0) return;
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
      } catch (_) {
        // Meter read failed, keep previous values
      }

      // True peak clipping: output exceeds ceiling
      final outTpMax = _outputTpL > _outputTpR ? _outputTpL : _outputTpR;
      _truePeakClipping = outTpMax > _output + 0.1;

      // GR for display: use max of L/R
      final grDisplay = _grLeft > _grRight ? _grLeft : _grRight;

      // Add to history for GR graph
      if (grDisplay > 0.01 || _levelHistory.isNotEmpty) {
        final inPeakMax = _inputPeakL > _inputPeakR ? _inputPeakL : _inputPeakR;
        _levelHistory.add(LimiterLevelSample(
          inputPeak: inPeakMax,
          outputPeak: outTpMax,
          gainReduction: grDisplay,
          truePeak: outTpMax,
          timestamp: DateTime.now(),
        ));

        while (_levelHistory.length > _maxHistorySamples) {
          _levelHistory.removeAt(0);
        }
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
          // Main content — horizontal layout, no scroll
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT: GR meter + LUFS display
                  _buildCompactMeters(),
                  const SizedBox(width: 12),
                  // CENTER: Main knobs
                  Expanded(
                    flex: 3,
                    child: _buildCompactControls(),
                  ),
                  const SizedBox(width: 12),
                  // RIGHT: Style + options
                  _buildCompactOptions(),
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(widget.icon, color: widget.accentColor, size: 14),
          const SizedBox(width: 6),
          Text(widget.title, style: FabFilterText.title.copyWith(fontSize: 11)),
          const SizedBox(width: 12),
          // Style dropdown
          _buildCompactStyleDropdown(),
          const Spacer(),
          // Oversampling indicator
          _buildCompactToggle('${_oversamplingLabel()}', _oversampling > 0, FabFilterColors.green, (_) {
            setState(() => _oversampling = (_oversampling + 1) % 4); // Cycle 0-3
            _setParam(7, _oversampling.toDouble());
          }),
          const SizedBox(width: 6),
          // A/B
          _buildCompactAB(),
          const SizedBox(width: 8),
          // Bypass
          _buildCompactBypass(),
        ],
      ),
    );
  }

  Widget _buildCompactStyleDropdown() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LimitingStyle>(
          value: _style,
          dropdownColor: FabFilterColors.bgDeep,
          style: FabFilterText.paramLabel.copyWith(fontSize: 10),
          icon: Icon(Icons.arrow_drop_down, size: 14, color: FabFilterColors.textMuted),
          isDense: true,
          items: LimitingStyle.values.map((s) => DropdownMenuItem(
            value: s,
            child: Text(s.label, style: const TextStyle(fontSize: 10)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _style = v);
              _setParam(6, v.index.toDouble());
            }
          },
        ),
      ),
    );
  }

  Widget _buildCompactToggle(String label, bool value, Color color, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: value ? color : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(color: value ? color : FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold)),
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

  Widget _buildCompactMeters() {
    return SizedBox(
      width: 120,
      child: Column(
        children: [
          // GR meter horizontal
          _buildHorizontalGRMeter(),
          const SizedBox(height: 6),
          // Input/Output peak meters
          Expanded(child: _buildCompactInputOutput()),
          const SizedBox(height: 6),
          // True peak indicator
          _buildCompactTruePeak(),
        ],
      ),
    );
  }

  Widget _buildHorizontalGRMeter() {
    final grMax = _grLeft > _grRight ? _grLeft : _grRight;
    final grNorm = (grMax / 24).clamp(0.0, 1.0);
    return Container(
      height: 20,
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Text('GR', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          const SizedBox(width: 4),
          Expanded(
            child: Stack(
              children: [
                Container(height: 12, decoration: BoxDecoration(color: FabFilterColors.bgVoid, borderRadius: BorderRadius.circular(2))),
                FractionallySizedBox(
                  widthFactor: grNorm,
                  child: Container(height: 12, decoration: BoxDecoration(color: FabFilterColors.red, borderRadius: BorderRadius.circular(2))),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(width: 28, child: Text('-${grMax.toStringAsFixed(1)}', style: FabFilterText.paramValue(FabFilterColors.red).copyWith(fontSize: 9), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildCompactInputOutput() {
    // Real input/output meters from DSP
    final inPeak = _inputPeakL > _inputPeakR ? _inputPeakL : _inputPeakR;
    final outTp = _outputTpL > _outputTpR ? _outputTpL : _outputTpR;
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildMeterRow('In L', _inputPeakL, FabFilterColors.blue),
          _buildMeterRow('In R', _inputPeakR, FabFilterColors.blue),
          const SizedBox(height: 2),
          _buildMeterRow('Out L', _outputTpL, FabFilterColors.cyan),
          _buildMeterRow('Out R', _outputTpR, FabFilterColors.cyan),
          const SizedBox(height: 2),
          _buildMeterRow('GR Max', -_grMaxHold, FabFilterColors.red, suffix: 'dB'),
        ],
      ),
    );
  }

  Widget _buildMeterRow(String label, double value, Color color, {String suffix = 'dB'}) {
    return Row(
      children: [
        SizedBox(width: 32, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
        Expanded(
          child: Text(
            value > -100 ? '${value.toStringAsFixed(1)} $suffix' : '-∞',
            style: FabFilterText.paramValue(color).copyWith(fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTruePeak() {
    final outTpMax = _outputTpL > _outputTpR ? _outputTpL : _outputTpR;
    return Container(
      height: 22,
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _truePeakClipping ? FabFilterColors.red : (outTpMax > _output - 0.5 ? FabFilterColors.orange : FabFilterColors.green),
            ),
          ),
          const SizedBox(width: 4),
          Text('TP', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          const Spacer(),
          Text(
            outTpMax > -100 ? '${outTpMax.toStringAsFixed(1)} dBTP' : '-∞',
            style: FabFilterText.paramValue(_truePeakClipping ? FabFilterColors.red : FabFilterColors.textSecondary).copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }

  String _oversamplingLabel() {
    switch (_oversampling) {
      case 0: return '1x';
      case 1: return '2x';
      case 2: return '4x';
      case 3: return '8x';
      default: return '${_oversampling}x';
    }
  }

  Widget _buildCompactControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Param 0: Input Trim (-12..+12 dB)
        _buildSmallKnob(
          value: (_inputTrim + 12) / 24,
          label: 'TRIM',
          display: '${_inputTrim >= 0 ? '+' : ''}${_inputTrim.toStringAsFixed(1)}dB',
          color: FabFilterColors.orange,
          onChanged: (v) {
            setState(() => _inputTrim = v * 24 - 12);
            _setParam(0, _inputTrim);
          },
        ),
        // Param 1: Threshold (-30..0 dB)
        _buildSmallKnob(
          value: (_threshold + 30) / 30,
          label: 'THRESH',
          display: '${_threshold.toStringAsFixed(1)}dB',
          color: FabFilterColors.red,
          onChanged: (v) {
            setState(() => _threshold = v * 30 - 30);
            _setParam(1, _threshold);
          },
        ),
        // Param 2: Ceiling (-3..0 dBTP)
        _buildSmallKnob(
          value: (_output + 3) / 3,
          label: 'CEILING',
          display: '${_output.toStringAsFixed(1)}dBTP',
          color: FabFilterColors.blue,
          onChanged: (v) {
            setState(() => _output = v * 3 - 3);
            _setParam(2, _output);
          },
        ),
        // Param 3: Release (1..1000 ms, logarithmic)
        _buildSmallKnob(
          value: math.log(_release.clamp(1, 1000) / 1) / math.log(1000),
          label: 'RELEASE',
          display: _release >= 100 ? '${(_release / 1000).toStringAsFixed(2)}s' : '${_release.toStringAsFixed(0)}ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _release = math.pow(1000, v).toDouble().clamp(1, 1000));
            _setParam(3, _release);
          },
        ),
        if (showExpertMode) ...[
          // Param 4: Attack (0.01..10 ms, logarithmic)
          _buildSmallKnob(
            value: math.log(_attack.clamp(0.01, 10) / 0.01) / math.log(10 / 0.01),
            label: 'ATTACK',
            display: _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)}µs' : '${_attack.toStringAsFixed(1)}ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _attack = (0.01 * math.pow(10 / 0.01, v)).clamp(0.01, 10));
              _setParam(4, _attack);
            },
          ),
          // Param 5: Lookahead (0..20 ms)
          _buildSmallKnob(
            value: _lookahead / 20,
            label: 'LOOK',
            display: '${_lookahead.toStringAsFixed(1)}ms',
            color: FabFilterColors.purple,
            onChanged: (v) {
              setState(() => _lookahead = v * 20);
              _setParam(5, _lookahead);
            },
          ),
          // Param 10: Mix (0..100 %)
          _buildSmallKnob(
            value: _mix / 100,
            label: 'MIX',
            display: '${_mix.toStringAsFixed(0)}%',
            color: FabFilterColors.green,
            onChanged: (v) {
              setState(() => _mix = v * 100);
              _setParam(10, _mix);
            },
          ),
        ],
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
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 48,
      onChanged: onChanged,
    );
  }

  Widget _buildCompactOptions() {
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Param 8: Stereo Link (0-100%)
          _buildLinkSlider(),
          const SizedBox(height: 4),
          // Param 9: M/S Mode
          _buildOptionRow('M/S', _msMode, (v) {
            setState(() => _msMode = v);
            _setParam(9, v ? 1.0 : 0.0);
          }),
          if (showExpertMode) ...[
            const SizedBox(height: 4),
            // Param 13: Channel Config (Stereo/Dual Mono/Mid-Side)
            _buildEnumSelector('CH', _channelConfig, const ['St', 'Dual', 'M/S'], (v) {
              setState(() => _channelConfig = v);
              _setParam(13, v.toDouble());
            }),
            const SizedBox(height: 4),
            // Param 12: Latency Profile (Zero-Lat/HQ/Offline)
            _buildEnumSelector('LAT', _latencyProfile, const ['Zero', 'HQ', 'Off'], (v) {
              setState(() => _latencyProfile = v);
              _setParam(12, v.toDouble());
            }),
            const SizedBox(height: 4),
            // Param 11: Dither Bits (Off/8/12/16/24)
            _buildEnumSelector('DTH', _ditherBits, const ['Off', '8', '12', '16', '24'], (v) {
              setState(() => _ditherBits = v);
              _setParam(11, v.toDouble());
            }),
          ],
          const Flexible(child: SizedBox(height: 8)),
          // Meter scale
          Container(
            padding: const EdgeInsets.all(4),
            decoration: FabFilterDecorations.display(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SCALE', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: MeterScale.values.take(4).map((s) => _buildTinyButton(
                    s.label.replaceAll(' dB', '').replaceAll('K-', ''),
                    _meterScale == s,
                    FabFilterColors.blue,
                    () => setState(() => _meterScale = s),
                  )).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Stereo link slider (param 8: 0-100%)
  Widget _buildLinkSlider() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: Row(
        children: [
          Text('LNK', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: FabFilterColors.purple,
                inactiveTrackColor: FabFilterColors.bgVoid,
                thumbColor: FabFilterColors.purple,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: _stereoLink,
                min: 0,
                max: 100,
                onChanged: (v) {
                  setState(() => _stereoLink = v);
                  _setParam(8, v);
                },
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: Text('${_stereoLink.toStringAsFixed(0)}', style: FabFilterText.paramValue(FabFilterColors.purple).copyWith(fontSize: 8), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  /// Enum selector (tiny button row)
  Widget _buildEnumSelector(String label, int value, List<String> options, ValueChanged<int> onChanged) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
          const SizedBox(width: 2),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(options.length, (i) => _buildTinyButton(
                options[i],
                value == i,
                FabFilterColors.cyan,
                () => onChanged(i),
              )),
            ),
          ),
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

  Widget _buildTinyButton(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 16,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : FabFilterColors.border),
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? color : FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.bold))),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// LIMITER DISPLAY PAINTER (Scrolling waveform)
// ═══════════════════════════════════════════════════════════════════════════

class _LimiterDisplayPainter extends CustomPainter {
  final List<LimiterLevelSample> history;
  final double ceiling;
  final MeterScale meterScale;

  _LimiterDisplayPainter({
    required this.history,
    required this.ceiling,
    required this.meterScale,
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

    // Horizontal grid lines
    final dbOffset = meterScale.offset.toDouble();
    for (var db = -48; db <= 0; db += 6) {
      final y = size.height * (1 - (db + 48 + dbOffset) / (48 + dbOffset));
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

        // Label
        _drawLabel(
          canvas,
          '${db}dB',
          Offset(4, y - 6),
          FabFilterColors.textMuted,
        );
      }
    }

    // Ceiling line
    final ceilingY = size.height * (1 - (ceiling + 48 + dbOffset) / (48 + dbOffset));
    final ceilingPaint = Paint()
      ..color = FabFilterColors.red
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, ceilingY),
      Offset(size.width, ceilingY),
      ceilingPaint,
    );

    if (history.isEmpty) return;

    final sampleWidth = size.width / history.length;

    // Input level (gray, background)
    _drawLevelPath(
      canvas,
      size,
      history.map((s) => s.inputPeak).toList(),
      FabFilterColors.textMuted.withValues(alpha: 0.3),
      dbOffset,
    );

    // Output level (blue, foreground)
    _drawLevelPath(
      canvas,
      size,
      history.map((s) => s.outputPeak).toList(),
      FabFilterColors.blue.withValues(alpha: 0.6),
      dbOffset,
    );

    // Gain reduction (red, from top)
    final grPaint = Paint()
      ..color = FabFilterColors.red.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final gr = history[i].gainReduction.abs();
      final grHeight = (gr / 24).clamp(0.0, 1.0) * size.height * 0.5;

      canvas.drawRect(
        Rect.fromLTWH(x, 0, sampleWidth + 1, grHeight),
        grPaint,
      );
    }

    // True peak clipping indicators
    for (var i = 0; i < history.length; i++) {
      if (history[i].truePeak > ceiling) {
        final x = i * sampleWidth;
        canvas.drawRect(
          Rect.fromLTWH(x, ceilingY - 2, sampleWidth + 1, 4),
          Paint()..color = FabFilterColors.red,
        );
      }
    }

    // Ceiling label
    _drawLabel(
      canvas,
      '${ceiling.toStringAsFixed(1)}dB',
      Offset(size.width - 50, ceilingY - 12),
      FabFilterColors.red,
    );
  }

  void _drawLevelPath(
    Canvas canvas,
    Size size,
    List<double> levels,
    Color color,
    double dbOffset,
  ) {
    final path = Path();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sampleWidth = size.width / levels.length;

    path.moveTo(0, size.height);

    for (var i = 0; i < levels.length; i++) {
      final x = i * sampleWidth;
      final level = levels[i];
      final normalizedLevel =
          ((level + 48 + dbOffset) / (48 + dbOffset)).clamp(0.0, 1.0);
      final y = size.height * (1 - normalizedLevel);

      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _LimiterDisplayPainter oldDelegate) => true;
}
