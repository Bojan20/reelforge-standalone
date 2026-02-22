/// FF-MBI Multiband Stereo Imager Panel — iZotope Ozone Level
///
/// Professional multiband stereo imaging processor:
/// - Up to 6 bands with configurable crossover frequencies
/// - Per-band Width, Pan, Mid/Side Gain, Rotation controls
/// - Per-band Solo/Mute/Bypass toggles
/// - Global I/O gain, mix, crossover type (BW12/LR24/LR48), M/S mode
/// - Per-band correlation meters from engine
/// - I/O peak metering at ~30fps
/// - A/B comparison with full snapshot

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';
import 'stereo_field_scope.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARAMETER INDICES (must match MultibandStereoImagerWrapper in Rust)
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  // Global (0-10)
  static const inputGain = 0;    // -24..+24 dB
  static const outputGain = 1;   // -24..+24 dB
  static const globalMix = 2;    // 0..100 %
  static const numBands = 3;     // 2..6
  static const crossoverType = 4; // 0=BW12, 1=LR24, 2=LR48
  static const crossover0 = 5;   // 20..20000 Hz
  static const crossover1 = 6;
  static const crossover2 = 7;
  static const crossover3 = 8;
  static const crossover4 = 9;
  static const msMode = 10;      // 0/1

  // Per-band (offset = 11 + band * 9)
  static const bWidth = 0;       // 0..2 (0=mono, 1=stereo, 2=wide)
  static const bPan = 1;         // -1..+1
  static const bMidGain = 2;     // -24..+24 dB
  static const bSideGain = 3;    // -24..+24 dB
  static const bRotation = 4;    // 0..360 deg
  static const bEnableWidth = 5; // 0/1
  static const bSolo = 6;        // 0/1
  static const bMute = 7;        // 0/1
  static const bBypass = 8;      // 0/1

  static const globalCount = 11;
  static const bandParamCount = 9;

  static int band(int bandIdx, int param) => globalCount + bandIdx * bandParamCount + param;
}

/// Crossover type names
const _crossoverLabels = ['BW12', 'LR24', 'LR48'];

/// Band accent colors
const _bandColors = [
  FabFilterColors.cyan,
  FabFilterColors.green,
  FabFilterColors.yellow,
  FabFilterColors.orange,
  FabFilterColors.pink,
  FabFilterColors.red,
];

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class MbImagerSnapshot implements DspParameterSnapshot {
  final double inputGain, outputGain, globalMix;
  final bool msMode;
  final int numBands, crossoverType;
  final List<double> crossovers;
  final List<MbImagerBandState> bands;

  const MbImagerSnapshot({
    required this.inputGain, required this.outputGain, required this.globalMix,
    required this.msMode, required this.numBands, required this.crossoverType,
    required this.crossovers, required this.bands,
  });

  @override
  MbImagerSnapshot copy() => MbImagerSnapshot(
    inputGain: inputGain, outputGain: outputGain, globalMix: globalMix,
    msMode: msMode, numBands: numBands, crossoverType: crossoverType,
    crossovers: List.of(crossovers),
    bands: bands.map((b) => b.copy()).toList(),
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! MbImagerSnapshot) return false;
    return inputGain == other.inputGain && outputGain == other.outputGain &&
        numBands == other.numBands && crossoverType == other.crossoverType;
  }
}

class MbImagerBandState {
  double width, pan, midGainDb, sideGainDb, rotation;
  bool enableWidth, solo, mute, bypass;

  MbImagerBandState({
    this.width = 1.0, this.pan = 0.0, this.midGainDb = 0.0,
    this.sideGainDb = 0.0, this.rotation = 0.0, this.enableWidth = true,
    this.solo = false, this.mute = false, this.bypass = false,
  });

  MbImagerBandState copy() => MbImagerBandState(
    width: width, pan: pan, midGainDb: midGainDb, sideGainDb: sideGainDb,
    rotation: rotation, enableWidth: enableWidth,
    solo: solo, mute: mute, bypass: bypass,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterMultibandImagerPanel extends FabFilterPanelBase {
  const FabFilterMultibandImagerPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-MBI',
          icon: Icons.surround_sound,
          accentColor: FabFilterColors.cyan,
          nodeType: DspNodeType.multibandStereoImager,
        );

  @override
  State<FabFilterMultibandImagerPanel> createState() => _FabFilterMultibandImagerPanelState();
}

class _FabFilterMultibandImagerPanelState extends State<FabFilterMultibandImagerPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {

  // ─── GLOBAL PARAMETERS ────────────────────────────────────────────
  double _inputGain = 0.0;
  double _outputGain = 0.0;
  double _globalMix = 100.0;
  bool _msMode = false;
  int _numBands = 4;
  int _crossoverType = 1; // LR24
  final List<double> _crossovers = [120, 750, 2500, 7000, 14000];

  // ─── PER-BAND ─────────────────────────────────────────────────────
  final List<MbImagerBandState> _bands = List.generate(6, (_) => MbImagerBandState());
  int _selectedBand = 0;

  // ─── METERING ─────────────────────────────────────────────────────
  double _inL = 0, _inR = 0, _outL = 0, _outR = 0;
  final List<double> _bandCorrelations = List.filled(6, 1.0);

  // ─── ENGINE ───────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ──────────────────────────────────────────────────────────
  MbImagerSnapshot? _snapshotA;
  MbImagerSnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  // ─── LIFECYCLE ────────────────────────────────────────────────────

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

  @override
  void dispose() {
    _meterController.dispose();
    super.dispose();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.multibandStereoImager) {
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
      _inputGain = _ffi.insertGetParam(t, s, _P.inputGain);
      _outputGain = _ffi.insertGetParam(t, s, _P.outputGain);
      _globalMix = _ffi.insertGetParam(t, s, _P.globalMix);
      _numBands = _ffi.insertGetParam(t, s, _P.numBands).round().clamp(2, 6);
      _crossoverType = _ffi.insertGetParam(t, s, _P.crossoverType).round().clamp(0, 2);
      for (int i = 0; i < 5; i++) {
        _crossovers[i] = _ffi.insertGetParam(t, s, _P.crossover0 + i);
      }
      _msMode = _ffi.insertGetParam(t, s, _P.msMode) > 0.5;
      for (int b = 0; b < 6; b++) {
        _bands[b]
          ..width = _ffi.insertGetParam(t, s, _P.band(b, _P.bWidth))
          ..pan = _ffi.insertGetParam(t, s, _P.band(b, _P.bPan))
          ..midGainDb = _ffi.insertGetParam(t, s, _P.band(b, _P.bMidGain))
          ..sideGainDb = _ffi.insertGetParam(t, s, _P.band(b, _P.bSideGain))
          ..rotation = _ffi.insertGetParam(t, s, _P.band(b, _P.bRotation))
          ..enableWidth = _ffi.insertGetParam(t, s, _P.band(b, _P.bEnableWidth)) > 0.5
          ..solo = _ffi.insertGetParam(t, s, _P.band(b, _P.bSolo)) > 0.5
          ..mute = _ffi.insertGetParam(t, s, _P.band(b, _P.bMute)) > 0.5
          ..bypass = _ffi.insertGetParam(t, s, _P.band(b, _P.bBypass)) > 0.5;
      }
    });
  }

  void _setParam(int idx, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, idx, value);
    }
  }

  // ─── A/B ──────────────────────────────────────────────────────────

  MbImagerSnapshot _snap() => MbImagerSnapshot(
    inputGain: _inputGain, outputGain: _outputGain, globalMix: _globalMix,
    msMode: _msMode, numBands: _numBands, crossoverType: _crossoverType,
    crossovers: List.of(_crossovers),
    bands: _bands.map((b) => b.copy()).toList(),
  );

  void _restore(MbImagerSnapshot s) {
    setState(() {
      _inputGain = s.inputGain; _outputGain = s.outputGain;
      _globalMix = s.globalMix; _msMode = s.msMode;
      _numBands = s.numBands; _crossoverType = s.crossoverType;
      for (int i = 0; i < 5; i++) _crossovers[i] = s.crossovers[i];
      for (int b = 0; b < 6; b++) {
        final src = s.bands[b];
        _bands[b]
          ..width = src.width ..pan = src.pan
          ..midGainDb = src.midGainDb ..sideGainDb = src.sideGainDb
          ..rotation = src.rotation ..enableWidth = src.enableWidth
          ..solo = src.solo ..mute = src.mute ..bypass = src.bypass;
      }
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.inputGain, _inputGain);
    _setParam(_P.outputGain, _outputGain);
    _setParam(_P.globalMix, _globalMix);
    _setParam(_P.msMode, _msMode ? 1 : 0);
    _setParam(_P.numBands, _numBands.toDouble());
    _setParam(_P.crossoverType, _crossoverType.toDouble());
    for (int i = 0; i < 5; i++) _setParam(_P.crossover0 + i, _crossovers[i]);
    for (int b = 0; b < 6; b++) {
      final band = _bands[b];
      _setParam(_P.band(b, _P.bWidth), band.width);
      _setParam(_P.band(b, _P.bPan), band.pan);
      _setParam(_P.band(b, _P.bMidGain), band.midGainDb);
      _setParam(_P.band(b, _P.bSideGain), band.sideGainDb);
      _setParam(_P.band(b, _P.bRotation), band.rotation);
      _setParam(_P.band(b, _P.bEnableWidth), band.enableWidth ? 1 : 0);
      _setParam(_P.band(b, _P.bSolo), band.solo ? 1 : 0);
      _setParam(_P.band(b, _P.bMute), band.mute ? 1 : 0);
      _setParam(_P.band(b, _P.bBypass), band.bypass ? 1 : 0);
    }
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

  // ─── METERING ─────────────────────────────────────────────────────

  void _updateMeters() {
    if (!mounted || !_initialized || _slotIndex < 0) return;
    final t = widget.trackId, s = _slotIndex;
    setState(() {
      try {
        _inL = _ffi.insertGetMeter(t, s, 0);
        _inR = _ffi.insertGetMeter(t, s, 1);
        _outL = _ffi.insertGetMeter(t, s, 2);
        _outR = _ffi.insertGetMeter(t, s, 3);
        for (int b = 0; b < 6; b++) {
          _bandCorrelations[b] = _ffi.insertGetMeter(t, s, 4 + b);
        }
      } catch (_) {}
    });
  }

  // ─── HELPERS ──────────────────────────────────────────────────────

  double _linNorm(double value, double minV, double maxV) {
    return ((value - minV) / (maxV - minV)).clamp(0.0, 1.0);
  }

  double _linDenorm(double norm, double minV, double maxV) {
    return minV + norm.clamp(0.0, 1.0) * (maxV - minV);
  }

  double _logNorm(double value, double minV, double maxV) {
    if (value <= minV) return 0;
    return (math.log(value) - math.log(minV)) / (math.log(maxV) - math.log(minV));
  }

  double _logDenorm(double norm, double minV, double maxV) {
    return math.exp(math.log(minV) + norm * (math.log(maxV) - math.log(minV)));
  }

  String _dbStr(double v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(1)} dB';
  String _pctStr(double v) => '${v.toStringAsFixed(0)}%';
  String _freqStr(double hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)}k' : '${hz.toStringAsFixed(0)} Hz';
  String _degStr(double deg) => '${deg.toStringAsFixed(0)}°';
  String _panStr(double p) => p < -0.01 ? 'L${(-p * 100).toStringAsFixed(0)}' : p > 0.01 ? 'R${(p * 100).toStringAsFixed(0)}' : 'C';

  double _linearToDb(double linear) => linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;

  Color get _bandColor => _bandColors[_selectedBand % _bandColors.length];

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('MB Imager', DspNodeType.multibandStereoImager, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildCompactHeader(),
          _buildBandSelector(),
          Expanded(child: _buildMainArea()),
          _buildBandStrip(),
          _buildFooter(),
        ],
      ),
    ));
  }

  // ─── BAND SELECTOR ROW ────────────────────────────────────────────

  Widget _buildBandSelector() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(bottom: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Text('BANDS', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          const SizedBox(width: 4),
          ...List.generate(5, (i) {
            final count = i + 2;
            final active = _numBands == count;
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: FabTinyButton(
                label: '$count',
                active: active,
                color: FabFilterColors.cyan,
                onTap: () {
                  setState(() => _numBands = count);
                  _setParam(_P.numBands, count.toDouble());
                },
              ),
            );
          }),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: List.generate(_numBands, (b) {
                final selected = _selectedBand == b;
                final color = _bandColors[b % _bandColors.length];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedBand = b),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                      decoration: BoxDecoration(
                        color: selected ? color.withValues(alpha: 0.25) : FabFilterColors.bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: selected ? color : FabFilterColors.borderSubtle,
                          width: selected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'B${b + 1}',
                          style: TextStyle(
                            color: selected ? color : FabFilterColors.textTertiary,
                            fontSize: 9, fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ─── MAIN CONTROL AREA ────────────────────────────────────────────

  Widget _buildMainArea() {
    final band = _bands[_selectedBand];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // I/O meters (left)
          _buildMeterColumn(),
          const SizedBox(width: 8),
          // Per-band controls (center)
          Expanded(child: _buildBandControls(band)),
          const SizedBox(width: 8),
          // Global sidebar (right)
          SizedBox(width: 100, child: _buildGlobalSidebar()),
        ],
      ),
    );
  }

  Widget _buildMeterColumn() {
    final inDb = _linearToDb(math.max(_inL, _inR));
    final outDb = _linearToDb(math.max(_outL, _outR));
    return SizedBox(
      width: 28,
      child: Column(
        children: [
          const FabSectionLabel('I/O'),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildVerticalMeter(inDb, FabFilterColors.cyan, 'IN')),
                const SizedBox(width: 2),
                Expanded(child: _buildVerticalMeter(outDb, FabFilterColors.green, 'OUT')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(double db, Color color, String label) {
    final norm = ((db + 60.0) / 60.0).clamp(0.0, 1.0);
    return Column(
      children: [
        Expanded(
          child: Container(
            width: 10,
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: norm,
                child: Container(
                  decoration: BoxDecoration(
                    color: norm > 0.95 ? FabFilterColors.red : color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 6)),
      ],
    );
  }

  // ─── PER-BAND CONTROLS ────────────────────────────────────────────

  Widget _buildBandControls(MbImagerBandState band) {
    final color = _bandColor;
    return Column(
      children: [
        // Band correlation meter
        _buildBandCorrelation(),
        const SizedBox(height: 4),
        // Vectorscope — multiband mode with per-band correlations
        SizedBox(
          height: 120,
          child: StereoFieldScope(
            peakL: _inL,
            peakR: _inR,
            correlation: _bandCorrelations[_selectedBand],
            width: band.width,
            pan: band.pan,
            rotationDeg: band.rotation,
            enableWidth: band.enableWidth,
            accent: color,
            showPhaseState: true,
            bandCorrelations: _bandCorrelations.sublist(0, _numBands),
            numBands: _numBands,
            bandColors: _bandColors.sublist(0, _numBands),
            selectedBand: _selectedBand,
          ),
        ),
        const SizedBox(height: 4),
        // Knob grid
        Expanded(child: _buildKnobGrid(band, color)),
      ],
    );
  }

  Widget _buildBandCorrelation() {
    final corr = _bandCorrelations[_selectedBand].clamp(-1.0, 1.0);
    final corrNorm = (corr + 1.0) / 2.0;
    final corrColor = corr < 0
        ? Color.lerp(FabFilterColors.red, FabFilterColors.yellow, corrNorm * 2)!
        : Color.lerp(FabFilterColors.yellow, FabFilterColors.green, (corrNorm - 0.5) * 2)!;

    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text('CORR', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
          const SizedBox(width: 4),
          Text('-1', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(3),
              ),
              child: LayoutBuilder(builder: (_, constraints) {
                final w = constraints.maxWidth;
                final pos = corrNorm * w;
                return Stack(
                  children: [
                    // Center tick
                    Positioned(
                      left: w * 0.5 - 0.5,
                      top: 0, bottom: 0,
                      child: Container(width: 1, color: FabFilterColors.textTertiary.withValues(alpha: 0.3)),
                    ),
                    // Indicator
                    Positioned(
                      left: pos.clamp(0, w - 4),
                      top: 0, bottom: 0,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: corrColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(width: 2),
          Text('+1', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            child: Text(
              corr.toStringAsFixed(2),
              style: TextStyle(color: corrColor, fontSize: 8, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKnobGrid(MbImagerBandState band, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // WIDTH
        _buildKnob(
          label: 'WIDTH',
          display: band.width <= 0.01 ? 'MONO' : band.width >= 1.99 ? 'WIDE' : '${(band.width * 100).toStringAsFixed(0)}%',
          value: (band.width / 2.0).clamp(0.0, 1.0),
          color: color,
          defaultValue: 0.5,
          onChanged: (v) {
            if (!band.enableWidth) return;
            final w = v * 2.0;
            setState(() => band.width = w);
            _setParam(_P.band(_selectedBand, _P.bWidth), w);
          },
        ),
        // PAN
        _buildKnob(
          label: 'PAN',
          display: _panStr(band.pan),
          value: _linNorm(band.pan, -1.0, 1.0),
          color: FabFilterColors.blue,
          defaultValue: 0.5,
          onChanged: (v) {
            final p = _linDenorm(v, -1.0, 1.0);
            setState(() => band.pan = p);
            _setParam(_P.band(_selectedBand, _P.bPan), p);
          },
        ),
        // MID GAIN
        _buildKnob(
          label: 'MID',
          display: _dbStr(band.midGainDb),
          value: _linNorm(band.midGainDb, -24.0, 24.0),
          color: FabFilterColors.green,
          defaultValue: 0.5,
          onChanged: (v) {
            final db = _linDenorm(v, -24.0, 24.0);
            setState(() => band.midGainDb = db);
            _setParam(_P.band(_selectedBand, _P.bMidGain), db);
          },
        ),
        // SIDE GAIN
        _buildKnob(
          label: 'SIDE',
          display: _dbStr(band.sideGainDb),
          value: _linNorm(band.sideGainDb, -24.0, 24.0),
          color: FabFilterColors.orange,
          defaultValue: 0.5,
          onChanged: (v) {
            final db = _linDenorm(v, -24.0, 24.0);
            setState(() => band.sideGainDb = db);
            _setParam(_P.band(_selectedBand, _P.bSideGain), db);
          },
        ),
        // ROTATION
        _buildKnob(
          label: 'ROTATE',
          display: _degStr(band.rotation),
          value: (band.rotation / 360.0).clamp(0.0, 1.0),
          color: FabFilterColors.pink,
          defaultValue: 0.0,
          onChanged: (v) {
            final deg = v * 360.0;
            setState(() => band.rotation = deg);
            _setParam(_P.band(_selectedBand, _P.bRotation), deg);
          },
        ),
      ],
    );
  }

  Widget _buildKnob({
    required String label,
    required String display,
    required double value,
    required Color color,
    required double defaultValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FabFilterKnob(
          value: value,
          label: label,
          display: display,
          color: color,
          size: 48,
          defaultValue: defaultValue,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ─── GLOBAL SIDEBAR ───────────────────────────────────────────────

  Widget _buildGlobalSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FabSectionLabel('GLOBAL'),
        const SizedBox(height: 4),
        // Input Gain
        _buildKnob(
          label: 'IN GAIN',
          display: _dbStr(_inputGain),
          value: _linNorm(_inputGain, -24.0, 24.0),
          color: FabFilterColors.cyan,
          defaultValue: 0.5,
          onChanged: (v) {
            final db = _linDenorm(v, -24.0, 24.0);
            setState(() => _inputGain = db);
            _setParam(_P.inputGain, db);
          },
        ),
        const SizedBox(height: 4),
        // Output Gain
        _buildKnob(
          label: 'OUT GAIN',
          display: _dbStr(_outputGain),
          value: _linNorm(_outputGain, -24.0, 24.0),
          color: FabFilterColors.green,
          defaultValue: 0.5,
          onChanged: (v) {
            final db = _linDenorm(v, -24.0, 24.0);
            setState(() => _outputGain = db);
            _setParam(_P.outputGain, db);
          },
        ),
        const SizedBox(height: 4),
        // Global Mix
        _buildKnob(
          label: 'MIX',
          display: _pctStr(_globalMix),
          value: (_globalMix / 100.0).clamp(0.0, 1.0),
          color: FabFilterColors.blue,
          defaultValue: 1.0,
          onChanged: (v) {
            final pct = v * 100.0;
            setState(() => _globalMix = pct);
            _setParam(_P.globalMix, pct);
          },
        ),
        const SizedBox(height: 8),
        // Crossover type
        _buildCrossoverTypeSelector(),
        const SizedBox(height: 4),
        // M/S mode
        _buildMsModeToggle(),
      ],
    );
  }

  Widget _buildCrossoverTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CROSSOVER', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        const SizedBox(height: 2),
        SizedBox(
          height: 20,
          child: Row(
            children: List.generate(3, (i) {
              final active = _crossoverType == i;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _crossoverType = i);
                      _setParam(_P.crossoverType, i.toDouble());
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: active ? FabFilterColors.cyan.withValues(alpha: 0.25) : FabFilterColors.bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: active ? FabFilterColors.cyan : FabFilterColors.borderSubtle,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _crossoverLabels[i],
                          style: TextStyle(
                            color: active ? FabFilterColors.cyan : FabFilterColors.textTertiary,
                            fontSize: 7, fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMsModeToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _msMode = !_msMode);
        _setParam(_P.msMode, _msMode ? 1 : 0);
      },
      child: Container(
        height: 20,
        decoration: BoxDecoration(
          color: _msMode ? FabFilterColors.orange.withValues(alpha: 0.25) : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _msMode ? FabFilterColors.orange : FabFilterColors.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            _msMode ? 'M/S MODE' : 'L/R MODE',
            style: TextStyle(
              color: _msMode ? FabFilterColors.orange : FabFilterColors.textTertiary,
              fontSize: 8, fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ─── BAND STRIP (Solo/Mute/Bypass) ───────────────────────────────

  Widget _buildBandStrip() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Width enable toggle
          FabTinyButton(
            label: 'W',
            active: _bands[_selectedBand].enableWidth,
            color: _bandColor,
            onTap: () {
              final val = !_bands[_selectedBand].enableWidth;
              setState(() => _bands[_selectedBand].enableWidth = val);
              _setParam(_P.band(_selectedBand, _P.bEnableWidth), val ? 1 : 0);
            },
          ),
          const SizedBox(width: 4),
          // Solo
          FabTinyButton(
            label: 'S',
            active: _bands[_selectedBand].solo,
            color: FabFilterColors.yellow,
            onTap: () {
              final val = !_bands[_selectedBand].solo;
              setState(() => _bands[_selectedBand].solo = val);
              _setParam(_P.band(_selectedBand, _P.bSolo), val ? 1 : 0);
            },
          ),
          const SizedBox(width: 2),
          // Mute
          FabTinyButton(
            label: 'M',
            active: _bands[_selectedBand].mute,
            color: FabFilterColors.red,
            onTap: () {
              final val = !_bands[_selectedBand].mute;
              setState(() => _bands[_selectedBand].mute = val);
              _setParam(_P.band(_selectedBand, _P.bMute), val ? 1 : 0);
            },
          ),
          const SizedBox(width: 2),
          // Bypass
          FabTinyButton(
            label: 'B',
            active: _bands[_selectedBand].bypass,
            color: FabFilterColors.orange,
            onTap: () {
              final val = !_bands[_selectedBand].bypass;
              setState(() => _bands[_selectedBand].bypass = val);
              _setParam(_P.band(_selectedBand, _P.bBypass), val ? 1 : 0);
            },
          ),
          const Spacer(),
          // Crossover frequency for selected band (if not last band)
          if (_selectedBand < _numBands - 1) ...[
            Text('FREQ', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
            const SizedBox(width: 4),
            SizedBox(
              width: 80,
              child: _buildCrossoverSlider(),
            ),
          ],
          if (_selectedBand < _numBands - 1) const SizedBox(width: 8),
          // Band correlation readout
          Text(
            'Corr: ${_bandCorrelations[_selectedBand].clamp(-1.0, 1.0).toStringAsFixed(2)}',
            style: TextStyle(
              color: _bandCorrelations[_selectedBand] < 0 ? FabFilterColors.red : FabFilterColors.green,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrossoverSlider() {
    final freq = _crossovers[_selectedBand];
    final norm = _logNorm(freq, 20, 20000);
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: _bandColor,
              inactiveTrackColor: FabFilterColors.bgVoid,
              thumbColor: _bandColor,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: norm,
              onChanged: (v) {
                final hz = _logDenorm(v, 20, 20000);
                setState(() => _crossovers[_selectedBand] = hz);
                _setParam(_P.crossover0 + _selectedBand, hz);
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          child: Text(
            _freqStr(freq),
            style: FabFilterText.paramLabel.copyWith(fontSize: 7, color: _bandColor),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ─── FOOTER ───────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: FabFilterColors.bgDeep,
      child: Row(
        children: [
          Text('FF-MBI  Multiband Imager',
            style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 8)),
          const Spacer(),
          Text(
            '${_numBands}B  ${_crossoverLabels[_crossoverType]}  ${_msMode ? "M/S" : "L/R"}',
            style: TextStyle(color: FabFilterColors.cyan, fontSize: 8, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
