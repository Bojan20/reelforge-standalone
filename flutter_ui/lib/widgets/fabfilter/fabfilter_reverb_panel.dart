/// FF-R Reverb Panel (FDN 8×8 — 2026 Upgrade)
///
/// Mastering-grade reverb interface with 15 parameters:
/// - Space, Brightness, Width, Mix, PreDelay, Style
/// - Diffusion, Distance, Decay, Low/High Decay Mult
/// - Character, Thickness, Ducking, Freeze
/// - Real-time decay visualization
/// - Equal-power crossfade mix control

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Reverb space type
enum ReverbSpace {
  room('Room', 'Small intimate room'),
  hall('Hall', 'Concert hall'),
  plate('Plate', 'Classic plate reverb'),
  chamber('Chamber', 'Reverb chamber'),
  spring('Spring', 'Spring reverb emulation');

  final String label;
  final String description;
  const ReverbSpace(this.label, this.description);
}

// ═══════════════════════════════════════════════════════════════════════════
// PARAM INDICES — must match ReverbWrapper in dsp_wrappers.rs
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const space = 0;
  static const brightness = 1;
  static const width = 2;
  static const mix = 3;
  static const predelay = 4;
  static const style = 5;
  static const diffusion = 6;
  static const distance = 7;
  static const decay = 8;
  static const lowDecay = 9;
  static const highDecay = 10;
  static const character = 11;
  static const thickness = 12;
  static const ducking = 13;
  static const freeze = 14;
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterReverbPanel extends FabFilterPanelBase {
  const FabFilterReverbPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-R',
          icon: Icons.waves,
          accentColor: FabFilterColors.purple,
          nodeType: DspNodeType.reverb,
        );

  @override
  State<FabFilterReverbPanel> createState() => _FabFilterReverbPanelState();
}

class _FabFilterReverbPanelState extends State<FabFilterReverbPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE — All 15 parameters
  // ─────────────────────────────────────────────────────────────────────────

  // Primary controls (row 1)
  double _space = 0.5;       // 0-1 (room size)
  double _brightness = 0.5;  // 0-1 (high freq damping inverted)
  double _decay = 0.5;       // 0-1 (mapped to feedback gain)
  double _mix = 0.3;         // 0-1 (equal-power crossfade)
  double _predelay = 20.0;   // ms (0-500)
  double _width = 1.0;       // 0-2 (M/S stereo width)
  ReverbSpace _spaceType = ReverbSpace.hall;

  // Character controls (row 2)
  double _diffusion = 0.7;   // 0-1
  double _distance = 0.3;    // 0-1 (ER level)
  double _character = 0.0;   // 0-1 (modulation depth)
  double _thickness = 0.0;   // 0-1 (tanh saturation)

  // Tonal shaping
  double _lowDecay = 1.0;    // 0.5-2.0 (low freq decay multiplier)
  double _highDecay = 0.5;   // 0.1-1.0 (high freq decay multiplier)

  // Special
  double _ducking = 0.0;     // 0-1 (self-ducking amount)
  bool _freeze = false;      // infinite sustain

  // Display
  bool _showAdvanced = false;

  // Animation
  late AnimationController _decayController;
  double _animatedDecay = 0.0;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // DspChainProvider integration
  String? _nodeId;
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();

    _decayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_updateDecayAnimation);
    _decayController.repeat();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);

    // Auto-add reverb to chain if not present
    if (!chain.nodes.any((n) => n.type == DspNodeType.reverb)) {
      dsp.addNode(widget.trackId, DspNodeType.reverb);
      chain = dsp.getChain(widget.trackId);
    }

    for (final node in chain.nodes) {
      if (node.type == DspNodeType.reverb) {
        _nodeId = node.id;
        _slotIndex = chain.nodes.indexWhere((n) => n.id == _nodeId);
        _initialized = true;
        _readParamsFromEngine();
        break;
      }
    }
  }

  void _readParamsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    setState(() {
      _space = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.space);
      _brightness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.brightness);
      _width = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.width);
      _mix = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.mix);
      _predelay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.predelay);
      final typeIdx = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.style).round();
      _spaceType = _typeIndexToSpace(typeIdx);
      _diffusion = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.diffusion);
      _distance = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.distance);
      _decay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.decay);
      _lowDecay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.lowDecay);
      _highDecay = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.highDecay);
      _character = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.character);
      _thickness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.thickness);
      _ducking = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.ducking);
      _freeze = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.freeze) > 0.5;
    });
  }

  ReverbSpace _typeIndexToSpace(int typeIndex) {
    return switch (typeIndex) {
      0 => ReverbSpace.room,
      1 => ReverbSpace.hall,
      2 => ReverbSpace.plate,
      3 => ReverbSpace.chamber,
      4 => ReverbSpace.spring,
      _ => ReverbSpace.room,
    };
  }

  int _spaceToTypeIndex(ReverbSpace space) {
    return switch (space) {
      ReverbSpace.room => 0,
      ReverbSpace.hall => 1,
      ReverbSpace.plate => 2,
      ReverbSpace.chamber => 3,
      ReverbSpace.spring => 4,
    };
  }

  void _setParam(int index, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, index, value);
    }
  }

  @override
  void dispose() {
    _decayController.dispose();
    super.dispose();
  }

  void _updateDecayAnimation() {
    final decayTime = 0.1 * math.pow(20 / 0.1, _decay).toDouble();
    setState(() {
      final t = (_decayController.value * 10) % decayTime;
      _animatedDecay = math.exp(-t / (decayTime * 0.3));
    });
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
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  // TOP: Decay visualization
                  SizedBox(height: 80, child: _buildDecayDisplay()),
                  const SizedBox(height: 6),
                  // MIDDLE: Primary knobs
                  Expanded(flex: 3, child: _buildPrimaryKnobs()),
                  const SizedBox(height: 4),
                  // BOTTOM: Character + Advanced
                  Expanded(flex: 2, child: _buildCharacterSection()),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(widget.icon, color: widget.accentColor, size: 14),
          const SizedBox(width: 6),
          Text(widget.title, style: FabFilterText.title.copyWith(fontSize: 11)),
          const SizedBox(width: 10),
          _buildSpaceDropdown(),
          const SizedBox(width: 8),
          // Freeze toggle
          _buildFreezeButton(),
          const Spacer(),
          // Advanced toggle
          _buildToggleButton('ADV', _showAdvanced, () {
            setState(() => _showAdvanced = !_showAdvanced);
          }),
          const SizedBox(width: 6),
          _buildABButtons(),
          const SizedBox(width: 6),
          _buildBypassButton(),
        ],
      ),
    );
  }

  Widget _buildSpaceDropdown() {
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
          value: _spaceType,
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
              setState(() => _spaceType = v);
              _setParam(_P.style, _spaceToTypeIndex(v).toDouble());
              // Read back space/brightness because set_style() may override them
              setState(() {
                _space = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.space);
                _brightness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.brightness);
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildFreezeButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _freeze = !_freeze);
        _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _freeze ? FabFilterColors.cyan.withValues(alpha: 0.3) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _freeze ? FabFilterColors.cyan : FabFilterColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ac_unit, size: 10, color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary),
            const SizedBox(width: 3),
            Text('FRZ', style: TextStyle(
              color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary,
              fontSize: 9, fontWeight: FontWeight.bold,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? widget.accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? widget.accentColor : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          color: active ? widget.accentColor : FabFilterColors.textTertiary,
          fontSize: 9, fontWeight: FontWeight.bold,
        )),
      ),
    );
  }

  Widget _buildABButtons() {
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
        child: Center(child: Text(label, style: TextStyle(
          color: active ? widget.accentColor : FabFilterColors.textTertiary,
          fontSize: 9, fontWeight: FontWeight.bold,
        ))),
      ),
    );
  }

  Widget _buildBypassButton() {
    return GestureDetector(
      onTap: toggleBypass,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bypassed ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: bypassed ? FabFilterColors.orange : FabFilterColors.border),
        ),
        child: Text('BYP', style: TextStyle(
          color: bypassed ? FabFilterColors.orange : FabFilterColors.textTertiary,
          fontSize: 9, fontWeight: FontWeight.bold,
        )),
      ),
    );
  }

  // ─── Decay Display ──────────────────────────────────────────────────────

  Widget _buildDecayDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: _ReverbDisplayPainter(
            decay: _decay,
            predelay: _predelay,
            space: _space,
            brightness: _brightness,
            lowDecayMult: _lowDecay,
            highDecayMult: _highDecay,
            animatedDecay: _animatedDecay,
            freeze: _freeze,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  // ─── Primary Knobs ──────────────────────────────────────────────────────

  Widget _buildPrimaryKnobs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _knob(
          value: _space, label: 'SPACE',
          display: '${(_space * 100).toStringAsFixed(0)}%',
          color: FabFilterColors.purple,
          onChanged: (v) {
            setState(() => _space = v);
            _setParam(_P.space, v);
          },
        ),
        _knob(
          value: _decay, label: 'DECAY',
          display: _formatDecay(_decay),
          color: FabFilterColors.purple,
          onChanged: (v) {
            setState(() => _decay = v);
            _setParam(_P.decay, v);
          },
        ),
        _knob(
          value: _brightness, label: 'BRIGHT',
          display: '${(_brightness * 100).toStringAsFixed(0)}%',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _brightness = v);
            _setParam(_P.brightness, v);
          },
        ),
        _knob(
          value: _predelay / 500.0, label: 'PRE',
          display: '${_predelay.toStringAsFixed(0)}ms',
          color: FabFilterColors.blue,
          onChanged: (v) {
            setState(() => _predelay = v * 500.0);
            _setParam(_P.predelay, _predelay);
          },
        ),
        _knob(
          value: _mix, label: 'MIX',
          display: '${(_mix * 100).toStringAsFixed(0)}%',
          color: FabFilterColors.green,
          onChanged: (v) {
            setState(() => _mix = v);
            _setParam(_P.mix, v);
          },
        ),
        _knob(
          value: _width / 2.0, label: 'WIDTH',
          display: '${(_width * 100).toStringAsFixed(0)}%',
          color: FabFilterColors.cyan,
          onChanged: (v) {
            setState(() => _width = v * 2.0);
            _setParam(_P.width, _width);
          },
        ),
      ],
    );
  }

  String _formatDecay(double d) {
    // Map 0-1 to a display time for reference
    final seconds = 0.1 * math.pow(20 / 0.1, d);
    return seconds >= 1 ? '${seconds.toStringAsFixed(1)}s' : '${(seconds * 1000).toStringAsFixed(0)}ms';
  }

  Widget _knob({
    required double value,
    required String label,
    required String display,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 44,
      onChanged: onChanged,
    );
  }

  // ─── Character + Advanced Section ───────────────────────────────────────

  Widget _buildCharacterSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT: Diffusion + Distance
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniSlider('Diff', _diffusion, '${(_diffusion * 100).toStringAsFixed(0)}%', (v) {
                setState(() => _diffusion = v);
                _setParam(_P.diffusion, v);
              }),
              _miniSlider('Dist', _distance, '${(_distance * 100).toStringAsFixed(0)}%', (v) {
                setState(() => _distance = v);
                _setParam(_P.distance, v);
              }),
              _miniSlider('Char', _character, '${(_character * 100).toStringAsFixed(0)}%', (v) {
                setState(() => _character = v);
                _setParam(_P.character, v);
              }),
              _miniSlider('Thick', _thickness, '${(_thickness * 100).toStringAsFixed(0)}%', (v) {
                setState(() => _thickness = v);
                _setParam(_P.thickness, v);
              }),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // RIGHT: Ducking + Advanced
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniSlider('Duck', _ducking, '${(_ducking * 100).toStringAsFixed(0)}%', (v) {
                setState(() => _ducking = v);
                _setParam(_P.ducking, v);
              }),
              if (_showAdvanced) ...[
                const SizedBox(height: 2),
                Text('TONAL DECAY', style: FabFilterText.paramLabel.copyWith(fontSize: 8, color: FabFilterColors.textMuted)),
                const SizedBox(height: 2),
                _miniSlider('Lo×', (_lowDecay - 0.5) / 1.5,
                  '${_lowDecay.toStringAsFixed(2)}×', (v) {
                  setState(() => _lowDecay = 0.5 + v * 1.5);
                  _setParam(_P.lowDecay, _lowDecay);
                }),
                _miniSlider('Hi×', (_highDecay - 0.1) / 0.9,
                  '${_highDecay.toStringAsFixed(2)}×', (v) {
                  setState(() => _highDecay = 0.1 + v * 0.9);
                  _setParam(_P.highDecay, _highDecay);
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniSlider(String label, double value, String display, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
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
          SizedBox(width: 34, child: Text(display, style: FabFilterText.paramLabel.copyWith(fontSize: 8), textAlign: TextAlign.right)),
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
  final double space;
  final double brightness;
  final double lowDecayMult;
  final double highDecayMult;
  final double animatedDecay;
  final bool freeze;

  _ReverbDisplayPainter({
    required this.decay,
    required this.predelay,
    required this.space,
    required this.brightness,
    required this.lowDecayMult,
    required this.highDecayMult,
    required this.animatedDecay,
    required this.freeze,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final rect = Offset.zero & canvasSize;
    final decayTime = 0.1 * math.pow(20 / 0.1, decay);

    // Background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, canvasSize.height),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      );
    canvas.drawRect(rect, bgPaint);

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    for (var i = 1; i <= 4; i++) {
      final x = (i / 5) * canvasSize.width;
      canvas.drawLine(Offset(x, 0), Offset(x, canvasSize.height), gridPaint);
    }
    for (var i = 1; i < 4; i++) {
      final y = (i / 4) * canvasSize.height;
      canvas.drawLine(Offset(0, y), Offset(canvasSize.width, y), gridPaint);
    }

    // Pre-delay region
    final maxTime = decayTime * 1.5;
    final predelayX = (predelay / 1000) / maxTime * canvasSize.width;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, predelayX, canvasSize.height),
      Paint()..color = FabFilterColors.blue.withValues(alpha: 0.2),
    );
    canvas.drawLine(
      Offset(predelayX, 0),
      Offset(predelayX, canvasSize.height),
      Paint()..color = FabFilterColors.blue..strokeWidth = 1,
    );

    // Freeze indicator
    if (freeze) {
      canvas.drawRect(rect, Paint()..color = FabFilterColors.cyan.withValues(alpha: 0.08));
      _drawLabel(canvas, 'FREEZE', Offset(canvasSize.width / 2 - 20, canvasSize.height / 2 - 6),
        color: FabFilterColors.cyan);
    }

    // Decay envelope (with low/high decay tint)
    final decayPath = Path();
    decayPath.moveTo(predelayX, canvasSize.height);

    for (var x = predelayX; x <= canvasSize.width; x += 2) {
      final t = ((x - predelayX) / canvasSize.width) * maxTime;
      final amplitude = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      final y = canvasSize.height * (1 - amplitude);
      decayPath.lineTo(x, y);
    }
    decayPath.lineTo(canvasSize.width, canvasSize.height);
    decayPath.close();

    canvas.drawPath(decayPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0), Offset(0, canvasSize.height),
        [FabFilterColors.purple.withValues(alpha: 0.8), FabFilterColors.purple.withValues(alpha: 0.1)],
      ));

    // Decay outline
    final outlinePath = Path();
    outlinePath.moveTo(predelayX, canvasSize.height * 0.1);
    for (var x = predelayX; x <= canvasSize.width; x += 2) {
      final t = ((x - predelayX) / canvasSize.width) * maxTime;
      final amplitude = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      outlinePath.lineTo(x, canvasSize.height * (1 - amplitude * 0.9));
    }
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterColors.purple..strokeWidth = 2..style = PaintingStyle.stroke);

    // Low/High decay bands (subtle coloring)
    if (lowDecayMult > 1.1) {
      // Show low freq sustain boost
      _drawLabel(canvas, 'Lo×${lowDecayMult.toStringAsFixed(1)}',
        Offset(predelayX + 4, 4), color: FabFilterColors.orange.withValues(alpha: 0.7));
    }
    if (highDecayMult < 0.8) {
      _drawLabel(canvas, 'Hi×${highDecayMult.toStringAsFixed(1)}',
        Offset(predelayX + 4, 16), color: FabFilterColors.cyan.withValues(alpha: 0.7));
    }

    // Early reflections
    final erPaint = Paint()..color = FabFilterColors.cyan..strokeWidth = 1;
    final random = math.Random(42);
    final erCount = (space * 10 + 5).toInt();
    for (var i = 0; i < erCount; i++) {
      final t = predelay / 1000 + random.nextDouble() * space * 0.1;
      final x = (t / maxTime) * canvasSize.width;
      final amplitude = 0.3 + random.nextDouble() * 0.4;
      if (x > predelayX && x < canvasSize.width) {
        canvas.drawLine(
          Offset(x, canvasSize.height),
          Offset(x, canvasSize.height * (1 - amplitude)),
          erPaint,
        );
      }
    }

    // Animated level indicator
    final indicatorX = predelayX + (canvasSize.width - predelayX) * 0.05;
    final indicatorY = canvasSize.height * (1 - animatedDecay * 0.8);
    canvas.drawCircle(Offset(indicatorX, indicatorY), 4, Paint()..color = FabFilterColors.green);

    // Labels
    _drawLabel(canvas, '${decayTime.toStringAsFixed(1)}s', Offset(canvasSize.width - 40, 4));
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, {Color? color}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color ?? FabFilterColors.textMuted, fontSize: 9),
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
      oldDelegate.space != space ||
      oldDelegate.animatedDecay != animatedDecay ||
      oldDelegate.freeze != freeze ||
      oldDelegate.lowDecayMult != lowDecayMult ||
      oldDelegate.highDecayMult != highDecayMult;
}
