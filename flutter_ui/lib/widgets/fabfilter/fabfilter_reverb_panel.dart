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
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Display section
                  if (!_compactView) ...[
                    _buildDisplaySection(),
                    const SizedBox(height: 16),
                  ],

                  // Main controls
                  _buildMainControls(),
                  const SizedBox(height: 16),

                  // Space selection
                  _buildSpaceSection(),
                  const SizedBox(height: 16),

                  // Character controls
                  _buildCharacterSection(),

                  // Expert: EQ & Damping
                  if (showExpertMode) ...[
                    const SizedBox(height: 16),
                    _buildDampingSection(),
                    if (_eqVisible) ...[
                      const SizedBox(height: 16),
                      _buildEqSection(),
                    ],
                  ],
                ],
              ),
            ),
          ),
          buildBottomBar(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPLAY SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDisplaySection() {
    return Container(
      height: 140,
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN CONTROLS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMainControls() {
    return buildSection(
      'REVERB',
      Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          // Size
          FabFilterKnob(
            value: _size,
            label: 'SIZE',
            display: '${(_size * 100).toStringAsFixed(0)}%',
            color: FabFilterColors.purple,
            onChanged: (v) {
              setState(() => _size = v);
              _ffi.algorithmicReverbSetRoomSize(widget.trackId, v);
            },
          ),

          // Decay
          FabFilterKnob(
            value: math.log(_decay / 0.1) / math.log(20 / 0.1),
            label: 'DECAY',
            display: _decay >= 1
                ? '${_decay.toStringAsFixed(1)}s'
                : '${(_decay * 1000).toStringAsFixed(0)}ms',
            color: FabFilterColors.purple,
            onChanged: (v) {
              setState(() => _decay = 0.1 * math.pow(20 / 0.1, v).toDouble());
              // Decay mapped via damping in FFI
            },
          ),

          // Brightness
          FabFilterKnob(
            value: _brightness,
            label: 'BRIGHTNESS',
            display: '${(_brightness * 100).toStringAsFixed(0)}%',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _brightness = v);
              // Brightness affects high damping
              _ffi.algorithmicReverbSetDamping(widget.trackId, 1 - v);
            },
          ),

          // Pre-delay
          FabFilterKnob(
            value: math.log(_predelay / 1) / math.log(200 / 1),
            label: 'PRE-DELAY',
            display: '${_predelay.toStringAsFixed(0)} ms',
            color: FabFilterColors.blue,
            onChanged: (v) {
              setState(() => _predelay = 1 * math.pow(200 / 1, v).toDouble());
              _ffi.algorithmicReverbSetPredelay(widget.trackId, _predelay);
            },
          ),

          // Mix
          FabFilterKnob(
            value: _mix / 100,
            label: 'MIX',
            display: '${_mix.toStringAsFixed(0)}%',
            color: FabFilterColors.green,
            onChanged: (v) {
              setState(() => _mix = v * 100);
              _ffi.algorithmicReverbSetDryWet(widget.trackId, v);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SPACE SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSpaceSection() {
    return buildSection(
      'SPACE',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Space buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReverbSpace.values.map((space) {
              final isSelected = _space == space;
              return GestureDetector(
                onTap: () {
                  setState(() => _space = space);
                  _ffi.algorithmicReverbSetType(widget.trackId, _spaceToReverbType(space));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: isSelected
                      ? FabFilterDecorations.toggleActive(FabFilterColors.purple)
                      : FabFilterDecorations.toggleInactive(),
                  child: Text(
                    space.label,
                    style: TextStyle(
                      color: isSelected
                          ? FabFilterColors.purple
                          : FabFilterColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          // Description
          Text(
            _space.description,
            style: FabFilterTextStyles.label.copyWith(
              color: FabFilterColors.textMuted,
            ),
          ),

          const SizedBox(height: 12),

          // Options
          Row(
            children: [
              buildToggle(
                'Compact',
                _compactView,
                (v) => setState(() => _compactView = v),
              ),
              if (showExpertMode) ...[
                const SizedBox(width: 16),
                buildToggle(
                  'EQ',
                  _eqVisible,
                  (v) => setState(() => _eqVisible = v),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHARACTER SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCharacterSection() {
    return buildSection(
      'CHARACTER',
      Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          // Distance
          FabFilterKnob(
            value: _distance / 100,
            label: 'DISTANCE',
            display: '${_distance.toStringAsFixed(0)}%',
            color: FabFilterColors.blue,
            onChanged: (v) => setState(() => _distance = v * 100),
          ),

          // Width
          FabFilterKnob(
            value: _width / 200, // 0-200%
            label: 'WIDTH',
            display: '${_width.toStringAsFixed(0)}%',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _width = v * 200);
              _ffi.algorithmicReverbSetWidth(widget.trackId, v * 2);
            },
          ),

          // Diffusion
          FabFilterKnob(
            value: _diffusion / 100,
            label: 'DIFFUSION',
            display: '${_diffusion.toStringAsFixed(0)}%',
            color: FabFilterColors.purple,
            onChanged: (v) => setState(() => _diffusion = v * 100),
          ),

          // Modulation
          if (showExpertMode)
            FabFilterKnob(
              value: _modulation / 100,
              label: 'MODULATION',
              display: '${_modulation.toStringAsFixed(0)}%',
              color: FabFilterColors.orange,
              onChanged: (v) => setState(() => _modulation = v * 100),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DAMPING SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDampingSection() {
    return buildSection(
      'DAMPING',
      Row(
        children: [
          Expanded(
            child: _buildSimpleSlider(
              'Low',
              _dampingLow,
              '${(_dampingLow * 100).toStringAsFixed(0)}%',
              FabFilterColors.orange,
              (v) => setState(() => _dampingLow = v),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildSimpleSlider(
              'High',
              _dampingHigh,
              '${(_dampingHigh * 100).toStringAsFixed(0)}%',
              FabFilterColors.cyan,
              (v) {
                setState(() => _dampingHigh = v);
                _ffi.algorithmicReverbSetDamping(widget.trackId, v);
              },
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 120,
            child: _buildSimpleSlider(
              'Freq',
              math.log(_dampingFreq / 500) / math.log(16000 / 500),
              _dampingFreq >= 1000
                  ? '${(_dampingFreq / 1000).toStringAsFixed(1)}k'
                  : '${_dampingFreq.toStringAsFixed(0)} Hz',
              FabFilterColors.purple,
              (v) => setState(
                  () => _dampingFreq = 500 * math.pow(16000 / 500, v).toDouble()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleSlider(
    String label,
    double value,
    String display,
    Color color,
    ValueChanged<double>? onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 35,
          child: Text(label, style: FabFilterTextStyles.label),
        ),
        Expanded(
          child: SliderTheme(
            data: fabFilterSliderTheme(color),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            display,
            style: FabFilterTextStyles.value.copyWith(color: color),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EQ SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEqSection() {
    return buildSection(
      'REVERB EQ',
      Container(
        height: 100,
        decoration: FabFilterDecorations.display(),
        padding: const EdgeInsets.all(8),
        child: CustomPaint(
          painter: _ReverbEqPainter(bands: _eqBands),
          size: Size.infinite,
        ),
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
