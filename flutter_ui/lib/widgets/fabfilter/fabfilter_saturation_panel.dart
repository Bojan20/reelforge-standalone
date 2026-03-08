/// FF-SAT Saturn 2 Multiband Saturator Panel
///
/// Professional multiband saturation processor:
/// - Per-band saturation with independent Drive, Type, Tone, Mix, Output, Dynamics
/// - 6 saturation modes: Tape, Tube, Transistor, Soft Clip, Hard Clip, Foldback
/// - Up to 6 bands with configurable crossover frequencies
/// - Global I/O gain, mix, M/S processing, crossover type
/// - Per-band Solo/Mute/Bypass strip
/// - Real-time I/O + per-band peak metering at ~30fps
/// - A/B comparison with full snapshot

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Parameter indices matching MultibandSaturatorWrapper in Rust
class _P {
  // Global (0-10)
  static const inputGain = 0;   // -24..+24 dB
  static const outputGain = 1;  // -24..+24 dB
  static const globalMix = 2;   // 0..100 %
  static const msMode = 3;      // 0/1
  static const numBands = 4;    // 2..6
  static const crossoverType = 5; // 0=BW12, 1=LR24, 2=LR48
  static const crossover1 = 6;  // 20..20000 Hz
  static const crossover2 = 7;
  static const crossover3 = 8;
  static const crossover4 = 9;
  static const crossover5 = 10;

  // Per-band (offset = 11 + band * 9)
  static const bDrive = 0;     // -24..+52 dB
  static const bType = 1;      // 0-5 enum
  static const bTone = 2;      // -100..+100
  static const bMix = 3;       // 0..100 %
  static const bOutput = 4;    // -24..+24 dB
  static const bDynamics = 5;  // -1..+1
  static const bSolo = 6;      // 0/1
  static const bMute = 7;      // 0/1
  static const bBypass = 8;    // 0/1

  static const globalCount = 11;
  static const bandParamCount = 9;

  static int band(int bandIdx, int param) => globalCount + bandIdx * bandParamCount + param;
}

/// Saturation type names
const _satTypeLabels = ['Tape', 'Tube', 'Trans', 'Soft', 'Hard', 'Fold'];
const _satTypeColors = [
  FabFilterColors.orange,  // Tape
  FabFilterColors.green,   // Tube
  FabFilterColors.cyan,    // Transistor
  FabFilterColors.yellow,  // Soft Clip
  FabFilterColors.red,     // Hard Clip
  FabFilterColors.pink,    // Foldback
];

/// Crossover type names
const _crossoverLabels = ['BW12', 'LR24', 'LR48'];

/// Factory preset for saturator
class _SatPreset {
  final String name;
  final String category;
  final double inputGain;
  final double outputGain;
  final double globalMix;
  final int numBands;
  final int crossoverType;
  final List<double> crossovers;
  final List<(double drive, int type, double tone, double mix)> bands;

  const _SatPreset({
    required this.name,
    required this.category,
    this.inputGain = 0,
    this.outputGain = 0,
    this.globalMix = 100,
    this.numBands = 2,
    this.crossoverType = 1,
    this.crossovers = const [800, 4000, 8000, 12000, 16000],
    this.bands = const [],
  });
}

const _kSatPresets = <_SatPreset>[
  // ── Subtle ──
  _SatPreset(name: 'Warm Tape', category: 'Subtle',
    inputGain: 0, outputGain: 0, globalMix: 60, numBands: 2, crossoverType: 1,
    crossovers: [800, 4000, 8000, 12000, 16000],
    bands: [(6, 0, 20, 80), (-2, 0, -10, 50)]),
  _SatPreset(name: 'Tube Glow', category: 'Subtle',
    inputGain: 0, outputGain: -1, globalMix: 50, numBands: 2,
    crossovers: [1000, 4000, 8000, 12000, 16000],
    bands: [(4, 1, 0, 70), (2, 1, 10, 40)]),
  _SatPreset(name: 'Console Drive', category: 'Subtle',
    inputGain: 0, outputGain: -2, globalMix: 40, numBands: 3,
    crossovers: [250, 3000, 8000, 12000, 16000],
    bands: [(3, 2, -5, 50), (5, 2, 0, 60), (2, 2, 10, 40)]),
  // ── Warm ──
  _SatPreset(name: 'Analog Warmth', category: 'Warm',
    inputGain: 2, outputGain: -2, globalMix: 70, numBands: 2,
    crossovers: [600, 4000, 8000, 12000, 16000],
    bands: [(8, 0, 15, 80), (4, 1, -5, 60)]),
  _SatPreset(name: 'Vintage Tape', category: 'Warm',
    inputGain: 3, outputGain: -3, globalMix: 80, numBands: 3,
    crossovers: [200, 4000, 8000, 12000, 16000],
    bands: [(10, 0, 30, 90), (6, 0, 0, 70), (3, 0, -20, 50)]),
  _SatPreset(name: 'Neve Preamp', category: 'Warm',
    inputGain: 2, outputGain: -1, globalMix: 60, numBands: 2,
    crossovers: [1200, 4000, 8000, 12000, 16000],
    bands: [(7, 2, 10, 75), (3, 2, 5, 50)]),
  // ── Aggressive ──
  _SatPreset(name: 'Crunch', category: 'Aggressive',
    inputGain: 6, outputGain: -4, globalMix: 80, numBands: 3,
    crossovers: [300, 3000, 8000, 12000, 16000],
    bands: [(12, 4, 0, 90), (18, 4, 10, 80), (8, 3, -10, 60)]),
  _SatPreset(name: 'Fuzz Box', category: 'Aggressive',
    inputGain: 8, outputGain: -6, globalMix: 100, numBands: 2,
    crossovers: [500, 4000, 8000, 12000, 16000],
    bands: [(24, 5, -20, 100), (20, 5, 0, 80)]),
  _SatPreset(name: 'Distortion', category: 'Aggressive',
    inputGain: 10, outputGain: -8, globalMix: 90, numBands: 2,
    crossovers: [400, 4000, 8000, 12000, 16000],
    bands: [(30, 4, 10, 100), (22, 4, -10, 80)]),
  // ── Creative ──
  _SatPreset(name: 'Lo-Fi Vinyl', category: 'Creative',
    inputGain: 0, outputGain: 0, globalMix: 50, numBands: 3,
    crossovers: [200, 6000, 8000, 12000, 16000],
    bands: [(8, 0, 30, 60), (4, 3, 0, 40), (2, 3, -40, 30)]),
  _SatPreset(name: 'Bitcrusher', category: 'Creative',
    inputGain: 4, outputGain: -3, globalMix: 70, numBands: 2,
    crossovers: [1000, 4000, 8000, 12000, 16000],
    bands: [(20, 5, 0, 80), (16, 5, 20, 60)]),
  _SatPreset(name: 'Parallel Warmth', category: 'Creative',
    inputGain: 0, outputGain: 0, globalMix: 30, numBands: 4,
    crossovers: [150, 800, 5000, 12000, 16000],
    bands: [(12, 0, 20, 100), (8, 1, 5, 80), (6, 2, 0, 60), (3, 3, -10, 40)]),
  // ── Drums ──
  _SatPreset(name: 'Drum Punch', category: 'Drums',
    inputGain: 3, outputGain: -2, globalMix: 70, numBands: 3,
    crossovers: [250, 5000, 8000, 12000, 16000],
    bands: [(10, 4, 0, 80), (6, 2, 10, 60), (4, 3, -5, 50)]),
  _SatPreset(name: 'Kick Thump', category: 'Drums',
    inputGain: 4, outputGain: -3, globalMix: 80, numBands: 2,
    crossovers: [300, 4000, 8000, 12000, 16000],
    bands: [(14, 0, 30, 90), (2, 3, -20, 30)]),
  // ── Bass ──
  _SatPreset(name: 'Bass Growl', category: 'Bass',
    inputGain: 5, outputGain: -4, globalMix: 70, numBands: 3,
    crossovers: [150, 2000, 8000, 12000, 16000],
    bands: [(4, 0, 20, 60), (16, 4, 10, 90), (3, 3, -10, 40)]),
  _SatPreset(name: 'Sub Warmth', category: 'Bass',
    inputGain: 2, outputGain: -1, globalMix: 50, numBands: 2,
    crossovers: [200, 4000, 8000, 12000, 16000],
    bands: [(6, 1, 30, 70), (8, 2, 0, 60)]),
  // ── Master ──
  _SatPreset(name: 'Bus Glue', category: 'Master',
    inputGain: 0, outputGain: -1, globalMix: 30, numBands: 3,
    crossovers: [300, 4000, 8000, 12000, 16000],
    bands: [(3, 0, 10, 50), (2, 1, 0, 40), (1, 3, -5, 30)]),
  _SatPreset(name: 'Master Tape', category: 'Master',
    inputGain: 0, outputGain: -2, globalMix: 40, numBands: 2,
    crossovers: [600, 4000, 8000, 12000, 16000],
    bands: [(5, 0, 15, 60), (3, 0, -10, 40)]),
  _SatPreset(name: 'Loud & Proud', category: 'Master',
    inputGain: 4, outputGain: -3, globalMix: 60, numBands: 3,
    crossovers: [200, 5000, 8000, 12000, 16000],
    bands: [(8, 0, 20, 80), (6, 4, 5, 70), (4, 3, -15, 50)]),
];

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class SaturationSnapshot implements DspParameterSnapshot {
  final double inputGain, outputGain, globalMix;
  final bool msMode;
  final int numBands, crossoverType;
  final List<double> crossovers;
  final List<SaturationBandState> bands;

  const SaturationSnapshot({
    required this.inputGain, required this.outputGain, required this.globalMix,
    required this.msMode, required this.numBands, required this.crossoverType,
    required this.crossovers, required this.bands,
  });

  @override
  SaturationSnapshot copy() => SaturationSnapshot(
    inputGain: inputGain, outputGain: outputGain, globalMix: globalMix,
    msMode: msMode, numBands: numBands, crossoverType: crossoverType,
    crossovers: List.of(crossovers),
    bands: bands.map((b) => b.copy()).toList(),
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! SaturationSnapshot) return false;
    return inputGain == other.inputGain && outputGain == other.outputGain &&
        numBands == other.numBands && crossoverType == other.crossoverType;
  }
}

class SaturationBandState {
  double drive, tone, mix, output, dynamics;
  int type;
  bool solo, mute, bypass;

  SaturationBandState({
    this.drive = 0, this.type = 0, this.tone = 0, this.mix = 100,
    this.output = 0, this.dynamics = 0, this.solo = false,
    this.mute = false, this.bypass = false,
  });

  SaturationBandState copy() => SaturationBandState(
    drive: drive, type: type, tone: tone, mix: mix,
    output: output, dynamics: dynamics, solo: solo, mute: mute, bypass: bypass,
  );

  SaturationBandState copyWith({
    double? drive, int? type, double? tone, double? mix,
    double? output, double? dynamics, bool? solo, bool? mute, bool? bypass,
  }) => SaturationBandState(
    drive: drive ?? this.drive, type: type ?? this.type,
    tone: tone ?? this.tone, mix: mix ?? this.mix,
    output: output ?? this.output, dynamics: dynamics ?? this.dynamics,
    solo: solo ?? this.solo, mute: mute ?? this.mute, bypass: bypass ?? this.bypass,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterSaturationPanel extends FabFilterPanelBase {
  const FabFilterSaturationPanel({
    super.key,
    required super.trackId,
    super.slotIndex,
  }) : super(
          title: 'FF-SAT',
          icon: Icons.whatshot,
          accentColor: FabFilterColors.orange,
          nodeType: DspNodeType.multibandSaturation,
        );

  @override
  State<FabFilterSaturationPanel> createState() => _FabFilterSaturationPanelState();
}

class _FabFilterSaturationPanelState extends State<FabFilterSaturationPanel>
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
  final List<SaturationBandState> _bands = List.generate(6, (_) => SaturationBandState());
  int _selectedBand = 0;

  // ─── METERING ─────────────────────────────────────────────────────
  double _inL = 0, _inR = 0, _outL = 0, _outR = 0;
  final List<double> _bandPeaks = List.filled(6, 0.0);

  // ─── ENGINE ───────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ──────────────────────────────────────────────────────────
  SaturationSnapshot? _snapshotA;
  SaturationSnapshot? _snapshotB;

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
    // Use slotIndex directly when passed from insert editor window
    if (widget.slotIndex >= 0) {
      _slotIndex = widget.slotIndex;
      final dsp = DspChainProvider.instance;
      final chain = dsp.getChain(widget.trackId);
      if (_slotIndex < chain.nodes.length) {
        _nodeId = chain.nodes[_slotIndex].id;
      }
      _initialized = true;
      _readParams();
      return;
    }
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.multibandSaturation) {
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
      _msMode = _ffi.insertGetParam(t, s, _P.msMode) > 0.5;
      _numBands = _ffi.insertGetParam(t, s, _P.numBands).round().clamp(2, 6);
      _crossoverType = _ffi.insertGetParam(t, s, _P.crossoverType).round().clamp(0, 2);
      for (int i = 0; i < 5; i++) {
        _crossovers[i] = _ffi.insertGetParam(t, s, _P.crossover1 + i);
      }
      for (int b = 0; b < 6; b++) {
        _bands[b]
          ..drive = _ffi.insertGetParam(t, s, _P.band(b, _P.bDrive))
          ..type = _ffi.insertGetParam(t, s, _P.band(b, _P.bType)).round().clamp(0, 5)
          ..tone = _ffi.insertGetParam(t, s, _P.band(b, _P.bTone))
          ..mix = _ffi.insertGetParam(t, s, _P.band(b, _P.bMix))
          ..output = _ffi.insertGetParam(t, s, _P.band(b, _P.bOutput))
          ..dynamics = _ffi.insertGetParam(t, s, _P.band(b, _P.bDynamics))
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

  SaturationSnapshot _snap() => SaturationSnapshot(
    inputGain: _inputGain, outputGain: _outputGain, globalMix: _globalMix,
    msMode: _msMode, numBands: _numBands, crossoverType: _crossoverType,
    crossovers: List.of(_crossovers),
    bands: _bands.map((b) => b.copy()).toList(),
  );

  void _restore(SaturationSnapshot s) {
    setState(() {
      _inputGain = s.inputGain; _outputGain = s.outputGain;
      _globalMix = s.globalMix; _msMode = s.msMode;
      _numBands = s.numBands; _crossoverType = s.crossoverType;
      for (int i = 0; i < 5; i++) _crossovers[i] = s.crossovers[i];
      for (int b = 0; b < 6; b++) {
        final src = s.bands[b];
        _bands[b]
          ..drive = src.drive ..type = src.type ..tone = src.tone
          ..mix = src.mix ..output = src.output ..dynamics = src.dynamics
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
    for (int i = 0; i < 5; i++) _setParam(_P.crossover1 + i, _crossovers[i]);
    for (int b = 0; b < 6; b++) {
      final band = _bands[b];
      _setParam(_P.band(b, _P.bDrive), band.drive);
      _setParam(_P.band(b, _P.bType), band.type.toDouble());
      _setParam(_P.band(b, _P.bTone), band.tone);
      _setParam(_P.band(b, _P.bMix), band.mix);
      _setParam(_P.band(b, _P.bOutput), band.output);
      _setParam(_P.band(b, _P.bDynamics), band.dynamics);
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
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId, s = _slotIndex;
    setState(() {
      try {
        _inL = _ffi.insertGetMeter(t, s, 0);
        _inR = _ffi.insertGetMeter(t, s, 1);
        _outL = _ffi.insertGetMeter(t, s, 2);
        _outR = _ffi.insertGetMeter(t, s, 3);
        for (int b = 0; b < 6; b++) {
          _bandPeaks[b] = _ffi.insertGetMeter(t, s, 4 + b);
        }
      } catch (e) {
        assert(() { debugPrint('Saturation meter error: $e'); return true; }());
      }
    });
  }

  // ─── HELPERS ──────────────────────────────────────────────────────

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

  double _linearToDb(double linear) => linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;

  Color get _bandColor => _satTypeColors[_bands[_selectedBand].type];

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('Saturation', DspNodeType.multibandSaturation, widget.trackId, () {
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
          // Band count selector
          const SizedBox(width: 4),
          Text('BANDS', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          const SizedBox(width: 4),
          ...List.generate(5, (i) {
            final count = i + 2; // 2..6
            final active = _numBands == count;
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: FabTinyButton(
                label: '$count',
                active: active,
                color: FabFilterColors.orange,
                onTap: () {
                  setState(() => _numBands = count);
                  _setParam(_P.numBands, count.toDouble());
                },
              ),
            );
          }),
          const SizedBox(width: 8),
          // Band select tabs
          Expanded(
            child: Row(
              children: List.generate(_numBands, (b) {
                final selected = _selectedBand == b;
                final typeColor = _satTypeColors[_bands[b].type];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedBand = b),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                      decoration: BoxDecoration(
                        color: selected ? typeColor.withValues(alpha: 0.25) : FabFilterColors.bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: selected ? typeColor : FabFilterColors.borderSubtle,
                          width: selected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'B${b + 1}',
                          style: TextStyle(
                            color: selected ? typeColor : FabFilterColors.textTertiary,
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
          // Transfer curve (mini)
          SizedBox(
            width: 60,
            child: Column(
              children: [
                const FabSectionLabel('CURVE'),
                const SizedBox(height: 2),
                Expanded(
                  child: Container(
                    decoration: FabFilterDecorations.display(),
                    clipBehavior: Clip.hardEdge,
                    child: CustomPaint(
                      painter: SatTransferCurvePainter(
                        satType: band.type,
                        drive: band.drive,
                        color: _satTypeColors[band.type],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildBandControls(SaturationBandState band) {
    return Column(
      children: [
        // Saturation type selector
        _buildSatTypeSelector(band),
        const SizedBox(height: 8),
        // Knob row
        Expanded(child: _buildKnobRow(band)),
        // Band peak meter
        const SizedBox(height: 4),
        _buildBandPeakMeter(),
      ],
    );
  }

  Widget _buildSatTypeSelector(SaturationBandState band) {
    return SizedBox(
      height: 22,
      child: Row(
        children: List.generate(6, (i) {
          final active = band.type == i;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: GestureDetector(
                onTap: () {
                  setState(() => band.type = i);
                  _setParam(_P.band(_selectedBand, _P.bType), i.toDouble());
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: active ? _satTypeColors[i].withValues(alpha: 0.25) : FabFilterColors.bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: active ? _satTypeColors[i] : FabFilterColors.borderSubtle,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _satTypeLabels[i],
                      style: TextStyle(
                        color: active ? _satTypeColors[i] : FabFilterColors.textTertiary,
                        fontSize: 8, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildKnobRow(SaturationBandState band) {
    final color = _bandColor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // DRIVE
        _buildKnob(
          label: 'DRIVE',
          display: _dbStr(band.drive),
          value: ((band.drive + 24.0) / 76.0).clamp(0.0, 1.0),
          color: color,
          defaultValue: 24.0 / 76.0,
          onChanged: (v) {
            final db = v * 76.0 - 24.0;
            setState(() => band.drive = db);
            _setParam(_P.band(_selectedBand, _P.bDrive), db);
          },
        ),
        // TONE
        _buildKnob(
          label: 'TONE',
          display: band.tone.toStringAsFixed(0),
          value: ((band.tone + 100.0) / 200.0).clamp(0.0, 1.0),
          color: FabFilterColors.cyan,
          defaultValue: 0.5,
          onChanged: (v) {
            final tone = v * 200.0 - 100.0;
            setState(() => band.tone = tone);
            _setParam(_P.band(_selectedBand, _P.bTone), tone);
          },
        ),
        // MIX
        _buildKnob(
          label: 'MIX',
          display: _pctStr(band.mix),
          value: (band.mix / 100.0).clamp(0.0, 1.0),
          color: FabFilterColors.blue,
          defaultValue: 1.0,
          onChanged: (v) {
            final pct = v * 100.0;
            setState(() => band.mix = pct);
            _setParam(_P.band(_selectedBand, _P.bMix), pct);
          },
        ),
        // OUTPUT
        _buildKnob(
          label: 'OUTPUT',
          display: _dbStr(band.output),
          value: ((band.output + 24.0) / 48.0).clamp(0.0, 1.0),
          color: FabFilterColors.green,
          defaultValue: 0.5,
          onChanged: (v) {
            final db = v * 48.0 - 24.0;
            setState(() => band.output = db);
            _setParam(_P.band(_selectedBand, _P.bOutput), db);
          },
        ),
        // DYNAMICS
        _buildKnob(
          label: 'DYN',
          display: band.dynamics.toStringAsFixed(2),
          value: ((band.dynamics + 1.0) / 2.0).clamp(0.0, 1.0),
          color: FabFilterColors.purple,
          defaultValue: 0.5,
          onChanged: (v) {
            final dyn = v * 2.0 - 1.0;
            setState(() => band.dynamics = dyn);
            _setParam(_P.band(_selectedBand, _P.bDynamics), dyn);
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
    return FabFilterKnob(
      value: value,
      label: label,
      display: display,
      color: color,
      size: 48,
      defaultValue: defaultValue,
      onChanged: onChanged,
    );
  }

  Widget _buildBandPeakMeter() {
    final peak = _bandPeaks[_selectedBand.clamp(0, 5)];
    final db = _linearToDb(peak);
    final norm = ((db + 60.0) / 60.0).clamp(0.0, 1.0);
    return FabHorizontalMeter(
      label: 'PK',
      value: norm,
      color: _bandColor,
      height: 10,
      displayText: '${db.toStringAsFixed(1)}',
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
        FabMiniSlider(
          label: 'IN',
          value: ((_inputGain + 24.0) / 48.0).clamp(0.0, 1.0),
          display: _dbStr(_inputGain),
          activeColor: FabFilterColors.cyan,
          onChanged: (v) {
            final db = v * 48.0 - 24.0;
            setState(() => _inputGain = db);
            _setParam(_P.inputGain, db);
          },
        ),
        const SizedBox(height: 2),
        // Output Gain
        FabMiniSlider(
          label: 'OUT',
          value: ((_outputGain + 24.0) / 48.0).clamp(0.0, 1.0),
          display: _dbStr(_outputGain),
          activeColor: FabFilterColors.green,
          onChanged: (v) {
            final db = v * 48.0 - 24.0;
            setState(() => _outputGain = db);
            _setParam(_P.outputGain, db);
          },
        ),
        const SizedBox(height: 2),
        // Global Mix
        FabMiniSlider(
          label: 'MIX',
          value: (_globalMix / 100.0).clamp(0.0, 1.0),
          display: _pctStr(_globalMix),
          activeColor: FabFilterColors.blue,
          onChanged: (v) {
            final pct = v * 100.0;
            setState(() => _globalMix = pct);
            _setParam(_P.globalMix, pct);
          },
        ),
        const SizedBox(height: 6),
        // M/S toggle
        FabCompactToggle(
          label: 'M/S',
          active: _msMode,
          color: FabFilterColors.purple,
          onToggle: () {
            setState(() => _msMode = !_msMode);
            _setParam(_P.msMode, _msMode ? 1 : 0);
          },
        ),
        const SizedBox(height: 6),
        // Crossover type
        const FabSectionLabel('CROSSOVER'),
        const SizedBox(height: 2),
        FabEnumSelector(
          label: 'XO',
          value: _crossoverType,
          options: _crossoverLabels,
          color: FabFilterColors.yellow,
          onChanged: (v) {
            setState(() => _crossoverType = v);
            _setParam(_P.crossoverType, v.toDouble());
          },
        ),
        const SizedBox(height: 6),
        // Crossover frequencies
        if (showExpertMode) ..._buildCrossoverSliders(),
      ],
    );
  }

  List<Widget> _buildCrossoverSliders() {
    final crossoverCount = _numBands - 1;
    return List.generate(crossoverCount.clamp(0, 5), (i) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: FabMiniSlider(
          label: 'F${i + 1}',
          value: _logNorm(_crossovers[i], 20, 20000),
          display: _freqStr(_crossovers[i]),
          activeColor: FabFilterColors.yellow,
          onChanged: (v) {
            final freq = _logDenorm(v, 20, 20000);
            setState(() => _crossovers[i] = freq);
            _setParam(_P.crossover1 + i, freq);
          },
        ),
      );
    });
  }

  // ─── BAND STRIP (Solo / Mute / Bypass) ────────────────────────────

  Widget _buildBandStrip() {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: List.generate(_numBands, (b) {
          final band = _bands[b];
          final isSelected = _selectedBand == b;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Solo
                  _buildStripToggle('S', band.solo, FabFilterColors.yellow, () {
                    setState(() => band.solo = !band.solo);
                    _setParam(_P.band(b, _P.bSolo), band.solo ? 1 : 0);
                  }),
                  const SizedBox(width: 2),
                  // Mute
                  _buildStripToggle('M', band.mute, FabFilterColors.red, () {
                    setState(() => band.mute = !band.mute);
                    _setParam(_P.band(b, _P.bMute), band.mute ? 1 : 0);
                  }),
                  const SizedBox(width: 2),
                  // Bypass
                  _buildStripToggle('B', band.bypass, FabFilterColors.orange, () {
                    setState(() => band.bypass = !band.bypass);
                    _setParam(_P.band(b, _P.bBypass), band.bypass ? 1 : 0);
                  }),
                  // Band number indicator
                  if (isSelected) ...[
                    const SizedBox(width: 3),
                    Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: _satTypeColors[band.type],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStripToggle(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 16, height: 16,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? color : FabFilterColors.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: active ? color : FabFilterColors.textDisabled,
            fontSize: 7, fontWeight: FontWeight.bold,
          )),
        ),
      ),
    );
  }

  // ─── FOOTER ───────────────────────────────────────────────────────

  Widget _buildFooter() {
    final inDb = _linearToDb(math.max(_inL, _inR));
    final outDb = _linearToDb(math.max(_outL, _outR));
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('IN ${inDb.toStringAsFixed(1)} dB',
            style: FabFilterText.paramLabel.copyWith(fontSize: 8, color: FabFilterColors.cyan),
            overflow: TextOverflow.ellipsis),
          const SizedBox(width: 12),
          Text('OUT ${outDb.toStringAsFixed(1)} dB',
            style: FabFilterText.paramLabel.copyWith(fontSize: 8, color: FabFilterColors.green),
            overflow: TextOverflow.ellipsis),
          const Spacer(),
          Text('${_satTypeLabels[_bands[_selectedBand].type]} | B${_selectedBand + 1}/${_numBands}',
            style: FabFilterText.paramLabel.copyWith(fontSize: 8, color: _bandColor),
            overflow: TextOverflow.ellipsis),
          const SizedBox(width: 8),
          _buildPresetButton(),
        ],
      ),
    );
  }

  Widget _buildPresetButton() {
    final categories = <String, List<_SatPreset>>{};
    for (final p in _kSatPresets) {
      categories.putIfAbsent(p.category, () => []).add(p);
    }
    return PopupMenuButton<_SatPreset>(
      onSelected: _loadPreset,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 120),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<_SatPreset>>[];
        for (final entry in categories.entries) {
          items.add(PopupMenuItem<_SatPreset>(
            enabled: false, height: 22,
            child: Text(entry.key.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                color: FabFilterColors.orange.withValues(alpha: 0.6))),
          ));
          for (final p in entry.value) {
            items.add(PopupMenuItem(value: p, height: 28,
              child: Text(p.name, style: const TextStyle(fontSize: 11))));
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FabFilterColors.borderMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 9, color: FabFilterColors.textTertiary),
            const SizedBox(width: 2),
            Text('PRESET', style: TextStyle(
              color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _loadPreset(_SatPreset p) {
    setState(() {
      _inputGain = p.inputGain;
      _outputGain = p.outputGain;
      _globalMix = p.globalMix;
      _numBands = p.numBands;
      _crossoverType = p.crossoverType;
      for (var i = 0; i < 5; i++) {
        _crossovers[i] = p.crossovers[i];
      }
      for (var b = 0; b < p.bands.length && b < 6; b++) {
        final (drive, type, tone, mix) = p.bands[b];
        _bands[b] = _bands[b].copyWith(
          drive: drive, type: type, tone: tone, mix: mix,
        );
      }
    });
    _applyAll();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSFER CURVE PAINTER — Shows waveshaper shape per type (S6)
// ═══════════════════════════════════════════════════════════════════════════

class SatTransferCurvePainter extends CustomPainter {
  final int satType; // 0-5
  final double drive; // dB
  final Color color;

  SatTransferCurvePainter({
    required this.satType,
    required this.drive,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Glass background
    canvas.drawRect(Offset.zero & size, Paint()
      ..color = const Color(0xFF0D0D12));

    // Grid: ±1 range
    final gridPaint = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), gridPaint);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), gridPaint);
    // Diagonal (1:1 line)
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0),
      Paint()..color = const Color(0xFF222230)..strokeWidth = 0.5);

    final driveLinear = math.pow(10, drive / 20).toDouble();
    final path = Path();
    const steps = 100;

    for (var i = 0; i <= steps; i++) {
      final input = (i / steps) * 2.0 - 1.0; // -1 to +1
      final driven = input * driveLinear;
      final output = _waveshape(driven, satType);
      final x = (i / steps) * size.width;
      final y = size.height * (1 - (output + 1) / 2);
      final yc = y.clamp(0.0, size.height);
      if (i == 0) path.moveTo(x, yc); else path.lineTo(x, yc);
    }

    // Fill under curve
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()
      ..color = color.withValues(alpha: 0.08));

    // Curve stroke
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke);
  }

  double _waveshape(double x, int type) {
    return switch (type) {
      0 => _tape(x),
      1 => _tube(x),
      2 => _transistor(x),
      3 => _softClip(x),
      4 => _hardClip(x),
      5 => _foldback(x),
      _ => x.clamp(-1.0, 1.0),
    };
  }

  double _tape(double x) {
    // Tape: asymmetric tanh with 2nd harmonic
    final s = x.sign;
    final a = x.abs();
    return s * (a / (1 + 0.3 * a)).clamp(-1.0, 1.0) + 0.05 * x * x.abs().clamp(0, 1);
  }

  double _tube(double x) {
    // Tube: warm asymmetric, even harmonics
    if (x >= 0) {
      return (1 - math.exp(-x)).clamp(-1.0, 1.0);
    } else {
      return (-0.8 * (1 - math.exp(x))).clamp(-1.0, 1.0);
    }
  }

  double _transistor(double x) {
    // Transistor: symmetric cubic soft
    return (1.5 * x - 0.5 * x * x * x).clamp(-1.0, 1.0);
  }

  double _softClip(double x) {
    // Soft clip: tanh
    return (x / (1 + x.abs())).clamp(-1.0, 1.0);
  }

  double _hardClip(double x) => x.clamp(-1.0, 1.0);

  double _foldback(double x) {
    // Foldback distortion
    var y = x;
    while (y > 1 || y < -1) {
      if (y > 1) y = 2 - y;
      if (y < -1) y = -2 - y;
    }
    return y;
  }

  @override
  bool shouldRepaint(covariant SatTransferCurvePainter old) =>
      old.satType != satType || old.drive != drive || old.color != color;
}
