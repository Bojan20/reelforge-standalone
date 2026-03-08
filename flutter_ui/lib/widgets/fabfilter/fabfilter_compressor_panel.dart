/// FF-C Compressor Panel — Pro-C 2 Ultimate
///
/// Professional dynamics processor:
/// - Glass transfer curve with animated knee region, ratio slope, range limit
/// - Scrolling GR history with gradient waveforms, peak hold, RMS overlay
/// - 16 compression styles (VCA/Opto/FET/VariMu/1176/SSL) with smooth switching
/// - Character saturation (Tube / Diode / Bright)
/// - Sidechain EQ with HP/LP/Mid controls + filter response overlay
/// - Real-time I/O + segmented GR metering + crest factor at 60fps
/// - 20 factory presets across 8 categories

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
// ENUMS & CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Insert chain parameter indices
class _P {
  static const threshold = 0;
  static const ratio = 1;
  static const attack = 2;
  static const release = 3;
  static const output = 4;
  static const mix = 5;
  static const link = 6;
  static const type = 7;
  static const character = 8;
  static const drive = 9;
  static const range = 10;
  static const scHpf = 11;
  static const scLpf = 12;
  static const scAudition = 13;
  static const lookahead = 14;
  static const scMidFreq = 15;
  static const scMidGain = 16;
  static const autoThreshold = 17;
  static const autoMakeup = 18;
  static const detection = 19;
  static const adaptiveRelease = 20;
  static const hostSync = 21;
  static const hostBpm = 22;
  static const midSide = 23;
  static const knee = 24;
}

/// Compression style (14 styles)
enum CompressionStyle {
  clean('Clean', Icons.lens_blur),
  classic('Classic', Icons.album),
  opto('Opto', Icons.lightbulb_outline),
  vocal('Vocal', Icons.mic),
  mastering('Master', Icons.tune),
  bus('Bus', Icons.route),
  punch('Punch', Icons.flash_on),
  pumping('Pump', Icons.waves),
  versatile('Versa', Icons.auto_awesome),
  smooth('Smooth', Icons.blur_on),
  upward('Up', Icons.arrow_upward),
  ttm('TTM', Icons.bolt),
  variMu('Vari-µ', Icons.radio),
  elOp('El-Op', Icons.wb_incandescent),
  allButtons('1176', Icons.grid_view),
  sslBus('SSL', Icons.dashboard);

  final String label;
  final IconData icon;
  const CompressionStyle(this.label, this.icon);

  /// Map to insert chain type (0=VCA, 1=Opto, 2=FET, 3=VariMu, 4=AllButtons, 5=SSL)
  int get engineType => switch (this) {
    clean || classic || mastering || bus || versatile || upward => 0,
    opto || vocal || smooth || elOp => 1,
    punch || pumping || ttm => 2,
    variMu => 3,
    allButtons => 4,
    sslBus => 5,
  };
}

/// Character mode for saturation
enum CharacterMode {
  off('Off', Icons.remove_circle_outline, Colors.grey),
  tube('Tube', Icons.local_fire_department, FabFilterColors.orange),
  diode('Diode', Icons.electrical_services, FabFilterColors.yellow),
  bright('Brt', Icons.wb_sunny, FabFilterColors.cyan);

  final String label;
  final IconData icon;
  final Color color;
  const CharacterMode(this.label, this.icon, this.color);
}

/// GR history sample
class _GrSample {
  final double input;
  final double output;
  final double gr;
  final double rmsLevel; // RMS level for overlay
  const _GrSample(this.input, this.output, this.gr, [this.rmsLevel = -60.0]);
}

/// Compressor factory preset (C8.2)
class _CompPreset {
  final String name;
  final String category;
  final CompressionStyle style;
  final double threshold, ratio, knee, attack, release, mix, output;
  final CharacterMode character;
  final double drive;
  final int detection; // 0=Peak, 1=RMS, 2=Hybrid
  final bool adaptiveRelease;

  const _CompPreset(this.name, this.category, this.style, {
    this.threshold = -18.0, this.ratio = 4.0, this.knee = 6.0,
    this.attack = 10.0, this.release = 100.0, this.mix = 100.0,
    this.output = 0.0, this.character = CharacterMode.off, this.drive = 0.0,
    this.detection = 0, this.adaptiveRelease = false,
  });
}

const _kCompPresets = <_CompPreset>[
  // ── Vocal ──
  _CompPreset('Vocal Gentle', 'Vocal', CompressionStyle.opto,
    threshold: -22, ratio: 2.5, knee: 12, attack: 15, release: 150,
    detection: 2, adaptiveRelease: true),
  _CompPreset('Vocal Upfront', 'Vocal', CompressionStyle.vocal,
    threshold: -18, ratio: 4, knee: 6, attack: 5, release: 80,
    character: CharacterMode.tube, drive: 4),
  _CompPreset('Vocal De-Ess', 'Vocal', CompressionStyle.clean,
    threshold: -24, ratio: 6, knee: 3, attack: 0.5, release: 40),
  // ── Drums ──
  _CompPreset('Drum Bus Glue', 'Drums', CompressionStyle.sslBus,
    threshold: -16, ratio: 4, knee: 6, attack: 30, release: 300,
    detection: 2),
  _CompPreset('Snare Punch', 'Drums', CompressionStyle.punch,
    threshold: -20, ratio: 6, knee: 3, attack: 0.1, release: 50),
  _CompPreset('Kick Control', 'Drums', CompressionStyle.allButtons,
    threshold: -14, ratio: 8, knee: 0, attack: 0.5, release: 60),
  _CompPreset('Room Crush', 'Drums', CompressionStyle.allButtons,
    threshold: -30, ratio: 20, knee: 0, attack: 0.02, release: 30,
    mix: 40, character: CharacterMode.tube, drive: 8),
  // ── Bass ──
  _CompPreset('Bass Smooth', 'Bass', CompressionStyle.opto,
    threshold: -20, ratio: 3, knee: 12, attack: 20, release: 200),
  _CompPreset('Bass Tight', 'Bass', CompressionStyle.punch,
    threshold: -16, ratio: 5, knee: 3, attack: 2, release: 80),
  // ── Mix Bus ──
  _CompPreset('Mix Bus SSL', 'Mix Bus', CompressionStyle.sslBus,
    threshold: -12, ratio: 2, knee: 6, attack: 30, release: 300,
    detection: 2, adaptiveRelease: true),
  _CompPreset('Mix Bus Gentle', 'Mix Bus', CompressionStyle.clean,
    threshold: -16, ratio: 1.5, knee: 18, attack: 30, release: 400,
    detection: 1),
  _CompPreset('Mix Bus NY', 'Mix Bus', CompressionStyle.classic,
    threshold: -25, ratio: 8, knee: 3, attack: 5, release: 100,
    mix: 35, character: CharacterMode.tube, drive: 4),
  // ── Master ──
  _CompPreset('Master Transparent', 'Master', CompressionStyle.mastering,
    threshold: -10, ratio: 1.5, knee: 12, attack: 30, release: 400,
    detection: 1, adaptiveRelease: true),
  _CompPreset('Master Warm', 'Master', CompressionStyle.variMu,
    threshold: -14, ratio: 2, knee: 12, attack: 20, release: 300,
    character: CharacterMode.tube, drive: 3),
  // ── Creative ──
  _CompPreset('Parallel Crush', 'Creative', CompressionStyle.allButtons,
    threshold: -30, ratio: 20, knee: 0, attack: 0.1, release: 40,
    mix: 30, character: CharacterMode.diode, drive: 12),
  _CompPreset('Pumping', 'Creative', CompressionStyle.pumping,
    threshold: -20, ratio: 8, knee: 0, attack: 0.5, release: 200),
  _CompPreset('Tube Warmth', 'Creative', CompressionStyle.variMu,
    threshold: -18, ratio: 3, knee: 12, attack: 15, release: 200,
    character: CharacterMode.tube, drive: 6),
  // ── Sidechain ──
  _CompPreset('SC Ducking', 'Sidechain', CompressionStyle.clean,
    threshold: -20, ratio: 8, knee: 3, attack: 1, release: 100),
  // ── Surgical ──
  _CompPreset('Surgical Peak', 'Surgical', CompressionStyle.clean,
    threshold: -6, ratio: 10, knee: 0, attack: 0.02, release: 20),
  _CompPreset('Tame Transients', 'Surgical', CompressionStyle.versatile,
    threshold: -12, ratio: 3, knee: 6, attack: 0.1, release: 60,
    detection: 0),
];

/// Snapshot for A/B comparison
class CompressorSnapshot implements DspParameterSnapshot {
  final double threshold, ratio, knee, attack, release, range, mix, output;
  final CompressionStyle style;
  final CharacterMode character;
  final double drive, lookahead, scHpf, scLpf, scMidFreq, scMidGain, hostBpm;
  final bool autoThreshold, autoMakeup, adaptiveRelease, hostSync, midSide;
  final int detection;

  const CompressorSnapshot({
    required this.threshold, required this.ratio, required this.knee,
    required this.attack, required this.release, required this.range,
    required this.mix, required this.output, required this.style,
    required this.character, required this.drive, required this.lookahead,
    required this.scHpf, required this.scLpf, required this.scMidFreq,
    required this.scMidGain, required this.hostBpm, required this.autoThreshold,
    required this.autoMakeup, required this.adaptiveRelease,
    required this.hostSync, required this.midSide, required this.detection,
  });

  @override
  CompressorSnapshot copy() => CompressorSnapshot(
    threshold: threshold, ratio: ratio, knee: knee, attack: attack,
    release: release, range: range, mix: mix, output: output, style: style,
    character: character, drive: drive, lookahead: lookahead, scHpf: scHpf,
    scLpf: scLpf, scMidFreq: scMidFreq, scMidGain: scMidGain,
    hostBpm: hostBpm, autoThreshold: autoThreshold, autoMakeup: autoMakeup,
    adaptiveRelease: adaptiveRelease, hostSync: hostSync, midSide: midSide,
    detection: detection,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! CompressorSnapshot) return false;
    return threshold == other.threshold && ratio == other.ratio &&
        knee == other.knee && attack == other.attack &&
        release == other.release && style == other.style &&
        character == other.character && detection == other.detection;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterCompressorPanel extends FabFilterPanelBase {
  const FabFilterCompressorPanel({
    super.key,
    required super.trackId,
    super.slotIndex,
  }) : super(
          title: 'FF-C',
          icon: Icons.compress,
          accentColor: FabFilterColors.orange,
          nodeType: DspNodeType.compressor,
        );

  @override
  State<FabFilterCompressorPanel> createState() =>
      _FabFilterCompressorPanelState();
}

class _FabFilterCompressorPanelState extends State<FabFilterCompressorPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {

  // ─── PARAMETERS ─────────────────────────────────────────────────────
  double _threshold = -18.0;
  double _ratio = 4.0;
  double _knee = 12.0;
  double _attack = 10.0;
  double _release = 100.0;
  double _range = -40.0;
  double _mix = 100.0;
  double _output = 0.0;

  CompressionStyle _style = CompressionStyle.clean;
  CharacterMode _character = CharacterMode.off;
  double _drive = 0.0;

  // Sidechain
  bool _scEnabled = false;
  double _scHpf = 80.0;
  double _scLpf = 12000.0;
  bool _scAudition = false;
  double _scMidFreq = 1000.0;
  double _scMidGain = 0.0;

  // Advanced
  double _lookahead = 0.0;
  bool _autoThreshold = false;
  bool _autoMakeup = false;
  int _detection = 0; // 0=Peak, 1=RMS, 2=Hybrid
  bool _adaptiveRelease = false;
  bool _hostSync = false;
  double _hostBpm = 120.0;
  bool _midSide = false;

  // ─── METERING ───────────────────────────────────────────────────────
  double _inputLevel = -60.0;
  double _outputLevel = -60.0;
  double _grCurrent = 0.0;
  double _grPeakHold = 0.0;
  int _grPeakHoldTimer = 0;
  double _rmsLevel = -60.0;
  double _rmsAccum = 0.0;
  int _rmsCount = 0;
  static const _rmsWindow = 10; // ~160ms at 60fps
  double _crestFactor = 0.0; // peak-to-RMS ratio in dB
  double _lufsApprox = -60.0; // approximated LUFS (RMS-based)
  final List<_GrSample> _grHistory = [];
  static const _maxHistory = 200;

  // ─── ENGINE ─────────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ────────────────────────────────────────────────────────────
  CompressorSnapshot? _snapshotA;
  CompressorSnapshot? _snapshotB;

  // ─── UNDO/REDO (C8.1) ─────────────────────────────────────────────
  final List<CompressorSnapshot> _undoStack = [];
  final List<CompressorSnapshot> _redoStack = [];
  static const _maxUndoStack = 50;
  late final FocusNode _panelFocusNode;

  // ─── DYNAMIC RANGE & STEREO CORRELATION (C4.3/C4.4) ───────────────
  double _dynamicRange = 0.0; // peak-to-trough in dB
  double _stereoCorrelation = 1.0; // -1 to +1
  double _inputPeakMax = -60.0;
  double _inputPeakMin = 0.0;
  int _drWindowCounter = 0;
  static const _drWindowFrames = 60; // ~1s at 60fps

  @override
  int get processorSlotIndex => _slotIndex;

  // ─── LIFECYCLE ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _panelFocusNode = FocusNode(debugLabel: 'comp-panel');
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
    _panelFocusNode.dispose();
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
      if (node.type == DspNodeType.compressor) {
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
      _threshold = _ffi.insertGetParam(t, s, _P.threshold);
      _ratio = _ffi.insertGetParam(t, s, _P.ratio);
      _attack = _ffi.insertGetParam(t, s, _P.attack);
      _release = _ffi.insertGetParam(t, s, _P.release);
      _output = _ffi.insertGetParam(t, s, _P.output);
      _mix = _ffi.insertGetParam(t, s, _P.mix) * 100.0;
      _character = _indexToCharacter(_ffi.insertGetParam(t, s, _P.character));
      _drive = _ffi.insertGetParam(t, s, _P.drive);
      _range = _ffi.insertGetParam(t, s, _P.range);
      _scHpf = _ffi.insertGetParam(t, s, _P.scHpf);
      _scLpf = _ffi.insertGetParam(t, s, _P.scLpf);
      _scAudition = _ffi.insertGetParam(t, s, _P.scAudition) > 0.5;
      _lookahead = _ffi.insertGetParam(t, s, _P.lookahead);
      _scMidFreq = _ffi.insertGetParam(t, s, _P.scMidFreq);
      _scMidGain = _ffi.insertGetParam(t, s, _P.scMidGain);
      _autoThreshold = _ffi.insertGetParam(t, s, _P.autoThreshold) > 0.5;
      _autoMakeup = _ffi.insertGetParam(t, s, _P.autoMakeup) > 0.5;
      _detection = _ffi.insertGetParam(t, s, _P.detection).round();
      _adaptiveRelease = _ffi.insertGetParam(t, s, _P.adaptiveRelease) > 0.5;
      _hostSync = _ffi.insertGetParam(t, s, _P.hostSync) > 0.5;
      _hostBpm = _ffi.insertGetParam(t, s, _P.hostBpm);
      _midSide = _ffi.insertGetParam(t, s, _P.midSide) > 0.5;
      _knee = _ffi.insertGetParam(t, s, _P.knee);
    });
  }

  CharacterMode _indexToCharacter(double v) => switch (v.round()) {
    1 => CharacterMode.tube, 2 => CharacterMode.diode,
    3 => CharacterMode.bright, _ => CharacterMode.off,
  };

  void _setParam(int idx, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, idx, value);
    }
  }

  // ─── A/B ────────────────────────────────────────────────────────────

  CompressorSnapshot _snap() => CompressorSnapshot(
    threshold: _threshold, ratio: _ratio, knee: _knee, attack: _attack,
    release: _release, range: _range, mix: _mix, output: _output,
    style: _style, character: _character, drive: _drive, lookahead: _lookahead,
    scHpf: _scHpf, scLpf: _scLpf, scMidFreq: _scMidFreq,
    scMidGain: _scMidGain, hostBpm: _hostBpm, autoThreshold: _autoThreshold,
    autoMakeup: _autoMakeup, adaptiveRelease: _adaptiveRelease,
    hostSync: _hostSync, midSide: _midSide, detection: _detection,
  );

  void _restore(CompressorSnapshot s) {
    setState(() {
      _threshold = s.threshold; _ratio = s.ratio; _knee = s.knee;
      _attack = s.attack; _release = s.release; _range = s.range;
      _mix = s.mix; _output = s.output; _style = s.style;
      _character = s.character; _drive = s.drive; _lookahead = s.lookahead;
      _scHpf = s.scHpf; _scLpf = s.scLpf; _scMidFreq = s.scMidFreq;
      _scMidGain = s.scMidGain; _hostBpm = s.hostBpm;
      _autoThreshold = s.autoThreshold; _autoMakeup = s.autoMakeup;
      _adaptiveRelease = s.adaptiveRelease; _hostSync = s.hostSync;
      _midSide = s.midSide; _detection = s.detection;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.threshold, _threshold);
    _setParam(_P.ratio, _ratio);
    _setParam(_P.attack, _attack);
    _setParam(_P.release, _release);
    _setParam(_P.output, _output);
    _setParam(_P.mix, _mix / 100.0);
    _setParam(_P.link, 1.0);
    _setParam(_P.type, _style.engineType.toDouble());
    _setParam(_P.character, _character.index.toDouble());
    _setParam(_P.drive, _drive);
    _setParam(_P.range, _range);
    _setParam(_P.scHpf, _scHpf);
    _setParam(_P.scLpf, _scLpf);
    _setParam(_P.scAudition, _scAudition ? 1 : 0);
    _setParam(_P.lookahead, _lookahead);
    _setParam(_P.scMidFreq, _scMidFreq);
    _setParam(_P.scMidGain, _scMidGain);
    _setParam(_P.autoThreshold, _autoThreshold ? 1 : 0);
    _setParam(_P.autoMakeup, _autoMakeup ? 1 : 0);
    _setParam(_P.detection, _detection.toDouble());
    _setParam(_P.adaptiveRelease, _adaptiveRelease ? 1 : 0);
    _setParam(_P.hostSync, _hostSync ? 1 : 0);
    _setParam(_P.hostBpm, _hostBpm);
    _setParam(_P.midSide, _midSide ? 1 : 0);
    _setParam(_P.knee, _knee);
  }

  void _loadPreset(_CompPreset p) {
    _pushUndo();
    setState(() {
      _threshold = p.threshold;
      _ratio = p.ratio;
      _knee = p.knee;
      _attack = p.attack;
      _release = p.release;
      _mix = p.mix;
      _output = p.output;
      _style = p.style;
      _character = p.character;
      _drive = p.drive;
      _detection = p.detection;
      _adaptiveRelease = p.adaptiveRelease;
    });
    _applyAll();
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

  // ─── UNDO/REDO (C8.1) ──────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(_snap());
    if (_undoStack.length > _maxUndoStack) _undoStack.removeAt(0);
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

  /// GR reset — clear history and peak hold (C8.7)
  void _resetGr() {
    setState(() {
      _grHistory.clear();
      _grPeakHold = 0.0;
      _grPeakHoldTimer = 0;
      _inputPeakMax = -60.0;
      _inputPeakMin = 0.0;
      _dynamicRange = 0.0;
    });
  }

  /// Keyboard handler for Cmd+Z / Cmd+Shift+Z (C8.1)
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Guard: don't handle if focus is on an EditableText
    if (_panelFocusNode.context != null) {
      final scope = FocusScope.of(_panelFocusNode.context!);
      if (scope.focusedChild != _panelFocusNode) return KeyEventResult.ignored;
    }
    final isMeta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) { _redo(); } else { _undo(); }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── METERING ───────────────────────────────────────────────────────

  void _updateMeters() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId, s = _slotIndex;

    setState(() {
      try {
        final grL = _ffi.insertGetMeter(t, s, 0);
        final grR = _ffi.insertGetMeter(t, s, 1);
        _grCurrent = (grL + grR) / 2.0;
      } catch (e) { _grCurrent = 0.0;
        assert(() { debugPrint('Compressor GR meter error: $e'); return true; }());
      }

      try {
        final peaks = _ffi.getPeakMeters();
        final peakLin = math.max(peaks.$1, peaks.$2);
        _inputLevel = peakLin > 1e-10 ? 20.0 * math.log(peakLin) / math.ln10 : -60.0;
        _outputLevel = _inputLevel + _grCurrent;
      } catch (e) {
        assert(() { debugPrint('Compressor peak meter error: $e'); return true; }());
      }

      // Peak hold with 2s decay (120 frames at 60fps)
      if (_grCurrent.abs() > _grPeakHold.abs()) {
        _grPeakHold = _grCurrent;
        _grPeakHoldTimer = 120;
      } else if (_grPeakHoldTimer > 0) {
        _grPeakHoldTimer--;
      } else {
        _grPeakHold = _grPeakHold * 0.95; // smooth decay
      }

      // RMS accumulation
      final lin = _inputLevel > -60 ? math.pow(10, _inputLevel / 20) : 0.0;
      _rmsAccum += lin * lin;
      _rmsCount++;
      if (_rmsCount >= _rmsWindow) {
        final rmsLin = math.sqrt(_rmsAccum / _rmsCount);
        _rmsLevel = rmsLin > 1e-10 ? 20.0 * math.log(rmsLin) / math.ln10 : -60.0;
        _rmsAccum = 0.0;
        _rmsCount = 0;

        // Crest factor: peak - RMS (in dB)
        _crestFactor = (_inputLevel - _rmsLevel).clamp(0.0, 30.0);

        // LUFS approximation: RMS with K-weighting offset (~+0.7 dB for broadband)
        _lufsApprox = _rmsLevel + 0.7;
      }

      // Dynamic range measurement (C4.3) — peak-to-trough over 1s window
      if (_inputLevel > _inputPeakMax) _inputPeakMax = _inputLevel;
      if (_inputLevel > -59 && _inputLevel < _inputPeakMin) _inputPeakMin = _inputLevel;
      _drWindowCounter++;
      if (_drWindowCounter >= _drWindowFrames) {
        _dynamicRange = (_inputPeakMax - _inputPeakMin).clamp(0.0, 60.0);
        _inputPeakMax = -60.0;
        _inputPeakMin = 0.0;
        _drWindowCounter = 0;
      }

      // Stereo correlation approximation (C4.4)
      try {
        final peaks = _ffi.getPeakMeters();
        final l = peaks.$1, r = peaks.$2;
        if (l > 1e-10 && r > 1e-10) {
          // Simple correlation: 1.0 = identical, 0 = uncorrelated, -1 = opposite
          final sum = l + r;
          final diff = (l - r).abs();
          _stereoCorrelation = ((sum - diff) / sum).clamp(-1.0, 1.0);
        }
      } catch (_) {}

      _grHistory.add(_GrSample(_inputLevel, _outputLevel, _grCurrent, _rmsLevel));
      while (_grHistory.length > _maxHistory) _grHistory.removeAt(0);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('Compressor', DspNodeType.compressor, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Focus(
      focusNode: _panelFocusNode,
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: GestureDetector(
        onTap: () => _panelFocusNode.requestFocus(),
        child: Container(
          decoration: FabFilterDecorations.panel(),
          child: Column(
            children: [
              buildCompactHeader(),
              // Display: transfer curve + GR history
              SizedBox(
                height: 110,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: _buildDisplay(),
                ),
              ),
              // Controls
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      // Style chips + character
                      SizedBox(
                        height: 28,
                        child: Row(
                          children: [
                            Expanded(child: _buildStyleChips()),
                            const SizedBox(width: 4),
                            _buildCharacterChip(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Main controls
                      Expanded(child: _buildMainRow()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // ─── DISPLAY ────────────────────────────────────────────────────────

  Widget _buildDisplay() {
    return Row(
      children: [
        // Transfer curve
        Expanded(
          child: Container(
            decoration: FabFilterDecorations.display(),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _KneeCurvePainter(
                      threshold: _threshold,
                      ratio: _ratio,
                      knee: _knee,
                      currentInput: _inputLevel,
                      grAmount: _grCurrent,
                      range: _range,
                      mix: _mix,
                    ),
                  ),
                ),
                // Ratio + threshold badge
                Positioned(
                  right: 4, top: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xDD0A0A10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: FabFilterProcessorColors.compAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${_ratio.toStringAsFixed(1)}:1  ${_threshold.toStringAsFixed(0)}dB',
                      style: TextStyle(
                        color: FabFilterProcessorColors.compAccent,
                        fontSize: 8, fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // Knee badge + look-ahead display (bottom-left) (C5.4)
                Positioned(
                  left: 4, bottom: 3,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_knee > 0.5)
                        Text(
                          'K ${_knee.toStringAsFixed(0)}dB',
                          style: TextStyle(
                            color: FabFilterProcessorColors.compKnee.withValues(alpha: 0.6),
                            fontSize: 7, fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (_knee > 0.5 && _lookahead > 0.1)
                        const SizedBox(width: 4),
                      if (_lookahead > 0.1)
                        Text(
                          'LA ${_lookahead.toStringAsFixed(1)}ms',
                          style: TextStyle(
                            color: FabFilterColors.cyan.withValues(alpha: 0.6),
                            fontSize: 7, fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                // Mix badge (bottom-right on transfer curve)
                if (_mix < 99)
                  Positioned(
                    right: 4, bottom: 3,
                    child: Text(
                      'MIX ${_mix.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: FabFilterColors.blue.withValues(alpha: 0.6),
                        fontSize: 7, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                // Undo indicator (C8.1) — subtle badge when undo stack available
                if (_undoStack.isNotEmpty)
                  Positioned(
                    left: 4, top: 3,
                    child: Text(
                      '↩${_undoStack.length}',
                      style: TextStyle(
                        color: FabFilterColors.textTertiary.withValues(alpha: 0.4),
                        fontSize: 6, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // GR history
        Expanded(
          child: Container(
            decoration: FabFilterDecorations.display(),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GrHistoryPainter(
                      history: _grHistory,
                      threshold: _threshold,
                      grPeakHold: _grPeakHold,
                      range: _range,
                      lookaheadMs: _lookahead,
                    ),
                  ),
                ),
                // SC filter response overlay with EQ node indicators (C2.1/C2.3)
                if (_scEnabled)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ScFilterResponsePainter(
                        hpFreq: _scHpf,
                        lpFreq: _scLpf,
                        midFreq: _scMidFreq,
                        midGain: _scMidGain,
                        showNodes: true,
                      ),
                    ),
                  ),
                // SC Audition visual feedback (C2.5) — pulsing border overlay
                if (_scEnabled && _scAudition)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: FabFilterColors.purple.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: FabFilterColors.purple.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('SC LISTEN', style: TextStyle(
                              color: FabFilterColors.purple,
                              fontSize: 6, fontWeight: FontWeight.bold,
                            )),
                          ),
                        ),
                      ),
                    ),
                  ),
                // GR readout (bottom-right)
                Positioned(
                  right: 4, bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xDD0A0A10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.3),
                      ),
                    ),
                    child: RichText(text: TextSpan(
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()]),
                      children: [
                        TextSpan(
                          text: 'GR ${_grCurrent.toStringAsFixed(1)}',
                          style: TextStyle(color: FabFilterProcessorColors.compGainReduction),
                        ),
                        TextSpan(
                          text: '  pk ${_grPeakHold.toStringAsFixed(1)}',
                          style: TextStyle(color: FabFilterColors.textTertiary),
                        ),
                      ],
                    )),
                  ),
                ),
                // GR reset button (C8.7)
                Positioned(
                  right: 4, top: 3,
                  child: GestureDetector(
                    onTap: _resetGr,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xDD0A0A10),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: FabFilterColors.textTertiary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text('RST', style: TextStyle(
                        color: FabFilterColors.textTertiary,
                        fontSize: 6, fontWeight: FontWeight.bold,
                      )),
                    ),
                  ),
                ),
                // Detection + style badge (top-left)
                Positioned(
                  left: 4, top: 3,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: FabFilterColors.cyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          ['PEAK', 'RMS', 'HYB'][_detection],
                          style: TextStyle(
                            color: FabFilterColors.cyan, fontSize: 7, fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _style.label.toUpperCase(),
                        style: TextStyle(
                          color: FabFilterProcessorColors.compAccent.withValues(alpha: 0.5),
                          fontSize: 7, fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── STYLE CHIPS ────────────────────────────────────────────────────

  Widget _buildStyleChips() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: CompressionStyle.values.length,
      separatorBuilder: (_, _a) => const SizedBox(width: 4),
      itemBuilder: (ctx, i) {
        final s = CompressionStyle.values[i];
        final active = _style == s;
        return GestureDetector(
          onTap: () {
            _pushUndo();
            setState(() => _style = s);
            _setParam(_P.type, s.engineType.toDouble());
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active
                  ? FabFilterProcessorColors.compAccent.withValues(alpha: 0.25)
                  : FabFilterColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? FabFilterProcessorColors.compAccent : FabFilterColors.borderMedium,
                width: active ? 1.5 : 1,
              ),
              boxShadow: active ? [
                BoxShadow(
                  color: FabFilterProcessorColors.compAccent.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 12,
                  color: active ? FabFilterProcessorColors.compAccent : FabFilterColors.textTertiary),
                const SizedBox(width: 3),
                Text(s.label, style: TextStyle(
                  color: active ? FabFilterProcessorColors.compAccent : FabFilterColors.textSecondary,
                  fontSize: 9, fontWeight: active ? FontWeight.bold : FontWeight.w500,
                ), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCharacterChip() {
    final active = _character != CharacterMode.off;
    return GestureDetector(
      onTap: () {
        _pushUndo();
        final next = CharacterMode.values[(_character.index + 1) % CharacterMode.values.length];
        setState(() {
          _character = next;
          if (next != CharacterMode.off && _drive < 0.1) _drive = 6.0;
        });
        _setParam(_P.character, next.index.toDouble());
        if (next != CharacterMode.off && _drive >= 0.1) {
          _setParam(_P.drive, _drive);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: active ? _character.color.withValues(alpha: 0.2) : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? _character.color : FabFilterColors.borderMedium,
          ),
          boxShadow: active ? [
            BoxShadow(
              color: _character.color.withValues(alpha: 0.15),
              blurRadius: 6,
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_character.icon, size: 12, color: _character.color),
            const SizedBox(width: 3),
            Text(_character.label, style: TextStyle(
              color: _character.color, fontSize: 9, fontWeight: FontWeight.bold,
            ), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ─── MAIN ROW ───────────────────────────────────────────────────────

  Widget _buildMainRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT: Meters (In/Out/GR)
        _buildMeters(),
        const SizedBox(width: 8),
        // CENTER: Knobs
        Expanded(flex: 3, child: _buildKnobs()),
        const SizedBox(width: 8),
        // RIGHT: Options
        SizedBox(width: 100, child: _buildOptions()),
      ],
    );
  }

  Widget _buildMeters() {
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          // Main meters row
          Expanded(
            child: Row(
              children: [
                _buildVerticalMeter('IN', _inputLevel, FabFilterColors.textSecondary),
                const SizedBox(width: 2),
                _buildVerticalMeter('OUT', _outputLevel, FabFilterColors.blue),
                const SizedBox(width: 2),
                _buildSegmentedGrMeter(),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Crest factor + LUFS + Dynamic Range + Stereo Correlation (C4.1-C4.4)
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'CF ${_crestFactor.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: FabFilterColors.yellow.withValues(alpha: 0.7),
                      fontSize: 6, fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'LU ${_lufsApprox.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: FabFilterColors.green.withValues(alpha: 0.7),
                      fontSize: 6, fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'DR ${_dynamicRange.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: FabFilterColors.cyan.withValues(alpha: 0.7),
                      fontSize: 6, fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'SC ${_stereoCorrelation.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: _stereoCorrelation < 0
                          ? FabFilterColors.red.withValues(alpha: 0.8)
                          : FabFilterColors.blue.withValues(alpha: 0.7),
                      fontSize: 6, fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Segmented GR LED meter — Pro-C 2 style (C4.5)
  Widget _buildSegmentedGrMeter() {
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 14,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: CustomPaint(
                painter: _SegmentedGrPainter(
                  grDb: _grCurrent,
                  peakHold: _grPeakHold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text('GR', style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(String label, double dB, Color color,
      {bool fromTop = false}) {
    final norm = fromTop
        ? (dB.abs() / 40).clamp(0.0, 1.0)
        : ((dB + 60) / 60).clamp(0.0, 1.0);

    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: CustomPaint(
                painter: _VerticalMeterPainter(
                  value: norm,
                  color: color,
                  fromTop: fromTop,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        ],
      ),
    );
  }

  Widget _buildKnobs() {
    return Column(
      children: [
        // Row 1: Main knobs
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _knob('THRESH', (_threshold + 60) / 60,
                '${_threshold.toStringAsFixed(0)} dB',
                FabFilterProcessorColors.compThreshold, (v) {
                  setState(() => _threshold = v * 60 - 60);
                  _setParam(_P.threshold, _threshold);
                }),
              _knob('RATIO', (_ratio - 1) / 19,
                '${_ratio.toStringAsFixed(1)}:1',
                FabFilterProcessorColors.compAccent, (v) {
                  setState(() => _ratio = v * 19 + 1);
                  _setParam(_P.ratio, _ratio);
                }),
              _knob('KNEE', _knee / 24,
                '${_knee.toStringAsFixed(0)} dB',
                FabFilterProcessorColors.compKnee, (v) {
                  setState(() => _knee = v * 24);
                  _setParam(_P.knee, _knee);
                }),
              _knob('ATT', math.log(_attack / 0.01) / math.log(500 / 0.01),
                _attack < 1
                  ? '${(_attack * 1000).toStringAsFixed(0)}µ'
                  : '${_attack.toStringAsFixed(0)}ms',
                FabFilterColors.cyan, (v) {
                  setState(() => _attack = 0.01 * math.pow(500 / 0.01, v));
                  _setParam(_P.attack, _attack);
                }),
              _knob('REL', math.log(_release / 5) / math.log(5000 / 5),
                _release >= 1000
                  ? '${(_release / 1000).toStringAsFixed(1)}s'
                  : '${_release.toStringAsFixed(0)}ms',
                FabFilterColors.cyan, (v) {
                  setState(() => _release = (5 * math.pow(5000 / 5, v)).toDouble());
                  _setParam(_P.release, _release);
                }),
              _knob('MIX', _mix / 100,
                '${_mix.toStringAsFixed(0)}%',
                FabFilterColors.blue, (v) {
                  setState(() => _mix = v * 100);
                  _setParam(_P.mix, _mix / 100.0);
                }),
              _knob('OUT', (_output + 24) / 48,
                '${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(0)}dB',
                FabFilterColors.green, (v) {
                  setState(() => _output = v * 48 - 24);
                  _setParam(_P.output, _output);
                }),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Secondary knobs + toggles
        SizedBox(
          height: 24,
          child: Row(
            children: [
              _miniParam('LOOK', _lookahead / 20,
                '${_lookahead.toStringAsFixed(1)}',
                FabFilterColors.purple, (v) {
                  setState(() => _lookahead = v * 20);
                  _setParam(_P.lookahead, _lookahead);
                }),
              const SizedBox(width: 4),
              _miniParam('DRV', _drive / 24,
                '${_drive.toStringAsFixed(0)}',
                FabFilterProcessorColors.compAccent, (v) {
                  setState(() => _drive = v * 24);
                  _setParam(_P.drive, _drive);
                }),
              const SizedBox(width: 4),
              _miniParam('RNG', (_range + 60) / 60,
                '${_range.toStringAsFixed(0)}',
                FabFilterColors.cyan, (v) {
                  setState(() => _range = v * 60 - 60);
                  _setParam(_P.range, _range);
                }),
              const SizedBox(width: 6),
              // Detection mode
              ..._detectionButtons(),
              const SizedBox(width: 6),
              // NY compression shortcut (C7.4) — sets mix to 45% for parallel compression
              _toggle('NY', _mix > 20 && _mix < 80, FabFilterColors.orange, () {
                _pushUndo();
                final isNy = _mix > 20 && _mix < 80;
                setState(() {
                  _mix = isNy ? 100.0 : 45.0;
                  // When activating NY mode, set aggressive settings if needed
                  if (!isNy && _ratio < 4) _ratio = 8.0;
                  if (!isNy && _threshold > -15) _threshold = -25.0;
                });
                _setParam(_P.mix, _mix / 100.0);
                if (!isNy) {
                  _setParam(_P.ratio, _ratio);
                  _setParam(_P.threshold, _threshold);
                }
              }),
              const SizedBox(width: 2),
              _toggle('M/S', _midSide, FabFilterColors.purple, () {
                setState(() => _midSide = !_midSide);
                _setParam(_P.midSide, _midSide ? 1 : 0);
              }),
              const SizedBox(width: 2),
              _toggle('AR', _adaptiveRelease, FabFilterColors.cyan, () {
                setState(() => _adaptiveRelease = !_adaptiveRelease);
                _setParam(_P.adaptiveRelease, _adaptiveRelease ? 1 : 0);
              }),
              const SizedBox(width: 2),
              _toggle('AM', _autoMakeup, FabFilterColors.green, () {
                setState(() => _autoMakeup = !_autoMakeup);
                _setParam(_P.autoMakeup, _autoMakeup ? 1 : 0);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _knob(String label, double value, String display, Color color,
      ValueChanged<double> onChanged) {
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 48,
      onChanged: onChanged,
    );
  }

  Widget _miniParam(String label, double value, String display, Color color,
      ValueChanged<double> onChanged) {
    return SizedBox(
      width: 48,
      child: Row(
        children: [
          FabFilterKnob(
            value: value.clamp(0.0, 1.0), label: '', display: '',
            color: color, size: 20, onChanged: onChanged,
          ),
          const SizedBox(width: 2),
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
              Text(display, style: TextStyle(color: color, fontSize: 7)),
            ],
          )),
        ],
      ),
    );
  }

  List<Widget> _detectionButtons() {
    const labels = ['P', 'R', 'H'];
    const tips = ['Peak', 'RMS', 'Hybrid'];
    return List.generate(3, (i) => Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: tips[i],
        child: FabTinyButton(
          label: labels[i],
          active: _detection == i,
          color: FabFilterColors.cyan,
          onTap: () {
            setState(() => _detection = i);
            _setParam(_P.detection, i.toDouble());
          },
        ),
      ),
    ));
  }

  Widget _toggle(String label, bool active, Color color, VoidCallback onTap) {
    return FabCompactToggle(
      label: label,
      active: active,
      onToggle: onTap,
      color: color,
    );
  }

  // ─── OPTIONS ────────────────────────────────────────────────────────

  Widget _buildOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FabOptionRow(label: 'SC', value: _scEnabled, accentColor: widget.accentColor,
          onChanged: (v) => setState(() => _scEnabled = v)),
        if (_scEnabled) ...[
          const SizedBox(height: 2),
          FabMiniSlider(label: 'HP', labelWidth: 18,
            value: (math.log(_scHpf / 20) / math.log(500 / 20)).clamp(0.0, 1.0),
            display: '${_scHpf.toStringAsFixed(0)}',
            activeColor: widget.accentColor,
            onChanged: (v) {
              setState(() => _scHpf = (20 * math.pow(500 / 20, v)).toDouble());
              _setParam(_P.scHpf, _scHpf);
            }),
          const SizedBox(height: 2),
          FabMiniSlider(label: 'LP', labelWidth: 18,
            value: (math.log(_scLpf / 1000) / math.log(20000 / 1000)).clamp(0.0, 1.0),
            display: '${(_scLpf / 1000).toStringAsFixed(0)}k',
            activeColor: widget.accentColor,
            onChanged: (v) {
              setState(() => _scLpf = (1000 * math.pow(20000 / 1000, v)).toDouble());
              _setParam(_P.scLpf, _scLpf);
            }),
          const SizedBox(height: 2),
          FabMiniSlider(label: 'MF', labelWidth: 18,
            value: (math.log(_scMidFreq / 200) / math.log(5000 / 200)).clamp(0.0, 1.0),
            display: '${_scMidFreq.toStringAsFixed(0)}',
            activeColor: widget.accentColor,
            onChanged: (v) {
              setState(() => _scMidFreq = (200 * math.pow(5000 / 200, v)).toDouble());
              _setParam(_P.scMidFreq, _scMidFreq);
            }),
          const SizedBox(height: 2),
          FabMiniSlider(label: 'MG', labelWidth: 18,
            value: ((_scMidGain + 12) / 24).clamp(0.0, 1.0),
            display: '${_scMidGain >= 0 ? '+' : ''}${_scMidGain.toStringAsFixed(0)}',
            activeColor: widget.accentColor,
            onChanged: (v) {
              setState(() => _scMidGain = v * 24 - 12);
              _setParam(_P.scMidGain, _scMidGain);
            }),
          const SizedBox(height: 2),
          FabOptionRow(label: 'AUD', value: _scAudition, accentColor: widget.accentColor,
            onChanged: (v) {
              setState(() => _scAudition = v);
              _setParam(_P.scAudition, v ? 1 : 0);
            }),
        ],
        const Flexible(child: SizedBox(height: 4)),
        FabOptionRow(label: 'A-THR', value: _autoThreshold, accentColor: widget.accentColor,
          onChanged: (v) {
            setState(() => _autoThreshold = v);
            _setParam(_P.autoThreshold, v ? 1 : 0);
          }),
        const SizedBox(height: 2),
        FabOptionRow(label: 'SYNC', value: _hostSync, accentColor: widget.accentColor,
          onChanged: (v) {
            setState(() => _hostSync = v);
            _setParam(_P.hostSync, v ? 1 : 0);
          }),
        if (_hostSync) ...[
          const SizedBox(height: 2),
          FabMiniSlider(label: 'BPM', labelWidth: 22,
            value: ((_hostBpm - 20) / 280).clamp(0.0, 1.0),
            display: '${_hostBpm.toStringAsFixed(0)}',
            activeColor: widget.accentColor,
            onChanged: (v) {
              setState(() => _hostBpm = v * 280 + 20);
              _setParam(_P.hostBpm, _hostBpm);
            }),
        ],
        const Flexible(child: SizedBox(height: 4)),
        // Preset browser (C8.2)
        _buildPresetButton(),
      ],
    );
  }

  Widget _buildPresetButton() {
    // Group presets by category
    final categories = <String, List<_CompPreset>>{};
    for (final p in _kCompPresets) {
      categories.putIfAbsent(p.category, () => []).add(p);
    }

    return PopupMenuButton<_CompPreset>(
      onSelected: _loadPreset,
      tooltip: 'Factory Presets',
      offset: const Offset(0, 20),
      color: const Color(0xFF1A1A22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: widget.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 10, color: widget.accentColor),
            const SizedBox(width: 3),
            Text('PRE', style: TextStyle(
              color: widget.accentColor, fontSize: 8, fontWeight: FontWeight.bold,
            )),
          ],
        ),
      ),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<_CompPreset>>[];
        for (final cat in categories.entries) {
          // Category header
          items.add(PopupMenuItem<_CompPreset>(
            enabled: false, height: 20,
            child: Text(cat.key.toUpperCase(), style: TextStyle(
              color: widget.accentColor.withValues(alpha: 0.6),
              fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1,
            )),
          ));
          for (final p in cat.value) {
            items.add(PopupMenuItem<_CompPreset>(
              value: p, height: 28,
              child: Text(p.name, style: const TextStyle(
                color: Colors.white, fontSize: 11,
              )),
            ));
          }
        }
        return items;
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VERTICAL METER PAINTER — gradient fills with peak line
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
// GR HISTORY PAINTER — glass waveform with gradient fills
// ═══════════════════════════════════════════════════════════════════════════

class _GrHistoryPainter extends CustomPainter {
  final List<_GrSample> history;
  final double threshold;
  final double grPeakHold;
  final double range;
  final double lookaheadMs;

  _GrHistoryPainter({
    required this.history,
    required this.threshold,
    this.grPeakHold = 0.0,
    this.range = -60.0,
    this.lookaheadMs = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background gradient ──
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, size.height),
        [const Color(0xFF0D0D12), const Color(0xFF08080C)],
      ),
    );

    // ── Grid ──
    final thinPaint = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    final medPaint = Paint()..color = const Color(0xFF222230)..strokeWidth = 0.5;
    for (var db = -60; db <= 0; db += 6) {
      final y = size.height * (1 - (db + 60) / 60);
      canvas.drawLine(
        Offset(0, y), Offset(size.width, y),
        db % 12 == 0 ? medPaint : thinPaint,
      );
    }

    // 0dB line
    canvas.drawLine(
      Offset(0, 0), Offset(size.width, 0),
      Paint()..color = const Color(0xFF2A2A38)..strokeWidth = 1,
    );

    // ── Threshold line ──
    final thY = size.height * (1 - (threshold + 60) / 60);
    canvas.drawLine(Offset(0, thY), Offset(size.width, thY), Paint()
      ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.35)
      ..strokeWidth = 1);
    // Threshold glow
    canvas.drawLine(Offset(0, thY), Offset(size.width, thY), Paint()
      ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.15)
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

    if (history.length < 2) return;
    final sw = size.width / history.length;
    final startX = size.width - history.length * sw;

    // ── Input level fill (subtle gray gradient) ──
    final inPath = Path()..moveTo(startX, size.height);
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final h = size.height * ((history[i].input + 60) / 60).clamp(0.0, 1.0);
      inPath.lineTo(x, size.height - h);
    }
    inPath.lineTo(startX + history.length * sw, size.height);
    inPath.close();
    canvas.drawPath(inPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height), Offset.zero,
        [
          const Color(0x08808088),
          const Color(0x20808088),
        ],
      ));

    // ── Output level fill (blue gradient) ──
    final outPath = Path()..moveTo(startX, size.height);
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final h = size.height * ((history[i].output + 60) / 60).clamp(0.0, 1.0);
      outPath.lineTo(x, size.height - h);
    }
    outPath.lineTo(startX + history.length * sw, size.height);
    outPath.close();
    canvas.drawPath(outPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height), Offset.zero,
        [
          FabFilterColors.blue.withValues(alpha: 0.05),
          FabFilterColors.blue.withValues(alpha: 0.3),
        ],
      ));

    // ── Output level stroke (thin blue line) ──
    final outLine = Path();
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final h = size.height * ((history[i].output + 60) / 60).clamp(0.0, 1.0);
      final y = size.height - h;
      i == 0 ? outLine.moveTo(x, y) : outLine.lineTo(x, y);
    }
    canvas.drawPath(outLine, Paint()
      ..color = FabFilterColors.blue.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke);

    // ── GR bars from top — gradient bars ──
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final grNorm = (history[i].gr.abs() / 40).clamp(0.0, 1.0);
      if (grNorm < 0.001) continue;
      final grH = size.height * grNorm;
      final barRect = Rect.fromLTWH(x, 0, sw + 0.5, grH);
      canvas.drawRect(barRect, Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, 0), Offset(x, grH),
          [
            FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.5),
            FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.15),
          ],
        ));
    }

    // ── GR edge glow ──
    final grEdge = Path();
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final grH = size.height * (history[i].gr.abs() / 40).clamp(0.0, 1.0);
      i == 0 ? grEdge.moveTo(x, grH) : grEdge.lineTo(x, grH);
    }
    canvas.drawPath(grEdge, Paint()
      ..color = FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    canvas.drawPath(grEdge, Paint()
      ..color = FabFilterProcessorColors.compGainReduction
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke);

    // ── GR Peak Hold line (dashed yellow) ──
    if (grPeakHold.abs() > 0.1) {
      final phY = size.height * (grPeakHold.abs() / 40).clamp(0.0, 1.0);
      final phPaint = Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      // Draw dashed line
      const dashLen = 4.0, gapLen = 3.0;
      var dx = 0.0;
      while (dx < size.width) {
        final end = (dx + dashLen).clamp(0.0, size.width);
        canvas.drawLine(Offset(dx, phY), Offset(end, phY), phPaint);
        dx += dashLen + gapLen;
      }
    }

    // ── Range limit line (if range > -60) ──
    if (range > -59.0) {
      final rangeGr = range.abs();
      final rlY = size.height * (rangeGr / 40).clamp(0.0, 1.0);
      canvas.drawLine(Offset(0, rlY), Offset(size.width, rlY), Paint()
        ..color = FabFilterColors.red.withValues(alpha: 0.4)
        ..strokeWidth = 1);
      // Label
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(color: FabFilterColors.red.withValues(alpha: 0.5), fontSize: 6))
        ..addText('RNG ${range.toStringAsFixed(0)}');
      final para = builder.build()..layout(const ui.ParagraphConstraints(width: 40));
      canvas.drawParagraph(para, Offset(2, rlY + 1));
    }

    // ── Look-ahead window indicator (C5.1) ──
    if (lookaheadMs > 0.1) {
      // lookahead = how many samples ahead the compressor "sees"
      // At 60fps, 200 samples ≈ 3.3s, so 20ms ≈ ~1.2 samples in history
      // Show as a cyan band at the right edge
      final laWidth = (lookaheadMs / 20.0 * 15.0).clamp(3.0, 15.0);
      final laRect = Rect.fromLTRB(
        size.width - laWidth, 0, size.width, size.height,
      );
      canvas.drawRect(laRect, Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.08));
      canvas.drawLine(
        Offset(size.width - laWidth, 0),
        Offset(size.width - laWidth, size.height),
        Paint()
          ..color = FabFilterColors.cyan.withValues(alpha: 0.3)
          ..strokeWidth = 0.8,
      );
      // "LA" label
      final laBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(color: FabFilterColors.cyan.withValues(alpha: 0.5), fontSize: 6))
        ..addText('LA');
      final laPara = laBuilder.build()..layout(const ui.ParagraphConstraints(width: 15));
      canvas.drawParagraph(laPara, Offset(size.width - laWidth + 1, size.height - 10));
    }

    // ── RMS overlay (thin green line) ──
    final rmsLine = Path();
    bool rmsStarted = false;
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final h = size.height * ((history[i].rmsLevel + 60) / 60).clamp(0.0, 1.0);
      final y = size.height - h;
      if (!rmsStarted) { rmsLine.moveTo(x, y); rmsStarted = true; }
      else { rmsLine.lineTo(x, y); }
    }
    if (rmsStarted) {
      canvas.drawPath(rmsLine, Paint()
        ..color = FabFilterColors.green.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GrHistoryPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// KNEE CURVE PAINTER — glass transfer function with animated zone
// ═══════════════════════════════════════════════════════════════════════════

class _KneeCurvePainter extends CustomPainter {
  final double threshold, ratio, knee, currentInput, grAmount, range, mix;

  _KneeCurvePainter({
    required this.threshold, required this.ratio,
    required this.knee, required this.currentInput,
    this.grAmount = 0.0,
    this.range = -60.0,
    this.mix = 100.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const minDb = -60.0, maxDb = 0.0, dbRange = maxDb - minDb;

    // ── Background gradient ──
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, size.height),
        [const Color(0xFF0D0D12), const Color(0xFF08080C)],
      ));

    // ── Grid ──
    final thinPaint = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    final medPaint = Paint()..color = const Color(0xFF222230)..strokeWidth = 0.5;

    for (var i = 1; i < 6; i++) {
      final t = i / 6;
      final x = t * size.width;
      final y = t * size.height;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        i % 2 == 0 ? medPaint : thinPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
        i % 2 == 0 ? medPaint : thinPaint);
    }

    // ── 1:1 diagonal (unity gain) ──
    canvas.drawLine(
      Offset(0, size.height), Offset(size.width, 0),
      Paint()..color = const Color(0xFF2A2A38)..strokeWidth = 0.8,
    );

    // ── Knee region highlight ──
    final halfKnee = knee / 2;
    final kneeStart = threshold - halfKnee;
    final kneeEnd = threshold + halfKnee;

    if (knee > 0.5) {
      final ksX = size.width * ((kneeStart - minDb) / dbRange);
      final keX = size.width * ((kneeEnd - minDb) / dbRange);
      canvas.drawRect(
        Rect.fromLTRB(ksX, 0, keX, size.height),
        Paint()..color = FabFilterProcessorColors.compKnee.withValues(alpha: 0.06),
      );
    }

    // ── Compression zone fill ──
    // Area between 1:1 line and transfer curve (where gain reduction happens)
    final zonePath = Path();
    final curvePath = Path();
    bool zoneStarted = false;

    for (var i = 0; i <= size.width.toInt(); i++) {
      final inDb = minDb + (i / size.width) * dbRange;
      final outDb = _transferFunction(inDb);
      final x = i.toDouble();
      final y = size.height * (1 - (outDb - minDb) / dbRange);

      i == 0 ? curvePath.moveTo(x, y) : curvePath.lineTo(x, y);

      // 1:1 reference Y
      final unityY = size.height * (1 - (inDb - minDb) / dbRange);

      if (outDb < inDb - 0.1) {
        if (!zoneStarted) {
          zonePath.moveTo(x, unityY);
          zoneStarted = true;
        }
        zonePath.lineTo(x, y);
      } else if (zoneStarted) {
        // Close the zone back along 1:1
        zonePath.lineTo(x, unityY);
      }
    }

    if (zoneStarted) {
      // Walk back along 1:1 to close
      final finalX = size.width;
      final finalInDb = maxDb;
      final finalUnityY = size.height * (1 - (finalInDb - minDb) / dbRange);
      zonePath.lineTo(finalX, finalUnityY);

      for (var i = size.width.toInt(); i >= 0; i--) {
        final inDb = minDb + (i / size.width) * dbRange;
        final outDb = _transferFunction(inDb);
        if (outDb < inDb - 0.1) {
          final unityY = size.height * (1 - (inDb - minDb) / dbRange);
          zonePath.lineTo(i.toDouble(), unityY);
        }
      }
      zonePath.close();

      canvas.drawPath(zonePath, Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0), Offset(0, size.height),
          [
            FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.12),
            FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.04),
          ],
        ));
    }

    // ── Transfer curve — glow + core ──
    canvas.drawPath(curvePath, Paint()
      ..color = FabFilterProcessorColors.compAccent.withValues(alpha: 0.3)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));

    canvas.drawPath(curvePath, Paint()
      ..color = FabFilterProcessorColors.compAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);

    // Bright highlight core
    canvas.drawPath(curvePath, Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke);

    // ── Parallel mix curve (C7.1) — shows dry/wet blend when mix < 100% ──
    if (mix < 99.0) {
      final mixNorm = mix / 100.0;
      final mixPath = Path();
      for (var i = 0; i <= size.width.toInt(); i++) {
        final inDb = minDb + (i / size.width) * dbRange;
        final wetDb = _transferFunction(inDb);
        // Parallel mix: blend dry (1:1) and wet (compressed) in dB domain
        final mixDb = inDb * (1.0 - mixNorm) + wetDb * mixNorm;
        final x = i.toDouble();
        final y = size.height * (1 - (mixDb - minDb) / dbRange);
        i == 0 ? mixPath.moveTo(x, y) : mixPath.lineTo(x, y);
      }
      // Dry (1:1) line is already drawn as diagonal
      // Draw the mixed curve with dashed style
      canvas.drawPath(mixPath, Paint()
        ..color = FabFilterColors.blue.withValues(alpha: 0.3)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawPath(mixPath, Paint()
        ..color = FabFilterColors.blue.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
      // Mix % label near the mixed curve
      final mixLabelDb = threshold + 10;
      final mixLabelX = size.width * ((mixLabelDb - minDb) / dbRange);
      final mixWet = _transferFunction(mixLabelDb);
      final mixBlend = mixLabelDb * (1 - mixNorm) + mixWet * mixNorm;
      final mixLabelY = size.height * (1 - (mixBlend - minDb) / dbRange);
      final mlBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(
          color: FabFilterColors.blue.withValues(alpha: 0.6), fontSize: 7,
        ))
        ..addText('MIX ${mix.toStringAsFixed(0)}%');
      final mlPara = mlBuilder.build()..layout(const ui.ParagraphConstraints(width: 40));
      canvas.drawParagraph(mlPara, Offset(mixLabelX + 4, mixLabelY - 10));
    }

    // ── Ratio slope line (above threshold) ──
    // Shows the slope of compression: 1:ratio
    if (ratio > 1.01) {
      final slopeStartDb = threshold + (knee / 2);
      final slopeStartX = size.width * ((slopeStartDb - minDb) / dbRange);
      final slopeStartOutDb = _transferFunction(slopeStartDb);
      final slopeStartY = size.height * (1 - (slopeStartOutDb - minDb) / dbRange);

      // Extend slope line to edge of display
      final slopeEndDb = maxDb;
      final slopeEndX = size.width * ((slopeEndDb - minDb) / dbRange);
      final slopeEndOutDb = _transferFunction(slopeEndDb);
      final slopeEndY = size.height * (1 - (slopeEndOutDb - minDb) / dbRange);

      // Dashed slope indicator
      final slopePaint = Paint()
        ..color = FabFilterProcessorColors.compAccent.withValues(alpha: 0.2)
        ..strokeWidth = 0.8;
      const dash = 3.0, gap = 2.0;
      final dx = slopeEndX - slopeStartX;
      final dy = slopeEndY - slopeStartY;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 1) {
        final ux = dx / len, uy = dy / len;
        var d = 0.0;
        while (d < len) {
          final end = math.min(d + dash, len);
          canvas.drawLine(
            Offset(slopeStartX + ux * d, slopeStartY + uy * d),
            Offset(slopeStartX + ux * end, slopeStartY + uy * end),
            slopePaint,
          );
          d += dash + gap;
        }
      }

      // Ratio label near slope
      final ratioLabel = '1:${ratio.toStringAsFixed(ratio >= 10 ? 0 : 1)}';
      final rBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(
          color: FabFilterProcessorColors.compAccent.withValues(alpha: 0.4),
          fontSize: 7,
        ))
        ..addText(ratioLabel);
      final rPara = rBuilder.build()..layout(const ui.ParagraphConstraints(width: 30));
      final midX = (slopeStartX + slopeEndX) / 2;
      final midY = (slopeStartY + slopeEndY) / 2;
      canvas.drawParagraph(rPara, Offset(midX + 4, midY - 4));
    }

    // ── Range limit line (horizontal) ──
    if (range > -59.0) {
      // Range limits max GR — show as horizontal line on output axis
      // At any input, output can't go below input + range (range is negative)
      final rangeOutDb = threshold + range; // approximate output floor
      if (rangeOutDb > minDb) {
        final rlY = size.height * (1 - (rangeOutDb - minDb) / dbRange);
        canvas.drawLine(Offset(0, rlY), Offset(size.width, rlY), Paint()
          ..color = FabFilterColors.red.withValues(alpha: 0.3)
          ..strokeWidth = 1);
        // Glow
        canvas.drawLine(Offset(0, rlY), Offset(size.width, rlY), Paint()
          ..color = FabFilterColors.red.withValues(alpha: 0.1)
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      }
    }

    // ── Threshold marker ──
    final thX = size.width * ((threshold - minDb) / dbRange);
    // Dashed-style: subtle vertical line
    canvas.drawLine(Offset(thX, 0), Offset(thX, size.height), Paint()
      ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.25)
      ..strokeWidth = 1);
    // Glow at intersection
    final thOutDb = _transferFunction(threshold);
    final thY = size.height * (1 - (thOutDb - minDb) / dbRange);
    canvas.drawCircle(Offset(thX, thY), 6, Paint()
      ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // ── Current input dot ──
    if (currentInput > minDb) {
      final inX = size.width * ((currentInput - minDb) / dbRange);
      final outDb = _transferFunction(currentInput);
      final outY = size.height * (1 - (outDb - minDb) / dbRange);

      // Crosshair guides
      final guidePaint = Paint()
        ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.2)
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(inX, outY), Offset(inX, size.height), guidePaint);
      canvas.drawLine(Offset(inX, outY), Offset(0, outY), guidePaint);

      // Outer glow
      canvas.drawCircle(Offset(inX, outY), 8, Paint()
        ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

      // Glass dot with radial gradient
      canvas.drawCircle(Offset(inX, outY), 5, Paint()
        ..shader = ui.Gradient.radial(
          Offset(inX - 1, outY - 1), 5,
          [
            Colors.white.withValues(alpha: 0.5),
            FabFilterProcessorColors.compThreshold,
            FabFilterProcessorColors.compThreshold.withValues(alpha: 0.6),
          ],
          [0.0, 0.5, 1.0],
        ));

      // Highlight dot
      canvas.drawCircle(
        Offset(inX - 1.5, outY - 1.5), 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }

    // ── dB labels ──
    final labelStyle = ui.TextStyle(
      color: const Color(0xFF505060),
      fontSize: 7,
    );
    for (var db in [-48, -36, -24, -12, 0]) {
      final x = size.width * ((db - minDb) / dbRange);
      _drawText(canvas, '${db}', Offset(x + 2, size.height - 10), labelStyle);
    }
  }

  double _transferFunction(double inDb) {
    final halfKnee = knee / 2;
    final kneeStart = threshold - halfKnee;
    final kneeEnd = threshold + halfKnee;

    double outDb;
    if (inDb < kneeStart) {
      outDb = inDb;
    } else if (inDb > kneeEnd) {
      outDb = threshold + (inDb - threshold) / ratio;
    } else if (knee > 1e-6) {
      // Quadratic knee interpolation (Pro-C 2 style)
      final x = inDb - kneeStart;
      final slope = 1.0 - 1.0 / ratio;
      outDb = inDb - (slope * x * x) / (2.0 * knee);
    } else {
      // Hard knee (knee ≈ 0): sharp transition at threshold
      outDb = threshold + (inDb - threshold) / ratio;
    }

    // Apply range limit (max GR clamp)
    if (range > -59.0) {
      final gr = inDb - outDb;
      if (gr > range.abs()) {
        outDb = inDb - range.abs();
      }
    }
    return outDb;
  }

  void _drawText(Canvas canvas, String text, Offset pos, ui.TextStyle style) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
      ..pushStyle(style)
      ..addText(text);
    final para = builder.build()..layout(const ui.ParagraphConstraints(width: 30));
    canvas.drawParagraph(para, pos);
  }

  @override
  bool shouldRepaint(covariant _KneeCurvePainter old) =>
      old.threshold != threshold || old.ratio != ratio ||
      old.knee != knee || old.currentInput != currentInput ||
      old.grAmount != grAmount || old.range != range || old.mix != mix;
}

// ═══════════════════════════════════════════════════════════════════════════
// SC FILTER RESPONSE PAINTER — sidechain HP/LP/Mid frequency curve overlay
// ═══════════════════════════════════════════════════════════════════════════

class _ScFilterResponsePainter extends CustomPainter {
  final double hpFreq, lpFreq, midFreq, midGain;
  final bool showNodes;

  _ScFilterResponsePainter({
    required this.hpFreq, required this.lpFreq,
    required this.midFreq, required this.midGain,
    this.showNodes = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const minF = 20.0, maxF = 20000.0;
    final logMin = math.log(minF), logMax = math.log(maxF);
    final logRange = logMax - logMin;

    // Compute composite SC filter response across frequency
    const nPoints = 128;
    final path = Path();
    for (var i = 0; i < nPoints; i++) {
      final t = i / (nPoints - 1);
      final freq = math.exp(logMin + t * logRange);
      final x = t * size.width;

      // HP response (2nd order, 12dB/oct)
      final hpRatio = freq / hpFreq;
      final hpMag = hpRatio * hpRatio / math.sqrt(1 + hpRatio * hpRatio * hpRatio * hpRatio);
      final hpDb = 20 * math.log(hpMag.clamp(1e-6, 10.0)) / math.ln10;

      // LP response (2nd order, 12dB/oct)
      final lpRatio = freq / lpFreq;
      final lpMag = 1.0 / math.sqrt(1 + lpRatio * lpRatio * lpRatio * lpRatio);
      final lpDb = 20 * math.log(lpMag.clamp(1e-6, 10.0)) / math.ln10;

      // Mid peaking EQ response (approximate bell)
      double midDb = 0.0;
      if (midGain.abs() > 0.1) {
        final relFreq = math.log(freq / midFreq);
        final q = 1.0; // Q=1 as in DSP
        final bandwidth = 1.0 / q;
        final bellShape = math.exp(-0.5 * (relFreq / bandwidth) * (relFreq / bandwidth));
        midDb = midGain * bellShape;
      }

      final totalDb = (hpDb + lpDb + midDb).clamp(-24.0, 12.0);
      // Map dB to Y: center = 0dB at mid-height, ±24dB range
      final y = size.height * (0.5 - totalDb / 48.0);

      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    // Glow
    canvas.drawPath(path, Paint()
      ..color = FabFilterColors.purple.withValues(alpha: 0.2)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

    // Core line
    canvas.drawPath(path, Paint()
      ..color = FabFilterColors.purple.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke);

    // SC label
    final scBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
      ..pushStyle(ui.TextStyle(
        color: FabFilterColors.purple.withValues(alpha: 0.6),
        fontSize: 7, fontWeight: ui.FontWeight.bold,
      ))
      ..addText('SC');
    final scPara = scBuilder.build()..layout(const ui.ParagraphConstraints(width: 20));
    canvas.drawParagraph(scPara, Offset(size.width - 16, 2));

    // SC EQ node indicators (C2.3) — dots at HP, LP, Mid positions
    if (showNodes) {
      final nodeColor = FabFilterColors.purple;
      // HP node
      final hpT = (math.log(hpFreq) - logMin) / logRange;
      final hpX = hpT * size.width;
      canvas.drawCircle(Offset(hpX, size.height * 0.5), 4, Paint()
        ..color = nodeColor.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(Offset(hpX, size.height * 0.5), 3, Paint()
        ..color = nodeColor.withValues(alpha: 0.6));
      canvas.drawCircle(Offset(hpX, size.height * 0.5 - 1), 1, Paint()
        ..color = Colors.white.withValues(alpha: 0.3));

      // LP node
      final lpT = (math.log(lpFreq) - logMin) / logRange;
      final lpX = lpT * size.width;
      canvas.drawCircle(Offset(lpX, size.height * 0.5), 4, Paint()
        ..color = nodeColor.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(Offset(lpX, size.height * 0.5), 3, Paint()
        ..color = nodeColor.withValues(alpha: 0.6));
      canvas.drawCircle(Offset(lpX, size.height * 0.5 - 1), 1, Paint()
        ..color = Colors.white.withValues(alpha: 0.3));

      // Mid EQ node (if active)
      if (midGain.abs() > 0.1) {
        final midT = (math.log(midFreq) - logMin) / logRange;
        final midX = midT * size.width;
        // Position node at the gain level on the curve
        final midY = size.height * (0.5 - midGain / 48.0);
        canvas.drawCircle(Offset(midX, midY), 5, Paint()
          ..color = nodeColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        canvas.drawCircle(Offset(midX, midY), 3.5, Paint()
          ..color = FabFilterColors.yellow.withValues(alpha: 0.7));
        canvas.drawCircle(Offset(midX, midY - 1), 1.2, Paint()
          ..color = Colors.white.withValues(alpha: 0.3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScFilterResponsePainter old) =>
      old.hpFreq != hpFreq || old.lpFreq != lpFreq ||
      old.midFreq != midFreq || old.midGain != midGain ||
      old.showNodes != showNodes;
}

// ═══════════════════════════════════════════════════════════════════════════
// SEGMENTED GR METER — Pro-C 2 style LED segments
// ═══════════════════════════════════════════════════════════════════════════

class _SegmentedGrPainter extends CustomPainter {
  final double grDb;
  final double peakHold;

  _SegmentedGrPainter({required this.grDb, this.peakHold = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    // Segments: -1, -2, -3, -6, -10, -20 dB
    const segments = [-1.0, -2.0, -3.0, -6.0, -10.0, -20.0];
    final segH = size.height / segments.length;
    final gap = 1.0;

    for (var i = 0; i < segments.length; i++) {
      final segDb = segments[i];
      final y = i * segH + gap / 2;
      final h = segH - gap;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1, y, size.width - 2, h),
        const Radius.circular(1),
      );

      final active = grDb <= segDb;
      final peakActive = peakHold <= segDb;

      if (active) {
        // Color by severity: green → yellow → orange → red
        final severity = i / (segments.length - 1);
        final color = Color.lerp(
          FabFilterColors.green,
          FabFilterProcessorColors.compGainReduction,
          severity,
        )!;
        canvas.drawRRect(rect, Paint()..color = color);
        // Glow
        canvas.drawRRect(rect, Paint()
          ..color = color.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      } else if (peakActive) {
        // Peak hold: dim outline
        canvas.drawRRect(rect, Paint()
          ..color = FabFilterColors.yellow.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
      } else {
        // Inactive segment
        canvas.drawRRect(rect, Paint()
          ..color = const Color(0xFF1A1A22));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedGrPainter old) =>
      old.grDb != grDb || old.peakHold != peakHold;
}
