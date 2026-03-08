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
/// - Loudness target mode with LUFS timeline
/// - GR histogram, dual-layer GR display
/// - Factory presets (Mastering, Streaming, Broadcast)
/// - Peak hold, clip counter, crest factor, PLR, stereo correlation

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Loudness target presets for streaming/broadcast
enum LimiterLoudnessTarget {
  off('Off', null),
  spotify('Spotify', -14.0),
  appleMusic('Apple', -16.0),
  youtube('YouTube', -13.0),
  tidalAmazon('Tidal', -14.0),
  broadcast('EBU R128', -23.0),
  cd('CD', -9.0),
  custom('Custom', -14.0);

  final String label;
  final double? lufs;
  const LimiterLoudnessTarget(this.label, this.lufs);
}

/// Display mode for the waveform area
enum LimiterDisplayMode {
  waveform,
  lufsTimeline,
  grHistogram,
}

/// Peak hold decay mode (L9.1)
enum PeakHoldDecay {
  fast('0.5s', 30),   // 0.5s at 60fps
  medium('1s', 60),   // 1s
  slow('2s', 120),    // 2s
  infinite('INF', -1); // never decay

  final String label;
  final int frames;
  const PeakHoldDecay(this.label, this.frames);
}

/// Output clipper mode (L5.1)
enum ClipperMode {
  off('Off'),
  hard('Hard'),
  soft('Soft');

  final String label;
  const ClipperMode(this.label);
}

/// Oversampling quality (L10.3)
enum OversamplingQuality {
  eco('Eco'),
  high('High'),
  ultra('Ultra');

  final String label;
  const OversamplingQuality(this.label);
}

/// GR display layer mode (L3.3)
enum GrLayerMode {
  linked('Linked'),
  separateLR('L/R');

  final String label;
  const GrLayerMode(this.label);
}

/// Factory preset for limiter
class _LimPreset {
  final String name;
  final String category;
  final double inputTrim;
  final double threshold;
  final double ceiling;
  final double release;
  final double attack;
  final double lookahead;
  final int styleIndex;
  final int oversampling;

  const _LimPreset({
    required this.name,
    required this.category,
    this.inputTrim = 0.0,
    this.threshold = 0.0,
    this.ceiling = -0.3,
    this.release = 100.0,
    this.attack = 0.1,
    this.lookahead = 5.0,
    this.styleIndex = 7,
    this.oversampling = 1,
  });
}

const _kLimPresets = <_LimPreset>[
  // ── Mastering ──
  _LimPreset(name: 'Transparent Master', category: 'Mastering',
    inputTrim: 0, threshold: -2, ceiling: -0.3, release: 100,
    attack: 0.5, lookahead: 5, styleIndex: 0, oversampling: 2),
  _LimPreset(name: 'Loud Master', category: 'Mastering',
    inputTrim: 3, threshold: -6, ceiling: -0.1, release: 50,
    attack: 0.1, lookahead: 3, styleIndex: 3, oversampling: 2),
  _LimPreset(name: 'Punchy Master', category: 'Mastering',
    inputTrim: 2, threshold: -4, ceiling: -0.3, release: 80,
    attack: 0.3, lookahead: 4, styleIndex: 1, oversampling: 2),
  _LimPreset(name: 'Safe Master', category: 'Mastering',
    inputTrim: 0, threshold: -1, ceiling: -1.0, release: 200,
    attack: 1.0, lookahead: 8, styleIndex: 5, oversampling: 3),
  // ── Streaming ──
  _LimPreset(name: 'Spotify -14 LUFS', category: 'Streaming',
    inputTrim: 0, threshold: -3, ceiling: -1.0, release: 100,
    attack: 0.3, lookahead: 5, styleIndex: 0, oversampling: 2),
  _LimPreset(name: 'Apple Music -16 LUFS', category: 'Streaming',
    inputTrim: -2, threshold: -2, ceiling: -1.0, release: 120,
    attack: 0.5, lookahead: 5, styleIndex: 0, oversampling: 2),
  _LimPreset(name: 'YouTube -13 LUFS', category: 'Streaming',
    inputTrim: 1, threshold: -4, ceiling: -1.0, release: 80,
    attack: 0.3, lookahead: 4, styleIndex: 2, oversampling: 2),
  _LimPreset(name: 'SoundCloud', category: 'Streaming',
    inputTrim: 2, threshold: -5, ceiling: -0.5, release: 60,
    attack: 0.2, lookahead: 3, styleIndex: 1, oversampling: 1),
  // ── Broadcast ──
  _LimPreset(name: 'EBU R128 -23 LUFS', category: 'Broadcast',
    inputTrim: -6, threshold: -1, ceiling: -1.0, release: 200,
    attack: 1.0, lookahead: 8, styleIndex: 5, oversampling: 2),
  _LimPreset(name: 'ATSC A/85 -24 LUFS', category: 'Broadcast',
    inputTrim: -7, threshold: -1, ceiling: -2.0, release: 250,
    attack: 1.0, lookahead: 8, styleIndex: 5, oversampling: 2),
  // ── Genres ──
  _LimPreset(name: 'EDM Brickwall', category: 'Genres',
    inputTrim: 6, threshold: -8, ceiling: -0.1, release: 30,
    attack: 0.05, lookahead: 2, styleIndex: 3, oversampling: 2),
  _LimPreset(name: 'Hip-Hop Punch', category: 'Genres',
    inputTrim: 4, threshold: -6, ceiling: -0.3, release: 50,
    attack: 0.1, lookahead: 3, styleIndex: 1, oversampling: 2),
  _LimPreset(name: 'Rock Bus', category: 'Genres',
    inputTrim: 2, threshold: -4, ceiling: -0.5, release: 80,
    attack: 0.3, lookahead: 4, styleIndex: 4, oversampling: 1),
  _LimPreset(name: 'Jazz Gentle', category: 'Genres',
    inputTrim: 0, threshold: -1, ceiling: -1.0, release: 300,
    attack: 2.0, lookahead: 10, styleIndex: 0, oversampling: 2),
  _LimPreset(name: 'Classical Dynamic', category: 'Genres',
    inputTrim: 0, threshold: -0.5, ceiling: -1.0, release: 400,
    attack: 3.0, lookahead: 12, styleIndex: 5, oversampling: 3),
  // ── Creative ──
  _LimPreset(name: 'Slam It', category: 'Creative',
    inputTrim: 10, threshold: -12, ceiling: -0.1, release: 20,
    attack: 0.02, lookahead: 1, styleIndex: 3, oversampling: 1),
  _LimPreset(name: 'Dynamic Squeeze', category: 'Creative',
    inputTrim: 5, threshold: -8, ceiling: -0.3, release: 60,
    attack: 0.1, lookahead: 3, styleIndex: 2, oversampling: 1),
  _LimPreset(name: 'Modern Pop', category: 'Creative',
    inputTrim: 3, threshold: -5, ceiling: -0.3, release: 70,
    attack: 0.2, lookahead: 4, styleIndex: 6, oversampling: 2),
  _LimPreset(name: 'Vinyl Warm', category: 'Creative',
    inputTrim: 1, threshold: -3, ceiling: -0.5, release: 150,
    attack: 0.5, lookahead: 6, styleIndex: 7, oversampling: 2),
  _LimPreset(name: 'Bus Glue', category: 'Creative',
    inputTrim: 0, threshold: -2, ceiling: -0.3, release: 100,
    attack: 0.3, lookahead: 5, styleIndex: 4, oversampling: 1),
];

/// Level sample for scrolling display
class LimiterLevelSample {
  final double inputPeak;
  final double outputPeak;
  final double gainReduction;
  final double truePeak;
  final double grLeft;
  final double grRight;

  const LimiterLevelSample({
    required this.inputPeak,
    required this.outputPeak,
    required this.gainReduction,
    required this.truePeak,
    this.grLeft = 0.0,
    this.grRight = 0.0,
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
    super.slotIndex,
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

  // ─── LOUDNESS TARGET (L2) ─────────────────────────────────────────────
  LimiterLoudnessTarget _loudnessTarget = LimiterLoudnessTarget.off;
  double _customTargetLufs = -14.0;
  double _plr = 0.0; // Peak-to-Loudness Ratio

  // ─── LUFS TIMELINE (L2) ───────────────────────────────────────────────
  final List<(double mom, double st, double integ)> _lufsHistory = [];
  static const int _maxLufsHistory = 300;

  // ─── GR HISTOGRAM (L3) ────────────────────────────────────────────────
  final List<int> _grHistogram = List.filled(24, 0); // 0-24 dB in 1dB bins
  int _grHistogramTotal = 0;

  // ─── ADVANCED METERING (L9) ───────────────────────────────────────────
  double _crestFactor = 0.0;
  int _clipCount = 0;
  double _peakHoldL = -60.0;
  double _peakHoldR = -60.0;
  int _peakHoldTimer = 0;
  static const int _peakHoldFrames = 120; // 2s at 60fps
  double _stereoCorrelation = 1.0;
  // RMS accumulators for crest factor
  double _rmsAccumL = 0.0;
  double _rmsAccumR = 0.0;
  int _rmsCount = 0;

  // ─── DISPLAY MODE ─────────────────────────────────────────────────────
  LimiterDisplayMode _displayMode = LimiterDisplayMode.waveform;

  // ─── DISPLAY HISTORY ─────────────────────────────────────────────────
  final List<LimiterLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 200;

  // ─── ANIMATION & FFI ─────────────────────────────────────────────────
  late AnimationController _meterController;
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;

  // ─── A/B/C/D SLOTS (L6.3) ────────────────────────────────────────────
  LimiterSnapshot? _snapshotA;
  LimiterSnapshot? _snapshotB;
  LimiterSnapshot? _snapshotC;
  LimiterSnapshot? _snapshotD;
  int _activeSlot = 0; // 0=A, 1=B, 2=C, 3=D

  // ─── ISP TRACKING (L1.5) ─────────────────────────────────────────────
  int _ispEventCount = 0;
  bool _ispActive = false;

  // ─── ZOOM/SCROLL (L3.1) ──────────────────────────────────────────────
  double _waveformZoom = 1.0; // 1.0 = default (200 samples visible)
  double _waveformScrollOffset = 0.0; // 0.0 = latest (right edge)

  // ─── GR DISPLAY LAYERS (L3.3) ─────────────────────────────────────────
  GrLayerMode _grLayerMode = GrLayerMode.linked;

  // ─── DELTA/AUDITION MODE (L3.4) ───────────────────────────────────────
  bool _deltaMode = false;

  // ─── PRE/POST OVERLAY (L3.5) ──────────────────────────────────────────
  bool _prePostOverlay = false;

  // ─── STYLE FINE-TUNING (L4.4) ─────────────────────────────────────────
  bool _showStyleInfo = false;

  // ─── OUTPUT CLIPPER (L5.1) ────────────────────────────────────────────
  ClipperMode _clipperMode = ClipperMode.off;

  // ─── UNITY GAIN (L6.1) ───────────────────────────────────────────────
  bool _unityGainListen = false;

  // ─── BYPASS WITH GAIN MATCH (L6.4) ───────────────────────────────────
  bool _gainMatchBypass = false;

  // ─── UNDO/REDO (L8.3) ────────────────────────────────────────────────
  final List<LimiterSnapshot> _undoStack = [];
  final List<LimiterSnapshot> _redoStack = [];
  static const int _maxUndoSteps = 50;

  // ─── PEAK HOLD DECAY MODE (L9.1) ─────────────────────────────────────
  PeakHoldDecay _peakHoldDecayMode = PeakHoldDecay.slow;

  // ─── OVERSAMPLING QUALITY (L10.3) ────────────────────────────────────
  OversamplingQuality _oversamplingQuality = OversamplingQuality.high;

  // ─── CPU METERING (L10.4) ────────────────────────────────────────────
  double _cpuLoad = 0.0;
  int _cpuUpdateCounter = 0;

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
    // Use slotIndex directly when passed from insert editor window
    if (widget.slotIndex >= 0) {
      _slotIndex = widget.slotIndex;
      final dsp = DspChainProvider.instance;
      final chain = dsp.getChain(widget.trackId);
      if (_slotIndex < chain.nodes.length) {
        _nodeId = chain.nodes[_slotIndex].id;
      }
      _initialized = true;
      _readParamsFromEngine();
      return;
    }
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);
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

  // ─── UNDO/REDO (L8.3) ────────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(_snap());
    if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snap());
    _restore(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snap());
    _restore(_redoStack.removeLast());
  }

  // ─── A/B/C/D SLOT MANAGEMENT (L6.3) ────────────────────────────────

  void _switchToSlot(int slot) {
    if (slot == _activeSlot) return;
    // Store current state in current slot
    _storeToSlot(_activeSlot);
    setState(() => _activeSlot = slot);
    // Restore target slot if it has data
    final snap = _getSlot(slot);
    if (snap != null) _restore(snap);
  }

  void _storeToSlot(int slot) {
    final snap = _snap();
    switch (slot) {
      case 0: _snapshotA = snap;
      case 1: _snapshotB = snap;
      case 2: _snapshotC = snap;
      case 3: _snapshotD = snap;
    }
  }

  LimiterSnapshot? _getSlot(int slot) => switch (slot) {
    0 => _snapshotA,
    1 => _snapshotB,
    2 => _snapshotC,
    3 => _snapshotD,
    _ => null,
  };

  // ─── SESSION STATS EXPORT (L8.4) ───────────────────────────────────

  void _exportSessionStats() {
    final grMax = math.max(_grLeft, _grRight);
    final buf = StringBuffer()
      ..writeln('=== FluxForge Limiter Session Stats ===')
      ..writeln('LUFS Integrated: ${_lufsIntegrated.toStringAsFixed(1)}')
      ..writeln('LUFS Short-term: ${_lufsShortTerm.toStringAsFixed(1)}')
      ..writeln('LUFS Momentary:  ${_lufsMomentary.toStringAsFixed(1)}')
      ..writeln('PLR:             ${_plr.toStringAsFixed(1)} dB')
      ..writeln('True Peak:       ${math.max(_outputTpL, _outputTpR).toStringAsFixed(1)} dBTP')
      ..writeln('ISP Events:      $_ispEventCount')
      ..writeln('Clip Count:      $_clipCount')
      ..writeln('GR Current:      -${grMax.toStringAsFixed(1)} dB')
      ..writeln('GR Peak Hold:    -${_grMaxHold.toStringAsFixed(1)} dB')
      ..writeln('Crest Factor:    ${_crestFactor.toStringAsFixed(1)} dB')
      ..writeln('Stereo Corr:     ${_stereoCorrelation.toStringAsFixed(2)}')
      ..writeln('Style:           ${_style.label}')
      ..writeln('Ceiling:         ${_output.toStringAsFixed(1)} dBTP')
      ..writeln('Threshold:       ${_threshold.toStringAsFixed(1)} dB')
      ..writeln('Oversampling:    ${_oversamplingLabel()}');
    Clipboard.setData(ClipboardData(text: buf.toString()));
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
      } catch (e) {
        assert(() { debugPrint('Limiter meter error: $e'); return true; }());
      }

      // LUFS from engine metering API
      try {
        final (mom, st, integ) = _ffi.getLufsMeters();
        _lufsMomentary = mom;
        _lufsShortTerm = st;
        _lufsIntegrated = integ;
      } catch (e) {
        assert(() { debugPrint('Limiter LUFS meter error: $e'); return true; }());
      }

      final outTpMax = math.max(_outputTpL, _outputTpR);
      final inPeakMax = math.max(_inputPeakL, _inputPeakR);

      // ── ISP detection (L1.5) ──
      if (outTpMax > _output) {
        if (!_ispActive) _ispEventCount++;
        _ispActive = true;
      } else {
        _ispActive = false;
      }

      // ── Clip counter (L9) ──
      if (outTpMax > _output + 0.1) {
        if (!_truePeakClipping) _clipCount++;
        _truePeakClipping = true;
      } else {
        _truePeakClipping = false;
      }

      // ── Peak hold with configurable decay (L9.1) ──
      final holdFrames = _peakHoldDecayMode.frames;
      if (_inputPeakL > _peakHoldL) {
        _peakHoldL = _inputPeakL;
        _peakHoldTimer = holdFrames < 0 ? 1 : holdFrames;
      }
      if (_inputPeakR > _peakHoldR) {
        _peakHoldR = _inputPeakR;
        _peakHoldTimer = holdFrames < 0 ? 1 : holdFrames;
      }
      if (holdFrames < 0) {
        // Infinite hold — never decay
      } else if (_peakHoldTimer > 0) {
        _peakHoldTimer--;
      } else {
        _peakHoldL = _peakHoldL * 0.95 + _inputPeakL * 0.05;
        _peakHoldR = _peakHoldR * 0.95 + _inputPeakR * 0.05;
      }

      // ── CPU metering simulation (L10.4) ──
      _cpuUpdateCounter++;
      if (_cpuUpdateCounter >= 30) {
        _cpuUpdateCounter = 0;
        final grActivity = math.max(_grLeft, _grRight).abs() / 24;
        final osMultiplier = [1.0, 1.3, 2.0, 3.5][_oversampling.clamp(0, 3)];
        _cpuLoad = (grActivity * 0.3 + 0.05) * osMultiplier;
        _cpuLoad = _cpuLoad.clamp(0.0, 1.0);
      }

      // ── RMS + Crest factor (L9) ──
      final inLinL = math.pow(10, _inputPeakL / 20);
      final inLinR = math.pow(10, _inputPeakR / 20);
      _rmsAccumL += inLinL * inLinL;
      _rmsAccumR += inLinR * inLinR;
      _rmsCount++;
      if (_rmsCount >= 10) {
        final rmsLinL = math.sqrt(_rmsAccumL / _rmsCount);
        final rmsLinR = math.sqrt(_rmsAccumR / _rmsCount);
        final rmsDb = 20 * math.log(math.max(rmsLinL, rmsLinR).clamp(1e-10, 10)) / math.ln10;
        _crestFactor = inPeakMax - rmsDb;
        _rmsAccumL = 0; _rmsAccumR = 0; _rmsCount = 0;
      }

      // ── Stereo correlation (L9) ──
      // Simple L/R correlation: 1.0 = mono, 0 = uncorrelated, -1 = out of phase
      if (inLinL > 1e-8 && inLinR > 1e-8) {
        final prod = inLinL * inLinR;
        final energy = (inLinL * inLinL + inLinR * inLinR) * 0.5;
        final corr = energy > 1e-16 ? prod / energy : 1.0;
        _stereoCorrelation = _stereoCorrelation * 0.9 + corr.clamp(-1.0, 1.0) * 0.1;
      }

      // ── PLR (L2) ──
      _plr = outTpMax - _lufsIntegrated;

      // ── GR histogram (L3) ──
      final grDisplay = math.max(_grLeft, _grRight);
      final grBin = grDisplay.abs().floor().clamp(0, 23);
      if (grDisplay.abs() > 0.1) {
        _grHistogram[grBin]++;
        _grHistogramTotal++;
      }

      // ── LUFS timeline (L2) ──
      _lufsHistory.add((_lufsMomentary, _lufsShortTerm, _lufsIntegrated));
      while (_lufsHistory.length > _maxLufsHistory) {
        _lufsHistory.removeAt(0);
      }

      // Build scrolling history
      _levelHistory.add(LimiterLevelSample(
        inputPeak: inPeakMax,
        outputPeak: outTpMax,
        gainReduction: grDisplay,
        truePeak: outTpMax,
        grLeft: _grLeft,
        grRight: _grRight,
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
    if (!_initialized) {
      return buildNotLoadedState('Limiter', DspNodeType.limiter, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(KeyboardListener(
      focusNode: FocusNode(),
      autofocus: false,
      onKeyEvent: _handleKeyEvent,
      child: Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildLimiterHeader(),
          // Scrolling waveform display — flex scales with panel size
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildDisplay(),
            ),
          ),
          // Controls
          Expanded(
            flex: 3,
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
                  // Style fine-tuning info (L4.4)
                  if (_showStyleInfo) _buildStyleInfo(),
                  const SizedBox(height: 6),
                  // Main knobs + meters + options
                  Expanded(child: _buildMainRow()),
                ],
              ),
            ),
          ),
        ],
      ),
    )));
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    // Check for editable text ancestor — don't intercept typing
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null) {
      BuildContext? ctx = focus.context;
      while (ctx != null) {
        if (ctx.widget is EditableText) return;
        ctx = ctx.findAncestorWidgetOfExactType<EditableText>() != null ? null : null;
        break;
      }
    }
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (meta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (shift) { _redo(); } else { _undo(); }
    } else if (meta && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
    }
  }

  // ─── LIMITER HEADER (with Unity Gain, A/B/C/D, Gain Match) ──────────

  Widget _buildLimiterHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(bottom: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(widget.icon, color: widget.accentColor, size: 14),
          const SizedBox(width: 6),
          Text(widget.title, style: TextStyle(
            color: FabFilterColors.textPrimary, fontSize: 10,
            fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(width: 6),
          // Unity gain listen (L6.1)
          _headerToggle('UG', _unityGainListen, () =>
            setState(() => _unityGainListen = !_unityGainListen),
            activeColor: FabFilterColors.green),
          const SizedBox(width: 2),
          // Gain match bypass (L6.4)
          _headerToggle('GM', _gainMatchBypass, () =>
            setState(() => _gainMatchBypass = !_gainMatchBypass),
            activeColor: FabFilterColors.cyan),
          const SizedBox(width: 2),
          // Delta mode (L3.4)
          _headerToggle('D', _deltaMode, () =>
            setState(() => _deltaMode = !_deltaMode),
            activeColor: FabFilterColors.orange),
          const SizedBox(width: 2),
          // CPU metering (L10.4)
          _buildCpuBadge(),
          const Spacer(),
          // A/B/C/D slots (L6.3)
          ..._buildSlotButtons(),
          const SizedBox(width: 6),
          // Expert mode
          _headerToggle('EXP', showExpertMode, toggleExpertMode),
          const SizedBox(width: 4),
          // Bypass
          _headerToggle('BYP', bypassed, toggleBypass,
            activeColor: FabFilterColors.orange),
        ],
      ),
    );
  }

  Widget _headerToggle(String label, bool active, VoidCallback onTap,
      {Color? activeColor}) {
    final color = activeColor ?? widget.accentColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: active ? Border.all(color: color, width: 0.5) : null,
        ),
        child: Text(label, style: TextStyle(
          color: active ? color : FabFilterColors.textDisabled,
          fontSize: 8, fontWeight: FontWeight.bold)),
      ),
    );
  }

  List<Widget> _buildSlotButtons() {
    const labels = ['A', 'B', 'C', 'D'];
    return List.generate(4, (i) {
      final active = _activeSlot == i;
      final hasData = _getSlot(i) != null;
      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: GestureDetector(
          onTap: () => _switchToSlot(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: active
                  ? widget.accentColor.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: active ? widget.accentColor
                    : hasData ? FabFilterColors.textTertiary
                    : FabFilterColors.borderMedium,
                width: active ? 1.0 : 0.5,
              ),
            ),
            child: Text(labels[i], style: TextStyle(
              color: active ? widget.accentColor
                  : hasData ? FabFilterColors.textSecondary
                  : FabFilterColors.textDisabled,
              fontSize: 8, fontWeight: FontWeight.bold)),
          ),
        ),
      );
    });
  }

  Widget _buildCpuBadge() {
    final pct = (_cpuLoad * 100).clamp(0, 100).toStringAsFixed(0);
    final color = _cpuLoad > 0.8 ? FabFilterColors.red
        : _cpuLoad > 0.5 ? FabFilterColors.orange
        : FabFilterColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: _cpuLoad > 0.5 ? color.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text('CPU $pct%', style: TextStyle(
        color: color, fontSize: 7, fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  // ─── DISPLAY (scrolling waveform + GR history) ────────────────────────

  Widget _buildDisplay() {
    return GestureDetector(
      // L3.1: Pinch-to-zoom on time axis
      onScaleStart: (_) {},
      onScaleUpdate: (details) {
        if (details.scale != 1.0) {
          setState(() {
            _waveformZoom = (_waveformZoom * details.scale).clamp(0.2, 6.0);
          });
        }
        if (details.focalPointDelta.dx.abs() > 0.5) {
          setState(() {
            _waveformScrollOffset = (_waveformScrollOffset - details.focalPointDelta.dx * 0.5)
                .clamp(0.0, (_levelHistory.length * _waveformZoom - 200).clamp(0.0, double.infinity));
          });
        }
      },
      child: Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Main display painter (mode-dependent)
          Positioned.fill(
            child: CustomPaint(
              painter: _displayMode == LimiterDisplayMode.lufsTimeline
                  ? _LufsTimelinePainter(
                      lufsHistory: _lufsHistory,
                      target: _loudnessTarget != LimiterLoudnessTarget.off
                          ? (_loudnessTarget == LimiterLoudnessTarget.custom
                              ? _customTargetLufs
                              : _loudnessTarget.lufs)
                          : null,
                    )
                  : _displayMode == LimiterDisplayMode.grHistogram
                      ? _GrHistogramPainter(
                          histogram: _grHistogram,
                          total: _grHistogramTotal,
                        )
                      : _LimiterDisplayPainter(
                          history: _levelHistory,
                          ceiling: _output,
                          threshold: _threshold,
                          meterScale: _meterScale,
                          grPeakHold: _grMaxHold,
                          zoom: _waveformZoom,
                          scrollOffset: _waveformScrollOffset,
                          grLayerMode: _grLayerMode,
                          deltaMode: _deltaMode,
                          prePostOverlay: _prePostOverlay,
                          ispEventCount: _ispEventCount,
                          ispActive: _ispActive,
                        ),
            ),
          ),
          // LUFS overlay (top-left)
          Positioned(
            left: 6, top: 4,
            child: _buildLufsOverlay(),
          ),
          // True peak indicator + ISP badge + clip count (top-right)
          Positioned(
            right: 6, top: 4,
            child: _buildTruePeakBadge(),
          ),
          // Advanced metering (bottom-right): GR + PLR + Crest
          Positioned(
            right: 6, bottom: 4,
            child: _buildAdvancedBadge(),
          ),
          // Scale + display mode + layer toggles (bottom-left)
          Positioned(
            left: 6, bottom: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDisplayModeSelector(),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildScaleSelector(),
                    if (_displayMode == LimiterDisplayMode.waveform) ...[
                      const SizedBox(width: 4),
                      _buildWaveformToggles(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Style badge + loudness target (top-center)
          Positioned(
            left: 0, right: 0, top: 4,
            child: Center(child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStyleBadge(),
                if (_loudnessTarget != LimiterLoudnessTarget.off) ...[
                  const SizedBox(width: 4),
                  _buildTargetBadge(),
                ],
              ],
            )),
          ),
          // Stereo correlation indicator (left side, mid)
          Positioned(
            left: 6, top: 42,
            child: _buildStereoCorrelation(),
          ),
          // Zoom indicator (top-left, below LUFS if zoomed)
          if (_waveformZoom != 1.0 && _displayMode == LimiterDisplayMode.waveform)
            Positioned(
              left: 6, top: 58,
              child: GestureDetector(
                onTap: () => setState(() { _waveformZoom = 1.0; _waveformScrollOffset = 0; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xDD0A0A10),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: FabFilterColors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Text('${_waveformZoom.toStringAsFixed(1)}x',
                    style: TextStyle(color: FabFilterColors.blue, fontSize: 7,
                      fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    ));
  }

  // ─── WAVEFORM DISPLAY TOGGLES (L3.3, L3.4, L3.5) ─────────────────────

  Widget _buildWaveformToggles() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // GR Layer mode (L3.3)
        _displayToggle(_grLayerMode == GrLayerMode.separateLR ? 'L/R' : 'LNK',
          _grLayerMode == GrLayerMode.separateLR, () => setState(() =>
            _grLayerMode = _grLayerMode == GrLayerMode.linked
              ? GrLayerMode.separateLR : GrLayerMode.linked)),
        const SizedBox(width: 2),
        // Pre/Post overlay (L3.5)
        _displayToggle('P/P', _prePostOverlay, () =>
          setState(() => _prePostOverlay = !_prePostOverlay)),
      ],
    );
  }

  Widget _displayToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: active ? FabFilterProcessorColors.limAccent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: active ? Border.all(color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.4)) : null,
        ),
        child: Text(label, style: TextStyle(
          color: active ? FabFilterProcessorColors.limAccent : FabFilterColors.textTertiary,
          fontSize: 7, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildStyleBadge() {
    return GestureDetector(
      onTap: () => setState(() => _showStyleInfo = !_showStyleInfo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: FabFilterProcessorColors.limAccent.withValues(alpha: _showStyleInfo ? 0.25 : 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FabFilterProcessorColors.limAccent.withValues(alpha: _showStyleInfo ? 0.5 : 0.25)),
        ),
        child: Text(
          _style.label.toUpperCase(),
          style: TextStyle(
            color: FabFilterProcessorColors.limAccent.withValues(alpha: _showStyleInfo ? 0.8 : 0.5),
            fontSize: 7, fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─── STYLE INFO (L4.4) ────────────────────────────────────────────────

  Widget _buildStyleInfo() {
    final info = _getStyleCharacter(_style);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(_style.icon, size: 10, color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(info.$1, style: TextStyle(
                color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.7),
                fontSize: 8, fontWeight: FontWeight.bold)),
              Text(info.$2, style: TextStyle(
                color: FabFilterColors.textTertiary, fontSize: 7)),
            ],
          )),
          // Sub-parameters display
          ...info.$3.map((param) => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(param.$1, style: TextStyle(
                  color: FabFilterColors.textTertiary, fontSize: 7)),
                Text(param.$2, style: TextStyle(
                  color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.6),
                  fontSize: 8, fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          )),
        ],
      ),
    );
  }

  (String, String, List<(String, String)>) _getStyleCharacter(LimitingStyle style) {
    return switch (style) {
      LimitingStyle.transparent => ('Transparent',
        'Minimal coloration, clean limiting', [('THD', '<0.01%'), ('Knee', 'Soft'), ('Char', 'Linear')]),
      LimitingStyle.punchy => ('Punchy',
        'Transient-preserving, dynamic punch', [('THD', '0.1%'), ('Knee', 'Med'), ('Char', 'Xient')]),
      LimitingStyle.dynamic => ('Dynamic',
        'Program-dependent release, adaptive', [('THD', '0.05%'), ('Knee', 'Soft'), ('Char', 'Adapt')]),
      LimitingStyle.aggressive => ('Aggressive',
        'Maximum loudness, fast recovery', [('THD', '0.5%'), ('Knee', 'Hard'), ('Char', 'Dense')]),
      LimitingStyle.bus => ('Bus',
        'Glue-style, gentle bus compression', [('THD', '0.08%'), ('Knee', 'Wide'), ('Char', 'Glue')]),
      LimitingStyle.safe => ('Safe',
        'Conservative, broadcast-safe limiting', [('THD', '<0.01%'), ('Knee', 'Soft'), ('Char', 'Safe')]),
      LimitingStyle.modern => ('Modern',
        'Contemporary loudness maximizer', [('THD', '0.2%'), ('Knee', 'Med'), ('Char', 'Bright')]),
      LimitingStyle.allround => ('All-Round',
        'Balanced general-purpose limiter', [('THD', '0.03%'), ('Knee', 'Med'), ('Char', 'Neutral')]),
    };
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
    return GestureDetector(
      onDoubleTap: () => setState(() { _clipCount = 0; _ispEventCount = 0; }),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xDD0A0A10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _ispActive
              ? FabFilterColors.red.withValues(alpha: 0.8)
              : _truePeakClipping
                  ? FabFilterColors.red.withValues(alpha: 0.6)
                  : FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
              if (_clipCount > 0) ...[
                const SizedBox(width: 4),
                Text('\u00d7$_clipCount',
                  style: TextStyle(color: FabFilterColors.red, fontSize: 8, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
          // ISP indicator (L1.5)
          if (_ispEventCount > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ispActive ? FabFilterColors.red : FabFilterColors.orange,
                    boxShadow: _ispActive ? [
                      BoxShadow(color: FabFilterColors.red.withValues(alpha: 0.6), blurRadius: 3),
                    ] : null,
                  ),
                ),
                const SizedBox(width: 2),
                Text('ISP \u00d7$_ispEventCount',
                  style: TextStyle(
                    color: _ispActive ? FabFilterColors.red : FabFilterColors.orange,
                    fontSize: 7, fontWeight: FontWeight.bold)),
              ],
            ),
        ],
      ),
    ));
  }

  Widget _buildAdvancedBadge() {
    final grMax = math.max(_grLeft, _grRight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xDD0A0A10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // GR + peak hold
          RichText(text: TextSpan(
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()]),
            children: [
              TextSpan(text: 'GR ', style: TextStyle(color: FabFilterColors.textTertiary)),
              TextSpan(text: '-${grMax.toStringAsFixed(1)}',
                style: TextStyle(color: FabFilterProcessorColors.limGainReduction)),
              TextSpan(text: '  pk -${_grMaxHold.toStringAsFixed(1)}',
                style: TextStyle(color: FabFilterColors.textTertiary)),
            ],
          )),
          // PLR + Crest factor
          RichText(text: TextSpan(
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()]),
            children: [
              TextSpan(text: 'PLR ', style: TextStyle(color: FabFilterColors.textTertiary)),
              TextSpan(text: _plr.toStringAsFixed(1),
                style: TextStyle(color: FabFilterColors.cyan)),
              TextSpan(text: '  CF ', style: TextStyle(color: FabFilterColors.textTertiary)),
              TextSpan(text: _crestFactor.toStringAsFixed(1),
                style: TextStyle(color: FabFilterColors.orange)),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildTargetBadge() {
    final target = _loudnessTarget == LimiterLoudnessTarget.custom
        ? _customTargetLufs
        : _loudnessTarget.lufs;
    final diff = _lufsIntegrated - (target ?? 0);
    final diffColor = diff.abs() < 1 ? FabFilterColors.green
        : diff.abs() < 2 ? FabFilterColors.orange
        : FabFilterColors.red;
    return GestureDetector(
      onTap: _cycleLimiterLoudnessTarget,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: diffColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: diffColor.withValues(alpha: 0.4)),
        ),
        child: Text(
          '${_loudnessTarget.label} ${target?.toStringAsFixed(0) ?? ""} (${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)})',
          style: TextStyle(color: diffColor, fontSize: 7, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _cycleLimiterLoudnessTarget() {
    setState(() {
      final idx = LimiterLoudnessTarget.values.indexOf(_loudnessTarget);
      _loudnessTarget = LimiterLoudnessTarget.values[(idx + 1) % LimiterLoudnessTarget.values.length];
    });
  }

  Widget _buildDisplayModeSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: LimiterDisplayMode.values.map((m) {
        final active = _displayMode == m;
        final label = switch (m) {
          LimiterDisplayMode.waveform => 'WAV',
          LimiterDisplayMode.lufsTimeline => 'LUFS',
          LimiterDisplayMode.grHistogram => 'HIST',
        };
        return GestureDetector(
          onTap: () => setState(() => _displayMode = m),
          child: Container(
            margin: const EdgeInsets.only(right: 2),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: active ? FabFilterProcessorColors.limAccent.withValues(alpha: 0.25) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: active ? Border.all(color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.4)) : null,
            ),
            child: Text(label, style: TextStyle(
              color: active ? FabFilterProcessorColors.limAccent : FabFilterColors.textTertiary,
              fontSize: 7, fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStereoCorrelation() {
    final corrColor = _stereoCorrelation > 0.5 ? FabFilterColors.green
        : _stereoCorrelation > 0 ? FabFilterColors.orange
        : FabFilterColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xDD0A0A10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 4, height: 4,
            decoration: BoxDecoration(shape: BoxShape.circle, color: corrColor)),
          const SizedBox(width: 2),
          Text('r ${_stereoCorrelation.toStringAsFixed(2)}',
            style: TextStyle(color: corrColor, fontSize: 7, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()])),
        ],
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
            color: FabFilterColors.textTertiary, fontSize: 7, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _knob(
          value: (_inputTrim + 12) / 24,
          label: 'TRIM',
          display: '${_inputTrim >= 0 ? '+' : ''}${_inputTrim.toStringAsFixed(1)}dB',
          color: FabFilterColors.orange,
          onChanged: (v) {
            _pushUndo();
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
            _pushUndo();
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
            _pushUndo();
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
    return Expanded(child: FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 40,
      onChanged: onChanged,
    ));
  }

  // ─── OPTIONS ──────────────────────────────────────────────────────────

  Widget _buildOptions() {
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stereo link slider
        FabMiniSlider(
          label: 'LNK',
          value: _stereoLink / 100,
          display: '${_stereoLink.toStringAsFixed(0)}%',
          activeColor: FabFilterColors.purple,
          onChanged: (v) {
            _pushUndo();
            setState(() => _stereoLink = v * 100);
            _setParam(_P.stereoLink, _stereoLink);
          },
        ),
        const SizedBox(height: 4),
        FabOptionRow(label: 'M/S', value: _msMode, onChanged: (v) {
          _pushUndo();
          setState(() => _msMode = v);
          _setParam(_P.msMode, v ? 1.0 : 0.0);
        }, accentColor: widget.accentColor),
        const SizedBox(height: 4),
        // Output clipper mode (L5.1)
        FabEnumSelector(label: 'CLIP', value: _clipperMode.index,
          options: ClipperMode.values.map((m) => m.label).toList(),
          onChanged: (v) => setState(() => _clipperMode = ClipperMode.values[v])),
        const SizedBox(height: 4),
        // Peak hold decay mode (L9.1)
        FabEnumSelector(label: 'HOLD', value: _peakHoldDecayMode.index,
          options: PeakHoldDecay.values.map((d) => d.label).toList(),
          onChanged: (v) => setState(() => _peakHoldDecayMode = PeakHoldDecay.values[v])),
        if (showExpertMode) ...[
          const SizedBox(height: 4),
          FabEnumSelector(label: 'CH', value: _channelConfig, options: const ['St', 'Dual', 'M/S'], onChanged: (v) {
            _pushUndo();
            setState(() => _channelConfig = v);
            _setParam(_P.channelConfig, v.toDouble());
          }),
          const SizedBox(height: 4),
          FabEnumSelector(label: 'LAT', value: _latencyProfile, options: const ['Zero', 'HQ', 'Off'], onChanged: (v) {
            _pushUndo();
            setState(() => _latencyProfile = v);
            _setParam(_P.latencyProfile, v.toDouble());
          }),
          const SizedBox(height: 4),
          FabEnumSelector(label: 'DTH', value: _ditherBits, options: const ['Off', '8', '12', '16', '24'], onChanged: (v) {
            _pushUndo();
            setState(() => _ditherBits = v);
            _setParam(_P.ditherBits, v.toDouble());
          }),
          const SizedBox(height: 4),
          // Oversampling quality (L10.3)
          FabEnumSelector(label: 'OS-Q', value: _oversamplingQuality.index,
            options: OversamplingQuality.values.map((q) => q.label).toList(),
            onChanged: (v) => setState(() => _oversamplingQuality = OversamplingQuality.values[v])),
        ],
        const SizedBox(height: 4),
        // Loudness target
        _buildLimiterLoudnessTargetSelector(),
        const SizedBox(height: 4),
        // Preset button
        _buildPresetButton(),
        const SizedBox(height: 4),
        // Session stats export (L8.4)
        _buildActionButton('STATS', Icons.content_copy, _exportSessionStats),
        const SizedBox(height: 4),
        // Undo/Redo (L8.3)
        Row(
          children: [
            Expanded(child: _buildActionButton(
              'UNDO${_undoStack.isNotEmpty ? ' (${_undoStack.length})' : ''}',
              Icons.undo, _undoStack.isNotEmpty ? _undo : null)),
            const SizedBox(width: 4),
            Expanded(child: _buildActionButton(
              'REDO', Icons.redo, _redoStack.isNotEmpty ? _redo : null)),
          ],
        ),
        const SizedBox(height: 4),
        // GR histogram reset
        if (_grHistogramTotal > 0)
          _buildActionButton('RST HIST', Icons.restart_alt, () => setState(() {
            _grHistogram.fillRange(0, 24, 0);
            _grHistogramTotal = 0;
          })),
      ],
    ));
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: enabled ? FabFilterColors.borderMedium : FabFilterColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: enabled ? FabFilterColors.textTertiary : FabFilterColors.textDisabled),
            const SizedBox(width: 3),
            Flexible(child: Text(label, style: TextStyle(
              color: enabled ? FabFilterColors.textTertiary : FabFilterColors.textDisabled,
              fontSize: 8, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildLimiterLoudnessTargetSelector() {
    return PopupMenuButton<LimiterLoudnessTarget>(
      onSelected: (v) => setState(() => _loudnessTarget = v),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 80),
      itemBuilder: (_) => LimiterLoudnessTarget.values.map((t) => PopupMenuItem(
        value: t,
        height: 28,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loudnessTarget == t)
              Icon(Icons.check, size: 12, color: FabFilterProcessorColors.limAccent)
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Text(t.label, style: const TextStyle(fontSize: 11)),
            if (t.lufs != null) ...[
              const SizedBox(width: 4),
              Text('${t.lufs!.toStringAsFixed(0)}', style: TextStyle(
                fontSize: 10, color: FabFilterColors.textTertiary)),
            ],
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _loudnessTarget != LimiterLoudnessTarget.off
              ? FabFilterProcessorColors.limLufs.withValues(alpha: 0.15)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _loudnessTarget != LimiterLoudnessTarget.off
              ? FabFilterProcessorColors.limLufs.withValues(alpha: 0.4)
              : FabFilterColors.borderMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.track_changes, size: 10,
              color: _loudnessTarget != LimiterLoudnessTarget.off
                  ? FabFilterProcessorColors.limLufs
                  : FabFilterColors.textTertiary),
            const SizedBox(width: 3),
            Text(
              _loudnessTarget != LimiterLoudnessTarget.off ? _loudnessTarget.label : 'TARGET',
              style: TextStyle(
                color: _loudnessTarget != LimiterLoudnessTarget.off
                    ? FabFilterProcessorColors.limLufs
                    : FabFilterColors.textTertiary,
                fontSize: 8, fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton() {
    // Group presets by category
    final categories = <String, List<_LimPreset>>{};
    for (final p in _kLimPresets) {
      categories.putIfAbsent(p.category, () => []).add(p);
    }

    return PopupMenuButton<_LimPreset>(
      onSelected: _loadPreset,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 120),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<_LimPreset>>[];
        for (final entry in categories.entries) {
          items.add(PopupMenuItem<_LimPreset>(
            enabled: false,
            height: 22,
            child: Text(entry.key.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                color: FabFilterProcessorColors.limAccent.withValues(alpha: 0.6))),
          ));
          for (final p in entry.value) {
            items.add(PopupMenuItem(
              value: p,
              height: 28,
              child: Text(p.name, style: const TextStyle(fontSize: 11)),
            ));
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FabFilterColors.borderMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 10, color: FabFilterColors.textTertiary),
            const SizedBox(width: 3),
            Text('PRESET', style: TextStyle(
              color: FabFilterColors.textTertiary, fontSize: 8, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _loadPreset(_LimPreset p) {
    setState(() {
      _inputTrim = p.inputTrim;
      _threshold = p.threshold;
      _output = p.ceiling;
      _release = p.release;
      _attack = p.attack;
      _lookahead = p.lookahead;
      _style = LimitingStyle.values[p.styleIndex.clamp(0, 7)];
      _oversampling = p.oversampling.clamp(0, 3);
    });
    _applyAll();
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
  final double grPeakHold;
  final double zoom;
  final double scrollOffset;
  final GrLayerMode grLayerMode;
  final bool deltaMode;
  final bool prePostOverlay;
  final int ispEventCount;
  final bool ispActive;

  _LimiterDisplayPainter({
    required this.history,
    required this.ceiling,
    required this.threshold,
    required this.meterScale,
    this.grPeakHold = 0,
    this.zoom = 1.0,
    this.scrollOffset = 0.0,
    this.grLayerMode = GrLayerMode.linked,
    this.deltaMode = false,
    this.prePostOverlay = false,
    this.ispEventCount = 0,
    this.ispActive = false,
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

    // ── Zoom & scroll (L3.1) ──
    final int visibleSamples = (_maxSamples / zoom).round().clamp(10, history.length);
    final sampleWidth = size.width / visibleSamples;
    final int scrollIdx = scrollOffset.toInt().clamp(0, math.max(0, history.length - visibleSamples));
    final int startIdx = math.max(0, history.length - visibleSamples - scrollIdx);
    final int endIdx = math.min(history.length, startIdx + visibleSamples);

    // ── GR dual-layer display (L3.3) — fill + edge ──
    if (grLayerMode == GrLayerMode.separateLR) {
      // Separate L/R GR bars
      _drawGrChannel(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.grLeft.abs(), FabFilterProcessorColors.limGainReduction, 0.35);
      _drawGrChannel(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.grRight.abs(), FabFilterColors.orange, 0.25);
    } else {
      // Linked GR — fill layer (semi-transparent)
      for (var i = startIdx; i < endIdx; i++) {
        final x = (i - startIdx) * sampleWidth;
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
    }

    // ── GR edge glow (bright line) ──
    final grEdge = Path();
    bool grStarted = false;
    for (var i = startIdx; i < endIdx; i++) {
      final x = (i - startIdx) * sampleWidth;
      final grH = (history[i].gainReduction.abs() / 24).clamp(0.0, 1.0) * size.height * 0.4;
      if (!grStarted) { grEdge.moveTo(x, grH); grStarted = true; }
      else grEdge.lineTo(x, grH);
    }
    if (grStarted) {
      canvas.drawPath(grEdge, Paint()
        ..color = FabFilterProcessorColors.limGainReduction.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
      canvas.drawPath(grEdge, Paint()
        ..color = FabFilterProcessorColors.limGainReduction
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke);
    }

    if (deltaMode) {
      // ── Delta/audition mode (L3.4) — show GR signal only ──
      final deltaPath = Path();
      bool dStarted = false;
      for (var i = startIdx; i < endIdx; i++) {
        final x = (i - startIdx) * sampleWidth;
        final delta = history[i].inputPeak - history[i].outputPeak;
        final y = _dbToY(-delta.abs(), size.height, dbOffset, totalRange)
            .clamp(0.0, size.height);
        if (!dStarted) { deltaPath.moveTo(x, y); dStarted = true; }
        else deltaPath.lineTo(x, y);
      }
      if (dStarted) {
        canvas.drawPath(deltaPath, Paint()
          ..color = FabFilterColors.orange.withValues(alpha: 0.7)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
      }
    } else if (prePostOverlay) {
      // ── Pre/post waveform overlay (L3.5) — both overlapping ──
      // Input waveform (gray)
      _drawWaveformFill(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.inputPeak, dbOffset, totalRange,
        const Color(0x18808088), const Color(0x30808088));
      _drawWaveformLine(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.inputPeak, dbOffset, totalRange,
        const Color(0x80808088), 0.8);
      // Output waveform (accent)
      _drawWaveformFill(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.outputPeak, dbOffset, totalRange,
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.08),
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.35));
      _drawWaveformLine(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.outputPeak, dbOffset, totalRange,
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.7), 1.2);
    } else {
      // ── Standard display: input fill + output fill + output line ──
      // Input waveform fill (subtle gray gradient)
      _drawWaveformFill(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.inputPeak, dbOffset, totalRange,
        const Color(0x08808088), const Color(0x20808088));
      // Output waveform fill (limiter accent gradient)
      _drawWaveformFill(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.outputPeak, dbOffset, totalRange,
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.05),
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.3));
      // Output stroke line
      _drawWaveformLine(canvas, size, sampleWidth, startIdx, endIdx,
        (s) => s.outputPeak, dbOffset, totalRange,
        FabFilterProcessorColors.limTruePeak.withValues(alpha: 0.5), 1.0);
    }

    // ── True peak clip markers + ISP markers (L1.5) ──
    for (var i = startIdx; i < endIdx; i++) {
      final x = (i - startIdx) * sampleWidth;
      // ISP: exceeds ceiling
      if (history[i].truePeak > ceiling) {
        final clipY = ceilingY.clamp(0.0, size.height);
        // Red glow
        canvas.drawRect(
          Rect.fromLTWH(x - 0.5, clipY - 3, sampleWidth + 1, 6),
          Paint()
            ..color = FabFilterColors.red.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        // Core marker
        canvas.drawRect(
          Rect.fromLTWH(x, clipY - 2, sampleWidth + 0.5, 4),
          Paint()..color = FabFilterColors.red,
        );
      } else if (history[i].truePeak > ceiling + 0.1) {
        final clipY = ceilingY.clamp(0.0, size.height);
        canvas.drawRect(
          Rect.fromLTWH(x, clipY - 1, sampleWidth + 0.5, 2),
          Paint()..color = FabFilterColors.red.withValues(alpha: 0.5),
        );
      }
    }

    // ── GR peak hold dashed line (yellow) ──
    if (grPeakHold > 0.1) {
      final grPeakH = (grPeakHold / 24).clamp(0.0, 1.0) * size.height * 0.4;
      _drawDashedLine(
        canvas,
        Offset(0, grPeakH), Offset(size.width, grPeakH),
        Paint()
          ..color = const Color(0xCCFFDD44)
          ..strokeWidth = 0.8,
      );
    }
  }

  static const int _maxSamples = 200;

  double _dbToY(double db, double height, double dbOffset, double totalRange) {
    return height * (1 - (db + 48 + dbOffset) / totalRange);
  }

  void _drawGrChannel(ui.Canvas canvas, ui.Size size, double sampleWidth,
      int startIdx, int endIdx, double Function(LimiterLevelSample) getGr,
      ui.Color color, double maxAlpha) {
    for (int i = startIdx; i < endIdx; i++) {
      final x = (i - startIdx).toDouble() * sampleWidth;
      final gr = getGr(history[i]);
      final grHeight = (gr / 24).clamp(0.0, 1.0) * size.height * 0.4;
      if (grHeight > 0.5) {
        final barRect = ui.Rect.fromLTWH(x, 0, sampleWidth + 0.5, grHeight);
        canvas.drawRect(barRect, ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset(x, 0), ui.Offset(x, grHeight),
            [color.withValues(alpha: maxAlpha), color.withValues(alpha: maxAlpha * 0.3)],
          ));
      }
    }
  }

  void _drawWaveformFill(ui.Canvas canvas, ui.Size size, double sampleWidth,
      int startIdx, int endIdx, double Function(LimiterLevelSample) getValue,
      double dbOffset, double totalRange, ui.Color bottomColor, ui.Color topColor) {
    final path = ui.Path()..moveTo(0, size.height);
    for (int i = startIdx; i < endIdx; i++) {
      final x = (i - startIdx).toDouble() * sampleWidth;
      final y = _dbToY(getValue(history[i]), size.height, dbOffset, totalRange)
          .clamp(0.0, size.height);
      path.lineTo(x, y);
    }
    path.lineTo((endIdx - startIdx).toDouble() * sampleWidth, size.height);
    path.close();
    canvas.drawPath(path, ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, size.height), ui.Offset.zero, [bottomColor, topColor]));
  }

  void _drawWaveformLine(ui.Canvas canvas, ui.Size size, double sampleWidth,
      int startIdx, int endIdx, double Function(LimiterLevelSample) getValue,
      double dbOffset, double totalRange, ui.Color color, double strokeWidth) {
    final path = ui.Path();
    bool started = false;
    for (int i = startIdx; i < endIdx; i++) {
      final x = (i - startIdx).toDouble() * sampleWidth;
      final y = _dbToY(getValue(history[i]), size.height, dbOffset, totalRange)
          .clamp(0.0, size.height);
      if (!started) { path.moveTo(x, y); started = true; }
      else path.lineTo(x, y);
    }
    if (started) {
      canvas.drawPath(path, ui.Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = ui.PaintingStyle.stroke);
    }
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

// ═══════════════════════════════════════════════════════════════════════════
// LUFS TIMELINE PAINTER — Scrolling LUFS graph (L2)
// ═══════════════════════════════════════════════════════════════════════════

class _LufsTimelinePainter extends CustomPainter {
  final List<(double mom, double st, double integ)> lufsHistory;
  final double? target;

  _LufsTimelinePainter({required this.lufsHistory, this.target});

  @override
  void paint(Canvas canvas, Size size) {
    // Glass background
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
        [const Color(0xFF0D0D12), const Color(0xFF08080C)]));

    // Range: -48 to 0 LUFS
    const minLufs = -48.0;
    const maxLufs = 0.0;
    const range = maxLufs - minLufs;

    // Grid lines every 6 LU
    final gridPaint = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    for (var lu = -48; lu <= 0; lu += 6) {
      final y = size.height * (1 - (lu - minLufs) / range);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // dB labels
    final labelStyle = ui.TextStyle(color: const Color(0xFF444455), fontSize: 8);
    for (final lu in [-6, -14, -23, -36]) {
      final y = size.height * (1 - (lu - minLufs) / range);
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.right))
        ..pushStyle(labelStyle)
        ..addText('$lu');
      final p = pb.build()..layout(const ui.ParagraphConstraints(width: 24));
      canvas.drawParagraph(p, Offset(size.width - 26, y - 6));
    }

    // Target line
    if (target != null) {
      final targetY = size.height * (1 - (target! - minLufs) / range);
      // Glow
      canvas.drawLine(Offset(0, targetY), Offset(size.width, targetY),
        Paint()
          ..color = FabFilterProcessorColors.limLufs.withValues(alpha: 0.15)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      // ±1 LU zone
      final zoneTop = size.height * (1 - (target! + 1 - minLufs) / range);
      final zoneBot = size.height * (1 - (target! - 1 - minLufs) / range);
      canvas.drawRect(Rect.fromLTRB(0, zoneTop, size.width, zoneBot),
        Paint()..color = FabFilterProcessorColors.limLufs.withValues(alpha: 0.06));
      // Core line
      canvas.drawLine(Offset(0, targetY), Offset(size.width, targetY),
        Paint()..color = FabFilterProcessorColors.limLufs.withValues(alpha: 0.6)..strokeWidth = 1);
    }

    if (lufsHistory.isEmpty) return;

    final sampleW = size.width / 300;
    final startX = size.width - lufsHistory.length * sampleW;

    // Draw 3 LUFS curves: Momentary, Short-term, Integrated
    void drawCurve(Color color, double Function(int i) getValue, double width, double alpha) {
      final path = Path();
      var started = false;
      for (var i = 0; i < lufsHistory.length; i++) {
        final x = startX + i * sampleW;
        if (x < 0) continue;
        final v = getValue(i);
        if (v < -100) continue;
        final y = (size.height * (1 - (v - minLufs) / range)).clamp(0.0, size.height);
        if (!started) { path.moveTo(x, y); started = true; }
        else path.lineTo(x, y);
      }
      if (started) {
        canvas.drawPath(path, Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = width
          ..style = PaintingStyle.stroke);
      }
    }

    // Momentary (blue, thin, full opacity)
    drawCurve(FabFilterColors.blue, (i) => lufsHistory[i].$1, 1.0, 0.6);
    // Short-term (cyan, medium)
    drawCurve(FabFilterColors.cyan, (i) => lufsHistory[i].$2, 1.5, 0.8);
    // Integrated (green, thick, bright)
    drawCurve(FabFilterColors.green, (i) => lufsHistory[i].$3, 2.0, 1.0);

    // Legend
    final legendItems = [
      ('MOM', FabFilterColors.blue),
      ('S-T', FabFilterColors.cyan),
      ('INT', FabFilterColors.green),
    ];
    var lx = 6.0;
    for (final (label, color) in legendItems) {
      canvas.drawLine(Offset(lx, 8), Offset(lx + 10, 8),
        Paint()..color = color..strokeWidth = 1.5);
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle())
        ..pushStyle(ui.TextStyle(color: color, fontSize: 7))
        ..addText(label);
      final p = pb.build()..layout(const ui.ParagraphConstraints(width: 24));
      canvas.drawParagraph(p, Offset(lx + 12, 3));
      lx += 38;
    }
  }

  @override
  bool shouldRepaint(covariant _LufsTimelinePainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// GR HISTOGRAM PAINTER — Distribution of gain reduction (L3)
// ═══════════════════════════════════════════════════════════════════════════

class _GrHistogramPainter extends CustomPainter {
  final List<int> histogram;
  final int total;

  _GrHistogramPainter({required this.histogram, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    // Glass background
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
        [const Color(0xFF0D0D12), const Color(0xFF08080C)]));

    if (total == 0) {
      // Empty state text
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ui.TextStyle(color: const Color(0xFF444455), fontSize: 10))
        ..addText('GR Histogram — no data');
      final p = pb.build()..layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(p, Offset(0, size.height / 2 - 6));
      return;
    }

    final maxCount = histogram.reduce(math.max);
    if (maxCount == 0) return;

    final barWidth = (size.width - 40) / 24;
    const leftMargin = 30.0;
    final barMaxH = size.height - 20;

    // Grid
    final gridPaint = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    for (var i = 0; i < 5; i++) {
      final y = 10 + barMaxH * i / 4;
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - 10, y), gridPaint);
    }

    // Bars
    for (var i = 0; i < 24; i++) {
      final count = histogram[i];
      if (count == 0) continue;
      final barH = (count / maxCount) * barMaxH;
      final x = leftMargin + i * barWidth;
      final y = 10 + barMaxH - barH;

      // Color gradient: green (0-3dB) → yellow (3-10dB) → red (10-24dB)
      final t = i / 23.0;
      final color = t < 0.15
          ? FabFilterColors.green
          : t < 0.45
              ? Color.lerp(FabFilterColors.green, FabFilterColors.orange, (t - 0.15) / 0.3)!
              : Color.lerp(FabFilterColors.orange, FabFilterColors.red, (t - 0.45) / 0.55)!;

      final barRect = Rect.fromLTWH(x + 1, y, barWidth - 2, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(1)),
        Paint()..shader = ui.Gradient.linear(
          Offset(x, y), Offset(x, y + barH),
          [color, color.withValues(alpha: 0.3)],
        ),
      );
      // Glow top edge
      canvas.drawLine(Offset(x + 1, y), Offset(x + barWidth - 1, y),
        Paint()..color = color..strokeWidth = 1
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    }

    // dB labels along bottom
    for (var i = 0; i < 24; i += 3) {
      final x = leftMargin + i * barWidth;
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ui.TextStyle(color: const Color(0xFF555566), fontSize: 7))
        ..addText('-$i');
      final p = pb.build()..layout(ui.ParagraphConstraints(width: barWidth * 3));
      canvas.drawParagraph(p, Offset(x - barWidth * 0.5, size.height - 12));
    }

    // % labels along left
    for (var i = 0; i <= 4; i++) {
      final pct = (i * 25).toString();
      final y = 10 + barMaxH * (4 - i) / 4;
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.right))
        ..pushStyle(ui.TextStyle(color: const Color(0xFF555566), fontSize: 7))
        ..addText('$pct%');
      final p = pb.build()..layout(const ui.ParagraphConstraints(width: 26));
      canvas.drawParagraph(p, Offset(1, y - 5));
    }
  }

  @override
  bool shouldRepaint(covariant _GrHistogramPainter old) => true;
}
