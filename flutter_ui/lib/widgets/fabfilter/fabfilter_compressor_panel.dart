/// FF-C Compressor Panel — Pro-C 2 Ultimate
///
/// Professional dynamics processor:
/// - Glass transfer curve with animated knee region
/// - Scrolling GR history with gradient waveforms
/// - 14 compression styles with smooth switching
/// - Character saturation (Tube / Diode / Bright)
/// - Sidechain EQ with HP/LP/Mid controls
/// - Real-time I/O + GR metering at 60fps

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

      _grHistory.add(_GrSample(_inputLevel, _outputLevel, _grCurrent));
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
    return wrapWithBypassOverlay(Container(
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
                // Knee badge (bottom-left)
                if (_knee > 0.5)
                  Positioned(
                    left: 4, bottom: 3,
                    child: Text(
                      'K ${_knee.toStringAsFixed(0)}dB',
                      style: TextStyle(
                        color: FabFilterProcessorColors.compKnee.withValues(alpha: 0.6),
                        fontSize: 7, fontWeight: FontWeight.bold,
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
      width: 44,
      child: Row(
        children: [
          _buildVerticalMeter('IN', _inputLevel, FabFilterColors.textSecondary),
          const SizedBox(width: 2),
          _buildVerticalMeter('OUT', _outputLevel, FabFilterColors.blue),
          const SizedBox(width: 2),
          _buildVerticalMeter('GR', _grCurrent,
            FabFilterProcessorColors.compGainReduction, fromTop: true),
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
      ],
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

  _GrHistoryPainter({required this.history, required this.threshold});

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
  }

  @override
  bool shouldRepaint(covariant _GrHistoryPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// KNEE CURVE PAINTER — glass transfer function with animated zone
// ═══════════════════════════════════════════════════════════════════════════

class _KneeCurvePainter extends CustomPainter {
  final double threshold, ratio, knee, currentInput, grAmount;

  _KneeCurvePainter({
    required this.threshold, required this.ratio,
    required this.knee, required this.currentInput,
    this.grAmount = 0.0,
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

    if (inDb < kneeStart) {
      return inDb;
    } else if (inDb > kneeEnd) {
      return threshold + (inDb - threshold) / ratio;
    } else {
      final kp = (inDb - kneeStart) / knee;
      final ca = 1 + (1 / ratio - 1) * kp * kp;
      return kneeStart + (inDb - kneeStart) * (1 + ca) / 2;
    }
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
      old.grAmount != grAmount;
}
