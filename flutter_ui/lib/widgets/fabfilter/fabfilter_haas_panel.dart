/// FF-H Haas Delay Panel — Precedence Effect Stereo Widener
///
/// Professional Haas delay processor for psychoacoustic stereo widening:
/// - Delay time knob (0.1–30ms) with sub-ms precision
/// - Channel selector (Left / Right delayed channel)
/// - Low-pass filter on delayed signal (200–18000 Hz)
/// - Feedback loop (0–70%)
/// - Phase invert toggle
/// - Wet/dry mix knob
/// - A/B comparison with full state snapshots

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARAMETER INDICES (must match Rust HaasDelayWrapper)
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const delayMs = 0;
  static const channel = 1; // 0.0=Left, 1.0=Right
  static const mix = 2;
  static const lpEnabled = 3;
  static const lpFrequency = 4;
  static const feedback = 5;
  static const phaseInvert = 6;
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class HaasSnapshot implements DspParameterSnapshot {
  final double delayMs, mix, lpFrequency, feedback;
  final bool channelRight, lpEnabled, phaseInvert;

  const HaasSnapshot({
    required this.delayMs,
    required this.mix,
    required this.lpFrequency,
    required this.feedback,
    required this.channelRight,
    required this.lpEnabled,
    required this.phaseInvert,
  });

  @override
  HaasSnapshot copy() => HaasSnapshot(
        delayMs: delayMs,
        mix: mix,
        lpFrequency: lpFrequency,
        feedback: feedback,
        channelRight: channelRight,
        lpEnabled: lpEnabled,
        phaseInvert: phaseInvert,
      );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! HaasSnapshot) return false;
    return delayMs == other.delayMs &&
        mix == other.mix &&
        lpFrequency == other.lpFrequency &&
        feedback == other.feedback &&
        channelRight == other.channelRight &&
        lpEnabled == other.lpEnabled &&
        phaseInvert == other.phaseInvert;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterHaasPanel extends FabFilterPanelBase {
  const FabFilterHaasPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-H',
          icon: Icons.spatial_audio_off,
          accentColor: FabFilterColors.green,
          nodeType: DspNodeType.haasDelay,
        );

  @override
  State<FabFilterHaasPanel> createState() => _FabFilterHaasPanelState();
}

class _FabFilterHaasPanelState extends State<FabFilterHaasPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─── DSP PARAMETERS ──────────────────────────────────────────────────
  double _delayMs = 8.0;
  bool _channelRight = true; // true = Right delayed
  double _mix = 1.0;
  bool _lpEnabled = true;
  double _lpFrequency = 8000.0;
  double _feedback = 0.0;
  bool _phaseInvert = false;

  // ─── METERING ────────────────────────────────────────────────────────
  double _inPeakL = 0.0;
  double _inPeakR = 0.0;
  double _outPeakL = 0.0;
  double _outPeakR = 0.0;

  // ─── ENGINE ──────────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ─────────────────────────────────────────────────────────────
  HaasSnapshot? _snapshotA;
  HaasSnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  // ─── LIFECYCLE ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
    initBypassFromProvider();
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33),
    )..addListener(_updateMeters);
    _meterController.repeat();
  }

  @override
  void dispose() {
    _meterController.dispose();
    super.dispose();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.haasDelay) {
        _nodeId = node.id;
        _slotIndex = chain.nodes.indexWhere((n) => n.id == _nodeId);
        _initialized = true;
        _readParams();
        break;
      }
    }
  }

  void _readParams() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId, s = _slotIndex;
    setState(() {
      _delayMs = _ffi.insertGetParam(t, s, _P.delayMs);
      _channelRight = _ffi.insertGetParam(t, s, _P.channel) > 0.5;
      _mix = _ffi.insertGetParam(t, s, _P.mix);
      _lpEnabled = _ffi.insertGetParam(t, s, _P.lpEnabled) > 0.5;
      _lpFrequency = _ffi.insertGetParam(t, s, _P.lpFrequency);
      _feedback = _ffi.insertGetParam(t, s, _P.feedback);
      _phaseInvert = _ffi.insertGetParam(t, s, _P.phaseInvert) > 0.5;
    });
  }

  void _setParam(int idx, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, idx, value);
    }
  }

  void _updateMeters() {
    if (!mounted || !_initialized) return;
    try {
      final meter = _ffi.getTrackMeter(widget.trackId);
      setState(() {
        _outPeakL = meter.peakL;
        _outPeakR = meter.peakR;
        _inPeakL = meter.rmsL;
        _inPeakR = meter.rmsR;
      });
    } catch (_) {}
  }

  // ─── A/B SNAPSHOT (FabFilterPanelMixin pattern) ─────────────────────

  HaasSnapshot _snap() => HaasSnapshot(
        delayMs: _delayMs,
        mix: _mix,
        lpFrequency: _lpFrequency,
        feedback: _feedback,
        channelRight: _channelRight,
        lpEnabled: _lpEnabled,
        phaseInvert: _phaseInvert,
      );

  void _restore(HaasSnapshot? s) {
    if (s == null) return;
    setState(() {
      _delayMs = s.delayMs;
      _mix = s.mix;
      _lpFrequency = s.lpFrequency;
      _feedback = s.feedback;
      _channelRight = s.channelRight;
      _lpEnabled = s.lpEnabled;
      _phaseInvert = s.phaseInvert;
    });
    _setParam(_P.delayMs, _delayMs);
    _setParam(_P.channel, _channelRight ? 1.0 : 0.0);
    _setParam(_P.mix, _mix);
    _setParam(_P.lpEnabled, _lpEnabled ? 1.0 : 0.0);
    _setParam(_P.lpFrequency, _lpFrequency);
    _setParam(_P.feedback, _feedback);
    _setParam(_P.phaseInvert, _phaseInvert ? 1.0 : 0.0);
  }

  @override
  void storeStateA() => _snapshotA = _snap();

  @override
  void storeStateB() => _snapshotB = _snap();

  @override
  void restoreStateA() => _restore(_snapshotA);

  @override
  void restoreStateB() => _restore(_snapshotB);

  @override
  void copyAToB() => _snapshotB = _snapshotA?.copy();

  @override
  void copyBToA() => _snapshotA = _snapshotB?.copy();

  // ─── NORMALIZATION HELPERS ──────────────────────────────────────────

  /// Log normalization for frequency-type knobs
  double _logNorm(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;
    return (math.log(value) - math.log(min)) /
        (math.log(max) - math.log(min));
  }

  double _logDenorm(double norm, double min, double max) {
    return min * math.pow(max / min, norm.clamp(0.0, 1.0));
  }

  /// Linear normalization
  double _linNorm(double value, double min, double max) {
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  double _linDenorm(double norm, double min, double max) {
    return min + norm.clamp(0.0, 1.0) * (max - min);
  }

  // ─── BUILD ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(
      Column(
        children: [
          // Header with title, bypass, A/B
          _buildHeader(),

          // Haas delay visualization
          Expanded(
            child: Container(
              color: FabFilterColors.bgDeep,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Delay visualization
                  _buildDelayVisualization(),
                  const SizedBox(height: 12),
                  // Main knobs row
                  _buildMainKnobs(),
                  const Flexible(child: SizedBox(height: 8)),
                  // Filter + toggles row
                  _buildFilterRow(),
                  const Flexible(child: SizedBox(height: 8)),
                  // I/O meters
                  _buildMeters(),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 32,
      color: FabFilterColors.bgMid,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.spatial_audio_off, size: 14, color: FabFilterColors.green),
          const SizedBox(width: 6),
          Text('FF-H  Haas Delay',
              style: TextStyle(
                  color: FabFilterColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          FabCompactAB(
            isStateB: isStateB,
            onToggle: toggleAB,
            accentColor: FabFilterColors.green,
          ),
          const SizedBox(width: 4),
          FabCompactBypass(
            bypassed: bypassed,
            onToggle: toggleBypass,
          ),
        ],
      ),
    );
  }

  // ─── DELAY VISUALIZATION ─────────────────────────────────────────────

  Widget _buildDelayVisualization() {
    return SizedBox(
      height: 80,
      child: CustomPaint(
        painter: _HaasVisualizationPainter(
          delayMs: _delayMs,
          channelRight: _channelRight,
          mix: _mix,
          phaseInvert: _phaseInvert,
          feedback: _feedback,
          accent: FabFilterColors.green,
        ),
        size: const Size(double.infinity, 80),
      ),
    );
  }

  // ─── MAIN KNOBS ──────────────────────────────────────────────────────

  Widget _buildMainKnobs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Delay time (0.1–30ms, log scale)
          FabFilterKnob(
            value: _logNorm(_delayMs, 0.1, 30.0),
            label: 'DELAY',
            display: _delayMs < 1.0
                ? '${(_delayMs * 1000).round()}µs'
                : '${_delayMs.toStringAsFixed(1)}ms',
            color: FabFilterColors.green,
            size: 52,
            defaultValue: _logNorm(8.0, 0.1, 30.0),
            onChanged: (norm) {
              final v = _logDenorm(norm, 0.1, 30.0);
              setState(() => _delayMs = v);
              _setParam(_P.delayMs, v);
            },
          ),

          // Mix (0–100%)
          FabFilterKnob(
            value: _mix,
            label: 'MIX',
            display: '${(_mix * 100).round()}%',
            color: FabFilterColors.green,
            size: 52,
            defaultValue: 1.0,
            onChanged: (v) {
              setState(() => _mix = v);
              _setParam(_P.mix, v);
            },
          ),

          // Feedback (0–70%)
          FabFilterKnob(
            value: _linNorm(_feedback, 0.0, 0.7),
            label: 'FEEDBACK',
            display: '${(_feedback * 100).round()}%',
            color: FabFilterColors.green,
            size: 52,
            defaultValue: 0.0,
            onChanged: (norm) {
              final v = _linDenorm(norm, 0.0, 0.7);
              setState(() => _feedback = v);
              _setParam(_P.feedback, v);
            },
          ),
        ],
      ),
    );
  }

  // ─── FILTER ROW ──────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Channel selector (L/R)
          _buildChannelSelector(),
          const SizedBox(width: 16),

          // LP Filter
          Expanded(child: _buildLpFilter()),
          const SizedBox(width: 16),

          // Phase invert toggle
          _buildPhaseToggle(),
        ],
      ),
    );
  }

  Widget _buildChannelSelector() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('DELAYED CH',
            style: TextStyle(
                color: FabFilterColors.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FabTinyButton(
              label: 'L',
              active: !_channelRight,
              color: FabFilterColors.green,
              onTap: () {
                setState(() => _channelRight = false);
                _setParam(_P.channel, 0.0);
              },
            ),
            const SizedBox(width: 2),
            FabTinyButton(
              label: 'R',
              active: _channelRight,
              color: FabFilterColors.green,
              onTap: () {
                setState(() => _channelRight = true);
                _setParam(_P.channel, 1.0);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLpFilter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FabTinyButton(
              label: 'LP',
              active: _lpEnabled,
              color: FabFilterColors.green,
              onTap: () {
                setState(() => _lpEnabled = !_lpEnabled);
                _setParam(_P.lpEnabled, _lpEnabled ? 1.0 : 0.0);
              },
            ),
            const SizedBox(width: 6),
            Text('FILTER',
                style: TextStyle(
                    color: FabFilterColors.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 140,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor:
                  _lpEnabled ? FabFilterColors.green : FabFilterColors.textTertiary,
              inactiveTrackColor: FabFilterColors.bgMid,
              thumbColor:
                  _lpEnabled ? FabFilterColors.green : FabFilterColors.textTertiary,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _lpFrequency,
              min: 200,
              max: 18000,
              onChanged: _lpEnabled
                  ? (v) {
                      setState(() => _lpFrequency = v);
                      _setParam(_P.lpFrequency, v);
                    }
                  : null,
            ),
          ),
        ),
        Text(
          _lpEnabled ? _formatFreq(_lpFrequency) : 'OFF',
          style: TextStyle(
              color: FabFilterColors.textPrimary,
              fontSize: 10,
              fontFamily: 'JetBrains Mono'),
        ),
      ],
    );
  }

  Widget _buildPhaseToggle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('PHASE',
            style: TextStyle(
                color: FabFilterColors.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
        const SizedBox(height: 4),
        FabTinyButton(
          label: 'Ø',
          active: _phaseInvert,
          color: const Color(0xFFFF6060),
          onTap: () {
            setState(() => _phaseInvert = !_phaseInvert);
            _setParam(_P.phaseInvert, _phaseInvert ? 1.0 : 0.0);
          },
        ),
      ],
    );
  }

  // ─── METERS ──────────────────────────────────────────────────────────

  Widget _buildMeters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildMeterPair('IN', _inPeakL, _inPeakR),
          const Spacer(),
          _buildMeterPair('OUT', _outPeakL, _outPeakR),
        ],
      ),
    );
  }

  Widget _buildMeterPair(String label, double peakL, double peakR) {
    double toDb(double linear) =>
        linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;
    final dbL = toDb(peakL).clamp(-60.0, 6.0);
    final dbR = toDb(peakR).clamp(-60.0, 6.0);
    final normL = ((dbL + 60) / 66).clamp(0.0, 1.0);
    final normR = ((dbR + 60) / 66).clamp(0.0, 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: FabFilterColors.textTertiary,
                fontSize: 8,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        _buildMeterBar(normL),
        const SizedBox(width: 1),
        _buildMeterBar(normR),
      ],
    );
  }

  Widget _buildMeterBar(double value) {
    return Container(
      width: 3,
      height: 24,
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: value,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [FabFilterColors.green, FabFilterColors.yellow],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────

  String _formatFreq(double hz) {
    if (hz >= 1000) {
      return '${(hz / 1000).toStringAsFixed(1)}kHz';
    }
    return '${hz.round()}Hz';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HAAS VISUALIZATION PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _HaasVisualizationPainter extends CustomPainter {
  final double delayMs;
  final bool channelRight;
  final double mix;
  final bool phaseInvert;
  final double feedback;
  final Color accent;

  _HaasVisualizationPainter({
    required this.delayMs,
    required this.channelRight,
    required this.mix,
    required this.phaseInvert,
    required this.feedback,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;

    // Background grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, midY), Offset(w, midY), gridPaint);

    // Direct signal (dry) — left side impulse
    final directX = w * 0.15;
    final directPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final directAmplitude = h * 0.35;
    // Draw dry channel
    final dryY = channelRight ? midY - h * 0.25 : midY + h * 0.25;
    canvas.drawLine(
      Offset(directX, dryY),
      Offset(directX, dryY - directAmplitude),
      directPaint,
    );
    // Label
    final dryLabel = channelRight ? 'L' : 'R';
    final tp = TextPainter(
      text: TextSpan(
          text: dryLabel,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9,
              fontFamily: 'JetBrains Mono')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(directX - 3, dryY + 4));

    // Delayed signal — offset by delay time
    final maxDelayPx = w * 0.6;
    final delayNorm = (delayMs / 30.0).clamp(0.0, 1.0);
    final delayedX = directX + 20 + delayNorm * maxDelayPx;

    final delayedPaint = Paint()
      ..color = accent.withValues(alpha: mix.clamp(0.2, 1.0))
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final delayedAmplitude =
        directAmplitude * mix * (phaseInvert ? -1.0 : 1.0);
    final wetY = channelRight ? midY + h * 0.25 : midY - h * 0.25;
    canvas.drawLine(
      Offset(delayedX, wetY),
      Offset(delayedX, wetY - delayedAmplitude),
      delayedPaint,
    );

    // Delay label
    final wetLabel = channelRight ? 'R' : 'L';
    final tp2 = TextPainter(
      text: TextSpan(
          text: wetLabel,
          style: TextStyle(
              color: accent.withValues(alpha: 0.7),
              fontSize: 9,
              fontFamily: 'JetBrains Mono')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(delayedX - 3, wetY + 4));

    // Delay time arrow
    final arrowPaint = Paint()
      ..color = accent.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final arrowY = midY;
    canvas.drawLine(
        Offset(directX, arrowY), Offset(delayedX, arrowY), arrowPaint);

    // Delay ms label
    final delayLabel = '${delayMs.toStringAsFixed(1)}ms';
    final tp3 = TextPainter(
      text: TextSpan(
          text: delayLabel,
          style: TextStyle(
              color: accent.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp3.paint(
        canvas, Offset((directX + delayedX) / 2 - tp3.width / 2, midY - 14));

    // Feedback echo (if > 0)
    if (feedback > 0.01) {
      final fbAmplitude = delayedAmplitude * feedback;
      final fbX = delayedX + (delayedX - directX) * 0.7;
      if (fbX < w - 10) {
        final fbPaint = Paint()
          ..color = accent.withValues(alpha: feedback * 0.5)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(fbX, wetY),
          Offset(fbX, wetY - fbAmplitude),
          fbPaint,
        );
      }
    }

    // Phase invert indicator
    if (phaseInvert) {
      final phiPaint = Paint()
        ..color = const Color(0xFFFF6060).withValues(alpha: 0.6)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(delayedX - 6, wetY - 2),
        Offset(delayedX + 6, wetY + 2),
        phiPaint,
      );
      canvas.drawLine(
        Offset(delayedX - 6, wetY + 2),
        Offset(delayedX + 6, wetY - 2),
        phiPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HaasVisualizationPainter oldDelegate) =>
      delayMs != oldDelegate.delayMs ||
      channelRight != oldDelegate.channelRight ||
      mix != oldDelegate.mix ||
      phaseInvert != oldDelegate.phaseInvert ||
      feedback != oldDelegate.feedback;
}
