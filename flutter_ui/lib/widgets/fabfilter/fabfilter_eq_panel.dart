/// FF-Q EQ Panel — Pro-Q inspired 64-band parametric EQ
///
/// Features:
/// - Interactive spectrum + EQ curve display with draggable nodes
/// - Piano keyboard frequency reference strip
/// - M/S processing toggle (Stereo / Mid / Side)
/// - Per-band solo & bypass via band chip
/// - Dynamic EQ per band (expert mode)
/// - Click-to-create, drag-to-adjust, scroll-for-Q
/// - Shape chip bar with color-coded filter types

import 'dart:async';
import 'dart:math' as math;
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
    with FabFilterPanelMixin<FabFilterEqPanel> {
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
  Timer? _spectrumTimer;

  // Interaction
  bool _isDragging = false;
  Offset? _previewPos;

  @override
  void initState() {
    super.initState();
    _initProcessor();
    initBypassFromProvider();
  }

  @override
  void dispose() {
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
      if (en >= 0.5) {
        restored.add(EqBand(
          index: i,
          freq: _ffi.insertGetParam(widget.trackId, _slotIndex, i * _P.paramsPerBand + _P.freq),
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
      // Convert 0-1 → dB, smooth with ballistics
      final db = List<double>.generate(raw.length, (i) => raw[i].clamp(0.0, 1.0) * 80 - 80);
      final prev = _spectrum;
      final out = List<double>.filled(db.length, -80.0);
      for (int i = 0; i < db.length; i++) {
        final p = i < prev.length ? prev[i] : -80.0;
        out[i] = db[i] > p ? p + (db[i] - p) * 0.6 : p + (db[i] - p) * 0.15;
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
        // Header
        buildCompactHeader(),
        // Placement chips + analyzer toggle
        _buildTopBar(),
        // Main display
        Expanded(child: _buildDisplay()),
        // Piano keyboard strip
        SizedBox(height: 16, child: CustomPaint(painter: _PianoStripPainter())),
        // Band chips
        _buildBandChips(),
        // Selected band editor
        if (_selectedBandIndex != null && _selectedBandIndex! < _bands.length)
          _buildBandEditor(),
      ]),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP BAR — M/S placement + analyzer + auto-gain + output
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        // M/S placement chips
        ...EqPlacement.values.map((p) => Padding(
          padding: const EdgeInsets.only(right: 3),
          child: GestureDetector(
            onTap: () => setState(() => _globalPlacement = p),
            child: AnimatedContainer(
              duration: FabFilterDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _globalPlacement == p ? p.color.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _globalPlacement == p ? p.color : FabFilterColors.borderSubtle,
                ),
              ),
              child: Text(p.label, style: TextStyle(
                color: _globalPlacement == p ? p.color : FabFilterColors.textTertiary,
                fontSize: 9, fontWeight: FontWeight.bold,
              )),
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
        // Output gain knob
        FabSectionLabel('OUT'),
        const SizedBox(width: 4),
        SizedBox(width: 50, child: SliderTheme(
          data: fabFilterSliderTheme(FabFilterColors.blue),
          child: Slider(
            value: ((_outputGain + 24) / 48).clamp(0.0, 1.0),
            onChanged: (v) {
              setState(() => _outputGain = v * 48 - 24);
              if (_slotIndex >= 0) {
                _ffi.insertSetParam(widget.trackId, _slotIndex, _P.outputGainIndex, _outputGain);
              }
            },
          ),
        )),
        SizedBox(width: 40, child: Text(
          '${_outputGain >= 0 ? '+' : ''}${_outputGain.toStringAsFixed(1)}',
          style: FabFilterText.paramValue(FabFilterColors.blue), textAlign: TextAlign.right,
        )),
      ]),
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
              onTapDown: (d) => _onTap(d.localPosition, box.biggest),
              onPanStart: (d) => _onDragStart(d.localPosition, box.biggest),
              onPanUpdate: (d) => _onDragUpdate(d.localPosition, box.biggest),
              onPanEnd: (_) => setState(() => _isDragging = false),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: CustomPaint(
                  painter: _EqDisplayPainter(
                    bands: _bands, selectedIdx: _selectedBandIndex, hoverIdx: _hoverBandIndex,
                    spectrum: _spectrum, analyzerOn: _analyzerOn,
                    previewPos: _previewPos, isDragging: _isDragging,
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
        FabSectionLabel('${_bands.length}'),
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
              onDoubleTap: () { setState(() => b.enabled = !b.enabled); _syncBand(i); },
              onLongPress: () => _removeBand(i),
              child: AnimatedContainer(
                duration: FabFilterDurations.fast,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: FabFilterDecorations.chip(c, selected: sel),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!b.enabled) Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(Icons.visibility_off, size: 8, color: FabFilterColors.textTertiary),
                  ),
                  if (b.solo) Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(Icons.headphones, size: 8, color: FabFilterColors.yellow),
                  ),
                  if (b.dynamicEnabled) Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(Icons.flash_on, size: 8, color: FabFilterColors.yellow),
                  ),
                  Text(_fmtFreq(b.freq), style: TextStyle(
                    color: sel ? FabFilterColors.textPrimary : (b.enabled ? c : FabFilterColors.textDisabled),
                    fontSize: 9, fontWeight: FontWeight.bold,
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
          padding: EdgeInsets.zero, constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
          tooltip: 'Add Band (click graph)',
          onPressed: () => _addBand(1000, EqFilterShape.bell),
        ),
        // Reset
        IconButton(
          icon: const Icon(Icons.refresh, size: 16),
          color: FabFilterColors.textTertiary,
          padding: EdgeInsets.zero, constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
          tooltip: 'Reset EQ',
          onPressed: _resetEq,
        ),
        const SizedBox(width: 4),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAND EDITOR — compact inline row
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBandEditor() {
    final b = _bands[_selectedBandIndex!];
    final c = _shapeColor(b.shape);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: FabFilterColors.bgMid,
        border: const Border(top: BorderSide(color: FabFilterColors.borderSubtle))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Row 1: Shape chips + placement + solo + enable + delete
        SizedBox(height: 24, child: Row(children: [
          Expanded(child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: EqFilterShape.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 2),
            itemBuilder: (_, i) {
              final s = EqFilterShape.values[i];
              final act = b.shape == s;
              return GestureDetector(
                onTap: () { setState(() => b.shape = s); _syncBand(_selectedBandIndex!); },
                child: AnimatedContainer(
                  duration: FabFilterDurations.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: act ? _shapeColor(s).withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: act ? _shapeColor(s) : FabFilterColors.borderSubtle),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(s.icon, size: 10, color: act ? _shapeColor(s) : FabFilterColors.textTertiary),
                    const SizedBox(width: 2),
                    Text(s.label, style: TextStyle(
                      fontSize: 8, fontWeight: FontWeight.bold,
                      color: act ? _shapeColor(s) : FabFilterColors.textTertiary,
                    )),
                  ]),
                ),
              );
            },
          )),
          const SizedBox(width: 4),
          // Placement cycle
          GestureDetector(
            onTap: () {
              final vals = EqPlacement.values;
              setState(() => b.placement = vals[(vals.indexOf(b.placement) + 1) % vals.length]);
              _syncBand(_selectedBandIndex!);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: b.placement.color),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(b.placement.label, style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold, color: b.placement.color,
              )),
            ),
          ),
          const SizedBox(width: 4),
          // Solo
          FabTinyButton(label: 'S', active: b.solo,
            onTap: () {
              setState(() {
                // Toggle solo: if already solo, un-solo; else solo this band
                if (b.solo) {
                  b.solo = false;
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, _P.soloBandIndex, -1.0);
                  }
                } else {
                  // Un-solo any other band
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
          // Enable
          FabTinyButton(label: b.enabled ? 'ON' : '-',
            active: b.enabled,
            onTap: () { setState(() => b.enabled = !b.enabled); _syncBand(_selectedBandIndex!); },
            color: FabFilterColors.green),
          const SizedBox(width: 2),
          // Delete
          GestureDetector(
            onTap: () => _removeBand(_selectedBandIndex!),
            child: const Icon(Icons.close, size: 14, color: FabFilterColors.red),
          ),
        ])),
        const SizedBox(height: 4),
        // Row 2: knobs — Freq, Gain, Q (+ dynamic if expert)
        SizedBox(height: 56, child: Row(children: [
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
          if (showExpertMode) ...[
            const VerticalDivider(width: 12, color: FabFilterColors.borderSubtle),
            FabTinyButton(label: 'DYN', active: b.dynamicEnabled,
              onTap: () { setState(() => b.dynamicEnabled = !b.dynamicEnabled); _syncBand(_selectedBandIndex!); },
              color: FabFilterColors.yellow),
            if (b.dynamicEnabled) ...[
              const SizedBox(width: 4),
              _editorKnob('THR', ((b.dynamicThreshold + 60) / 60).clamp(0.0, 1.0),
                '${b.dynamicThreshold.toStringAsFixed(0)}', FabFilterColors.yellow, (v) {
                setState(() => b.dynamicThreshold = v * 60 - 60);
                _syncBand(_selectedBandIndex!);
              }),
              _editorKnob('RAT', ((b.dynamicRatio - 1) / 19).clamp(0.0, 1.0),
                '${b.dynamicRatio.toStringAsFixed(1)}', FabFilterColors.yellow, (v) {
                setState(() => b.dynamicRatio = 1 + v * 19);
                _syncBand(_selectedBandIndex!);
              }),
            ],
          ],
        ])),
      ]),
    );
  }

  Widget _editorKnob(String label, double norm, String display, Color c, ValueChanged<double> onChanged) {
    return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 36, width: 36, child: FabFilterKnob(
        value: norm.clamp(0.0, 1.0),
        onChanged: onChanged,
        color: c,
        size: 36,
        label: label,
        display: display,
      )),
    ]));
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

  void _onTap(Offset pos, Size size) {
    for (int i = 0; i < _bands.length; i++) {
      if (!_bands[i].enabled) continue;
      final bx = _freqToX(_bands[i].freq, size.width);
      final by = _gainToY(_bands[i].gain, size.height);
      if ((Offset(bx, by) - pos).distance < 15) {
        setState(() => _selectedBandIndex = i);
        return;
      }
    }
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
    setState(() { _bands.clear(); _selectedBandIndex = null; });
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
    const lo = 1.0, hi = 4.477; // log10(10)..log10(30000)
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
  // 10 octaves: A0 (27.5 Hz) → C8 (4186 Hz), extended display to 20kHz
  static const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _blackNotes = {1, 3, 6, 8, 10}; // C#, D#, F#, G#, A#

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = FabFilterColors.bgMid;
    canvas.drawRect(Offset.zero & size, bg);

    final whitePaint = Paint()..color = const Color(0xFFE0E0E4);
    final blackPaint = Paint()..color = const Color(0xFF303038);
    final cPaint = Paint()..color = FabFilterColors.blue.withValues(alpha: 0.4);
    final borderP = Paint()..color = FabFilterColors.borderSubtle..strokeWidth = 0.5..style = PaintingStyle.stroke;

    // Draw keys from C1 (32.7Hz) to C8 (4186Hz) — 7 octaves
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
          canvas.drawRect(Rect.fromLTWH(x, 0, w * 0.6, size.height * 0.6), blackPaint);
        } else {
          final paint = note == 0 ? cPaint : whitePaint; // C notes highlighted
          canvas.drawRect(Rect.fromLTWH(x, isBlack ? 0 : size.height * 0.4, w, size.height * 0.6), paint);
          canvas.drawRect(Rect.fromLTWH(x, isBlack ? 0 : size.height * 0.4, w, size.height * 0.6), borderP);
        }
      }
    }

    // Freq labels at key frequencies
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final f in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(f, size.width);
      tp.text = TextSpan(text: f >= 1000 ? '${(f / 1000).toInt()}k' : '${f.toInt()}',
        style: const TextStyle(color: FabFilterColors.textTertiary, fontSize: 7));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height));
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
// EQ DISPLAY PAINTER — Spectrum + Curve + Nodes
// ═══════════════════════════════════════════════════════════════════════════════

class _EqDisplayPainter extends CustomPainter {
  final List<EqBand> bands;
  final int? selectedIdx;
  final int? hoverIdx;
  final List<double> spectrum;
  final bool analyzerOn;
  final Offset? previewPos;
  final bool isDragging;

  _EqDisplayPainter({
    required this.bands, required this.selectedIdx, required this.hoverIdx,
    required this.spectrum, required this.analyzerOn,
    required this.previewPos, required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = FabFilterColors.bgVoid);
    _drawGrid(canvas, size);
    if (analyzerOn && spectrum.isNotEmpty) _drawSpectrum(canvas, size);
    _drawEqCurve(canvas, size);
    if (previewPos != null && !isDragging) _drawPreview(canvas, previewPos!);
    _drawNodes(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final p = Paint()..color = FabFilterColors.borderSubtle..strokeWidth = 0.5;
    // Frequency lines
    for (final f in [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]) {
      final x = _fx(f, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    // dB lines
    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy),
      Paint()..color = FabFilterColors.borderMedium..strokeWidth = 1);
    for (final db in [-24.0, -18.0, -12.0, -6.0, 6.0, 12.0, 18.0, 24.0]) {
      final y = cy - (db / 30) * (cy);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    // dB labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final db in [-12, 0, 12]) {
      final y = cy - (db / 30) * cy;
      tp.text = TextSpan(text: '${db > 0 ? '+' : ''}$db', style: const TextStyle(
        color: FabFilterColors.textDisabled, fontSize: 7));
      tp.layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
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
        p2.dx, p2.dy);
    }

    final fill = Path()..addPath(curve, Offset.zero)..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    final color = FabFilterProcessorColors.eqAnalyzerLine;
    canvas.drawPath(fill, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.03)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(curve, Paint()..color = color.withValues(alpha: 0.5)..strokeWidth = 1.5..style = PaintingStyle.stroke);
  }

  void _drawEqCurve(Canvas canvas, Size size) {
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

    // Fill: orange above 0dB, cyan below
    final fillPath = Path.from(path)..lineTo(size.width, cy)..lineTo(0, cy)..close();
    canvas.drawPath(fillPath, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [FabFilterColors.orange.withValues(alpha: 0.12), FabFilterColors.cyan.withValues(alpha: 0.12)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // Stroke
    canvas.drawPath(path, Paint()..color = FabFilterProcessorColors.eqCurveLine
      ..strokeWidth = 2..style = PaintingStyle.stroke);
  }

  void _drawPreview(Canvas canvas, Offset pos) {
    final c = FabFilterColors.blue.withValues(alpha: 0.4);
    canvas.drawLine(Offset(pos.dx, 0), Offset(pos.dx, 9999), Paint()..color = c..strokeWidth = 0.5);
    canvas.drawLine(Offset(0, pos.dy), Offset(9999, pos.dy), Paint()..color = c..strokeWidth = 0.5);
    canvas.drawCircle(pos, 6, Paint()..color = c);
  }

  void _drawNodes(Canvas canvas, Size size) {
    final cy = size.height / 2;
    for (int i = 0; i < bands.length; i++) {
      final b = bands[i];
      if (!b.enabled) continue;
      final x = _fx(b.freq, size.width);
      final y = (cy - (b.gain / 30) * cy).clamp(6.0, size.height - 6);
      final c = _shapeColor(b.shape);
      final sel = i == selectedIdx;
      final hov = i == hoverIdx;
      final r = sel ? 9.0 : (hov ? 7.0 : 5.0);

      if (sel || hov) canvas.drawCircle(Offset(x, y), r + 4, Paint()..color = c.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(x, y), r, Paint()..color = c);
      if (sel) canvas.drawCircle(Offset(x, y), r + 2,
        Paint()..color = FabFilterColors.textPrimary..style = PaintingStyle.stroke..strokeWidth = 2);
      if (b.dynamicEnabled) canvas.drawCircle(Offset(x, y - r - 5), 2.5, Paint()..color = FabFilterColors.yellow);
      if (b.solo) canvas.drawCircle(Offset(x + r + 4, y - r - 2), 2.5, Paint()..color = FabFilterColors.yellow);
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
    spectrum != old.spectrum || analyzerOn != old.analyzerOn ||
    previewPos != old.previewPos || isDragging != old.isDragging;
}
