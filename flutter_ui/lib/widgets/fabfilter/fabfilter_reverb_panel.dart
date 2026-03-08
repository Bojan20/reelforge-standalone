/// FF-R Reverb Panel — Pro-R 2 Ultimate
///
/// Mastering-grade reverb interface with 19 parameters:
/// - Space, Brightness, Width, Mix, PreDelay, Style
/// - Diffusion, Distance, Decay, Low/High Decay Mult
/// - Character, Thickness, Ducking, Freeze
/// - Glass decay visualization with tonal EQ bands
/// - Real-time wet tail sparkle + early reflection plot
/// - Decay history waveform with gradient fills
/// - Pre-delay region with glow marker
/// - Freeze state overlay with ice crystallization effect

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
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Reverb space type
enum ReverbSpace {
  room('Room', Icons.meeting_room),
  hall('Hall', Icons.church),
  plate('Plate', Icons.rectangle_outlined),
  chamber('Chamber', Icons.sensors),
  spring('Spring', Icons.cable),
  ambient('Ambient', Icons.cloud),
  shimmer('Shimmer', Icons.auto_awesome),
  nonlinear('Nonlinear', Icons.show_chart),
  vintage('Vintage', Icons.radio),
  gated('Gated', Icons.door_front_door);

  final String label;
  final IconData icon;
  const ReverbSpace(this.label, this.icon);
}

// ═══════════════════════════════════════════════════════════════════════════
// PARAM INDICES — must match ReverbWrapper in dsp_wrappers.rs
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const space = 0;
  static const brightness = 1;
  static const width = 2;
  static const mix = 3;
  static const predelay = 4;
  static const style = 5;
  static const diffusion = 6;
  static const distance = 7;
  static const decay = 8;
  static const lowDecay = 9;
  static const highDecay = 10;
  static const character = 11;
  static const thickness = 12;
  static const ducking = 13;
  static const freeze = 14;
  static const spin = 15;
  static const wander = 16;
  static const erLevel = 17;
  static const lateLevel = 18;
  static const xoFreq1 = 19;
  static const xoFreq2 = 20;
  static const xoFreq3 = 21;
  static const lowmidDecay = 22;
  static const highmidDecay = 23;
  // F5: Output Processing
  static const outEqLoGain = 24;
  static const outEqLoFreq = 25;
  static const outEqHiGain = 26;
  static const outEqHiFreq = 27;
  static const outEqMidGain = 28;
  static const outEqMidFreq = 29;
  static const outEqMidQ = 30;
  static const softLimiter = 31;
  static const bpmSync = 32;
  static const bpm = 33;
  static const noteDiv = 34;
  static const pdFeedback = 35;
  // F8: Advanced FDN
  static const fdnSize = 36;
  static const matrixType = 37;
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class ReverbSnapshot implements DspParameterSnapshot {
  final double space, brightness, width, mix, predelay;
  final int style;
  final double diffusion, distance, decay;
  final double lowDecayMult, highDecayMult;
  final double character, thickness, ducking;
  final bool freeze;
  final double spin, wander;
  final double erLevel, lateLevel;
  final double xoFreq1, xoFreq2, xoFreq3;
  final double lowmidDecayMult, highmidDecayMult;
  // F5: Output Processing
  final double outEqLoGain, outEqLoFreq, outEqHiGain, outEqHiFreq;
  final double outEqMidGain, outEqMidFreq, outEqMidQ;
  final bool softLimiter, bpmSync;
  final double bpm, pdFeedback;
  final int noteDiv;
  // F8: Advanced FDN
  final int fdnSize;    // 0=Small/4, 1=Medium/8, 2=Large/16
  final int matrixType; // 0=Hadamard, 1=Householder

  const ReverbSnapshot({
    required this.space, required this.brightness, required this.width,
    required this.mix, required this.predelay, required this.style,
    required this.diffusion, required this.distance, required this.decay,
    required this.lowDecayMult, required this.highDecayMult,
    required this.character, required this.thickness, required this.ducking,
    required this.freeze, required this.spin, required this.wander,
    required this.erLevel, required this.lateLevel,
    required this.xoFreq1, required this.xoFreq2, required this.xoFreq3,
    required this.lowmidDecayMult, required this.highmidDecayMult,
    required this.outEqLoGain, required this.outEqLoFreq,
    required this.outEqHiGain, required this.outEqHiFreq,
    required this.outEqMidGain, required this.outEqMidFreq,
    required this.outEqMidQ,
    required this.softLimiter, required this.bpmSync,
    required this.bpm, required this.noteDiv, required this.pdFeedback,
    this.fdnSize = 1, this.matrixType = 0,
  });

  @override
  ReverbSnapshot copy() => ReverbSnapshot(
    space: space, brightness: brightness, width: width, mix: mix,
    predelay: predelay, style: style, diffusion: diffusion,
    distance: distance, decay: decay, lowDecayMult: lowDecayMult,
    highDecayMult: highDecayMult, character: character,
    thickness: thickness, ducking: ducking, freeze: freeze,
    spin: spin, wander: wander,
    erLevel: erLevel, lateLevel: lateLevel,
    xoFreq1: xoFreq1, xoFreq2: xoFreq2, xoFreq3: xoFreq3,
    lowmidDecayMult: lowmidDecayMult, highmidDecayMult: highmidDecayMult,
    outEqLoGain: outEqLoGain, outEqLoFreq: outEqLoFreq,
    outEqHiGain: outEqHiGain, outEqHiFreq: outEqHiFreq,
    outEqMidGain: outEqMidGain, outEqMidFreq: outEqMidFreq,
    outEqMidQ: outEqMidQ,
    softLimiter: softLimiter, bpmSync: bpmSync,
    bpm: bpm, noteDiv: noteDiv, pdFeedback: pdFeedback,
    fdnSize: fdnSize, matrixType: matrixType,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! ReverbSnapshot) return false;
    return space == other.space && brightness == other.brightness &&
        width == other.width && mix == other.mix &&
        predelay == other.predelay && style == other.style &&
        decay == other.decay && freeze == other.freeze &&
        spin == other.spin && wander == other.wander &&
        erLevel == other.erLevel && lateLevel == other.lateLevel &&
        xoFreq1 == other.xoFreq1 && xoFreq2 == other.xoFreq2 &&
        xoFreq3 == other.xoFreq3 &&
        lowmidDecayMult == other.lowmidDecayMult &&
        highmidDecayMult == other.highmidDecayMult &&
        outEqLoGain == other.outEqLoGain && outEqLoFreq == other.outEqLoFreq &&
        outEqHiGain == other.outEqHiGain && outEqHiFreq == other.outEqHiFreq &&
        outEqMidGain == other.outEqMidGain && outEqMidFreq == other.outEqMidFreq &&
        outEqMidQ == other.outEqMidQ &&
        softLimiter == other.softLimiter && bpmSync == other.bpmSync &&
        bpm == other.bpm && noteDiv == other.noteDiv &&
        pdFeedback == other.pdFeedback &&
        fdnSize == other.fdnSize && matrixType == other.matrixType;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FACTORY PRESETS (R9.3)
// ═══════════════════════════════════════════════════════════════════════════

class ReverbPreset {
  final String name;
  final String category;
  final ReverbSnapshot snapshot;
  const ReverbPreset(this.name, this.category, this.snapshot);
}

ReverbSnapshot _p({
  double space = 0.5, double brightness = 0.6, double width = 1.0,
  double mix = 0.33, double predelay = 0.0, int style = 0,
  double diffusion = 0.0, double distance = 0.0, double decay = 0.5,
  double lowDecay = 1.0, double highDecay = 1.0,
  double character = 0.0, double thickness = 0.0, double ducking = 0.0,
  bool freeze = false, double spin = 0.5, double wander = 0.5,
  double erLevel = 1.0, double lateLevel = 1.0,
  double xoFreq1 = 250.0, double xoFreq2 = 2000.0, double xoFreq3 = 8000.0,
  double lowmidDecay = 1.0, double highmidDecay = 1.0,
  double outEqLoGain = 0.0, double outEqLoFreq = 200.0,
  double outEqHiGain = 0.0, double outEqHiFreq = 8000.0,
  double outEqMidGain = 0.0, double outEqMidFreq = 1000.0, double outEqMidQ = 1.0,
  bool softLimiter = false, bool bpmSync = false,
  double bpm = 120.0, int noteDiv = 2, double pdFeedback = 0.0,
}) => ReverbSnapshot(
  space: space, brightness: brightness, width: width, mix: mix,
  predelay: predelay, style: style, diffusion: diffusion,
  distance: distance, decay: decay,
  lowDecayMult: lowDecay, highDecayMult: highDecay,
  character: character, thickness: thickness, ducking: ducking,
  freeze: freeze, spin: spin, wander: wander,
  erLevel: erLevel, lateLevel: lateLevel,
  xoFreq1: xoFreq1, xoFreq2: xoFreq2, xoFreq3: xoFreq3,
  lowmidDecayMult: lowmidDecay, highmidDecayMult: highmidDecay,
  outEqLoGain: outEqLoGain, outEqLoFreq: outEqLoFreq,
  outEqHiGain: outEqHiGain, outEqHiFreq: outEqHiFreq,
  outEqMidGain: outEqMidGain, outEqMidFreq: outEqMidFreq,
  outEqMidQ: outEqMidQ,
  softLimiter: softLimiter, bpmSync: bpmSync,
  bpm: bpm, noteDiv: noteDiv, pdFeedback: pdFeedback,
);

final List<ReverbPreset> kReverbPresets = [
  // === ROOMS ===
  ReverbPreset('Small Room', 'Rooms', _p(style: 0, space: 0.2, decay: 0.2, brightness: 0.7, mix: 0.25, diffusion: 0.3, erLevel: 1.0, lateLevel: 0.6)),
  ReverbPreset('Medium Room', 'Rooms', _p(style: 0, space: 0.4, decay: 0.35, brightness: 0.6, mix: 0.3, diffusion: 0.5, erLevel: 0.9, lateLevel: 0.8)),
  ReverbPreset('Large Room', 'Rooms', _p(style: 0, space: 0.65, decay: 0.45, brightness: 0.55, mix: 0.3, diffusion: 0.6, erLevel: 0.8, lateLevel: 0.9)),
  ReverbPreset('Drum Room', 'Rooms', _p(style: 0, space: 0.3, decay: 0.2, brightness: 0.8, mix: 0.2, diffusion: 0.2, erLevel: 1.0, lateLevel: 0.5, thickness: 0.3)),
  // === HALLS ===
  ReverbPreset('Concert Hall', 'Halls', _p(style: 1, space: 0.7, decay: 0.65, brightness: 0.5, mix: 0.3, diffusion: 0.7, width: 1.3, erLevel: 0.7, lateLevel: 1.0)),
  ReverbPreset('Large Hall', 'Halls', _p(style: 1, space: 0.85, decay: 0.75, brightness: 0.45, mix: 0.35, diffusion: 0.8, width: 1.5, erLevel: 0.6, lateLevel: 1.0)),
  ReverbPreset('Cathedral', 'Halls', _p(style: 1, space: 1.0, decay: 0.9, brightness: 0.35, mix: 0.4, diffusion: 0.9, width: 1.8, lowDecay: 1.3, highDecay: 0.6)),
  // === PLATES ===
  ReverbPreset('Vocal Plate', 'Plates', _p(style: 2, space: 0.5, decay: 0.45, brightness: 0.7, mix: 0.25, diffusion: 0.8, width: 1.2, outEqMidGain: 2.0, outEqMidFreq: 3000.0)),
  ReverbPreset('Bright Plate', 'Plates', _p(style: 2, space: 0.6, decay: 0.5, brightness: 0.85, mix: 0.3, diffusion: 0.85, width: 1.4, highDecay: 0.8)),
  ReverbPreset('Dark Plate', 'Plates', _p(style: 2, space: 0.55, decay: 0.55, brightness: 0.3, mix: 0.3, diffusion: 0.7, outEqHiGain: -4.0)),
  // === CHAMBERS ===
  ReverbPreset('Studio Chamber', 'Chambers', _p(style: 3, space: 0.35, decay: 0.3, brightness: 0.6, mix: 0.2, diffusion: 0.4, erLevel: 1.0)),
  ReverbPreset('Echo Chamber', 'Chambers', _p(style: 3, space: 0.5, decay: 0.4, brightness: 0.65, mix: 0.3, predelay: 40.0, pdFeedback: 0.2)),
  // === SPRINGS ===
  ReverbPreset('Spring Classic', 'Springs', _p(style: 4, space: 0.3, decay: 0.3, brightness: 0.6, mix: 0.25, character: 0.6, thickness: 0.4)),
  ReverbPreset('Spring Drip', 'Springs', _p(style: 4, space: 0.25, decay: 0.25, brightness: 0.7, mix: 0.3, character: 0.8, thickness: 0.6)),
  // === AMBIENT ===
  ReverbPreset('Ambient Wash', 'Ambient', _p(style: 5, space: 0.8, decay: 0.8, brightness: 0.4, mix: 0.45, diffusion: 0.9, width: 1.8, lowDecay: 1.2, highDecay: 0.5)),
  ReverbPreset('Ambient Pad', 'Ambient', _p(style: 5, space: 0.9, decay: 0.85, brightness: 0.35, mix: 0.5, diffusion: 0.95, width: 2.0, spin: 0.7, wander: 0.7)),
  // === SHIMMER ===
  ReverbPreset('Shimmer Pad', 'Shimmer', _p(style: 6, space: 0.75, decay: 0.7, brightness: 0.6, mix: 0.4, diffusion: 0.85, width: 1.6, character: 0.7)),
  ReverbPreset('Shimmer Bright', 'Shimmer', _p(style: 6, space: 0.8, decay: 0.75, brightness: 0.8, mix: 0.35, diffusion: 0.9, highDecay: 0.9, character: 0.8)),
  // === NONLINEAR ===
  ReverbPreset('Nonlinear Drums', 'Nonlinear', _p(style: 7, space: 0.4, decay: 0.3, brightness: 0.7, mix: 0.3, character: 0.6, thickness: 0.5)),
  // === VINTAGE ===
  ReverbPreset('Vintage Lexicon', 'Vintage', _p(style: 8, space: 0.5, decay: 0.5, brightness: 0.5, mix: 0.3, diffusion: 0.6, width: 1.0, character: 0.4)),
  ReverbPreset('Lo-Fi Verb', 'Vintage', _p(style: 8, space: 0.4, decay: 0.4, brightness: 0.3, mix: 0.25, outEqHiGain: -6.0, outEqLoGain: -2.0)),
  // === GATED ===
  ReverbPreset('80s Gated', 'Gated', _p(style: 9, space: 0.5, decay: 0.5, brightness: 0.7, mix: 0.4, thickness: 0.6)),
  ReverbPreset('Gated Snare', 'Gated', _p(style: 9, space: 0.35, decay: 0.35, brightness: 0.8, mix: 0.35, erLevel: 1.0, lateLevel: 0.8)),
  // === SPECIAL ===
  ReverbPreset('Vocal Doubler', 'Special', _p(style: 0, space: 0.15, decay: 0.1, brightness: 0.7, mix: 0.15, predelay: 20.0, diffusion: 0.2, erLevel: 1.0, lateLevel: 0.3)),
  ReverbPreset('Infinite Freeze', 'Special', _p(style: 1, space: 0.7, decay: 1.0, brightness: 0.5, mix: 0.5, freeze: true, width: 1.5, diffusion: 0.8)),
];

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterReverbPanel extends FabFilterPanelBase {
  const FabFilterReverbPanel({
    super.key,
    required super.trackId,
    super.slotIndex,
  }) : super(
          title: 'FF-R',
          icon: Icons.waves,
          accentColor: FabFilterColors.purple,
          nodeType: DspNodeType.reverb,
        );

  @override
  State<FabFilterReverbPanel> createState() => _FabFilterReverbPanelState();
}

class _FabFilterReverbPanelState extends State<FabFilterReverbPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE — All 19 parameters
  // ─────────────────────────────────────────────────────────────────────────

  // Primary controls
  double _space = 0.5;
  double _brightness = 0.5;
  double _decay = 0.5;
  double _mix = 0.3;
  double _predelay = 20.0;  // ms (0-500)
  double _width = 1.0;      // 0-2
  ReverbSpace _spaceType = ReverbSpace.hall;

  // Character controls — defaults match Rust (all off by default)
  double _diffusion = 0.0;
  double _distance = 0.0;
  double _character = 0.0;
  double _thickness = 0.0;

  // Tonal shaping
  double _lowDecay = 1.0;   // 0.5-2.0
  double _highDecay = 0.5;  // 0.1-1.0

  // Special
  double _ducking = 0.0;
  bool _freeze = false;

  // Velvet noise modulation (Phase 1)
  double _spin = 0.5;    // 0.0-1.0 (maps to 1-5 Hz fast modulation)
  double _wander = 0.5;  // 0.0-1.0 (maps to 0.05-0.5 Hz slow drift)
  double _erLevel = 1.0;    // 0.0-1.0 (ER gain)
  double _lateLevel = 1.0;  // 0.0-1.0 (FDN tail gain)

  // 4-band crossover (Phase 4)
  double _xoFreq1 = 250.0;   // Crossover 1 Hz (Low/LowMid)
  double _xoFreq2 = 2000.0;  // Crossover 2 Hz (LowMid/HighMid)
  double _xoFreq3 = 8000.0;  // Crossover 3 Hz (HighMid/High)
  double _lowmidDecay = 1.0;  // 0.5-2.0
  double _highmidDecay = 1.0; // 0.5-2.0
  // F5: Output Processing
  double _outEqLoGain = 0.0;   // -12 to +12 dB
  double _outEqLoFreq = 200.0; // 80-500 Hz
  double _outEqHiGain = 0.0;   // -12 to +12 dB
  double _outEqHiFreq = 8000.0; // 2000-16000 Hz
  double _outEqMidGain = 0.0;  // -12 to +12 dB
  double _outEqMidFreq = 1000.0; // 200-8000 Hz
  double _outEqMidQ = 1.0;     // 0.5-5.0
  bool _softLimiter = false;
  bool _bpmSync = false;
  double _bpm = 120.0;         // 60-200
  int _noteDiv = 2;            // 0-7
  double _pdFeedback = 0.0;    // 0.0-0.5
  // F8: Advanced FDN
  int _fdnSize = 1;     // 0=Small, 1=Medium, 2=Large
  int _matrixType = 0;  // 0=Hadamard, 1=Householder

  // Metering
  double _wetLevel = 0.0;
  double _inputLevel = 0.0;
  final List<double> _decayHistory = List.filled(80, 0.0);
  int _historyIndex = 0;

  // Animation
  late AnimationController _meterController;
  late AnimationController _freezeController;
  late Animation<double> _freezeAnim;
  double _animatedDecay = 0.0;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;

  // A/B snapshots
  ReverbSnapshot? _snapshotA;
  ReverbSnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
    initBypassFromProvider();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_updateMeters);
    _meterController.repeat();

    _freezeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _freezeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _freezeController, curve: Curves.easeInOut),
    );
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
      if (node.type == DspNodeType.reverb) {
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
      _space = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.space);
      _brightness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.brightness);
      _width = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.width);
      _mix = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.mix);
      _predelay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.predelay);
      final typeIdx = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.style).round();
      _spaceType = _typeIndexToSpace(typeIdx);
      _diffusion = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.diffusion);
      _distance = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.distance);
      _decay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.decay);
      _lowDecay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.lowDecay);
      _highDecay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.highDecay);
      _character = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.character);
      _thickness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.thickness);
      _ducking = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.ducking);
      _freeze = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.freeze) > 0.5;
      _spin = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.spin);
      _wander = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.wander);
      _erLevel = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.erLevel);
      _lateLevel = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.lateLevel);
      _xoFreq1 = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.xoFreq1);
      _xoFreq2 = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.xoFreq2);
      _xoFreq3 = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.xoFreq3);
      _lowmidDecay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.lowmidDecay);
      _highmidDecay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.highmidDecay);
      // F5: Output Processing
      _outEqLoGain = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqLoGain);
      _outEqLoFreq = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqLoFreq);
      _outEqHiGain = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqHiGain);
      _outEqHiFreq = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqHiFreq);
      _outEqMidGain = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqMidGain);
      _outEqMidFreq = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqMidFreq);
      _outEqMidQ = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outEqMidQ);
      _softLimiter = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.softLimiter) > 0.5;
      _bpmSync = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.bpmSync) > 0.5;
      _bpm = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.bpm);
      _noteDiv = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.noteDiv).round();
      _pdFeedback = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.pdFeedback);
      _fdnSize = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.fdnSize).round();
      _matrixType = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.matrixType).round();
      if (_freeze) _freezeController.forward();
    });
  }

  ReverbSpace _typeIndexToSpace(int typeIndex) {
    return switch (typeIndex) {
      0 => ReverbSpace.room,
      1 => ReverbSpace.hall,
      2 => ReverbSpace.plate,
      3 => ReverbSpace.chamber,
      4 => ReverbSpace.spring,
      5 => ReverbSpace.ambient,
      6 => ReverbSpace.shimmer,
      7 => ReverbSpace.nonlinear,
      8 => ReverbSpace.vintage,
      9 => ReverbSpace.gated,
      _ => ReverbSpace.room,
    };
  }

  int _spaceToTypeIndex(ReverbSpace space) {
    return switch (space) {
      ReverbSpace.room => 0,
      ReverbSpace.hall => 1,
      ReverbSpace.plate => 2,
      ReverbSpace.chamber => 3,
      ReverbSpace.spring => 4,
      ReverbSpace.ambient => 5,
      ReverbSpace.shimmer => 6,
      ReverbSpace.nonlinear => 7,
      ReverbSpace.vintage => 8,
      ReverbSpace.gated => 9,
    };
  }

  void _setParam(int index, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, index, value);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A/B STATE
  // ─────────────────────────────────────────────────────────────────────────

  ReverbSnapshot _snap() => ReverbSnapshot(
    space: _space, brightness: _brightness, width: _width, mix: _mix,
    predelay: _predelay, style: _spaceToTypeIndex(_spaceType),
    diffusion: _diffusion, distance: _distance, decay: _decay,
    lowDecayMult: _lowDecay, highDecayMult: _highDecay,
    character: _character, thickness: _thickness, ducking: _ducking,
    freeze: _freeze, spin: _spin, wander: _wander,
    erLevel: _erLevel, lateLevel: _lateLevel,
    xoFreq1: _xoFreq1, xoFreq2: _xoFreq2, xoFreq3: _xoFreq3,
    lowmidDecayMult: _lowmidDecay, highmidDecayMult: _highmidDecay,
    outEqLoGain: _outEqLoGain, outEqLoFreq: _outEqLoFreq,
    outEqHiGain: _outEqHiGain, outEqHiFreq: _outEqHiFreq,
    outEqMidGain: _outEqMidGain, outEqMidFreq: _outEqMidFreq,
    outEqMidQ: _outEqMidQ,
    softLimiter: _softLimiter, bpmSync: _bpmSync,
    bpm: _bpm, noteDiv: _noteDiv, pdFeedback: _pdFeedback,
    fdnSize: _fdnSize, matrixType: _matrixType,
  );

  void _restore(ReverbSnapshot s) {
    setState(() {
      _space = s.space; _brightness = s.brightness; _width = s.width;
      _mix = s.mix; _predelay = s.predelay;
      _spaceType = _typeIndexToSpace(s.style);
      _diffusion = s.diffusion; _distance = s.distance; _decay = s.decay;
      _lowDecay = s.lowDecayMult; _highDecay = s.highDecayMult;
      _character = s.character; _thickness = s.thickness;
      _ducking = s.ducking; _freeze = s.freeze;
      _spin = s.spin; _wander = s.wander;
      _erLevel = s.erLevel; _lateLevel = s.lateLevel;
      _xoFreq1 = s.xoFreq1; _xoFreq2 = s.xoFreq2; _xoFreq3 = s.xoFreq3;
      _lowmidDecay = s.lowmidDecayMult; _highmidDecay = s.highmidDecayMult;
      _outEqLoGain = s.outEqLoGain; _outEqLoFreq = s.outEqLoFreq;
      _outEqHiGain = s.outEqHiGain; _outEqHiFreq = s.outEqHiFreq;
      _outEqMidGain = s.outEqMidGain; _outEqMidFreq = s.outEqMidFreq;
      _outEqMidQ = s.outEqMidQ;
      _softLimiter = s.softLimiter; _bpmSync = s.bpmSync;
      _bpm = s.bpm; _noteDiv = s.noteDiv; _pdFeedback = s.pdFeedback;
      _fdnSize = s.fdnSize; _matrixType = s.matrixType;
    });
    if (_freeze) { _freezeController.forward(); } else { _freezeController.reverse(); }
    _applyAll();
  }

  void _loadPreset(int index) {
    if (index < 0 || index >= kReverbPresets.length) return;
    final s = kReverbPresets[index].snapshot;
    setState(() {
      _space = s.space; _brightness = s.brightness; _width = s.width;
      _mix = s.mix; _predelay = s.predelay;
      _spaceType = _typeIndexToSpace(s.style);
      _diffusion = s.diffusion; _distance = s.distance; _decay = s.decay;
      _lowDecay = s.lowDecayMult; _highDecay = s.highDecayMult;
      _character = s.character; _thickness = s.thickness;
      _ducking = s.ducking; _freeze = s.freeze;
      _spin = s.spin; _wander = s.wander;
      _erLevel = s.erLevel; _lateLevel = s.lateLevel;
      _xoFreq1 = s.xoFreq1; _xoFreq2 = s.xoFreq2; _xoFreq3 = s.xoFreq3;
      _lowmidDecay = s.lowmidDecayMult; _highmidDecay = s.highmidDecayMult;
      _outEqLoGain = s.outEqLoGain; _outEqLoFreq = s.outEqLoFreq;
      _outEqHiGain = s.outEqHiGain; _outEqHiFreq = s.outEqHiFreq;
      _outEqMidGain = s.outEqMidGain; _outEqMidFreq = s.outEqMidFreq;
      _outEqMidQ = s.outEqMidQ;
      _softLimiter = s.softLimiter; _bpmSync = s.bpmSync;
      _bpm = s.bpm; _noteDiv = s.noteDiv; _pdFeedback = s.pdFeedback;
      _fdnSize = s.fdnSize; _matrixType = s.matrixType;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.space, _space);
    _setParam(_P.brightness, _brightness);
    _setParam(_P.width, _width);
    _setParam(_P.mix, _mix);
    _setParam(_P.predelay, _predelay);
    _setParam(_P.style, _spaceToTypeIndex(_spaceType).toDouble());
    _setParam(_P.diffusion, _diffusion);
    _setParam(_P.distance, _distance);
    _setParam(_P.decay, _decay);
    _setParam(_P.lowDecay, _lowDecay);
    _setParam(_P.highDecay, _highDecay);
    _setParam(_P.character, _character);
    _setParam(_P.thickness, _thickness);
    _setParam(_P.ducking, _ducking);
    _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
    _setParam(_P.spin, _spin);
    _setParam(_P.wander, _wander);
    _setParam(_P.erLevel, _erLevel);
    _setParam(_P.lateLevel, _lateLevel);
    _setParam(_P.xoFreq1, _xoFreq1);
    _setParam(_P.xoFreq2, _xoFreq2);
    _setParam(_P.xoFreq3, _xoFreq3);
    _setParam(_P.lowmidDecay, _lowmidDecay);
    _setParam(_P.highmidDecay, _highmidDecay);
    // F5: Output Processing
    _setParam(_P.outEqLoGain, _outEqLoGain);
    _setParam(_P.outEqLoFreq, _outEqLoFreq);
    _setParam(_P.outEqHiGain, _outEqHiGain);
    _setParam(_P.outEqHiFreq, _outEqHiFreq);
    _setParam(_P.outEqMidGain, _outEqMidGain);
    _setParam(_P.outEqMidFreq, _outEqMidFreq);
    _setParam(_P.outEqMidQ, _outEqMidQ);
    _setParam(_P.softLimiter, _softLimiter ? 1.0 : 0.0);
    _setParam(_P.bpmSync, _bpmSync ? 1.0 : 0.0);
    _setParam(_P.bpm, _bpm);
    _setParam(_P.noteDiv, _noteDiv.toDouble());
    _setParam(_P.pdFeedback, _pdFeedback);
    _setParam(_P.fdnSize, _fdnSize.toDouble());
    _setParam(_P.matrixType, _matrixType.toDouble());
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
    _freezeController.dispose();
    super.dispose();
  }

  void _updateMeters() {
    if (!mounted) return;
    setState(() {
      if (_initialized && _slotIndex >= 0) {
        _inputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
        _wetLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);

        _decayHistory[_historyIndex % _decayHistory.length] = _wetLevel;
        _historyIndex++;
      }

      final decayTime = 0.1 * math.pow(20 / 0.1, _decay).toDouble();
      final t = (_meterController.value * 10) % decayTime;
      _animatedDecay = _freeze ? 0.8 : math.exp(-t / (decayTime * 0.3));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('Reverb', DspNodeType.reverb, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildPremiumHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  // TOP: Space type selector + Freeze
                  _buildSpaceSelector(),
                  const SizedBox(height: 4),
                  // DISPLAY: Decay + tonal EQ visualization
                  Expanded(flex: 3, child: _buildDecayDisplay()),
                  const SizedBox(height: 4),
                  // PRIMARY: Core knobs
                  _buildPrimaryKnobs(),
                  const SizedBox(height: 4),
                  // BOTTOM: Character sliders + tonal decay
                  Expanded(flex: 2, child: _buildCharacterSection()),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // ─── Premium Header with meters ─────────────────────────────────────────

  Widget _buildPremiumHeader() {
    final decayTime = 0.1 * math.pow(20 / 0.1, _decay);
    final decayLabel = decayTime >= 1
        ? '${decayTime.toStringAsFixed(1)}s'
        : '${(decayTime * 1000).toStringAsFixed(0)}ms';

    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FabFilterColors.bgSurface,
            FabFilterColors.bgMid.withValues(alpha: 0.8),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Title
            Icon(Icons.waves, size: 13, color: FabFilterColors.purple),
            const SizedBox(width: 4),
            Text('FF-R', style: TextStyle(
              color: FabFilterColors.textPrimary,
              fontSize: 11, fontWeight: FontWeight.bold,
            )),
            const SizedBox(width: 8),
            // Space type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.purple.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(_spaceType.label.toUpperCase(), style: TextStyle(
                color: FabFilterColors.purple,
                fontSize: 8, fontWeight: FontWeight.bold,
              ), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            // Preset selector
            PopupMenuButton<int>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Presets',
              position: PopupMenuPosition.under,
              color: FabFilterColors.bgSurface,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: FabFilterColors.bgVoid,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: FabFilterColors.borderSubtle, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.library_music, size: 9, color: FabFilterColors.textSecondary),
                    const SizedBox(width: 2),
                    Text('PRESET', style: TextStyle(
                      fontSize: 7, fontWeight: FontWeight.bold,
                      color: FabFilterColors.textSecondary,
                    )),
                  ],
                ),
              ),
              itemBuilder: (_) {
                final items = <PopupMenuEntry<int>>[];
                String? lastCategory;
                for (int i = 0; i < kReverbPresets.length; i++) {
                  final p = kReverbPresets[i];
                  if (p.category != lastCategory) {
                    if (lastCategory != null) items.add(const PopupMenuDivider(height: 4));
                    items.add(PopupMenuItem<int>(
                      enabled: false, height: 20,
                      child: Text(p.category.toUpperCase(), style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.bold,
                        color: FabFilterColors.textMuted,
                      )),
                    ));
                    lastCategory = p.category;
                  }
                  items.add(PopupMenuItem<int>(
                    value: i, height: 24,
                    child: Text(p.name, style: const TextStyle(fontSize: 11)),
                  ));
                }
                return items;
              },
              onSelected: (idx) => _loadPreset(idx),
            ),
            const SizedBox(width: 6),
            // Decay readout
            Text(decayLabel, style: TextStyle(
              color: FabFilterProcessorColors.reverbDecay,
              fontSize: 9, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ), overflow: TextOverflow.ellipsis),
            const Spacer(),
            // Mini I/O meters
            _buildMiniMeter('IN', _inputLevel, FabFilterColors.cyan),
            const SizedBox(width: 6),
            _buildMiniMeter('WET', _wetLevel, FabFilterColors.green),
            const SizedBox(width: 6),
            // Mix %
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('${(_mix * 100).toStringAsFixed(0)}%', style: TextStyle(
                color: FabFilterColors.green,
                fontSize: 8, fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
            ),
            const SizedBox(width: 6),
            // Freeze indicator
            if (_freeze)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: FabFilterColors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.5), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ac_unit, size: 8, color: FabFilterColors.cyan),
                    const SizedBox(width: 2),
                    Text('FRZ', style: TextStyle(
                      color: FabFilterColors.cyan,
                      fontSize: 7, fontWeight: FontWeight.bold,
                    )),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: FabFilterColors.purple),
            const SizedBox(width: 4),
            FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMeter(String label, double level, Color color) {
    final dB = level > 1e-10 ? 20.0 * math.log(level) / math.ln10 : -60.0;
    final norm = ((dB + 60) / 60).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(
          color: FabFilterColors.textTertiary,
          fontSize: 7, fontWeight: FontWeight.bold,
        )),
        const SizedBox(width: 2),
        SizedBox(
          width: 24, height: 5,
          child: CustomPaint(
            painter: _MiniMeterPainter(value: norm, color: color),
          ),
        ),
      ],
    );
  }

  // ─── Space Selector (chip bar) ────────────────────────────────────────

  Widget _buildSpaceSelector() {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          ...ReverbSpace.values.map((s) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () {
                setState(() => _spaceType = s);
                _setParam(_P.style, _spaceToTypeIndex(s).toDouble());
                setState(() {
                  _space = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.space);
                  _brightness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.brightness);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _spaceType == s
                      ? FabFilterColors.purple.withValues(alpha: 0.25)
                      : FabFilterColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _spaceType == s ? FabFilterColors.purple : FabFilterColors.borderSubtle,
                    width: _spaceType == s ? 1.5 : 1,
                  ),
                  boxShadow: _spaceType == s ? [
                    BoxShadow(
                      color: FabFilterColors.purple.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 11,
                      color: _spaceType == s ? FabFilterColors.purple : FabFilterColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(s.label, style: TextStyle(
                      color: _spaceType == s ? FabFilterColors.textPrimary : FabFilterColors.textTertiary,
                      fontSize: 9, fontWeight: FontWeight.bold,
                    )),
                  ],
                ),
              ),
            ),
          )),
          const Spacer(),
          _buildFreezeButton(),
        ],
      ),
    );
  }

  Widget _buildFreezeButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _freeze = !_freeze);
        _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
        if (_freeze) {
          _freezeController.forward();
        } else {
          _freezeController.reverse();
        }
      },
      child: AnimatedBuilder(
        animation: _freezeAnim,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _freeze
                  ? FabFilterColors.cyan.withValues(alpha: 0.15 + _freezeAnim.value * 0.15)
                  : FabFilterColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _freeze ? FabFilterColors.cyan : FabFilterColors.borderSubtle,
                width: _freeze ? 1.5 : 1,
              ),
              boxShadow: _freeze ? [
                BoxShadow(
                  color: FabFilterColors.cyan.withValues(alpha: 0.15 + _freezeAnim.value * 0.1),
                  blurRadius: 8 + _freezeAnim.value * 4,
                ),
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.ac_unit, size: 12,
                  color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary),
                const SizedBox(width: 4),
                Text('FREEZE', style: TextStyle(
                  color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary,
                  fontSize: 9, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Decay Display ────────────────────────────────────────────────────

  Widget _buildDecayDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            CustomPaint(
              painter: _ReverbDisplayPainter(
                decay: _decay,
                predelay: _predelay,
                space: _space,
                brightness: _brightness,
                lowDecayMult: _lowDecay,
                lowmidDecayMult: _lowmidDecay,
                highmidDecayMult: _highmidDecay,
                highDecayMult: _highDecay,
                animatedDecay: _animatedDecay,
                freeze: _freeze,
                freezeAnim: _freezeAnim.value,
                distance: _distance,
                wetLevel: _wetLevel,
                inputLevel: _inputLevel,
                decayHistory: List.from(_decayHistory),
                historyIndex: _historyIndex,
                diffusion: _diffusion,
                mix: _mix,
              ),
              size: Size.infinite,
            ),
            // Tonal indicator (top-right)
            Positioned(
              right: 4,
              top: 4,
              child: _buildTonalIndicator(),
            ),
            // Mix indicator (bottom-left)
            Positioned(
              left: 4,
              bottom: 4,
              child: _buildMixIndicator(),
            ),
            // Width indicator (bottom-right)
            Positioned(
              right: 4,
              bottom: 4,
              child: _buildWidthBadge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTonalIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Low decay indicator bar
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  _lowDecay > 1.0
                      ? FabFilterColors.orange.withValues(alpha: 0.2)
                      : FabFilterColors.cyan.withValues(alpha: 0.2),
                  _lowDecay > 1.0
                      ? FabFilterColors.orange.withValues(alpha: (_lowDecay - 1.0).clamp(0.0, 1.0))
                      : FabFilterColors.cyan.withValues(alpha: (1.0 - _lowDecay).clamp(0.0, 1.0) * 2),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Text('Lo ${_lowDecay.toStringAsFixed(1)}×',
            style: TextStyle(
              color: _lowDecay > 1.0 ? FabFilterColors.orange : FabFilterColors.cyan,
              fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
          const SizedBox(width: 6),
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  FabFilterColors.cyan.withValues(alpha: 0.2),
                  FabFilterColors.cyan.withValues(alpha: (1.0 - _highDecay).clamp(0.0, 1.0)),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Text('Hi ${_highDecay.toStringAsFixed(1)}×',
            style: TextStyle(
              color: FabFilterColors.cyan,
              fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        ],
      ),
    );
  }

  Widget _buildMixIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40, height: 6,
            child: CustomPaint(
              painter: _MixBarPainter(mix: _mix),
            ),
          ),
          const SizedBox(width: 4),
          Text('${(_mix * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: FabFilterColors.green,
              fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        ],
      ),
    );
  }

  Widget _buildWidthBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text('W ${(_width * 100).toStringAsFixed(0)}%', style: TextStyle(
        color: FabFilterColors.cyan.withValues(alpha: 0.7),
        fontSize: 8, fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
      )),
    );
  }

  // ─── Primary Knobs ────────────────────────────────────────────────────

  Widget _buildPrimaryKnobs() {
    return SizedBox(
      height: 68,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _knob(
            value: _space, label: 'SPACE',
            display: '${(_space * 100).toStringAsFixed(0)}%',
            color: FabFilterProcessorColors.reverbAccent,
            onChanged: (v) {
              setState(() => _space = v);
              _setParam(_P.space, v);
            },
          ),
          _knob(
            value: _decay, label: 'DECAY',
            display: _formatDecay(_decay),
            color: FabFilterProcessorColors.reverbDecay,
            onChanged: (v) {
              setState(() => _decay = v);
              _setParam(_P.decay, v);
            },
          ),
          _knob(
            value: _brightness, label: 'BRIGHT',
            display: '${(_brightness * 100).toStringAsFixed(0)}%',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _brightness = v);
              _setParam(_P.brightness, v);
            },
          ),
          _knob(
            value: _predelay / 500.0, label: 'PRE-DLY',
            display: '${_predelay.toStringAsFixed(0)}ms',
            color: FabFilterProcessorColors.reverbPredelay,
            onChanged: (v) {
              setState(() => _predelay = v * 500.0);
              _setParam(_P.predelay, _predelay);
            },
          ),
          _knob(
            value: _mix, label: 'MIX',
            display: '${(_mix * 100).toStringAsFixed(0)}%',
            color: FabFilterColors.green,
            onChanged: (v) {
              setState(() => _mix = v);
              _setParam(_P.mix, v);
            },
          ),
          _knob(
            value: _width / 2.0, label: 'WIDTH',
            display: '${(_width * 100).toStringAsFixed(0)}%',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _width = v * 2.0);
              _setParam(_P.width, _width);
            },
          ),
        ],
      ),
    );
  }

  String _formatDecay(double d) {
    final seconds = 0.1 * math.pow(20 / 0.1, d);
    return seconds >= 1 ? '${seconds.toStringAsFixed(1)}s' : '${(seconds * 1000).toStringAsFixed(0)}ms';
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
      size: 36,
      onChanged: onChanged,
    );
  }

  // ─── Character + Tonal Decay Section ──────────────────────────────────

  Widget _buildCharacterSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT: Diffusion, Distance, Character, Thickness
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FabSectionLabel('CHARACTER'),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _knob(
                      value: _diffusion, label: 'DIFF',
                      display: '${(_diffusion * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbAccent,
                      onChanged: (v) {
                        setState(() => _diffusion = v);
                        _setParam(_P.diffusion, v);
                      },
                    ),
                    _knob(
                      value: _distance, label: 'DIST',
                      display: '${(_distance * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbPredelay,
                      onChanged: (v) {
                        setState(() => _distance = v);
                        _setParam(_P.distance, v);
                      },
                    ),
                    _knob(
                      value: _character, label: 'CHAR',
                      display: '${(_character * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbDecay,
                      onChanged: (v) {
                        setState(() => _character = v);
                        _setParam(_P.character, v);
                      },
                    ),
                    _knob(
                      value: _thickness, label: 'THICK',
                      display: '${(_thickness * 100).toStringAsFixed(0)}%',
                      color: FabFilterColors.orange,
                      onChanged: (v) {
                        setState(() => _thickness = v);
                        _setParam(_P.thickness, v);
                      },
                    ),
                    _knob(
                      value: _spin, label: 'SPIN',
                      display: '${(1.0 + _spin * 4.0).toStringAsFixed(1)} Hz',
                      color: FabFilterColors.cyan,
                      onChanged: (v) {
                        setState(() => _spin = v);
                        _setParam(_P.spin, v);
                      },
                    ),
                    _knob(
                      value: _wander, label: 'WNDR',
                      display: '${(0.05 + _wander * 0.45).toStringAsFixed(2)} Hz',
                      color: FabFilterProcessorColors.reverbPredelay,
                      onChanged: (v) {
                        setState(() => _wander = v);
                        _setParam(_P.wander, v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // RIGHT: Ducking + Tonal Decay
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FabSectionLabel('DYNAMICS'),
              const SizedBox(height: 2),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _knob(
                      value: _ducking, label: 'DUCK',
                      display: '${(_ducking * 100).toStringAsFixed(0)}%',
                      color: FabFilterColors.green,
                      onChanged: (v) {
                        setState(() => _ducking = v);
                        _setParam(_P.ducking, v);
                      },
                    ),
                    _knob(
                      value: (_lowDecay - 0.5) / 1.5, label: 'LO ×',
                      display: '${_lowDecay.toStringAsFixed(2)}×',
                      color: FabFilterColors.orange,
                      onChanged: (v) {
                        setState(() => _lowDecay = 0.5 + v * 1.5);
                        _setParam(_P.lowDecay, _lowDecay);
                      },
                    ),
                    _knob(
                      value: (_lowmidDecay - 0.5) / 1.5, label: 'LM ×',
                      display: '${_lowmidDecay.toStringAsFixed(2)}×',
                      color: FabFilterColors.orange,
                      onChanged: (v) {
                        setState(() => _lowmidDecay = 0.5 + v * 1.5);
                        _setParam(_P.lowmidDecay, _lowmidDecay);
                      },
                    ),
                    _knob(
                      value: (_highmidDecay - 0.5) / 1.5, label: 'HM ×',
                      display: '${_highmidDecay.toStringAsFixed(2)}×',
                      color: FabFilterColors.cyan,
                      onChanged: (v) {
                        setState(() => _highmidDecay = 0.5 + v * 1.5);
                        _setParam(_P.highmidDecay, _highmidDecay);
                      },
                    ),
                    _knob(
                      value: (_highDecay - 0.1) / 0.9, label: 'HI ×',
                      display: '${_highDecay.toStringAsFixed(2)}×',
                      color: FabFilterColors.cyan,
                      onChanged: (v) {
                        setState(() => _highDecay = 0.1 + v * 0.9);
                        _setParam(_P.highDecay, _highDecay);
                      },
                    ),
                    _knob(
                      value: _erLevel, label: 'ER',
                      display: '${(_erLevel * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbAccent,
                      onChanged: (v) {
                        setState(() => _erLevel = v);
                        _setParam(_P.erLevel, v);
                      },
                    ),
                    _knob(
                      value: _lateLevel, label: 'LATE',
                      display: '${(_lateLevel * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbDecay,
                      onChanged: (v) {
                        setState(() => _lateLevel = v);
                        _setParam(_P.lateLevel, v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              FabSectionLabel('OUTPUT'),
              const SizedBox(height: 2),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _knob(
                      value: (_outEqLoGain + 12.0) / 24.0, label: 'LO EQ',
                      display: '${_outEqLoGain.toStringAsFixed(1)}dB',
                      color: FabFilterColors.orange,
                      onChanged: (v) {
                        setState(() => _outEqLoGain = v * 24.0 - 12.0);
                        _setParam(_P.outEqLoGain, _outEqLoGain);
                      },
                    ),
                    _knob(
                      value: (_outEqMidGain + 12.0) / 24.0, label: 'MID EQ',
                      display: '${_outEqMidGain.toStringAsFixed(1)}dB',
                      color: FabFilterColors.green,
                      onChanged: (v) {
                        setState(() => _outEqMidGain = v * 24.0 - 12.0);
                        _setParam(_P.outEqMidGain, _outEqMidGain);
                      },
                    ),
                    _knob(
                      value: (_outEqHiGain + 12.0) / 24.0, label: 'HI EQ',
                      display: '${_outEqHiGain.toStringAsFixed(1)}dB',
                      color: FabFilterColors.cyan,
                      onChanged: (v) {
                        setState(() => _outEqHiGain = v * 24.0 - 12.0);
                        _setParam(_P.outEqHiGain, _outEqHiGain);
                      },
                    ),
                    _knob(
                      value: _pdFeedback / 0.5, label: 'PD FB',
                      display: '${(_pdFeedback * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbAccent,
                      onChanged: (v) {
                        setState(() => _pdFeedback = v * 0.5);
                        _setParam(_P.pdFeedback, _pdFeedback);
                      },
                    ),
                    // Soft Limiter toggle
                    GestureDetector(
                      onTap: () {
                        setState(() => _softLimiter = !_softLimiter);
                        _setParam(_P.softLimiter, _softLimiter ? 1.0 : 0.0);
                      },
                      child: Container(
                        width: 36, height: 24,
                        decoration: BoxDecoration(
                          color: _softLimiter ? FabFilterColors.blue : FabFilterColors.bgVoid,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FabFilterColors.borderSubtle),
                        ),
                        alignment: Alignment.center,
                        child: Text('LIM', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w600,
                          color: _softLimiter ? Colors.white : FabFilterColors.textMuted,
                        )),
                      ),
                    ),
                    // BPM Sync toggle (R8.6)
                    GestureDetector(
                      onTap: () {
                        setState(() => _bpmSync = !_bpmSync);
                        _setParam(_P.bpmSync, _bpmSync ? 1.0 : 0.0);
                      },
                      child: Container(
                        width: 36, height: 24,
                        decoration: BoxDecoration(
                          color: _bpmSync ? FabFilterColors.purple : FabFilterColors.bgVoid,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FabFilterColors.borderSubtle),
                        ),
                        alignment: Alignment.center,
                        child: Text('SYNC', style: TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w600,
                          color: _bpmSync ? Colors.white : FabFilterColors.textMuted,
                        )),
                      ),
                    ),
                    // Note division picker (R8.6)
                    if (_bpmSync) GestureDetector(
                      onTap: () {
                        setState(() => _noteDiv = (_noteDiv + 1) % 8);
                        _setParam(_P.noteDiv, _noteDiv.toDouble());
                      },
                      child: Container(
                        width: 32, height: 24,
                        decoration: BoxDecoration(
                          color: FabFilterColors.bgVoid,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FabFilterColors.purple.withValues(alpha: 0.3)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          const ['1/1', '1/2', '1/4', '1/8', '1/16', '1/4.', '1/8.', '1/4T'][_noteDiv.clamp(0, 7)],
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: FabFilterColors.purple),
                        ),
                      ),
                    ),
                    // FDN Size picker (R8.7)
                    GestureDetector(
                      onTap: () {
                        setState(() => _fdnSize = (_fdnSize + 1) % 3);
                        _setParam(_P.fdnSize, _fdnSize.toDouble());
                      },
                      child: Container(
                        width: 32, height: 24,
                        decoration: BoxDecoration(
                          color: FabFilterColors.bgVoid,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FabFilterColors.borderSubtle),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          const ['4×4', '8×8', '16'][_fdnSize.clamp(0, 2)],
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: FabFilterColors.textSecondary),
                        ),
                      ),
                    ),
                    // Matrix type picker (R8.7)
                    GestureDetector(
                      onTap: () {
                        setState(() => _matrixType = (_matrixType + 1) % 2);
                        _setParam(_P.matrixType, _matrixType.toDouble());
                      },
                      child: Container(
                        width: 36, height: 24,
                        decoration: BoxDecoration(
                          color: FabFilterColors.bgVoid,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FabFilterColors.borderSubtle),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _matrixType == 0 ? 'HAD' : 'HOU',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: FabFilterColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// MINI METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _MiniMeterPainter extends CustomPainter {
  final double value;
  final Color color;
  _MiniMeterPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      Paint()..color = FabFilterColors.bgVoid,
    );
    // Fill with gradient
    if (value > 0.001) {
      final fillWidth = size.width * value.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, fillWidth, size.height),
          const Radius.circular(2),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero, Offset(size.width, 0),
            [color.withValues(alpha: 0.6), color],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMeterPainter old) =>
      old.value != value || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// MIX BAR PAINTER (dry/wet indicator)
// ═══════════════════════════════════════════════════════════════════════════

class _MixBarPainter extends CustomPainter {
  final double mix;
  _MixBarPainter({required this.mix});

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    // Background
    canvas.drawRRect(rr, Paint()..color = FabFilterColors.borderSubtle);
    // Dry portion (left)
    final dryWidth = size.width * (1 - mix);
    if (dryWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, dryWidth, size.height),
          const Radius.circular(3),
        ),
        Paint()..color = FabFilterColors.textTertiary.withValues(alpha: 0.5),
      );
    }
    // Wet portion (right) — gradient fill
    final wetWidth = size.width * mix;
    if (wetWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - wetWidth, 0, wetWidth, size.height),
          const Radius.circular(3),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(size.width - wetWidth, 0), Offset(size.width, 0),
            [FabFilterColors.green.withValues(alpha: 0.5), FabFilterColors.green.withValues(alpha: 0.8)],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MixBarPainter old) => old.mix != mix;
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB DISPLAY PAINTER — Pro-R 2 Ultimate
// ═══════════════════════════════════════════════════════════════════════════

class _ReverbDisplayPainter extends CustomPainter {
  final double decay;
  final double predelay;
  final double space;
  final double brightness;
  final double lowDecayMult;
  final double lowmidDecayMult;
  final double highmidDecayMult;
  final double highDecayMult;
  final double animatedDecay;
  final bool freeze;
  final double freezeAnim;
  final double distance;
  final double wetLevel;
  final double inputLevel;
  final List<double> decayHistory;
  final int historyIndex;
  final double diffusion;
  final double mix;

  _ReverbDisplayPainter({
    required this.decay,
    required this.predelay,
    required this.space,
    required this.brightness,
    required this.lowDecayMult,
    required this.lowmidDecayMult,
    required this.highmidDecayMult,
    required this.highDecayMult,
    required this.animatedDecay,
    required this.freeze,
    required this.freezeAnim,
    required this.distance,
    required this.wetLevel,
    required this.inputLevel,
    required this.decayHistory,
    required this.historyIndex,
    required this.diffusion,
    required this.mix,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final decayTime = 0.1 * math.pow(20 / 0.1, decay);
    final maxTime = decayTime * 1.5;
    final predelayNorm = (predelay / 1000) / maxTime;
    final predelayX = predelayNorm * s.width;

    // ─── Glass background gradient ─────────────────────────────────────
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, s.height),
        [
          const Color(0xFF0D0D14),
          const Color(0xFF0A0A10),
          const Color(0xFF080810),
        ],
        [0.0, 0.5, 1.0],
      ));

    // Subtle radial ambience glow centered at decay peak
    canvas.drawCircle(
      Offset(predelayX + 20, s.height * 0.3),
      s.width * 0.4,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(predelayX + 20, s.height * 0.3),
          s.width * 0.4,
          [
            FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
    );

    // ─── Grid with subtle cross lines ──────────────────────────────────
    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;
    for (var i = 1; i <= 4; i++) {
      final x = (i / 5) * s.width;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), gridPaint);
    }
    for (var i = 1; i < 4; i++) {
      final y = (i / 4) * s.height;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), gridPaint);
    }

    // ─── Time axis labels ──────────────────────────────────────────────
    for (var i = 1; i <= 4; i++) {
      final t = (i / 5) * maxTime;
      final label = t >= 1.0 ? '${t.toStringAsFixed(1)}s' : '${(t * 1000).toStringAsFixed(0)}ms';
      _drawLabel(canvas, label, Offset((i / 5) * s.width - 10, s.height - 12),
        color: FabFilterColors.textTertiary.withValues(alpha: 0.4));
    }

    // ─── dB axis labels (left) ─────────────────────────────────────────
    for (var i = 0; i < 4; i++) {
      final db = -(i * 20);
      final y = (i / 4) * s.height;
      _drawLabel(canvas, '${db}dB', Offset(2, y + 1),
        color: FabFilterColors.textTertiary.withValues(alpha: 0.35));
    }

    // ─── Pre-delay region with glass effect ────────────────────────────
    if (predelayX > 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, predelayX, s.height),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero, Offset(predelayX, 0),
            [
              FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.08),
              FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.15),
            ],
          ),
      );
      // Pre-delay marker line with glow
      canvas.drawLine(
        Offset(predelayX, 0), Offset(predelayX, s.height),
        Paint()
          ..color = FabFilterProcessorColors.reverbPredelay
          ..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(predelayX, 0), Offset(predelayX, s.height),
        Paint()
          ..color = FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.3)
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // ─── Freeze overlay ────────────────────────────────────────────────
    if (freeze || freezeAnim > 0.01) {
      final fA = freezeAnim.clamp(0.0, 1.0);
      // Ice tint
      canvas.drawRect(rect,
        Paint()..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.05 * fA));
      // Freeze horizon line
      final freezeY = s.height * 0.2;
      canvas.drawLine(
        Offset(predelayX, freezeY), Offset(s.width, freezeY),
        Paint()
          ..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.4 * fA)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      // Glow on freeze line
      canvas.drawLine(
        Offset(predelayX, freezeY), Offset(s.width, freezeY),
        Paint()
          ..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.15 * fA)
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Ice crystal dots
      final rng = math.Random(77);
      for (var i = 0; i < (20 * fA).toInt(); i++) {
        final cx = predelayX + rng.nextDouble() * (s.width - predelayX);
        final cy = rng.nextDouble() * s.height;
        canvas.drawCircle(
          Offset(cx, cy), 1.0 + rng.nextDouble() * 1.5,
          Paint()..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.15 * fA),
        );
      }
    }

    // ─── Low-frequency decay band (warm tint fill) ─────────────────────
    if (lowDecayMult > 1.05) {
      final loPath = Path();
      loPath.moveTo(predelayX, s.height);
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space) * lowDecayMult));
        loPath.lineTo(x, s.height * (1 - amp * 0.9));
      }
      loPath.lineTo(s.width, s.height);
      loPath.close();
      canvas.drawPath(loPath, Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, s.height * 0.1), Offset(0, s.height),
          [
            FabFilterColors.orange.withValues(alpha: 0.12 * (lowDecayMult - 1.0).clamp(0.0, 1.0)),
            FabFilterColors.orange.withValues(alpha: 0.02),
          ],
        ));
    }

    // ─── Main decay envelope fill (glass gradient) ─────────────────────
    final decayPath = Path();
    decayPath.moveTo(predelayX, s.height);
    for (var x = predelayX; x <= s.width; x += 2) {
      final t = ((x - predelayX) / s.width) * maxTime;
      final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      decayPath.lineTo(x, s.height * (1 - amp));
    }
    decayPath.lineTo(s.width, s.height);
    decayPath.close();

    canvas.drawPath(decayPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0), Offset(0, s.height),
        [
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.45),
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.12),
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.03),
        ],
        [0.0, 0.5, 1.0],
      ));

    // ─── Decay outline with glow ─────────────────────────────────────
    final outlinePath = Path();
    bool first = true;
    for (var x = predelayX; x <= s.width; x += 2) {
      final t = ((x - predelayX) / s.width) * maxTime;
      final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      final y = s.height * (1 - amp * 0.9);
      if (first) { outlinePath.moveTo(x, y); first = false; } else { outlinePath.lineTo(x, y); }
    }
    // Glow behind main curve
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.25)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // Main curve
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterProcessorColors.reverbAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);

    // ─── High-frequency decay envelope (shorter, cyan) ─────────────────
    if (highDecayMult < 0.95) {
      final hiPath = Path();
      bool hiFirst = true;
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.7 : math.exp(-t / (decayTime * 0.3 * (1 + space) * highDecayMult));
        final y = s.height * (1 - amp * 0.9);
        if (hiFirst) { hiPath.moveTo(x, y); hiFirst = false; } else { hiPath.lineTo(x, y); }
      }
      // Glow
      canvas.drawPath(hiPath, Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.15)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawPath(hiPath, Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.6)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // ─── LowMid decay band (R8.1) ─────────────────────────────────────
    if ((lowmidDecayMult - 1.0).abs() > 0.05) {
      final lmPath = Path();
      bool lmFirst = true;
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.75 : math.exp(-t / (decayTime * 0.3 * (1 + space) * lowmidDecayMult));
        final y = s.height * (1 - amp * 0.9);
        if (lmFirst) { lmPath.moveTo(x, y); lmFirst = false; } else { lmPath.lineTo(x, y); }
      }
      canvas.drawPath(lmPath, Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.12)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawPath(lmPath, Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // ─── HighMid decay band (R8.1) ──────────────────────────────────
    if ((highmidDecayMult - 1.0).abs() > 0.05) {
      final hmPath = Path();
      bool hmFirst = true;
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.7 : math.exp(-t / (decayTime * 0.3 * (1 + space) * highmidDecayMult));
        final y = s.height * (1 - amp * 0.9);
        if (hmFirst) { hmPath.moveTo(x, y); hmFirst = false; } else { hmPath.lineTo(x, y); }
      }
      canvas.drawPath(hmPath, Paint()
        ..color = FabFilterColors.green.withValues(alpha: 0.12)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawPath(hmPath, Paint()
        ..color = FabFilterColors.green.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // ─── Early reflections (glass impulse lines) ─────────────────────
    final erRng = math.Random(42);
    final erCount = (space * 12 + 4).toInt();
    final erSpread = distance.clamp(0.05, 1.0) * 0.15;
    for (var i = 0; i < erCount; i++) {
      final t = predelay / 1000 + erRng.nextDouble() * erSpread;
      final x = (t / maxTime) * s.width;
      final amp = 0.3 + erRng.nextDouble() * 0.5;
      if (x > predelayX && x < s.width * 0.4) {
        final alpha = 0.3 + erRng.nextDouble() * 0.4;
        final erY = s.height * (1 - amp);
        // Glass glow behind each ER line
        canvas.drawLine(
          Offset(x, s.height),
          Offset(x, erY),
          Paint()
            ..color = FabFilterProcessorColors.reverbEarlyRef.withValues(alpha: alpha * 0.15)
            ..strokeWidth = 4
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        // ER line
        canvas.drawLine(
          Offset(x, s.height),
          Offset(x, erY),
          Paint()
            ..color = FabFilterProcessorColors.reverbEarlyRef.withValues(alpha: alpha)
            ..strokeWidth = 1.5,
        );
        // Top dot
        canvas.drawCircle(
          Offset(x, erY), 2,
          Paint()..color = FabFilterProcessorColors.reverbEarlyRef.withValues(alpha: alpha * 0.8),
        );
      }
    }

    // ─── Real-time wet level indicator (glass node) ───────────────────
    if (wetLevel > 0.001) {
      final levelY = s.height * (1 - wetLevel.clamp(0.0, 1.0) * 0.85);
      final indicatorX = predelayX + 8;
      // Outer glow
      canvas.drawCircle(
        Offset(indicatorX, levelY), 8,
        Paint()
          ..color = FabFilterColors.green.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Glass circle
      canvas.drawCircle(
        Offset(indicatorX, levelY), 5,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(indicatorX - 1, levelY - 1), 5,
            [
              FabFilterColors.green.withValues(alpha: 0.9),
              FabFilterColors.green.withValues(alpha: 0.4),
            ],
          ),
      );
      // Highlight
      canvas.drawCircle(
        Offset(indicatorX - 1.5, levelY - 1.5), 2,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }

    // ─── Input level indicator ────────────────────────────────────────
    if (inputLevel > 0.001) {
      final inY = s.height * (1 - inputLevel.clamp(0.0, 1.0) * 0.85);
      // Small cyan diamond at left edge
      final diamondPath = Path();
      diamondPath.moveTo(3, inY);
      diamondPath.lineTo(6, inY - 3);
      diamondPath.lineTo(9, inY);
      diamondPath.lineTo(6, inY + 3);
      diamondPath.close();
      canvas.drawPath(diamondPath, Paint()..color = FabFilterColors.cyan.withValues(alpha: 0.6));
    }

    // ─── Decay tail sparkle (history waveform) ────────────────────────
    final histLen = decayHistory.length;
    if (histLen > 0) {
      final sparkPath = Path();
      bool sparkFirst = true;
      for (var i = 0; i < histLen; i++) {
        final idx = (historyIndex - histLen + i) % histLen;
        final val = decayHistory[idx < 0 ? idx + histLen : idx];
        if (val > 0.005) {
          final age = i / histLen;
          final x = predelayX + (s.width - predelayX) * (i / histLen);
          final y = s.height * (1 - val.clamp(0.0, 1.0) * 0.7);
          if (sparkFirst) { sparkPath.moveTo(x, y); sparkFirst = false; } else { sparkPath.lineTo(x, y); }
        }
      }
      if (!sparkFirst) {
        // Glow trail
        canvas.drawPath(sparkPath, Paint()
          ..color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.1)
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        // Sparkle trail line
        canvas.drawPath(sparkPath, Paint()
          ..color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.3)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke);
      }
    }

    // ─── Diffusion indicator (top-left) ────────────────────────────────
    if (diffusion > 0.05) {
      final diffW = s.width * 0.15 * diffusion;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(predelayX + 2, 3, diffW, 4),
          const Radius.circular(2),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(predelayX + 2, 0), Offset(predelayX + 2 + diffW, 0),
            [
              FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.4),
              FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.1),
            ],
          ),
      );
    }

    // ─── Decay time label ──────────────────────────────────────────────
    _drawLabel(canvas, '${decayTime.toStringAsFixed(1)}s',
      Offset(s.width - 36, 4),
      color: FabFilterProcessorColors.reverbDecay);

    // Pre-delay label
    if (predelay > 5) {
      _drawLabel(canvas, '${predelay.toStringAsFixed(0)}ms',
        Offset(math.max(2, predelayX - 30), s.height - 14),
        color: FabFilterProcessorColors.reverbPredelay);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, {Color? color}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? FabFilterColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ReverbDisplayPainter old) =>
      old.decay != decay ||
      old.predelay != predelay ||
      old.space != space ||
      old.animatedDecay != animatedDecay ||
      old.freeze != freeze ||
      old.freezeAnim != freezeAnim ||
      old.lowDecayMult != lowDecayMult ||
      old.highDecayMult != highDecayMult ||
      old.brightness != brightness ||
      old.distance != distance ||
      old.wetLevel != wetLevel ||
      old.inputLevel != inputLevel ||
      old.historyIndex != historyIndex ||
      old.diffusion != diffusion ||
      old.mix != mix;
}
