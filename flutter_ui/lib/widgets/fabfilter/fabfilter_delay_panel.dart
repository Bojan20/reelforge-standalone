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
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! DelaySnapshot) return false;
    return delayL == other.delayL && delayR == other.delayR &&
        feedback == other.feedback && mix == other.mix &&
        pingPong == other.pingPong && link == other.link &&
        freeze == other.freeze && tempoSync == other.tempoSync &&
        hpQ == other.hpQ && lpQ == other.lpQ &&
        midFreq == other.midFreq && midGain == other.midGain &&
        drive == other.drive && tilt == other.tilt &&
        lfo1Rate == other.lfo1Rate && lfo1Depth == other.lfo1Depth &&
        lfo1Shape == other.lfo1Shape && lfo2Rate == other.lfo2Rate &&
        lfo2Depth == other.lfo2Depth && pitchShift == other.pitchShift &&
        modRouting == other.modRouting;
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
          // Delay tap visualization
          SizedBox(
            height: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildVisualization(),
            ),
          ),
          // Controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _buildMainKnobRow(),
                  const SizedBox(height: 6),
                  _buildSecondaryRow(),
                  const SizedBox(height: 6),
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
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
        FabFilterKnob(
          value: _feedback / 100.0,
          label: 'FDBK',
          display: _fmtPct(_feedback),
          color: FabFilterColors.orange,
          size: 48,
          defaultValue: 0.4,
          onChanged: (v) {
            setState(() => _feedback = v * 100.0);
            _setParam(_P.feedback, v * 100.0);
          },
        ),
        FabFilterKnob(
          value: _mix / 100.0,
          label: 'MIX',
          display: _fmtPct(_mix),
          color: FabFilterColors.cyan,
          size: 48,
          defaultValue: 0.3,
          onChanged: (v) {
            setState(() => _mix = v * 100.0);
            _setParam(_P.mix, v * 100.0);
          },
        ),
      ],
    );
  }

  Widget _buildDelayKnob(String label, double ms, ValueChanged<double> onMs) {
    final norm = _logNorm(ms.clamp(1, 5000), 1, 5000);
    return FabFilterKnob(
      value: norm,
      label: label,
      display: _fmtMs(ms),
      color: FabFilterColors.cyan,
      size: 48,
      defaultValue: _logNorm(375, 1, 5000),
      onChanged: (v) => onMs(_logDenorm(v, 1, 5000)),
    );
  }

  // ─── SECONDARY ROW ──────────────────────────────────────────────────

  Widget _buildSecondaryRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FabFilterKnob(
          value: _pingPong / 100.0,
          label: 'P-PONG',
          display: _fmtPct(_pingPong),
          color: FabFilterColors.purple,
          size: 40,
          defaultValue: 0.0,
          onChanged: (v) {
            setState(() => _pingPong = v * 100.0);
            _setParam(_P.pingPong, v * 100.0);
          },
        ),
        FabFilterKnob(
          value: _width / 200.0,
          label: 'WIDTH',
          display: '${_width.toStringAsFixed(0)}%',
          color: FabFilterColors.blue,
          size: 40,
          defaultValue: 0.5,
          onChanged: (v) {
            setState(() => _width = v * 200.0);
            _setParam(_P.width, v * 200.0);
          },
        ),
        FabFilterKnob(
          value: _ducking / 100.0,
          label: 'DUCK',
          display: _fmtPct(_ducking),
          color: FabFilterColors.yellow,
          size: 40,
          defaultValue: 0.0,
          onChanged: (v) {
            setState(() => _ducking = v * 100.0);
            _setParam(_P.ducking, v * 100.0);
          },
        ),
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
        ],
      ),
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
