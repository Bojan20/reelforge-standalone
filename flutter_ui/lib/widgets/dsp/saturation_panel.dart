/// Saturation Panel — FabFilter Saturn 2 Style
///
/// Professional multi-mode saturation with knob-based interface:
/// - Saturation curve display with real-time input/output visualization
/// - 6 saturation type chips (Tape, Tube, Transistor, Soft Clip, Hard Clip, Foldback)
/// - Rotary knobs for all parameters (NO sliders)
/// - Vertical IN/OUT metering
/// - Compact options column (Oversampling, M/S, Stereo Link)
///
/// SaturatorWrapper param layout (10 params):
///   0: Drive (-24..+40 dB)      5: TapeBias (0..100%)
///   1: Type (0-5 enum)          6: Oversampling (0-3: X1/X2/X4/X8)
///   2: Tone (-100..+100)        7: InputTrim (-12..+12 dB)
///   3: Mix (0..100%)            8: MSMode (0/1)
///   4: Output (-24..+24 dB)     9: StereoLink (0/1)
///
/// Meters (4): InputPeakL(0), InputPeakR(1), OutputPeakL(2), OutputPeakR(3)

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../fabfilter/fabfilter_theme.dart';
import '../fabfilter/fabfilter_knob.dart';
import '../fabfilter/fabfilter_panel_base.dart';
import '../fabfilter/fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

/// Saturation type (matches SaturatorWrapper param index 1)
enum SaturationType {
  tape('Tape', 'Warm analog tape saturation', FabFilterColors.orange, Icons.album),
  tube('Tube', 'Even harmonics, creamy warmth', FabFilterColors.green, Icons.local_fire_department),
  transistor('Transistor', 'Odd harmonics, aggressive', FabFilterColors.cyan, Icons.electrical_services),
  softClip('Soft Clip', 'Clean soft limiting', FabFilterColors.yellow, Icons.blur_on),
  hardClip('Hard Clip', 'Digital-style clipping', FabFilterColors.red, Icons.flash_on),
  foldback('Foldback', 'Creative foldback distortion', FabFilterColors.pink, Icons.waves);

  final String label;
  final String description;
  final Color color;
  final IconData icon;
  const SaturationType(this.label, this.description, this.color, this.icon);

  static SaturationType fromIndex(int idx) {
    if (idx >= 0 && idx < values.length) return values[idx];
    return tape;
  }
}

/// Oversampling mode (matches SaturatorWrapper param index 6)
enum OversamplingMode {
  x1('1x', 'No oversampling'),
  x2('2x', '2x oversampling'),
  x4('4x', '4x oversampling'),
  x8('8x', '8x oversampling');

  final String label;
  final String description;
  const OversamplingMode(this.label, this.description);

  static OversamplingMode fromIndex(int idx) {
    if (idx >= 0 && idx < values.length) return values[idx];
    return x1;
  }
}

/// A/B comparison snapshot for saturation parameters
class SaturationSnapshot implements DspParameterSnapshot {
  final double drive;
  final SaturationType type;
  final double tone;
  final double mix;
  final double output;
  final double tapeBias;
  final OversamplingMode oversampling;
  final double inputTrim;
  final bool msMode;
  final bool stereoLink;

  const SaturationSnapshot({
    required this.drive,
    required this.type,
    required this.tone,
    required this.mix,
    required this.output,
    required this.tapeBias,
    required this.oversampling,
    required this.inputTrim,
    required this.msMode,
    required this.stereoLink,
  });

  @override
  SaturationSnapshot copy() => SaturationSnapshot(
    drive: drive,
    type: type,
    tone: tone,
    mix: mix,
    output: output,
    tapeBias: tapeBias,
    oversampling: oversampling,
    inputTrim: inputTrim,
    msMode: msMode,
    stereoLink: stereoLink,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! SaturationSnapshot) return false;
    return drive == other.drive &&
        type == other.type &&
        tone == other.tone &&
        mix == other.mix &&
        output == other.output &&
        tapeBias == other.tapeBias &&
        oversampling == other.oversampling &&
        inputTrim == other.inputTrim &&
        msMode == other.msMode &&
        stereoLink == other.stereoLink;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class SaturationPanel extends FabFilterPanelBase {
  const SaturationPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-SAT',
          icon: Icons.whatshot,
          accentColor: FabFilterColors.orange,
          nodeType: DspNodeType.saturation,
        );

  @override
  State<SaturationPanel> createState() => _SaturationPanelState();
}

class _SaturationPanelState extends State<SaturationPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  final _ffi = NativeFFI.instance;

  // Main parameters (match SaturatorWrapper indices 0-9)
  double _drive = 0.0;            // 0: dB (-24..+40)
  SaturationType _type = SaturationType.tape;  // 1: enum (0-5)
  double _tone = 0.0;             // 2: (-100..+100)
  double _mix = 100.0;            // 3: (0..100%)
  double _output = 0.0;           // 4: dB (-24..+24)
  double _tapeBias = 50.0;        // 5: (0..100%)
  OversamplingMode _oversampling = OversamplingMode.x1;  // 6: enum (0-3)
  double _inputTrim = 0.0;        // 7: dB (-12..+12)
  bool _msMode = false;           // 8: bool
  bool _stereoLink = true;        // 9: bool

  // Metering
  double _inputPeakL = -60.0;
  double _inputPeakR = -60.0;
  double _outputPeakL = -60.0;
  double _outputPeakR = -60.0;

  // Internal
  String? _nodeId;
  int _slotIndex = -1;
  bool _initialized = false;
  late AnimationController _meterController;

  @override
  int get processorSlotIndex => _slotIndex;

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);
    _meterController.repeat();

    _initializeProcessor();
  }

  @override
  void dispose() {
    _meterController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PROCESSOR INIT (InsertProcessor chain)
  // ─────────────────────────────────────────────────────────────────────────

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);

    // Only connect to existing saturation node — do NOT auto-add
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.saturation) {
        _nodeId = node.id;
        _slotIndex = chain.nodes.indexWhere((n) => n.id == _nodeId);
        _initialized = true;
        _readParamsFromEngine();
        return;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PARAMETER I/O via InsertProcessor chain
  // ─────────────────────────────────────────────────────────────────────────

  void _applyAllParameters() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId;
    final s = _slotIndex;

    _ffi.insertSetParam(t, s, 0, _drive);
    _ffi.insertSetParam(t, s, 1, _type.index.toDouble());
    _ffi.insertSetParam(t, s, 2, _tone);
    _ffi.insertSetParam(t, s, 3, _mix);
    _ffi.insertSetParam(t, s, 4, _output);
    _ffi.insertSetParam(t, s, 5, _tapeBias);
    _ffi.insertSetParam(t, s, 6, _oversampling.index.toDouble());
    _ffi.insertSetParam(t, s, 7, _inputTrim);
    _ffi.insertSetParam(t, s, 8, _msMode ? 1.0 : 0.0);
    _ffi.insertSetParam(t, s, 9, _stereoLink ? 1.0 : 0.0);
  }

  void _readParamsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId;
    final s = _slotIndex;
    setState(() {
      _drive = _ffi.insertGetParam(t, s, 0);
      _type = SaturationType.fromIndex(_ffi.insertGetParam(t, s, 1).round());
      _tone = _ffi.insertGetParam(t, s, 2);
      _mix = _ffi.insertGetParam(t, s, 3);
      _output = _ffi.insertGetParam(t, s, 4);
      _tapeBias = _ffi.insertGetParam(t, s, 5);
      _oversampling = OversamplingMode.fromIndex(_ffi.insertGetParam(t, s, 6).round());
      _inputTrim = _ffi.insertGetParam(t, s, 7);
      _msMode = _ffi.insertGetParam(t, s, 8) > 0.5;
      _stereoLink = _ffi.insertGetParam(t, s, 9) > 0.5;
    });
  }

  void _setParam(int index, double value) {
    if (!_initialized || _slotIndex < 0) return;
    _ffi.insertSetParam(widget.trackId, _slotIndex, index, value);
    widget.onSettingsChanged?.call();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // METERING (4 meters from SaturatorWrapper)
  // ─────────────────────────────────────────────────────────────────────────

  void _updateMeters() {
    if (!_initialized || _slotIndex < 0) return;
    setState(() {
      final inL = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
      final inR = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);
      final outL = _ffi.insertGetMeter(widget.trackId, _slotIndex, 2);
      final outR = _ffi.insertGetMeter(widget.trackId, _slotIndex, 3);
      _inputPeakL = inL > 1e-10 ? 20.0 * math.log(inL) / math.ln10 : -60.0;
      _inputPeakR = inR > 1e-10 ? 20.0 * math.log(inR) / math.ln10 : -60.0;
      _outputPeakL = outL > 1e-10 ? 20.0 * math.log(outL) / math.ln10 : -60.0;
      _outputPeakR = outR > 1e-10 ? 20.0 * math.log(outR) / math.ln10 : -60.0;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A/B SNAPSHOT
  // ─────────────────────────────────────────────────────────────────────────

  SaturationSnapshot? _snapshotA;
  SaturationSnapshot? _snapshotB;

  SaturationSnapshot _createSnapshot() => SaturationSnapshot(
    drive: _drive,
    type: _type,
    tone: _tone,
    mix: _mix,
    output: _output,
    tapeBias: _tapeBias,
    oversampling: _oversampling,
    inputTrim: _inputTrim,
    msMode: _msMode,
    stereoLink: _stereoLink,
  );

  void _restoreSnapshot(SaturationSnapshot snapshot) {
    setState(() {
      _drive = snapshot.drive;
      _type = snapshot.type;
      _tone = snapshot.tone;
      _mix = snapshot.mix;
      _output = snapshot.output;
      _tapeBias = snapshot.tapeBias;
      _oversampling = snapshot.oversampling;
      _inputTrim = snapshot.inputTrim;
      _msMode = snapshot.msMode;
      _stereoLink = snapshot.stereoLink;
    });
    _applyAllParameters();
  }

  @override
  void storeStateA() {
    _snapshotA = _createSnapshot();
    super.storeStateA();
  }

  @override
  void storeStateB() {
    _snapshotB = _createSnapshot();
    super.storeStateB();
  }

  @override
  void restoreStateA() {
    if (_snapshotA != null) _restoreSnapshot(_snapshotA!);
  }

  @override
  void restoreStateB() {
    if (_snapshotB != null) _restoreSnapshot(_snapshotB!);
  }

  @override
  void copyAToB() {
    _snapshotB = _snapshotA?.copy();
    super.copyAToB();
  }

  @override
  void copyBToA() {
    _snapshotA = _snapshotB?.copy();
    super.copyBToA();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHANGE HANDLERS
  // ─────────────────────────────────────────────────────────────────────────

  void _onDriveChanged(double value) {
    setState(() => _drive = value.clamp(-24.0, 40.0));
    _setParam(0, _drive);
  }

  void _onTypeChanged(SaturationType newType) {
    setState(() => _type = newType);
    _setParam(1, newType.index.toDouble());
  }

  void _onToneChanged(double value) {
    setState(() => _tone = value.clamp(-100.0, 100.0));
    _setParam(2, _tone);
  }

  void _onMixChanged(double value) {
    setState(() => _mix = value.clamp(0.0, 100.0));
    _setParam(3, _mix);
  }

  void _onOutputChanged(double value) {
    setState(() => _output = value.clamp(-24.0, 24.0));
    _setParam(4, _output);
  }

  void _onTapeBiasChanged(double value) {
    setState(() => _tapeBias = value.clamp(0.0, 100.0));
    _setParam(5, _tapeBias);
  }

  void _onOversamplingChanged(OversamplingMode mode) {
    setState(() => _oversampling = mode);
    _setParam(6, mode.index.toDouble());
  }

  void _onInputTrimChanged(double value) {
    setState(() => _inputTrim = value.clamp(-12.0, 12.0));
    _setParam(7, _inputTrim);
  }

  void _onMsModeChanged(bool value) {
    setState(() => _msMode = value);
    _setParam(8, value ? 1.0 : 0.0);
  }

  void _onStereoLinkChanged(bool value) {
    setState(() => _stereoLink = value);
    _setParam(9, value ? 1.0 : 0.0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildCompactHeader(),
          // Display: saturation transfer curve
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
                  // Type chips
                  SizedBox(
                    height: 28,
                    child: _buildTypeChips(),
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

  // ─── DISPLAY (Saturation Transfer Curve) ──────────────────────────────

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
                    painter: _SaturationCurvePainter(
                      type: _type,
                      drive: _drive,
                      tone: _tone,
                      inputLevel: math.max(_inputPeakL, _inputPeakR),
                    ),
                  ),
                ),
                // Drive badge (top-right)
                Positioned(
                  right: 4, top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${_drive >= 0 ? '+' : ''}${_drive.toStringAsFixed(1)} dB',
                      style: TextStyle(
                        color: _type.color,
                        fontSize: 9, fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // Type badge (top-left)
                Positioned(
                  left: 4, top: 4,
                  child: Text(
                    _type.label.toUpperCase(),
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
        const SizedBox(width: 4),
        // Character display (right half)
        Expanded(
          child: Container(
            decoration: FabFilterDecorations.display(),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _HarmonicSpectrumPainter(
                      type: _type,
                      drive: _drive,
                      inputLevel: math.max(_inputPeakL, _inputPeakR),
                    ),
                  ),
                ),
                // Mix badge (bottom-right)
                Positioned(
                  right: 4, bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'MIX ${_mix.round()}%  OUT ${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: FabFilterProcessorColors.satAccent,
                        fontSize: 8, fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // Oversampling badge (top-left)
                Positioned(
                  left: 4, top: 4,
                  child: Text(
                    'OS ${_oversampling.label}',
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

  // ─── TYPE CHIPS ────────────────────────────────────────────────────────

  Widget _buildTypeChips() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: SaturationType.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (ctx, i) {
        final t = SaturationType.values[i];
        final active = _type == t;
        return GestureDetector(
          onTap: () => _onTypeChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active
                  ? t.color.withValues(alpha: 0.25)
                  : FabFilterColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? t.color : FabFilterColors.borderMedium,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: 12, color: active ? t.color : FabFilterColors.textTertiary),
                const SizedBox(width: 3),
                Text(t.label, style: TextStyle(
                  color: active ? t.color : FabFilterColors.textSecondary,
                  fontSize: 9, fontWeight: active ? FontWeight.bold : FontWeight.w500,
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── MAIN ROW ─────────────────────────────────────────────────────────

  Widget _buildMainRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT: Meters (In/Out)
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

  // ─── METERS ────────────────────────────────────────────────────────────

  Widget _buildMeters() {
    return SizedBox(
      width: 44,
      child: Row(
        children: [
          _buildVerticalMeter('IN', math.max(_inputPeakL, _inputPeakR), FabFilterColors.green),
          const SizedBox(width: 2),
          _buildVerticalMeter('L', _inputPeakL, FabFilterColors.textTertiary),
          const SizedBox(width: 2),
          _buildVerticalMeter('R', _inputPeakR, FabFilterColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(String label, double dB, Color color) {
    final norm = ((dB + 60) / 60).clamp(0.0, 1.0);
    final meterColor = norm > 0.95 ? FabFilterColors.red
        : norm > 0.75 ? FabFilterColors.orange
        : color;

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
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: norm,
                  child: Container(
                    decoration: BoxDecoration(
                      color: meterColor,
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

  // ─── KNOBS ─────────────────────────────────────────────────────────────

  Widget _buildKnobs() {
    return Column(
      children: [
        // Row 1: Main knobs (Drive, Tone, Mix, Output)
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _knob('DRIVE', (_drive + 24) / 64,
                '${_drive >= 0 ? '+' : ''}${_drive.toStringAsFixed(1)} dB',
                FabFilterProcessorColors.satDrive, (v) {
                  _onDriveChanged(v * 64 - 24);
                }, defaultValue: 24.0 / 64.0),
              _knob('TONE', (_tone + 100) / 200,
                '${_tone >= 0 ? '+' : ''}${_tone.toStringAsFixed(0)}',
                FabFilterColors.cyan, (v) {
                  _onToneChanged(v * 200 - 100);
                }, defaultValue: 0.5),
              _knob('MIX', _mix / 100,
                '${_mix.round()}%',
                FabFilterColors.green, (v) {
                  _onMixChanged(v * 100);
                }, defaultValue: 1.0),
              _knob('OUTPUT', (_output + 24) / 48,
                '${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(1)} dB',
                FabFilterColors.blue, (v) {
                  _onOutputChanged(v * 48 - 24);
                }, defaultValue: 0.5),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Secondary knobs + mini params
        SizedBox(
          height: 24,
          child: Row(
            children: [
              _miniParam('TRIM', (_inputTrim + 12) / 24,
                '${_inputTrim >= 0 ? '+' : ''}${_inputTrim.toStringAsFixed(1)}',
                FabFilterColors.yellow, (v) {
                  _onInputTrimChanged(v * 24 - 12);
                }),
              const SizedBox(width: 4),
              if (_type == SaturationType.tape)
                _miniParam('BIAS', _tapeBias / 100,
                  '${_tapeBias.round()}%',
                  FabFilterProcessorColors.satWarmth, (v) {
                    _onTapeBiasChanged(v * 100);
                  }),
              if (_type == SaturationType.tape)
                const SizedBox(width: 4),
              // Output meters inline
              Expanded(
                child: Row(
                  children: [
                    const Spacer(),
                    _buildInlineMeter('OL', _outputPeakL, FabFilterProcessorColors.satAccent),
                    const SizedBox(width: 3),
                    _buildInlineMeter('OR', _outputPeakR, FabFilterProcessorColors.satAccent),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _knob(String label, double value, String display, Color color,
      ValueChanged<double> onChanged, {double defaultValue = 0.5}) {
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 56,
      defaultValue: defaultValue,
      onChanged: onChanged,
    );
  }

  Widget _miniParam(String label, double value, String display, Color color,
      ValueChanged<double> onChanged) {
    return SizedBox(
      width: 52,
      child: Row(
        children: [
          SizedBox(
            width: 22, child: Text(label,
              style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: color,
                inactiveTrackColor: FabFilterColors.bgVoid,
                thumbColor: color,
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMeter(String label, double dB, Color color) {
    final norm = ((dB + 60) / 60).clamp(0.0, 1.0);
    return SizedBox(
      width: 36,
      child: Row(
        children: [
          Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 6)),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(1),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: norm,
                child: Container(
                  decoration: BoxDecoration(
                    color: norm > 0.9 ? FabFilterColors.red : color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── OPTIONS COLUMN ────────────────────────────────────────────────────

  Widget _buildOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('QUALITY'),
          const SizedBox(height: 2),
          FabEnumSelector(
            label: 'OS',
            value: _oversampling.index,
            options: OversamplingMode.values.map((m) => m.label).toList(),
            onChanged: (i) => _onOversamplingChanged(OversamplingMode.fromIndex(i)),
            color: FabFilterColors.purple,
          ),
          const SizedBox(height: 6),
          FabSectionLabel('PROCESSING'),
          const SizedBox(height: 2),
          FabOptionRow(
            label: 'M/S Mode',
            value: _msMode,
            onChanged: _onMsModeChanged,
            accentColor: FabFilterColors.cyan,
          ),
          const SizedBox(height: 3),
          FabOptionRow(
            label: 'Stereo Link',
            value: _stereoLink,
            onChanged: _onStereoLinkChanged,
            accentColor: FabFilterColors.blue,
          ),
          const Spacer(),
          // Character indicators
          _buildCharacterIndicators(),
        ],
      ),
    );
  }

  Widget _buildCharacterIndicators() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHARACTER', style: FabFilterText.paramLabel.copyWith(fontSize: 7, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Row(
            children: [
              _charDot('Even', _type == SaturationType.tube || _type == SaturationType.tape),
              const SizedBox(width: 4),
              _charDot('Odd', _type == SaturationType.transistor || _type == SaturationType.hardClip),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _charDot('Soft', _type == SaturationType.softClip || _type == SaturationType.tape || _type == SaturationType.tube),
              const SizedBox(width: 4),
              _charDot('Hard', _type == SaturationType.hardClip || _type == SaturationType.foldback),
            ],
          ),
        ],
      ),
    );
  }

  Widget _charDot(String label, bool active) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _type.color : FabFilterColors.bgSurface,
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(
          color: active ? _type.color : FabFilterColors.textDisabled,
          fontSize: 8, fontWeight: FontWeight.bold,
        )),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SATURATION CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _SaturationCurvePainter extends CustomPainter {
  final SaturationType type;
  final double drive;
  final double tone;
  final double inputLevel;

  _SaturationCurvePainter({
    required this.type,
    required this.drive,
    required this.tone,
    required this.inputLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Grid lines
    final gridPaint = Paint()
      ..color = FabFilterColors.borderSubtle.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), gridPaint);
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), gridPaint);
    // Diagonal reference (linear)
    canvas.drawLine(Offset(0, h), Offset(w, 0), gridPaint);

    // Saturation curve
    final driveLinear = math.pow(10, drive / 20).toDouble();
    final path = Path();
    final points = <Offset>[];

    for (int i = 0; i <= 100; i++) {
      final x = i / 100.0;
      final input = x * 2.0 - 1.0; // -1 to 1
      final driven = (input * driveLinear).clamp(-4.0, 4.0);
      final saturated = _applySaturation(driven, type);
      // Map to screen: input -1..1 → x 0..w, output -1..1 → y h..0
      final sx = x * w;
      final sy = h - ((saturated + 1) / 2) * h;
      points.add(Offset(sx, sy.clamp(0, h)));
    }

    if (points.isNotEmpty) {
      path.moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }

    // Fill under curve
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fillPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0), Offset(0, h),
        [type.color.withValues(alpha: 0.15), type.color.withValues(alpha: 0.02)],
      ));

    // Curve stroke
    canvas.drawPath(path, Paint()
      ..color = type.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // Input level indicator
    if (inputLevel > -55) {
      final inputNorm = ((inputLevel + 60) / 60).clamp(0.0, 1.0);
      final ix = inputNorm * w;
      canvas.drawLine(
        Offset(ix, 0), Offset(ix, h),
        Paint()
          ..color = FabFilterColors.textTertiary.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
    }
  }

  double _applySaturation(double x, SaturationType type) {
    return switch (type) {
      SaturationType.tape => (x * 0.9).clamp(-1.0, 1.0) + 0.1 * x / (1 + x.abs()),
      SaturationType.tube => x.sign * (1 - math.exp(-x.abs() * 1.5)),
      SaturationType.transistor => (2 / math.pi) * math.atan(x * 1.5),
      SaturationType.softClip => x / (1 + x.abs()),
      SaturationType.hardClip => x.clamp(-0.8, 0.8),
      SaturationType.foldback => _foldback(x),
    };
  }

  double _foldback(double x) {
    var v = x;
    final threshold = 0.8;
    if (v.abs() > threshold) {
      v = threshold - (v.abs() - threshold);
      v = v.abs() * x.sign;
    }
    return v.clamp(-1.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _SaturationCurvePainter old) {
    return type != old.type || drive != old.drive || tone != old.tone || inputLevel != old.inputLevel;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HARMONIC SPECTRUM PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _HarmonicSpectrumPainter extends CustomPainter {
  final SaturationType type;
  final double drive;
  final double inputLevel;

  _HarmonicSpectrumPainter({
    required this.type,
    required this.drive,
    required this.inputLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, h * i / 4), Offset(w, h * i / 4), gridPaint);
    }

    // Harmonic bars — simulate harmonic content based on saturation type
    final harmonics = _getHarmonicAmplitudes(type, drive);
    final barWidth = w / (harmonics.length * 2 + 1);
    final driveNorm = ((drive + 24) / 64).clamp(0.0, 1.0);

    for (int i = 0; i < harmonics.length; i++) {
      final amplitude = harmonics[i] * driveNorm;
      if (amplitude < 0.01) continue;

      final x = (i * 2 + 1) * barWidth;
      final barH = amplitude * h * 0.85;
      final isEven = (i + 2) % 2 == 0;

      // Color: even harmonics = warm (orange), odd = cool (cyan)
      final barColor = isEven
          ? FabFilterProcessorColors.satWarmth
          : FabFilterColors.cyan;

      // Fill
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, h - barH, barWidth * 0.8, barH),
        const Radius.circular(2),
      );
      canvas.drawRRect(barRect, Paint()
        ..color = barColor.withValues(alpha: 0.6));

      // Glow top
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h - barH, barWidth * 0.8, 3),
          const Radius.circular(2),
        ),
        Paint()..color = barColor,
      );

      // Label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: 'H${i + 2}',
          style: TextStyle(color: barColor.withValues(alpha: 0.7), fontSize: 7),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(canvas, Offset(x, h - barH - 10));
    }

    // Fundamental
    final fundH = h * 0.7;
    final fundRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(barWidth * 0.1, h - fundH, barWidth * 0.8, fundH),
      const Radius.circular(2),
    );
    canvas.drawRRect(fundRect, Paint()
      ..color = FabFilterColors.textSecondary.withValues(alpha: 0.3));
    final fundLabel = TextPainter(
      text: TextSpan(
        text: 'F',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 7),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    fundLabel.paint(canvas, Offset(barWidth * 0.3, h - fundH - 10));
  }

  List<double> _getHarmonicAmplitudes(SaturationType type, double drive) {
    // Returns amplitudes for harmonics H2..H8
    return switch (type) {
      SaturationType.tape =>     [0.7, 0.2, 0.4, 0.1, 0.2, 0.05, 0.1],
      SaturationType.tube =>     [0.9, 0.15, 0.5, 0.08, 0.25, 0.04, 0.1],
      SaturationType.transistor => [0.3, 0.8, 0.15, 0.5, 0.1, 0.3, 0.05],
      SaturationType.softClip => [0.5, 0.4, 0.3, 0.2, 0.15, 0.1, 0.05],
      SaturationType.hardClip => [0.4, 0.7, 0.3, 0.5, 0.2, 0.35, 0.15],
      SaturationType.foldback => [0.6, 0.6, 0.5, 0.5, 0.4, 0.4, 0.3],
    };
  }

  @override
  bool shouldRepaint(covariant _HarmonicSpectrumPainter old) {
    return type != old.type || drive != old.drive || inputLevel != old.inputLevel;
  }
}
