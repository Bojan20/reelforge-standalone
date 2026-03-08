/// FF-DLY Delay Panel — Timeless 3 Style
///
/// Professional stereo delay processor:
/// - Delay tap visualization with feedback trails
/// - Linked/unlinked L/R delay times
/// - Ping-pong stereo bounce mode
/// - HP/LP feedback filters
/// - Modulation (rate + depth)
/// - Ducking, freeze, tempo sync
/// - Real-time I/O metering at ~30fps
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
// PARAMETER INDICES (must match Rust DelayWrapper)
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const delayL = 0;
  static const delayR = 1;
  static const feedback = 2;
  static const mix = 3;
  static const pingPong = 4;
  static const hpFilter = 5;
  static const lpFilter = 6;
  static const modRate = 7;
  static const modDepth = 8;
  static const width = 9;
  static const ducking = 10;
  static const link = 11;
  static const freeze = 12;
  static const tempoSync = 13;
  // D1 — Feedback Filter Upgrade params
  static const hpQ = 14;
  static const lpQ = 15;
  static const midFreq = 16;
  static const midQ = 17;
  static const midGain = 18;
  static const drive = 19;
  static const driveMode = 20;
  static const tilt = 21;
  static const filterLfoRate = 22;
  static const filterLfoDepth = 23;
  // D2 — Modulation Engine params
  static const lfo1Rate = 24;
  static const lfo1Depth = 25;
  static const lfo1Shape = 26;
  static const lfo1Sync = 27;
  static const lfo1SyncDiv = 28;
  static const lfo1Retrigger = 29;
  static const lfo2Rate = 30;
  static const lfo2Depth = 31;
  static const lfo2Shape = 32;
  static const lfo2Sync = 33;
  static const lfo2SyncDiv = 34;
  static const envSensitivity = 35;
  static const envAttack = 36;
  static const envRelease = 37;
  static const pitchShift = 38;
  static const modRouting = 39;
  // D3 — Tempo Sync & Rhythm
  static const bpm = 40;
  static const noteValueL = 41;
  static const noteValueR = 42;
  static const swing = 43;
  // D7 — Vintage Character
  static const vintageMode = 44;
  static const vintageAmount = 45;
  // D5 — Stereo & Spatial
  static const stereoRouting = 46;
  static const crossFeedback = 47;
  static const haasDelay = 48;
  static const diffusion = 49;
  // D6 — Freeze & Glitch
  static const reverse = 50;
  static const stutter = 51;
  static const stutterRate = 52;
  static const infiniteFB = 53;
  // D10 — Advanced
  static const sidechain = 54;
  static const midiTrigger = 55;
  static const smoothing = 56;
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class DelaySnapshot implements DspParameterSnapshot {
  final double delayL, delayR, feedback, mix, pingPong;
  final double hpFilter, lpFilter, modRate, modDepth;
  final double width, ducking;
  final bool link, freeze, tempoSync;
  // D1 — Feedback Filter Upgrade
  final double hpQ, lpQ, midFreq, midQ, midGain;
  final double drive, tilt, filterLfoRate, filterLfoDepth;
  final int driveMode;
  // D2 — Modulation Engine
  final double lfo1Rate, lfo1Depth, lfo2Rate, lfo2Depth;
  final int lfo1Shape, lfo2Shape;
  final bool lfo1Sync, lfo2Sync, lfo1Retrigger;
  final int lfo1SyncDiv, lfo2SyncDiv;
  final double envSensitivity, envAttack, envRelease;
  final double pitchShift;
  final int modRouting;
  // D3 — Tempo Sync
  final double bpm, swing;
  final int noteValueL, noteValueR;
  // D7 — Vintage
  final int vintageMode;
  final double vintageAmount;
  // D5 — Stereo
  final int stereoRouting;
  final double crossFeedback, haasDelay, diffusion;
  // D6 — Freeze & Glitch
  final bool reverse, stutter, infiniteFB;
  final double stutterRate;
  // D10 — Advanced
  final bool sidechainEnabled;
  final int midiTriggerMode;
  final double smoothing;

  const DelaySnapshot({
    required this.delayL, required this.delayR, required this.feedback,
    required this.mix, required this.pingPong, required this.hpFilter,
    required this.lpFilter, required this.modRate, required this.modDepth,
    required this.width, required this.ducking, required this.link,
    required this.freeze, required this.tempoSync,
    required this.hpQ, required this.lpQ, required this.midFreq,
    required this.midQ, required this.midGain, required this.drive,
    required this.driveMode, required this.tilt,
    required this.filterLfoRate, required this.filterLfoDepth,
    required this.lfo1Rate, required this.lfo1Depth, required this.lfo1Shape,
    required this.lfo1Sync, required this.lfo1SyncDiv, required this.lfo1Retrigger,
    required this.lfo2Rate, required this.lfo2Depth, required this.lfo2Shape,
    required this.lfo2Sync, required this.lfo2SyncDiv,
    required this.envSensitivity, required this.envAttack, required this.envRelease,
    required this.pitchShift, required this.modRouting,
    required this.bpm, required this.noteValueL, required this.noteValueR,
    required this.swing, required this.vintageMode, required this.vintageAmount,
    required this.stereoRouting, required this.crossFeedback,
    required this.haasDelay, required this.diffusion,
    required this.reverse, required this.stutter, required this.stutterRate,
    required this.infiniteFB,
    this.sidechainEnabled = false, this.midiTriggerMode = 0, this.smoothing = 0.0,
  });

  @override
  DelaySnapshot copy() => DelaySnapshot(
    delayL: delayL, delayR: delayR, feedback: feedback, mix: mix,
    pingPong: pingPong, hpFilter: hpFilter, lpFilter: lpFilter,
    modRate: modRate, modDepth: modDepth, width: width, ducking: ducking,
    link: link, freeze: freeze, tempoSync: tempoSync,
    hpQ: hpQ, lpQ: lpQ, midFreq: midFreq, midQ: midQ, midGain: midGain,
    drive: drive, driveMode: driveMode, tilt: tilt,
    filterLfoRate: filterLfoRate, filterLfoDepth: filterLfoDepth,
    lfo1Rate: lfo1Rate, lfo1Depth: lfo1Depth, lfo1Shape: lfo1Shape,
    lfo1Sync: lfo1Sync, lfo1SyncDiv: lfo1SyncDiv, lfo1Retrigger: lfo1Retrigger,
    lfo2Rate: lfo2Rate, lfo2Depth: lfo2Depth, lfo2Shape: lfo2Shape,
    lfo2Sync: lfo2Sync, lfo2SyncDiv: lfo2SyncDiv,
    envSensitivity: envSensitivity, envAttack: envAttack, envRelease: envRelease,
    pitchShift: pitchShift, modRouting: modRouting,
    bpm: bpm, noteValueL: noteValueL, noteValueR: noteValueR,
    swing: swing, vintageMode: vintageMode, vintageAmount: vintageAmount,
    stereoRouting: stereoRouting, crossFeedback: crossFeedback,
    haasDelay: haasDelay, diffusion: diffusion,
    reverse: reverse, stutter: stutter, stutterRate: stutterRate,
    infiniteFB: infiniteFB,
    sidechainEnabled: sidechainEnabled, midiTriggerMode: midiTriggerMode,
    smoothing: smoothing,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! DelaySnapshot) return false;
    return delayL == other.delayL && delayR == other.delayR &&
        feedback == other.feedback && mix == other.mix &&
        pingPong == other.pingPong && hpFilter == other.hpFilter &&
        lpFilter == other.lpFilter && modRate == other.modRate &&
        modDepth == other.modDepth && width == other.width &&
        ducking == other.ducking && link == other.link &&
        freeze == other.freeze && tempoSync == other.tempoSync &&
        hpQ == other.hpQ && lpQ == other.lpQ &&
        midFreq == other.midFreq && midQ == other.midQ &&
        midGain == other.midGain && drive == other.drive &&
        driveMode == other.driveMode && tilt == other.tilt &&
        filterLfoRate == other.filterLfoRate &&
        filterLfoDepth == other.filterLfoDepth &&
        lfo1Rate == other.lfo1Rate && lfo1Depth == other.lfo1Depth &&
        lfo1Shape == other.lfo1Shape && lfo1Sync == other.lfo1Sync &&
        lfo1SyncDiv == other.lfo1SyncDiv &&
        lfo1Retrigger == other.lfo1Retrigger &&
        lfo2Rate == other.lfo2Rate && lfo2Depth == other.lfo2Depth &&
        lfo2Shape == other.lfo2Shape && lfo2Sync == other.lfo2Sync &&
        lfo2SyncDiv == other.lfo2SyncDiv &&
        envSensitivity == other.envSensitivity &&
        envAttack == other.envAttack && envRelease == other.envRelease &&
        pitchShift == other.pitchShift && modRouting == other.modRouting &&
        bpm == other.bpm && noteValueL == other.noteValueL &&
        noteValueR == other.noteValueR && swing == other.swing &&
        vintageMode == other.vintageMode &&
        vintageAmount == other.vintageAmount &&
        stereoRouting == other.stereoRouting &&
        crossFeedback == other.crossFeedback &&
        haasDelay == other.haasDelay && diffusion == other.diffusion &&
        reverse == other.reverse && stutter == other.stutter &&
        stutterRate == other.stutterRate && infiniteFB == other.infiniteFB &&
        sidechainEnabled == other.sidechainEnabled &&
        midiTriggerMode == other.midiTriggerMode &&
        smoothing == other.smoothing;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterDelayPanel extends FabFilterPanelBase {
  const FabFilterDelayPanel({
    super.key,
    required super.trackId,
    super.slotIndex,
  }) : super(
          title: 'FF-DLY',
          icon: Icons.timer,
          accentColor: FabFilterColors.cyan,
          nodeType: DspNodeType.delay,
        );

  @override
  State<FabFilterDelayPanel> createState() => _FabFilterDelayPanelState();
}

class _FabFilterDelayPanelState extends State<FabFilterDelayPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {

  // ─── DSP PARAMETERS ──────────────────────────────────────────────────
  double _delayL = 375.0;
  double _delayR = 375.0;
  double _feedback = 40.0;
  double _mix = 30.0;
  double _pingPong = 0.0;
  double _hpFilter = 80.0;
  double _lpFilter = 12000.0;
  double _modRate = 0.5;
  double _modDepth = 10.0;
  double _width = 100.0;
  double _ducking = 0.0;
  bool _link = true;
  bool _freeze = false;
  bool _tempoSync = false;

  // D1 — Feedback Filter Upgrade
  double _hpQ = 0.707;
  double _lpQ = 0.707;
  double _midFreq = 1000.0;
  double _midQ = 1.0;
  double _midGain = 0.0;
  double _drive = 0.0;
  int _driveMode = 0; // 0=Tube, 1=Tape, 2=Transistor
  double _tilt = 0.0;
  double _filterLfoRate = 0.0;
  double _filterLfoDepth = 0.0;

  // D2 — Modulation Engine
  double _lfo1Rate = 1.0;
  double _lfo1Depth = 0.0;
  int _lfo1Shape = 0;
  bool _lfo1Sync = false;
  int _lfo1SyncDiv = 7; // 1/4
  bool _lfo1Retrigger = false;
  double _lfo2Rate = 1.0;
  double _lfo2Depth = 0.0;
  int _lfo2Shape = 0;
  bool _lfo2Sync = false;
  int _lfo2SyncDiv = 7; // 1/4
  double _envSensitivity = 50.0;
  double _envAttack = 5.0;
  double _envRelease = 50.0;
  double _pitchShift = 0.0;
  int _modRouting = 0;

  // D3 — Tempo Sync
  double _bpm = 120.0;
  int _noteValueL = 9; // 1/4
  int _noteValueR = 9;
  double _swing = 0.0;

  // D7 — Vintage
  int _vintageMode = 0; // 0=Clean
  double _vintageAmount = 50.0;

  // D5 — Stereo
  int _stereoRouting = 1; // 1=PingPong
  double _crossFeedback = 0.0;
  double _haasDelay = 0.0;
  double _diffusion = 0.0;

  // D6 — Freeze & Glitch
  bool _reverse = false;
  bool _stutter = false;
  double _stutterRate = 125.0;
  bool _infiniteFB = false;

  // D10 — Advanced
  bool _sidechainEnabled = false;
  int _midiTriggerMode = 0;
  double _smoothing = 0.0;

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
  DelaySnapshot? _snapshotA;
  DelaySnapshot? _snapshotB;

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
      if (node.type == DspNodeType.delay) {
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
      _delayL = _ffi.insertGetParam(t, s, _P.delayL);
      _delayR = _ffi.insertGetParam(t, s, _P.delayR);
      _feedback = _ffi.insertGetParam(t, s, _P.feedback);
      _mix = _ffi.insertGetParam(t, s, _P.mix);
      _pingPong = _ffi.insertGetParam(t, s, _P.pingPong);
      _hpFilter = _ffi.insertGetParam(t, s, _P.hpFilter);
      _lpFilter = _ffi.insertGetParam(t, s, _P.lpFilter);
      _modRate = _ffi.insertGetParam(t, s, _P.modRate);
      _modDepth = _ffi.insertGetParam(t, s, _P.modDepth);
      _width = _ffi.insertGetParam(t, s, _P.width);
      _ducking = _ffi.insertGetParam(t, s, _P.ducking);
      _link = _ffi.insertGetParam(t, s, _P.link) > 0.5;
      _freeze = _ffi.insertGetParam(t, s, _P.freeze) > 0.5;
      _tempoSync = _ffi.insertGetParam(t, s, _P.tempoSync) > 0.5;
      // D1 params
      _hpQ = _ffi.insertGetParam(t, s, _P.hpQ);
      _lpQ = _ffi.insertGetParam(t, s, _P.lpQ);
      _midFreq = _ffi.insertGetParam(t, s, _P.midFreq);
      _midQ = _ffi.insertGetParam(t, s, _P.midQ);
      _midGain = _ffi.insertGetParam(t, s, _P.midGain);
      _drive = _ffi.insertGetParam(t, s, _P.drive);
      _driveMode = _ffi.insertGetParam(t, s, _P.driveMode).round();
      _tilt = _ffi.insertGetParam(t, s, _P.tilt);
      _filterLfoRate = _ffi.insertGetParam(t, s, _P.filterLfoRate);
      _filterLfoDepth = _ffi.insertGetParam(t, s, _P.filterLfoDepth);
      // D2 params
      _lfo1Rate = _ffi.insertGetParam(t, s, _P.lfo1Rate);
      _lfo1Depth = _ffi.insertGetParam(t, s, _P.lfo1Depth);
      _lfo1Shape = _ffi.insertGetParam(t, s, _P.lfo1Shape).round();
      _lfo1Sync = _ffi.insertGetParam(t, s, _P.lfo1Sync) > 0.5;
      _lfo1SyncDiv = _ffi.insertGetParam(t, s, _P.lfo1SyncDiv).round();
      _lfo1Retrigger = _ffi.insertGetParam(t, s, _P.lfo1Retrigger) > 0.5;
      _lfo2Rate = _ffi.insertGetParam(t, s, _P.lfo2Rate);
      _lfo2Depth = _ffi.insertGetParam(t, s, _P.lfo2Depth);
      _lfo2Shape = _ffi.insertGetParam(t, s, _P.lfo2Shape).round();
      _lfo2Sync = _ffi.insertGetParam(t, s, _P.lfo2Sync) > 0.5;
      _lfo2SyncDiv = _ffi.insertGetParam(t, s, _P.lfo2SyncDiv).round();
      _envSensitivity = _ffi.insertGetParam(t, s, _P.envSensitivity);
      _envAttack = _ffi.insertGetParam(t, s, _P.envAttack);
      _envRelease = _ffi.insertGetParam(t, s, _P.envRelease);
      _pitchShift = _ffi.insertGetParam(t, s, _P.pitchShift);
      _modRouting = _ffi.insertGetParam(t, s, _P.modRouting).round();
      // D3
      _bpm = _ffi.insertGetParam(t, s, _P.bpm);
      _noteValueL = _ffi.insertGetParam(t, s, _P.noteValueL).round();
      _noteValueR = _ffi.insertGetParam(t, s, _P.noteValueR).round();
      _swing = _ffi.insertGetParam(t, s, _P.swing);
      // D7
      _vintageMode = _ffi.insertGetParam(t, s, _P.vintageMode).round();
      _vintageAmount = _ffi.insertGetParam(t, s, _P.vintageAmount);
      // D5
      _stereoRouting = _ffi.insertGetParam(t, s, _P.stereoRouting).round();
      _crossFeedback = _ffi.insertGetParam(t, s, _P.crossFeedback);
      _haasDelay = _ffi.insertGetParam(t, s, _P.haasDelay);
      _diffusion = _ffi.insertGetParam(t, s, _P.diffusion);
      // D6
      _reverse = _ffi.insertGetParam(t, s, _P.reverse) > 0.5;
      _stutter = _ffi.insertGetParam(t, s, _P.stutter) > 0.5;
      _stutterRate = _ffi.insertGetParam(t, s, _P.stutterRate);
      _infiniteFB = _ffi.insertGetParam(t, s, _P.infiniteFB) > 0.5;
      // D10
      _sidechainEnabled = _ffi.insertGetParam(t, s, _P.sidechain) > 0.5;
      _midiTriggerMode = _ffi.insertGetParam(t, s, _P.midiTrigger).round();
      _smoothing = _ffi.insertGetParam(t, s, _P.smoothing);
    });
  }

  void _setParam(int idx, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, idx, value);
    }
  }

  // ─── A/B STATE ───────────────────────────────────────────────────────

  DelaySnapshot _snap() => DelaySnapshot(
    delayL: _delayL, delayR: _delayR, feedback: _feedback, mix: _mix,
    pingPong: _pingPong, hpFilter: _hpFilter, lpFilter: _lpFilter,
    modRate: _modRate, modDepth: _modDepth, width: _width,
    ducking: _ducking, link: _link, freeze: _freeze, tempoSync: _tempoSync,
    hpQ: _hpQ, lpQ: _lpQ, midFreq: _midFreq, midQ: _midQ,
    midGain: _midGain, drive: _drive, driveMode: _driveMode, tilt: _tilt,
    filterLfoRate: _filterLfoRate, filterLfoDepth: _filterLfoDepth,
    lfo1Rate: _lfo1Rate, lfo1Depth: _lfo1Depth, lfo1Shape: _lfo1Shape,
    lfo1Sync: _lfo1Sync, lfo1SyncDiv: _lfo1SyncDiv, lfo1Retrigger: _lfo1Retrigger,
    lfo2Rate: _lfo2Rate, lfo2Depth: _lfo2Depth, lfo2Shape: _lfo2Shape,
    lfo2Sync: _lfo2Sync, lfo2SyncDiv: _lfo2SyncDiv,
    envSensitivity: _envSensitivity, envAttack: _envAttack, envRelease: _envRelease,
    pitchShift: _pitchShift, modRouting: _modRouting,
    bpm: _bpm, noteValueL: _noteValueL, noteValueR: _noteValueR,
    swing: _swing, vintageMode: _vintageMode, vintageAmount: _vintageAmount,
    stereoRouting: _stereoRouting, crossFeedback: _crossFeedback,
    haasDelay: _haasDelay, diffusion: _diffusion,
    reverse: _reverse, stutter: _stutter, stutterRate: _stutterRate,
    infiniteFB: _infiniteFB,
    sidechainEnabled: _sidechainEnabled, midiTriggerMode: _midiTriggerMode,
    smoothing: _smoothing,
  );

  void _restore(DelaySnapshot s) {
    setState(() {
      _delayL = s.delayL; _delayR = s.delayR; _feedback = s.feedback;
      _mix = s.mix; _pingPong = s.pingPong; _hpFilter = s.hpFilter;
      _lpFilter = s.lpFilter; _modRate = s.modRate; _modDepth = s.modDepth;
      _width = s.width; _ducking = s.ducking; _link = s.link;
      _freeze = s.freeze; _tempoSync = s.tempoSync;
      _hpQ = s.hpQ; _lpQ = s.lpQ; _midFreq = s.midFreq; _midQ = s.midQ;
      _midGain = s.midGain; _drive = s.drive; _driveMode = s.driveMode;
      _tilt = s.tilt; _filterLfoRate = s.filterLfoRate;
      _filterLfoDepth = s.filterLfoDepth;
      // D2
      _lfo1Rate = s.lfo1Rate; _lfo1Depth = s.lfo1Depth; _lfo1Shape = s.lfo1Shape;
      _lfo1Sync = s.lfo1Sync; _lfo1SyncDiv = s.lfo1SyncDiv; _lfo1Retrigger = s.lfo1Retrigger;
      _lfo2Rate = s.lfo2Rate; _lfo2Depth = s.lfo2Depth; _lfo2Shape = s.lfo2Shape;
      _lfo2Sync = s.lfo2Sync; _lfo2SyncDiv = s.lfo2SyncDiv;
      _envSensitivity = s.envSensitivity; _envAttack = s.envAttack; _envRelease = s.envRelease;
      _pitchShift = s.pitchShift; _modRouting = s.modRouting;
      // D3+D7
      _bpm = s.bpm; _noteValueL = s.noteValueL; _noteValueR = s.noteValueR;
      _swing = s.swing; _vintageMode = s.vintageMode; _vintageAmount = s.vintageAmount;
      // D5
      _stereoRouting = s.stereoRouting; _crossFeedback = s.crossFeedback;
      _haasDelay = s.haasDelay; _diffusion = s.diffusion;
      // D6
      _reverse = s.reverse; _stutter = s.stutter;
      _stutterRate = s.stutterRate; _infiniteFB = s.infiniteFB;
      // D10
      _sidechainEnabled = s.sidechainEnabled; _midiTriggerMode = s.midiTriggerMode;
      _smoothing = s.smoothing;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.delayL, _delayL);
    _setParam(_P.delayR, _delayR);
    _setParam(_P.feedback, _feedback);
    _setParam(_P.mix, _mix);
    _setParam(_P.pingPong, _pingPong);
    _setParam(_P.hpFilter, _hpFilter);
    _setParam(_P.lpFilter, _lpFilter);
    _setParam(_P.modRate, _modRate);
    _setParam(_P.modDepth, _modDepth);
    _setParam(_P.width, _width);
    _setParam(_P.ducking, _ducking);
    _setParam(_P.link, _link ? 1.0 : 0.0);
    _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
    _setParam(_P.tempoSync, _tempoSync ? 1.0 : 0.0);
    _setParam(_P.hpQ, _hpQ);
    _setParam(_P.lpQ, _lpQ);
    _setParam(_P.midFreq, _midFreq);
    _setParam(_P.midQ, _midQ);
    _setParam(_P.midGain, _midGain);
    _setParam(_P.drive, _drive);
    _setParam(_P.driveMode, _driveMode.toDouble());
    _setParam(_P.tilt, _tilt);
    _setParam(_P.filterLfoRate, _filterLfoRate);
    _setParam(_P.filterLfoDepth, _filterLfoDepth);
    // D2
    _setParam(_P.lfo1Rate, _lfo1Rate);
    _setParam(_P.lfo1Depth, _lfo1Depth);
    _setParam(_P.lfo1Shape, _lfo1Shape.toDouble());
    _setParam(_P.lfo1Sync, _lfo1Sync ? 1.0 : 0.0);
    _setParam(_P.lfo1SyncDiv, _lfo1SyncDiv.toDouble());
    _setParam(_P.lfo1Retrigger, _lfo1Retrigger ? 1.0 : 0.0);
    _setParam(_P.lfo2Rate, _lfo2Rate);
    _setParam(_P.lfo2Depth, _lfo2Depth);
    _setParam(_P.lfo2Shape, _lfo2Shape.toDouble());
    _setParam(_P.lfo2Sync, _lfo2Sync ? 1.0 : 0.0);
    _setParam(_P.lfo2SyncDiv, _lfo2SyncDiv.toDouble());
    _setParam(_P.envSensitivity, _envSensitivity);
    _setParam(_P.envAttack, _envAttack);
    _setParam(_P.envRelease, _envRelease);
    _setParam(_P.pitchShift, _pitchShift);
    _setParam(_P.modRouting, _modRouting.toDouble());
    // D3
    _setParam(_P.bpm, _bpm);
    _setParam(_P.noteValueL, _noteValueL.toDouble());
    _setParam(_P.noteValueR, _noteValueR.toDouble());
    _setParam(_P.swing, _swing);
    // D7
    _setParam(_P.vintageMode, _vintageMode.toDouble());
    _setParam(_P.vintageAmount, _vintageAmount);
    // D5
    _setParam(_P.stereoRouting, _stereoRouting.toDouble());
    _setParam(_P.crossFeedback, _crossFeedback);
    _setParam(_P.haasDelay, _haasDelay);
    _setParam(_P.diffusion, _diffusion);
    // D6
    _setParam(_P.reverse, _reverse ? 1.0 : 0.0);
    _setParam(_P.stutter, _stutter ? 1.0 : 0.0);
    _setParam(_P.stutterRate, _stutterRate);
    _setParam(_P.infiniteFB, _infiniteFB ? 1.0 : 0.0);
    // D10
    _setParam(_P.sidechain, _sidechainEnabled ? 1.0 : 0.0);
    _setParam(_P.midiTrigger, _midiTriggerMode.toDouble());
    _setParam(_P.smoothing, _smoothing);
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

  // ─── METERING ────────────────────────────────────────────────────────

  void _updateMeters() {
    if (!mounted || !_initialized || _slotIndex < 0) return;
    setState(() {
      final t = widget.trackId, s = _slotIndex;
      try {
        _inPeakL = _ffi.insertGetMeter(t, s, 0);
        _inPeakR = _ffi.insertGetMeter(t, s, 1);
        _outPeakL = _ffi.insertGetMeter(t, s, 2);
        _outPeakR = _ffi.insertGetMeter(t, s, 3);
      } catch (e) {
        assert(() { debugPrint('Delay meter error: $e'); return true; }());
      }
    });
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────

  double _logNorm(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;
    return (math.log(value) - math.log(min)) / (math.log(max) - math.log(min));
  }

  double _logDenorm(double norm, double min, double max) {
    return math.exp(math.log(min) + norm * (math.log(max) - math.log(min)));
  }

  String _fmtMs(double ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)}s';
    if (ms >= 100) return '${ms.toStringAsFixed(0)}ms';
    return '${ms.toStringAsFixed(1)}ms';
  }

  String _fmtHz(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)}k';
    return '${hz.toStringAsFixed(0)}Hz';
  }

  String _fmtPct(double v) => '${v.toStringAsFixed(0)}%';

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('Delay', DspNodeType.delay, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildHeader(),
          // Delay tap visualization — flex scales with panel size
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildVisualization(),
            ),
          ),
          // Controls
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _buildMainKnobRow(),
                  const SizedBox(height: 6),
                  _buildSecondaryRow(),
                  const SizedBox(height: 4),
                  // D8.1: Tap timeline visualization
                  SizedBox(
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: CustomPaint(
                        size: const Size(double.infinity, 28),
                        painter: _TapTimelinePainter(
                          delayL: _delayL,
                          delayR: _delayR,
                          feedback: _feedback,
                          linked: _link,
                          stereoRouting: _stereoRouting,
                          freeze: _freeze,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(child: _buildExpertSection()),
                ],
              ),
            ),
          ),
          // Bottom toggles
          _buildBottomToggles(),
        ],
      ),
    ));
  }

  // ─── PRESET PICKER ───────────────────────────────────────────────────

  void _showPresetPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        final categories = _factoryPresets.map((p) => p.category).toSet().toList();
        return Dialog(
          backgroundColor: FabFilterColors.bgDeep,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 320,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('DELAY PRESETS', style: FabFilterText.sectionHeader.copyWith(
                    color: FabFilterColors.cyan, fontSize: 11, letterSpacing: 1.5,
                  )),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: categories.map((cat) {
                      final presets = _factoryPresets.where((p) => p.category == cat).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2, left: 4),
                            child: Text(cat.toUpperCase(), style: TextStyle(
                              color: FabFilterColors.textTertiary, fontSize: 8,
                              fontWeight: FontWeight.bold, letterSpacing: 1.2,
                            )),
                          ),
                          ...presets.map((p) => InkWell(
                            onTap: () {
                              _restore(p.snapshot);
                              Navigator.of(ctx).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Text(p.name, style: const TextStyle(
                                color: FabFilterColors.textPrimary, fontSize: 11,
                              )),
                            ),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── HEADER ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final inDb = _peakToDb(math.max(_inPeakL, _inPeakR));
    final outDb = _peakToDb(math.max(_outPeakL, _outPeakR));

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(bottom: BorderSide(color: FabFilterColors.cyan.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.timer, color: FabFilterColors.cyan, size: 14),
          const SizedBox(width: 6),
          Text('FF-DLY', style: FabFilterText.sectionHeader.copyWith(
            color: FabFilterColors.cyan, fontSize: 10, letterSpacing: 1.2,
          )),
          const SizedBox(width: 8),
          // Input meter
          _buildMiniMeter('IN', inDb),
          const SizedBox(width: 4),
          _buildMiniMeter('OUT', outDb),
          const Spacer(),
          FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: FabFilterColors.cyan),
          const SizedBox(width: 6),
          FabMiniButton(label: 'P', active: false, onTap: _showPresetPicker, accentColor: FabFilterColors.cyan),
          const SizedBox(width: 6),
          FabMiniButton(label: 'E', active: showExpertMode, onTap: toggleExpertMode, accentColor: FabFilterColors.cyan),
          const SizedBox(width: 6),
          FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass),
          if (widget.onClose != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, size: 14, color: FabFilterColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniMeter(String label, double db) {
    final norm = ((db + 60) / 60).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 7), overflow: TextOverflow.ellipsis),
        const SizedBox(width: 2),
        SizedBox(
          width: 24,
          height: 4,
          child: Container(
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: norm,
              child: Container(
                decoration: BoxDecoration(
                  color: norm > 0.9 ? FabFilterColors.red : FabFilterColors.cyan,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _peakToDb(double linear) {
    return linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;
  }

  // ─── VISUALIZATION ───────────────────────────────────────────────────

  Widget _buildVisualization() {
    return Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.hardEdge,
      child: CustomPaint(
        painter: _DelayTapPainter(
          delayL: _delayL,
          delayR: _delayR,
          feedback: _feedback / 100.0,
          pingPong: _pingPong / 100.0,
          linked: _link,
          freeze: _freeze,
        ),
        size: Size.infinite,
      ),
    );
  }

  // ─── MAIN KNOB ROW ──────────────────────────────────────────────────

  Widget _buildMainKnobRow() {
    return Row(
      children: [
        _buildDelayKnob('DELAY L', _delayL, (v) {
          setState(() {
            _delayL = v;
            if (_link) _delayR = v;
          });
          _setParam(_P.delayL, v);
          if (_link) _setParam(_P.delayR, v);
        }),
        _buildDelayKnob(_link ? 'DELAY R' : 'DELAY R', _delayR, (v) {
          setState(() => _delayR = v);
          _setParam(_P.delayR, v);
          if (_link) {
            setState(() => _delayL = v);
            _setParam(_P.delayL, v);
          }
        }),
        Expanded(child: FabFilterKnob(
          value: _feedback / 100.0,
          label: 'FDBK',
          display: _fmtPct(_feedback),
          color: FabFilterColors.orange,
          size: 44,
          defaultValue: 0.4,
          onChanged: (v) {
            setState(() => _feedback = v * 100.0);
            _setParam(_P.feedback, v * 100.0);
          },
        )),
        Expanded(child: FabFilterKnob(
          value: _mix / 100.0,
          label: 'MIX',
          display: _fmtPct(_mix),
          color: FabFilterColors.cyan,
          size: 44,
          defaultValue: 0.3,
          onChanged: (v) {
            setState(() => _mix = v * 100.0);
            _setParam(_P.mix, v * 100.0);
          },
        )),
      ],
    );
  }

  Widget _buildDelayKnob(String label, double ms, ValueChanged<double> onMs) {
    final norm = _logNorm(ms.clamp(1, 5000), 1, 5000);
    return Expanded(child: FabFilterKnob(
      value: norm,
      label: label,
      display: _fmtMs(ms),
      color: FabFilterColors.cyan,
      size: 44,
      defaultValue: _logNorm(375, 1, 5000),
      onChanged: (v) => onMs(_logDenorm(v, 1, 5000)),
    ));
  }

  // ─── SECONDARY ROW ──────────────────────────────────────────────────

  Widget _buildSecondaryRow() {
    return Row(
      children: [
        Expanded(child: FabFilterKnob(
          value: _pingPong / 100.0,
          label: 'P-PONG',
          display: _fmtPct(_pingPong),
          color: FabFilterColors.purple,
          size: 36,
          defaultValue: 0.0,
          onChanged: (v) {
            setState(() => _pingPong = v * 100.0);
            _setParam(_P.pingPong, v * 100.0);
          },
        )),
        Expanded(child: FabFilterKnob(
          value: _width / 200.0,
          label: 'WIDTH',
          display: '${_width.toStringAsFixed(0)}%',
          color: FabFilterColors.blue,
          size: 36,
          defaultValue: 0.5,
          onChanged: (v) {
            setState(() => _width = v * 200.0);
            _setParam(_P.width, v * 200.0);
          },
        )),
        Expanded(child: FabFilterKnob(
          value: _ducking / 100.0,
          label: 'DUCK',
          display: _fmtPct(_ducking),
          color: FabFilterColors.yellow,
          size: 36,
          defaultValue: 0.0,
          onChanged: (v) {
            setState(() => _ducking = v * 100.0);
            _setParam(_P.ducking, v * 100.0);
          },
        )),
      ],
    );
  }

  // ─── EXPERT SECTION ──────────────────────────────────────────────────

  Widget _buildExpertSection() {
    if (!showExpertMode) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // D8.3: Filter frequency response visualization
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              size: const Size(double.infinity, 40),
              painter: _FilterResponsePainter(
                hpFreq: _hpFilter, lpFreq: _lpFilter,
                midFreq: _midFreq, midGain: _midGain, tilt: _tilt,
              ),
            ),
          ),
          const FabSectionLabel('FEEDBACK FILTER'),
          Row(
            children: [
              Expanded(child: _buildFilterKnob('HP', _hpFilter, (v) {
                setState(() => _hpFilter = v);
                _setParam(_P.hpFilter, v);
              })),
              Expanded(child: FabFilterKnob(
                value: ((_hpQ - 0.5) / 9.5).clamp(0.0, 1.0),
                label: 'HP Q',
                display: _hpQ.toStringAsFixed(1),
                color: FabFilterColors.orange,
                size: 32,
                defaultValue: (0.707 - 0.5) / 9.5,
                onChanged: (v) {
                  setState(() => _hpQ = 0.5 + v * 9.5);
                  _setParam(_P.hpQ, _hpQ);
                },
              )),
              Expanded(child: _buildFilterKnob('LP', _lpFilter, (v) {
                setState(() => _lpFilter = v);
                _setParam(_P.lpFilter, v);
              })),
              Expanded(child: FabFilterKnob(
                value: ((_lpQ - 0.5) / 9.5).clamp(0.0, 1.0),
                label: 'LP Q',
                display: _lpQ.toStringAsFixed(1),
                color: FabFilterColors.orange,
                size: 32,
                defaultValue: (0.707 - 0.5) / 9.5,
                onChanged: (v) {
                  setState(() => _lpQ = 0.5 + v * 9.5);
                  _setParam(_P.lpQ, _lpQ);
                },
              )),
            ],
          ),
          const SizedBox(height: 4),
          // Parametric mid band
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: _logNorm(_midFreq.clamp(80, 16000), 80, 16000),
                label: 'MID',
                display: _fmtHz(_midFreq),
                color: FabFilterColors.yellow,
                size: 32,
                defaultValue: _logNorm(1000, 80, 16000),
                onChanged: (v) {
                  setState(() => _midFreq = _logDenorm(v, 80, 16000));
                  _setParam(_P.midFreq, _midFreq);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: ((_midQ - 0.5) / 9.5).clamp(0.0, 1.0),
                label: 'MID Q',
                display: _midQ.toStringAsFixed(1),
                color: FabFilterColors.yellow,
                size: 32,
                defaultValue: (1.0 - 0.5) / 9.5,
                onChanged: (v) {
                  setState(() => _midQ = 0.5 + v * 9.5);
                  _setParam(_P.midQ, _midQ);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: ((_midGain + 18.0) / 36.0).clamp(0.0, 1.0),
                label: 'MID dB',
                display: '${_midGain >= 0 ? "+" : ""}${_midGain.toStringAsFixed(1)}',
                color: FabFilterColors.yellow,
                size: 32,
                defaultValue: 0.5,
                onChanged: (v) {
                  setState(() => _midGain = v * 36.0 - 18.0);
                  _setParam(_P.midGain, _midGain);
                },
              )),
            ],
          ),
          const SizedBox(height: 6),
          const FabSectionLabel('DRIVE & CHARACTER'),
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: _drive / 100.0,
                label: 'DRIVE',
                display: _fmtPct(_drive),
                color: FabFilterColors.red,
                size: 36,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _drive = v * 100.0);
                  _setParam(_P.drive, _drive);
                },
              )),
              Expanded(child: _buildDriveModePicker()),
              Expanded(child: FabFilterKnob(
                value: ((_tilt + 6.0) / 12.0).clamp(0.0, 1.0),
                label: 'TILT',
                display: '${_tilt >= 0 ? "+" : ""}${_tilt.toStringAsFixed(1)}',
                color: FabFilterColors.purple,
                size: 36,
                defaultValue: 0.5,
                onChanged: (v) {
                  setState(() => _tilt = v * 12.0 - 6.0);
                  _setParam(_P.tilt, _tilt);
                },
              )),
            ],
          ),
          const SizedBox(height: 6),
          const FabSectionLabel('MODULATION'),
          Row(
            children: [
              Expanded(
                child: FabFilterKnob(
                  value: _modRate / 10.0,
                  label: 'RATE',
                  display: '${_modRate.toStringAsFixed(2)}Hz',
                  color: FabFilterColors.green,
                  size: 36,
                  defaultValue: 0.05,
                  onChanged: (v) {
                    setState(() => _modRate = v * 10.0);
                    _setParam(_P.modRate, v * 10.0);
                  },
                ),
              ),
              Expanded(
                child: FabFilterKnob(
                  value: _modDepth / 100.0,
                  label: 'DEPTH',
                  display: _fmtPct(_modDepth),
                  color: FabFilterColors.green,
                  size: 36,
                  defaultValue: 0.1,
                  onChanged: (v) {
                    setState(() => _modDepth = v * 100.0);
                    _setParam(_P.modDepth, v * 100.0);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const FabSectionLabel('FILTER LFO'),
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: _filterLfoRate / 20.0,
                label: 'FLT RATE',
                display: '${_filterLfoRate.toStringAsFixed(2)}Hz',
                color: FabFilterColors.cyan,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _filterLfoRate = v * 20.0);
                  _setParam(_P.filterLfoRate, _filterLfoRate);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: _filterLfoDepth / 100.0,
                label: 'FLT DPTH',
                display: _fmtPct(_filterLfoDepth),
                color: FabFilterColors.cyan,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _filterLfoDepth = v * 100.0);
                  _setParam(_P.filterLfoDepth, _filterLfoDepth);
                },
              )),
            ],
          ),
          const SizedBox(height: 8),
          // ─── D2 MODULATION ENGINE ───────────────────────────────
          const FabSectionLabel('LFO 1'),
          _buildLfoSection(
            rate: _lfo1Rate,
            depth: _lfo1Depth,
            shape: _lfo1Shape,
            sync: _lfo1Sync,
            syncDiv: _lfo1SyncDiv,
            retrigger: _lfo1Retrigger,
            onRateChanged: (v) { setState(() => _lfo1Rate = v); _setParam(_P.lfo1Rate, v); },
            onDepthChanged: (v) { setState(() => _lfo1Depth = v); _setParam(_P.lfo1Depth, v); },
            onShapeChanged: (v) { setState(() => _lfo1Shape = v); _setParam(_P.lfo1Shape, v.toDouble()); },
            onSyncChanged: (v) { setState(() => _lfo1Sync = v); _setParam(_P.lfo1Sync, v ? 1.0 : 0.0); },
            onSyncDivChanged: (v) { setState(() => _lfo1SyncDiv = v); _setParam(_P.lfo1SyncDiv, v.toDouble()); },
            onRetriggerChanged: (v) { setState(() => _lfo1Retrigger = v); _setParam(_P.lfo1Retrigger, v ? 1.0 : 0.0); },
          ),
          // D8.5: LFO1 waveform display
          if (_lfo1Depth > 0.01) Container(
            height: 28,
            margin: const EdgeInsets.only(top: 2, bottom: 2),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(3),
            ),
            child: CustomPaint(
              size: const Size(double.infinity, 28),
              painter: _LfoWaveformPainter(shape: _lfo1Shape, color: FabFilterColors.green),
            ),
          ),
          const SizedBox(height: 6),
          const FabSectionLabel('LFO 2'),
          _buildLfoSection(
            rate: _lfo2Rate,
            depth: _lfo2Depth,
            shape: _lfo2Shape,
            sync: _lfo2Sync,
            syncDiv: _lfo2SyncDiv,
            retrigger: null,
            onRateChanged: (v) { setState(() => _lfo2Rate = v); _setParam(_P.lfo2Rate, v); },
            onDepthChanged: (v) { setState(() => _lfo2Depth = v); _setParam(_P.lfo2Depth, v); },
            onShapeChanged: (v) { setState(() => _lfo2Shape = v); _setParam(_P.lfo2Shape, v.toDouble()); },
            onSyncChanged: (v) { setState(() => _lfo2Sync = v); _setParam(_P.lfo2Sync, v ? 1.0 : 0.0); },
            onSyncDivChanged: (v) { setState(() => _lfo2SyncDiv = v); _setParam(_P.lfo2SyncDiv, v.toDouble()); },
            onRetriggerChanged: null,
          ),
          const SizedBox(height: 6),
          const FabSectionLabel('ENVELOPE'),
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: _envSensitivity / 100.0,
                label: 'SENS',
                display: _fmtPct(_envSensitivity),
                color: FabFilterColors.orange,
                size: 32,
                defaultValue: 0.5,
                onChanged: (v) {
                  setState(() => _envSensitivity = v * 100.0);
                  _setParam(_P.envSensitivity, _envSensitivity);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: _envAttack / 100.0,
                label: 'ATK',
                display: '${_envAttack.toStringAsFixed(1)}ms',
                color: FabFilterColors.orange,
                size: 32,
                defaultValue: 0.05,
                onChanged: (v) {
                  setState(() => _envAttack = v * 100.0);
                  _setParam(_P.envAttack, _envAttack);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: _envRelease / 1000.0,
                label: 'REL',
                display: '${_envRelease.toStringAsFixed(0)}ms',
                color: FabFilterColors.orange,
                size: 32,
                defaultValue: 0.05,
                onChanged: (v) {
                  setState(() => _envRelease = v * 1000.0);
                  _setParam(_P.envRelease, _envRelease);
                },
              )),
            ],
          ),
          const SizedBox(height: 6),
          const FabSectionLabel('PITCH & ROUTING'),
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: ((_pitchShift + 12.0) / 24.0).clamp(0.0, 1.0),
                label: 'PITCH',
                display: '${_pitchShift >= 0 ? "+" : ""}${_pitchShift.toStringAsFixed(1)}st',
                color: FabFilterColors.purple,
                size: 36,
                defaultValue: 0.5,
                onChanged: (v) {
                  setState(() => _pitchShift = v * 24.0 - 12.0);
                  _setParam(_P.pitchShift, _pitchShift);
                },
              )),
              Expanded(child: _buildModRoutingPicker()),
            ],
          ),
          const SizedBox(height: 8),
          // ─── D3 TEMPO SYNC ──────────────────────────────────────
          const FabSectionLabel('TEMPO SYNC'),
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: ((_bpm - 20.0) / 280.0).clamp(0.0, 1.0),
                label: 'BPM',
                display: _bpm.toStringAsFixed(1),
                color: FabFilterColors.cyan,
                size: 36,
                defaultValue: (120.0 - 20.0) / 280.0,
                onChanged: (v) {
                  setState(() => _bpm = 20.0 + v * 280.0);
                  _setParam(_P.bpm, _bpm);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: _swing / 100.0,
                label: 'SWING',
                display: _fmtPct(_swing),
                color: FabFilterColors.cyan,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _swing = v * 100.0);
                  _setParam(_P.swing, _swing);
                },
              )),
            ],
          ),
          const SizedBox(height: 4),
          // Note value pickers
          _buildNoteValuePicker('NOTE L', _noteValueL, (v) {
            setState(() => _noteValueL = v);
            _setParam(_P.noteValueL, v.toDouble());
          }),
          if (!_link) ...[
            const SizedBox(height: 3),
            _buildNoteValuePicker('NOTE R', _noteValueR, (v) {
              setState(() => _noteValueR = v);
              _setParam(_P.noteValueR, v.toDouble());
            }),
          ],
          const SizedBox(height: 8),
          // ─── D7 VINTAGE CHARACTER ───────────────────────────────
          const FabSectionLabel('VINTAGE'),
          Row(
            children: [
              Expanded(child: _buildVintageModePicker()),
              Expanded(child: FabFilterKnob(
                value: _vintageAmount / 100.0,
                label: 'AMOUNT',
                display: _fmtPct(_vintageAmount),
                color: FabFilterColors.orange,
                size: 36,
                defaultValue: 0.5,
                onChanged: (v) {
                  setState(() => _vintageAmount = v * 100.0);
                  _setParam(_P.vintageAmount, _vintageAmount);
                },
              )),
            ],
          ),
          const SizedBox(height: 8),
          // ─── D5 STEREO & SPATIAL ──────────────────────────────────
          const FabSectionLabel('STEREO & SPATIAL'),
          _buildStereoRoutingPicker(),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: FabFilterKnob(
                value: _crossFeedback / 100.0,
                label: 'X-FEED',
                display: _fmtPct(_crossFeedback),
                color: FabFilterColors.blue,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _crossFeedback = v * 100.0);
                  _setParam(_P.crossFeedback, _crossFeedback);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: (_haasDelay / 30.0).clamp(0.0, 1.0),
                label: 'HAAS',
                display: '${_haasDelay.toStringAsFixed(1)}ms',
                color: FabFilterColors.blue,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _haasDelay = v * 30.0);
                  _setParam(_P.haasDelay, _haasDelay);
                },
              )),
              Expanded(child: FabFilterKnob(
                value: _diffusion / 100.0,
                label: 'DIFFUSE',
                display: _fmtPct(_diffusion),
                color: FabFilterColors.blue,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _diffusion = v * 100.0);
                  _setParam(_P.diffusion, _diffusion);
                },
              )),
            ],
          ),
          const SizedBox(height: 8),
          // ─── D6 FREEZE & GLITCH ───────────────────────────────────
          const FabSectionLabel('FREEZE & GLITCH'),
          Row(
            children: [
              Expanded(child: FabMiniButton(
                label: 'REV',
                active: _reverse,
                onTap: () {
                  setState(() => _reverse = !_reverse);
                  _setParam(_P.reverse, _reverse ? 1.0 : 0.0);
                },
                accentColor: FabFilterColors.red,
              )),
              Expanded(child: FabMiniButton(
                label: 'STUTTER',
                active: _stutter,
                onTap: () {
                  setState(() => _stutter = !_stutter);
                  _setParam(_P.stutter, _stutter ? 1.0 : 0.0);
                },
                accentColor: FabFilterColors.red,
              )),
              Expanded(child: FabMiniButton(
                label: 'INF',
                active: _infiniteFB,
                onTap: () {
                  setState(() => _infiniteFB = !_infiniteFB);
                  _setParam(_P.infiniteFB, _infiniteFB ? 1.0 : 0.0);
                },
                accentColor: FabFilterColors.red,
              )),
            ],
          ),
          if (_stutter) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: FabFilterKnob(
                  value: (_stutterRate / 500.0).clamp(0.0, 1.0),
                  label: 'STTR RATE',
                  display: '${_stutterRate.toStringAsFixed(0)}ms',
                  color: FabFilterColors.red,
                  size: 32,
                  defaultValue: 125.0 / 500.0,
                  onChanged: (v) {
                    setState(() => _stutterRate = v * 500.0);
                    _setParam(_P.stutterRate, _stutterRate);
                  },
                )),
              ],
            ),
          ],
          // D8.8: Freeze visualization
          if (_freeze || _infiniteFB) ...[
            const SizedBox(height: 6),
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: FabFilterColors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FabFilterColors.red.withOpacity(0.3)),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _freeze ? Icons.ac_unit : Icons.all_inclusive,
                      color: FabFilterColors.red.withOpacity(0.8),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _freeze && _infiniteFB ? 'FROZEN + INFINITE'
                          : _freeze ? 'BUFFER FROZEN'
                          : 'INFINITE FEEDBACK',
                      style: TextStyle(
                        color: FabFilterColors.red.withOpacity(0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // ─── D10 ADVANCED ─────────────────────────────────────────
          const FabSectionLabel('ADVANCED'),
          Row(
            children: [
              Expanded(child: FabMiniButton(
                label: 'SC',
                active: _sidechainEnabled,
                onTap: () {
                  setState(() => _sidechainEnabled = !_sidechainEnabled);
                  _setParam(_P.sidechain, _sidechainEnabled ? 1.0 : 0.0);
                },
                accentColor: FabFilterColors.yellow,
              )),
              Expanded(child: _buildMidiTriggerPicker()),
              Expanded(child: FabFilterKnob(
                value: _smoothing / 100.0,
                label: 'SMOOTH',
                display: _fmtPct(_smoothing),
                color: FabFilterColors.green,
                size: 32,
                defaultValue: 0.0,
                onChanged: (v) {
                  setState(() => _smoothing = v * 100.0);
                  _setParam(_P.smoothing, _smoothing);
                },
              )),
            ],
          ),
        ],
      ),
    );
  }

  // ─── MIDI TRIGGER MODE PICKER ────────────────────────────────────────

  static const _midiTriggerNames = ['OFF', 'FRZ', 'STT', 'REV'];
  static const _midiTriggerColors = [
    Colors.white38,
    FabFilterColors.cyan,
    FabFilterColors.red,
    FabFilterColors.purple,
  ];

  Widget _buildMidiTriggerPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MIDI', style: TextStyle(fontSize: 7, color: Colors.white38)),
        const SizedBox(height: 2),
        Row(
          children: List.generate(4, (i) => Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _midiTriggerMode = i);
                _setParam(_P.midiTrigger, i.toDouble());
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: i == _midiTriggerMode
                      ? _midiTriggerColors[i].withOpacity(0.7)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _midiTriggerNames[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: i == _midiTriggerMode ? FontWeight.bold : FontWeight.normal,
                    color: i == _midiTriggerMode ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          )),
        ),
      ],
    );
  }

  // ─── STEREO ROUTING PICKER ───────────────────────────────────────────

  static const _stereoRoutingNames = ['STEREO', 'PING-PONG', 'X-FEED', 'DUAL MONO', 'MID/SIDE'];
  static const _stereoRoutingColors = [
    FabFilterColors.blue,
    FabFilterColors.cyan,
    FabFilterColors.green,
    FabFilterColors.yellow,
    FabFilterColors.purple,
  ];

  Widget _buildStereoRoutingPicker() {
    return Row(
      children: List.generate(5, (i) => Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _stereoRouting = i);
            _setParam(_P.stereoRouting, i.toDouble());
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: i == _stereoRouting
                  ? _stereoRoutingColors[i].withOpacity(0.7)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _stereoRoutingNames[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 7,
                fontWeight: i == _stereoRouting ? FontWeight.bold : FontWeight.normal,
                color: i == _stereoRouting ? Colors.white : Colors.white54,
              ),
            ),
          ),
        ),
      )),
    );
  }

  // ─── LFO SECTION BUILDER ────────────────────────────────────────────

  static const _lfoShapeNames = ['SIN', 'TRI', 'SAW↑', 'SAW↓', 'SQR', 'S&H', 'RND'];
  static const _syncDivNames = [
    '1/64', '1/32', '1/16T', '1/16', '1/8T', '1/8', '1/4T', '1/4',
    '1/2T', '1/2', '1/1T', '1/1', '2/1', '4/1', '1/16D', '1/8D',
  ];

  Widget _buildLfoSection({
    required double rate,
    required double depth,
    required int shape,
    required bool sync,
    required int syncDiv,
    required bool? retrigger,
    required ValueChanged<double> onRateChanged,
    required ValueChanged<double> onDepthChanged,
    required ValueChanged<int> onShapeChanged,
    required ValueChanged<bool> onSyncChanged,
    required ValueChanged<int> onSyncDivChanged,
    required ValueChanged<bool>? onRetriggerChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shape picker row
        Row(
          children: List.generate(7, (i) => Expanded(
            child: GestureDetector(
              onTap: () => onShapeChanged(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: i == shape
                      ? FabFilterColors.green.withOpacity(0.7)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _lfoShapeNames[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: i == shape ? FontWeight.bold : FontWeight.normal,
                    color: i == shape ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ),
          )),
        ),
        const SizedBox(height: 4),
        // Rate + Depth knobs
        Row(
          children: [
            Expanded(child: FabFilterKnob(
              value: rate / 20.0,
              label: 'RATE',
              display: sync ? _syncDivNames[syncDiv.clamp(0, 15)] : '${rate.toStringAsFixed(2)}Hz',
              color: FabFilterColors.green,
              size: 32,
              defaultValue: 0.05,
              onChanged: (v) => onRateChanged(v * 20.0),
            )),
            Expanded(child: FabFilterKnob(
              value: depth / 100.0,
              label: 'DEPTH',
              display: _fmtPct(depth),
              color: FabFilterColors.green,
              size: 32,
              defaultValue: 0.0,
              onChanged: (v) => onDepthChanged(v * 100.0),
            )),
            // Sync toggle
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => onSyncChanged(!sync),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: sync ? FabFilterColors.green.withOpacity(0.7) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('SYNC', style: TextStyle(
                      fontSize: 8,
                      fontWeight: sync ? FontWeight.bold : FontWeight.normal,
                      color: sync ? Colors.white : Colors.white54,
                    )),
                  ),
                ),
                if (retrigger != null) ...[
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: () => onRetriggerChanged?.call(!retrigger),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: retrigger ? FabFilterColors.red.withOpacity(0.7) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('RETRIG', style: TextStyle(
                        fontSize: 7,
                        fontWeight: retrigger ? FontWeight.bold : FontWeight.normal,
                        color: retrigger ? Colors.white : Colors.white54,
                      )),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        // Sync division picker (only when sync is on)
        if (sync) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 22,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 16,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onSyncDivChanged(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: i == syncDiv
                        ? FabFilterColors.green.withOpacity(0.7)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _syncDivNames[i],
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: i == syncDiv ? FontWeight.bold : FontWeight.normal,
                      color: i == syncDiv ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── MOD ROUTING PRESET PICKER ──────────────────────────────────────

  static const _routingNames = [
    'OFF', 'L1→TIME', 'L1→FLT', 'L1→PAN', 'L1+L2', 'ENV→FB', 'ENV→FLT', 'L1→DRV', 'L1→PITCH',
  ];

  Widget _buildModRoutingPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('MOD ROUTE', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        const SizedBox(height: 2),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: List.generate(_routingNames.length, (i) => GestureDetector(
            onTap: () {
              setState(() => _modRouting = i);
              _setParam(_P.modRouting, i.toDouble());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: i == _modRouting
                    ? FabFilterColors.purple.withOpacity(0.7)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _routingNames[i],
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: i == _modRouting ? FontWeight.bold : FontWeight.normal,
                  color: i == _modRouting ? Colors.white : Colors.white54,
                ),
              ),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildDriveModePicker() {
    const modes = ['TUBE', 'TAPE', 'TRNS'];
    const colors = [FabFilterColors.orange, FabFilterColors.yellow, FabFilterColors.red];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('MODE', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: GestureDetector(
              onTap: () {
                setState(() => _driveMode = i);
                _setParam(_P.driveMode, i.toDouble());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _driveMode == i
                    ? colors[i].withValues(alpha: 0.3)
                    : FabFilterColors.bgVoid,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _driveMode == i
                      ? colors[i].withValues(alpha: 0.6)
                      : FabFilterColors.borderSubtle,
                    width: 0.5,
                  ),
                ),
                child: Text(modes[i], style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: _driveMode == i ? colors[i] : FabFilterColors.textTertiary,
                )),
              ),
            ),
          )),
        ),
      ],
    );
  }

  // ─── D3 NOTE VALUE PICKER ──────────────────────────────────────────

  static const _noteValueNames = [
    '1/64', '1/32', '1/16T', '1/16', '1/16D',
    '1/8T', '1/8', '1/8D',
    '1/4T', '1/4', '1/4D',
    '1/2T', '1/2', '1/2D',
    '1/1T', '1/1', '1/1D',
    '2/1', '4/1',
  ];

  Widget _buildNoteValuePicker(String label, int selected, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        const SizedBox(height: 2),
        SizedBox(
          height: 22,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 19,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: i == selected
                      ? FabFilterColors.cyan.withOpacity(0.7)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _noteValueNames[i],
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: i == selected ? FontWeight.bold : FontWeight.normal,
                    color: i == selected ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── D7 VINTAGE MODE PICKER ──────────────────────────────────────

  static const _vintageModeNames = ['CLEAN', 'TAPE', 'BBD', 'OIL CAN', 'LO-FI'];
  static const _vintageModeColors = [
    Colors.white54, FabFilterColors.orange, FabFilterColors.yellow,
    FabFilterColors.green, FabFilterColors.red,
  ];

  Widget _buildVintageModePicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('MODE', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        const SizedBox(height: 2),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: List.generate(5, (i) => GestureDetector(
            onTap: () {
              setState(() => _vintageMode = i);
              _setParam(_P.vintageMode, i.toDouble());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: i == _vintageMode
                    ? _vintageModeColors[i].withOpacity(0.3)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: i == _vintageMode
                      ? _vintageModeColors[i].withOpacity(0.6)
                      : Colors.transparent,
                  width: 0.5,
                ),
              ),
              child: Text(
                _vintageModeNames[i],
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: i == _vintageMode ? FontWeight.bold : FontWeight.normal,
                  color: i == _vintageMode ? _vintageModeColors[i] : Colors.white54,
                ),
              ),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildFilterKnob(String label, double hz, ValueChanged<double> onHz) {
    final norm = _logNorm(hz.clamp(20, 20000), 20, 20000);
    return FabFilterKnob(
      value: norm,
      label: label,
      display: _fmtHz(hz),
      color: FabFilterColors.orange,
      size: 36,
      defaultValue: label == 'HP' ? _logNorm(80, 20, 20000) : _logNorm(12000, 20, 20000),
      onChanged: (v) => onHz(_logDenorm(v, 20, 20000)),
    );
  }

  // ─── BOTTOM TOGGLES ──────────────────────────────────────────────────

  Widget _buildBottomToggles() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          FabCompactToggle(
            label: 'LINK',
            active: _link,
            color: FabFilterColors.cyan,
            onToggle: () {
              setState(() => _link = !_link);
              _setParam(_P.link, _link ? 1.0 : 0.0);
              if (_link) {
                setState(() => _delayR = _delayL);
                _setParam(_P.delayR, _delayL);
              }
            },
          ),
          const SizedBox(width: 6),
          FabCompactToggle(
            label: 'FRZ',
            active: _freeze,
            color: FabFilterColors.blue,
            onToggle: () {
              setState(() => _freeze = !_freeze);
              _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
            },
          ),
          const SizedBox(width: 6),
          FabCompactToggle(
            label: 'SYNC',
            active: _tempoSync,
            color: FabFilterColors.green,
            onToggle: () {
              setState(() => _tempoSync = !_tempoSync);
              _setParam(_P.tempoSync, _tempoSync ? 1.0 : 0.0);
            },
          ),
          const Spacer(),
          // Feedback amount display
          Text(
            'FB ${_feedback.toStringAsFixed(0)}%',
            style: FabFilterText.paramLabel.copyWith(
              fontSize: 8,
              color: _feedback > 90 ? FabFilterColors.red : FabFilterColors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          // Delay times summary
          Text(
            _link ? 'L=R ${_fmtMs(_delayL)}' : 'L${_fmtMs(_delayL)} R${_fmtMs(_delayR)}',
            style: FabFilterText.paramLabel.copyWith(fontSize: 8),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELAY TAP VISUALIZATION PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _DelayTapPainter extends CustomPainter {
  final double delayL;
  final double delayR;
  final double feedback;
  final double pingPong;
  final bool linked;
  final bool freeze;

  _DelayTapPainter({
    required this.delayL,
    required this.delayR,
    required this.feedback,
    required this.pingPong,
    required this.linked,
    required this.freeze,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final maxDelay = math.max(delayL, delayR).clamp(1.0, 5000.0);
    final timeScale = (w - 24) / (maxDelay * 4).clamp(500.0, 20000.0);

    // Background grid
    _drawGrid(canvas, size);

    // Draw feedback taps
    final taps = _generateTaps(timeScale, w);
    for (final tap in taps) {
      final x = tap.x;
      if (x > w - 4) continue;

      final alpha = tap.amplitude.clamp(0.0, 1.0);
      final isLeft = tap.isLeft;
      final color = isLeft ? FabFilterColors.cyan : FabFilterColors.orange;
      final tapH = (h * 0.35) * alpha;

      // Tap line
      canvas.drawLine(
        Offset(x, midY - tapH),
        Offset(x, midY + tapH),
        Paint()
          ..color = color.withValues(alpha: alpha * 0.9)
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round,
      );

      // Glow
      canvas.drawLine(
        Offset(x, midY - tapH * 0.8),
        Offset(x, midY + tapH * 0.8),
        Paint()
          ..color = color.withValues(alpha: alpha * 0.2)
          ..strokeWidth = 8.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Freeze indicator
    if (freeze) {
      final freezePaint = Paint()
        ..color = FabFilterColors.blue.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), freezePaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: 'FREEZE',
          style: TextStyle(
            color: FabFilterColors.blue.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(w / 2 - textPainter.width / 2, 4));
    }

    // Center line
    canvas.drawLine(
      Offset(0, midY),
      Offset(w, midY),
      Paint()
        ..color = FabFilterColors.borderSubtle.withValues(alpha: 0.5)
        ..strokeWidth = 0.5,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Vertical grid (time divisions)
    for (int i = 1; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal grid
    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  List<_Tap> _generateTaps(double timeScale, double maxWidth) {
    final taps = <_Tap>[];
    final maxTaps = 12;
    var ampL = 1.0;
    var ampR = 1.0;

    for (int i = 0; i < maxTaps; i++) {
      final timeL = delayL * (i + 1);
      final timeR = delayR * (i + 1);

      if (pingPong > 0.5) {
        // Ping-pong: alternate L/R
        final isLeft = i.isEven;
        final time = isLeft ? timeL : timeR;
        final amp = isLeft ? ampL : ampR;
        final x = 12 + time * timeScale;
        if (x < maxWidth - 4) {
          taps.add(_Tap(x: x, amplitude: amp, isLeft: isLeft));
        }
        if (isLeft) {
          ampL *= feedback;
        } else {
          ampR *= feedback;
        }
      } else {
        // Normal: L and R taps at their own delay times
        final xL = 12 + timeL * timeScale;
        final xR = 12 + timeR * timeScale;
        if (xL < maxWidth - 4) {
          taps.add(_Tap(x: xL, amplitude: ampL, isLeft: true));
        }
        if (!linked && xR < maxWidth - 4) {
          taps.add(_Tap(x: xR, amplitude: ampR, isLeft: false));
        }
        ampL *= feedback;
        ampR *= feedback;
      }

      if (ampL < 0.02 && ampR < 0.02) break;
    }

    return taps;
  }

  @override
  bool shouldRepaint(covariant _DelayTapPainter old) {
    return delayL != old.delayL || delayR != old.delayR ||
        feedback != old.feedback || pingPong != old.pingPong ||
        linked != old.linked || freeze != old.freeze;
  }
}

class _Tap {
  final double x;
  final double amplitude;
  final bool isLeft;
  const _Tap({required this.x, required this.amplitude, required this.isLeft});
}

// ═══════════════════════════════════════════════════════════════════════════
// D8.1 — TAP TIMELINE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _TapTimelinePainter extends CustomPainter {
  final double delayL, delayR, feedback;
  final bool linked;
  final int stereoRouting;
  final bool freeze;

  _TapTimelinePainter({
    required this.delayL, required this.delayR, required this.feedback,
    required this.linked, required this.stereoRouting, required this.freeze,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxDelay = math.max(delayL, linked ? delayL : delayR) * 3.0;
    if (maxDelay < 1.0) return;

    final fbNorm = (feedback / 100.0).clamp(0.0, 0.99);
    final midY = size.height * 0.5;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 4; i++) {
      final x = size.width * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw L taps (blue, above center)
    _drawTapSequence(canvas, size, delayL, fbNorm, maxDelay,
        FabFilterColors.cyan, midY - 2, -1);

    // Draw R taps (orange, below center)
    final dR = linked ? delayL : delayR;
    if (stereoRouting == 1) {
      // Ping-pong: R taps are offset by half
      _drawTapSequence(canvas, size, dR, fbNorm, maxDelay,
          FabFilterColors.orange, midY + 2, 1);
    } else {
      _drawTapSequence(canvas, size, dR, fbNorm, maxDelay,
          FabFilterColors.orange, midY + 2, 1);
    }

    // Freeze indicator
    if (freeze) {
      final freezePaint = Paint()
        ..color = FabFilterColors.red.withOpacity(0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), freezePaint);
    }
  }

  void _drawTapSequence(Canvas canvas, Size size, double delayMs, double fb,
      double maxMs, Color color, double baseY, int direction) {
    double amp = 1.0;
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 1; i <= 12; i++) {
      if (amp < 0.02) break;
      final t = delayMs * i;
      final x = (t / maxMs) * size.width;
      if (x > size.width) break;

      final r = 2.0 + amp * 4.0;
      final y = baseY + direction * amp * (size.height * 0.3);
      dotPaint.color = color.withOpacity(amp * 0.8);
      canvas.drawCircle(Offset(x, y), r, dotPaint);

      amp *= fb;
    }
  }

  @override
  bool shouldRepaint(covariant _TapTimelinePainter old) {
    return delayL != old.delayL || delayR != old.delayR ||
        feedback != old.feedback || linked != old.linked ||
        stereoRouting != old.stereoRouting || freeze != old.freeze;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// D8.3 — FILTER FREQUENCY RESPONSE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _FilterResponsePainter extends CustomPainter {
  final double hpFreq, lpFreq, midFreq, midGain, tilt;

  _FilterResponsePainter({
    required this.hpFreq, required this.lpFreq,
    required this.midFreq, required this.midGain, required this.tilt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FabFilterColors.cyan.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = FabFilterColors.cyan.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final steps = size.width.toInt();

    for (int i = 0; i <= steps; i++) {
      final x = i.toDouble();
      final norm = x / size.width;
      // Log frequency: 20Hz to 20kHz
      final freq = 20.0 * math.pow(1000.0, norm);

      // Compute approximate magnitude response
      double db = 0.0;

      // HP response (12dB/oct slope approx)
      if (freq < hpFreq) {
        final ratio = freq / hpFreq;
        db += 12.0 * (math.log(ratio) / math.ln2); // -12dB/oct below cutoff
      }

      // LP response
      if (freq > lpFreq) {
        final ratio = freq / lpFreq;
        db -= 12.0 * (math.log(ratio) / math.ln2);
      }

      // Mid peak/dip
      final midOctDist = (math.log(freq / midFreq) / math.ln2).abs();
      if (midOctDist < 2.0) {
        db += midGain * math.max(0.0, 1.0 - midOctDist * 0.5);
      }

      // Tilt
      db += tilt * (math.log(freq / 1000.0) / math.ln2) * 0.5;

      // Map dB to y (center = 0dB, ±18dB range)
      final y = size.height * 0.5 - (db / 18.0) * (size.height * 0.4);

      if (i == 0) {
        path.moveTo(x, y.clamp(0.0, size.height));
        fillPath.moveTo(x, y.clamp(0.0, size.height));
      } else {
        path.lineTo(x, y.clamp(0.0, size.height));
        fillPath.lineTo(x, y.clamp(0.0, size.height));
      }
    }

    // Fill under curve
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Center line (0 dB)
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FilterResponsePainter old) {
    return hpFreq != old.hpFreq || lpFreq != old.lpFreq ||
        midFreq != old.midFreq || midGain != old.midGain || tilt != old.tilt;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// D8.5 — LFO WAVEFORM PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _LfoWaveformPainter extends CustomPainter {
  final int shape;
  final Color color;

  _LfoWaveformPainter({required this.shape, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final steps = size.width.toInt();

    for (int i = 0; i <= steps; i++) {
      final phase = i / size.width; // 0..1 = one full cycle
      final value = _lfoValue(phase, shape); // -1..1

      final y = size.height * 0.5 - value * (size.height * 0.4);
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    canvas.drawPath(path, paint);

    // Center line
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      centerPaint,
    );
  }

  static double _lfoValue(double phase, int shape) {
    switch (shape) {
      case 0: // Sine
        return math.sin(phase * 2 * math.pi);
      case 1: // Triangle
        final t = (phase * 4.0) % 4.0;
        if (t < 1) return t;
        if (t < 3) return 2 - t;
        return t - 4;
      case 2: // Saw Up
        return phase * 2.0 - 1.0;
      case 3: // Saw Down
        return 1.0 - phase * 2.0;
      case 4: // Square
        return phase < 0.5 ? 1.0 : -1.0;
      case 5: // Sample & Hold
        return ((phase * 7).floor() * 0.287 * 2.0 - 0.5).clamp(-1.0, 1.0);
      case 6: // Random Smooth (sine-ish random)
        return math.sin(phase * 2 * math.pi + 2.7) * 0.6 +
            math.sin(phase * 6.28 * 3 + 0.3) * 0.3;
      default:
        return 0;
    }
  }

  @override
  bool shouldRepaint(covariant _LfoWaveformPainter old) {
    return shape != old.shape || color != old.color;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// D9.3 — FACTORY PRESETS
// ═══════════════════════════════════════════════════════════════════════════

class _DelayPreset {
  final String name;
  final String category;
  final DelaySnapshot snapshot;
  const _DelayPreset(this.name, this.category, this.snapshot);
}

DelaySnapshot _makePreset({
  double delayL = 500, double delayR = 500, double feedback = 50,
  double mix = 50, double pingPong = 0,
  double hpFilter = 80, double lpFilter = 8000,
  double modRate = 0.5, double modDepth = 10,
  double width = 100, double ducking = 0,
  bool link = true, bool freeze = false, bool tempoSync = false,
  double hpQ = 0.707, double lpQ = 0.707,
  double midFreq = 1000, double midQ = 1.0, double midGain = 0,
  double drive = 0, int driveMode = 0, double tilt = 0,
  double filterLfoRate = 0, double filterLfoDepth = 0,
  double lfo1Rate = 1, double lfo1Depth = 0, int lfo1Shape = 0,
  bool lfo1Sync = false, int lfo1SyncDiv = 7, bool lfo1Retrigger = false,
  double lfo2Rate = 1, double lfo2Depth = 0, int lfo2Shape = 0,
  bool lfo2Sync = false, int lfo2SyncDiv = 7,
  double envSensitivity = 50, double envAttack = 5, double envRelease = 50,
  double pitchShift = 0, int modRouting = 0,
  double bpm = 120, int noteValueL = 9, int noteValueR = 9,
  double swing = 0, int vintageMode = 0, double vintageAmount = 50,
  int stereoRouting = 1, double crossFeedback = 0,
  double haasDelay = 0, double diffusion = 0,
  bool reverse = false, bool stutter = false, double stutterRate = 125,
  bool infiniteFB = false,
}) => DelaySnapshot(
  delayL: delayL, delayR: delayR, feedback: feedback, mix: mix,
  pingPong: pingPong, hpFilter: hpFilter, lpFilter: lpFilter,
  modRate: modRate, modDepth: modDepth, width: width, ducking: ducking,
  link: link, freeze: freeze, tempoSync: tempoSync,
  hpQ: hpQ, lpQ: lpQ, midFreq: midFreq, midQ: midQ, midGain: midGain,
  drive: drive, driveMode: driveMode, tilt: tilt,
  filterLfoRate: filterLfoRate, filterLfoDepth: filterLfoDepth,
  lfo1Rate: lfo1Rate, lfo1Depth: lfo1Depth, lfo1Shape: lfo1Shape,
  lfo1Sync: lfo1Sync, lfo1SyncDiv: lfo1SyncDiv, lfo1Retrigger: lfo1Retrigger,
  lfo2Rate: lfo2Rate, lfo2Depth: lfo2Depth, lfo2Shape: lfo2Shape,
  lfo2Sync: lfo2Sync, lfo2SyncDiv: lfo2SyncDiv,
  envSensitivity: envSensitivity, envAttack: envAttack, envRelease: envRelease,
  pitchShift: pitchShift, modRouting: modRouting,
  bpm: bpm, noteValueL: noteValueL, noteValueR: noteValueR,
  swing: swing, vintageMode: vintageMode, vintageAmount: vintageAmount,
  stereoRouting: stereoRouting, crossFeedback: crossFeedback,
  haasDelay: haasDelay, diffusion: diffusion,
  reverse: reverse, stutter: stutter, stutterRate: stutterRate,
  infiniteFB: infiniteFB,
);

final List<_DelayPreset> _factoryPresets = [
  // ─── CLEAN / DIGITAL ────────────────────────────
  _DelayPreset('Clean Digital', 'Clean', _makePreset(
    delayL: 500, feedback: 40, mix: 35, stereoRouting: 0,
  )),
  _DelayPreset('Slapback', 'Clean', _makePreset(
    delayL: 80, feedback: 10, mix: 50, stereoRouting: 0,
  )),
  _DelayPreset('Dotted 8th', 'Clean', _makePreset(
    tempoSync: true, noteValueL: 14, feedback: 35, mix: 40,
  )),
  _DelayPreset('Ping-Pong Wide', 'Clean', _makePreset(
    delayL: 375, feedback: 45, mix: 40, stereoRouting: 1, width: 150,
  )),
  _DelayPreset('Dual Mono', 'Clean', _makePreset(
    delayL: 250, delayR: 375, feedback: 40, mix: 35,
    link: false, stereoRouting: 3,
  )),

  // ─── TAPE / ANALOG ──────────────────────────────
  _DelayPreset('Tape Echo', 'Tape', _makePreset(
    delayL: 400, feedback: 55, mix: 40, vintageMode: 1, vintageAmount: 70,
    hpFilter: 150, lpFilter: 5000, drive: 15, tilt: -1.5,
  )),
  _DelayPreset('Warm Tape', 'Tape', _makePreset(
    delayL: 340, feedback: 50, mix: 45, vintageMode: 1, vintageAmount: 55,
    lpFilter: 4000, modRate: 0.8, modDepth: 8,
  )),
  _DelayPreset('Tape Wobble', 'Tape', _makePreset(
    delayL: 450, feedback: 50, mix: 40, vintageMode: 1, vintageAmount: 85,
    lpFilter: 3500, modRate: 2.5, modDepth: 25,
  )),
  _DelayPreset('Oil Can Spring', 'Tape', _makePreset(
    delayL: 200, feedback: 45, mix: 40, vintageMode: 3, vintageAmount: 75,
    lpFilter: 4500, diffusion: 30, modRate: 1.2, modDepth: 15,
  )),

  // ─── BBD / ANALOG ───────────────────────────────
  _DelayPreset('BBD Chorus', 'BBD', _makePreset(
    delayL: 15, feedback: 20, mix: 50, vintageMode: 2, vintageAmount: 60,
    modRate: 1.5, modDepth: 40, stereoRouting: 0,
  )),
  _DelayPreset('BBD Flanger', 'BBD', _makePreset(
    delayL: 5, feedback: 70, mix: 50, vintageMode: 2, vintageAmount: 50,
    modRate: 0.3, modDepth: 80, stereoRouting: 0,
  )),
  _DelayPreset('BBD Echo', 'BBD', _makePreset(
    delayL: 300, feedback: 50, mix: 40, vintageMode: 2, vintageAmount: 65,
    lpFilter: 4000, hpFilter: 120,
  )),

  // ─── LO-FI ──────────────────────────────────────
  _DelayPreset('Lo-Fi Ambient', 'Lo-Fi', _makePreset(
    delayL: 600, feedback: 60, mix: 50, vintageMode: 4, vintageAmount: 70,
    lpFilter: 3000, diffusion: 40, stereoRouting: 1,
  )),
  _DelayPreset('Broken Radio', 'Lo-Fi', _makePreset(
    delayL: 350, feedback: 45, mix: 40, vintageMode: 4, vintageAmount: 90,
    hpFilter: 300, lpFilter: 2500, drive: 30,
  )),

  // ─── DUB / REGGAE ───────────────────────────────
  _DelayPreset('Dub Delay', 'Dub', _makePreset(
    delayL: 375, feedback: 65, mix: 50, hpFilter: 200, lpFilter: 3000,
    drive: 20, driveMode: 0, vintageMode: 1, vintageAmount: 40,
    filterLfoRate: 0.5, filterLfoDepth: 30,
  )),
  _DelayPreset('Dub Siren', 'Dub', _makePreset(
    delayL: 250, feedback: 70, mix: 55, hpFilter: 250, lpFilter: 2500,
    drive: 35, vintageMode: 1, vintageAmount: 50,
    lfo1Rate: 3.0, lfo1Depth: 40, lfo1Shape: 0, modRouting: 1,
  )),

  // ─── CREATIVE / SPATIAL ─────────────────────────
  _DelayPreset('Shimmer Delay', 'Creative', _makePreset(
    delayL: 700, feedback: 55, mix: 45, pitchShift: 12.0,
    lpFilter: 6000, diffusion: 50, stereoRouting: 1,
  )),
  _DelayPreset('Octave Down', 'Creative', _makePreset(
    delayL: 500, feedback: 50, mix: 40, pitchShift: -12.0,
    hpFilter: 100, lpFilter: 5000,
  )),
  _DelayPreset('Fifth Up', 'Creative', _makePreset(
    delayL: 400, feedback: 45, mix: 40, pitchShift: 7.0,
    lpFilter: 7000, diffusion: 25,
  )),
  _DelayPreset('Cross-Feed Wash', 'Creative', _makePreset(
    delayL: 450, delayR: 600, feedback: 50, mix: 45, link: false,
    stereoRouting: 2, crossFeedback: 40, diffusion: 35,
  )),
  _DelayPreset('Mid/Side Space', 'Creative', _makePreset(
    delayL: 300, feedback: 40, mix: 40, stereoRouting: 4,
    haasDelay: 12, diffusion: 20,
  )),
  _DelayPreset('Haas Widener', 'Creative', _makePreset(
    delayL: 250, feedback: 30, mix: 35, haasDelay: 18,
    stereoRouting: 0, width: 150,
  )),

  // ─── GLITCH / EXPERIMENTAL ──────────────────────
  _DelayPreset('Reverse Wash', 'Glitch', _makePreset(
    delayL: 500, feedback: 50, mix: 50, reverse: true,
    lpFilter: 5000, diffusion: 40,
  )),
  _DelayPreset('Glitch Stutter', 'Glitch', _makePreset(
    delayL: 300, feedback: 40, mix: 50, stutter: true, stutterRate: 80,
  )),
  _DelayPreset('Infinite Hold', 'Glitch', _makePreset(
    delayL: 500, feedback: 50, mix: 50, infiniteFB: true, freeze: true,
    lpFilter: 6000,
  )),
  _DelayPreset('Granular Freeze', 'Glitch', _makePreset(
    delayL: 800, feedback: 60, mix: 55, freeze: true,
    diffusion: 60, lpFilter: 5000, modRate: 0.3, modDepth: 15,
  )),

  // ─── VOCALS ─────────────────────────────────────
  _DelayPreset('Ducking Vocal', 'Vocal', _makePreset(
    delayL: 375, feedback: 35, mix: 40, ducking: 60,
    hpFilter: 200, lpFilter: 6000, stereoRouting: 1,
  )),
  _DelayPreset('Vocal Thickener', 'Vocal', _makePreset(
    delayL: 30, feedback: 15, mix: 35, stereoRouting: 0,
    haasDelay: 8, lpFilter: 7000,
  )),

  // ─── POLYRHYTHMIC ───────────────────────────────
  _DelayPreset('Polyrhythm', 'Rhythm', _makePreset(
    tempoSync: true, noteValueL: 7, noteValueR: 4, link: false,
    feedback: 40, mix: 40, stereoRouting: 1, swing: 30,
  )),
  _DelayPreset('Triplet Bounce', 'Rhythm', _makePreset(
    tempoSync: true, noteValueL: 4, feedback: 45, mix: 40,
    stereoRouting: 1, swing: 0,
  )),
];
