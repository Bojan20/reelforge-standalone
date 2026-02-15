/// FF-R Reverb Panel (FDN 8×8 — 2026 Upgrade)
///
/// Mastering-grade reverb interface with 15 parameters:
/// - Space, Brightness, Width, Mix, PreDelay, Style
/// - Diffusion, Distance, Decay, Low/High Decay Mult
/// - Character, Thickness, Ducking, Freeze
/// - Real-time decay visualization with tonal EQ
/// - Equal-power crossfade mix control

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
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Reverb space type
enum ReverbSpace {
  room('Room', Icons.meeting_room),
  hall('Hall', Icons.church),
  plate('Plate', Icons.rectangle_outlined),
  chamber('Chamber', Icons.sensors),
  spring('Spring', Icons.cable);

  final String label;
  final IconData icon;
  const ReverbSpace(this.label, this.icon);
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

  // Primary controls
  double _space = 0.5;
  double _brightness = 0.5;
  double _decay = 0.5;
  double _mix = 0.3;
  double _predelay = 20.0;  // ms (0-500)
  double _width = 1.0;      // 0-2
  ReverbSpace _spaceType = ReverbSpace.hall;

  // Character controls — defaults match Rust (all off by default)
  double _diffusion = 0.0;
  double _distance = 0.0;
  double _character = 0.0;
  double _thickness = 0.0;

  // Tonal shaping
  double _lowDecay = 1.0;   // 0.5-2.0
  double _highDecay = 0.5;  // 0.1-1.0

  // Special
  double _ducking = 0.0;
  bool _freeze = false;

  // Metering
  double _wetLevel = 0.0;
  double _inputLevel = 0.0;
  final List<double> _decayHistory = List.filled(60, 0.0);
  int _historyIndex = 0;

  // Animation
  late AnimationController _decayController;
  double _animatedDecay = 0.0;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
    initBypassFromProvider();

    _decayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_updateMeters);
    _decayController.repeat();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);

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

  void _updateMeters() {
    if (!mounted) return;
    setState(() {
      if (_initialized && _slotIndex >= 0) {
        // Read real-time levels from FFI
        _inputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
        _wetLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);

        // Store wet level history for tail visualization
        _decayHistory[_historyIndex % _decayHistory.length] = _wetLevel;
        _historyIndex++;
      }

      // Calculate animated decay envelope for display
      final decayTime = 0.1 * math.pow(20 / 0.1, _decay).toDouble();
      final t = (_decayController.value * 10) % decayTime;
      _animatedDecay = _freeze ? 0.8 : math.exp(-t / (decayTime * 0.3));
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
          buildCompactHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  // TOP: Space type selector + Freeze
                  _buildSpaceSelector(),
                  const SizedBox(height: 4),
                  // DISPLAY: Decay + tonal EQ visualization
                  Expanded(flex: 3, child: _buildDecayDisplay()),
                  const SizedBox(height: 4),
                  // PRIMARY: Core knobs
                  _buildPrimaryKnobs(),
                  const SizedBox(height: 4),
                  // BOTTOM: Character sliders + tonal decay
                  Expanded(flex: 2, child: _buildCharacterSection()),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // ─── Space Selector (chip bar) ────────────────────────────────────────

  Widget _buildSpaceSelector() {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          ...ReverbSpace.values.map((s) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () {
                setState(() => _spaceType = s);
                _setParam(_P.style, _spaceToTypeIndex(s).toDouble());
                // Style may adjust space/brightness presets
                setState(() {
                  _space = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.space);
                  _brightness = _ffi.insertGetParam(widget.trackId, _slotIndex, _P.brightness);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _spaceType == s
                      ? FabFilterColors.purple.withValues(alpha: 0.25)
                      : FabFilterColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _spaceType == s ? FabFilterColors.purple : FabFilterColors.borderSubtle,
                    width: _spaceType == s ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 11,
                      color: _spaceType == s ? FabFilterColors.purple : FabFilterColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(s.label, style: TextStyle(
                      color: _spaceType == s ? FabFilterColors.textPrimary : FabFilterColors.textTertiary,
                      fontSize: 9, fontWeight: FontWeight.bold,
                    )),
                  ],
                ),
              ),
            ),
          )),
          const Spacer(),
          _buildFreezeButton(),
        ],
      ),
    );
  }

  Widget _buildFreezeButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _freeze = !_freeze);
        _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _freeze ? FabFilterColors.cyan.withValues(alpha: 0.3) : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _freeze ? FabFilterColors.cyan : FabFilterColors.borderSubtle,
            width: _freeze ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ac_unit, size: 11,
              color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary),
            const SizedBox(width: 3),
            Text('FREEZE', style: TextStyle(
              color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary,
              fontSize: 9, fontWeight: FontWeight.bold,
            )),
          ],
        ),
      ),
    );
  }

  // ─── Decay Display ────────────────────────────────────────────────────

  Widget _buildDecayDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            // Main decay visualization
            CustomPaint(
              painter: _ReverbDisplayPainter(
                decay: _decay,
                predelay: _predelay,
                space: _space,
                brightness: _brightness,
                lowDecayMult: _lowDecay,
                highDecayMult: _highDecay,
                animatedDecay: _animatedDecay,
                freeze: _freeze,
                distance: _distance,
                wetLevel: _wetLevel,
                inputLevel: _inputLevel,
                decayHistory: List.from(_decayHistory),
                historyIndex: _historyIndex,
              ),
              size: Size.infinite,
            ),
            // Tonal EQ overlay (low/high decay)
            Positioned(
              right: 4,
              top: 4,
              child: _buildTonalIndicator(),
            ),
            // Mix meter
            Positioned(
              left: 4,
              bottom: 4,
              child: _buildMixIndicator(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTonalIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Low decay indicator
          Container(
            width: 4, height: 14,
            decoration: BoxDecoration(
              color: _lowDecay > 1.0
                  ? FabFilterColors.orange.withValues(alpha: (_lowDecay - 1.0).clamp(0.0, 1.0))
                  : FabFilterColors.cyan.withValues(alpha: (1.0 - _lowDecay).clamp(0.0, 1.0) * 2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Text('Lo ${_lowDecay.toStringAsFixed(1)}×',
            style: TextStyle(
              color: _lowDecay > 1.0 ? FabFilterColors.orange : FabFilterColors.cyan,
              fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
          const SizedBox(width: 6),
          Container(
            width: 4, height: 14,
            decoration: BoxDecoration(
              color: FabFilterColors.cyan.withValues(alpha: (1.0 - _highDecay).clamp(0.0, 1.0)),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Text('Hi ${_highDecay.toStringAsFixed(1)}×',
            style: TextStyle(
              color: FabFilterColors.cyan,
              fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        ],
      ),
    );
  }

  Widget _buildMixIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dry/Wet bar
          SizedBox(
            width: 40, height: 6,
            child: CustomPaint(
              painter: _MixBarPainter(mix: _mix),
            ),
          ),
          const SizedBox(width: 4),
          Text('${(_mix * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: FabFilterColors.green,
              fontSize: 8, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        ],
      ),
    );
  }

  // ─── Primary Knobs ────────────────────────────────────────────────────

  Widget _buildPrimaryKnobs() {
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _knob(
            value: _space, label: 'SPACE',
            display: '${(_space * 100).toStringAsFixed(0)}%',
            color: FabFilterProcessorColors.reverbAccent,
            onChanged: (v) {
              setState(() => _space = v);
              _setParam(_P.space, v);
            },
          ),
          _knob(
            value: _decay, label: 'DECAY',
            display: _formatDecay(_decay),
            color: FabFilterProcessorColors.reverbDecay,
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
            value: _predelay / 500.0, label: 'PRE-DLY',
            display: '${_predelay.toStringAsFixed(0)}ms',
            color: FabFilterProcessorColors.reverbPredelay,
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
      ),
    );
  }

  String _formatDecay(double d) {
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

  // ─── Character + Tonal Decay Section ──────────────────────────────────

  Widget _buildCharacterSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT: Diffusion, Distance, Character, Thickness — FabFilter knobs
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FabSectionLabel('CHARACTER'),
              const SizedBox(height: 4),
              SizedBox(
                height: 72,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _knob(
                      value: _diffusion, label: 'DIFF',
                      display: '${(_diffusion * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbAccent,
                      onChanged: (v) {
                        setState(() => _diffusion = v);
                        _setParam(_P.diffusion, v);
                      },
                    ),
                    _knob(
                      value: _distance, label: 'DIST',
                      display: '${(_distance * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbPredelay,
                      onChanged: (v) {
                        setState(() => _distance = v);
                        _setParam(_P.distance, v);
                      },
                    ),
                    _knob(
                      value: _character, label: 'CHAR',
                      display: '${(_character * 100).toStringAsFixed(0)}%',
                      color: FabFilterProcessorColors.reverbDecay,
                      onChanged: (v) {
                        setState(() => _character = v);
                        _setParam(_P.character, v);
                      },
                    ),
                    _knob(
                      value: _thickness, label: 'THICK',
                      display: '${(_thickness * 100).toStringAsFixed(0)}%',
                      color: FabFilterColors.orange,
                      onChanged: (v) {
                        setState(() => _thickness = v);
                        _setParam(_P.thickness, v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // RIGHT: Ducking + Tonal Decay — FabFilter knobs
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FabSectionLabel('DYNAMICS'),
              const SizedBox(height: 4),
              SizedBox(
                height: 72,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _knob(
                      value: _ducking, label: 'DUCK',
                      display: '${(_ducking * 100).toStringAsFixed(0)}%',
                      color: FabFilterColors.green,
                      onChanged: (v) {
                        setState(() => _ducking = v);
                        _setParam(_P.ducking, v);
                      },
                    ),
                    _knob(
                      value: (_lowDecay - 0.5) / 1.5, label: 'LO ×',
                      display: '${_lowDecay.toStringAsFixed(2)}×',
                      color: FabFilterColors.orange,
                      onChanged: (v) {
                        setState(() => _lowDecay = 0.5 + v * 1.5);
                        _setParam(_P.lowDecay, _lowDecay);
                      },
                    ),
                    _knob(
                      value: (_highDecay - 0.1) / 0.9, label: 'HI ×',
                      display: '${_highDecay.toStringAsFixed(2)}×',
                      color: FabFilterColors.cyan,
                      onChanged: (v) {
                        setState(() => _highDecay = 0.1 + v * 0.9);
                        _setParam(_P.highDecay, _highDecay);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// MIX BAR PAINTER (dry/wet indicator)
// ═══════════════════════════════════════════════════════════════════════════

class _MixBarPainter extends CustomPainter {
  final double mix;
  _MixBarPainter({required this.mix});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint()..color = FabFilterColors.borderSubtle,
    );
    // Dry portion (left)
    final dryWidth = size.width * (1 - mix);
    if (dryWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, dryWidth, size.height),
          const Radius.circular(3),
        ),
        Paint()..color = FabFilterColors.textTertiary.withValues(alpha: 0.5),
      );
    }
    // Wet portion (right)
    final wetWidth = size.width * mix;
    if (wetWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - wetWidth, 0, wetWidth, size.height),
          const Radius.circular(3),
        ),
        Paint()..color = FabFilterColors.green.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MixBarPainter old) => old.mix != mix;
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB DISPLAY PAINTER (Enhanced decay visualization)
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
  final double distance;
  final double wetLevel;
  final double inputLevel;
  final List<double> decayHistory;
  final int historyIndex;

  _ReverbDisplayPainter({
    required this.decay,
    required this.predelay,
    required this.space,
    required this.brightness,
    required this.lowDecayMult,
    required this.highDecayMult,
    required this.animatedDecay,
    required this.freeze,
    required this.distance,
    required this.wetLevel,
    required this.inputLevel,
    required this.decayHistory,
    required this.historyIndex,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final decayTime = 0.1 * math.pow(20 / 0.1, decay);
    final maxTime = decayTime * 1.5;
    final predelayNorm = (predelay / 1000) / maxTime;
    final predelayX = predelayNorm * s.width;

    // ─── Background gradient ───────────────────────────────────────────
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, s.height),
        [FabFilterColors.bgVoid, FabFilterColors.bgDeep],
      ));

    // ─── Grid ──────────────────────────────────────────────────────────
    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;
    for (var i = 1; i <= 4; i++) {
      final x = (i / 5) * s.width;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), gridPaint);
    }
    for (var i = 1; i < 4; i++) {
      final y = (i / 4) * s.height;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), gridPaint);
    }

    // ─── Pre-delay region ──────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, predelayX, s.height),
      Paint()..color = FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.12),
    );
    canvas.drawLine(
      Offset(predelayX, 0), Offset(predelayX, s.height),
      Paint()
        ..color = FabFilterProcessorColors.reverbPredelay
        ..strokeWidth = 1.5,
    );

    // ─── Freeze overlay ────────────────────────────────────────────────
    if (freeze) {
      canvas.drawRect(rect,
        Paint()..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.06));
      // Freeze horizon line
      final freezeY = s.height * 0.2;
      canvas.drawLine(
        Offset(predelayX, freezeY), Offset(s.width, freezeY),
        Paint()
          ..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.4)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // ─── Low-frequency decay band (warm tint) ──────────────────────────
    if (lowDecayMult > 1.05) {
      final loPath = Path();
      loPath.moveTo(predelayX, s.height);
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space) * lowDecayMult));
        loPath.lineTo(x, s.height * (1 - amp * 0.9));
      }
      loPath.lineTo(s.width, s.height);
      loPath.close();
      canvas.drawPath(loPath, Paint()
        ..color = FabFilterColors.orange.withValues(alpha: 0.08 * (lowDecayMult - 1.0).clamp(0.0, 1.0)));
    }

    // ─── Main decay envelope fill ──────────────────────────────────────
    final decayPath = Path();
    decayPath.moveTo(predelayX, s.height);
    for (var x = predelayX; x <= s.width; x += 2) {
      final t = ((x - predelayX) / s.width) * maxTime;
      final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      decayPath.lineTo(x, s.height * (1 - amp));
    }
    decayPath.lineTo(s.width, s.height);
    decayPath.close();

    canvas.drawPath(decayPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, s.height),
        [
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.5),
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.05),
        ],
      ));

    // ─── Decay outline ─────────────────────────────────────────────────
    final outlinePath = Path();
    bool first = true;
    for (var x = predelayX; x <= s.width; x += 2) {
      final t = ((x - predelayX) / s.width) * maxTime;
      final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      final y = s.height * (1 - amp * 0.9);
      if (first) { outlinePath.moveTo(x, y); first = false; } else { outlinePath.lineTo(x, y); }
    }
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterProcessorColors.reverbAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);

    // ─── High-frequency decay envelope (dimmer, shorter) ───────────────
    if (highDecayMult < 0.9) {
      final hiPath = Path();
      bool hiFirst = true;
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.7 : math.exp(-t / (decayTime * 0.3 * (1 + space) * highDecayMult));
        final y = s.height * (1 - amp * 0.9);
        if (hiFirst) { hiPath.moveTo(x, y); hiFirst = false; } else { hiPath.lineTo(x, y); }
      }
      canvas.drawPath(hiPath, Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // ─── Early reflections ─────────────────────────────────────────────
    final erPaint = Paint()
      ..color = FabFilterProcessorColors.reverbEarlyRef
      ..strokeWidth = 1.5;
    final random = math.Random(42);
    final erCount = (space * 12 + 4).toInt();
    final erSpread = distance.clamp(0.05, 1.0) * 0.15;
    for (var i = 0; i < erCount; i++) {
      final t = predelay / 1000 + random.nextDouble() * erSpread;
      final x = (t / maxTime) * s.width;
      final amp = 0.3 + random.nextDouble() * 0.5;
      if (x > predelayX && x < s.width * 0.4) {
        canvas.drawLine(
          Offset(x, s.height),
          Offset(x, s.height * (1 - amp)),
          erPaint..color = FabFilterProcessorColors.reverbEarlyRef.withValues(
            alpha: 0.4 + random.nextDouble() * 0.4),
        );
      }
    }

    // ─── Real-time wet level indicator ─────────────────────────────────
    if (wetLevel > 0.001) {
      final levelY = s.height * (1 - wetLevel.clamp(0.0, 1.0) * 0.85);
      final indicatorX = predelayX + 6;
      canvas.drawCircle(
        Offset(indicatorX, levelY), 4,
        Paint()..color = FabFilterColors.green,
      );
      canvas.drawCircle(
        Offset(indicatorX, levelY), 6,
        Paint()
          ..color = FabFilterColors.green.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // ─── Decay tail sparkle (history) ──────────────────────────────────
    final histLen = decayHistory.length;
    if (histLen > 0) {
      final sparkPaint = Paint()..strokeWidth = 1;
      for (var i = 0; i < histLen; i++) {
        final idx = (historyIndex - histLen + i) % histLen;
        final val = decayHistory[idx < 0 ? idx + histLen : idx];
        if (val > 0.01) {
          final age = i / histLen;
          final x = predelayX + (s.width - predelayX) * (i / histLen);
          final y = s.height * (1 - val.clamp(0.0, 1.0) * 0.7);
          sparkPaint.color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.15 * age);
          canvas.drawCircle(Offset(x, y), 1.5, sparkPaint);
        }
      }
    }

    // ─── Decay time label ──────────────────────────────────────────────
    _drawLabel(canvas, '${decayTime.toStringAsFixed(1)}s',
      Offset(s.width - 36, 4));

    // Pre-delay label
    if (predelay > 5) {
      _drawLabel(canvas, '${predelay.toStringAsFixed(0)}ms',
        Offset(math.max(2, predelayX - 30), s.height - 14),
        color: FabFilterProcessorColors.reverbPredelay);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, {Color? color}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? FabFilterColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ReverbDisplayPainter old) =>
      old.decay != decay ||
      old.predelay != predelay ||
      old.space != space ||
      old.animatedDecay != animatedDecay ||
      old.freeze != freeze ||
      old.lowDecayMult != lowDecayMult ||
      old.highDecayMult != highDecayMult ||
      old.brightness != brightness ||
      old.distance != distance ||
      old.wetLevel != wetLevel ||
      old.inputLevel != inputLevel ||
      old.historyIndex != historyIndex;
}
