/// Saturation Panel — Saturn 2 Class
///
/// Multi-mode saturation processor wired to InsertProcessor chain:
/// - Tape: Warm, compressed, analog warmth
/// - Tube: Even harmonics, creamy distortion
/// - Transistor: Odd harmonics, aggressive edge
/// - Soft Clip: Clean limiting
/// - Hard Clip: Digital clipping
/// - Foldback: Creative foldback distortion
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
import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../fabfilter/fabfilter_theme.dart';
import '../fabfilter/fabfilter_panel_base.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

/// Saturation type (matches SaturatorWrapper param index 1)
enum SaturationType {
  tape('Tape', 'Warm analog tape saturation', FabFilterColors.orange),
  tube('Tube', 'Even harmonics, creamy warmth', FabFilterColors.green),
  transistor('Transistor', 'Odd harmonics, aggressive', FabFilterColors.cyan),
  softClip('Soft Clip', 'Clean soft limiting', FabFilterColors.yellow),
  hardClip('Hard Clip', 'Digital-style clipping', FabFilterColors.red),
  foldback('Foldback', 'Creative foldback distortion', FabFilterColors.pink);

  final String label;
  final String description;
  final Color color;
  const SaturationType(this.label, this.description, this.color);

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
    return wrapWithBypassOverlay(
      Container(
        decoration: FabFilterDecorations.panel(),
        child: Column(
          children: [
            buildHeader(),
            const Divider(height: 1, color: FabFilterColors.bgDeep),
            _buildTypeSelector(),
            const Divider(height: 1, color: FabFilterColors.bgDeep),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildDriveSection(),
                    const SizedBox(height: 16),
                    _buildToneSection(),
                    const SizedBox(height: 16),
                    _buildMixSection(),
                    const SizedBox(height: 16),
                    _buildOutputSection(),
                    if (_type == SaturationType.tape) ...[
                      const SizedBox(height: 16),
                      _buildTapeBiasSection(),
                    ],
                    const SizedBox(height: 16),
                    _buildInputTrimSection(),
                    const SizedBox(height: 16),
                    _buildAdvancedSection(),
                    const SizedBox(height: 16),
                    _buildMeterSection(),
                    const SizedBox(height: 12),
                    _buildCharacterDisplay(),
                  ],
                ),
              ),
            ),
            buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI SECTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: SaturationType.values.take(3).map((type) {
              return _buildTypeButton(type);
            }).toList(),
          ),
          const SizedBox(height: 4),
          Row(
            children: SaturationType.values.skip(3).map((type) {
              return _buildTypeButton(type);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(SaturationType type) {
    final isSelected = type == _type;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: GestureDetector(
          onTap: () => _onTypeChanged(type),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? type.color.withValues(alpha: 0.3)
                  : FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? type.color : FabFilterColors.bgSurface,
              ),
            ),
            child: Text(
              type.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? type.color : FabFilterColors.bgHover,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriveSection() {
    return buildSliderRow(
      'DRIVE',
      _drive,
      -24.0,
      40.0,
      '${_drive >= 0 ? '+' : ''}${_drive.toStringAsFixed(1)} dB',
      _onDriveChanged,
      color: _type.color,
    );
  }

  Widget _buildToneSection() {
    return buildSliderRow(
      'TONE',
      _tone,
      -100.0,
      100.0,
      '${_tone >= 0 ? '+' : ''}${_tone.toStringAsFixed(0)}',
      _onToneChanged,
      color: FabFilterColors.cyan,
    );
  }

  Widget _buildMixSection() {
    return buildSliderRow(
      'MIX',
      _mix,
      0.0,
      100.0,
      '${_mix.round()}%',
      (v) => _onMixChanged(v),
      color: FabFilterColors.green,
    );
  }

  Widget _buildOutputSection() {
    return buildSliderRow(
      'OUTPUT',
      _output,
      -24.0,
      24.0,
      '${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(1)} dB',
      _onOutputChanged,
      color: FabFilterColors.blue,
    );
  }

  Widget _buildTapeBiasSection() {
    return buildSliderRow(
      'TAPE BIAS',
      _tapeBias,
      0.0,
      100.0,
      '${_tapeBias.round()}%',
      _onTapeBiasChanged,
      color: FabFilterColors.orange,
    );
  }

  Widget _buildInputTrimSection() {
    return buildSliderRow(
      'INPUT TRIM',
      _inputTrim,
      -12.0,
      12.0,
      '${_inputTrim >= 0 ? '+' : ''}${_inputTrim.toStringAsFixed(1)} dB',
      _onInputTrimChanged,
      color: FabFilterColors.yellow,
    );
  }

  Widget _buildAdvancedSection() {
    return buildSection(
      'ADVANCED',
      Column(
        children: [
          // Oversampling selector
          buildDropdown<OversamplingMode>(
            'OVERSAMPLING',
            _oversampling,
            OversamplingMode.values,
            (m) => m.label,
            _onOversamplingChanged,
          ),
          const SizedBox(height: 8),
          // M/S Mode toggle
          Row(
            children: [
              Expanded(
                child: buildToggle(
                  'M/S MODE',
                  _msMode,
                  _onMsModeChanged,
                  activeColor: FabFilterColors.cyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: buildToggle(
                  'STEREO LINK',
                  _stereoLink,
                  _onStereoLinkChanged,
                  activeColor: FabFilterColors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: FabFilterDecorations.section(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('METERS', style: FabFilterText.sectionHeader),
          const SizedBox(height: 8),
          _buildMeterBar('IN L', _inputPeakL, FabFilterColors.green),
          const SizedBox(height: 4),
          _buildMeterBar('IN R', _inputPeakR, FabFilterColors.green),
          const SizedBox(height: 4),
          _buildMeterBar('OUT L', _outputPeakL, FabFilterColors.orange),
          const SizedBox(height: 4),
          _buildMeterBar('OUT R', _outputPeakR, FabFilterColors.orange),
        ],
      ),
    );
  }

  Widget _buildMeterBar(String label, double dB, Color color) {
    // Normalize dB to 0-1 range: -60dB = 0, 0dB = 1
    final norm = ((dB + 60) / 60).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: FabFilterText.paramLabel.copyWith(fontSize: 8),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: FabFilterColors.bgVoid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: norm,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, norm > 0.9 ? FabFilterColors.red : color],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 36,
          child: Text(
            '${dB.toStringAsFixed(1)}',
            style: FabFilterText.paramValue(color).copyWith(fontSize: 8),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterDisplay() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: FabFilterDecorations.section(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildCharacterItem('Even\nHarmonics',
              _type == SaturationType.tube || _type == SaturationType.tape),
          _buildCharacterItem('Odd\nHarmonics',
              _type == SaturationType.transistor || _type == SaturationType.hardClip),
          _buildCharacterItem('Soft\nClip',
              _type == SaturationType.softClip || _type == SaturationType.tape || _type == SaturationType.tube),
          _buildCharacterItem('Hard\nClip',
              _type == SaturationType.hardClip || _type == SaturationType.transistor || _type == SaturationType.foldback),
        ],
      ),
    );
  }

  Widget _buildCharacterItem(String label, bool active) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _type.color : FabFilterColors.bgSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? _type.color : FabFilterColors.bgHover,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
