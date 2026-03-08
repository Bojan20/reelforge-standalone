/// FF-Q EQ Panel — Pro-Q 3 Style Ultimate
///
/// Professional 64-band parametric EQ with:
/// - Interactive spectrum + EQ curve display with draggable nodes
/// - Catmull-Rom spline spectrum analyzer with peak hold
/// - Piano keyboard frequency reference strip
/// - M/S processing toggle (Stereo / Mid / Side)
/// - Per-band solo & bypass via band chip
/// - Dynamic EQ per band (expert mode)
/// - Click-to-create, drag-to-adjust, scroll-for-Q
/// - All rotary knobs — NO sliders
/// - Node info tooltip on hover/drag

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../services/dsp_frequency_calculator.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';
import 'fabfilter_knob.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

enum EqFilterShape {
  bell('Bell', Icons.lens_blur),
  lowShelf('L Shelf', Icons.south_west),
  highShelf('H Shelf', Icons.north_east),
  lowCut('L Cut', Icons.vertical_align_bottom),
  highCut('H Cut', Icons.vertical_align_top),
  notch('Notch', Icons.compress),
  bandPass('BPass', Icons.filter_alt),
  tiltShelf('Tilt', Icons.trending_up),
  allPass('AllP', Icons.sync_alt),
  brickwall('Brick', Icons.square);

  const EqFilterShape(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum EqPlacement {
  stereo('ST', Icons.headphones, FabFilterColors.blue),
  left('L', Icons.chevron_left, FabFilterColors.orange),
  right('R', Icons.chevron_right, FabFilterColors.orange),
  mid('M', Icons.center_focus_strong, FabFilterColors.green),
  side('S', Icons.unfold_more, FabFilterColors.purple);

  const EqPlacement(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

enum EqSlope {
  db6(6, '6'),
  db12(12, '12'),
  db18(18, '18'),
  db24(24, '24'),
  db36(36, '36'),
  db48(48, '48'),
  db72(72, '72'),
  db96(96, '96'),
  brickwall(96, 'BW');

  const EqSlope(this.dbPerOct, this.label);
  final int dbPerOct;
  final String label;

  /// Number of cascaded biquad stages needed (each stage = 12 dB/oct for Butterworth)
  int get stages => (dbPerOct / 12).ceil().clamp(1, 8);
}

// ═══════════════════════════════════════════════════════════════════════════════
// EQ BAND MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class EqBand {
  int index;
  double freq;
  double gain;
  double q;
  EqFilterShape shape;
  EqSlope slope;
  EqPlacement placement;
  bool enabled;
  bool solo;
  // Dynamic EQ
  bool dynamicEnabled;
  double dynamicThreshold;
  double dynamicRatio;
  double dynamicAttack;
  double dynamicRelease;

  EqBand({
    required this.index,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.shape = EqFilterShape.bell,
    this.slope = EqSlope.db12,
    this.placement = EqPlacement.stereo,
    this.enabled = true,
    this.solo = false,
    this.dynamicEnabled = false,
    this.dynamicThreshold = -20.0,
    this.dynamicRatio = 2.0,
    this.dynamicAttack = 10.0,
    this.dynamicRelease = 100.0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════════

class EqSnapshot implements DspParameterSnapshot {
  final List<Map<String, dynamic>> bandData;
  final double outputGain;
  final bool autoGain;
  final int globalPlacementIdx;

  const EqSnapshot({
    required this.bandData,
    required this.outputGain,
    required this.autoGain,
    required this.globalPlacementIdx,
  });

  @override
  DspParameterSnapshot copy() => EqSnapshot(
    bandData: bandData.map((m) => Map<String, dynamic>.from(m)).toList(),
    outputGain: outputGain,
    autoGain: autoGain,
    globalPlacementIdx: globalPlacementIdx,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! EqSnapshot) return false;
    if (outputGain != other.outputGain || autoGain != other.autoGain || globalPlacementIdx != other.globalPlacementIdx) return false;
    if (bandData.length != other.bandData.length) return false;
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EQ PRESETS (E5.5/E5.6)
// ═══════════════════════════════════════════════════════════════════════════════

class EqPreset {
  final String name;
  final String category;
  final EqSnapshot snapshot;
  final bool isFactory;

  const EqPreset({
    required this.name,
    required this.category,
    required this.snapshot,
    this.isFactory = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'category': category,
    'bandData': snapshot.bandData, 'outputGain': snapshot.outputGain,
    'autoGain': snapshot.autoGain, 'globalPlacementIdx': snapshot.globalPlacementIdx,
  };

  factory EqPreset.fromJson(Map<String, dynamic> json) => EqPreset(
    name: json['name'] as String,
    category: json['category'] as String? ?? 'Custom',
    snapshot: EqSnapshot(
      bandData: (json['bandData'] as List).cast<Map<String, dynamic>>(),
      outputGain: (json['outputGain'] as num?)?.toDouble() ?? 0.0,
      autoGain: json['autoGain'] as bool? ?? false,
      globalPlacementIdx: json['globalPlacementIdx'] as int? ?? 0,
    ),
  );
}

/// Factory EQ presets — common starting points
final List<EqPreset> _factoryEqPresets = [
  // Vocal
  EqPreset(name: 'Vocal Presence', category: 'Vocal', isFactory: true, snapshot: EqSnapshot(
    bandData: [
      {'index': 0, 'freq': 80.0, 'gain': 0.0, 'q': 0.7, 'shape': EqFilterShape.lowCut.index, 'slope': EqSlope.db24.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 1, 'freq': 250.0, 'gain': -2.5, 'q': 1.5, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 2, 'freq': 3500.0, 'gain': 3.0, 'q': 1.2, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 3, 'freq': 12000.0, 'gain': 2.0, 'q': 0.7, 'shape': EqFilterShape.highShelf.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
    ],
    outputGain: 0.0, autoGain: false, globalPlacementIdx: 0,
  )),
  // Guitar
  EqPreset(name: 'Guitar Body', category: 'Guitar', isFactory: true, snapshot: EqSnapshot(
    bandData: [
      {'index': 0, 'freq': 100.0, 'gain': -3.0, 'q': 1.0, 'shape': EqFilterShape.lowShelf.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 1, 'freq': 800.0, 'gain': -2.0, 'q': 2.0, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 2, 'freq': 5000.0, 'gain': 2.5, 'q': 1.0, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
    ],
    outputGain: 0.0, autoGain: false, globalPlacementIdx: 0,
  )),
  // Drums
  EqPreset(name: 'Kick Punch', category: 'Drums', isFactory: true, snapshot: EqSnapshot(
    bandData: [
      {'index': 0, 'freq': 60.0, 'gain': 3.0, 'q': 1.5, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 1, 'freq': 350.0, 'gain': -4.0, 'q': 2.0, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 2, 'freq': 3000.0, 'gain': 2.0, 'q': 1.5, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
    ],
    outputGain: 0.0, autoGain: false, globalPlacementIdx: 0,
  )),
  // Master
  EqPreset(name: 'Gentle Master', category: 'Master', isFactory: true, snapshot: EqSnapshot(
    bandData: [
      {'index': 0, 'freq': 30.0, 'gain': 0.0, 'q': 0.7, 'shape': EqFilterShape.lowCut.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 1, 'freq': 200.0, 'gain': -1.0, 'q': 0.8, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 2, 'freq': 3000.0, 'gain': 1.0, 'q': 0.5, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 3, 'freq': 10000.0, 'gain': 1.5, 'q': 0.7, 'shape': EqFilterShape.highShelf.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
    ],
    outputGain: 0.0, autoGain: false, globalPlacementIdx: 0,
  )),
  // Surgical
  EqPreset(name: 'De-Mud', category: 'Surgical', isFactory: true, snapshot: EqSnapshot(
    bandData: [
      {'index': 0, 'freq': 300.0, 'gain': -3.0, 'q': 2.0, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 1, 'freq': 500.0, 'gain': -2.0, 'q': 2.5, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
    ],
    outputGain: 0.0, autoGain: false, globalPlacementIdx: 0,
  )),
  EqPreset(name: 'De-Harsh', category: 'Surgical', isFactory: true, snapshot: EqSnapshot(
    bandData: [
      {'index': 0, 'freq': 2500.0, 'gain': -2.5, 'q': 3.0, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
      {'index': 1, 'freq': 5000.0, 'gain': -2.0, 'q': 2.0, 'shape': EqFilterShape.bell.index, 'slope': EqSlope.db12.index, 'placement': 0, 'enabled': true, 'solo': false, 'dynamicEnabled': false, 'dynamicThreshold': -20.0, 'dynamicRatio': 2.0, 'dynamicAttack': 10.0, 'dynamicRelease': 100.0},
    ],
    outputGain: 0.0, autoGain: false, globalPlacementIdx: 0,
  )),
];

// ═══════════════════════════════════════════════════════════════════════════════
// PARAM INDICES — ProEqWrapper convention: band * 12 + param
// ═══════════════════════════════════════════════════════════════════════════════

class _P {
  static const freq = 0, gain = 1, q = 2, enabled = 3, shape = 4;
  static const dynEnabled = 5, dynThreshold = 6, dynRatio = 7;
  static const dynAttack = 8, dynRelease = 9;
  static const placement = 11;
  static const paramsPerBand = 12;
  static const outputGainIndex = 64 * paramsPerBand;       // 768
  static const autoGainIndex = 64 * paramsPerBand + 1;     // 769
  static const soloBandIndex = 64 * paramsPerBand + 2;     // 770
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class FabFilterEqPanel extends FabFilterPanelBase {
  const FabFilterEqPanel({
    super.key,
    required super.trackId,
    super.slotIndex,
    super.sampleRate,
    super.onSettingsChanged,
  }) : super(
         title: 'FF-Q 64',
         icon: Icons.equalizer,
         accentColor: FabFilterProcessorColors.eqAccent,
         nodeType: DspNodeType.eq,
       );

  @override
  State<FabFilterEqPanel> createState() => _FabFilterEqPanelState();
}

class _FabFilterEqPanelState extends State<FabFilterEqPanel>
    with FabFilterPanelMixin<FabFilterEqPanel>, TickerProviderStateMixin {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // DspChainProvider
  String _nodeId = '';
  int _slotIndex = -1;
  @override
  int get processorSlotIndex => _slotIndex;

  // Bands
  final List<EqBand> _bands = [];
  int? _selectedBandIndex;
  int? _hoverBandIndex;

  // Global
  double _outputGain = 0.0;
  bool _analyzerOn = true;
  bool _autoGain = false;
  EqPlacement _globalPlacement = EqPlacement.stereo;

  // Spectrum
  List<double> _spectrum = [];
  List<double> _peakHold = [];
  Timer? _spectrumTimer;
  bool _spectrumFrozen = false;       // E2.4: freeze snapshot
  List<double> _frozenSpectrum = [];   // E2.4: frozen snapshot data
  double _spectrumTilt = 0.0;         // E2.5: tilt compensation dB/oct (0, -3, -4.5)
  bool _showPreSpectrum = false;      // E2.1: show pre-EQ overlay
  List<double> _preSpectrum = [];     // E2.1: pre-EQ spectrum data

  // Interaction
  bool _isDragging = false;
  bool _dragSoloActive = false;   // Alt+drag solo listen (E3.2)
  // E8.1: Spring animation — smoothed node positions
  final Map<int, Offset> _springPos = {};  // band index → current display position
  static const _springStiffness = 0.35;    // 0-1, higher = snappier
  Offset? _previewPos;
  Offset? _doubleTapPos;
  late final FocusNode _displayFocusNode; // E3.8: keyboard shortcuts
  double _gainScale = 30.0; // E7.5: ±30dB default, options: 12, 24, 30
  bool _showPhase = false;            // E4.1: phase response curve
  bool _showGroupDelay = false;       // E4.2: group delay
  Float64List _phaseCurve = Float64List(512); // E4.1: phase in degrees
  int _phaseMode = 0;                // E4.3: 0=ZeroLatency, 1=Natural, 2=Linear
  int _oversampleMode = 0;           // E7.1: 0=Off, 1=2x, 2=4x, 3=8x
  bool _autoListen = false;          // E7.4: auto-solo band while dragging
  bool _freqColorMode = false;       // E8.2: color by frequency instead of shape
  int _eqMode = 0;                   // E9.1/E9.4: 0=Digital, 1=Pultec, 2=API550, 3=Neve1073, 4=Ultra
  bool _matchMode = false;           // E6: EQ Match mode
  bool _bassMono = false;            // E9.2: Bass mono toggle
  double _bassMonoFreq = 120.0;     // E9.2: Bass mono crossover frequency
  int _msSpectrumMode = 0;          // E2.6: 0=L/R, 1=Mid, 2=Side
  int _fftSizeMode = 0;            // E2.2: 0=8K, 1=16K, 2=32K
  static const _fftSizes = [8192, 16384, 32768];
  static const _fftLabels = ['8K', '16K', '32K'];
  // E8.3: Waterfall/sonogram
  bool _waterfallMode = false;
  final List<List<double>> _waterfallBuffer = [];
  static const _waterfallMaxFrames = 128;
  // E9.3: Room correction wizard
  bool _roomCorrectionActive = false;
  int _roomCorrectionStep = 0;  // 0=idle, 1=capturing, 2=analyzed, 3=corrected
  int _roomTargetCurve = 1;     // 0=Flat, 1=Harman, 2=B&K, 3=BBC, 4=X-Curve
  List<({double freq, double q, double mag, int type_})> _roomModes = [];
  Timer? _roomCaptureTimer;
  double _roomCaptureProgress = 0.0;
  int _roomCorrectionBands = 0;
  List<double>? _matchReference;     // E6.1: captured reference spectrum
  List<double>? _matchSource;        // E6.2: captured source spectrum
  double _matchAmount = 0.5;         // E6.4: match intensity 0-100%

  // Cached biquad frequency response curves (E1: accurate H(z) evaluation)
  static const int _curveResolution = 512;
  static final Float64List _curveFrequencies = DspFrequencyCalculator.generateLogFrequencies(
    numPoints: _curveResolution,
  );
  /// Per-band magnitude curves in dB, indexed by list position (not band.index)
  List<Float64List> _bandCurves = [];
  /// Composite (summed) magnitude curve in dB
  Float64List _compositeCurve = Float64List(_curveResolution);

  // Metering (~30fps via AnimationController)
  double _inPeakL = 0.0;
  double _inPeakR = 0.0;
  double _outPeakL = 0.0;
  double _outPeakR = 0.0;
  late AnimationController _meterController;

  // A/B snapshots
  EqSnapshot? _snapshotA;
  EqSnapshot? _snapshotB;

  // E5.1: Undo/Redo stack
  final List<EqSnapshot> _undoStack = [];
  final List<EqSnapshot> _redoStack = [];
  static const _maxUndoDepth = 50;

  // E5.2: Copy/paste band
  static Map<String, dynamic>? _copiedBand;

  // ═══════════════════════════════════════════════════════════════════════════
  // A/B COMPARISON — mixin overrides
  // ═══════════════════════════════════════════════════════════════════════════

  EqSnapshot _captureSnapshot() {
    return EqSnapshot(
      bandData: _bands.map((b) => <String, dynamic>{
        'index': b.index, 'freq': b.freq, 'gain': b.gain, 'q': b.q,
        'shape': b.shape.index, 'slope': b.slope.index, 'placement': b.placement.index,
        'enabled': b.enabled, 'solo': b.solo,
        'dynamicEnabled': b.dynamicEnabled,
        'dynamicThreshold': b.dynamicThreshold,
        'dynamicRatio': b.dynamicRatio,
        'dynamicAttack': b.dynamicAttack,
        'dynamicRelease': b.dynamicRelease,
      }).toList(),
      outputGain: _outputGain,
      autoGain: _autoGain,
      globalPlacementIdx: _globalPlacement.index,
    );
  }

  void _restoreSnapshot(EqSnapshot snapshot) {
    setState(() {
      _bands.clear();
      for (final d in snapshot.bandData) {
        _bands.add(EqBand(
          index: d['index'] as int,
          freq: d['freq'] as double,
          gain: d['gain'] as double,
          q: d['q'] as double,
          shape: EqFilterShape.values[(d['shape'] as int).clamp(0, EqFilterShape.values.length - 1)],
          slope: EqSlope.values[((d['slope'] as int?) ?? 1).clamp(0, EqSlope.values.length - 1)],
          placement: EqPlacement.values[(d['placement'] as int).clamp(0, EqPlacement.values.length - 1)],
          enabled: d['enabled'] as bool,
          solo: d['solo'] as bool,
          dynamicEnabled: d['dynamicEnabled'] as bool,
          dynamicThreshold: d['dynamicThreshold'] as double,
          dynamicRatio: d['dynamicRatio'] as double,
          dynamicAttack: d['dynamicAttack'] as double,
          dynamicRelease: d['dynamicRelease'] as double,
        ));
      }
      _outputGain = snapshot.outputGain;
      _autoGain = snapshot.autoGain;
      _globalPlacement = EqPlacement.values[snapshot.globalPlacementIdx.clamp(0, EqPlacement.values.length - 1)];
      _selectedBandIndex = _bands.isNotEmpty ? 0 : null;
    });
    // Push snapshot bands to engine — disable only unused band indices
    final usedIndices = _bands.map((b) => b.index).toSet();
    for (int i = 0; i < 64; i++) {
      if (!usedIndices.contains(i)) {
        _setP(i, _P.enabled, 0.0);
      }
    }
    for (int i = 0; i < _bands.length; i++) {
      _syncBand(i);
    }
    _ffi.insertSetParam(widget.trackId, _slotIndex, _P.outputGainIndex, _outputGain);
    _ffi.insertSetParam(widget.trackId, _slotIndex, _P.autoGainIndex, _autoGain ? 1.0 : 0.0);
    _recalcCurves();
  }

  @override
  void storeStateA() { _snapshotA = _captureSnapshot(); super.storeStateA(); }
  @override
  void storeStateB() { _snapshotB = _captureSnapshot(); super.storeStateB(); }
  @override
  void restoreStateA() { if (_snapshotA != null) _restoreSnapshot(_snapshotA!); }
  @override
  void restoreStateB() { if (_snapshotB != null) _restoreSnapshot(_snapshotB!); }
  @override
  void copyAToB() { _snapshotB = _snapshotA?.copy() as EqSnapshot?; super.copyAToB(); }
  @override
  void copyBToA() { _snapshotA = _snapshotB?.copy() as EqSnapshot?; super.copyBToA(); }

  // ═══════════════════════════════════════════════════════════════════════════
  // E5.1: UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push current state to undo stack (call BEFORE making changes)
  void _pushUndo() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > _maxUndoDepth) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_captureSnapshot());
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_captureSnapshot());
    _restoreSnapshot(_redoStack.removeLast());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METERING — ~30fps I/O peak levels
  // ═══════════════════════════════════════════════════════════════════════════

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
        assert(() { debugPrint('EQ meter error: $e'); return true; }());
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _displayFocusNode = FocusNode(debugLabel: 'eq-display');
    _initProcessor();
    initBypassFromProvider();
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33),
    )..addListener(_updateMeters);
    _meterController.repeat();
  }

  @override
  void dispose() {
    _displayFocusNode.dispose();
    _meterController.dispose();
    _spectrumTimer?.cancel();
    _roomCaptureTimer?.cancel();
    super.dispose();
  }

  void _initProcessor() {
    // If slotIndex was passed directly (from insert editor window), use it
    if (widget.slotIndex >= 0) {
      _slotIndex = widget.slotIndex;
      final dsp = DspChainProvider.instance;
      final chain = dsp.getChain(widget.trackId);
      if (_slotIndex < chain.nodes.length) {
        _nodeId = chain.nodes[_slotIndex].id;
      }
      setState(() => _initialized = true);
      _sanitizeBandsFromEngine();
      _startSpectrum();
      return;
    }
    // Fallback: search by node type (for Lower Zone panels without slotIndex)
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);
    for (int i = 0; i < chain.nodes.length; i++) {
      if (chain.nodes[i].type == DspNodeType.eq) {
        _nodeId = chain.nodes[i].id;
        _slotIndex = i;
        setState(() => _initialized = true);
        _sanitizeBandsFromEngine();
        _startSpectrum();
        return;
      }
    }
    // No EQ node found — stay uninitialized, build() shows buildNotLoadedState
  }

  /// Reset all 64 bands in engine to disabled, then start clean.
  void _sanitizeBandsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    // Force-disable all 64 bands — EQ starts clean, user creates bands explicitly
    for (int i = 0; i < 64; i++) {
      _setP(i, _P.enabled, 0.0);
    }
    setState(() {
      _bands.clear();
      _outputGain = 0.0;
      _autoGain = false;
      _selectedBandIndex = null;
    });
  }

  void _startSpectrum() {
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_initialized || !_analyzerOn) return;
      if (_spectrumFrozen) return; // E2.4: don't update when frozen
      final raw = _ffi.getMasterSpectrum();
      if (raw.isEmpty) return;
      // E2.1: Fetch pre-EQ spectrum overlay
      if (_showPreSpectrum) {
        final preRaw = _ffi.proEqGetPreSpectrum(widget.trackId);
        if (preRaw != null && preRaw.isNotEmpty) {
          _preSpectrum = List<double>.generate(preRaw.length, (i) {
            return (preRaw[i].clamp(0.0, 1.0) * 80 - 80).toDouble();
          });
        }
      }
      // Check if there's actual signal — if all bins are near-silent, clear spectrum
      final db = List<double>.generate(raw.length, (i) {
        double val = raw[i].clamp(0.0, 1.0) * 80 - 80;
        // E2.5: Apply tilt compensation
        if (_spectrumTilt != 0 && raw.length > 1) {
          // Approximate octave position: bin 0 = ~20Hz, last bin = ~20kHz ≈ 10 octaves
          final octave = (i / (raw.length - 1)) * 10.0;
          val -= _spectrumTilt * octave; // negative tilt boosts high freq display
        }
        return val;
      });
      final hasSignal = db.any((v) => v > -72.0);
      if (!hasSignal) {
        if (_spectrum.isNotEmpty) {
          setState(() { _spectrum = []; _peakHold = []; });
        }
        return;
      }
      final prev = _spectrum;
      final out = List<double>.filled(db.length, -80.0);
      for (int i = 0; i < db.length; i++) {
        final p = i < prev.length ? prev[i] : -80.0;
        out[i] = db[i] > p ? p + (db[i] - p) * 0.6 : p + (db[i] - p) * 0.15;
      }
      // Peak hold with slow decay
      if (_peakHold.length != out.length) {
        _peakHold = List<double>.from(out);
      } else {
        for (int i = 0; i < out.length; i++) {
          if (out[i] > _peakHold[i]) {
            _peakHold[i] = out[i];
          } else {
            _peakHold[i] -= 0.3; // slow decay
          }
        }
      }
      // E8.3: Feed waterfall buffer
      if (_waterfallMode) {
        _waterfallBuffer.add(List<double>.from(out));
        if (_waterfallBuffer.length > _waterfallMaxFrames) {
          _waterfallBuffer.removeAt(0);
        }
      }
      bool diff = prev.length != out.length;
      if (!diff) {
        for (int i = 0; i < out.length; i++) {
          if ((out[i] - prev[i]).abs() > 0.1) { diff = true; break; }
        }
      }
      if (diff) setState(() => _spectrum = out);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('EQ', DspNodeType.eq, widget.trackId, () {
        _initProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(children: [
        buildCompactHeader(),
        _buildTopBar(),
        // E4.4: Linear phase latency indicator
        if (_phaseMode == 2) Container(
          height: 14,
          color: const Color(0xFF1A1420),
          alignment: Alignment.center,
          child: Text(
            'Linear Phase — Latency: ${(8192 / (widget.sampleRate > 0 ? widget.sampleRate : 48000) * 1000).toStringAsFixed(1)} ms',
            style: const TextStyle(color: Color(0xFFFF8C40), fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: _buildDisplay()),
        SizedBox(height: 16, child: CustomPaint(painter: _PianoStripPainter())),
        // E6: Match mode panel
        if (_matchMode) _buildMatchPanel(),
        // E9.3: Room correction wizard panel
        if (_roomCorrectionActive) _buildRoomCorrectionPanel(),
        _buildBandChips(),
        if (_selectedBandIndex != null && _selectedBandIndex! < _bands.length)
          Flexible(child: _buildBandEditor()),
      ]),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP BAR — M/S placement + analyzer + auto-gain + output knob
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        // M/S placement chips
        ...EqPlacement.values.map((p) => Padding(
          padding: const EdgeInsets.only(right: 2),
          child: GestureDetector(
            onTap: () => setState(() => _globalPlacement = p),
            child: AnimatedContainer(
              duration: FabFilterDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _globalPlacement == p ? p.color.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _globalPlacement == p ? p.color : FabFilterColors.borderSubtle,
                  width: _globalPlacement == p ? 1.5 : 0.5,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(p.icon, size: 10,
                  color: _globalPlacement == p ? p.color : FabFilterColors.textTertiary),
                const SizedBox(width: 2),
                Text(p.label, style: TextStyle(
                  color: _globalPlacement == p ? p.color : FabFilterColors.textTertiary,
                  fontSize: 9, fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
          ),
        )),
        const SizedBox(width: 4),
        // E9.1/E9.4: EQ mode picker
        GestureDetector(
          onTap: () => setState(() => _eqMode = (_eqMode + 1) % 5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _eqMode != 0 ? FabFilterColors.orange.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _eqMode != 0 ? FabFilterColors.orange : FabFilterColors.borderSubtle,
                width: 0.5,
              ),
            ),
            child: Text(
              const ['Digital', 'Pultec', 'API 550', 'Neve', 'Ultra'][_eqMode],
              style: TextStyle(
                color: _eqMode != 0 ? FabFilterColors.orange : FabFilterColors.textTertiary,
                fontSize: 8, fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // All toolbar buttons in an Expanded Wrap — flows to second line when needed
        Expanded(child: Wrap(
          spacing: 2,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // E6: EQ Match mode toggle
            FabTinyButton(label: 'MTH', active: _matchMode,
              onTap: () => setState(() => _matchMode = !_matchMode),
              color: FabFilterColors.green),
            // E5.5: Preset browser button
            FabTinyButton(label: 'PRE', active: false,
              onTap: _showPresetBrowser,
              color: FabFilterColors.purple),
            // E5.7: Export/Import via clipboard
            FabTinyButton(label: 'EXP', active: false,
              onTap: _exportEqToClipboard,
              color: FabFilterColors.textTertiary),
            // E7.5: Gain scale toggle
            FabTinyButton(
              label: '±${_gainScale.toInt()}',
              active: _gainScale != 30.0,
              onTap: () => setState(() {
                _gainScale = _gainScale == 30.0 ? 12.0 : (_gainScale == 12.0 ? 24.0 : 30.0);
              }),
              color: FabFilterColors.yellow),
            const SizedBox(width: 2),
            // Analyzer toggle
            FabTinyButton(label: 'ANA', active: _analyzerOn,
              onTap: () => setState(() => _analyzerOn = !_analyzerOn),
              color: FabFilterColors.cyan),
            // E2.2: FFT resolution toggle
            FabTinyButton(label: _fftLabels[_fftSizeMode], active: _fftSizeMode > 0,
              onTap: () {
                setState(() => _fftSizeMode = (_fftSizeMode + 1) % 3);
                _ffi.proEqSetFftSize(widget.trackId, _fftSizes[_fftSizeMode]);
              },
              color: FabFilterColors.cyan),
            // E2.1: Pre/Post spectrum overlay
            FabTinyButton(label: 'PRE', active: _showPreSpectrum,
              onTap: () {
                setState(() => _showPreSpectrum = !_showPreSpectrum);
                _ffi.proEqSetAnalyzerMode(widget.trackId,
                    _showPreSpectrum ? ProEqAnalyzerMode.preEq : ProEqAnalyzerMode.postEq);
              },
              color: FabFilterColors.green),
            // E2.6: Mid/Side spectrum
            FabTinyButton(label: _msSpectrumMode == 0 ? 'L/R' : (_msSpectrumMode == 1 ? 'MID' : 'SIDE'),
              active: _msSpectrumMode != 0,
              onTap: () => setState(() => _msSpectrumMode = (_msSpectrumMode + 1) % 3),
              color: FabFilterColors.purple),
            // E2.4: Freeze spectrum
            FabTinyButton(label: 'FRZ', active: _spectrumFrozen,
              onTap: () => setState(() {
                _spectrumFrozen = !_spectrumFrozen;
                if (_spectrumFrozen) {
                  _frozenSpectrum = List<double>.from(_spectrum);
                }
              }),
              color: FabFilterColors.pink),
            // E8.3: Waterfall/sonogram mode
            FabTinyButton(label: 'WF', active: _waterfallMode,
              onTap: () => setState(() {
                _waterfallMode = !_waterfallMode;
                if (!_waterfallMode) _waterfallBuffer.clear();
              }),
              color: FabFilterColors.purple),
            // E2.5: Tilt compensation
            FabTinyButton(
              label: _spectrumTilt == 0 ? 'TILT' : '${_spectrumTilt.toStringAsFixed(1)}',
              active: _spectrumTilt != 0,
              onTap: () => setState(() {
                _spectrumTilt = _spectrumTilt == 0 ? -3.0 : (_spectrumTilt == -3.0 ? -4.5 : 0.0);
              }),
              color: FabFilterColors.orange),
            // E4.1: Phase response toggle
            FabTinyButton(label: 'PH', active: _showPhase,
              onTap: () { setState(() => _showPhase = !_showPhase); _recalcCurves(); },
              color: FabFilterColors.orange),
            // E4.2: Group delay toggle
            FabTinyButton(label: 'GD', active: _showGroupDelay,
              onTap: () => setState(() => _showGroupDelay = !_showGroupDelay),
              color: FabFilterColors.green),
            // Auto-gain
            FabTinyButton(label: 'AG', active: _autoGain,
              onTap: () {
                setState(() => _autoGain = !_autoGain);
                if (_slotIndex >= 0) {
                  _ffi.insertSetParam(widget.trackId, _slotIndex, _P.autoGainIndex, _autoGain ? 1.0 : 0.0);
                }
                widget.onSettingsChanged?.call();
              },
              color: FabFilterColors.green),
            const SizedBox(width: 4),
            // I/O level meters (compact vertical bars)
            _buildCompactIOMeter(),
            const SizedBox(width: 4),
            // Output gain knob + label
            SizedBox(
              width: 100,
              height: 30,
              child: Row(children: [
                SizedBox(
                  width: 52,
                  child: FabFilterKnob(
                    value: ((_outputGain + 24) / 48).clamp(0.0, 1.0),
                    label: '',
                    display: '',
                    color: FabFilterColors.blue,
                    size: 24,
                    adaptive: true,
                    defaultValue: 0.5,
                    onChanged: (v) {
                      setState(() => _outputGain = v * 48 - 24);
                      if (_slotIndex >= 0) {
                        _ffi.insertSetParam(widget.trackId, _slotIndex, _P.outputGainIndex, _outputGain);
                      }
                      widget.onSettingsChanged?.call();
                    },
                  ),
                ),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('OUT', style: TextStyle(
                      color: FabFilterColors.textTertiary, fontSize: 7,
                      fontWeight: FontWeight.bold, letterSpacing: 1,
                    ), overflow: TextOverflow.ellipsis),
                    Text(
                      '${_outputGain >= 0 ? '+' : ''}${_outputGain.toStringAsFixed(1)} dB',
                      style: FabFilterText.paramValue(FabFilterColors.blue),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )),
              ]),
            ),
            // E4.3: Phase mode picker
            FabTinyButton(
              label: const ['ZL', 'NAT', 'LIN'][_phaseMode],
              active: _phaseMode != 0,
              onTap: () {
                final next = (_phaseMode + 1) % 3;
                setState(() => _phaseMode = next);
                _ffi.proEqSetPhaseMode(widget.trackId, next);
              },
              color: FabFilterColors.orange),
            // E7.1: Oversampling picker
            FabTinyButton(
              label: const ['OS:Off', 'OS:2x', 'OS:4x', 'OS:8x'][_oversampleMode],
              active: _oversampleMode != 0,
              onTap: () {
                setState(() => _oversampleMode = (_oversampleMode + 1) % 4);
                _ffi.proEqSetOversampling(widget.trackId, _oversampleMode);
              },
              color: FabFilterColors.cyan),
            // E7.4: Auto-listen mode
            FabTinyButton(label: 'AL', active: _autoListen,
              onTap: () => setState(() => _autoListen = !_autoListen),
              color: FabFilterColors.yellow),
            // E8.2: Color mode toggle
            FabTinyButton(label: _freqColorMode ? 'CLR' : 'SHP', active: _freqColorMode,
              onTap: () => setState(() => _freqColorMode = !_freqColorMode),
              color: FabFilterColors.pink),
            // E9.2: Bass mono toggle (tap=toggle, right-click=cycle freq)
            GestureDetector(
              onTap: () {
                setState(() => _bassMono = !_bassMono);
                _ffi.bassMonoSetEnabled(widget.trackId, _bassMono);
                if (_bassMono) _ffi.bassMonoSetFreq(widget.trackId, _bassMonoFreq);
              },
              onSecondaryTap: () {
                const freqs = [60.0, 80.0, 100.0, 120.0, 150.0, 200.0];
                final idx = freqs.indexOf(_bassMonoFreq);
                setState(() => _bassMonoFreq = freqs[(idx + 1) % freqs.length]);
                if (_bassMono) _ffi.bassMonoSetFreq(widget.trackId, _bassMonoFreq);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: _bassMono ? FabFilterColors.green.withValues(alpha: 0.2) : FabFilterColors.bgMid,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: _bassMono ? FabFilterColors.green : FabFilterColors.border),
                ),
                child: Text(_bassMono ? 'BM:${_bassMonoFreq.round()}' : 'BM',
                  style: TextStyle(
                    color: _bassMono ? FabFilterColors.green : FabFilterColors.textTertiary,
                    fontSize: 7, fontWeight: FontWeight.bold)),
              ),
            ),
            // E9.3: Room correction wizard
            FabTinyButton(label: 'RM', active: _roomCorrectionActive,
              onTap: () => setState(() {
                _roomCorrectionActive = !_roomCorrectionActive;
                if (!_roomCorrectionActive) {
                  _roomCaptureTimer?.cancel();
                  _roomCorrectionStep = 0;
                }
              }),
              color: FabFilterColors.green),
            // E8.4: Full-screen mode
            GestureDetector(
              onTap: () => _showFullscreen(context),
              child: const Icon(Icons.fullscreen, size: 16, color: FabFilterColors.textTertiary),
            ),
          ],
        )),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // I/O METERING — compact stereo bars in top bar
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompactIOMeter() {
    return SizedBox(
      width: 40,
      height: 26,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // IN label + bars
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('IN', style: TextStyle(
            color: FabFilterColors.textDisabled, fontSize: 6,
            fontWeight: FontWeight.bold, letterSpacing: 0.5,
          ), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Row(children: [
            _meterBar(_inPeakL, 14),
            const SizedBox(width: 1),
            _meterBar(_inPeakR, 14),
          ]),
        ]),
        const SizedBox(width: 4),
        // OUT label + bars
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('OUT', style: TextStyle(
            color: FabFilterColors.textDisabled, fontSize: 6,
            fontWeight: FontWeight.bold, letterSpacing: 0.5,
          ), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Row(children: [
            _meterBar(_outPeakL, 14),
            const SizedBox(width: 1),
            _meterBar(_outPeakR, 14),
          ]),
        ]),
      ]),
    );
  }

  Widget _meterBar(double linear, double height) {
    // Convert linear to dB, then to 0..1 range (-60dB..0dB)
    final dB = linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;
    final norm = ((dB + 60.0) / 60.0).clamp(0.0, 1.0);
    final isHot = dB > -3.0;
    final isClip = dB > -0.5;
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0E),
        borderRadius: BorderRadius.circular(1),
      ),
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        width: 3,
        height: norm * height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: isClip
                ? [FabFilterColors.red, FabFilterColors.red]
                : isHot
                    ? [FabFilterColors.green, FabFilterColors.yellow]
                    : [FabFilterColors.green, FabFilterColors.cyan],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPLAY — Spectrum + EQ Curve + Band Nodes
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDisplay() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: FabFilterDecorations.display(),
      child: LayoutBuilder(builder: (ctx, box) {
        return Focus(
          focusNode: _displayFocusNode,
          onKeyEvent: (_, event) => _handleKeyEvent(event, box.biggest),
          child: MouseRegion(
          onHover: (e) => _onHover(e.localPosition, box.biggest),
          onExit: (_) => setState(() { _hoverBandIndex = null; _previewPos = null; }),
          child: Listener(
            onPointerSignal: (e) { if (e is PointerScrollEvent) _onScroll(e, box.biggest); },
            onPointerPanZoomUpdate: (e) => _onTrackpadScroll(e.panDelta.dy, box.biggest),
            child: GestureDetector(
              onTapDown: (d) => _onTapSelect(d.localPosition, box.biggest),
              onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
              onDoubleTap: () { if (_doubleTapPos != null) _onDoubleTap(_doubleTapPos!, box.biggest); },
              onSecondaryTapDown: (d) => _onRightClick(d.localPosition, d.globalPosition, box.biggest),
              onPanStart: (d) => _onDragStart(d.localPosition, box.biggest),
              onPanUpdate: (d) => _onDragUpdate(d.localPosition, box.biggest),
              onPanEnd: (_) => _onDragEnd(box.biggest),
              child: RepaintBoundary( // E8.5: isolate repaint for smooth 60fps
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: CustomPaint(
                  painter: _EqDisplayPainter(
                    bands: _bands,
                    selectedIdx: _selectedBandIndex,
                    hoverIdx: _hoverBandIndex,
                    spectrum: _spectrum,
                    peakHold: _peakHold,
                    analyzerOn: _analyzerOn,
                    previewPos: _previewPos,
                    isDragging: _isDragging,
                    bandCurves: _bandCurves,
                    compositeCurve: _compositeCurve,
                    curveFrequencies: _curveFrequencies,
                    gainScale: _gainScale,
                    frozenSpectrum: _frozenSpectrum,
                    phaseCurve: _showPhase ? _phaseCurve : null,
                    showGroupDelay: _showGroupDelay,
                    freqColorMode: _freqColorMode,
                    preSpectrum: _showPreSpectrum ? _preSpectrum : const [],
                    waterfallBuffer: _waterfallMode ? _waterfallBuffer : const [],
                    soloBandIdx: _bands.any((b) => b.solo) ? _bands.firstWhere((b) => b.solo).index : -1,
                  ),
                  size: box.biggest,
                ),
              ),
            )),
          ),
        ));
      }),
    );
  }

  // E3.8: Keyboard shortcut handler
  KeyEventResult _handleKeyEvent(KeyEvent event, Size size) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Guard: don't handle if an EditableText ancestor has focus
    if (_displayFocusNode.context != null) {
      final scope = FocusScope.of(_displayFocusNode.context!);
      if (scope.focusedChild != _displayFocusNode) return KeyEventResult.ignored;
    }
    final idx = _selectedBandIndex;
    final isMeta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // E5.1: Cmd+Z = Undo, Cmd+Shift+Z = Redo
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) { _redo(); } else { _undo(); }
      return KeyEventResult.handled;
    }
    // E5.2: Cmd+C = copy band, Cmd+V = paste band
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (idx != null && idx < _bands.length) {
        final b = _bands[idx];
        _copiedBand = {
          'freq': b.freq, 'gain': b.gain, 'q': b.q,
          'shape': b.shape.index, 'slope': b.slope.index,
          'placement': b.placement.index,
          'dynamicEnabled': b.dynamicEnabled,
          'dynamicThreshold': b.dynamicThreshold,
          'dynamicRatio': b.dynamicRatio,
          'dynamicAttack': b.dynamicAttack,
          'dynamicRelease': b.dynamicRelease,
        };
      }
      return KeyEventResult.handled;
    }
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_copiedBand != null) {
        _pushUndo();
        _addBand((_copiedBand!['freq'] as double), EqFilterShape.values[(_copiedBand!['shape'] as int).clamp(0, EqFilterShape.values.length - 1)]);
        // Apply copied params to newest band
        if (_bands.isNotEmpty) {
          final nb = _bands.last;
          nb.gain = _copiedBand!['gain'] as double;
          nb.q = _copiedBand!['q'] as double;
          nb.slope = EqSlope.values[(_copiedBand!['slope'] as int).clamp(0, EqSlope.values.length - 1)];
          nb.dynamicEnabled = _copiedBand!['dynamicEnabled'] as bool;
          nb.dynamicThreshold = _copiedBand!['dynamicThreshold'] as double;
          nb.dynamicRatio = _copiedBand!['dynamicRatio'] as double;
          nb.dynamicAttack = _copiedBand!['dynamicAttack'] as double;
          nb.dynamicRelease = _copiedBand!['dynamicRelease'] as double;
          _syncBand(_bands.length - 1);
        }
      }
      return KeyEventResult.handled;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        // Delete selected band
        if (idx != null && idx < _bands.length) {
          _removeBand(idx);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.space:
        // Toggle enable/disable selected band
        if (idx != null && idx < _bands.length) {
          _pushUndo();
          setState(() => _bands[idx].enabled = !_bands[idx].enabled);
          _setP(_bands[idx].index, _P.enabled, _bands[idx].enabled ? 1.0 : 0.0);
          _recalcCurves();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyS:
        // Toggle solo on selected band (exclusive — only one solo at a time)
        if (idx != null && idx < _bands.length) {
          setState(() {
            if (_bands[idx].solo) {
              _bands[idx].solo = false;
            } else {
              for (final other in _bands) { other.solo = false; }
              _bands[idx].solo = true;
            }
          });
          _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex,
            _bands[idx].solo ? _bands[idx].index.toDouble() : -1.0);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyD:
        // Toggle dynamic EQ on selected band
        if (idx != null && idx < _bands.length) {
          _pushUndo();
          setState(() => _bands[idx].dynamicEnabled = !_bands[idx].dynamicEnabled);
          _syncBand(idx);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyI:
        // E5.3: Invert selected band gain (boost↔cut)
        if (idx != null && idx < _bands.length) {
          _pushUndo();
          setState(() => _bands[idx].gain = -_bands[idx].gain);
          _syncBand(idx);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.escape:
        // Deselect
        setState(() => _selectedBandIndex = null);
        return KeyEventResult.handled;
      default:
        break;
    }
    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND CHIPS — horizontal scrollable strip
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBandChips() {
    return SizedBox(
      height: 30,
      child: Row(children: [
        const SizedBox(width: 8),
        // Band count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: FabFilterProcessorColors.eqAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FabFilterProcessorColors.eqAccent.withValues(alpha: 0.3)),
          ),
          child: Text('${_bands.length}', style: TextStyle(
            color: FabFilterProcessorColors.eqAccent,
            fontSize: 9, fontWeight: FontWeight.bold,
          )),
        ),
        const SizedBox(width: 4),
        Expanded(child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: _bands.length,
          separatorBuilder: (_, _) => const SizedBox(width: 3),
          itemBuilder: (_, i) {
            final b = _bands[i];
            final sel = i == _selectedBandIndex;
            final c = _shapeColor(b.shape);
            return GestureDetector(
              onTap: () => setState(() => _selectedBandIndex = i),
              onDoubleTap: () {
                setState(() => b.enabled = !b.enabled);
                _setP(b.index, _P.enabled, b.enabled ? 1.0 : 0.0);
              },
              onLongPress: () => _removeBand(i),
              child: AnimatedContainer(
                duration: FabFilterDurations.fast,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? c.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? c : (b.enabled ? c.withValues(alpha: 0.4) : FabFilterColors.borderSubtle),
                    width: sel ? 1.5 : 0.5,
                  ),
                  boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.2), blurRadius: 6)] : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(b.shape.icon, size: 9,
                    color: b.enabled ? c : FabFilterColors.textDisabled),
                  const SizedBox(width: 3),
                  if (!b.enabled) Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(Icons.visibility_off, size: 7, color: FabFilterColors.textTertiary),
                  ),
                  if (b.solo) Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(Icons.headphones, size: 7, color: FabFilterColors.yellow),
                  ),
                  if (b.dynamicEnabled) Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(Icons.flash_on, size: 7, color: FabFilterColors.yellow),
                  ),
                  Text(_fmtFreq(b.freq), style: TextStyle(
                    color: sel ? FabFilterColors.textPrimary : (b.enabled ? c : FabFilterColors.textDisabled),
                    fontSize: 9, fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
                ]),
              ),
            );
          },
        )),
        // Add band
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 18),
          color: FabFilterProcessorColors.eqAccent,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
          tooltip: 'Add Band (or click graph)',
          onPressed: () => _addBand(1000, EqFilterShape.bell),
        ),
        // Reset
        IconButton(
          icon: const Icon(Icons.refresh, size: 16),
          color: FabFilterColors.textTertiary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
          tooltip: 'Reset EQ',
          onPressed: _resetEq,
        ),
        const SizedBox(width: 4),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND EDITOR — Pro-Q 3 style: Shape chips | Knobs | Options
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBandEditor() {
    final b = _bands[_selectedBandIndex!];
    final c = _shapeColor(b.shape);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        border: const Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(children: [
        // ── LEFT: Shape selector (vertical compact grid) ──
        SizedBox(
          width: 100,
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: EqFilterShape.values.map((s) {
              final act = b.shape == s;
              final sc = _shapeColor(s);
              return GestureDetector(
                onTap: () {
                  setState(() => b.shape = s);
                  _syncBand(_selectedBandIndex!);
                },
                child: AnimatedContainer(
                  duration: FabFilterDurations.fast,
                  width: 46,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: act ? sc.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: act ? sc : FabFilterColors.borderSubtle,
                      width: act ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(s.icon, size: 9, color: act ? sc : FabFilterColors.textTertiary),
                    const SizedBox(width: 2),
                    Text(s.label, style: TextStyle(
                      fontSize: 7, fontWeight: FontWeight.bold,
                      color: act ? sc : FabFilterColors.textTertiary,
                    )),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        Container(width: 1, height: 60, color: FabFilterColors.borderSubtle),
        const SizedBox(width: 8),
        // ── CENTER: Knobs row ──
        Expanded(child: SizedBox(
          height: 68,
          child: Row(children: [
            _editorKnob('FREQ', _freqToNorm(b.freq), _fmtFreq(b.freq), c, (v) {
              setState(() => b.freq = _normToFreq(v));
              _syncBand(_selectedBandIndex!);
            }, onScroll: (e) => _onScroll(e, const Size(1, 1)),
               onTrackpadScroll: (dy) => _onTrackpadScroll(dy, const Size(1, 1))),
            _editorKnob('GAIN', ((b.gain + 30) / 60).clamp(0.0, 1.0),
              '${b.gain >= 0 ? '+' : ''}${b.gain.toStringAsFixed(1)}',
              b.gain >= 0 ? FabFilterColors.orange : FabFilterColors.cyan, (v) {
              setState(() => b.gain = v * 60 - 30);
              _syncBand(_selectedBandIndex!);
            }, onScroll: (e) => _onScroll(e, const Size(1, 1)),
               onTrackpadScroll: (dy) => _onTrackpadScroll(dy, const Size(1, 1))),
            _editorKnob('Q', (math.log(b.q / 0.1) / math.log(30 / 0.1)).clamp(0.0, 1.0),
              b.q.toStringAsFixed(2), c, (v) {
              setState(() => b.q = (0.1 * math.pow(30 / 0.1, v)).toDouble());
              _syncBand(_selectedBandIndex!);
            }),
            if (showExpertMode && b.dynamicEnabled) ...[
              _editorKnob('THR', ((b.dynamicThreshold + 60) / 60).clamp(0.0, 1.0),
                '${b.dynamicThreshold.toStringAsFixed(0)}',
                FabFilterColors.yellow, (v) {
                setState(() => b.dynamicThreshold = v * 60 - 60);
                _syncBand(_selectedBandIndex!);
              }),
              _editorKnob('RAT', ((b.dynamicRatio - 1) / 19).clamp(0.0, 1.0),
                '${b.dynamicRatio.toStringAsFixed(1)}:1',
                FabFilterColors.yellow, (v) {
                setState(() => b.dynamicRatio = 1 + v * 19);
                _syncBand(_selectedBandIndex!);
              }),
            ],
          ]),
        )),
        const SizedBox(width: 8),
        Container(width: 1, height: 60, color: FabFilterColors.borderSubtle),
        const SizedBox(width: 6),
        // ── RIGHT: Options column ──
        SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Placement cycle
              GestureDetector(
                onTap: () {
                  final vals = EqPlacement.values;
                  setState(() => b.placement = vals[(vals.indexOf(b.placement) + 1) % vals.length]);
                  _syncBand(_selectedBandIndex!);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: b.placement.color, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                    color: b.placement.color.withValues(alpha: 0.1),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(b.placement.icon, size: 10, color: b.placement.color),
                    const SizedBox(width: 2),
                    Text(b.placement.label, style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.bold, color: b.placement.color,
                    )),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              // Solo / Enable / Dynamic / Delete row
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FabTinyButton(label: 'S', active: b.solo,
                  onTap: () {
                    setState(() {
                      if (b.solo) {
                        b.solo = false;
                        if (_slotIndex >= 0) {
                          _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex, -1.0);
                        }
                      } else {
                        for (final other in _bands) { other.solo = false; }
                        b.solo = true;
                        if (_slotIndex >= 0) {
                          _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex, b.index.toDouble());
                        }
                      }
                    });
                  },
                  color: FabFilterColors.yellow),
                const SizedBox(width: 2),
                FabTinyButton(label: b.enabled ? 'ON' : '-',
                  active: b.enabled,
                  onTap: () {
                    setState(() => b.enabled = !b.enabled);
                    _setP(b.index, _P.enabled, b.enabled ? 1.0 : 0.0);
                  },
                  color: FabFilterColors.green),
              ]),
              const SizedBox(height: 3),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (showExpertMode)
                  FabTinyButton(label: 'DYN', active: b.dynamicEnabled,
                    onTap: () {
                      setState(() => b.dynamicEnabled = !b.dynamicEnabled);
                      _syncBand(_selectedBandIndex!);
                    },
                    color: FabFilterColors.yellow),
                if (showExpertMode) const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => _removeBand(_selectedBandIndex!),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: FabFilterColors.red.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.close, size: 10, color: FabFilterColors.red),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _editorKnob(String label, double norm, String display, Color c, ValueChanged<double> onChanged, {void Function(PointerScrollEvent)? onScroll, void Function(double dy)? onTrackpadScroll}) {
    return Expanded(child: FabFilterKnob(
      value: norm.clamp(0.0, 1.0),
      onChanged: onChanged,
      onScroll: onScroll,
      onTrackpadScroll: onTrackpadScroll,
      color: c,
      size: 36,
      adaptive: true,
      label: label,
      display: display,
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERACTION HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _onHover(Offset pos, Size size) {
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
        setState(() { _hoverBandIndex = i; _previewPos = null; });
        return;
      }
    }
    setState(() { _hoverBandIndex = null; _previewPos = pos; });
  }

  void _onScroll(PointerScrollEvent e, Size size) {
    _onTrackpadScroll(e.scrollDelta.dy, size);
  }

  /// Unified scroll handler for both mouse wheel (PointerScrollEvent) and
  /// macOS trackpad two-finger gesture (PointerPanZoomUpdateEvent).
  void _onTrackpadScroll(double scrollDy, Size size) {
    final idx = _selectedBandIndex ?? _hoverBandIndex;
    if (idx == null || idx >= _bands.length) return;
    final b = _bands[idx];

    // E3.7: For cut/shelf filters, scroll changes slope instead of Q
    final isSlopeFilter = b.shape == EqFilterShape.lowCut ||
        b.shape == EqFilterShape.highCut ||
        b.shape == EqFilterShape.brickwall;
    if (isSlopeFilter) {
      final slopes = EqSlope.values;
      final curIdx = slopes.indexOf(b.slope);
      final newIdx = scrollDy > 0
          ? (curIdx - 1).clamp(0, slopes.length - 1)
          : (curIdx + 1).clamp(0, slopes.length - 1);
      if (newIdx != curIdx) {
        setState(() => b.slope = slopes[newIdx]);
        _syncBand(idx);
      }
      return;
    }

    final fine = HardwareKeyboard.instance.isShiftPressed;
    final delta = (scrollDy > 0 ? -0.2 : 0.2) * (fine ? 0.1 : 1.0);
    setState(() => b.q = (b.q + delta).clamp(0.1, 30.0));
    _syncBand(idx); // _recalcCurves() called inside _syncBand
  }

  void _onTapSelect(Offset pos, Size size) {
    _displayFocusNode.requestFocus(); // E3.8: Focus display for keyboard shortcuts
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed; // Cmd on macOS (E3.4)
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
        if (isCtrl) {
          // E3.4: Ctrl/Cmd+click = reset band to default (gain=0, Q=1)
          _pushUndo(); // E5.1
          setState(() {
            _bands[i].gain = 0.0;
            _bands[i].q = 1.0;
            _selectedBandIndex = i;
          });
          _syncBand(i);
          return;
        }
        setState(() => _selectedBandIndex = i);
        return;
      }
    }
    // Single click on empty space — deselect
    setState(() => _selectedBandIndex = null);
  }

  void _onDoubleTap(Offset pos, Size size) {
    // Double-click on existing band — toggle enabled
    for (int i = 0; i < _bands.length; i++) {
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
        _pushUndo(); // E5.1
        setState(() => _bands[i].enabled = !_bands[i].enabled);
        _setP(_bands[i].index, _P.enabled, _bands[i].enabled ? 1.0 : 0.0);
        _recalcCurves();
        return;
      }
    }
    // Double-click on empty space — add new band at position
    _addBand(_xToFreq(pos.dx, size.width), EqFilterShape.bell);
  }

  // E3.5: Right-click context menu
  void _onRightClick(Offset localPos, Offset globalPos, Size size) {
    // Find band under cursor
    int? bandIdx;
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - localPos).distance < 15) {
        bandIdx = i;
        break;
      }
    }

    final items = <PopupMenuEntry<String>>[];
    if (bandIdx != null) {
      final b = _bands[bandIdx];
      items.addAll([
        PopupMenuItem(value: 'solo', child: Text(b.solo ? 'Unsolo' : 'Solo')),
        PopupMenuItem(value: 'bypass', child: Text(b.enabled ? 'Bypass Band' : 'Enable Band')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'invert', child: Text('Invert Gain')),
        const PopupMenuItem(value: 'copy', child: Text('Copy Band')),
        const PopupMenuItem(value: 'reset', child: Text('Reset to Default')),
        const PopupMenuItem(value: 'delete', child: Text('Delete Band')),
        const PopupMenuDivider(),
        // Filter shape submenu
        ...EqFilterShape.values.where((s) => s != EqFilterShape.brickwall).map(
          (s) => PopupMenuItem(
            value: 'shape_${s.index}',
            child: Row(children: [
              Icon(s.icon, size: 14, color: b.shape == s ? FabFilterColors.blue : null),
              const SizedBox(width: 6),
              Text(s.label, style: TextStyle(
                fontWeight: b.shape == s ? FontWeight.bold : FontWeight.normal,
              )),
            ]),
          ),
        ),
      ]);
    } else {
      items.addAll([
        const PopupMenuItem(value: 'add_bell', child: Text('Add Bell')),
        const PopupMenuItem(value: 'add_lowshelf', child: Text('Add Low Shelf')),
        const PopupMenuItem(value: 'add_highshelf', child: Text('Add High Shelf')),
        const PopupMenuItem(value: 'add_lowcut', child: Text('Add Low Cut')),
        const PopupMenuItem(value: 'add_highcut', child: Text('Add High Cut')),
        if (_copiedBand != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'paste', child: Text('Paste Band')),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'bypass_bells', child: Text('Bypass All Bells')),
        const PopupMenuItem(value: 'bypass_cuts', child: Text('Bypass All Cuts')),
        const PopupMenuItem(value: 'bypass_shelves', child: Text('Bypass All Shelves')),
        const PopupMenuItem(value: 'enable_all', child: Text('Enable All Bands')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'reset_all', child: Text('Reset All')),
      ]);
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      items: items,
      color: const Color(0xFF1A1A22),
    ).then((val) {
      if (val == null) return;
      if (bandIdx != null) {
        final bi = bandIdx;
        final b = _bands[bi];
        switch (val) {
          case 'solo':
            setState(() {
              if (b.solo) {
                b.solo = false;
              } else {
                for (final other in _bands) { other.solo = false; }
                b.solo = true;
              }
            });
            _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex,
              b.solo ? b.index.toDouble() : -1.0);
          case 'bypass':
            setState(() => b.enabled = !b.enabled);
            _setP(b.index, _P.enabled, b.enabled ? 1.0 : 0.0);
            _recalcCurves();
          case 'invert':
            _pushUndo();
            setState(() => b.gain = -b.gain);
            _syncBand(bi);
          case 'copy':
            _copiedBand = {
              'freq': b.freq, 'gain': b.gain, 'q': b.q,
              'shape': b.shape.index, 'slope': b.slope.index,
              'placement': b.placement.index,
              'dynamicEnabled': b.dynamicEnabled,
              'dynamicThreshold': b.dynamicThreshold,
              'dynamicRatio': b.dynamicRatio,
              'dynamicAttack': b.dynamicAttack,
              'dynamicRelease': b.dynamicRelease,
            };
          case 'reset':
            _pushUndo();
            setState(() { b.gain = 0.0; b.q = 1.0; });
            _syncBand(bi);
          case 'delete':
            _removeBand(bi);
          default:
            if (val.startsWith('shape_')) {
              final si = int.tryParse(val.substring(6));
              if (si != null && si < EqFilterShape.values.length) {
                setState(() => b.shape = EqFilterShape.values[si]);
                _syncBand(bi);
              }
            }
        }
      } else {
        switch (val) {
          case 'add_bell': _addBand(_xToFreq(localPos.dx, size.width), EqFilterShape.bell);
          case 'add_lowshelf': _addBand(_xToFreq(localPos.dx, size.width), EqFilterShape.lowShelf);
          case 'add_highshelf': _addBand(_xToFreq(localPos.dx, size.width), EqFilterShape.highShelf);
          case 'add_lowcut': _addBand(_xToFreq(localPos.dx, size.width), EqFilterShape.lowCut);
          case 'add_highcut': _addBand(_xToFreq(localPos.dx, size.width), EqFilterShape.highCut);
          case 'paste':
            if (_copiedBand != null) {
              final freq = _xToFreq(localPos.dx, size.width);
              _pushUndo();
              _addBand(freq, EqFilterShape.values[(_copiedBand!['shape'] as int).clamp(0, EqFilterShape.values.length - 1)]);
              if (_bands.isNotEmpty) {
                final nb = _bands.last;
                nb.gain = _copiedBand!['gain'] as double;
                nb.q = _copiedBand!['q'] as double;
                nb.slope = EqSlope.values[(_copiedBand!['slope'] as int).clamp(0, EqSlope.values.length - 1)];
                nb.dynamicEnabled = _copiedBand!['dynamicEnabled'] as bool;
                nb.dynamicThreshold = _copiedBand!['dynamicThreshold'] as double;
                nb.dynamicRatio = _copiedBand!['dynamicRatio'] as double;
                nb.dynamicAttack = _copiedBand!['dynamicAttack'] as double;
                nb.dynamicRelease = _copiedBand!['dynamicRelease'] as double;
                _syncBand(_bands.length - 1);
              }
            }
          case 'bypass_bells': _bypassByShape({EqFilterShape.bell});
          case 'bypass_cuts': _bypassByShape({EqFilterShape.lowCut, EqFilterShape.highCut, EqFilterShape.brickwall});
          case 'bypass_shelves': _bypassByShape({EqFilterShape.lowShelf, EqFilterShape.highShelf, EqFilterShape.tiltShelf});
          case 'enable_all': _enableAllBands();
          case 'reset_all': _resetEq();
        }
      }
    });
  }

  void _onDragStart(Offset pos, Size size) {
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
        _pushUndo(); // E5.1: snapshot before drag
        setState(() { _selectedBandIndex = i; _isDragging = true; });
        // E3.2 + E7.4: Alt+drag or auto-listen = solo listen
        if ((HardwareKeyboard.instance.isAltPressed || _autoListen) && _slotIndex >= 0) {
          _dragSoloActive = true;
          _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex, _bands[i].index.toDouble());
        }
        return;
      }
    }
  }

  void _onDragUpdate(Offset pos, Size size) {
    if (!_isDragging || _selectedBandIndex == null) return;
    final b = _bands[_selectedBandIndex!];
    // E3.3: Shift+drag = fine adjust (10× precision)
    final fine = HardwareKeyboard.instance.isShiftPressed;
    final rawFreq = _xToFreq(pos.dx, size.width);
    final rawGain = _yToGain(pos.dy, size.height);
    setState(() {
      if (fine) {
        // Fine mode: 10× precision
        b.freq = (b.freq + (rawFreq - b.freq) * 0.1).clamp(10.0, 30000.0);
        b.gain = (b.gain + (rawGain - b.gain) * 0.1).clamp(-30.0, 30.0);
      } else {
        // E8.1: Spring physics — smooth exponential interpolation instead of instant snap
        b.freq = (b.freq + (rawFreq - b.freq) * _springStiffness).clamp(10.0, 30000.0);
        b.gain = (b.gain + (rawGain - b.gain) * _springStiffness).clamp(-30.0, 30.0);
      }
    });
    _syncBand(_selectedBandIndex!);
  }

  void _onDragEnd(Size size) {
    // E3.2: Disengage solo listen on drag end
    if (_dragSoloActive && _slotIndex >= 0) {
      _dragSoloActive = false;
      _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex, -1.0);
    }
    // E3.9: Drag off-screen = delete band
    // (checked via last drag position — if band is near edge, user dragged it out)
    if (_isDragging && _selectedBandIndex != null) {
      final b = _bands[_selectedBandIndex!];
      final bx = _freqToX(b.freq, size.width);
      final by = _gainToY(b.gain, size.height);
      // Delete if dragged past top/bottom edge (within 4px of boundary)
      if (by <= 4 || by >= size.height - 4) {
        _removeBand(_selectedBandIndex!);
        setState(() => _isDragging = false);
        return;
      }
    }
    setState(() => _isDragging = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND OPS (via InsertProcessor chain)
  // ═══════════════════════════════════════════════════════════════════════════

  void _addBand(double freq, EqFilterShape shape) {
    if (_bands.length >= 64 || _slotIndex < 0) return;
    _pushUndo(); // E5.1
    // Find first free (disabled) band index in engine — don't assume sequential
    int idx = _bands.length;
    final usedIndices = _bands.map((b) => b.index).toSet();
    for (int i = 0; i < 64; i++) {
      if (!usedIndices.contains(i)) { idx = i; break; }
    }
    final band = EqBand(index: idx, freq: freq, shape: shape, placement: _globalPlacement);
    setState(() { _bands.add(band); _selectedBandIndex = _bands.length - 1; });
    // Set all params BEFORE enabling — engine updates coefficients only when enabled
    _setP(idx, _P.freq, freq);
    _setP(idx, _P.gain, 0.0);
    _setP(idx, _P.q, 1.0);
    _setP(idx, _P.shape, shape.index.toDouble());
    _setP(idx, _P.placement, _globalPlacement.index.toDouble());
    // Enable LAST so coefficients are computed with correct params
    _setP(idx, _P.enabled, 1.0);
    _recalcCurves();
    widget.onSettingsChanged?.call();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCURATE BIQUAD CURVE CALCULATION (E1)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Map EqFilterShape to DspFrequencyCalculator filter type string.
  static String _shapeToFilterType(EqFilterShape shape) {
    return switch (shape) {
      EqFilterShape.bell => 'bell',
      EqFilterShape.lowShelf => 'lowshelf',
      EqFilterShape.highShelf => 'highshelf',
      EqFilterShape.lowCut => 'highpass',
      EqFilterShape.highCut => 'lowpass',
      EqFilterShape.notch => 'notch',
      EqFilterShape.bandPass => 'bandpass',
      EqFilterShape.tiltShelf => 'tilt',
      EqFilterShape.allPass => 'allpass',
      EqFilterShape.brickwall => 'highpass',
    };
  }

  /// Recalculate all cached frequency response curves using true biquad H(z).
  void _recalcCurves() {
    final sr = widget.sampleRate;
    final n = _curveResolution;
    final freqs = _curveFrequencies;

    // Rebuild per-band curves
    _bandCurves = List<Float64List>.generate(_bands.length, (bi) {
      final b = _bands[bi];
      final curve = Float64List(n);
      if (!b.enabled) return curve; // all zeros (0 dB)

      final filterType = _shapeToFilterType(b.shape);
      final isCut = b.shape == EqFilterShape.lowCut ||
                    b.shape == EqFilterShape.highCut ||
                    b.shape == EqFilterShape.brickwall;

      // Number of cascaded biquad stages for cut/shelf slopes
      final stages = isCut ? b.slope.stages : 1;

      // Calculate Butterworth Q values for cascaded stages
      final stageQs = _butterworthQs(stages, isCut ? null : b.q);

      for (int i = 0; i < n; i++) {
        double magDb = 0.0;
        for (int s = 0; s < stages; s++) {
          magDb += _biquadMagnitudeDb(
            filterType: filterType,
            freq: freqs[i],
            fc: b.freq,
            gain: b.gain,
            q: stageQs[s],
            sampleRate: sr,
            slopeDb: b.slope.dbPerOct.toDouble(),
          );
        }
        curve[i] = magDb;
      }
      return curve;
    });

    // Composite = sum of all band curves in dB
    final comp = Float64List(n);
    for (final bc in _bandCurves) {
      for (int i = 0; i < n; i++) {
        comp[i] += bc[i];
      }
    }
    _compositeCurve = comp;

    // E4.1: Phase response (sum of all band phases in radians → degrees)
    if (_showPhase) {
      final phase = Float64List(n);
      for (int bi = 0; bi < _bands.length; bi++) {
        final b = _bands[bi];
        if (!b.enabled) continue;
        final filterType = _shapeToFilterType(b.shape);
        final isCut = b.shape == EqFilterShape.lowCut || b.shape == EqFilterShape.highCut || b.shape == EqFilterShape.brickwall;
        final stages = isCut ? b.slope.stages : 1;
        final stageQs = _butterworthQs(stages, isCut ? null : b.q);
        for (int i = 0; i < n; i++) {
          for (int s = 0; s < stages; s++) {
            phase[i] += _biquadPhaseRad(
              filterType: filterType, freq: freqs[i], fc: b.freq,
              gain: b.gain, q: stageQs[s], sampleRate: sr, slopeDb: b.slope.dbPerOct.toDouble(),
            );
          }
        }
      }
      // Convert radians to degrees
      for (int i = 0; i < n; i++) {
        phase[i] = phase[i] * 180.0 / math.pi;
      }
      _phaseCurve = phase;
    }
  }

  /// Butterworth Q values for cascaded biquad stages.
  /// For N stages (each 2nd-order = 12dB/oct), total = N×12 dB/oct.
  /// Q_k = 1 / (2 * sin(π * (2k-1) / (2*N))) for k = 1..N
  static List<double> _butterworthQs(int stages, [double? overrideQ]) {
    if (stages == 1) return [overrideQ ?? 0.7071067811865476];
    final qs = <double>[];
    for (int k = 1; k <= stages; k++) {
      qs.add(1.0 / (2.0 * math.sin(math.pi * (2 * k - 1) / (2 * stages))));
    }
    return qs;
  }

  /// Evaluate a single biquad stage magnitude in dB at frequency [freq].
  /// Uses Audio EQ Cookbook formulas — matches DspFrequencyCalculator exactly.
  static double _biquadMagnitudeDb({
    required String filterType,
    required double freq,
    required double fc,
    required double gain,
    required double q,
    required double sampleRate,
    required double slopeDb,
  }) {
    final w0 = 2.0 * math.pi * fc / sampleRate;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final A = math.pow(10.0, gain / 40.0).toDouble();

    double alpha;
    if (filterType == 'lowshelf' || filterType == 'highshelf') {
      final S = slopeDb / 12.0;
      alpha = sinW0 / 2.0 * math.sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0);
    } else {
      alpha = sinW0 / (2.0 * q);
    }

    double b0, b1, b2, a0, a1, a2;
    switch (filterType) {
      case 'bell':
      case 'peaking':
        b0 = 1.0 + alpha * A;
        b1 = -2.0 * cosW0;
        b2 = 1.0 - alpha * A;
        a0 = 1.0 + alpha / A;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha / A;
      case 'lowshelf':
        final sqa = math.sqrt(A) * alpha;
        b0 = A * ((A + 1) - (A - 1) * cosW0 + 2 * sqa);
        b1 = 2 * A * ((A - 1) - (A + 1) * cosW0);
        b2 = A * ((A + 1) - (A - 1) * cosW0 - 2 * sqa);
        a0 = (A + 1) + (A - 1) * cosW0 + 2 * sqa;
        a1 = -2 * ((A - 1) + (A + 1) * cosW0);
        a2 = (A + 1) + (A - 1) * cosW0 - 2 * sqa;
      case 'highshelf':
        final sqa = math.sqrt(A) * alpha;
        b0 = A * ((A + 1) + (A - 1) * cosW0 + 2 * sqa);
        b1 = -2 * A * ((A - 1) + (A + 1) * cosW0);
        b2 = A * ((A + 1) + (A - 1) * cosW0 - 2 * sqa);
        a0 = (A + 1) - (A - 1) * cosW0 + 2 * sqa;
        a1 = 2 * ((A - 1) - (A + 1) * cosW0);
        a2 = (A + 1) - (A - 1) * cosW0 - 2 * sqa;
      case 'highpass': // lowCut
        b0 = (1 + cosW0) / 2;
        b1 = -(1 + cosW0);
        b2 = (1 + cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
      case 'lowpass': // highCut
        b0 = (1 - cosW0) / 2;
        b1 = 1 - cosW0;
        b2 = (1 - cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
      case 'notch':
        b0 = 1;
        b1 = -2 * cosW0;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
      case 'bandpass':
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
      case 'allpass':
        b0 = 1 - alpha;
        b1 = -2 * cosW0;
        b2 = 1 + alpha;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
      case 'tilt':
        final sqa = math.sqrt(A) * alpha;
        b0 = A * ((A + 1) + (A - 1) * cosW0 + 2 * sqa);
        b1 = -2 * A * ((A - 1) + (A + 1) * cosW0);
        b2 = A * ((A + 1) + (A - 1) * cosW0 - 2 * sqa);
        a0 = (A + 1) - (A - 1) * cosW0 + 2 * sqa;
        a1 = 2 * ((A - 1) - (A + 1) * cosW0);
        a2 = (A + 1) - (A - 1) * cosW0 - 2 * sqa;
      default:
        return 0.0;
    }

    // Normalize
    b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;

    // Evaluate |H(e^jω)| at freq
    final w = 2.0 * math.pi * freq / sampleRate;
    final cw = math.cos(w);
    final sw = math.sin(w);
    final c2w = math.cos(2 * w);
    final s2w = math.sin(2 * w);

    final nr = b0 + b1 * cw + b2 * c2w;
    final ni = -b1 * sw - b2 * s2w;
    final dr = 1.0 + a1 * cw + a2 * c2w;
    final di = -a1 * sw - a2 * s2w;

    final numMag = math.sqrt(nr * nr + ni * ni);
    final denMag = math.sqrt(dr * dr + di * di);
    final mag = denMag > 1e-10 ? numMag / denMag : numMag;
    return 20.0 * math.log(mag.clamp(1e-10, double.infinity)) / math.ln10;
  }

  /// E4.1: Evaluate biquad phase in radians at [freq].
  /// Uses same coefficient calculation as _biquadMagnitudeDb.
  static double _biquadPhaseRad({
    required String filterType,
    required double freq,
    required double fc,
    required double gain,
    required double q,
    required double sampleRate,
    required double slopeDb,
  }) {
    final w0 = 2.0 * math.pi * fc / sampleRate;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final A = math.pow(10.0, gain / 40.0).toDouble();

    double alpha;
    if (filterType == 'lowshelf' || filterType == 'highshelf') {
      final S = slopeDb / 12.0;
      alpha = sinW0 / 2.0 * math.sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0);
    } else {
      alpha = sinW0 / (2.0 * q);
    }

    double b0, b1, b2, a0, a1, a2;
    switch (filterType) {
      case 'bell' || 'peaking':
        b0 = 1.0 + alpha * A; b1 = -2.0 * cosW0; b2 = 1.0 - alpha * A;
        a0 = 1.0 + alpha / A; a1 = -2.0 * cosW0; a2 = 1.0 - alpha / A;
      case 'lowshelf':
        final sqa = math.sqrt(A) * alpha;
        b0 = A * ((A+1) - (A-1)*cosW0 + 2*sqa); b1 = 2*A*((A-1) - (A+1)*cosW0); b2 = A*((A+1) - (A-1)*cosW0 - 2*sqa);
        a0 = (A+1) + (A-1)*cosW0 + 2*sqa; a1 = -2*((A-1) + (A+1)*cosW0); a2 = (A+1) + (A-1)*cosW0 - 2*sqa;
      case 'highshelf':
        final sqa = math.sqrt(A) * alpha;
        b0 = A*((A+1) + (A-1)*cosW0 + 2*sqa); b1 = -2*A*((A-1) + (A+1)*cosW0); b2 = A*((A+1) + (A-1)*cosW0 - 2*sqa);
        a0 = (A+1) - (A-1)*cosW0 + 2*sqa; a1 = 2*((A-1) - (A+1)*cosW0); a2 = (A+1) - (A-1)*cosW0 - 2*sqa;
      case 'highpass':
        b0 = (1+cosW0)/2; b1 = -(1+cosW0); b2 = (1+cosW0)/2;
        a0 = 1+alpha; a1 = -2*cosW0; a2 = 1-alpha;
      case 'lowpass':
        b0 = (1-cosW0)/2; b1 = 1-cosW0; b2 = (1-cosW0)/2;
        a0 = 1+alpha; a1 = -2*cosW0; a2 = 1-alpha;
      case 'notch':
        b0 = 1; b1 = -2*cosW0; b2 = 1;
        a0 = 1+alpha; a1 = -2*cosW0; a2 = 1-alpha;
      case 'bandpass':
        b0 = alpha; b1 = 0; b2 = -alpha;
        a0 = 1+alpha; a1 = -2*cosW0; a2 = 1-alpha;
      case 'allpass':
        b0 = 1-alpha; b1 = -2*cosW0; b2 = 1+alpha;
        a0 = 1+alpha; a1 = -2*cosW0; a2 = 1-alpha;
      default:
        return 0.0;
    }
    b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;

    final w = 2.0 * math.pi * freq / sampleRate;
    final cw = math.cos(w);
    final sw = math.sin(w);
    final c2w = math.cos(2 * w);
    final s2w = math.sin(2 * w);
    final nr = b0 + b1 * cw + b2 * c2w;
    final ni = -b1 * sw - b2 * s2w;
    final dr = 1.0 + a1 * cw + a2 * c2w;
    final di = -a1 * sw - a2 * s2w;
    // Phase = arg(H) = atan2(numImag, numReal) - atan2(denImag, denReal)
    return math.atan2(ni, nr) - math.atan2(di, dr);
  }

  void _syncBand(int i) {
    if (_slotIndex < 0 || i >= _bands.length) return;
    final b = _bands[i];
    _setP(b.index, _P.freq, b.freq);
    _setP(b.index, _P.gain, b.gain);
    _setP(b.index, _P.q, b.q);
    _setP(b.index, _P.enabled, b.enabled ? 1.0 : 0.0);
    _setP(b.index, _P.shape, b.shape.index.toDouble());
    _setP(b.index, _P.placement, b.placement.index.toDouble());
    _setP(b.index, _P.dynEnabled, b.dynamicEnabled ? 1.0 : 0.0);
    _setP(b.index, _P.dynThreshold, b.dynamicThreshold);
    _setP(b.index, _P.dynRatio, b.dynamicRatio);
    _setP(b.index, _P.dynAttack, b.dynamicAttack);
    _setP(b.index, _P.dynRelease, b.dynamicRelease);
    _recalcCurves();
    widget.onSettingsChanged?.call();
  }

  void _removeBand(int i) {
    if (_slotIndex < 0 || i >= _bands.length) return;
    _pushUndo(); // E5.1
    _setP(_bands[i].index, _P.enabled, 0.0);
    setState(() {
      _bands.removeAt(i);
      _selectedBandIndex = _bands.isEmpty ? null : i.clamp(0, _bands.length - 1);
    });
    _recalcCurves();
    widget.onSettingsChanged?.call();
  }

  // E5.5/E5.6: Preset browser
  void _showPresetBrowser() {
    final categories = <String>{};
    for (final p in _factoryEqPresets) {
      categories.add(p.category);
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF121218),
        child: SizedBox(
          width: 320,
          height: 400,
          child: Column(children: [
            // Header
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
              ),
              child: Row(children: [
                const Text('EQ Presets', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const Spacer(),
                // Save current as preset
                GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _savePresetDialog();
                  },
                  child: const Text('Save Current', style: TextStyle(color: FabFilterColors.blue, fontSize: 10)),
                ),
              ]),
            ),
            // Preset list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(4),
                children: categories.expand((cat) => [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                    child: Text(cat, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                  ..._factoryEqPresets.where((p) => p.category == cat).map((p) =>
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(p.name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pushUndo();
                        _restoreSnapshot(p.snapshot);
                      },
                    ),
                  ),
                ]).toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _savePresetDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Save EQ Preset', style: TextStyle(color: Colors.white70, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(hintText: 'Preset name', hintStyle: TextStyle(color: Colors.white24)),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () { ctrl.dispose(); Navigator.of(ctx).pop(); }, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                // Save to factory list (in-memory for now — E5.7 will add JSON persistence)
                _factoryEqPresets.add(EqPreset(
                  name: ctrl.text.trim(),
                  category: 'Custom',
                  snapshot: _captureSnapshot(),
                ));
              }
              ctrl.dispose();
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // E5.7: Export EQ config to clipboard as JSON
  void _exportEqToClipboard() {
    final preset = EqPreset(
      name: 'Exported EQ',
      category: 'Export',
      snapshot: _captureSnapshot(),
    );
    final json = preset.toJson();
    // Simple JSON encoding (avoid import dart:convert just for this)
    final sb = StringBuffer('{"name":"${json['name']}","category":"${json['category']}",');
    sb.write('"outputGain":${json['outputGain']},"autoGain":${json['autoGain']},');
    sb.write('"globalPlacementIdx":${json['globalPlacementIdx']},"bandData":[');
    final bands = json['bandData'] as List;
    for (int i = 0; i < bands.length; i++) {
      if (i > 0) sb.write(',');
      final b = bands[i] as Map<String, dynamic>;
      sb.write('{');
      final entries = b.entries.toList();
      for (int j = 0; j < entries.length; j++) {
        if (j > 0) sb.write(',');
        final v = entries[j].value;
        if (v is String) {
          sb.write('"${entries[j].key}":"$v"');
        } else {
          sb.write('"${entries[j].key}":$v');
        }
      }
      sb.write('}');
    }
    sb.write(']}');
    Clipboard.setData(ClipboardData(text: sb.toString()));
    // Brief visual feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('EQ config copied to clipboard'),
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFF1A1A22),
      ),
    );
  }

  // E6: EQ Match panel
  Widget _buildMatchPanel() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A1A22))),
        color: Color(0xFF0D0D14),
      ),
      child: Row(children: [
        // E6.1: Capture reference
        FabTinyButton(
          label: _matchReference != null ? 'REF ✓' : 'Capture Ref',
          active: _matchReference != null,
          onTap: () => setState(() => _matchReference = List<double>.from(_spectrum)),
          color: FabFilterColors.green),
        const SizedBox(width: 4),
        // E6.2: Capture source
        FabTinyButton(
          label: _matchSource != null ? 'SRC ✓' : 'Capture Src',
          active: _matchSource != null,
          onTap: () => setState(() => _matchSource = List<double>.from(_spectrum)),
          color: FabFilterColors.cyan),
        const SizedBox(width: 8),
        // E6.4: Match amount slider
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: FabFilterColors.green,
              inactiveTrackColor: FabFilterColors.borderSubtle,
              thumbColor: FabFilterColors.green,
            ),
            child: Slider(
              value: _matchAmount,
              onChanged: (v) => setState(() => _matchAmount = v),
            ),
          ),
        ),
        Text('${(_matchAmount * 100).toInt()}%',
          style: const TextStyle(color: FabFilterColors.green, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        // E6.3: Apply match
        FabTinyButton(
          label: 'Apply',
          active: false,
          onTap: _matchReference != null && _matchSource != null ? _applyMatch : () {},
          color: FabFilterColors.blue),
      ]),
    );
  }

  // E6.3: Apply match — auto-generate bands from spectral difference
  void _applyMatch() {
    if (_matchReference == null || _matchSource == null) return;
    _pushUndo();
    final ref = _matchReference!;
    final src = _matchSource!;
    final len = math.min(ref.length, src.length);
    if (len < 4) return;

    // Calculate difference in 8 bands
    const numBands = 8;
    final bandSize = len ~/ numBands;
    for (int i = 0; i < numBands; i++) {
      double sumDiff = 0;
      for (int j = i * bandSize; j < (i + 1) * bandSize && j < len; j++) {
        sumDiff += ref[j] - src[j];
      }
      final avgDiff = sumDiff / bandSize;
      final gain = (avgDiff * _matchAmount).clamp(-12.0, 12.0);
      if (gain.abs() < 0.5) continue; // skip near-zero bands

      // Map band index to frequency
      final freq = 20.0 * math.pow(20000.0 / 20.0, (i + 0.5) / numBands);
      _addBand(freq, EqFilterShape.bell);
      if (_bands.isNotEmpty) {
        _bands.last.gain = gain;
        _bands.last.q = 1.0;
        _syncBand(_bands.length - 1);
      }
    }
  }

  // E8.4: Full-screen EQ display
  // ═══════════════════════════════════════════════════════════════════════════
  // E9.3: ROOM CORRECTION WIZARD
  // ═══════════════════════════════════════════════════════════════════════════

  void _startRoomCapture() {
    _ffi.roomCorrectionStartMeasurement(widget.trackId);
    setState(() { _roomCorrectionStep = 1; _roomCaptureProgress = 0.0; });
    // Capture for 5 seconds — feed spectrum data as measurement proxy
    _roomCaptureTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _roomCaptureProgress = (t.tick / 50).clamp(0.0, 1.0));
      if (t.tick >= 50) {
        t.cancel();
        _analyzeRoom();
      }
    });
  }

  void _analyzeRoom() {
    final modeCount = _ffi.roomCorrectionAnalyze(widget.trackId);
    if (modeCount < 0) return; // analysis failed
    _roomModes.clear();
    for (int i = 0; i < modeCount; i++) {
      final mode = _ffi.roomCorrectionGetMode(widget.trackId, i);
      if (mode != null) _roomModes.add(mode);
    }
    setState(() => _roomCorrectionStep = 2);
  }

  void _generateRoomCorrection() {
    final bandCount = _ffi.roomCorrectionGenerate(widget.trackId, _roomTargetCurve);
    setState(() {
      _roomCorrectionBands = bandCount;
      _roomCorrectionStep = 3;
    });
  }

  void _applyRoomCorrection() {
    _pushUndo();
    // Get correction curve and create EQ bands to compensate
    final curve = _ffi.roomCorrectionGetCurve(widget.trackId);
    if (curve == null || curve.isEmpty) return;
    // Sample correction at up to 10 frequency bands and create bell bands
    final numBands = curve.length < 10 ? curve.length : 10;
    final bandSize = curve.length ~/ numBands;
    if (bandSize < 1) return;
    for (int i = 0; i < numBands; i++) {
      double sum = 0;
      final end = (i * bandSize + bandSize).clamp(0, curve.length);
      for (int j = i * bandSize; j < end; j++) {
        sum += curve[j];
      }
      final avgDb = sum / bandSize;
      if (avgDb.abs() < 0.5) continue; // skip negligible correction
      final gain = avgDb.clamp(-12.0, 12.0);
      final freq = 20.0 * math.pow(20000.0 / 20.0, (i + 0.5) / numBands);
      _addBand(freq, EqFilterShape.bell);
      if (_bands.isNotEmpty) {
        _bands.last.gain = gain;
        _bands.last.q = 2.0; // moderate Q for room correction
        _syncBand(_bands.length - 1);
      }
    }
    _recalcCurves();
    setState(() => _roomCorrectionActive = false);
  }

  Widget _buildRoomCorrectionPanel() {
    final modeTypeNames = ['Axial', 'Tangential', 'Oblique'];
    final targetNames = ['Flat', 'Harman', 'B&K', 'BBC', 'X-Curve'];

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xDD0D0D18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FabFilterColors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.spatial_audio_off, size: 14, color: FabFilterColors.green),
            const SizedBox(width: 6),
            Text('ROOM CORRECTION', style: TextStyle(
              color: FabFilterColors.green, fontSize: 10,
              fontWeight: FontWeight.bold, letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _roomCorrectionActive = false),
              child: const Icon(Icons.close, size: 14, color: FabFilterColors.textTertiary)),
          ]),
          const SizedBox(height: 8),

          // Step 1: Capture
          if (_roomCorrectionStep == 0) ...[
            Text('Reproduce testni signal ili pink noise u prostoriji.',
              style: TextStyle(color: FabFilterColors.textSecondary, fontSize: 9)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _startRoomCapture,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: FabFilterColors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FabFilterColors.green)),
                child: Text('▶ CAPTURE (5s)', style: TextStyle(
                  color: FabFilterColors.green, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
          ],

          // Step 1b: Capturing...
          if (_roomCorrectionStep == 1) ...[
            Row(children: [
              Expanded(child: LinearProgressIndicator(
                value: _roomCaptureProgress,
                backgroundColor: const Color(0x22FFFFFF),
                valueColor: const AlwaysStoppedAnimation(FabFilterColors.green),
              )),
              const SizedBox(width: 8),
              Text('${(_roomCaptureProgress * 100).round()}%',
                style: TextStyle(color: FabFilterColors.green, fontSize: 9)),
            ]),
          ],

          // Step 2: Analyzed — show room modes
          if (_roomCorrectionStep == 2) ...[
            Text('Detektovano ${_roomModes.length} sobnih modova:',
              style: TextStyle(color: FabFilterColors.textSecondary, fontSize: 9)),
            const SizedBox(height: 4),
            if (_roomModes.isNotEmpty)
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _roomModes.length,
                  itemBuilder: (_, i) {
                    final m = _roomModes[i];
                    return Container(
                      width: 70, margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0x18FFFFFF),
                        borderRadius: BorderRadius.circular(4)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${m.freq.round()} Hz', style: TextStyle(
                            color: FabFilterColors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                          Text('${m.mag > 0 ? '+' : ''}${m.mag.toStringAsFixed(1)} dB',
                            style: TextStyle(
                              color: m.mag > 0 ? FabFilterColors.orange : FabFilterColors.cyan,
                              fontSize: 8)),
                          Text('Q:${m.q.toStringAsFixed(1)} ${modeTypeNames[m.type_.clamp(0, 2)]}',
                            style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 7)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            // Target curve picker
            Row(children: [
              Text('Target: ', style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 8)),
              ...List.generate(5, (i) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _roomTargetCurve = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: _roomTargetCurve == i
                          ? FabFilterColors.green.withValues(alpha: 0.3) : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: _roomTargetCurve == i
                          ? FabFilterColors.green : FabFilterColors.border)),
                    child: Text(targetNames[i], style: TextStyle(
                      color: _roomTargetCurve == i ? FabFilterColors.green : FabFilterColors.textTertiary,
                      fontSize: 7, fontWeight: FontWeight.bold)),
                  ),
                ),
              )),
            ]),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _generateRoomCorrection,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: FabFilterColors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FabFilterColors.green)),
                child: Text('GENERATE CORRECTION', style: TextStyle(
                  color: FabFilterColors.green, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
          ],

          // Step 3: Correction generated — apply
          if (_roomCorrectionStep == 3) ...[
            Text('Generisano $_roomCorrectionBands korekcijskih bandova.',
              style: TextStyle(color: FabFilterColors.green, fontSize: 9)),
            const SizedBox(height: 6),
            Row(children: [
              GestureDetector(
                onTap: _applyRoomCorrection,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: FabFilterColors.green.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FabFilterColors.green)),
                  child: Text('APPLY TO EQ', style: TextStyle(
                    color: FabFilterColors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _roomCorrectionStep = 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FabFilterColors.border)),
                  child: Text('RETRY', style: TextStyle(
                    color: FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  void _showFullscreen(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black87,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF08080C),
        child: Stack(children: [
          FabFilterEqPanel(
            trackId: widget.trackId,
            slotIndex: widget.slotIndex,
            sampleRate: widget.sampleRate,
            onSettingsChanged: widget.onSettingsChanged,
          ),
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0x44FFFFFF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.fullscreen_exit, size: 18, color: Colors.white70),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // E5.4: Bypass bands by shape type
  void _bypassByShape(Set<EqFilterShape> shapes) {
    _pushUndo();
    setState(() {
      for (final b in _bands) {
        if (shapes.contains(b.shape)) {
          b.enabled = false;
          _setP(b.index, _P.enabled, 0.0);
        }
      }
    });
    _recalcCurves();
  }

  void _enableAllBands() {
    _pushUndo();
    setState(() {
      for (final b in _bands) {
        b.enabled = true;
        _setP(b.index, _P.enabled, 1.0);
      }
    });
    _recalcCurves();
  }

  void _resetEq() {
    if (_slotIndex < 0) return;
    _pushUndo(); // E5.1
    for (int i = 0; i < 64; i++) {
      _setP(i, _P.enabled, 0.0);
      _setP(i, _P.gain, 0.0);
    }
    setState(() {
      _bands.clear();
      _selectedBandIndex = null;
      _outputGain = 0.0;
    });
    _recalcCurves();
    _ffi.insertSetParam(widget.trackId, _slotIndex, _P.outputGainIndex, 0.0);
    widget.onSettingsChanged?.call();
  }

  void _setP(int bandIdx, int paramIdx, double val) {
    if (_slotIndex < 0) return;
    _ffi.insertSetParam(widget.trackId, _slotIndex, bandIdx * _P.paramsPerBand + paramIdx, val);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static double _freqToX(double f, double w) {
    const lo = 1.0, hi = 4.477;
    return ((math.log(f.clamp(10, 30000)) / math.ln10 - lo) / (hi - lo)) * w;
  }
  static double _xToFreq(double x, double w) {
    const lo = 1.0, hi = 4.477;
    return math.pow(10, lo + (x / w) * (hi - lo)).toDouble();
  }
  double _gainToY(double g, double h) => h / 2 - (g / _gainScale) * (h / 2);
  double _yToGain(double y, double h) => ((h / 2 - y) / (h / 2)) * _gainScale;

  double _freqToNorm(double f) => (math.log(f.clamp(10, 30000) / 10) / math.log(30000 / 10)).clamp(0.0, 1.0);
  double _normToFreq(double n) => (10 * math.pow(30000 / 10, n)).toDouble();

  String _fmtFreq(double f) => f >= 1000
      ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)}k'
      : '${f.toInt()}';

  static Color _shapeColor(EqFilterShape s) => switch (s) {
    EqFilterShape.bell => FabFilterColors.blue,
    EqFilterShape.lowShelf => FabFilterColors.orange,
    EqFilterShape.highShelf => FabFilterColors.yellow,
    EqFilterShape.lowCut || EqFilterShape.highCut || EqFilterShape.brickwall => FabFilterColors.red,
    EqFilterShape.notch => FabFilterColors.pink,
    EqFilterShape.bandPass => FabFilterColors.green,
    EqFilterShape.tiltShelf => FabFilterColors.cyan,
    EqFilterShape.allPass => FabFilterColors.textTertiary,
  };

  /// E8.2: Frequency-based color (spectral rainbow: red→orange→yellow→green→cyan→blue→purple)
  static Color _freqColor(double freq) {
    // Map 20Hz-20kHz log scale to 0.0-1.0
    final t = ((math.log(freq.clamp(20, 20000)) / math.ln10 - 1.301) / (4.301 - 1.301)).clamp(0.0, 1.0);
    // HSV hue: 0° (red, low freq) → 270° (purple, high freq)
    return HSVColor.fromAHSV(1.0, t * 270.0, 0.8, 0.9).toColor();
  }

  static EqFilterShape _intToShape(int v) => v >= 0 && v < EqFilterShape.values.length
      ? EqFilterShape.values[v] : EqFilterShape.bell;
  static EqPlacement _intToPlacement(int v) => v >= 0 && v < EqPlacement.values.length
      ? EqPlacement.values[v] : EqPlacement.stereo;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIANO KEYBOARD STRIP — frequency reference
// ═══════════════════════════════════════════════════════════════════════════════

class _PianoStripPainter extends CustomPainter {
  static const _blackNotes = {1, 3, 6, 8, 10};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = FabFilterColors.bgMid);

    final whitePaint = Paint()..color = const Color(0xFFD0D0D8);
    final blackPaint = Paint()..color = const Color(0xFF252530);
    final cPaint = Paint()..color = FabFilterColors.blue.withValues(alpha: 0.35);
    final borderP = Paint()
      ..color = FabFilterColors.borderSubtle
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int octave = 1; octave <= 8; octave++) {
      for (int note = 0; note < 12; note++) {
        if (octave == 8 && note > 0) break;
        final freq = 440.0 * math.pow(2, (octave - 4) + (note - 9) / 12.0);
        if (freq < 10 || freq > 30000) continue;
        final x = _freqToX(freq, size.width);
        final nextFreq = 440.0 * math.pow(2, (octave - 4) + (note - 8) / 12.0);
        final nextX = _freqToX(nextFreq.clamp(10, 30000), size.width);
        final w = (nextX - x).clamp(1.0, 30.0);

        final isBlack = _blackNotes.contains(note);
        if (isBlack) {
          canvas.drawRect(Rect.fromLTWH(x, 0, w * 0.6, size.height * 0.55), blackPaint);
        } else {
          final paint = note == 0 ? cPaint : whitePaint;
          canvas.drawRect(Rect.fromLTWH(x, size.height * 0.35, w, size.height * 0.65), paint);
          canvas.drawRect(Rect.fromLTWH(x, size.height * 0.35, w, size.height * 0.65), borderP);
        }
      }
    }

    // Octave labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int oct = 2; oct <= 7; oct++) {
      final freq = 440.0 * math.pow(2, (oct - 4) + (-9) / 12.0); // C note
      final x = _freqToX(freq, size.width);
      tp.text = TextSpan(
        text: 'C$oct',
        style: const TextStyle(color: FabFilterColors.textDisabled, fontSize: 6),
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 1, 0));
    }
  }

  static double _freqToX(double f, double w) {
    const lo = 1.0, hi = 4.477;
    return ((math.log(f.clamp(10, 30000)) / math.ln10 - lo) / (hi - lo)) * w;
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// EQ DISPLAY PAINTER — Pro-Q 3 Style: Spectrum + Curve + Nodes
// ═══════════════════════════════════════════════════════════════════════════════

class _EqDisplayPainter extends CustomPainter {
  final List<EqBand> bands;
  final int? selectedIdx;
  final int? hoverIdx;
  final List<double> spectrum;
  final List<double> peakHold;
  final bool analyzerOn;
  final Offset? previewPos;
  final bool isDragging;
  /// Pre-calculated per-band magnitude curves (dB), 512 points each.
  final List<Float64List> bandCurves;
  /// Pre-calculated composite magnitude curve (dB), 512 points.
  final Float64List compositeCurve;
  /// Log-spaced frequency array corresponding to curve points.
  final Float64List curveFrequencies;
  /// Gain display scale in dB (E7.5)
  final double gainScale;
  /// E2.4: Frozen spectrum snapshot
  final List<double> frozenSpectrum;
  /// E4.1: Phase curve in degrees
  final Float64List? phaseCurve;
  /// E4.2: Show group delay
  final bool showGroupDelay;
  /// E8.2: Color by frequency
  final bool freqColorMode;
  /// E2.1: Pre-EQ spectrum overlay
  final List<double> preSpectrum;
  /// E8.3: Waterfall/sonogram buffer
  final List<List<double>> waterfallBuffer;
  /// E7.2: Solo band index for spectrum coloring (-1 = none)
  final int soloBandIdx;

  _EqDisplayPainter({
    required this.bands,
    required this.selectedIdx,
    required this.hoverIdx,
    required this.spectrum,
    required this.peakHold,
    required this.analyzerOn,
    required this.previewPos,
    required this.isDragging,
    required this.bandCurves,
    required this.compositeCurve,
    required this.curveFrequencies,
    this.gainScale = 30.0,
    this.frozenSpectrum = const [],
    this.phaseCurve,
    this.showGroupDelay = false,
    this.freqColorMode = false,
    this.preSpectrum = const [],
    this.waterfallBuffer = const [],
    this.soloBandIdx = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0D0D12), Color(0xFF08080C)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    _drawGrid(canvas, size);
    if (analyzerOn && spectrum.isNotEmpty) _drawSpectrum(canvas, size);
    if (waterfallBuffer.isNotEmpty) _drawWaterfall(canvas, size);
    _drawEqCurve(canvas, size);
    if (phaseCurve != null) _drawPhaseCurve(canvas, size);
    if (showGroupDelay && phaseCurve != null) _drawGroupDelay(canvas, size);
    if (previewPos != null && !isDragging) _drawPreview(canvas, previewPos!);
    _drawNodes(canvas, size);
    _drawFreqAxis(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final thinP = Paint()..color = const Color(0xFF1A1A22)..strokeWidth = 0.5;
    final medP = Paint()..color = const Color(0xFF222230)..strokeWidth = 0.5;

    // Frequency grid lines
    for (final f in [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]) {
      final x = _fx(f, size.width);
      final isMajor = f == 100 || f == 1000 || f == 10000;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), isMajor ? medP : thinP);
    }

    // 0 dB center line
    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy),
      Paint()..color = const Color(0xFF2A2A38)..strokeWidth = 1);

    // dB grid lines + labels — adapt to gain scale
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final gridStep = gainScale <= 12 ? 3.0 : 6.0;
    for (double db = -gainScale + gridStep; db < gainScale; db += gridStep) {
      if (db == 0) continue;
      final y = cy - (db / gainScale) * cy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thinP);
    }
    // dB labels on left edge
    final labelStep = gainScale <= 12 ? 6 : 12;
    for (int db = -(gainScale.toInt()); db <= gainScale.toInt(); db += labelStep) {
      final y = cy - (db / gainScale) * cy;
      tp.text = TextSpan(
        text: '${db > 0 ? '+' : ''}$db',
        style: TextStyle(
          color: db == 0 ? const Color(0xFF555568) : const Color(0xFF333344),
          fontSize: 8,
          fontWeight: db == 0 ? FontWeight.bold : FontWeight.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(3, y - tp.height / 2));
    }
  }

  void _drawFreqAxis(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final labels = {
      20.0: '20', 50.0: '50', 100.0: '100', 200.0: '200', 500.0: '500',
      1000.0: '1k', 2000.0: '2k', 5000.0: '5k', 10000.0: '10k', 20000.0: '20k',
    };
    for (final e in labels.entries) {
      final x = _fx(e.key, size.width);
      final isMajor = e.key == 100 || e.key == 1000 || e.key == 10000;
      tp.text = TextSpan(
        text: e.value,
        style: TextStyle(
          color: isMajor ? const Color(0xFF555568) : const Color(0xFF333344),
          fontSize: 7,
          fontWeight: isMajor ? FontWeight.bold : FontWeight.normal,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height - 1));
    }
  }

  void _drawSpectrum(Canvas canvas, Size size) {
    if (spectrum.length < 2) return;
    // Frequency-proportional smoothing
    final smoothed = List<double>.from(spectrum);
    for (int pass = 0; pass < 2; pass++) {
      final prev = List<double>.from(smoothed);
      for (int i = 1; i < smoothed.length - 1; i++) {
        final r = i / smoothed.length;
        final rad = r < 0.25 ? 5 : (r < 0.5 ? 3 : 1);
        double sum = 0; int cnt = 0;
        for (int j = -rad; j <= rad; j++) {
          sum += prev[(i + j).clamp(0, prev.length - 1)];
          cnt++;
        }
        smoothed[i] = sum / cnt;
      }
    }

    // Catmull-Rom spline
    final pts = <Offset>[];
    for (int i = 0; i < smoothed.length; i++) {
      final x = (i / (smoothed.length - 1)) * size.width;
      final y = size.height - ((smoothed[i].clamp(-80.0, 0.0) + 80) / 80) * size.height;
      pts.add(Offset(x, y));
    }

    final curve = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i]; final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      curve.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx, p2.dy,
      );
    }

    // E7.2: Solo band spectrum coloring — yellow when solo active
    final isSolo = soloBandIdx >= 0;
    final specFillColors = isSolo
        ? [const Color(0x40FFD700), const Color(0x18FFD700), const Color(0x05FFD700)]
        : [const Color(0x404A9EFF), const Color(0x184A9EFF), const Color(0x054A9EFF)];
    final specLineColor = isSolo ? const Color(0x88FFD700) : const Color(0x884A9EFF);

    // Spectrum fill gradient
    final fill = Path()..addPath(curve, Offset.zero)
      ..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(fill, Paint()..shader = ui.Gradient.linear(
      Offset(0, 0), Offset(0, size.height),
      specFillColors,
      [0.0, 0.5, 1.0],
    ));

    // Spectrum line
    canvas.drawPath(curve, Paint()
      ..color = specLineColor
      ..strokeWidth = isSolo ? 1.6 : 1.2
      ..style = PaintingStyle.stroke);

    // E7.2: Solo label when active
    if (isSolo) {
      final tp = TextPainter(
        text: TextSpan(text: 'SOLO SPECTRUM', style: TextStyle(
          color: const Color(0xCCFFD700), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 8, 6));
    }

    // Peak hold thin line
    if (peakHold.length > 1 && peakHold.length == smoothed.length) {
      final peakPath = Path();
      for (int i = 0; i < peakHold.length; i++) {
        final x = (i / (peakHold.length - 1)) * size.width;
        final y = size.height - ((peakHold[i].clamp(-80.0, 0.0) + 80) / 80) * size.height;
        i == 0 ? peakPath.moveTo(x, y) : peakPath.lineTo(x, y);
      }
      canvas.drawPath(peakPath, Paint()
        ..color = const Color(0x444A9EFF)
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke);
    }

    // E2.4: Frozen spectrum overlay (white dashed)
    if (frozenSpectrum.length > 1) {
      final frozenPath = Path();
      for (int i = 0; i < frozenSpectrum.length; i++) {
        final x = (i / (frozenSpectrum.length - 1)) * size.width;
        final y = size.height - ((frozenSpectrum[i].clamp(-80.0, 0.0) + 80) / 80) * size.height;
        i == 0 ? frozenPath.moveTo(x, y) : frozenPath.lineTo(x, y);
      }
      canvas.drawPath(frozenPath, Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke);
    }

    // E2.1: Pre-EQ spectrum overlay (green dashed)
    if (preSpectrum.length > 1) {
      final prePath = Path();
      for (int i = 0; i < preSpectrum.length; i++) {
        final x = (i / (preSpectrum.length - 1)) * size.width;
        final y = size.height - ((preSpectrum[i].clamp(-80.0, 0.0) + 80) / 80) * size.height;
        i == 0 ? prePath.moveTo(x, y) : prePath.lineTo(x, y);
      }
      canvas.drawPath(prePath, Paint()
        ..color = const Color(0x6640CC80)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke);
    }
  }

  /// E8.3: Spectrum waterfall/sonogram — 2D spectrogram (time × freq × amplitude as color)
  void _drawWaterfall(Canvas canvas, Size size) {
    if (waterfallBuffer.isEmpty) return;
    final numFrames = waterfallBuffer.length;
    // Render in bottom 40% of display as a semi-transparent overlay
    final wfHeight = size.height * 0.4;
    final wfTop = size.height - wfHeight;
    final rowH = wfHeight / numFrames;

    for (int row = 0; row < numFrames; row++) {
      final frame = waterfallBuffer[row];
      if (frame.isEmpty) continue;
      final y = wfTop + row * rowH;

      if (frame.length < 2) continue;
      for (int col = 0; col < frame.length; col++) {
        final x = (col / (frame.length - 1)) * size.width;
        final nextX = ((col + 1) / (frame.length - 1)) * size.width;
        // Map dB (-80..0) to intensity (0..1)
        final intensity = ((frame[col] + 80) / 80).clamp(0.0, 1.0);
        if (intensity < 0.02) continue; // skip silent bins for performance

        // HSV heatmap: blue(240°) → cyan(180°) → green(120°) → yellow(60°) → red(0°)
        final hue = (1.0 - intensity) * 240.0;
        final color = HSVColor.fromAHSV(
          intensity * 0.6, // alpha fades with intensity
          hue, 0.9, 0.5 + intensity * 0.5,
        ).toColor();

        canvas.drawRect(
          Rect.fromLTRB(x, y, nextX + 0.5, y + rowH + 0.5),
          Paint()..color = color,
        );
      }
    }

    // Border line between waterfall and main display
    canvas.drawLine(
      Offset(0, wfTop), Offset(size.width, wfTop),
      Paint()..color = const Color(0x44FFFFFF)..strokeWidth = 0.5,
    );
  }

  void _drawEqCurve(Canvas canvas, Size size) {
    if (bands.isEmpty && compositeCurve.every((v) => v == 0)) return;
    final cy = size.height / 2;
    final n = compositeCurve.length;

    // Helper: interpolate dB from cached curve at pixel x position
    double _interpolateDb(Float64List curve, double freq) {
      // Binary search in curveFrequencies
      int lo = 0, hi = n - 1;
      if (freq <= curveFrequencies[0]) return curve[0];
      if (freq >= curveFrequencies[n - 1]) return curve[n - 1];
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (curveFrequencies[mid] <= freq) { lo = mid; } else { hi = mid; }
      }
      final denom = curveFrequencies[hi] - curveFrequencies[lo];
      final t = denom > 0 ? (freq - curveFrequencies[lo]) / denom : 0.0;
      return curve[lo] + (curve[hi] - curve[lo]) * t;
    }

    // Draw composite curve from cached data
    final path = Path();
    for (int px = 0; px <= size.width.toInt(); px++) {
      final f = _xf(px.toDouble(), size.width);
      final db = _interpolateDb(compositeCurve, f);
      final y = (cy - (db / gainScale) * cy).clamp(0.0, size.height);
      px == 0 ? path.moveTo(px.toDouble(), y) : path.lineTo(px.toDouble(), y);
    }

    // Fill with dual-tone gradient: boost(warm) above 0dB, cut(cool) below
    final fillPath = Path.from(path)..lineTo(size.width, cy)..lineTo(0, cy)..close();
    canvas.drawPath(fillPath, Paint()..shader = ui.Gradient.linear(
      Offset(0, 0), Offset(0, size.height),
      [
        const Color(0x20FF9040), // warm boost above
        const Color(0x00000000),
        const Color(0x2040C8FF), // cool cut below
      ],
      [0.0, 0.5, 1.0],
    ));

    // Individual band contribution curves (subtle, per-band color)
    for (int bi = 0; bi < bands.length; bi++) {
      final b = bands[bi];
      if (!b.enabled) continue;
      final isSel = bi == selectedIdx;
      final isHov = bi == hoverIdx;
      if (!isSel && !isHov) continue;
      if (bi >= bandCurves.length) continue;
      final bPath = Path();
      for (int px = 0; px <= size.width.toInt(); px += 2) {
        final f = _xf(px.toDouble(), size.width);
        final bdb = _interpolateDb(bandCurves[bi], f);
        final y = (cy - (bdb / gainScale) * cy).clamp(0.0, size.height);
        px == 0 ? bPath.moveTo(px.toDouble(), y) : bPath.lineTo(px.toDouble(), y);
      }
      final bFill = Path.from(bPath)..lineTo(size.width, cy)..lineTo(0, cy)..close();
      final bc = freqColorMode ? _FabFilterEqPanelState._freqColor(b.freq) : _shapeColor(b.shape);
      canvas.drawPath(bFill, Paint()..color = bc.withValues(alpha: isSel ? 0.12 : 0.06));
      canvas.drawPath(bPath, Paint()
        ..color = bc.withValues(alpha: isSel ? 0.5 : 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // Main composite curve stroke — bright white-tinted
    canvas.drawPath(path, Paint()
      ..color = const Color(0xDDE0E0F0)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);
  }

  // E4.1: Phase response curve (orange, ±180°)
  void _drawPhaseCurve(Canvas canvas, Size size) {
    final pc = phaseCurve;
    if (pc == null || pc.isEmpty) return;
    final cy = size.height / 2;
    final n = pc.length;

    final path = Path();
    for (int px = 0; px <= size.width.toInt(); px += 2) {
      final f = _xf(px.toDouble(), size.width);
      // Interpolate phase from cached curve
      int lo = 0, hi = n - 1;
      if (f <= curveFrequencies[0]) { lo = 0; hi = 0; }
      else if (f >= curveFrequencies[n - 1]) { lo = n - 1; hi = n - 1; }
      else {
        while (hi - lo > 1) {
          final mid = (lo + hi) ~/ 2;
          if (curveFrequencies[mid] <= f) { lo = mid; } else { hi = mid; }
        }
      }
      final t = hi == lo ? 0.0 : (f - curveFrequencies[lo]) / (curveFrequencies[hi] - curveFrequencies[lo]);
      final deg = pc[lo] + (pc[hi] - pc[lo]) * t;
      // Map ±180° to display height
      final y = (cy - (deg / 180.0) * cy).clamp(0.0, size.height);
      px == 0 ? path.moveTo(px.toDouble(), y) : path.lineTo(px.toDouble(), y);
    }
    canvas.drawPath(path, Paint()
      ..color = const Color(0xAAFF8C40)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke);

    // Phase axis labels (right side)
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final deg in [-180, -90, 0, 90, 180]) {
      final y = cy - (deg / 180.0) * cy;
      tp.text = TextSpan(
        text: '${deg}°',
        style: const TextStyle(color: Color(0x66FF8C40), fontSize: 7),
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width - tp.width - 3, y - tp.height / 2));
    }
  }

  // E4.2: Group delay (green, derived from phase)
  void _drawGroupDelay(Canvas canvas, Size size) {
    final pc = phaseCurve;
    if (pc == null || pc.length < 3) return;
    final cy = size.height / 2;
    final n = pc.length;

    // Group delay = -dφ/dω, approximate via finite differences
    // Convert degrees back to radians for derivative, then to ms
    final path = Path();
    double maxGd = 0.01;
    final gdValues = <double>[];
    for (int i = 1; i < n - 1; i++) {
      final dPhase = (pc[i + 1] - pc[i - 1]) * math.pi / 180.0; // radians
      final dOmega = 2.0 * math.pi * (curveFrequencies[i + 1] - curveFrequencies[i - 1]);
      final gd = dOmega > 0 ? -dPhase / dOmega * 1000.0 : 0.0; // ms
      gdValues.add(gd);
      if (gd.abs() > maxGd) maxGd = gd.abs();
    }
    // Normalize to display height
    for (int i = 0; i < gdValues.length; i++) {
      final px = _fx(curveFrequencies[i + 1], size.width);
      final y = (cy - (gdValues[i] / maxGd) * cy * 0.8).clamp(0.0, size.height);
      i == 0 ? path.moveTo(px, y) : path.lineTo(px, y);
    }
    canvas.drawPath(path, Paint()
      ..color = const Color(0xAA40CC80)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke);
  }

  void _drawPreview(Canvas canvas, Offset pos) {
    final c = FabFilterColors.blue.withValues(alpha: 0.3);
    canvas.drawLine(Offset(pos.dx, 0), Offset(pos.dx, 9999), Paint()..color = c..strokeWidth = 0.5);
    canvas.drawLine(Offset(0, pos.dy), Offset(9999, pos.dy), Paint()..color = c..strokeWidth = 0.5);
    canvas.drawCircle(pos, 5, Paint()..color = c);
    canvas.drawCircle(pos, 5, Paint()
      ..color = FabFilterColors.blue.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  void _drawNodes(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < bands.length; i++) {
      final b = bands[i];
      if (!b.enabled) continue;
      final x = _fx(b.freq, size.width);
      final y = (cy - (b.gain / gainScale) * cy).clamp(6.0, size.height - 6);
      final c = freqColorMode ? _FabFilterEqPanelState._freqColor(b.freq) : _shapeColor(b.shape);
      final sel = i == selectedIdx;
      final hov = i == hoverIdx;
      final r = sel ? 8.0 : (hov ? 7.0 : 5.0);

      // ─── Q ring visualization (Pro-Q style bandwidth indicator) ─────
      if (sel || hov) {
        // Bandwidth edges: f_low = f / k, f_high = f * k, where k = 2^(1/(2*Q))
        final q = b.q.clamp(0.05, 50.0);
        final k = math.pow(2, 1 / (2 * q));
        final fLow = b.freq / k;
        final fHigh = b.freq * k;
        final xLow = _fx(fLow, size.width);
        final xHigh = _fx(fHigh, size.width);
        final qWidth = (xHigh - xLow).abs();

        // Only draw Q ring for shapes that have meaningful Q
        final hasQ = b.shape == EqFilterShape.bell ||
            b.shape == EqFilterShape.notch ||
            b.shape == EqFilterShape.bandPass ||
            b.shape == EqFilterShape.allPass;
        if (hasQ && qWidth > 4) {
          // Elliptical Q ring — horizontal radius = bandwidth, vertical = proportional
          final rx = qWidth / 2;
          final ry = (rx * 0.6).clamp(12.0, size.height * 0.4);
          final ringRect = Rect.fromCenter(
            center: Offset(x, y),
            width: rx * 2,
            height: ry * 2,
          );
          // Fill
          canvas.drawOval(ringRect, Paint()
            ..color = c.withValues(alpha: sel ? 0.08 : 0.04));
          // Stroke
          canvas.drawOval(ringRect, Paint()
            ..color = c.withValues(alpha: sel ? 0.35 : 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 1.2 : 0.8);
        }
      }

      // E8.6: Audio-reactive glow — node glows proportional to energy at band frequency
      if (analyzerOn && spectrum.isNotEmpty) {
        final binIdx = ((math.log(b.freq.clamp(20, 20000)) / math.ln10 - 1.301) / (4.301 - 1.301) * (spectrum.length - 1)).round().clamp(0, spectrum.length - 1);
        final energy = ((spectrum[binIdx] + 80) / 80).clamp(0.0, 1.0); // 0=silent, 1=full
        if (energy > 0.1) {
          canvas.drawCircle(Offset(x, y), r + 8 + energy * 6, Paint()
            ..color = c.withValues(alpha: energy * 0.25)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + energy * 4));
        }
      }

      // Outer glow
      if (sel || hov) {
        canvas.drawCircle(Offset(x, y), r + 6, Paint()
          ..color = c.withValues(alpha: sel ? 0.2 : 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }

      // Node body — glass effect
      canvas.drawCircle(Offset(x, y), r, Paint()
        ..shader = ui.Gradient.radial(
          Offset(x - r * 0.3, y - r * 0.3), r * 1.5,
          [c.withValues(alpha: 0.9), c.withValues(alpha: 0.5)],
        ));

      // Node border
      if (sel) {
        canvas.drawCircle(Offset(x, y), r + 1.5, Paint()
          ..color = FabFilterColors.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      } else if (hov) {
        canvas.drawCircle(Offset(x, y), r + 1, Paint()
          ..color = c.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
      }

      // Highlight dot
      canvas.drawCircle(Offset(x - r * 0.25, y - r * 0.25), r * 0.25,
        Paint()..color = Colors.white.withValues(alpha: 0.4));

      // E3.6: Band number label on node
      if (r >= 7.0) {
        // Show band number on selected/hovered nodes
        tp.text = TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 7,
            fontWeight: FontWeight.bold,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
      }

      // E3.7: Slope label for cut filters (on selected/hovered)
      if ((sel || hov) && (b.shape == EqFilterShape.lowCut ||
          b.shape == EqFilterShape.highCut || b.shape == EqFilterShape.brickwall)) {
        final slopeLbl = b.slope.label;
        tp.text = TextSpan(
          text: '$slopeLbl dB',
          style: TextStyle(
            color: c.withValues(alpha: 0.7),
            fontSize: 7,
            fontWeight: FontWeight.bold,
          ),
        );
        tp.layout();
        final sx = b.shape == EqFilterShape.lowCut ? x + r + 4 : x - r - tp.width - 4;
        tp.paint(canvas, Offset(sx, y + r + 2));
      }

      // Dynamic EQ indicator
      if (b.dynamicEnabled) {
        canvas.drawCircle(Offset(x, y - r - 5), 2.5, Paint()..color = FabFilterColors.yellow);
      }
      // Solo indicator
      if (b.solo) {
        canvas.drawCircle(Offset(x + r + 4, y - r - 2), 2.5, Paint()..color = FabFilterColors.yellow);
      }

      // Info tooltip on hover/drag
      if ((sel && isDragging) || hov) {
        final freqTxt = b.freq >= 1000
            ? '${(b.freq / 1000).toStringAsFixed(b.freq >= 10000 ? 0 : 1)} kHz'
            : '${b.freq.toInt()} Hz';
        final gainTxt = '${b.gain >= 0 ? '+' : ''}${b.gain.toStringAsFixed(1)} dB';
        tp.text = TextSpan(
          text: '$freqTxt  $gainTxt',
          style: TextStyle(
            color: c, fontSize: 9, fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
        tp.layout();
        final tx = (x - tp.width / 2).clamp(2.0, size.width - tp.width - 2);
        final ty = y < 30 ? y + r + 6 : y - r - tp.height - 6;

        // Tooltip background
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(tx - 4, ty - 2, tp.width + 8, tp.height + 4),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, Paint()..color = const Color(0xDD121218));
        canvas.drawRRect(rect, Paint()
          ..color = c.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
        tp.paint(canvas, Offset(tx, ty));
      }
    }

    // E7.3: Collision detection — orange dot between overlapping bands
    final enabledBands = <int>[];
    for (int i = 0; i < bands.length; i++) {
      if (bands[i].enabled) enabledBands.add(i);
    }
    for (int a = 0; a < enabledBands.length; a++) {
      for (int b = a + 1; b < enabledBands.length; b++) {
        final ba = bands[enabledBands[a]], bb = bands[enabledBands[b]];
        // Check if within 1/3 octave of each other
        final ratio = ba.freq > bb.freq ? ba.freq / bb.freq : bb.freq / ba.freq;
        if (ratio < 1.26) { // ~1/3 octave
          final mx = _fx((ba.freq + bb.freq) / 2, size.width);
          final ya = cy - (ba.gain / gainScale) * cy;
          final yb = cy - (bb.gain / gainScale) * cy;
          final my = (ya + yb) / 2;
          canvas.drawCircle(Offset(mx, my), 3.5, Paint()
            ..color = const Color(0xCCFF8C00)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
          canvas.drawCircle(Offset(mx, my), 2, Paint()
            ..color = const Color(0xFFFF8C00));
        }
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static double _fx(double f, double w) {
    const lo = 1.0, hi = 4.477;
    return ((math.log(f.clamp(10, 30000)) / math.ln10 - lo) / (hi - lo)) * w;
  }
  static double _xf(double x, double w) {
    const lo = 1.0, hi = 4.477;
    return math.pow(10, lo + (x / w) * (hi - lo)).toDouble();
  }

  static Color _shapeColor(EqFilterShape s) => _FabFilterEqPanelState._shapeColor(s);

  @override
  bool shouldRepaint(covariant _EqDisplayPainter old) =>
    bands != old.bands || selectedIdx != old.selectedIdx || hoverIdx != old.hoverIdx ||
    spectrum != old.spectrum || peakHold != old.peakHold || analyzerOn != old.analyzerOn ||
    previewPos != old.previewPos || isDragging != old.isDragging ||
    !identical(compositeCurve, old.compositeCurve) ||
    !identical(bandCurves, old.bandCurves) ||
    !identical(curveFrequencies, old.curveFrequencies) ||
    gainScale != old.gainScale ||
    frozenSpectrum != old.frozenSpectrum ||
    phaseCurve != old.phaseCurve ||
    showGroupDelay != old.showGroupDelay ||
    freqColorMode != old.freqColorMode ||
    preSpectrum != old.preSpectrum ||
    waterfallBuffer != old.waterfallBuffer ||
    soloBandIdx != old.soloBandIdx;
}
