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
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
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

enum EqSlope { db6, db12, db18, db24, db36, db48, db72, db96, brickwall }

// ═══════════════════════════════════════════════════════════════════════════════
// EQ BAND MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class EqBand {
  int index;
  double freq;
  double gain;
  double q;
  EqFilterShape shape;
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

  // Interaction
  bool _isDragging = false;
  Offset? _previewPos;
  Offset? _doubleTapPos;

  // Metering (~30fps via AnimationController)
  double _inPeakL = 0.0;
  double _inPeakR = 0.0;
  double _outPeakL = 0.0;
  double _outPeakR = 0.0;
  late AnimationController _meterController;

  // A/B snapshots
  EqSnapshot? _snapshotA;
  EqSnapshot? _snapshotB;

  // ═══════════════════════════════════════════════════════════════════════════
  // A/B COMPARISON — mixin overrides
  // ═══════════════════════════════════════════════════════════════════════════

  EqSnapshot _captureSnapshot() {
    return EqSnapshot(
      bandData: _bands.map((b) => <String, dynamic>{
        'index': b.index, 'freq': b.freq, 'gain': b.gain, 'q': b.q,
        'shape': b.shape.index, 'placement': b.placement.index,
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
    // Push all params to engine — disable all first, then sync active bands
    for (int i = 0; i < 64; i++) {
      _setP(i, _P.enabled, 0.0);
    }
    for (int i = 0; i < _bands.length; i++) {
      _syncBand(i);
    }
    _ffi.insertSetParam(widget.trackId, _slotIndex, _P.outputGainIndex, _outputGain);
    _ffi.insertSetParam(widget.trackId, _slotIndex, _P.autoGainIndex, _autoGain ? 1.0 : 0.0);
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
      } catch (_) {}
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
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
    _meterController.dispose();
    _spectrumTimer?.cancel();
    super.dispose();
  }

  void _initProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);
    if (!chain.nodes.any((n) => n.type == DspNodeType.eq)) {
      dsp.addNode(widget.trackId, DspNodeType.eq);
      chain = dsp.getChain(widget.trackId);
    }
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.eq) {
        _nodeId = node.id;
        _slotIndex = chain.nodes.indexWhere((n) => n.id == _nodeId);
        setState(() => _initialized = true);
        _readBandsFromEngine();
        _startSpectrum();
        break;
      }
    }
  }

  void _readBandsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    final restored = <EqBand>[];
    for (int i = 0; i < 64; i++) {
      final en = _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.enabled);
      final freq = _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.freq);
      if (en >= 0.5 || freq > 10.0) {
        restored.add(EqBand(
          index: i,
          enabled: en >= 0.5,
          freq: freq,
          gain: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.gain),
          q: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.q),
          shape: _intToShape(_ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.shape).round()),
          placement: _intToPlacement(_ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.placement).round()),
          dynamicEnabled: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.dynEnabled) >= 0.5,
          dynamicThreshold: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.dynThreshold),
          dynamicRatio: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.dynRatio),
          dynamicAttack: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.dynAttack),
          dynamicRelease: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.dynRelease),
        ));
      }
    }
    final outG = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.outputGainIndex);
    final ag = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.autoGainIndex) > 0.5;
    setState(() {
      _bands.clear();
      _bands.addAll(restored);
      _outputGain = outG;
      _autoGain = ag;
      _selectedBandIndex = _bands.isNotEmpty ? 0 : null;
    });
  }

  void _startSpectrum() {
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_initialized || !_analyzerOn) return;
      final raw = _ffi.getMasterSpectrum();
      if (raw.isEmpty) return;
      final db = List<double>.generate(raw.length, (i) => raw[i].clamp(0.0, 1.0) * 80 - 80);
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
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(children: [
        buildCompactHeader(),
        _buildTopBar(),
        Expanded(child: _buildDisplay()),
        SizedBox(height: 16, child: CustomPaint(painter: _PianoStripPainter())),
        _buildBandChips(),
        if (_selectedBandIndex != null && _selectedBandIndex! < _bands.length)
          _buildBandEditor(),
      ]),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP BAR — M/S placement + analyzer + auto-gain + output knob
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                )),
              ]),
            ),
          ),
        )),
        const Spacer(),
        // Analyzer toggle
        FabTinyButton(label: 'ANA', active: _analyzerOn,
          onTap: () => setState(() => _analyzerOn = !_analyzerOn),
          color: FabFilterColors.cyan),
        const SizedBox(width: 4),
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
        const SizedBox(width: 8),
        // I/O level meters (compact vertical bars)
        _buildCompactIOMeter(),
        const SizedBox(width: 8),
        // Output gain knob
        SizedBox(
          width: 52,
          height: 30,
          child: Row(children: [
            Expanded(child: FabFilterKnob(
              value: ((_outputGain + 24) / 48).clamp(0.0, 1.0),
              label: '',
              display: '',
              color: FabFilterColors.blue,
              size: 24,
              defaultValue: 0.5,
              onChanged: (v) {
                setState(() => _outputGain = v * 48 - 24);
                if (_slotIndex >= 0) {
                  _ffi.insertSetParam(widget.trackId, _slotIndex, _P.outputGainIndex, _outputGain);
                }
                widget.onSettingsChanged?.call();
              },
            )),
          ]),
        ),
        SizedBox(
          width: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('OUT', style: TextStyle(
                color: FabFilterColors.textTertiary, fontSize: 7,
                fontWeight: FontWeight.bold, letterSpacing: 1,
              )),
              Text(
                '${_outputGain >= 0 ? '+' : ''}${_outputGain.toStringAsFixed(1)} dB',
                style: FabFilterText.paramValue(FabFilterColors.blue),
              ),
            ],
          ),
        ),
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
          )),
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
          )),
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
        return MouseRegion(
          onHover: (e) => _onHover(e.localPosition, box.biggest),
          onExit: (_) => setState(() { _hoverBandIndex = null; _previewPos = null; }),
          child: Listener(
            onPointerSignal: (e) { if (e is PointerScrollEvent) _onScroll(e, box.biggest); },
            child: GestureDetector(
              onTapDown: (d) => _onTapSelect(d.localPosition, box.biggest),
              onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
              onDoubleTap: () { if (_doubleTapPos != null) _onDoubleTap(_doubleTapPos!, box.biggest); },
              onPanStart: (d) => _onDragStart(d.localPosition, box.biggest),
              onPanUpdate: (d) => _onDragUpdate(d.localPosition, box.biggest),
              onPanEnd: (_) => setState(() => _isDragging = false),
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
                  ),
                  size: box.biggest,
                ),
              ),
            ),
          ),
        );
      }),
    );
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
            }),
            _editorKnob('GAIN', ((b.gain + 30) / 60).clamp(0.0, 1.0),
              '${b.gain >= 0 ? '+' : ''}${b.gain.toStringAsFixed(1)}',
              b.gain >= 0 ? FabFilterColors.orange : FabFilterColors.cyan, (v) {
              setState(() => b.gain = v * 60 - 30);
              _syncBand(_selectedBandIndex!);
            }),
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

  Widget _editorKnob(String label, double norm, String display, Color c, ValueChanged<double> onChanged) {
    return Expanded(child: FabFilterKnob(
      value: norm.clamp(0.0, 1.0),
      onChanged: onChanged,
      color: c,
      size: 36,
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
    final idx = _selectedBandIndex ?? _hoverBandIndex;
    if (idx == null || idx >= _bands.length) return;
    final fine = HardwareKeyboard.instance.isShiftPressed;
    final delta = (e.scrollDelta.dy > 0 ? -0.2 : 0.2) * (fine ? 0.1 : 1.0);
    setState(() => _bands[idx].q = (_bands[idx].q + delta).clamp(0.1, 30.0));
    _syncBand(idx);
  }

  void _onTapSelect(Offset pos, Size size) {
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
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
        setState(() => _bands[i].enabled = !_bands[i].enabled);
        _setP(_bands[i].index, _P.enabled, _bands[i].enabled ? 1.0 : 0.0);
        return;
      }
    }
    // Double-click on empty space — add new band at position
    _addBand(_xToFreq(pos.dx, size.width), EqFilterShape.bell);
  }

  void _onDragStart(Offset pos, Size size) {
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
        setState(() { _selectedBandIndex = i; _isDragging = true; });
        return;
      }
    }
  }

  void _onDragUpdate(Offset pos, Size size) {
    if (!_isDragging || _selectedBandIndex == null) return;
    final b = _bands[_selectedBandIndex!];
    setState(() {
      b.freq = _xToFreq(pos.dx, size.width).clamp(10.0, 30000.0);
      b.gain = _yToGain(pos.dy, size.height).clamp(-30.0, 30.0);
    });
    _syncBand(_selectedBandIndex!);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND OPS (via InsertProcessor chain)
  // ═══════════════════════════════════════════════════════════════════════════

  void _addBand(double freq, EqFilterShape shape) {
    if (_bands.length >= 64 || _slotIndex < 0) return;
    final idx = _bands.length;
    final band = EqBand(index: idx, freq: freq, shape: shape, placement: _globalPlacement);
    _setP(idx, _P.freq, freq);
    _setP(idx, _P.gain, 0.0);
    _setP(idx, _P.q, 1.0);
    _setP(idx, _P.enabled, 1.0);
    _setP(idx, _P.shape, shape.index.toDouble());
    _setP(idx, _P.placement, _globalPlacement.index.toDouble());
    setState(() { _bands.add(band); _selectedBandIndex = _bands.length - 1; });
    widget.onSettingsChanged?.call();
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
    widget.onSettingsChanged?.call();
  }

  void _removeBand(int i) {
    if (_slotIndex < 0 || i >= _bands.length) return;
    _setP(_bands[i].index, _P.enabled, 0.0);
    setState(() {
      _bands.removeAt(i);
      _selectedBandIndex = _bands.isEmpty ? null : i.clamp(0, _bands.length - 1);
    });
    widget.onSettingsChanged?.call();
  }

  void _resetEq() {
    if (_slotIndex < 0) return;
    for (int i = 0; i < 64; i++) {
      _setP(i, _P.enabled, 0.0);
      _setP(i, _P.gain, 0.0);
    }
    setState(() {
      _bands.clear();
      _selectedBandIndex = null;
      _outputGain = 0.0;
    });
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
  static double _gainToY(double g, double h) => h / 2 - (g / 30) * (h / 2);
  static double _yToGain(double y, double h) => ((h / 2 - y) / (h / 2)) * 30;

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

  _EqDisplayPainter({
    required this.bands,
    required this.selectedIdx,
    required this.hoverIdx,
    required this.spectrum,
    required this.peakHold,
    required this.analyzerOn,
    required this.previewPos,
    required this.isDragging,
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
    _drawEqCurve(canvas, size);
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

    // dB grid lines + labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final db in [-24.0, -18.0, -12.0, -6.0, 6.0, 12.0, 18.0, 24.0]) {
      final y = cy - (db / 30) * cy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thinP);
    }
    // dB labels on left edge
    for (final db in [-24, -12, 0, 12, 24]) {
      final y = cy - (db / 30) * cy;
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

    // Spectrum fill gradient
    final fill = Path()..addPath(curve, Offset.zero)
      ..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(fill, Paint()..shader = ui.Gradient.linear(
      Offset(0, 0), Offset(0, size.height),
      [
        const Color(0x404A9EFF),
        const Color(0x184A9EFF),
        const Color(0x054A9EFF),
      ],
      [0.0, 0.5, 1.0],
    ));

    // Spectrum line
    canvas.drawPath(curve, Paint()
      ..color = const Color(0x884A9EFF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke);

    // Peak hold thin line
    if (peakHold.isNotEmpty && peakHold.length == smoothed.length) {
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
  }

  void _drawEqCurve(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    final path = Path();
    final cy = size.height / 2;
    for (int px = 0; px <= size.width.toInt(); px++) {
      final f = _xf(px.toDouble(), size.width);
      double db = 0;
      for (final b in bands) {
        if (!b.enabled) continue;
        db += _bandResponse(f, b);
      }
      final y = (cy - (db / 30) * cy).clamp(0.0, size.height);
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
      final bPath = Path();
      for (int px = 0; px <= size.width.toInt(); px += 2) {
        final f = _xf(px.toDouble(), size.width);
        final bdb = _bandResponse(f, b);
        final y = (cy - (bdb / 30) * cy).clamp(0.0, size.height);
        px == 0 ? bPath.moveTo(px.toDouble(), y) : bPath.lineTo(px.toDouble(), y);
      }
      final bFill = Path.from(bPath)..lineTo(size.width, cy)..lineTo(0, cy)..close();
      final bc = _shapeColor(b.shape);
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
      final y = (cy - (b.gain / 30) * cy).clamp(6.0, size.height - 6);
      final c = _shapeColor(b.shape);
      final sel = i == selectedIdx;
      final hov = i == hoverIdx;
      final r = sel ? 8.0 : (hov ? 7.0 : 5.0);

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

  static double _bandResponse(double freq, EqBand band) {
    final ratio = freq / band.freq;
    final lr = math.log(ratio) / math.ln2;
    return switch (band.shape) {
      EqFilterShape.bell => band.gain * math.exp(-math.pow(lr * band.q, 2)),
      EqFilterShape.lowShelf => band.gain * (1 - 1 / (1 + math.exp(-lr * 4))),
      EqFilterShape.highShelf => band.gain * (1 / (1 + math.exp(-lr * 4))),
      EqFilterShape.lowCut => ratio < 1 ? -30 * (1 - ratio) : 0,
      EqFilterShape.highCut => ratio > 1 ? -30 * (ratio - 1) : 0,
      EqFilterShape.notch => -30.0 * math.exp(-math.pow(lr * band.q * 2, 2)),
      EqFilterShape.bandPass => math.exp(-math.pow(lr * band.q, 2)) * 12 - 6,
      EqFilterShape.tiltShelf => band.gain * lr.clamp(-2.0, 2.0) / 2,
      EqFilterShape.allPass || EqFilterShape.brickwall => 0,
    };
  }

  static Color _shapeColor(EqFilterShape s) => _FabFilterEqPanelState._shapeColor(s);

  @override
  bool shouldRepaint(covariant _EqDisplayPainter old) =>
    bands != old.bands || selectedIdx != old.selectedIdx || hoverIdx != old.hoverIdx ||
    spectrum != old.spectrum || peakHold != old.peakHold || analyzerOn != old.analyzerOn ||
    previewPos != old.previewPos || isDragging != old.isDragging;
}
