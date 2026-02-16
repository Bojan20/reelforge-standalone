/// FF-DLY Delay Panel — Timeless 3 Style
///
/// Professional stereo delay processor:
/// - Delay tap visualization with feedback trails
/// - Linked/unlinked L/R delay times
/// - Ping-pong stereo bounce mode
/// - HP/LP feedback filters
/// - Modulation (rate + depth)
/// - Ducking, freeze, tempo sync
/// - Real-time I/O metering at ~30fps
/// - A/B comparison with full state snapshots

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARAMETER INDICES (must match Rust DelayWrapper)
// ═══════════════════════════════════════════════════════════════════════════

class _P {
  static const delayL = 0;
  static const delayR = 1;
  static const feedback = 2;
  static const mix = 3;
  static const pingPong = 4;
  static const hpFilter = 5;
  static const lpFilter = 6;
  static const modRate = 7;
  static const modDepth = 8;
  static const width = 9;
  static const ducking = 10;
  static const link = 11;
  static const freeze = 12;
  static const tempoSync = 13;
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class DelaySnapshot implements DspParameterSnapshot {
  final double delayL, delayR, feedback, mix, pingPong;
  final double hpFilter, lpFilter, modRate, modDepth;
  final double width, ducking;
  final bool link, freeze, tempoSync;

  const DelaySnapshot({
    required this.delayL, required this.delayR, required this.feedback,
    required this.mix, required this.pingPong, required this.hpFilter,
    required this.lpFilter, required this.modRate, required this.modDepth,
    required this.width, required this.ducking, required this.link,
    required this.freeze, required this.tempoSync,
  });

  @override
  DelaySnapshot copy() => DelaySnapshot(
    delayL: delayL, delayR: delayR, feedback: feedback, mix: mix,
    pingPong: pingPong, hpFilter: hpFilter, lpFilter: lpFilter,
    modRate: modRate, modDepth: modDepth, width: width, ducking: ducking,
    link: link, freeze: freeze, tempoSync: tempoSync,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! DelaySnapshot) return false;
    return delayL == other.delayL && delayR == other.delayR &&
        feedback == other.feedback && mix == other.mix &&
        pingPong == other.pingPong && link == other.link &&
        freeze == other.freeze && tempoSync == other.tempoSync;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterDelayPanel extends FabFilterPanelBase {
  const FabFilterDelayPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-DLY',
          icon: Icons.timer,
          accentColor: FabFilterColors.cyan,
          nodeType: DspNodeType.delay,
        );

  @override
  State<FabFilterDelayPanel> createState() => _FabFilterDelayPanelState();
}

class _FabFilterDelayPanelState extends State<FabFilterDelayPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {

  // ─── DSP PARAMETERS ──────────────────────────────────────────────────
  double _delayL = 375.0;
  double _delayR = 375.0;
  double _feedback = 40.0;
  double _mix = 30.0;
  double _pingPong = 0.0;
  double _hpFilter = 80.0;
  double _lpFilter = 12000.0;
  double _modRate = 0.5;
  double _modDepth = 10.0;
  double _width = 100.0;
  double _ducking = 0.0;
  bool _link = true;
  bool _freeze = false;
  bool _tempoSync = false;

  // ─── METERING ────────────────────────────────────────────────────────
  double _inPeakL = 0.0;
  double _inPeakR = 0.0;
  double _outPeakL = 0.0;
  double _outPeakR = 0.0;

  // ─── ENGINE ──────────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ─────────────────────────────────────────────────────────────
  DelaySnapshot? _snapshotA;
  DelaySnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  // ─── LIFECYCLE ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
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
    super.dispose();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);
    if (!chain.nodes.any((n) => n.type == DspNodeType.delay)) {
      dsp.addNode(widget.trackId, DspNodeType.delay);
      chain = dsp.getChain(widget.trackId);
    }
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.delay) {
        _nodeId = node.id;
        _slotIndex = chain.nodes.indexWhere((n) => n.id == _nodeId);
        _initialized = true;
        _readParams();
        break;
      }
    }
  }

  void _readParams() {
    if (!_initialized || _slotIndex < 0) return;
    final t = widget.trackId, s = _slotIndex;
    setState(() {
      _delayL = _ffi.insertGetParam(t, s, _P.delayL);
      _delayR = _ffi.insertGetParam(t, s, _P.delayR);
      _feedback = _ffi.insertGetParam(t, s, _P.feedback);
      _mix = _ffi.insertGetParam(t, s, _P.mix);
      _pingPong = _ffi.insertGetParam(t, s, _P.pingPong);
      _hpFilter = _ffi.insertGetParam(t, s, _P.hpFilter);
      _lpFilter = _ffi.insertGetParam(t, s, _P.lpFilter);
      _modRate = _ffi.insertGetParam(t, s, _P.modRate);
      _modDepth = _ffi.insertGetParam(t, s, _P.modDepth);
      _width = _ffi.insertGetParam(t, s, _P.width);
      _ducking = _ffi.insertGetParam(t, s, _P.ducking);
      _link = _ffi.insertGetParam(t, s, _P.link) > 0.5;
      _freeze = _ffi.insertGetParam(t, s, _P.freeze) > 0.5;
      _tempoSync = _ffi.insertGetParam(t, s, _P.tempoSync) > 0.5;
    });
  }

  void _setParam(int idx, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, idx, value);
    }
  }

  // ─── A/B STATE ───────────────────────────────────────────────────────

  DelaySnapshot _snap() => DelaySnapshot(
    delayL: _delayL, delayR: _delayR, feedback: _feedback, mix: _mix,
    pingPong: _pingPong, hpFilter: _hpFilter, lpFilter: _lpFilter,
    modRate: _modRate, modDepth: _modDepth, width: _width,
    ducking: _ducking, link: _link, freeze: _freeze, tempoSync: _tempoSync,
  );

  void _restore(DelaySnapshot s) {
    setState(() {
      _delayL = s.delayL; _delayR = s.delayR; _feedback = s.feedback;
      _mix = s.mix; _pingPong = s.pingPong; _hpFilter = s.hpFilter;
      _lpFilter = s.lpFilter; _modRate = s.modRate; _modDepth = s.modDepth;
      _width = s.width; _ducking = s.ducking; _link = s.link;
      _freeze = s.freeze; _tempoSync = s.tempoSync;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.delayL, _delayL);
    _setParam(_P.delayR, _delayR);
    _setParam(_P.feedback, _feedback);
    _setParam(_P.mix, _mix);
    _setParam(_P.pingPong, _pingPong);
    _setParam(_P.hpFilter, _hpFilter);
    _setParam(_P.lpFilter, _lpFilter);
    _setParam(_P.modRate, _modRate);
    _setParam(_P.modDepth, _modDepth);
    _setParam(_P.width, _width);
    _setParam(_P.ducking, _ducking);
    _setParam(_P.link, _link ? 1.0 : 0.0);
    _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
    _setParam(_P.tempoSync, _tempoSync ? 1.0 : 0.0);
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

  // ─── METERING ────────────────────────────────────────────────────────

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

  // ─── HELPERS ─────────────────────────────────────────────────────────

  double _logNorm(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;
    return (math.log(value) - math.log(min)) / (math.log(max) - math.log(min));
  }

  double _logDenorm(double norm, double min, double max) {
    return math.exp(math.log(min) + norm * (math.log(max) - math.log(min)));
  }

  String _fmtMs(double ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)}s';
    if (ms >= 100) return '${ms.toStringAsFixed(0)}ms';
    return '${ms.toStringAsFixed(1)}ms';
  }

  String _fmtHz(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)}k';
    return '${hz.toStringAsFixed(0)}Hz';
  }

  String _fmtPct(double v) => '${v.toStringAsFixed(0)}%';

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildHeader(),
          // Delay tap visualization
          SizedBox(
            height: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildVisualization(),
            ),
          ),
          // Controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _buildMainKnobRow(),
                  const SizedBox(height: 6),
                  _buildSecondaryRow(),
                  const SizedBox(height: 6),
                  Expanded(child: _buildExpertSection()),
                ],
              ),
            ),
          ),
          // Bottom toggles
          _buildBottomToggles(),
        ],
      ),
    ));
  }

  // ─── HEADER ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final inDb = _peakToDb(math.max(_inPeakL, _inPeakR));
    final outDb = _peakToDb(math.max(_outPeakL, _outPeakR));

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(bottom: BorderSide(color: FabFilterColors.cyan.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.timer, color: FabFilterColors.cyan, size: 14),
          const SizedBox(width: 6),
          Text('FF-DLY', style: FabFilterText.sectionHeader.copyWith(
            color: FabFilterColors.cyan, fontSize: 10, letterSpacing: 1.2,
          )),
          const SizedBox(width: 8),
          // Input meter
          _buildMiniMeter('IN', inDb),
          const SizedBox(width: 4),
          _buildMiniMeter('OUT', outDb),
          const Spacer(),
          FabCompactAB(isStateB: isStateB, onToggle: toggleAB, accentColor: FabFilterColors.cyan),
          const SizedBox(width: 6),
          FabMiniButton(label: 'E', active: showExpertMode, onTap: toggleExpertMode, accentColor: FabFilterColors.cyan),
          const SizedBox(width: 6),
          FabCompactBypass(bypassed: bypassed, onToggle: toggleBypass),
          if (widget.onClose != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, size: 14, color: FabFilterColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniMeter(String label, double db) {
    final norm = ((db + 60) / 60).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 7)),
        const SizedBox(width: 2),
        SizedBox(
          width: 24,
          height: 4,
          child: Container(
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: norm,
              child: Container(
                decoration: BoxDecoration(
                  color: norm > 0.9 ? FabFilterColors.red : FabFilterColors.cyan,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _peakToDb(double linear) {
    return linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;
  }

  // ─── VISUALIZATION ───────────────────────────────────────────────────

  Widget _buildVisualization() {
    return Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.hardEdge,
      child: CustomPaint(
        painter: _DelayTapPainter(
          delayL: _delayL,
          delayR: _delayR,
          feedback: _feedback / 100.0,
          pingPong: _pingPong / 100.0,
          linked: _link,
          freeze: _freeze,
        ),
        size: Size.infinite,
      ),
    );
  }

  // ─── MAIN KNOB ROW ──────────────────────────────────────────────────

  Widget _buildMainKnobRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildDelayKnob('DELAY L', _delayL, (v) {
          setState(() {
            _delayL = v;
            if (_link) _delayR = v;
          });
          _setParam(_P.delayL, v);
          if (_link) _setParam(_P.delayR, v);
        }),
        _buildDelayKnob(_link ? 'DELAY R' : 'DELAY R', _delayR, (v) {
          setState(() => _delayR = v);
          _setParam(_P.delayR, v);
          if (_link) {
            setState(() => _delayL = v);
            _setParam(_P.delayL, v);
          }
        }),
        FabFilterKnob(
          value: _feedback / 100.0,
          label: 'FDBK',
          display: _fmtPct(_feedback),
          color: FabFilterColors.orange,
          size: 48,
          defaultValue: 0.4,
          onChanged: (v) {
            setState(() => _feedback = v * 100.0);
            _setParam(_P.feedback, v * 100.0);
          },
        ),
        FabFilterKnob(
          value: _mix / 100.0,
          label: 'MIX',
          display: _fmtPct(_mix),
          color: FabFilterColors.cyan,
          size: 48,
          defaultValue: 0.3,
          onChanged: (v) {
            setState(() => _mix = v * 100.0);
            _setParam(_P.mix, v * 100.0);
          },
        ),
      ],
    );
  }

  Widget _buildDelayKnob(String label, double ms, ValueChanged<double> onMs) {
    final norm = _logNorm(ms.clamp(1, 5000), 1, 5000);
    return FabFilterKnob(
      value: norm,
      label: label,
      display: _fmtMs(ms),
      color: FabFilterColors.cyan,
      size: 48,
      defaultValue: _logNorm(375, 1, 5000),
      onChanged: (v) => onMs(_logDenorm(v, 1, 5000)),
    );
  }

  // ─── SECONDARY ROW ──────────────────────────────────────────────────

  Widget _buildSecondaryRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FabFilterKnob(
          value: _pingPong / 100.0,
          label: 'P-PONG',
          display: _fmtPct(_pingPong),
          color: FabFilterColors.purple,
          size: 40,
          defaultValue: 0.0,
          onChanged: (v) {
            setState(() => _pingPong = v * 100.0);
            _setParam(_P.pingPong, v * 100.0);
          },
        ),
        FabFilterKnob(
          value: _width / 200.0,
          label: 'WIDTH',
          display: '${_width.toStringAsFixed(0)}%',
          color: FabFilterColors.blue,
          size: 40,
          defaultValue: 0.5,
          onChanged: (v) {
            setState(() => _width = v * 200.0);
            _setParam(_P.width, v * 200.0);
          },
        ),
        FabFilterKnob(
          value: _ducking / 100.0,
          label: 'DUCK',
          display: _fmtPct(_ducking),
          color: FabFilterColors.yellow,
          size: 40,
          defaultValue: 0.0,
          onChanged: (v) {
            setState(() => _ducking = v * 100.0);
            _setParam(_P.ducking, v * 100.0);
          },
        ),
      ],
    );
  }

  // ─── EXPERT SECTION ──────────────────────────────────────────────────

  Widget _buildExpertSection() {
    if (!showExpertMode) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FabSectionLabel('FILTER'),
          Row(
            children: [
              Expanded(child: _buildFilterKnob('HP', _hpFilter, (v) {
                setState(() => _hpFilter = v);
                _setParam(_P.hpFilter, v);
              })),
              Expanded(child: _buildFilterKnob('LP', _lpFilter, (v) {
                setState(() => _lpFilter = v);
                _setParam(_P.lpFilter, v);
              })),
            ],
          ),
          const SizedBox(height: 6),
          const FabSectionLabel('MODULATION'),
          Row(
            children: [
              Expanded(
                child: FabFilterKnob(
                  value: _modRate / 10.0,
                  label: 'RATE',
                  display: '${_modRate.toStringAsFixed(2)}Hz',
                  color: FabFilterColors.green,
                  size: 36,
                  defaultValue: 0.05,
                  onChanged: (v) {
                    setState(() => _modRate = v * 10.0);
                    _setParam(_P.modRate, v * 10.0);
                  },
                ),
              ),
              Expanded(
                child: FabFilterKnob(
                  value: _modDepth / 100.0,
                  label: 'DEPTH',
                  display: _fmtPct(_modDepth),
                  color: FabFilterColors.green,
                  size: 36,
                  defaultValue: 0.1,
                  onChanged: (v) {
                    setState(() => _modDepth = v * 100.0);
                    _setParam(_P.modDepth, v * 100.0);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterKnob(String label, double hz, ValueChanged<double> onHz) {
    final norm = _logNorm(hz.clamp(20, 20000), 20, 20000);
    return FabFilterKnob(
      value: norm,
      label: label,
      display: _fmtHz(hz),
      color: FabFilterColors.orange,
      size: 36,
      defaultValue: label == 'HP' ? _logNorm(80, 20, 20000) : _logNorm(12000, 20, 20000),
      onChanged: (v) => onHz(_logDenorm(v, 20, 20000)),
    );
  }

  // ─── BOTTOM TOGGLES ──────────────────────────────────────────────────

  Widget _buildBottomToggles() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          FabCompactToggle(
            label: 'LINK',
            active: _link,
            color: FabFilterColors.cyan,
            onToggle: () {
              setState(() => _link = !_link);
              _setParam(_P.link, _link ? 1.0 : 0.0);
              if (_link) {
                setState(() => _delayR = _delayL);
                _setParam(_P.delayR, _delayL);
              }
            },
          ),
          const SizedBox(width: 6),
          FabCompactToggle(
            label: 'FRZ',
            active: _freeze,
            color: FabFilterColors.blue,
            onToggle: () {
              setState(() => _freeze = !_freeze);
              _setParam(_P.freeze, _freeze ? 1.0 : 0.0);
            },
          ),
          const SizedBox(width: 6),
          FabCompactToggle(
            label: 'SYNC',
            active: _tempoSync,
            color: FabFilterColors.green,
            onToggle: () {
              setState(() => _tempoSync = !_tempoSync);
              _setParam(_P.tempoSync, _tempoSync ? 1.0 : 0.0);
            },
          ),
          const Spacer(),
          // Feedback amount display
          Text(
            'FB ${_feedback.toStringAsFixed(0)}%',
            style: FabFilterText.paramLabel.copyWith(
              fontSize: 8,
              color: _feedback > 90 ? FabFilterColors.red : FabFilterColors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          // Delay times summary
          Text(
            _link ? 'L=R ${_fmtMs(_delayL)}' : 'L${_fmtMs(_delayL)} R${_fmtMs(_delayR)}',
            style: FabFilterText.paramLabel.copyWith(fontSize: 8),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELAY TAP VISUALIZATION PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _DelayTapPainter extends CustomPainter {
  final double delayL;
  final double delayR;
  final double feedback;
  final double pingPong;
  final bool linked;
  final bool freeze;

  _DelayTapPainter({
    required this.delayL,
    required this.delayR,
    required this.feedback,
    required this.pingPong,
    required this.linked,
    required this.freeze,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final maxDelay = math.max(delayL, delayR).clamp(1.0, 5000.0);
    final timeScale = (w - 24) / (maxDelay * 4).clamp(500.0, 20000.0);

    // Background grid
    _drawGrid(canvas, size);

    // Draw feedback taps
    final taps = _generateTaps(timeScale, w);
    for (final tap in taps) {
      final x = tap.x;
      if (x > w - 4) continue;

      final alpha = tap.amplitude.clamp(0.0, 1.0);
      final isLeft = tap.isLeft;
      final color = isLeft ? FabFilterColors.cyan : FabFilterColors.orange;
      final tapH = (h * 0.35) * alpha;

      // Tap line
      canvas.drawLine(
        Offset(x, midY - tapH),
        Offset(x, midY + tapH),
        Paint()
          ..color = color.withValues(alpha: alpha * 0.9)
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round,
      );

      // Glow
      canvas.drawLine(
        Offset(x, midY - tapH * 0.8),
        Offset(x, midY + tapH * 0.8),
        Paint()
          ..color = color.withValues(alpha: alpha * 0.2)
          ..strokeWidth = 8.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Freeze indicator
    if (freeze) {
      final freezePaint = Paint()
        ..color = FabFilterColors.blue.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), freezePaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: 'FREEZE',
          style: TextStyle(
            color: FabFilterColors.blue.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(w / 2 - textPainter.width / 2, 4));
    }

    // Center line
    canvas.drawLine(
      Offset(0, midY),
      Offset(w, midY),
      Paint()
        ..color = FabFilterColors.borderSubtle.withValues(alpha: 0.5)
        ..strokeWidth = 0.5,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Vertical grid (time divisions)
    for (int i = 1; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal grid
    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  List<_Tap> _generateTaps(double timeScale, double maxWidth) {
    final taps = <_Tap>[];
    final maxTaps = 12;
    var ampL = 1.0;
    var ampR = 1.0;

    for (int i = 0; i < maxTaps; i++) {
      final timeL = delayL * (i + 1);
      final timeR = delayR * (i + 1);

      if (pingPong > 0.5) {
        // Ping-pong: alternate L/R
        final isLeft = i.isEven;
        final time = isLeft ? timeL : timeR;
        final amp = isLeft ? ampL : ampR;
        final x = 12 + time * timeScale;
        if (x < maxWidth - 4) {
          taps.add(_Tap(x: x, amplitude: amp, isLeft: isLeft));
        }
        if (isLeft) {
          ampL *= feedback;
        } else {
          ampR *= feedback;
        }
      } else {
        // Normal: L and R taps at their own delay times
        final xL = 12 + timeL * timeScale;
        final xR = 12 + timeR * timeScale;
        if (xL < maxWidth - 4) {
          taps.add(_Tap(x: xL, amplitude: ampL, isLeft: true));
        }
        if (!linked && xR < maxWidth - 4) {
          taps.add(_Tap(x: xR, amplitude: ampR, isLeft: false));
        }
        ampL *= feedback;
        ampR *= feedback;
      }

      if (ampL < 0.02 && ampR < 0.02) break;
    }

    return taps;
  }

  @override
  bool shouldRepaint(covariant _DelayTapPainter old) {
    return delayL != old.delayL || delayR != old.delayR ||
        feedback != old.feedback || pingPong != old.pingPong ||
        linked != old.linked || freeze != old.freeze;
  }
}

class _Tap {
  final double x;
  final double amplitude;
  final bool isLeft;
  const _Tap({required this.x, required this.amplitude, required this.isLeft});
}
