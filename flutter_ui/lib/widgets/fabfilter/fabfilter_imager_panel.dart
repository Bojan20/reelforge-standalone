/// FF-IMG Stereo Imager Panel — Professional Stereo Field Processor
///
/// iZotope Ozone-class stereo imaging with:
/// - Width control (mono → stereo → wide)
/// - Pan + Pan Law (Linear / Constant Power / Compromise / No Center Atten.)
/// - L/R Balance
/// - Mid/Side gain (independent M and S level control)
/// - Stereo Rotation (0–360 degrees)
/// - Per-module enable toggles
/// - Vectorscope-style stereo field visualization
/// - Correlation meter from engine
/// - A/B comparison with full state snapshots

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'stereo_field_scope.dart';
import 'fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARAMETER INDICES (must match Rust StereoImagerWrapper)
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const width = 0;
  static const pan = 1;
  static const panLaw = 2; // 0=Linear, 1=ConstantPower, 2=Compromise, 3=NoCenterAtten
  static const balance = 3;
  static const midGainDb = 4;
  static const sideGainDb = 5;
  static const rotationDeg = 6;
  static const enableBalance = 7;
  static const enablePanner = 8;
  static const enableWidth = 9;
  static const enableMs = 10;
  static const enableRotation = 11;
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class ImagerSnapshot implements DspParameterSnapshot {
  final double width, pan, balance, midGainDb, sideGainDb, rotationDeg;
  final int panLaw;
  final bool enableBalance, enablePanner, enableWidth, enableMs, enableRotation;

  const ImagerSnapshot({
    required this.width,
    required this.pan,
    required this.panLaw,
    required this.balance,
    required this.midGainDb,
    required this.sideGainDb,
    required this.rotationDeg,
    required this.enableBalance,
    required this.enablePanner,
    required this.enableWidth,
    required this.enableMs,
    required this.enableRotation,
  });

  @override
  ImagerSnapshot copy() => ImagerSnapshot(
        width: width,
        pan: pan,
        panLaw: panLaw,
        balance: balance,
        midGainDb: midGainDb,
        sideGainDb: sideGainDb,
        rotationDeg: rotationDeg,
        enableBalance: enableBalance,
        enablePanner: enablePanner,
        enableWidth: enableWidth,
        enableMs: enableMs,
        enableRotation: enableRotation,
      );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! ImagerSnapshot) return false;
    return width == other.width &&
        pan == other.pan &&
        panLaw == other.panLaw &&
        balance == other.balance &&
        midGainDb == other.midGainDb &&
        sideGainDb == other.sideGainDb &&
        rotationDeg == other.rotationDeg &&
        enableBalance == other.enableBalance &&
        enablePanner == other.enablePanner &&
        enableWidth == other.enableWidth &&
        enableMs == other.enableMs &&
        enableRotation == other.enableRotation;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterImagerPanel extends FabFilterPanelBase {
  const FabFilterImagerPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-IMG',
          icon: Icons.surround_sound,
          accentColor: FabFilterColors.cyan,
          nodeType: DspNodeType.stereoImager,
        );

  @override
  State<FabFilterImagerPanel> createState() => _FabFilterImagerPanelState();
}

class _FabFilterImagerPanelState extends State<FabFilterImagerPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─── DSP PARAMETERS ──────────────────────────────────────────────────
  double _width = 1.0; // 0.0 (mono) → 1.0 (stereo) → 2.0 (wide)
  double _pan = 0.0; // -1.0 (L) → +1.0 (R)
  int _panLaw = 1; // 0=Linear, 1=ConstPower, 2=Compromise, 3=NoCenterAtten
  double _balance = 0.0; // -1.0 (L only) → +1.0 (R only)
  double _midGainDb = 0.0; // -24 → +24 dB
  double _sideGainDb = 0.0; // -24 → +24 dB
  double _rotationDeg = 0.0; // 0 → 360 degrees
  bool _enableBalance = false;
  bool _enablePanner = false;
  bool _enableWidth = true;
  bool _enableMs = false;
  bool _enableRotation = false;

  // ─── METERING ────────────────────────────────────────────────────────
  double _peakL = 0.0;
  double _peakR = 0.0;
  double _correlation = 0.0;

  // ─── ENGINE ──────────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ─────────────────────────────────────────────────────────────
  ImagerSnapshot? _snapshotA;
  ImagerSnapshot? _snapshotB;

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
      if (node.type == DspNodeType.stereoImager) {
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
      _width = _ffi.insertGetParam(t, s, _P.width);
      _pan = _ffi.insertGetParam(t, s, _P.pan);
      _panLaw = _ffi.insertGetParam(t, s, _P.panLaw).round().clamp(0, 3);
      _balance = _ffi.insertGetParam(t, s, _P.balance);
      _midGainDb = _ffi.insertGetParam(t, s, _P.midGainDb);
      _sideGainDb = _ffi.insertGetParam(t, s, _P.sideGainDb);
      _rotationDeg = _ffi.insertGetParam(t, s, _P.rotationDeg);
      _enableBalance = _ffi.insertGetParam(t, s, _P.enableBalance) > 0.5;
      _enablePanner = _ffi.insertGetParam(t, s, _P.enablePanner) > 0.5;
      _enableWidth = _ffi.insertGetParam(t, s, _P.enableWidth) > 0.5;
      _enableMs = _ffi.insertGetParam(t, s, _P.enableMs) > 0.5;
      _enableRotation = _ffi.insertGetParam(t, s, _P.enableRotation) > 0.5;
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
        _peakL = meter.peakL;
        _peakR = meter.peakR;
        _correlation = meter.correlation;
      });
    } catch (_) {}
  }

  // ─── A/B SNAPSHOT ─────────────────────────────────────────────────────

  ImagerSnapshot _snap() => ImagerSnapshot(
        width: _width,
        pan: _pan,
        panLaw: _panLaw,
        balance: _balance,
        midGainDb: _midGainDb,
        sideGainDb: _sideGainDb,
        rotationDeg: _rotationDeg,
        enableBalance: _enableBalance,
        enablePanner: _enablePanner,
        enableWidth: _enableWidth,
        enableMs: _enableMs,
        enableRotation: _enableRotation,
      );

  void _restore(ImagerSnapshot? s) {
    if (s == null) return;
    setState(() {
      _width = s.width;
      _pan = s.pan;
      _panLaw = s.panLaw;
      _balance = s.balance;
      _midGainDb = s.midGainDb;
      _sideGainDb = s.sideGainDb;
      _rotationDeg = s.rotationDeg;
      _enableBalance = s.enableBalance;
      _enablePanner = s.enablePanner;
      _enableWidth = s.enableWidth;
      _enableMs = s.enableMs;
      _enableRotation = s.enableRotation;
    });
    _setParam(_P.width, _width);
    _setParam(_P.pan, _pan);
    _setParam(_P.panLaw, _panLaw.toDouble());
    _setParam(_P.balance, _balance);
    _setParam(_P.midGainDb, _midGainDb);
    _setParam(_P.sideGainDb, _sideGainDb);
    _setParam(_P.rotationDeg, _rotationDeg);
    _setParam(_P.enableBalance, _enableBalance ? 1.0 : 0.0);
    _setParam(_P.enablePanner, _enablePanner ? 1.0 : 0.0);
    _setParam(_P.enableWidth, _enableWidth ? 1.0 : 0.0);
    _setParam(_P.enableMs, _enableMs ? 1.0 : 0.0);
    _setParam(_P.enableRotation, _enableRotation ? 1.0 : 0.0);
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
          _buildHeader(),
          Expanded(
            child: Container(
              color: FabFilterColors.bgDeep,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  // Vectorscope visualization
                  Expanded(flex: 3, child: _buildVectorscope()),
                  const SizedBox(height: 4),
                  // Correlation meter
                  _buildCorrelationMeter(),
                  const SizedBox(height: 8),
                  // Width knob (main control)
                  _buildWidthSection(),
                  const SizedBox(height: 8),
                  // Module rows
                  _buildModuleRows(),
                  const Flexible(child: SizedBox(height: 4)),
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
          Icon(Icons.surround_sound, size: 14, color: FabFilterColors.cyan),
          const SizedBox(width: 6),
          Text('FF-IMG  Stereo Imager',
              style: TextStyle(
                  color: FabFilterColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          FabCompactAB(
            isStateB: isStateB,
            onToggle: toggleAB,
            accentColor: FabFilterColors.cyan,
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

  // ─── VECTORSCOPE ─────────────────────────────────────────────────────

  Widget _buildVectorscope() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StereoFieldScope(
        peakL: _peakL,
        peakR: _peakR,
        correlation: _correlation,
        width: _width,
        pan: _pan,
        balance: _balance,
        rotationDeg: _rotationDeg,
        enableWidth: _enableWidth,
        enablePanner: _enablePanner,
        enableBalance: _enableBalance,
        enableRotation: _enableRotation,
        accent: FabFilterColors.cyan,
        showPhaseState: true,
      ),
    );
  }

  // ─── CORRELATION METER ───────────────────────────────────────────────

  Widget _buildCorrelationMeter() {
    // Correlation: -1.0 (out of phase) → 0.0 (uncorrelated) → +1.0 (mono)
    final corrNorm = (_correlation + 1.0) / 2.0; // 0.0 → 1.0
    final corrColor = _correlation < 0
        ? Color.lerp(FabFilterColors.red, FabFilterColors.yellow, corrNorm * 2)!
        : Color.lerp(FabFilterColors.yellow, FabFilterColors.green, (corrNorm - 0.5) * 2)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('-1',
                  style: TextStyle(
                      color: FabFilterColors.textTertiary,
                      fontSize: 8,
                      fontFamily: 'JetBrains Mono')),
              Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: FabFilterColors.bgMid,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final indicatorX = corrNorm * w;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Center line (0 correlation)
                          Positioned(
                            left: w / 2 - 0.5,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 1,
                              color: FabFilterColors.textTertiary.withValues(alpha: 0.3),
                            ),
                          ),
                          // Indicator
                          Positioned(
                            left: indicatorX.clamp(0, w) - 3,
                            top: -1,
                            child: Container(
                              width: 6,
                              height: 8,
                              decoration: BoxDecoration(
                                color: corrColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Text('+1',
                  style: TextStyle(
                      color: FabFilterColors.textTertiary,
                      fontSize: 8,
                      fontFamily: 'JetBrains Mono')),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'CORRELATION  ${_correlation.toStringAsFixed(2)}',
            style: TextStyle(
                color: corrColor,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }

  // ─── WIDTH SECTION ───────────────────────────────────────────────────

  Widget _buildWidthSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Width enable toggle
          FabTinyButton(
            label: 'W',
            active: _enableWidth,
            color: FabFilterColors.cyan,
            onTap: () {
              setState(() => _enableWidth = !_enableWidth);
              _setParam(_P.enableWidth, _enableWidth ? 1.0 : 0.0);
            },
          ),
          const SizedBox(width: 12),
          // Width knob (0.0=mono → 1.0=stereo → 2.0=wide)
          FabFilterKnob(
            value: _linNorm(_width, 0.0, 2.0),
            label: 'WIDTH',
            display: _width <= 0.01
                ? 'MONO'
                : _width >= 1.99
                    ? '200%'
                    : '${(_width * 100).round()}%',
            color: _enableWidth ? FabFilterColors.cyan : FabFilterColors.textTertiary,
            size: 56,
            defaultValue: 0.5, // 1.0 = stereo = 50% knob
            onChanged: (norm) {
                  if (!_enableWidth) return;
                  final v = _linDenorm(norm, 0.0, 2.0);
                  setState(() => _width = v);
                  _setParam(_P.width, v);
                },
          ),
        ],
      ),
    );
  }

  // ─── MODULE ROWS ─────────────────────────────────────────────────────

  Widget _buildModuleRows() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Pan + Pan Law
          _buildPanRow(),
          const SizedBox(height: 6),
          // Row 2: Balance + M/S
          _buildBalanceMsRow(),
          const SizedBox(height: 6),
          // Row 3: Rotation
          _buildRotationRow(),
        ],
      ),
    );
  }

  Widget _buildPanRow() {
    return Row(
      children: [
        FabTinyButton(
          label: 'P',
          active: _enablePanner,
          color: FabFilterColors.cyan,
          onTap: () {
            setState(() => _enablePanner = !_enablePanner);
            _setParam(_P.enablePanner, _enablePanner ? 1.0 : 0.0);
          },
        ),
        const SizedBox(width: 6),
        // Pan knob
        FabFilterKnob(
          value: _linNorm(_pan, -1.0, 1.0),
          label: 'PAN',
          display: _pan.abs() < 0.01
              ? 'C'
              : _pan < 0
                  ? 'L${(-_pan * 100).round()}'
                  : 'R${(_pan * 100).round()}',
          color: _enablePanner ? FabFilterColors.cyan : FabFilterColors.textTertiary,
          size: 38,
          defaultValue: 0.5, // 0.0 pan = center = 50% knob
          onChanged: (norm) {
                if (!_enablePanner) return;
                final v = _linDenorm(norm, -1.0, 1.0);
                setState(() => _pan = v);
                _setParam(_P.pan, v);
              },
        ),
        const SizedBox(width: 12),
        // Pan Law selector
        Expanded(
          child: _buildPanLawSelector(),
        ),
      ],
    );
  }

  Widget _buildPanLawSelector() {
    const labels = ['LIN', 'CP', 'CMP', 'NCA'];
    const tooltips = ['Linear', 'Constant Power', 'Compromise', 'No Center Atten.'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('PAN LAW',
            style: TextStyle(
                color: FabFilterColors.textTertiary,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            return Padding(
              padding: EdgeInsets.only(left: i > 0 ? 2 : 0),
              child: Tooltip(
                message: tooltips[i],
                child: FabTinyButton(
                  label: labels[i],
                  active: _panLaw == i,
                  color: FabFilterColors.cyan,
                  onTap: () {
                    setState(() => _panLaw = i);
                    _setParam(_P.panLaw, i.toDouble());
                  },
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBalanceMsRow() {
    return Row(
      children: [
        // Balance
        FabTinyButton(
          label: 'B',
          active: _enableBalance,
          color: FabFilterColors.cyan,
          onTap: () {
            setState(() => _enableBalance = !_enableBalance);
            _setParam(_P.enableBalance, _enableBalance ? 1.0 : 0.0);
          },
        ),
        const SizedBox(width: 6),
        FabFilterKnob(
          value: _linNorm(_balance, -1.0, 1.0),
          label: 'BAL',
          display: _balance.abs() < 0.01
              ? 'C'
              : _balance < 0
                  ? 'L${(-_balance * 100).round()}'
                  : 'R${(_balance * 100).round()}',
          color: _enableBalance ? FabFilterColors.cyan : FabFilterColors.textTertiary,
          size: 38,
          defaultValue: 0.5,
          onChanged: (norm) {
                if (!_enableBalance) return;
                final v = _linDenorm(norm, -1.0, 1.0);
                setState(() => _balance = v);
                _setParam(_P.balance, v);
              },
        ),
        const SizedBox(width: 12),
        // M/S Gain
        FabTinyButton(
          label: 'MS',
          active: _enableMs,
          color: FabFilterColors.purple,
          onTap: () {
            setState(() => _enableMs = !_enableMs);
            _setParam(_P.enableMs, _enableMs ? 1.0 : 0.0);
          },
        ),
        const SizedBox(width: 6),
        FabFilterKnob(
          value: _linNorm(_midGainDb, -24.0, 24.0),
          label: 'MID',
          display: '${_midGainDb >= 0 ? '+' : ''}${_midGainDb.toStringAsFixed(1)}',
          color: _enableMs ? FabFilterColors.purple : FabFilterColors.textTertiary,
          size: 38,
          defaultValue: 0.5, // 0dB
          onChanged: (norm) {
                if (!_enableMs) return;
                final v = _linDenorm(norm, -24.0, 24.0);
                setState(() => _midGainDb = v);
                _setParam(_P.midGainDb, v);
              },
        ),
        const SizedBox(width: 4),
        FabFilterKnob(
          value: _linNorm(_sideGainDb, -24.0, 24.0),
          label: 'SIDE',
          display: '${_sideGainDb >= 0 ? '+' : ''}${_sideGainDb.toStringAsFixed(1)}',
          color: _enableMs ? FabFilterColors.purple : FabFilterColors.textTertiary,
          size: 38,
          defaultValue: 0.5,
          onChanged: (norm) {
                if (!_enableMs) return;
                final v = _linDenorm(norm, -24.0, 24.0);
                setState(() => _sideGainDb = v);
                _setParam(_P.sideGainDb, v);
              },
        ),
      ],
    );
  }

  Widget _buildRotationRow() {
    return Row(
      children: [
        FabTinyButton(
          label: 'R',
          active: _enableRotation,
          color: FabFilterColors.orange,
          onTap: () {
            setState(() => _enableRotation = !_enableRotation);
            _setParam(_P.enableRotation, _enableRotation ? 1.0 : 0.0);
          },
        ),
        const SizedBox(width: 6),
        FabFilterKnob(
          value: _linNorm(_rotationDeg, 0.0, 360.0),
          label: 'ROTATE',
          display: '${_rotationDeg.toStringAsFixed(0)}°',
          color: _enableRotation ? FabFilterColors.orange : FabFilterColors.textTertiary,
          size: 38,
          defaultValue: 0.0,
          onChanged: (norm) {
                if (!_enableRotation) return;
                final v = _linDenorm(norm, 0.0, 360.0);
                setState(() => _rotationDeg = v);
                _setParam(_P.rotationDeg, v);
              },
        ),
        const Spacer(),
        // Width readout
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: FabFilterColors.bgMid,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: FabFilterColors.borderSubtle),
          ),
          child: Text(
            'WIDTH ${(_width * 100).round()}%',
            style: TextStyle(
                color: FabFilterColors.cyan,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono'),
          ),
        ),
      ],
    );
  }

  // ─── METERS ──────────────────────────────────────────────────────────

  Widget _buildMeters() {
    double toDb(double linear) =>
        linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;
    final dbL = toDb(_peakL).clamp(-60.0, 6.0);
    final dbR = toDb(_peakR).clamp(-60.0, 6.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildMeterStrip('L', dbL),
          const SizedBox(width: 4),
          _buildMeterStrip('R', dbR),
          const Spacer(),
          // dB readout
          Text(
            '${dbL.toStringAsFixed(1)} / ${dbR.toStringAsFixed(1)} dB',
            style: TextStyle(
                color: FabFilterColors.textTertiary,
                fontSize: 8,
                fontFamily: 'JetBrains Mono'),
          ),
        ],
      ),
    );
  }

  Widget _buildMeterStrip(String label, double db) {
    final norm = ((db + 60) / 66).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: FabFilterColors.textTertiary,
                fontSize: 8,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 3),
        Container(
          width: 80,
          height: 4,
          decoration: BoxDecoration(
            color: FabFilterColors.bgMid,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: norm,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [FabFilterColors.cyan, FabFilterColors.green],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
