/// FF-E De-Esser Panel
///
/// Professional de-esser processor inspired by FabFilter DS:
/// - Frequency and Bandwidth controls for sibilance targeting
/// - Threshold / Range dynamics
/// - Wideband and Split-Band modes
/// - Attack / Release timing
/// - Listen mode for monitoring the sibilance band
/// - Real-time gain reduction metering at ~30fps
/// - A/B comparison with full snapshot

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';
import 'fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Parameter indices matching DeEsserWrapper in Rust dsp_wrappers.rs
class _P {
  static const frequency = 0;  // 500..20000 Hz
  static const bandwidth = 1;  // 0.1..2.0 octaves
  static const threshold = 2;  // -60..0 dB
  static const range = 3;      // 0..40 dB
  static const mode = 4;       // 0=Wideband, 1=SplitBand
  static const attack = 5;     // 0.5..100 ms
  static const release = 6;    // 10..1000 ms
  static const listen = 7;     // 0/1
  static const bypass = 8;     // 0/1
}

const _modeLabels = ['WIDE', 'SPLIT'];

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class DeEsserSnapshot implements DspParameterSnapshot {
  final double frequency, bandwidth, threshold, range, attack, release;
  final int mode;
  final bool listen;

  const DeEsserSnapshot({
    required this.frequency, required this.bandwidth,
    required this.threshold, required this.range,
    required this.mode, required this.attack,
    required this.release, required this.listen,
  });

  @override
  DeEsserSnapshot copy() => DeEsserSnapshot(
    frequency: frequency, bandwidth: bandwidth,
    threshold: threshold, range: range,
    mode: mode, attack: attack,
    release: release, listen: listen,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! DeEsserSnapshot) return false;
    return frequency == other.frequency && bandwidth == other.bandwidth &&
        threshold == other.threshold && range == other.range &&
        mode == other.mode && attack == other.attack &&
        release == other.release && listen == other.listen;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterDeEsserPanel extends FabFilterPanelBase {
  const FabFilterDeEsserPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-E',
          icon: Icons.mic_off,
          accentColor: FabFilterColors.pink,
          nodeType: DspNodeType.deEsser,
        );

  @override
  State<FabFilterDeEsserPanel> createState() => _FabFilterDeEsserPanelState();
}

class _FabFilterDeEsserPanelState extends State<FabFilterDeEsserPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {

  // ─── PARAMETERS ─────────────────────────────────────────────────
  double _frequency = 6000.0;
  double _bandwidth = 0.5;
  double _threshold = -20.0;
  double _range = 12.0;
  int _mode = 0; // 0=Wideband, 1=SplitBand
  double _attack = 5.0;
  double _release = 50.0;
  bool _listen = false;

  // ─── METERING ───────────────────────────────────────────────────
  double _gainReduction = 0.0; // dB (negative)

  // ─── ENGINE ─────────────────────────────────────────────────────
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  String? _nodeId;
  int _slotIndex = -1;
  late AnimationController _meterController;

  // ─── A/B ────────────────────────────────────────────────────────
  DeEsserSnapshot? _snapshotA;
  DeEsserSnapshot? _snapshotB;

  @override
  int get processorSlotIndex => _slotIndex;

  // ─── LIFECYCLE ──────────────────────────────────────────────────

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
    final chain = dsp.getChain(widget.trackId);
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.deEsser) {
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
      _frequency = _ffi.insertGetParam(t, s, _P.frequency).clamp(500.0, 20000.0);
      _bandwidth = _ffi.insertGetParam(t, s, _P.bandwidth).clamp(0.1, 2.0);
      _threshold = _ffi.insertGetParam(t, s, _P.threshold).clamp(-60.0, 0.0);
      _range = _ffi.insertGetParam(t, s, _P.range).clamp(0.0, 40.0);
      _mode = _ffi.insertGetParam(t, s, _P.mode).round().clamp(0, 1);
      _attack = _ffi.insertGetParam(t, s, _P.attack).clamp(0.5, 100.0);
      _release = _ffi.insertGetParam(t, s, _P.release).clamp(10.0, 1000.0);
      _listen = _ffi.insertGetParam(t, s, _P.listen) > 0.5;
    });
  }

  void _setParam(int idx, double value) {
    if (_initialized && _slotIndex >= 0) {
      _ffi.insertSetParam(widget.trackId, _slotIndex, idx, value);
    }
  }

  // ─── A/B ────────────────────────────────────────────────────────

  DeEsserSnapshot _snap() => DeEsserSnapshot(
    frequency: _frequency, bandwidth: _bandwidth,
    threshold: _threshold, range: _range,
    mode: _mode, attack: _attack,
    release: _release, listen: _listen,
  );

  void _restore(DeEsserSnapshot s) {
    setState(() {
      _frequency = s.frequency; _bandwidth = s.bandwidth;
      _threshold = s.threshold; _range = s.range;
      _mode = s.mode; _attack = s.attack;
      _release = s.release; _listen = s.listen;
    });
    _applyAll();
  }

  void _applyAll() {
    if (!_initialized || _slotIndex < 0) return;
    _setParam(_P.frequency, _frequency);
    _setParam(_P.bandwidth, _bandwidth);
    _setParam(_P.threshold, _threshold);
    _setParam(_P.range, _range);
    _setParam(_P.mode, _mode.toDouble());
    _setParam(_P.attack, _attack);
    _setParam(_P.release, _release);
    _setParam(_P.listen, _listen ? 1 : 0);
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

  // ─── METERING ───────────────────────────────────────────────────

  void _updateMeters() {
    if (!_initialized || _slotIndex < 0) return;
    setState(() {
      try {
        // DeEsserWrapper exposes gain_reduction_db() via meter slot 0
        _gainReduction = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
      } catch (_) {}
    });
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  double _logNorm(double value, double minV, double maxV) {
    if (value <= minV) return 0;
    return (math.log(value) - math.log(minV)) / (math.log(maxV) - math.log(minV));
  }

  double _logDenorm(double norm, double minV, double maxV) {
    return math.exp(math.log(minV) + norm * (math.log(maxV) - math.log(minV)));
  }

  String _freqStr(double hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)}k' : '${hz.toStringAsFixed(0)} Hz';
  String _dbStr(double v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(1)} dB';
  String _msStr(double v) => v >= 100 ? '${v.toStringAsFixed(0)} ms' : '${v.toStringAsFixed(1)} ms';

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return buildNotLoadedState('De-Esser', DspNodeType.deEsser, widget.trackId, () {
        _initializeProcessor();
        setState(() {});
      });
    }
    return wrapWithBypassOverlay(Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          buildCompactHeader(),
          Expanded(child: _buildMainArea()),
          _buildGRMeter(),
          _buildFooter(),
        ],
      ),
    ));
  }

  // ─── MAIN CONTROL AREA ──────────────────────────────────────────

  Widget _buildMainArea() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Frequency band controls
          Expanded(flex: 3, child: _buildFrequencySection()),
          const SizedBox(width: 8),
          // Center: Dynamics controls
          Expanded(flex: 3, child: _buildDynamicsSection()),
          const SizedBox(width: 8),
          // Right: Timing + Mode
          SizedBox(width: 110, child: _buildSidebar()),
        ],
      ),
    );
  }

  Widget _buildFrequencySection() {
    return Column(
      children: [
        const FabSectionLabel('DETECTION'),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // FREQUENCY knob (logarithmic)
              FabFilterKnob(
                value: _logNorm(_frequency, 500, 20000),
                label: 'FREQ',
                display: _freqStr(_frequency),
                color: FabFilterColors.pink,
                size: 56,
                defaultValue: _logNorm(6000, 500, 20000),
                onChanged: (v) {
                  final freq = _logDenorm(v, 500, 20000);
                  setState(() => _frequency = freq);
                  _setParam(_P.frequency, freq);
                },
              ),
              // BANDWIDTH knob (logarithmic)
              FabFilterKnob(
                value: _logNorm(_bandwidth, 0.1, 2.0),
                label: 'BW',
                display: '${_bandwidth.toStringAsFixed(2)} oct',
                color: FabFilterColors.cyan,
                size: 56,
                defaultValue: _logNorm(0.5, 0.1, 2.0),
                onChanged: (v) {
                  final bw = _logDenorm(v, 0.1, 2.0);
                  setState(() => _bandwidth = bw);
                  _setParam(_P.bandwidth, bw);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicsSection() {
    return Column(
      children: [
        const FabSectionLabel('DYNAMICS'),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // THRESHOLD knob
              FabFilterKnob(
                value: ((_threshold + 60.0) / 60.0).clamp(0.0, 1.0),
                label: 'THRESH',
                display: _dbStr(_threshold),
                color: FabFilterColors.orange,
                size: 56,
                defaultValue: ((-20.0 + 60.0) / 60.0),
                onChanged: (v) {
                  final db = v * 60.0 - 60.0;
                  setState(() => _threshold = db);
                  _setParam(_P.threshold, db);
                },
              ),
              // RANGE knob
              FabFilterKnob(
                value: (_range / 40.0).clamp(0.0, 1.0),
                label: 'RANGE',
                display: _dbStr(_range),
                color: FabFilterColors.yellow,
                size: 56,
                defaultValue: 12.0 / 40.0,
                onChanged: (v) {
                  final db = v * 40.0;
                  setState(() => _range = db);
                  _setParam(_P.range, db);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode selector
        const FabSectionLabel('MODE'),
        const SizedBox(height: 4),
        Row(
          children: List.generate(2, (i) {
            final active = _mode == i;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 0 ? 2 : 0),
                child: FabTinyButton(
                  label: _modeLabels[i],
                  active: active,
                  color: FabFilterColors.pink,
                  onTap: () {
                    setState(() => _mode = i);
                    _setParam(_P.mode, i.toDouble());
                  },
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        // Timing
        const FabSectionLabel('TIMING'),
        const SizedBox(height: 4),
        FabMiniSlider(
          label: 'ATK',
          value: _logNorm(_attack, 0.5, 100),
          display: _msStr(_attack),
          activeColor: FabFilterColors.green,
          onChanged: (v) {
            final ms = _logDenorm(v, 0.5, 100);
            setState(() => _attack = ms);
            _setParam(_P.attack, ms);
          },
        ),
        const SizedBox(height: 2),
        FabMiniSlider(
          label: 'REL',
          value: _logNorm(_release, 10, 1000),
          display: _msStr(_release),
          activeColor: FabFilterColors.green,
          onChanged: (v) {
            final ms = _logDenorm(v, 10, 1000);
            setState(() => _release = ms);
            _setParam(_P.release, ms);
          },
        ),
        const SizedBox(height: 8),
        // Listen toggle
        FabCompactToggle(
          label: 'LISTEN',
          active: _listen,
          color: FabFilterColors.yellow,
          onToggle: () {
            setState(() => _listen = !_listen);
            _setParam(_P.listen, _listen ? 1 : 0);
          },
        ),
        const Flexible(child: SizedBox(height: 8)),
      ],
    );
  }

  // ─── GAIN REDUCTION METER ───────────────────────────────────────

  Widget _buildGRMeter() {
    final grDb = _gainReduction.clamp(-40.0, 0.0);
    final norm = (grDb.abs() / 40.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: FabHorizontalMeter(
        label: 'GR',
        value: norm,
        color: FabFilterColors.orange,
        height: 12,
        displayText: '${grDb.toStringAsFixed(1)} dB',
        inverted: true,
      ),
    );
  }

  // ─── FOOTER ─────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(top: BorderSide(color: FabFilterColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            _freqStr(_frequency),
            style: FabFilterText.paramLabel.copyWith(fontSize: 8, color: FabFilterColors.pink),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 8),
          Text(
            _modeLabels[_mode],
            style: FabFilterText.paramLabel.copyWith(fontSize: 8, color: FabFilterColors.cyan),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          if (_listen)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.yellow.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: FabFilterColors.yellow, width: 0.5),
              ),
              child: Text(
                'LISTEN',
                style: FabFilterText.paramLabel.copyWith(fontSize: 7, color: FabFilterColors.yellow),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (_listen) const SizedBox(width: 8),
          Text(
            'GR: ${_gainReduction.toStringAsFixed(1)} dB',
            style: FabFilterText.paramLabel.copyWith(
              fontSize: 8,
              color: _gainReduction < -3 ? FabFilterColors.orange : FabFilterColors.textTertiary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
