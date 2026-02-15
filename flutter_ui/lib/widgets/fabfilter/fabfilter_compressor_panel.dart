/// FF-C Compressor Panel
///
/// Professional compressor interface:
/// - Animated transfer curve + GR history display
/// - 14 compression style chips
/// - Character mode selector
/// - Sidechain EQ visualization
/// - Real-time gain reduction metering

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
  variMu('Vari', Icons.radio),
  elOp('El-Op', Icons.wb_incandescent);

  final String label;
  final IconData icon;
  const CompressionStyle(this.label, this.icon);

  /// Map to insert chain type (0=VCA, 1=Opto, 2=FET)
  int get engineType => switch (this) {
    clean || classic || mastering || bus || versatile || upward => 0,
    opto || vocal || smooth || variMu || elOp => 1,
    punch || pumping || ttm => 2,
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
  const _GrSample(this.input, this.output, this.gr);
}

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

  @override
  int get processorSlotIndex => _slotIndex;

  // ─── LIFECYCLE ──────────────────────────────────────────────────────

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
    var chain = dsp.getChain(widget.trackId);
    if (!chain.nodes.any((n) => n.type == DspNodeType.compressor)) {
      dsp.addNode(widget.trackId, DspNodeType.compressor);
      chain = dsp.getChain(widget.trackId);
    }
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

  // ─── METERING ───────────────────────────────────────────────────────

  void _updateMeters() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId, s = _slotIndex;

    setState(() {
      try {
        final grL = _ffi.insertGetMeter(t, s, 0);
        final grR = _ffi.insertGetMeter(t, s, 1);
        _grCurrent = (grL + grR) / 2.0;
      } catch (_) { _grCurrent = 0.0; }

      try {
        final peaks = _ffi.getPeakMeters();
        final peakLin = math.max(peaks.$1, peaks.$2);
        _inputLevel = peakLin > 1e-10 ? 20.0 * math.log(peakLin) / math.ln10 : -60.0;
        _outputLevel = _inputLevel + _grCurrent;
      } catch (_) {}

      if (_grCurrent.abs() > _grPeakHold.abs()) _grPeakHold = _grCurrent;

      // Build GR history
      _grHistory.add(_GrSample(_inputLevel, _outputLevel, _grCurrent));
      while (_grHistory.length > _maxHistory) _grHistory.removeAt(0);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildCompactHeader(),
          // Display: transfer curve + GR history
          SizedBox(
            height: 100,
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
                  // Style chips
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
    ));
  }

  // ─── DISPLAY ────────────────────────────────────────────────────────

  Widget _buildDisplay() {
    return Row(
      children: [
        // Transfer curve (left half)
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
                    ),
                  ),
                ),
                // Ratio badge (top-right)
                Positioned(
                  right: 4, top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${_ratio.toStringAsFixed(1)}:1',
                      style: TextStyle(
                        color: FabFilterProcessorColors.compAccent,
                        fontSize: 9, fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // GR history (right half)
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
                    ),
                  ),
                ),
                // GR badge (bottom-right)
                Positioned(
                  right: 4, bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'GR ${_grCurrent.toStringAsFixed(1)} dB  pk ${_grPeakHold.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: FabFilterProcessorColors.compGainReduction,
                        fontSize: 8, fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // Detection badge (top-left)
                Positioned(
                  left: 4, top: 4,
                  child: Text(
                    ['PEAK', 'RMS', 'HYB'][_detection],
                    style: TextStyle(
                      color: FabFilterColors.textTertiary,
                      fontSize: 8, fontWeight: FontWeight.bold,
                    ),
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
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (ctx, i) {
        final s = CompressionStyle.values[i];
        final active = _style == s;
        return GestureDetector(
          onTap: () {
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
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 12, color: active ? FabFilterProcessorColors.compAccent : FabFilterColors.textTertiary),
                const SizedBox(width: 3),
                Text(s.label, style: TextStyle(
                  color: active ? FabFilterProcessorColors.compAccent : FabFilterColors.textSecondary,
                  fontSize: 9, fontWeight: active ? FontWeight.bold : FontWeight.w500,
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCharacterChip() {
    return GestureDetector(
      onTap: () {
        final next = CharacterMode.values[(_character.index + 1) % CharacterMode.values.length];
        setState(() => _character = next);
        _setParam(_P.character, next.index.toDouble());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _character != CharacterMode.off
              ? _character.color.withValues(alpha: 0.2)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _character != CharacterMode.off ? _character.color : FabFilterColors.borderMedium,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_character.icon, size: 12, color: _character.color),
            const SizedBox(width: 3),
            Text(_character.label, style: TextStyle(
              color: _character.color, fontSize: 9, fontWeight: FontWeight.bold,
            )),
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
      width: 44,
      child: Row(
        children: [
          _buildVerticalMeter('IN', _inputLevel, FabFilterColors.textSecondary),
          const SizedBox(width: 2),
          _buildVerticalMeter('OUT', _outputLevel, FabFilterColors.blue),
          const SizedBox(width: 2),
          _buildVerticalMeter('GR', _grCurrent, FabFilterProcessorColors.compGainReduction, fromTop: true),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(String label, double dB, Color color, {bool fromTop = false}) {
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
              child: Align(
                alignment: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: norm,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
              _knob('THRESH', (_threshold + 60) / 60, '${_threshold.toStringAsFixed(0)} dB',
                FabFilterProcessorColors.compThreshold, (v) {
                  setState(() => _threshold = v * 60 - 60);
                  _setParam(_P.threshold, _threshold);
                }),
              _knob('RATIO', (_ratio - 1) / 19, '${_ratio.toStringAsFixed(1)}:1',
                FabFilterProcessorColors.compAccent, (v) {
                  setState(() => _ratio = v * 19 + 1);
                  _setParam(_P.ratio, _ratio);
                }),
              _knob('KNEE', _knee / 24, '${_knee.toStringAsFixed(0)} dB',
                FabFilterColors.blue, (v) {
                  setState(() => _knee = v * 24);
                  _setParam(_P.knee, _knee);
                }),
              _knob('ATT', math.log(_attack / 0.01) / math.log(500 / 0.01),
                _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)}µ' : '${_attack.toStringAsFixed(0)}ms',
                FabFilterColors.cyan, (v) {
                  setState(() => _attack = 0.01 * math.pow(500 / 0.01, v));
                  _setParam(_P.attack, _attack);
                }),
              _knob('REL', math.log(_release / 5) / math.log(5000 / 5),
                _release >= 1000 ? '${(_release / 1000).toStringAsFixed(1)}s' : '${_release.toStringAsFixed(0)}ms',
                FabFilterColors.cyan, (v) {
                  setState(() => _release = (5 * math.pow(5000 / 5, v)).toDouble());
                  _setParam(_P.release, _release);
                }),
              _knob('MIX', _mix / 100, '${_mix.toStringAsFixed(0)}%',
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
        // Row 2: Advanced params + toggles
        SizedBox(
          height: 24,
          child: Row(
            children: [
              _miniParam('LOOK', _lookahead / 20, '${_lookahead.toStringAsFixed(1)}', FabFilterColors.purple, (v) {
                setState(() => _lookahead = v * 20);
                _setParam(_P.lookahead, _lookahead);
              }),
              const SizedBox(width: 4),
              _miniParam('DRV', _drive / 24, '${_drive.toStringAsFixed(0)}', FabFilterProcessorColors.compAccent, (v) {
                setState(() => _drive = v * 24);
                _setParam(_P.drive, _drive);
              }),
              const SizedBox(width: 4),
              _miniParam('RNG', (_range + 60) / 60, '${_range.toStringAsFixed(0)}', FabFilterColors.cyan, (v) {
                setState(() => _range = v * 60 - 60);
                _setParam(_P.range, _range);
              }),
              const SizedBox(width: 6),
              // Detection mode
              ..._detectionButtons(),
              const SizedBox(width: 6),
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

  Widget _knob(String label, double value, String display, Color color, ValueChanged<double> onChanged) {
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 48,
      onChanged: onChanged,
    );
  }

  Widget _miniParam(String label, double value, String display, Color color, ValueChanged<double> onChanged) {
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
        child: _tinyBtn(labels[i], _detection == i, FabFilterColors.cyan, () {
          setState(() => _detection = i);
          _setParam(_P.detection, i.toDouble());
        }),
      ),
    ));
  }

  Widget _toggle(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 20, padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : FabFilterColors.borderMedium),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: active ? color : FabFilterColors.textTertiary,
          fontSize: 8, fontWeight: FontWeight.bold,
        ))),
      ),
    );
  }

  Widget _tinyBtn(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 18,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : FabFilterColors.borderMedium),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: active ? color : FabFilterColors.textTertiary,
          fontSize: 8, fontWeight: FontWeight.bold,
        ))),
      ),
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
            onChanged: (v) {
              setState(() => _scHpf = (20 * math.pow(500 / 20, v)).toDouble());
              _setParam(_P.scHpf, _scHpf);
            }),
          const SizedBox(height: 2),
          FabMiniSlider(label: 'LP', labelWidth: 18,
            value: (math.log(_scLpf / 1000) / math.log(20000 / 1000)).clamp(0.0, 1.0),
            display: '${(_scLpf / 1000).toStringAsFixed(0)}k',
            onChanged: (v) {
              setState(() => _scLpf = (1000 * math.pow(20000 / 1000, v)).toDouble());
              _setParam(_P.scLpf, _scLpf);
            }),
          const SizedBox(height: 2),
          FabMiniSlider(label: 'MF', labelWidth: 18,
            value: (math.log(_scMidFreq / 200) / math.log(5000 / 200)).clamp(0.0, 1.0),
            display: '${_scMidFreq.toStringAsFixed(0)}',
            onChanged: (v) {
              setState(() => _scMidFreq = (200 * math.pow(5000 / 200, v)).toDouble());
              _setParam(_P.scMidFreq, _scMidFreq);
            }),
          const SizedBox(height: 2),
          FabMiniSlider(label: 'MG', labelWidth: 18,
            value: ((_scMidGain + 12) / 24).clamp(0.0, 1.0),
            display: '${_scMidGain >= 0 ? '+' : ''}${_scMidGain.toStringAsFixed(0)}',
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
            onChanged: (v) {
              setState(() => _hostBpm = v * 280 + 20);
              _setParam(_P.hostBpm, _hostBpm);
            }),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GR HISTORY PAINTER (scrolling waveform)
// ═══════════════════════════════════════════════════════════════════════════

class _GrHistoryPainter extends CustomPainter {
  final List<_GrSample> history;
  final double threshold;

  _GrHistoryPainter({required this.history, required this.threshold});

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, size.height),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      ),
    );

    // Grid
    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;
    for (var db = -60; db <= 0; db += 12) {
      final y = size.height * (1 - (db + 60) / 60);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Threshold line
    final thY = size.height * (1 - (threshold + 60) / 60);
    canvas.drawLine(Offset(0, thY), Offset(size.width, thY), Paint()
      ..color = FabFilterProcessorColors.compThreshold
      ..strokeWidth = 1);

    if (history.length < 2) return;
    final sw = size.width / history.length;
    final startX = size.width - history.length * sw;

    // Input level (gray fill)
    final inPath = Path()..moveTo(startX, size.height);
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final h = size.height * ((history[i].input + 60) / 60).clamp(0.0, 1.0);
      inPath.lineTo(x, size.height - h);
    }
    inPath.lineTo(startX + history.length * sw, size.height);
    inPath.close();
    canvas.drawPath(inPath, Paint()..color = FabFilterColors.textMuted.withValues(alpha: 0.3));

    // Output level (blue fill)
    final outPath = Path()..moveTo(startX, size.height);
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final h = size.height * ((history[i].output + 60) / 60).clamp(0.0, 1.0);
      outPath.lineTo(x, size.height - h);
    }
    outPath.lineTo(startX + history.length * sw, size.height);
    outPath.close();
    canvas.drawPath(outPath, Paint()..color = FabFilterColors.blue.withValues(alpha: 0.5));

    // GR bars from top
    for (var i = 0; i < history.length; i++) {
      final x = startX + i * sw;
      final grH = size.height * (history[i].gr.abs() / 40).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(x, 0, sw + 1, grH),
        Paint()..color = FabFilterProcessorColors.compGainReduction.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrHistoryPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// KNEE CURVE PAINTER (transfer function)
// ═══════════════════════════════════════════════════════════════════════════

class _KneeCurvePainter extends CustomPainter {
  final double threshold, ratio, knee, currentInput;

  _KneeCurvePainter({
    required this.threshold, required this.ratio,
    required this.knee, required this.currentInput,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, size.height),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      ));

    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;

    // 1:1 diagonal
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), gridPaint);

    // Grid
    final gs = size.width / 4;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(i * gs, 0), Offset(i * gs, size.height), gridPaint);
      canvas.drawLine(Offset(0, i * gs), Offset(size.width, i * gs), gridPaint);
    }

    // Transfer curve
    const minDb = -60.0, maxDb = 0.0, dbRange = maxDb - minDb;
    final curvePath = Path();
    final halfKnee = knee / 2;
    final kneeStart = threshold - halfKnee;
    final kneeEnd = threshold + halfKnee;

    for (var i = 0; i <= size.width.toInt(); i++) {
      final inDb = minDb + (i / size.width) * dbRange;
      double outDb;
      if (inDb < kneeStart) {
        outDb = inDb;
      } else if (inDb > kneeEnd) {
        outDb = threshold + (inDb - threshold) / ratio;
      } else {
        final kp = (inDb - kneeStart) / knee;
        final ca = 1 + (1 / ratio - 1) * kp * kp;
        outDb = kneeStart + (inDb - kneeStart) * (1 + ca) / 2;
      }
      final x = i.toDouble();
      final y = size.height * (1 - (outDb - minDb) / dbRange);
      i == 0 ? curvePath.moveTo(x, y) : curvePath.lineTo(x, y);
    }

    canvas.drawPath(curvePath, Paint()
      ..color = FabFilterProcessorColors.compAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke);

    // Current input dot
    if (currentInput > minDb) {
      final inX = size.width * ((currentInput - minDb) / dbRange);
      double outDb;
      if (currentInput < kneeStart) {
        outDb = currentInput;
      } else if (currentInput > kneeEnd) {
        outDb = threshold + (currentInput - threshold) / ratio;
      } else {
        final kp = (currentInput - kneeStart) / knee;
        final ca = 1 + (1 / ratio - 1) * kp * kp;
        outDb = kneeStart + (currentInput - kneeStart) * (1 + ca) / 2;
      }
      final outY = size.height * (1 - (outDb - minDb) / dbRange);
      canvas.drawCircle(Offset(inX, outY), 4, Paint()..color = FabFilterProcessorColors.compThreshold);
      final lp = Paint()
        ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(inX, outY), Offset(inX, size.height), lp);
      canvas.drawLine(Offset(inX, outY), Offset(0, outY), lp);
    }

    // Threshold marker
    final thX = size.width * ((threshold - minDb) / dbRange);
    canvas.drawLine(Offset(thX, 0), Offset(thX, size.height), Paint()
      ..color = FabFilterProcessorColors.compThreshold.withValues(alpha: 0.4)
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _KneeCurvePainter old) =>
      old.threshold != threshold || old.ratio != ratio ||
      old.knee != knee || old.currentInput != currentInput;
}
