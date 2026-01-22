/// FabFilter Pro-R Style Reverb Panel
///
/// Inspired by Pro-R 2's interface:
/// - Real-time decay visualization
/// - Space-based parameter control
/// - Distance/Character/Stereo sections
/// - Pre-delay with tempo sync
/// - EQ and damping controls

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Reverb space type (inspired by Pro-R)
enum ReverbSpace {
  room('Room', 'Small intimate room'),
  studio('Studio', 'Recording studio ambience'),
  hall('Hall', 'Concert hall'),
  chamber('Chamber', 'Reverb chamber'),
  plate('Plate', 'Classic plate reverb'),
  cathedral('Cathedral', 'Large cathedral space'),
  vintage('Vintage', 'Vintage hardware emulation'),
  shimmer('Shimmer', 'Shimmering pitch-shifted tails');

  final String label;
  final String description;
  const ReverbSpace(this.label, this.description);
}

/// Decay rate mode
enum DecayMode {
  linear('Linear'),
  exponential('Exponential'),
  inverse('Inverse');

  final String label;
  const DecayMode(this.label);
}

/// EQ band for reverb coloring
class ReverbEqBand {
  final int index;
  double freq;
  double gain;
  bool enabled;

  ReverbEqBand({
    required this.index,
    this.freq = 1000,
    this.gain = 0,
    this.enabled = true,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterReverbPanel extends FabFilterPanelBase {
  const FabFilterReverbPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'Reverb',
          icon: Icons.waves,
          accentColor: FabFilterColors.purple,
        );

  @override
  State<FabFilterReverbPanel> createState() => _FabFilterReverbPanelState();
}

class _FabFilterReverbPanelState extends State<FabFilterReverbPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  // Main parameters
  double _brightness = 0.5; // 0-1 (dark to bright)
  double _size = 0.5; // 0-1 (room size)
  double _decay = 2.0; // seconds
  double _mix = 30.0; // %
  double _predelay = 20.0; // ms

  // Character
  double _distance = 50.0; // % (near to far)
  double _width = 100.0; // %
  double _modulation = 0.0; // %
  double _diffusion = 80.0; // %

  // Damping
  double _dampingHigh = 0.5; // 0-1
  double _dampingLow = 0.2; // 0-1
  double _dampingFreq = 4000.0; // Hz

  // Space
  ReverbSpace _space = ReverbSpace.hall;
  DecayMode _decayMode = DecayMode.exponential;

  // EQ bands
  List<ReverbEqBand> _eqBands = [];
  bool _eqVisible = false;

  // Display
  bool _compactView = false;

  // Animation
  late AnimationController _decayController;
  double _animatedDecay = 0.0;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  @override
  void initState() {
    super.initState();

    // Initialize FFI reverb
    _initializeProcessor();

    // Initialize EQ bands
    _eqBands = [
      ReverbEqBand(index: 0, freq: 80, gain: 0),
      ReverbEqBand(index: 1, freq: 500, gain: 0),
      ReverbEqBand(index: 2, freq: 2000, gain: 0),
      ReverbEqBand(index: 3, freq: 8000, gain: 0),
    ];

    // Decay animation
    _decayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_updateDecayAnimation);

    _decayController.repeat();
  }

  void _initializeProcessor() {
    final success = _ffi.algorithmicReverbCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      _initialized = true;
      _applyAllParameters();
    }
  }

  void _applyAllParameters() {
    if (!_initialized) return;
    _ffi.algorithmicReverbSetRoomSize(widget.trackId, _size);
    _ffi.algorithmicReverbSetDamping(widget.trackId, _dampingHigh);
    _ffi.algorithmicReverbSetWidth(widget.trackId, _width / 100.0);
    _ffi.algorithmicReverbSetDryWet(widget.trackId, _mix / 100.0);
    _ffi.algorithmicReverbSetPredelay(widget.trackId, _predelay);
    _ffi.algorithmicReverbSetType(widget.trackId, _spaceToReverbType(_space));
  }

  ReverbType _spaceToReverbType(ReverbSpace space) {
    return switch (space) {
      ReverbSpace.room => ReverbType.room,
      ReverbSpace.studio => ReverbType.room,
      ReverbSpace.hall => ReverbType.hall,
      ReverbSpace.chamber => ReverbType.chamber,
      ReverbSpace.plate => ReverbType.plate,
      ReverbSpace.cathedral => ReverbType.hall,
      ReverbSpace.vintage => ReverbType.chamber,
      ReverbSpace.shimmer => ReverbType.hall,
    };
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _decayController.dispose();
    if (_initialized) {
      _ffi.algorithmicReverbRemove(widget.trackId);
    }
    super.dispose();
  }

  void _updateDecayAnimation() {
    setState(() {
      // Simulate decay envelope animation
      final t = (_decayController.value * 10) % _decay;
      _animatedDecay = math.exp(-t / (_decay * 0.3));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD — Compact horizontal layout, NO scrolling
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          // Compact header
          _buildCompactHeader(),
          // Main content — horizontal layout, no scroll
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT: Decay visualization (compact)
                  _buildCompactDisplay(),
                  const SizedBox(width: 12),
                  // CENTER: Main knobs
                  Expanded(flex: 3, child: _buildCompactControls()),
                  const SizedBox(width: 12),
                  // RIGHT: Space + options
                  _buildCompactOptions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FabFilterColors.borderSubtle))),
      child: Row(
        children: [
          Icon(widget.icon, color: widget.accentColor, size: 14),
          const SizedBox(width: 6),
          Text(widget.title, style: FabFilterText.title.copyWith(fontSize: 11)),
          const SizedBox(width: 12),
          // Space selector dropdown
          _buildCompactSpaceDropdown(),
          const Spacer(),
          _buildCompactAB(),
          const SizedBox(width: 8),
          _buildCompactBypass(),
        ],
      ),
    );
  }

  Widget _buildCompactSpaceDropdown() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ReverbSpace>(
          value: _space,
          dropdownColor: FabFilterColors.bgDeep,
          style: FabFilterText.paramLabel.copyWith(fontSize: 10),
          icon: Icon(Icons.arrow_drop_down, size: 14, color: FabFilterColors.textMuted),
          isDense: true,
          items: ReverbSpace.values.map((s) => DropdownMenuItem(
            value: s,
            child: Text(s.label, style: const TextStyle(fontSize: 10)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _space = v);
              _ffi.algorithmicReverbSetType(widget.trackId, _spaceToReverbType(v));
            }
          },
        ),
      ),
    );
  }

  Widget _buildCompactAB() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMiniButton('A', !isStateB, () { if (isStateB) toggleAB(); }),
        const SizedBox(width: 2),
        _buildMiniButton('B', isStateB, () { if (!isStateB) toggleAB(); }),
      ],
    );
  }

  Widget _buildMiniButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: active ? widget.accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? widget.accentColor : FabFilterColors.border),
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? widget.accentColor : FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _buildCompactBypass() {
    return GestureDetector(
      onTap: toggleBypass,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bypassed ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: bypassed ? FabFilterColors.orange : FabFilterColors.border),
        ),
        child: Text('BYP', style: TextStyle(color: bypassed ? FabFilterColors.orange : FabFilterColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCompactDisplay() {
    return SizedBox(
      width: 120,
      child: Container(
        decoration: FabFilterDecorations.display(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            painter: _ReverbDisplayPainter(
              decay: _decay,
              predelay: _predelay,
              size: _size,
              dampingHigh: _dampingHigh,
              animatedDecay: _animatedDecay,
              brightness: _brightness,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSmallKnob(
          value: _size,
          label: 'SIZE',
          display: '${(_size * 100).toStringAsFixed(0)}%',
          color: FabFilterColors.purple,
          onChanged: (v) {
            setState(() => _size = v);
            _ffi.algorithmicReverbSetRoomSize(widget.trackId, v);
          },
        ),
        _buildSmallKnob(
          value: math.log(_decay / 0.1) / math.log(20 / 0.1),
          label: 'DECAY',
          display: _decay >= 1 ? '${_decay.toStringAsFixed(1)}s' : '${(_decay * 1000).toStringAsFixed(0)}ms',
          color: FabFilterColors.purple,
          onChanged: (v) => setState(() => _decay = 0.1 * math.pow(20 / 0.1, v).toDouble()),
        ),
        _buildSmallKnob(
          value: _brightness,
          label: 'BRIGHT',
          display: '${(_brightness * 100).toStringAsFixed(0)}%',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _brightness = v);
            _ffi.algorithmicReverbSetDamping(widget.trackId, 1 - v);
          },
        ),
        _buildSmallKnob(
          value: math.log(_predelay / 1) / math.log(200 / 1),
          label: 'PRE',
          display: '${_predelay.toStringAsFixed(0)}ms',
          color: FabFilterColors.blue,
          onChanged: (v) {
            setState(() => _predelay = 1 * math.pow(200 / 1, v).toDouble());
            _ffi.algorithmicReverbSetPredelay(widget.trackId, _predelay);
          },
        ),
        _buildSmallKnob(
          value: _mix / 100,
          label: 'MIX',
          display: '${_mix.toStringAsFixed(0)}%',
          color: FabFilterColors.green,
          onChanged: (v) {
            setState(() => _mix = v * 100);
            _ffi.algorithmicReverbSetDryWet(widget.trackId, v);
          },
        ),
        _buildSmallKnob(
          value: _width / 200,
          label: 'WIDTH',
          display: '${_width.toStringAsFixed(0)}%',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _width = v * 200);
            _ffi.algorithmicReverbSetWidth(widget.trackId, v * 2);
          },
        ),
      ],
    );
  }

  Widget _buildSmallKnob({
    required double value,
    required String label,
    required String display,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return FabFilterKnob(value: value.clamp(0.0, 1.0), label: label, display: display, color: color, size: 48, onChanged: onChanged);
  }

  Widget _buildCompactOptions() {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Character controls compact
          _buildMiniSlider('Dist', _distance / 100, '${_distance.toStringAsFixed(0)}%', (v) => setState(() => _distance = v * 100)),
          const SizedBox(height: 4),
          _buildMiniSlider('Diff', _diffusion / 100, '${_diffusion.toStringAsFixed(0)}%', (v) => setState(() => _diffusion = v * 100)),
          const Spacer(),
          // Damping (expert)
          if (showExpertMode) ...[
            Text('DAMPING', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
            const SizedBox(height: 2),
            _buildMiniSlider('Lo', _dampingLow, '${(_dampingLow * 100).toStringAsFixed(0)}%', (v) => setState(() => _dampingLow = v)),
            _buildMiniSlider('Hi', _dampingHigh, '${(_dampingHigh * 100).toStringAsFixed(0)}%', (v) {
              setState(() => _dampingHigh = v);
              _ffi.algorithmicReverbSetDamping(widget.trackId, v);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniSlider(String label, double value, String display, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          SizedBox(width: 22, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: FabFilterColors.purple,
                inactiveTrackColor: FabFilterColors.bgVoid,
                thumbColor: FabFilterColors.purple,
              ),
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
          ),
          SizedBox(width: 28, child: Text(display, style: FabFilterText.paramLabel.copyWith(fontSize: 8), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB DISPLAY PAINTER (Decay visualization)
// ═══════════════════════════════════════════════════════════════════════════

class _ReverbDisplayPainter extends CustomPainter {
  final double decay;
  final double predelay;
  final double size;
  final double dampingHigh;
  final double animatedDecay;
  final double brightness;

  _ReverbDisplayPainter({
    required this.decay,
    required this.predelay,
    required this.size,
    required this.dampingHigh,
    required this.animatedDecay,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final rect = Offset.zero & canvasSize;

    // Background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, canvasSize.height),
        [
          FabFilterColors.bgVoid,
          FabFilterColors.bgDeep,
        ],
      );
    canvas.drawRect(rect, bgPaint);

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    // Time grid
    final maxTime = decay * 1.5;
    for (var i = 1; i <= 4; i++) {
      final x = (i / 5) * canvasSize.width;
      canvas.drawLine(Offset(x, 0), Offset(x, canvasSize.height), gridPaint);
    }

    // Amplitude grid
    for (var i = 1; i < 4; i++) {
      final y = (i / 4) * canvasSize.height;
      canvas.drawLine(Offset(0, y), Offset(canvasSize.width, y), gridPaint);
    }

    // Pre-delay region
    final predelayX = (predelay / 1000) / maxTime * canvasSize.width;
    final predelayPaint = Paint()
      ..color = FabFilterColors.blue.withValues(alpha: 0.2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, predelayX, canvasSize.height),
      predelayPaint,
    );

    // Pre-delay line
    canvas.drawLine(
      Offset(predelayX, 0),
      Offset(predelayX, canvasSize.height),
      Paint()
        ..color = FabFilterColors.blue
        ..strokeWidth = 1,
    );

    // Decay envelope
    final decayPath = Path();
    final decayPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, canvasSize.height),
        [
          FabFilterColors.purple.withValues(alpha: 0.8),
          FabFilterColors.purple.withValues(alpha: 0.1),
        ],
      );

    decayPath.moveTo(predelayX, canvasSize.height);

    // Draw exponential decay curve
    for (var x = predelayX; x <= canvasSize.width; x += 2) {
      final t = ((x - predelayX) / canvasSize.width) * maxTime;
      final amplitude = math.exp(-t / (decay * 0.3 * (1 + size)));
      final y = canvasSize.height * (1 - amplitude);

      decayPath.lineTo(x, y);
    }

    decayPath.lineTo(canvasSize.width, canvasSize.height);
    decayPath.close();
    canvas.drawPath(decayPath, decayPaint);

    // Decay curve outline
    final outlinePath = Path();
    outlinePath.moveTo(predelayX, canvasSize.height * 0.1);

    for (var x = predelayX; x <= canvasSize.width; x += 2) {
      final t = ((x - predelayX) / canvasSize.width) * maxTime;
      final amplitude = math.exp(-t / (decay * 0.3 * (1 + size)));
      final y = canvasSize.height * (1 - amplitude * 0.9);

      outlinePath.lineTo(x, y);
    }

    canvas.drawPath(
      outlinePath,
      Paint()
        ..color = FabFilterColors.purple
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Early reflections (small spikes)
    final erPaint = Paint()
      ..color = FabFilterColors.cyan
      ..strokeWidth = 1;

    final random = math.Random(42); // Deterministic
    final erCount = (size * 10 + 5).toInt();
    for (var i = 0; i < erCount; i++) {
      final t = predelay / 1000 + random.nextDouble() * size * 0.1;
      final x = (t / maxTime) * canvasSize.width;
      final amplitude = 0.3 + random.nextDouble() * 0.4;
      final y = canvasSize.height * (1 - amplitude);

      if (x > predelayX && x < canvasSize.width) {
        canvas.drawLine(
          Offset(x, canvasSize.height),
          Offset(x, y),
          erPaint,
        );
      }
    }

    // Animated level indicator
    final indicatorX = predelayX + (canvasSize.width - predelayX) * 0.05;
    final indicatorY = canvasSize.height * (1 - animatedDecay * 0.8);

    canvas.drawCircle(
      Offset(indicatorX, indicatorY),
      4,
      Paint()..color = FabFilterColors.green,
    );

    // Labels
    _drawLabel(canvas, 'Pre-delay', Offset(4, canvasSize.height - 14));
    _drawLabel(
        canvas, '${decay.toStringAsFixed(1)}s', Offset(canvasSize.width - 40, 4));
  }

  void _drawLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: FabFilterColors.textMuted,
          fontSize: 9,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ReverbDisplayPainter oldDelegate) =>
      oldDelegate.decay != decay ||
      oldDelegate.predelay != predelay ||
      oldDelegate.size != size ||
      oldDelegate.animatedDecay != animatedDecay;
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB EQ PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _ReverbEqPainter extends CustomPainter {
  final List<ReverbEqBand> bands;

  _ReverbEqPainter({required this.bands});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRect(rect, Paint()..color = FabFilterColors.bgVoid);

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    // Frequency grid
    for (final freq in [100, 1000, 10000]) {
      final x = _freqToX(freq.toDouble(), size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // 0dB line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Draw EQ curve
    final curvePaint = Paint()
      ..color = FabFilterColors.purple
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final curvePath = Path();
    curvePath.moveTo(0, size.height / 2);

    for (var i = 0; i < size.width; i += 2) {
      final freq = _xToFreq(i.toDouble(), size.width);
      var totalGain = 0.0;

      for (final band in bands) {
        if (!band.enabled) continue;
        final octaves = (math.log(freq / band.freq) / math.ln2).abs();
        final response = band.gain * math.exp(-octaves * octaves * 2);
        totalGain += response;
      }

      final y = size.height / 2 - (totalGain / 12) * (size.height / 2);
      curvePath.lineTo(i.toDouble(), y.clamp(0, size.height));
    }

    canvas.drawPath(curvePath, curvePaint);

    // Band markers
    final markerPaint = Paint()
      ..color = FabFilterColors.purple
      ..style = PaintingStyle.fill;

    for (final band in bands) {
      if (!band.enabled) continue;
      final x = _freqToX(band.freq, size.width);
      final y = size.height / 2 - (band.gain / 12) * (size.height / 2);

      canvas.drawCircle(
        Offset(x, y.clamp(4, size.height - 4)),
        4,
        markerPaint,
      );
    }
  }

  double _freqToX(double freq, double width) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    return width *
        (math.log(freq / minFreq) / math.log(maxFreq / minFreq)).clamp(0, 1);
  }

  double _xToFreq(double x, double width) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    return minFreq * math.pow(maxFreq / minFreq, x / width);
  }

  @override
  bool shouldRepaint(covariant _ReverbEqPainter oldDelegate) => true;
}
