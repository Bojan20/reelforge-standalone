// ignore_for_file: unused_field, unused_element
/// RF-EQ 64 — ReelForge Professional 64-Band Parametric Equalizer
///
/// Features:
/// - 64 fully parametric bands
/// - Floating band control panel (bottom-centered)
/// - Real-time spectrum analyzer (signal-dependent)
/// - Butterworth highpass/lowpass filters
/// - 10 filter shapes: Bell, Shelf, Cut, Notch, Bandpass, Tilt, AllPass
/// - Professional dark UI with glow effects
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FABFILTER-STYLE COLOR SYSTEM
// ═══════════════════════════════════════════════════════════════════════════

class _Colors {
  // Background - deep dark (FabFilter style)
  static const bg1 = Color(0xFF1A1A1E);
  static const bg2 = Color(0xFF202024);
  static const bg3 = Color(0xFF28282E);
  static const bg4 = Color(0xFF303038);
  static const bg5 = Color(0xFF3A3A44);

  // EQ Curve - FabFilter yellow/orange
  static const curveMain = Color(0xFFFFB347);      // Warm orange-yellow
  static const curveLight = Color(0xFFFFD080);     // Lighter
  static const curveDark = Color(0xFFE89020);      // Darker
  static const curveGlow = Color(0x60FFB347);      // Glow

  // Fill under curve
  static const curveFill = Color(0x18FFB347);

  // Spectrum analyzer - white/gray (FabFilter style)
  static const spectrumLine = Color(0xFFE0E0E0);
  static const spectrumFill = Color(0x15FFFFFF);

  // Band colors - FabFilter palette
  static const bands = [
    Color(0xFFFF6B6B),  // Red
    Color(0xFFFFBE5C),  // Orange
    Color(0xFFFFE66D),  // Yellow
    Color(0xFF7DDB7D),  // Green
    Color(0xFF5DADE2),  // Cyan
    Color(0xFF6B8AFF),  // Blue
    Color(0xFFB07DDB),  // Purple
    Color(0xFFFF7DDB),  // Pink
  ];

  // Grid
  static const gridMajor = Color(0xFF404048);
  static const gridMinor = Color(0xFF2A2A30);

  // Text
  static const textBright = Color(0xFFF0F0F5);
  static const textPrimary = Color(0xFFB0B0B8);
  static const textSecondary = Color(0xFF707078);
  static const textDim = Color(0xFF505058);

  // Controls
  static const controlBg = Color(0xFF252528);
  static const controlBorder = Color(0xFF404048);
  static const controlHover = Color(0xFF353540);

  // Status
  static const red = Color(0xFFFF5555);
  static const green = Color(0xFF55FF88);
  static const bypass = Color(0xFFFF4444);
}

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & DATA
// ═══════════════════════════════════════════════════════════════════════════

enum FilterShape {
  bell,
  lowShelf,
  highShelf,
  lowCut,
  highCut,
  notch,
  bandPass,
  tiltShelf,
  flatTilt,
  allPass,
}

enum StereoMode { stereo, left, right, mid, side }

class _Band {
  int id;
  bool enabled;
  bool bypassed;
  FilterShape shape;
  double freq;
  double gain;
  double q;
  int slope; // dB/oct: 6, 12, 18, 24, 36, 48, 72, 96
  StereoMode stereo;

  _Band({
    required this.id,
    this.enabled = true,
    this.bypassed = false,
    this.shape = FilterShape.bell,
    this.freq = 1000,
    this.gain = 0,
    this.q = 1.0,
    this.slope = 24,
    this.stereo = StereoMode.stereo,
  });

  _Band copy() => _Band(
    id: id,
    enabled: enabled,
    bypassed: bypassed,
    shape: shape,
    freq: freq,
    gain: gain,
    q: q,
    slope: slope,
    stereo: stereo,
  );

  Color get color => _Colors.bands[id % _Colors.bands.length];

  String get shapeIcon {
    switch (shape) {
      case FilterShape.bell: return '∩';
      case FilterShape.lowShelf: return '⌊';
      case FilterShape.highShelf: return '⌉';
      case FilterShape.lowCut: return '╱';
      case FilterShape.highCut: return '╲';
      case FilterShape.notch: return '∪';
      case FilterShape.bandPass: return '▲';
      case FilterShape.tiltShelf: return '∠';
      case FilterShape.flatTilt: return '—';
      case FilterShape.allPass: return 'φ';
    }
  }

  String get shapeName {
    switch (shape) {
      case FilterShape.bell: return 'Bell';
      case FilterShape.lowShelf: return 'Low Shelf';
      case FilterShape.highShelf: return 'High Shelf';
      case FilterShape.lowCut: return 'Low Cut';
      case FilterShape.highCut: return 'High Cut';
      case FilterShape.notch: return 'Notch';
      case FilterShape.bandPass: return 'Band Pass';
      case FilterShape.tiltShelf: return 'Tilt Shelf';
      case FilterShape.flatTilt: return 'Flat Tilt';
      case FilterShape.allPass: return 'All Pass';
    }
  }

  bool get hasGain =>
    shape != FilterShape.lowCut &&
    shape != FilterShape.highCut &&
    shape != FilterShape.notch &&
    shape != FilterShape.allPass;

  bool get hasSlope =>
    shape == FilterShape.lowCut || shape == FilterShape.highCut;
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ProEqEditor extends StatefulWidget {
  final String trackId;
  final double width;
  final double height;

  const ProEqEditor({
    super.key,
    required this.trackId,
    this.width = 1200,
    this.height = 700,
  });

  @override
  State<ProEqEditor> createState() => _ProEqEditorState();
}

class _ProEqEditorState extends State<ProEqEditor> with TickerProviderStateMixin {
  late List<_Band> _bands;
  int? _selectedBand;
  int? _hoveredBand;
  int? _draggingBand;

  // Animations
  late AnimationController _glowController;
  late AnimationController _panelController;
  late Animation<double> _panelOpacity;

  // State
  int _rangeIndex = 2; // ±12dB default
  bool _analyzerOn = true;
  bool _globalBypass = false;
  double _outputGain = 0;
  int _phaseMode = 0; // 0=Zero Lat, 1=Natural, 2=Linear

  // Spectrum data
  late AnimationController _spectrumController;
  List<double> _spectrum = [];
  double _signalLevel = 0; // 0-1, for fade effect

  // Undo/Redo
  final List<List<_Band>> _undoStack = [];
  final List<List<_Band>> _redoStack = [];

  final FocusNode _focus = FocusNode();

  // For knob/value dragging
  double _dragStartValue = 0;
  Offset _dragStartPos = Offset.zero;

  @override
  void initState() {
    super.initState();

    // Default bands
    _bands = [
      _Band(id: 0, shape: FilterShape.lowCut, freq: 30, slope: 24),
      _Band(id: 1, shape: FilterShape.lowShelf, freq: 100, gain: 2.0),
      _Band(id: 2, shape: FilterShape.bell, freq: 400, gain: -2.5, q: 1.2),
      _Band(id: 3, shape: FilterShape.bell, freq: 2500, gain: 3.0, q: 0.8),
      _Band(id: 4, shape: FilterShape.highShelf, freq: 8000, gain: 1.5),
      _Band(id: 5, shape: FilterShape.highCut, freq: 18000, slope: 24),
    ];
    _pushUndo();

    // Glow animation for curve
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    // Panel fade animation
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _panelOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _panelController, curve: Curves.easeOut),
    );

    // Spectrum update
    _spectrumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateSpectrum);
    _spectrumController.repeat();
  }

  void _updateSpectrum() {
    // In real app: _signalLevel comes from audio engine RMS meter
    // For demo: simulate with random signal on/off (90% on, 10% off)
    final rnd = math.Random();
    final signalActive = rnd.nextDouble() > 0.1;

    // Smooth signal level transitions
    if (signalActive) {
      _signalLevel = (_signalLevel + 0.08).clamp(0.0, 1.0);
    } else {
      _signalLevel = (_signalLevel - 0.04).clamp(0.0, 1.0);
    }

    // NO SIGNAL: Clear spectrum completely - nothing to show
    if (_signalLevel < 0.01) {
      _spectrum.clear();
      if (mounted) setState(() {});
      return;
    }

    // HAS SIGNAL: Generate spectrum visualization
    const n = 256;
    if (_spectrum.length != n) _spectrum = List.filled(n, -100.0);

    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final f = (20 * math.pow(1000, t)).toDouble();

      // Base spectrum (pink noise slope: -3dB/octave)
      double db = -35 - t * 15;

      // Musical content: bass bump + presence
      if (f > 50 && f < 180) db += 10 * math.exp(-math.pow((f - 90) / 40, 2));
      if (f > 1500 && f < 5000) db += 6 * math.exp(-math.pow((f - 2500) / 800, 2));

      // Apply EQ curve to spectrum
      for (final b in _bands) {
        if (!b.enabled || b.bypassed) continue;
        db += _getFilterResponse(b, f) * 0.4;
      }

      // Smooth interpolation
      _spectrum[i] = _spectrum[i] * 0.82 + db * 0.18;
    }

    if (mounted) setState(() {});
  }

  double _getFilterResponse(_Band b, double f) {
    final f0 = b.freq, g = b.gain, q = b.q;
    final ratio = f / f0;

    switch (b.shape) {
      case FilterShape.bell:
        // Parametric bell with Q control
        final logRatio = math.log(ratio) / math.ln2;
        final bandwidth = 1.0 / q;
        return g * math.exp(-0.5 * math.pow(logRatio / bandwidth, 2));

      case FilterShape.lowShelf:
        // Smooth low shelf transition
        if (ratio <= 0.5) return g;
        if (ratio >= 2.0) return 0;
        final t = (ratio - 0.5) / 1.5;
        return g * (1 - t * t * (3 - 2 * t)); // Smoothstep

      case FilterShape.highShelf:
        // Smooth high shelf transition
        if (ratio >= 2.0) return g;
        if (ratio <= 0.5) return 0;
        final t = (ratio - 0.5) / 1.5;
        return g * t * t * (3 - 2 * t); // Smoothstep

      case FilterShape.lowCut:
        // Butterworth highpass: -3dB at cutoff, 0dB passband above
        // |H(jw)|² = (w/wc)^(2n) / (1 + (w/wc)^(2n))
        final order = b.slope ~/ 6;
        final x = math.pow(ratio, order * 2).toDouble();
        final magnitude = math.sqrt(x / (1.0 + x));
        if (magnitude <= 0) return -100.0;
        return (20 * math.log(magnitude) / math.ln10).clamp(-100.0, 0.0);

      case FilterShape.highCut:
        // Butterworth lowpass: -3dB at cutoff, 0dB passband below
        // |H(jw)|² = 1 / (1 + (w/wc)^(2n))
        final order = b.slope ~/ 6;
        final x = math.pow(ratio, order * 2).toDouble();
        final magnitude = 1.0 / math.sqrt(1.0 + x);
        if (magnitude <= 0) return -100.0;
        return (20 * math.log(magnitude) / math.ln10).clamp(-100.0, 0.0);

      case FilterShape.notch:
        // Notch filter with Q control
        final logRatio = math.log(ratio) / math.ln2;
        final bw = 0.5 / q;
        if (logRatio.abs() > bw * 3) return 0;
        return -30 * math.exp(-0.5 * math.pow(logRatio / bw, 2));

      case FilterShape.bandPass:
        // Bandpass with Q control
        final logRatio = math.log(ratio) / math.ln2;
        final bw = 1.0 / q;
        final atten = -60 * math.pow(logRatio.abs() / bw, 2);
        return atten.clamp(-60.0, 0.0).toDouble();

      case FilterShape.tiltShelf:
        // Spectral tilt
        final logRatio = math.log(ratio) / math.ln2;
        return g * (logRatio / 3).clamp(-1.0, 1.0);

      case FilterShape.flatTilt:
        // Flat tilt across spectrum
        final logRatio = math.log(ratio) / math.ln2;
        return g * (logRatio / 5).clamp(-1.0, 1.0);

      case FilterShape.allPass:
        return 0; // Phase only, no gain change
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _panelController.dispose();
    _spectrumController.dispose();
    _focus.dispose();
    super.dispose();
  }

  double get _range => [3.0, 6.0, 12.0, 30.0][_rangeIndex];

  void _pushUndo() {
    _undoStack.add(_bands.map((b) => b.copy()).toList());
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.length <= 1) return;
    _redoStack.add(_undoStack.removeLast());
    setState(() => _bands = _undoStack.last.map((b) => b.copy()).toList());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    setState(() => _bands = next.map((b) => b.copy()).toList());
  }

  void _selectBand(int? index) {
    if (_selectedBand == index) return;
    setState(() => _selectedBand = index);
    if (index != null) {
      _panelController.forward(from: 0);
    } else {
      _panelController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: _Colors.bg1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _Colors.bg4, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Stack(
                  children: [
                    // Main EQ display
                    _buildEQDisplay(),
                    // Floating band controls (FabFilter style)
                    if (_selectedBand != null) _buildFloatingControls(),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _selectBand(null);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.delete && _selectedBand != null) {
      if (_bands.length > 1) {
        _pushUndo();
        setState(() {
          _bands.removeAt(_selectedBand!);
          _selectedBand = null;
        });
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyZ &&
        HardwareKeyboard.instance.isControlPressed) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _redo();
      } else {
        _undo();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _Colors.bg2,
        border: Border(bottom: BorderSide(color: _Colors.bg4)),
      ),
      child: Row(
        children: [
          // Logo
          const Text(
            'PRO-EQ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: _Colors.curveMain,
            ),
          ),
          const SizedBox(width: 20),

          // Preset selector
          _buildHeaderButton('Default', Icons.keyboard_arrow_down),
          const SizedBox(width: 8),

          // Undo/Redo
          _buildIconButton(Icons.undo, _undoStack.length > 1, _undo),
          _buildIconButton(Icons.redo, _redoStack.isNotEmpty, _redo),

          const Spacer(),

          // Range selector
          _buildRangeSelector(),
          const SizedBox(width: 12),

          // Analyzer toggle
          _buildAnalyzerToggle(),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(String text, IconData icon) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _Colors.controlBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _Colors.controlBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 11, color: _Colors.textPrimary)),
          const SizedBox(width: 4),
          Icon(icon, size: 14, color: _Colors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, bool enabled, VoidCallback? onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: enabled ? _Colors.controlBg : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: enabled ? _Colors.textSecondary : _Colors.textDim),
      ),
    );
  }

  Widget _buildRangeSelector() {
    final labels = ['±3', '±6', '±12', '±30'];
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: _Colors.controlBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _Colors.controlBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) {
          final active = i == _rangeIndex;
          return GestureDetector(
            onTap: () => setState(() => _rangeIndex = i),
            child: Container(
              width: 36,
              decoration: BoxDecoration(
                color: active ? _Colors.curveMain.withOpacity(0.2) : null,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Text(
                  '${labels[i]}dB',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? _Colors.curveMain : _Colors.textDim,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAnalyzerToggle() {
    return GestureDetector(
      onTap: () => setState(() => _analyzerOn = !_analyzerOn),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _analyzerOn ? _Colors.curveMain.withOpacity(0.15) : _Colors.controlBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _analyzerOn ? _Colors.curveMain.withOpacity(0.4) : _Colors.controlBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq, size: 14,
                color: _analyzerOn ? _Colors.curveMain : _Colors.textDim),
            const SizedBox(width: 6),
            Text(
              'ANALYZER',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: _analyzerOn ? _Colors.curveMain : _Colors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EQ DISPLAY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEQDisplay() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Store size for floating panel positioning
        _eqDisplaySize = Size(constraints.maxWidth, constraints.maxHeight);

        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && _hoveredBand != null) {
              _pushUndo();
              final b = _bands[_hoveredBand!];
              final delta = e.scrollDelta.dy > 0 ? -0.1 : 0.1;
              b.q = (b.q + delta).clamp(0.1, 18.0);
              setState(() {});
            }
          },
          child: MouseRegion(
            onHover: (e) => _handleHover(e.localPosition, constraints),
            onExit: (_) => setState(() => _hoveredBand = null),
            child: GestureDetector(
              onTapDown: (d) => _handleTap(d.localPosition, constraints),
              onDoubleTapDown: (d) => _handleDoubleTap(d.localPosition, constraints),
              onPanStart: (d) => _handleDragStart(d.localPosition, constraints),
              onPanUpdate: (d) => _handleDragUpdate(d.localPosition, constraints),
              onPanEnd: (_) => setState(() => _draggingBand = null),
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (ctx, _) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _EQDisplayPainter(
                      bands: _bands,
                      selectedBand: _selectedBand,
                      hoveredBand: _hoveredBand,
                      range: _range,
                      spectrum: _analyzerOn && _signalLevel > 0.01 ? _spectrum : null,
                      signalLevel: _signalLevel,
                      glowValue: _glowController.value,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleHover(Offset pos, BoxConstraints c) {
    for (int i = 0; i < _bands.length; i++) {
      final nodePos = _getBandPosition(_bands[i], c);
      if ((nodePos - pos).distance <= 14) {
        if (_hoveredBand != i) setState(() => _hoveredBand = i);
        return;
      }
    }
    if (_hoveredBand != null) setState(() => _hoveredBand = null);
  }

  void _handleTap(Offset pos, BoxConstraints c) {
    for (int i = 0; i < _bands.length; i++) {
      final nodePos = _getBandPosition(_bands[i], c);
      if ((nodePos - pos).distance <= 14) {
        _selectBand(i);
        return;
      }
    }
    _selectBand(null);
  }

  void _handleDoubleTap(Offset pos, BoxConstraints c) {
    // Check if clicking on existing band
    for (int i = 0; i < _bands.length; i++) {
      final nodePos = _getBandPosition(_bands[i], c);
      if ((nodePos - pos).distance <= 14) {
        // Reset band to default
        _pushUndo();
        _bands[i].gain = 0;
        _bands[i].q = 1.0;
        setState(() {});
        return;
      }
    }

    // Create new band
    if (_bands.length >= 24) return;
    _pushUndo();

    final freq = _xToFreq(pos.dx, c.maxWidth);
    final gain = _yToGain(pos.dy, c.maxHeight);

    setState(() {
      _bands.add(_Band(
        id: _bands.length,
        freq: freq.clamp(20.0, 20000.0),
        gain: gain.clamp(-_range, _range),
      ));
      _selectBand(_bands.length - 1);
    });
  }

  void _handleDragStart(Offset pos, BoxConstraints c) {
    for (int i = 0; i < _bands.length; i++) {
      final nodePos = _getBandPosition(_bands[i], c);
      if ((nodePos - pos).distance <= 14) {
        _pushUndo();
        setState(() {
          _draggingBand = i;
          _selectBand(i);
        });
        return;
      }
    }
  }

  void _handleDragUpdate(Offset pos, BoxConstraints c) {
    if (_draggingBand == null) return;
    final b = _bands[_draggingBand!];

    setState(() {
      b.freq = _xToFreq(pos.dx, c.maxWidth).clamp(10.0, 30000.0);
      if (b.hasGain) {
        b.gain = _yToGain(pos.dy, c.maxHeight).clamp(-30.0, 30.0);
      }
    });
  }

  Offset _getBandPosition(_Band b, BoxConstraints c) {
    final x = _freqToX(b.freq, c.maxWidth);
    final y = b.hasGain
        ? _gainToY(b.gain, c.maxHeight, _range)
        : _gainToY(0, c.maxHeight, _range);
    return Offset(x, y);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOATING BAND CONTROLS (FabFilter Style - Bottom Centered)
  // ═══════════════════════════════════════════════════════════════════════════

  // Store EQ display size for panel positioning
  Size _eqDisplaySize = Size.zero;

  Widget _buildFloatingControls() {
    if (_selectedBand == null || _selectedBand! >= _bands.length) {
      return const SizedBox();
    }

    final band = _bands[_selectedBand!];

    const panelWidth = 480.0;

    return AnimatedBuilder(
      animation: _panelController,
      builder: (ctx, _) {
        // Slide up from bottom animation
        final slideOffset = (1 - _panelOpacity.value) * 20;

        return Positioned(
          // Centered horizontally
          left: (_eqDisplaySize.width - panelWidth) / 2,
          // Fixed at bottom with margin
          bottom: 24 - slideOffset,
          child: Opacity(
            opacity: _panelOpacity.value,
            child: _buildControlPanel(band, panelWidth),
          ),
        );
      },
    );
  }

  Widget _buildControlPanel(_Band band, double panelWidth) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [band.color.withOpacity(0.4), band.color.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8)),
          BoxShadow(color: band.color.withOpacity(0.2), blurRadius: 24, spreadRadius: -8),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF5181820),
          borderRadius: BorderRadius.circular(9),
        ),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top accent bar
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, band.color, Colors.transparent],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // === SECTION 1: Power + Shape + Slope ===
                    _buildMiniIconButton(
                      icon: Icons.power_settings_new,
                      active: band.bypassed,
                      activeColor: _Colors.bypass,
                      onTap: () {
                        _pushUndo();
                        band.bypassed = !band.bypassed;
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildMiniShapeSelector(band),
                    if (band.hasSlope) ...[
                      const SizedBox(width: 6),
                      _buildMiniSlopeSelector(band),
                    ],

                    _buildDivider(),

                    // === SECTION 2: FREQ / GAIN / Q ===
                    _buildMiniParam('FREQ', _formatFreq(band.freq), band.color, (d) {
                      final logF = math.log(band.freq);
                      band.freq = math.exp(logF - d * 0.006).clamp(10.0, 30000.0);
                      setState(() {});
                    }),
                    const SizedBox(width: 10),
                    _buildMiniParam('GAIN', _formatGain(band.gain), _Colors.curveMain, (d) {
                      band.gain = (band.gain - d * 0.08).clamp(-30.0, 30.0);
                      setState(() {});
                    }, enabled: band.hasGain, onReset: () {
                      _pushUndo();
                      band.gain = 0;
                      setState(() {});
                    }),
                    const SizedBox(width: 10),
                    _buildMiniParam('Q', band.q.toStringAsFixed(2), _Colors.textPrimary, (d) {
                      band.q = (band.q - d * 0.012).clamp(0.1, 18.0);
                      setState(() {});
                    }, onReset: () {
                      _pushUndo();
                      band.q = 1.0;
                      setState(() {});
                    }),

                    _buildDivider(),

                    // === SECTION 3: Navigation ===
                    _buildMiniIconButton(icon: Icons.chevron_left, onTap: () {
                      if (_selectedBand! > 0) _selectBand(_selectedBand! - 1);
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '${_selectedBand! + 1}/${_bands.length}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: band.color),
                      ),
                    ),
                    _buildMiniIconButton(icon: Icons.chevron_right, onTap: () {
                      if (_selectedBand! < _bands.length - 1) _selectBand(_selectedBand! + 1);
                    }),
                    const SizedBox(width: 10),
                    _buildMiniIconButton(
                      icon: Icons.close,
                      onTap: () {
                        if (_bands.length > 1) {
                          _pushUndo();
                          _bands.removeAt(_selectedBand!);
                          _selectBand(null);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(width: 1, height: 32, color: _Colors.bg5.withOpacity(0.4)),
  );

  Widget _buildMiniIconButton({
    required IconData icon,
    bool active = false,
    Color? activeColor,
    required VoidCallback onTap,
  }) {
    final c = active ? (activeColor ?? _Colors.curveMain) : _Colors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: active ? c.withOpacity(0.2) : _Colors.bg3,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: active ? c.withOpacity(0.5) : _Colors.controlBorder),
          ),
          child: Icon(icon, size: 14, color: c),
        ),
      ),
    );
  }

  Widget _buildMiniShapeSelector(_Band band) {
    return GestureDetector(
      onTap: () {
        _pushUndo();
        final shapes = FilterShape.values;
        band.shape = shapes[(shapes.indexOf(band.shape) + 1) % shapes.length];
        setState(() {});
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _Colors.bg3,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: band.color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(band.shapeIcon, style: TextStyle(fontSize: 10, color: band.color, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              Text(band.shapeName, style: const TextStyle(fontSize: 10, color: _Colors.textPrimary)),
              Icon(Icons.unfold_more, size: 10, color: _Colors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniSlopeSelector(_Band band) {
    return GestureDetector(
      onTap: () {
        _pushUndo();
        final slopes = [6, 12, 18, 24, 36, 48, 72, 96];
        final idx = slopes.indexOf(band.slope);
        band.slope = slopes[(idx + 1) % slopes.length];
        setState(() {});
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _Colors.bg3,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _Colors.controlBorder),
          ),
          child: Center(
            child: Text('${band.slope}dB', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: band.color)),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniParam(String label, String value, Color color, ValueChanged<double> onDrag, {
    bool enabled = true,
    VoidCallback? onReset,
  }) {
    return GestureDetector(
      onVerticalDragStart: enabled ? (_) => _pushUndo() : null,
      onVerticalDragUpdate: enabled ? (d) => onDrag(d.delta.dy) : null,
      onDoubleTap: enabled ? onReset : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: _Colors.textDim, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Container(
                width: 50,
                height: 22,
                decoration: BoxDecoration(
                  color: _Colors.bg1,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: enabled ? color.withOpacity(0.3) : _Colors.controlBorder),
                ),
                child: Center(
                  child: Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: enabled ? color : _Colors.textDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Compact shape button for floating panel
  Widget _buildCompactShapeButton(_Band band) {
    return Tooltip(
      message: 'Filter Shape',
      child: GestureDetector(
        onTap: () {
          _pushUndo();
          final shapes = FilterShape.values;
          band.shape = shapes[(shapes.indexOf(band.shape) + 1) % shapes.length];
          setState(() {});
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _Colors.bg1,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: band.color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                band.shapeIcon,
                style: TextStyle(fontSize: 11, color: band.color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Text(
                band.shapeName,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _Colors.textPrimary),
              ),
              const SizedBox(width: 2),
              Icon(Icons.unfold_more, size: 12, color: _Colors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  // Compact slope button
  Widget _buildCompactSlopeButton(_Band band) {
    return Tooltip(
      message: 'Slope',
      child: GestureDetector(
        onTap: () {
          _pushUndo();
          final slopes = [6, 12, 18, 24, 36, 48, 72, 96];
          final idx = slopes.indexOf(band.slope);
          band.slope = slopes[(idx + 1) % slopes.length];
          setState(() {});
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _Colors.bg1,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _Colors.controlBorder),
          ),
          child: Center(
            child: Text(
              '${band.slope}dB',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: band.color),
            ),
          ),
        ),
      ),
    );
  }

  // Compact value control for floating panel
  Widget _buildCompactValueControl({
    required String label,
    required String value,
    required Color color,
    bool enabled = true,
    required ValueChanged<double> onDrag,
    VoidCallback? onDoubleTap,
  }) {
    return GestureDetector(
      onVerticalDragStart: enabled ? (_) => _pushUndo() : null,
      onVerticalDragUpdate: enabled ? (d) => onDrag(d.delta.dy) : null,
      onDoubleTap: enabled ? onDoubleTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: enabled ? _Colors.textSecondary : _Colors.textDim,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 54,
                height: 24,
                decoration: BoxDecoration(
                  color: _Colors.bg1,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: enabled ? color.withOpacity(0.3) : _Colors.controlBorder,
                  ),
                ),
                child: Center(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: enabled ? color : _Colors.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelIconButton({
    required IconData icon,
    bool active = false,
    Color? activeColor,
    String? tooltip,
    required VoidCallback onTap,
  }) {
    final color = active ? (activeColor ?? _Colors.curveMain) : _Colors.textSecondary;
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.2) : _Colors.bg1,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? color.withOpacity(0.5) : _Colors.controlBorder,
              width: 1,
            ),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _buildShapeButton(_Band band) {
    return Tooltip(
      message: 'Filter Shape (click to cycle)',
      child: GestureDetector(
        onTap: () {
          _pushUndo();
          final shapes = FilterShape.values;
          band.shape = shapes[(shapes.indexOf(band.shape) + 1) % shapes.length];
          setState(() {});
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _Colors.bg1,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: band.color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shape icon with color
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: band.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    band.shapeIcon,
                    style: TextStyle(fontSize: 12, color: band.color, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                band.shapeName,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _Colors.textPrimary),
              ),
              const SizedBox(width: 4),
              Icon(Icons.unfold_more, size: 14, color: _Colors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlopeButton(_Band band) {
    return Tooltip(
      message: 'Slope (click to cycle)',
      child: GestureDetector(
        onTap: () {
          _pushUndo();
          final slopes = [6, 12, 18, 24, 36, 48, 72, 96];
          final idx = slopes.indexOf(band.slope);
          band.slope = slopes[(idx + 1) % slopes.length];
          setState(() {});
        },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _Colors.bg1,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _Colors.controlBorder),
          ),
          child: Center(
            child: Text(
              '${band.slope} dB/oct',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: band.color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValueControl({
    required String label,
    required String value,
    required Color color,
    double width = 56,
    bool enabled = true,
    required ValueChanged<double> onDrag,
    VoidCallback? onDoubleTap,
  }) {
    return GestureDetector(
      onVerticalDragStart: enabled ? (_) => _pushUndo() : null,
      onVerticalDragUpdate: enabled ? (d) => onDrag(d.delta.dy) : null,
      onDoubleTap: enabled ? onDoubleTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label on top
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: enabled ? _Colors.textSecondary : _Colors.textDim,
                ),
              ),
              const SizedBox(height: 4),
              // Value box
              Container(
                width: width,
                height: 28,
                decoration: BoxDecoration(
                  color: _Colors.bg1,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: enabled ? color.withOpacity(0.4) : _Colors.controlBorder,
                    width: 1,
                  ),
                  boxShadow: enabled ? [
                    BoxShadow(
                      color: color.withOpacity(0.1),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ] : null,
                ),
                child: Center(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: enabled ? color : _Colors.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _Colors.bg1,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _Colors.controlBorder),
          ),
          child: Icon(icon, size: 16, color: _Colors.textSecondary),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _Colors.bg2,
        border: Border(top: BorderSide(color: _Colors.bg4)),
      ),
      child: Row(
        children: [
          // Phase mode selector
          _buildPhaseSelector(),

          const Spacer(),

          // Output gain
          const Text('OUTPUT', style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: _Colors.textDim,
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() {
                _outputGain = (_outputGain - d.delta.dy * 0.1).clamp(-12.0, 12.0);
              });
            },
            onDoubleTap: () => setState(() => _outputGain = 0),
            child: Container(
              width: 60,
              height: 24,
              decoration: BoxDecoration(
                color: _Colors.bg1,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: _Colors.controlBorder),
              ),
              child: Center(
                child: Text(
                  '${_outputGain >= 0 ? '+' : ''}${_outputGain.toStringAsFixed(1)} dB',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _Colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Global bypass
          GestureDetector(
            onTap: () => setState(() => _globalBypass = !_globalBypass),
            child: Container(
              width: 32,
              height: 24,
              decoration: BoxDecoration(
                color: _globalBypass ? _Colors.bypass.withOpacity(0.2) : _Colors.controlBg,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _globalBypass ? _Colors.bypass.withOpacity(0.5) : _Colors.controlBorder,
                ),
              ),
              child: Icon(
                Icons.power_settings_new,
                size: 14,
                color: _globalBypass ? _Colors.bypass : _Colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseSelector() {
    final modes = ['ZERO LAT', 'NATURAL', 'LINEAR'];
    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: _Colors.controlBg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final active = i == _phaseMode;
          return GestureDetector(
            onTap: () => setState(() => _phaseMode = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? _Colors.curveMain.withOpacity(0.2) : null,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  modes[i],
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: active ? _Colors.curveMain : _Colors.textDim,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatFreq(double f) {
    if (f >= 10000) return '${(f / 1000).toStringAsFixed(1)}k';
    if (f >= 1000) return '${(f / 1000).toStringAsFixed(2)}k';
    return '${f.toInt()} Hz';
  }

  String _formatGain(double g) {
    return '${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)}';
  }

  double _freqToX(double f, double w) {
    const minF = 10.0, maxF = 30000.0;
    final logMin = math.log(minF) / math.ln10;
    final logMax = math.log(maxF) / math.ln10;
    final logF = math.log(f.clamp(minF, maxF)) / math.ln10;
    return ((logF - logMin) / (logMax - logMin)) * w;
  }

  double _xToFreq(double x, double w) {
    const minF = 10.0, maxF = 30000.0;
    final logMin = math.log(minF) / math.ln10;
    final logMax = math.log(maxF) / math.ln10;
    return math.pow(10, logMin + (x / w) * (logMax - logMin)).toDouble();
  }

  double _gainToY(double g, double h, double range) {
    return (1 - (g + range) / (range * 2)) * h;
  }

  double _yToGain(double y, double h) {
    return (1 - y / h) * (_range * 2) - _range;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ DISPLAY PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _EQDisplayPainter extends CustomPainter {
  final List<_Band> bands;
  final int? selectedBand;
  final int? hoveredBand;
  final double range;
  final List<double>? spectrum;
  final double signalLevel;
  final double glowValue;

  _EQDisplayPainter({
    required this.bands,
    this.selectedBand,
    this.hoveredBand,
    required this.range,
    this.spectrum,
    required this.signalLevel,
    required this.glowValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = _Colors.bg1,
    );

    _drawGrid(canvas, size);

    // Spectrum - ONLY draw when signal present and spectrum has data
    if (spectrum != null && spectrum!.isNotEmpty && signalLevel > 0.02) {
      _drawSpectrum(canvas, size);
    }

    _drawEQCurve(canvas, size);
    _drawBandNodes(canvas, size);
    _drawLabels(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Vertical lines (frequency)
    final freqs = [20, 30, 50, 100, 200, 300, 500, 1000, 2000, 3000, 5000, 10000, 20000];
    for (final f in freqs) {
      final x = _freqToX(f.toDouble(), w);
      final major = [100, 1000, 10000].contains(f);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..color = major ? _Colors.gridMajor : _Colors.gridMinor
          ..strokeWidth = 1,
      );
    }

    // Horizontal lines (gain)
    final step = range <= 6 ? 2.0 : (range <= 12 ? 3.0 : 6.0);
    for (double g = -range; g <= range; g += step) {
      final y = _gainToY(g, h, range);
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = g == 0 ? _Colors.gridMajor : _Colors.gridMinor
          ..strokeWidth = g == 0 ? 1.5 : 1,
      );
    }
  }

  void _drawSpectrum(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = spectrum!.length;

    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = (i / (n - 1)) * w;
      final db = spectrum![i].clamp(-100.0, 0.0);
      // Map dB to screen (0dB at center, spectrum below)
      final normalized = (db + 60) / 60; // -60dB to 0dB mapped to 0-1
      final y = h - (normalized * h * 0.8);
      points.add(Offset(x, y.clamp(0.0, h)));
    }

    if (points.length < 2) return;

    // Build smooth path using Catmull-Rom
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      const t = 0.4;
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) * t / 3,
        p1.dy + (p2.dy - p0.dy) * t / 3,
        p2.dx - (p3.dx - p1.dx) * t / 3,
        p2.dy - (p3.dy - p1.dy) * t / 3,
        p2.dx,
        p2.dy,
      );
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final opacity = signalLevel * 0.8;
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, h),
          [
            _Colors.spectrumFill.withOpacity(opacity * 0.5),
            _Colors.spectrumFill.withOpacity(opacity * 0.02),
          ],
        ),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = _Colors.spectrumLine.withOpacity(opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawEQCurve(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const n = 512;

    final points = <Offset>[];
    for (int i = 0; i <= n; i++) {
      final x = (i / n) * w;
      final freq = _xToFreq(x, w);

      double totalGain = 0;
      for (final b in bands) {
        if (!b.enabled || b.bypassed) continue;
        totalGain += _getBandResponse(b, freq);
      }

      final y = _gainToY(totalGain.clamp(-range, range), h, range);
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // Build smooth curve
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      const t = 0.3;
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) * t / 2,
        p1.dy + (p2.dy - p0.dy) * t / 2,
        p2.dx - (p3.dx - p1.dx) * t / 2,
        p2.dy - (p3.dy - p1.dy) * t / 2,
        p2.dx,
        p2.dy,
      );
    }

    // Fill under curve
    final zeroY = _gainToY(0, h, range);
    final fillPath = Path.from(path)
      ..lineTo(w, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = _Colors.curveFill);

    // Glow effect
    final glowOpacity = 0.3 + glowValue * 0.15;
    canvas.drawPath(
      path,
      Paint()
        ..color = _Colors.curveGlow.withOpacity(glowOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Main curve - thick yellow/orange
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(w, 0),
          [_Colors.curveDark, _Colors.curveMain, _Colors.curveLight, _Colors.curveMain, _Colors.curveDark],
          [0.0, 0.25, 0.5, 0.75, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  double _getBandResponse(_Band b, double f) {
    final f0 = b.freq, g = b.gain, q = b.q;
    final ratio = f / f0;

    switch (b.shape) {
      case FilterShape.bell:
        // Parametric bell with Q control
        final logRatio = math.log(ratio) / math.ln2;
        final bandwidth = 1.0 / q;
        return g * math.exp(-0.5 * math.pow(logRatio / bandwidth, 2));

      case FilterShape.lowShelf:
        // Smooth low shelf transition
        if (ratio <= 0.5) return g;
        if (ratio >= 2.0) return 0;
        final t = (ratio - 0.5) / 1.5;
        return g * (1 - t * t * (3 - 2 * t));

      case FilterShape.highShelf:
        // Smooth high shelf transition
        if (ratio >= 2.0) return g;
        if (ratio <= 0.5) return 0;
        final t = (ratio - 0.5) / 1.5;
        return g * t * t * (3 - 2 * t);

      case FilterShape.lowCut:
        // Butterworth highpass: -3dB at cutoff, 0dB passband above
        final order = b.slope ~/ 6;
        final x = math.pow(ratio, order * 2).toDouble();
        final magnitude = math.sqrt(x / (1.0 + x));
        if (magnitude <= 0) return -100.0;
        return (20 * math.log(magnitude) / math.ln10).clamp(-100.0, 0.0);

      case FilterShape.highCut:
        // Butterworth lowpass: -3dB at cutoff, 0dB passband below
        final order = b.slope ~/ 6;
        final x = math.pow(ratio, order * 2).toDouble();
        final magnitude = 1.0 / math.sqrt(1.0 + x);
        if (magnitude <= 0) return -100.0;
        return (20 * math.log(magnitude) / math.ln10).clamp(-100.0, 0.0);

      case FilterShape.notch:
        final logRatio = math.log(ratio) / math.ln2;
        final bw = 0.5 / q;
        if (logRatio.abs() > bw * 3) return 0;
        return -30 * math.exp(-0.5 * math.pow(logRatio / bw, 2));

      case FilterShape.bandPass:
        final logRatio = math.log(ratio) / math.ln2;
        final bw = 1.0 / q;
        final atten = -60 * math.pow(logRatio.abs() / bw, 2);
        return atten.clamp(-60.0, 0.0).toDouble();

      case FilterShape.tiltShelf:
        final logRatio = math.log(ratio) / math.ln2;
        return g * (logRatio / 3).clamp(-1.0, 1.0);

      case FilterShape.flatTilt:
        final logRatio = math.log(ratio) / math.ln2;
        return g * (logRatio / 5).clamp(-1.0, 1.0);

      case FilterShape.allPass:
        return 0;
    }
  }

  void _drawBandNodes(Canvas canvas, Size size) {
    for (int i = 0; i < bands.length; i++) {
      _drawNode(canvas, size, i);
    }
  }

  void _drawNode(Canvas canvas, Size size, int index) {
    final b = bands[index];
    final x = _freqToX(b.freq, size.width);
    final y = b.hasGain
        ? _gainToY(b.gain, size.height, range)
        : _gainToY(0, size.height, range);

    final isSelected = index == selectedBand;
    final isHovered = index == hoveredBand;
    final isActive = isSelected || isHovered;

    final color = b.color;
    final opacity = b.enabled && !b.bypassed ? 1.0 : 0.4;
    final radius = isActive ? 12.0 : 10.0;

    // Outer glow for active
    if (isActive) {
      canvas.drawCircle(
        Offset(x, y),
        radius + 8,
        Paint()
          ..color = color.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Main circle
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            Color.lerp(color, Colors.white, 0.3)!,
            color,
            Color.lerp(color, Colors.black, 0.2)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius)),
    );

    // Inner dark circle
    canvas.drawCircle(
      Offset(x, y),
      radius - 4,
      Paint()..color = _Colors.bg1.withOpacity(0.7),
    );

    // Band number
    final tp = TextPainter(
      text: TextSpan(
        text: '${b.id + 1}',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color.withOpacity(opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));

    // Bypass indicator
    if (b.bypassed) {
      final p = Paint()
        ..color = _Colors.bypass
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x - 5, y - 5), Offset(x + 5, y + 5), p);
      canvas.drawLine(Offset(x + 5, y - 5), Offset(x - 5, y + 5), p);
    }
  }

  void _drawLabels(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Frequency labels
    for (final f in [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]) {
      final x = _freqToX(f.toDouble(), w);
      final label = f >= 1000 ? '${f ~/ 1000}k' : '$f';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 9, color: _Colors.textDim),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, h - tp.height - 4));
    }

    // Gain labels
    final step = range <= 6 ? 3.0 : (range <= 12 ? 6.0 : 12.0);
    for (double g = -range; g <= range; g += step) {
      final y = _gainToY(g, h, range);
      final label = g == 0 ? '0' : (g > 0 ? '+${g.toInt()}' : '${g.toInt()}');
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 9, color: _Colors.textDim),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }
  }

  // Helper methods
  double _freqToX(double f, double w) {
    const minF = 10.0, maxF = 30000.0;
    final logMin = math.log(minF) / math.ln10;
    final logMax = math.log(maxF) / math.ln10;
    final logF = math.log(f.clamp(minF, maxF)) / math.ln10;
    return ((logF - logMin) / (logMax - logMin)) * w;
  }

  double _xToFreq(double x, double w) {
    const minF = 10.0, maxF = 30000.0;
    final logMin = math.log(minF) / math.ln10;
    final logMax = math.log(maxF) / math.ln10;
    return math.pow(10, logMin + (x / w) * (logMax - logMin)).toDouble();
  }

  double _gainToY(double g, double h, double range) {
    return (1 - (g + range) / (range * 2)) * h;
  }

  @override
  bool shouldRepaint(covariant _EQDisplayPainter old) => true;
}
