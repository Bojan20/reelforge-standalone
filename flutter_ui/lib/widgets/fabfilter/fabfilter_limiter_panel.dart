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
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  // Main parameters
  double _gain = 0.0; // dB (input gain/drive) - boosts signal into limiter
  double _output = -0.3; // dB (output ceiling)
  double _threshold = -10.0; // dB (limiting threshold, separate from ceiling)
  double _attack = 1.0; // ms (0.01 - 10)
  double _release = 100.0; // ms (1 - 1000)
  double _lookahead = 2.0; // ms (0 - 10)

  // Style
  LimitingStyle _style = LimitingStyle.transparent;

  // Metering
  MeterScale _meterScale = MeterScale.normal;
  bool _truePeakEnabled = true;

  // Display
  bool _compactView = false;
  final List<LimiterLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 300;

  // Real-time meters
  double _currentInputPeak = -60.0;
  double _currentOutputPeak = -60.0;
  double _currentGainReduction = 0.0;
  double _peakGainReduction = 0.0;
  double _currentTruePeak = -60.0;
  bool _truePeakClipping = false;

  // LUFS
  double _lufsIntegrated = -14.0;
  double _lufsShortTerm = -14.0;
  double _lufsMomentary = -12.0;
  double _lufsRange = 6.0; // LRA

  // Animation
  late AnimationController _meterController;

  // Link channels (L/R)
  bool _channelLink = true;

  // Unity gain (auto)
  bool _unityGain = false;

  // FFI & DspChainProvider integration
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  // DspChainProvider tracking (FIX: Use insert chain, not ghost DYNAMICS_LIMITERS)
  String? _nodeId;
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();

    // Initialize FFI limiter
    _initializeProcessor();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);

    _meterController.repeat();
  }

  /// Initialize processor via DspChainProvider (FIX: Uses insert chain, not ghost HashMap)
  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Find existing limiter node or add one
    DspNode? limiterNode;
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.limiter) {
        limiterNode = node;
        break;
      }
    }

    if (limiterNode == null) {
      // Add limiter via DspChainProvider (this calls insertLoadProcessor → insert chain)
      dsp.addNode(widget.trackId, DspNodeType.limiter);
      final updatedChain = dsp.getChain(widget.trackId);
      if (updatedChain.nodes.isNotEmpty) {
        limiterNode = updatedChain.nodes.last;
      }
    }

    if (limiterNode != null) {
      _nodeId = limiterNode.id;
      _slotIndex = dsp.getChain(widget.trackId).nodes.indexWhere((n) => n.id == _nodeId);
      _initialized = true;
      _applyAllParameters();
    } else {
    }
  }

  /// Apply all parameters to the insert chain limiter (FIX: Uses insertSetParam)
  ///
  /// Parameter indices for TruePeakLimiterWrapper in insert chain:
  /// 0: Threshold (dB) - level at which limiting begins
  /// 1: Ceiling (dB) - maximum output level
  /// 2: Release (ms)
  /// 3: Oversampling (0=X1, 1=X2, 2=X4, 3+=X8)
  void _applyAllParameters() {
    if (!_initialized || _slotIndex < 0) return;

    // Use insertSetParam to set parameters on the REAL insert chain processor
    // FIX: Use separate threshold and ceiling values
    // Threshold should be lower than ceiling for limiting to engage
    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);  // Threshold
    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _output);     // Ceiling
    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _release);    // Release
    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _truePeakEnabled ? 3.0 : 0.0); // Oversampling (8x when true peak, 1x otherwise)
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    // NOTE: Don't remove the limiter from DspChainProvider on dispose
    // The node lifecycle is managed by DspChainProvider, not by this panel.
    super.dispose();
  }

  void _updateMeters() {
    setState(() {
      // Get gain reduction from channel strip limiter (track 0 = master)
      // This returns GR in dB (negative values when limiting)
      try {
        _currentGainReduction = _ffi.channelStripGetLimiterGr(widget.trackId);
      } catch (_) {
        _currentGainReduction = 0.0;
      }

      // Get true peak from advanced meters (8x oversampled)
      try {
        final truePeakData = _ffi.advancedGetTruePeak8x();
        _currentTruePeak = truePeakData.maxDbtp;
      } catch (_) {
        _currentTruePeak = -60.0;
      }

      // Get peak levels from engine (master bus)
      // NOTE: For insert chain processors, we'd need per-slot metering
      // For now, use master bus peak levels as proxy
      try {
        final (peakL, peakR) = _ffi.getPeakMeters();
        // Convert linear to dB
        final peakMax = peakL > peakR ? peakL : peakR;
        _currentOutputPeak = peakMax > 1e-10 ? 20.0 * math.log(peakMax) / math.ln10 : -60.0;
        // Input is approximated as output + GR (inverse of limiting)
        _currentInputPeak = _currentOutputPeak - _currentGainReduction;
      } catch (_) {
        _currentInputPeak = -60.0;
        _currentOutputPeak = -60.0;
      }

      // True peak clipping detection (-0.1 dBTP threshold)
      _truePeakClipping = _currentTruePeak > -0.1;

      // Track peak GR (most negative value)
      if (_currentGainReduction.abs() > 0.01 && _currentGainReduction.abs() > _peakGainReduction.abs()) {
        _peakGainReduction = _currentGainReduction;
      }

      // Add to history for GR graph
      if (_currentGainReduction.abs() > 0.01 || _levelHistory.isNotEmpty) {
        _levelHistory.add(LimiterLevelSample(
          inputPeak: _currentInputPeak,
          outputPeak: _currentOutputPeak,
          gainReduction: _currentGainReduction,
          truePeak: _currentTruePeak,
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
          // True peak toggle
          _buildCompactToggle('TP', _truePeakEnabled, FabFilterColors.green, (v) {
            setState(() => _truePeakEnabled = v);
            if (_slotIndex >= 0) _ffi.insertSetParam(widget.trackId, _slotIndex, 3, v ? 3.0 : 0.0);
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
          onChanged: (v) => v != null ? setState(() => _style = v) : null,
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
          // LUFS display compact
          Expanded(child: _buildCompactLufs()),
          const SizedBox(height: 6),
          // True peak indicator
          _buildCompactTruePeak(),
        ],
      ),
    );
  }

  Widget _buildHorizontalGRMeter() {
    final grNorm = (_currentGainReduction.abs() / 24).clamp(0.0, 1.0);
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
          SizedBox(width: 28, child: Text('${_currentGainReduction.toStringAsFixed(1)}', style: FabFilterText.paramValue(FabFilterColors.red).copyWith(fontSize: 9), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildCompactLufs() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLufsRow('Int', _lufsIntegrated, FabFilterColors.blue),
          _buildLufsRow('Short', _lufsShortTerm, FabFilterColors.cyan),
          _buildLufsRow('Mom', _lufsMomentary, FabFilterColors.green),
          _buildLufsRow('LRA', _lufsRange, FabFilterColors.purple, suffix: 'LU'),
        ],
      ),
    );
  }

  Widget _buildLufsRow(String label, double value, Color color, {String suffix = 'LUFS'}) {
    return Row(
      children: [
        SizedBox(width: 32, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
        Expanded(
          child: Text(
            '${value.toStringAsFixed(1)} $suffix',
            style: FabFilterText.paramValue(color).copyWith(fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTruePeak() {
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
              color: _truePeakClipping ? FabFilterColors.red : (_currentTruePeak > _output - 0.5 ? FabFilterColors.orange : FabFilterColors.green),
            ),
          ),
          const SizedBox(width: 4),
          Text('TP', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          const Spacer(),
          Text(
            _currentTruePeak > -60 ? '${_currentTruePeak.toStringAsFixed(1)} dB' : '-∞',
            style: FabFilterText.paramValue(_truePeakClipping ? FabFilterColors.red : FabFilterColors.textSecondary).copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSmallKnob(
          value: (_gain + 24) / 48,
          label: 'GAIN',
          display: '${_gain >= 0 ? '+' : ''}${_gain.toStringAsFixed(0)}dB',
          color: FabFilterColors.orange,
          onChanged: (v) => setState(() => _gain = v * 48 - 24),
          // NOTE: Gain/drive is UI-only for now, doesn't map to insert chain limiter
        ),
        // THRESHOLD: Level at which limiting begins (FIX: separate from ceiling)
        _buildSmallKnob(
          value: (_threshold + 24) / 24, // Range: -24 to 0 dB
          label: 'THRESH',
          display: '${_threshold.toStringAsFixed(1)}dB',
          color: FabFilterColors.red,
          onChanged: (v) {
            setState(() => _threshold = v * 24 - 24);
            if (_slotIndex >= 0) {
              _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold); // Threshold
            }
          },
        ),
        // OUTPUT/CEILING: Maximum output level
        _buildSmallKnob(
          value: (_output + 12) / 12, // Range: -12 to 0 dB
          label: 'CEILING',
          display: '${_output.toStringAsFixed(1)}dB',
          color: FabFilterColors.blue,
          onChanged: (v) {
            setState(() => _output = v * 12 - 12);
            if (_slotIndex >= 0) {
              _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _output); // Ceiling only
            }
          },
        ),
        _buildSmallKnob(
          value: math.log(_release / 1) / math.log(1000 / 1),
          label: 'RELEASE',
          display: _release >= 100 ? '${(_release / 1000).toStringAsFixed(1)}s' : '${_release.toStringAsFixed(0)}ms',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _release = 1 * math.pow(1000 / 1, v).toDouble());
            if (_slotIndex >= 0) {
              _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _release); // Release
            }
          },
        ),
        if (showExpertMode) ...[
          _buildSmallKnob(
            value: math.log(_attack / 0.01) / math.log(10 / 0.01),
            label: 'ATTACK',
            display: _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)}µ' : '${_attack.toStringAsFixed(1)}ms',
            color: FabFilterColors.cyan,
            onChanged: (v) => setState(() => _attack = 0.01 * math.pow(10 / 0.01, v).toDouble()),
            // NOTE: Attack is UI-only, insert chain limiter doesn't expose attack
          ),
          _buildSmallKnob(
            value: _lookahead / 10,
            label: 'LOOK',
            display: '${_lookahead.toStringAsFixed(1)}ms',
            color: FabFilterColors.purple,
            onChanged: (v) => setState(() => _lookahead = v * 10),
            // NOTE: Lookahead is UI-only for now
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
      width: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOptionRow('Link', _channelLink, (v) => setState(() => _channelLink = v)),
          const SizedBox(height: 4),
          _buildOptionRow('Unity', _unityGain, (v) => setState(() => _unityGain = v)),
          const Flexible(child: SizedBox(height: 8)), // Flexible gap - can shrink to 0
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
