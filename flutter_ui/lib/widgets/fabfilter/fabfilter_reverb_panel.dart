/// FF-R Reverb Panel — Pro-R 2 Ultimate
///
/// Mastering-grade reverb interface with 15 parameters:
/// - Space, Brightness, Width, Mix, PreDelay, Style
/// - Diffusion, Distance, Decay, Low/High Decay Mult
/// - Character, Thickness, Ducking, Freeze
/// - Glass decay visualization with tonal EQ bands
/// - Real-time wet tail sparkle + early reflection plot
/// - Decay history waveform with gradient fills
/// - Pre-delay region with glow marker
/// - Freeze state overlay with ice crystallization effect

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
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class ReverbSnapshot implements DspParameterSnapshot {
  final double space, brightness, width, mix, predelay;
  final int style;
  final double diffusion, distance, decay;
  final double lowDecayMult, highDecayMult;
  final double character, thickness, ducking;
  final bool freeze;

  const ReverbSnapshot({
    required this.space, required this.brightness, required this.width,
    required this.mix, required this.predelay, required this.style,
    required this.diffusion, required this.distance, required this.decay,
    required this.lowDecayMult, required this.highDecayMult,
    required this.character, required this.thickness, required this.ducking,
    required this.freeze,
  });

  @override
  ReverbSnapshot copy() => ReverbSnapshot(
    space: space, brightness: brightness, width: width, mix: mix,
    predelay: predelay, style: style, diffusion: diffusion,
    distance: distance, decay: decay, lowDecayMult: lowDecayMult,
    highDecayMult: highDecayMult, character: character,
    thickness: thickness, ducking: ducking, freeze: freeze,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! ReverbSnapshot) return false;
    return space == other.space && brightness == other.brightness &&
        width == other.width && mix == other.mix &&
        predelay == other.predelay && style == other.style &&
        decay == other.decay && freeze == other.freeze;
  }
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
  final List<double> _decayHistory = List.filled(80, 0.0);
  int _historyIndex = 0;

  // Animation
  late AnimationController _meterController;
  late AnimationController _freezeController;
  late Animation<double> _freezeAnim;
  double _animatedDecay = 0.0;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;

  // A/B snapshots
  ReverbSnapshot? _snapshotA;
  ReverbSnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
    initBypassFromProvider();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_updateMeters);
    _meterController.repeat();

    _freezeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _freezeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _freezeController, curve: Curves.easeInOut),
    );
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
      if (_freeze) _freezeController.forward();
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

  // ─────────────────────────────────────────────────────────────────────────
  // A/B STATE
  // ─────────────────────────────────────────────────────────────────────────

  ReverbSnapshot _snap() => ReverbSnapshot(
    space: _space, brightness: _brightness, width: _width, mix: _mix,
    predelay: _predelay, style: _spaceToTypeIndex(_spaceType),
    diffusion: _diffusion, distance: _distance, decay: _decay,
    lowDecayMult: _lowDecay, highDecayMult: _highDecay,
    character: _character, thickness: _thickness, ducking: _ducking,
    freeze: _freeze,
  );

  void _restore(ReverbSnapshot s) {
    setState(() {
      _space = s.space; _brightness = s.brightness; _width = s.width;
      _mix = s.mix; _predelay = s.predelay;
      _spaceType = _typeIndexToSpace(s.style);
      _diffusion = s.diffusion; _distance = s.distance; _decay = s.decay;
      _lowDecay = s.lowDecayMult; _highDecay = s.highDecayMult;
      _character = s.character; _thickness = s.thickness;
      _ducking = s.ducking; _freeze = s.freeze;
    });
    if (_freeze) { _freezeController.forward(); } else { _freezeController.reverse(); }
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.space, _space);
    _setParam(_P.brightness, _brightness);
    _setParam(_P.width, _width);
    _setParam(_P.mix, _mix);
    _setParam(_P.predelay, _predelay);
    _setParam(_P.style, _spaceToTypeIndex(_spaceType).toDouble());
    _setParam(_P.diffusion, _diffusion);
    _setParam(_P.distance, _distance);
    _setParam(_P.decay, _decay);
    _setParam(_P.lowDecay, _lowDecay);
    _setParam(_P.highDecay, _highDecay);
    _setParam(_P.character, _character);
    _setParam(_P.thickness, _thickness);
    _setParam(_P.ducking, _ducking);
    _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
  }

  @override
  void storeStateA() { _snapshotA = _snap(); super.storeStateA(); }
  @override
  void storeStateB() { _snapshotB = _snap(); super.storeStateB(); }
  @override
  void restoreStateA() { if (_snapshotA != null) _restore(_snapshotA!); }
  @override
  void restoreStateB() { if (_snapshotB != null) _restore(_snapshotB!); }
  @override
  void copyAToB() { _snapshotB = _snapshotA?.copy(); super.copyAToB(); }
  @override
  void copyBToA() { _snapshotA = _snapshotB?.copy(); super.copyBToA(); }

  @override
  void dispose() {
    _meterController.dispose();
    _freezeController.dispose();
    super.dispose();
  }

  void _updateMeters() {
    if (!mounted) return;
    setState(() {
      if (_initialized && _slotIndex >= 0) {
        _inputLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
        _wetLevel = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);

        _decayHistory[_historyIndex % _decayHistory.length] = _wetLevel;
        _historyIndex++;
      }

      final decayTime = 0.1 * math.pow(20 / 0.1, _decay).toDouble();
      final t = (_meterController.value * 10) % decayTime;
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
          _buildPremiumHeader(),
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

  // ─── Premium Header with meters ─────────────────────────────────────────

  Widget _buildPremiumHeader() {
    final decayTime = 0.1 * math.pow(20 / 0.1, _decay);
    final decayLabel = decayTime >= 1
        ? '${decayTime.toStringAsFixed(1)}s'
        : '${(decayTime * 1000).toStringAsFixed(0)}ms';

    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FabFilterColors.bgSurface,
            FabFilterColors.bgMid.withValues(alpha: 0.8),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Title
            Icon(Icons.waves, size: 13, color: FabFilterColors.purple),
            const SizedBox(width: 4),
            Text('FF-R', style: TextStyle(
              color: FabFilterColors.textPrimary,
              fontSize: 11, fontWeight: FontWeight.bold,
            )),
            const SizedBox(width: 8),
            // Space type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.purple.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(_spaceType.label.toUpperCase(), style: TextStyle(
                color: FabFilterColors.purple,
                fontSize: 8, fontWeight: FontWeight.bold,
              )),
            ),
            const SizedBox(width: 6),
            // Decay readout
            Text(decayLabel, style: TextStyle(
              color: FabFilterProcessorColors.reverbDecay,
              fontSize: 9, fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
            const Spacer(),
            // Mini I/O meters
            _buildMiniMeter('IN', _inputLevel, FabFilterColors.cyan),
            const SizedBox(width: 6),
            _buildMiniMeter('WET', _wetLevel, FabFilterColors.green),
            const SizedBox(width: 6),
            // Mix %
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('${(_mix * 100).toStringAsFixed(0)}%', style: TextStyle(
                color: FabFilterColors.green,
                fontSize: 8, fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
            ),
            const SizedBox(width: 6),
            // Freeze indicator
            if (_freeze)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: FabFilterColors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.5), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ac_unit, size: 8, color: FabFilterColors.cyan),
                    const SizedBox(width: 2),
                    Text('FRZ', style: TextStyle(
                      color: FabFilterColors.cyan,
                      fontSize: 7, fontWeight: FontWeight.bold,
                    )),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: FabFilterColors.purple),
            const SizedBox(width: 4),
            FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMeter(String label, double level, Color color) {
    final dB = level > 1e-10 ? 20.0 * math.log(level) / math.ln10 : -60.0;
    final norm = ((dB + 60) / 60).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(
          color: FabFilterColors.textTertiary,
          fontSize: 7, fontWeight: FontWeight.bold,
        )),
        const SizedBox(width: 2),
        SizedBox(
          width: 24, height: 5,
          child: CustomPaint(
            painter: _MiniMeterPainter(value: norm, color: color),
          ),
        ),
      ],
    );
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
                  boxShadow: _spaceType == s ? [
                    BoxShadow(
                      color: FabFilterColors.purple.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ] : null,
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
        if (_freeze) {
          _freezeController.forward();
        } else {
          _freezeController.reverse();
        }
      },
      child: AnimatedBuilder(
        animation: _freezeAnim,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _freeze
                  ? FabFilterColors.cyan.withValues(alpha: 0.15 + _freezeAnim.value * 0.15)
                  : FabFilterColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _freeze ? FabFilterColors.cyan : FabFilterColors.borderSubtle,
                width: _freeze ? 1.5 : 1,
              ),
              boxShadow: _freeze ? [
                BoxShadow(
                  color: FabFilterColors.cyan.withValues(alpha: 0.15 + _freezeAnim.value * 0.1),
                  blurRadius: 8 + _freezeAnim.value * 4,
                ),
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.ac_unit, size: 12,
                  color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary),
                const SizedBox(width: 4),
                Text('FREEZE', style: TextStyle(
                  color: _freeze ? FabFilterColors.cyan : FabFilterColors.textTertiary,
                  fontSize: 9, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          );
        },
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
                freezeAnim: _freezeAnim.value,
                distance: _distance,
                wetLevel: _wetLevel,
                inputLevel: _inputLevel,
                decayHistory: List.from(_decayHistory),
                historyIndex: _historyIndex,
                diffusion: _diffusion,
                mix: _mix,
              ),
              size: Size.infinite,
            ),
            // Tonal indicator (top-right)
            Positioned(
              right: 4,
              top: 4,
              child: _buildTonalIndicator(),
            ),
            // Mix indicator (bottom-left)
            Positioned(
              left: 4,
              bottom: 4,
              child: _buildMixIndicator(),
            ),
            // Width indicator (bottom-right)
            Positioned(
              right: 4,
              bottom: 4,
              child: _buildWidthBadge(),
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
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Low decay indicator bar
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  _lowDecay > 1.0
                      ? FabFilterColors.orange.withValues(alpha: 0.2)
                      : FabFilterColors.cyan.withValues(alpha: 0.2),
                  _lowDecay > 1.0
                      ? FabFilterColors.orange.withValues(alpha: (_lowDecay - 1.0).clamp(0.0, 1.0))
                      : FabFilterColors.cyan.withValues(alpha: (1.0 - _lowDecay).clamp(0.0, 1.0) * 2),
                ],
              ),
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
            width: 3, height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  FabFilterColors.cyan.withValues(alpha: 0.2),
                  FabFilterColors.cyan.withValues(alpha: (1.0 - _highDecay).clamp(0.0, 1.0)),
                ],
              ),
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
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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

  Widget _buildWidthBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text('W ${(_width * 100).toStringAsFixed(0)}%', style: TextStyle(
        color: FabFilterColors.cyan.withValues(alpha: 0.7),
        fontSize: 8, fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
      )),
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
        // LEFT: Diffusion, Distance, Character, Thickness
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
        // RIGHT: Ducking + Tonal Decay
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
// MINI METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _MiniMeterPainter extends CustomPainter {
  final double value;
  final Color color;
  _MiniMeterPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      Paint()..color = FabFilterColors.bgVoid,
    );
    // Fill with gradient
    if (value > 0.001) {
      final fillWidth = size.width * value.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, fillWidth, size.height),
          const Radius.circular(2),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero, Offset(size.width, 0),
            [color.withValues(alpha: 0.6), color],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMeterPainter old) =>
      old.value != value || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// MIX BAR PAINTER (dry/wet indicator)
// ═══════════════════════════════════════════════════════════════════════════

class _MixBarPainter extends CustomPainter {
  final double mix;
  _MixBarPainter({required this.mix});

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    // Background
    canvas.drawRRect(rr, Paint()..color = FabFilterColors.borderSubtle);
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
    // Wet portion (right) — gradient fill
    final wetWidth = size.width * mix;
    if (wetWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - wetWidth, 0, wetWidth, size.height),
          const Radius.circular(3),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(size.width - wetWidth, 0), Offset(size.width, 0),
            [FabFilterColors.green.withValues(alpha: 0.5), FabFilterColors.green.withValues(alpha: 0.8)],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MixBarPainter old) => old.mix != mix;
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB DISPLAY PAINTER — Pro-R 2 Ultimate
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
  final double freezeAnim;
  final double distance;
  final double wetLevel;
  final double inputLevel;
  final List<double> decayHistory;
  final int historyIndex;
  final double diffusion;
  final double mix;

  _ReverbDisplayPainter({
    required this.decay,
    required this.predelay,
    required this.space,
    required this.brightness,
    required this.lowDecayMult,
    required this.highDecayMult,
    required this.animatedDecay,
    required this.freeze,
    required this.freezeAnim,
    required this.distance,
    required this.wetLevel,
    required this.inputLevel,
    required this.decayHistory,
    required this.historyIndex,
    required this.diffusion,
    required this.mix,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final decayTime = 0.1 * math.pow(20 / 0.1, decay);
    final maxTime = decayTime * 1.5;
    final predelayNorm = (predelay / 1000) / maxTime;
    final predelayX = predelayNorm * s.width;

    // ─── Glass background gradient ─────────────────────────────────────
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero, Offset(0, s.height),
        [
          const Color(0xFF0D0D14),
          const Color(0xFF0A0A10),
          const Color(0xFF080810),
        ],
        [0.0, 0.5, 1.0],
      ));

    // Subtle radial ambience glow centered at decay peak
    canvas.drawCircle(
      Offset(predelayX + 20, s.height * 0.3),
      s.width * 0.4,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(predelayX + 20, s.height * 0.3),
          s.width * 0.4,
          [
            FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
    );

    // ─── Grid with subtle cross lines ──────────────────────────────────
    final gridPaint = Paint()..color = FabFilterColors.grid..strokeWidth = 0.5;
    for (var i = 1; i <= 4; i++) {
      final x = (i / 5) * s.width;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), gridPaint);
    }
    for (var i = 1; i < 4; i++) {
      final y = (i / 4) * s.height;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), gridPaint);
    }

    // ─── Time axis labels ──────────────────────────────────────────────
    for (var i = 1; i <= 4; i++) {
      final t = (i / 5) * maxTime;
      final label = t >= 1.0 ? '${t.toStringAsFixed(1)}s' : '${(t * 1000).toStringAsFixed(0)}ms';
      _drawLabel(canvas, label, Offset((i / 5) * s.width - 10, s.height - 12),
        color: FabFilterColors.textTertiary.withValues(alpha: 0.4));
    }

    // ─── dB axis labels (left) ─────────────────────────────────────────
    for (var i = 0; i < 4; i++) {
      final db = -(i * 20);
      final y = (i / 4) * s.height;
      _drawLabel(canvas, '${db}dB', Offset(2, y + 1),
        color: FabFilterColors.textTertiary.withValues(alpha: 0.35));
    }

    // ─── Pre-delay region with glass effect ────────────────────────────
    if (predelayX > 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, predelayX, s.height),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero, Offset(predelayX, 0),
            [
              FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.08),
              FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.15),
            ],
          ),
      );
      // Pre-delay marker line with glow
      canvas.drawLine(
        Offset(predelayX, 0), Offset(predelayX, s.height),
        Paint()
          ..color = FabFilterProcessorColors.reverbPredelay
          ..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(predelayX, 0), Offset(predelayX, s.height),
        Paint()
          ..color = FabFilterProcessorColors.reverbPredelay.withValues(alpha: 0.3)
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // ─── Freeze overlay ────────────────────────────────────────────────
    if (freeze || freezeAnim > 0.01) {
      final fA = freezeAnim.clamp(0.0, 1.0);
      // Ice tint
      canvas.drawRect(rect,
        Paint()..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.05 * fA));
      // Freeze horizon line
      final freezeY = s.height * 0.2;
      canvas.drawLine(
        Offset(predelayX, freezeY), Offset(s.width, freezeY),
        Paint()
          ..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.4 * fA)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      // Glow on freeze line
      canvas.drawLine(
        Offset(predelayX, freezeY), Offset(s.width, freezeY),
        Paint()
          ..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.15 * fA)
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Ice crystal dots
      final rng = math.Random(77);
      for (var i = 0; i < (20 * fA).toInt(); i++) {
        final cx = predelayX + rng.nextDouble() * (s.width - predelayX);
        final cy = rng.nextDouble() * s.height;
        canvas.drawCircle(
          Offset(cx, cy), 1.0 + rng.nextDouble() * 1.5,
          Paint()..color = FabFilterProcessorColors.reverbFreeze.withValues(alpha: 0.15 * fA),
        );
      }
    }

    // ─── Low-frequency decay band (warm tint fill) ─────────────────────
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
        ..shader = ui.Gradient.linear(
          Offset(0, s.height * 0.1), Offset(0, s.height),
          [
            FabFilterColors.orange.withValues(alpha: 0.12 * (lowDecayMult - 1.0).clamp(0.0, 1.0)),
            FabFilterColors.orange.withValues(alpha: 0.02),
          ],
        ));
    }

    // ─── Main decay envelope fill (glass gradient) ─────────────────────
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
        Offset(0, 0), Offset(0, s.height),
        [
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.45),
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.12),
          FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.03),
        ],
        [0.0, 0.5, 1.0],
      ));

    // ─── Decay outline with glow ─────────────────────────────────────
    final outlinePath = Path();
    bool first = true;
    for (var x = predelayX; x <= s.width; x += 2) {
      final t = ((x - predelayX) / s.width) * maxTime;
      final amp = freeze ? 0.8 : math.exp(-t / (decayTime * 0.3 * (1 + space)));
      final y = s.height * (1 - amp * 0.9);
      if (first) { outlinePath.moveTo(x, y); first = false; } else { outlinePath.lineTo(x, y); }
    }
    // Glow behind main curve
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.25)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // Main curve
    canvas.drawPath(outlinePath, Paint()
      ..color = FabFilterProcessorColors.reverbAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);

    // ─── High-frequency decay envelope (shorter, cyan) ─────────────────
    if (highDecayMult < 0.95) {
      final hiPath = Path();
      bool hiFirst = true;
      for (var x = predelayX; x <= s.width; x += 2) {
        final t = ((x - predelayX) / s.width) * maxTime;
        final amp = freeze ? 0.7 : math.exp(-t / (decayTime * 0.3 * (1 + space) * highDecayMult));
        final y = s.height * (1 - amp * 0.9);
        if (hiFirst) { hiPath.moveTo(x, y); hiFirst = false; } else { hiPath.lineTo(x, y); }
      }
      // Glow
      canvas.drawPath(hiPath, Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.15)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawPath(hiPath, Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.6)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }

    // ─── Early reflections (glass impulse lines) ─────────────────────
    final erRng = math.Random(42);
    final erCount = (space * 12 + 4).toInt();
    final erSpread = distance.clamp(0.05, 1.0) * 0.15;
    for (var i = 0; i < erCount; i++) {
      final t = predelay / 1000 + erRng.nextDouble() * erSpread;
      final x = (t / maxTime) * s.width;
      final amp = 0.3 + erRng.nextDouble() * 0.5;
      if (x > predelayX && x < s.width * 0.4) {
        final alpha = 0.3 + erRng.nextDouble() * 0.4;
        final erY = s.height * (1 - amp);
        // Glass glow behind each ER line
        canvas.drawLine(
          Offset(x, s.height),
          Offset(x, erY),
          Paint()
            ..color = FabFilterProcessorColors.reverbEarlyRef.withValues(alpha: alpha * 0.15)
            ..strokeWidth = 4
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        // ER line
        canvas.drawLine(
          Offset(x, s.height),
          Offset(x, erY),
          Paint()
            ..color = FabFilterProcessorColors.reverbEarlyRef.withValues(alpha: alpha)
            ..strokeWidth = 1.5,
        );
        // Top dot
        canvas.drawCircle(
          Offset(x, erY), 2,
          Paint()..color = FabFilterProcessorColors.reverbEarlyRef.withValues(alpha: alpha * 0.8),
        );
      }
    }

    // ─── Real-time wet level indicator (glass node) ───────────────────
    if (wetLevel > 0.001) {
      final levelY = s.height * (1 - wetLevel.clamp(0.0, 1.0) * 0.85);
      final indicatorX = predelayX + 8;
      // Outer glow
      canvas.drawCircle(
        Offset(indicatorX, levelY), 8,
        Paint()
          ..color = FabFilterColors.green.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Glass circle
      canvas.drawCircle(
        Offset(indicatorX, levelY), 5,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(indicatorX - 1, levelY - 1), 5,
            [
              FabFilterColors.green.withValues(alpha: 0.9),
              FabFilterColors.green.withValues(alpha: 0.4),
            ],
          ),
      );
      // Highlight
      canvas.drawCircle(
        Offset(indicatorX - 1.5, levelY - 1.5), 2,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }

    // ─── Input level indicator ────────────────────────────────────────
    if (inputLevel > 0.001) {
      final inY = s.height * (1 - inputLevel.clamp(0.0, 1.0) * 0.85);
      // Small cyan diamond at left edge
      final diamondPath = Path();
      diamondPath.moveTo(3, inY);
      diamondPath.lineTo(6, inY - 3);
      diamondPath.lineTo(9, inY);
      diamondPath.lineTo(6, inY + 3);
      diamondPath.close();
      canvas.drawPath(diamondPath, Paint()..color = FabFilterColors.cyan.withValues(alpha: 0.6));
    }

    // ─── Decay tail sparkle (history waveform) ────────────────────────
    final histLen = decayHistory.length;
    if (histLen > 0) {
      final sparkPath = Path();
      bool sparkFirst = true;
      for (var i = 0; i < histLen; i++) {
        final idx = (historyIndex - histLen + i) % histLen;
        final val = decayHistory[idx < 0 ? idx + histLen : idx];
        if (val > 0.005) {
          final age = i / histLen;
          final x = predelayX + (s.width - predelayX) * (i / histLen);
          final y = s.height * (1 - val.clamp(0.0, 1.0) * 0.7);
          if (sparkFirst) { sparkPath.moveTo(x, y); sparkFirst = false; } else { sparkPath.lineTo(x, y); }
        }
      }
      if (!sparkFirst) {
        // Glow trail
        canvas.drawPath(sparkPath, Paint()
          ..color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.1)
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        // Sparkle trail line
        canvas.drawPath(sparkPath, Paint()
          ..color = FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.3)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke);
      }
    }

    // ─── Diffusion indicator (top-left) ────────────────────────────────
    if (diffusion > 0.05) {
      final diffW = s.width * 0.15 * diffusion;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(predelayX + 2, 3, diffW, 4),
          const Radius.circular(2),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(predelayX + 2, 0), Offset(predelayX + 2 + diffW, 0),
            [
              FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.4),
              FabFilterProcessorColors.reverbAccent.withValues(alpha: 0.1),
            ],
          ),
      );
    }

    // ─── Decay time label ──────────────────────────────────────────────
    _drawLabel(canvas, '${decayTime.toStringAsFixed(1)}s',
      Offset(s.width - 36, 4),
      color: FabFilterProcessorColors.reverbDecay);

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
      old.freezeAnim != freezeAnim ||
      old.lowDecayMult != lowDecayMult ||
      old.highDecayMult != highDecayMult ||
      old.brightness != brightness ||
      old.distance != distance ||
      old.wetLevel != wetLevel ||
      old.inputLevel != inputLevel ||
      old.historyIndex != historyIndex ||
      old.diffusion != diffusion ||
      old.mix != mix;
}
