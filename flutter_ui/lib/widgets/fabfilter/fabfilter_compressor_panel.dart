/// FF-C Compressor Panel
///
/// Professional compressor interface:
/// - Animated level/knee display
/// - 14 compression styles
/// - Character modes (Tube, Diode, Bright)
/// - 6-band sidechain EQ
/// - Transfer curve visualization
/// - Real-time gain reduction metering

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../src/rust/native_ffi.dart';
import '../../providers/dsp_chain_provider.dart';
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Compression style (14 styles)
enum CompressionStyle {
  clean('Clean', 'Transparent digital compression'),
  classic('Classic', 'Classic VCA-style compression'),
  opto('Opto', 'Optical compressor emulation'),
  vocal('Vocal', 'Optimized for vocals'),
  mastering('Mastering', 'Gentle mastering compression'),
  bus('Bus', 'Glue compression for buses'),
  punch('Punch', 'Punchy transient preservation'),
  pumping('Pumping', 'Deliberate pumping effect'),
  versatile('Versatile', 'General purpose - NEW'),
  smooth('Smooth', 'Super smooth gluing - NEW'),
  upward('Upward', 'Upward compression - NEW'),
  ttm('TTM', 'To The Max - multiband - NEW'),
  variMu('Vari-Mu', 'Tube variable-mu - NEW'),
  elOp('El-Op', 'Optical emulation - NEW');

  final String label;
  final String description;
  const CompressionStyle(this.label, this.description);
}

/// Character mode for saturation
enum CharacterMode {
  off('Off', Colors.grey),
  tube('Tube', FabFilterColors.orange),
  diode('Diode', FabFilterColors.yellow),
  bright('Bright', FabFilterColors.cyan);

  final String label;
  final Color color;
  const CharacterMode(this.label, this.color);
}

/// Sidechain EQ band
class SidechainBand {
  int index;
  double freq;
  double gain;
  double q;
  bool enabled;

  SidechainBand({
    required this.index,
    this.freq = 1000,
    this.gain = 0,
    this.q = 1.0,
    this.enabled = true,
  });
}

/// Level history sample for scrolling display
class LevelSample {
  final double input;
  final double output;
  final double gainReduction;
  final DateTime timestamp;

  LevelSample({
    required this.input,
    required this.output,
    required this.gainReduction,
    required this.timestamp,
  });
}

/// Snapshot of compressor parameters for A/B comparison
class CompressorSnapshot implements DspParameterSnapshot {
  final double threshold;
  final double ratio;
  final double knee;
  final double attack;
  final double release;
  final double range;
  final double mix;
  final double output;
  final CompressionStyle style;
  final CharacterMode character;
  final double drive;
  final bool sidechainEnabled;
  final double sidechainHpf;
  final double sidechainLpf;

  const CompressorSnapshot({
    required this.threshold,
    required this.ratio,
    required this.knee,
    required this.attack,
    required this.release,
    required this.range,
    required this.mix,
    required this.output,
    required this.style,
    required this.character,
    required this.drive,
    required this.sidechainEnabled,
    required this.sidechainHpf,
    required this.sidechainLpf,
  });

  @override
  CompressorSnapshot copy() => CompressorSnapshot(
    threshold: threshold,
    ratio: ratio,
    knee: knee,
    attack: attack,
    release: release,
    range: range,
    mix: mix,
    output: output,
    style: style,
    character: character,
    drive: drive,
    sidechainEnabled: sidechainEnabled,
    sidechainHpf: sidechainHpf,
    sidechainLpf: sidechainLpf,
  );

  @override
  bool equals(DspParameterSnapshot other) {
    if (other is! CompressorSnapshot) return false;
    return threshold == other.threshold &&
        ratio == other.ratio &&
        knee == other.knee &&
        attack == other.attack &&
        release == other.release &&
        range == other.range &&
        mix == other.mix &&
        output == other.output &&
        style == other.style &&
        character == other.character &&
        drive == other.drive &&
        sidechainEnabled == other.sidechainEnabled &&
        sidechainHpf == other.sidechainHpf &&
        sidechainLpf == other.sidechainLpf;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterCompressorPanel extends FabFilterPanelBase {
  const FabFilterCompressorPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'FF-C',
          icon: Icons.compress,
          accentColor: FabFilterColors.orange,
          nodeType: DspNodeType.compressor,
        );

  @override
  State<FabFilterCompressorPanel> createState() =>
      _FabFilterCompressorPanelState();
}

class _FabFilterCompressorPanelState extends State<FabFilterCompressorPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  // Main parameters
  double _threshold = -18.0; // dB
  double _ratio = 4.0; // :1
  double _knee = 12.0; // dB (NOTE: Not supported in insert chain, UI-only)
  double _attack = 10.0; // ms
  double _release = 100.0; // ms
  double _range = -40.0; // dB
  double _mix = 100.0; // %
  double _output = 0.0; // dB

  // Style & character
  CompressionStyle _style = CompressionStyle.clean;
  CharacterMode _character = CharacterMode.off;
  double _drive = 0.0; // dB

  // Sidechain
  bool _sidechainEnabled = false;
  double _sidechainHpf = 80.0; // Hz
  double _sidechainLpf = 12000.0; // Hz
  bool _sidechainEqVisible = false;
  List<SidechainBand> _sidechainBands = [];
  bool _sidechainAudition = false;

  // Display
  bool _compactView = false;
  final List<LevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 200;

  // Animation
  late AnimationController _meterController;
  double _currentInputLevel = -60.0;
  double _currentOutputLevel = -60.0;
  double _currentGainReduction = 0.0;
  double _peakGainReduction = 0.0;

  // Auto threshold
  bool _autoThreshold = false;

  // A/B comparison snapshots
  CompressorSnapshot? _snapshotA;
  CompressorSnapshot? _snapshotB;

  // Host sync
  bool _hostSync = false;

  // FFI & DspChainProvider integration
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  // DspChainProvider tracking (FIX: Use insert chain, not ghost DYNAMICS_COMPRESSORS)
  String? _nodeId;
  int _slotIndex = -1;

  @override
  int get processorSlotIndex => _slotIndex;

  @override
  void initState() {
    super.initState();

    // Initialize FFI compressor
    _initializeProcessor();

    // Initialize sidechain EQ bands
    _sidechainBands = List.generate(
      6,
      (i) => SidechainBand(
        index: i,
        freq: 100 * math.pow(2, i).toDouble(),
        gain: 0,
        q: 1.0,
        enabled: true,
      ),
    );

    // Meter animation controller
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);

    _meterController.repeat();
  }

  /// Initialize processor via DspChainProvider (FIX: Uses insert chain, not ghost HashMap)
  ///
  /// This ensures the compressor is in the actual audio signal path.
  /// Previous implementation used compressorCreate() which created a ghost
  /// instance that was NEVER processed by the audio thread.
  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Find existing compressor node or add one
    DspNode? compNode;
    bool isNewNode = false;
    for (final node in chain.nodes) {
      if (node.type == DspNodeType.compressor) {
        compNode = node;
        break;
      }
    }

    if (compNode == null) {
      // Add compressor via DspChainProvider (this calls insertLoadProcessor → insert chain)
      dsp.addNode(widget.trackId, DspNodeType.compressor);
      final updatedChain = dsp.getChain(widget.trackId);
      if (updatedChain.nodes.isNotEmpty) {
        compNode = updatedChain.nodes.last;
        isNewNode = true;
      }
    }

    if (compNode != null) {
      _nodeId = compNode.id;
      _slotIndex = dsp.getChain(widget.trackId).nodes.indexWhere((n) => n.id == _nodeId);
      _initialized = true;
      if (isNewNode) {
        _applyAllParameters();
      } else {
        _readParamsFromEngine();
      }
    }
  }

  /// Apply all parameters to the insert chain compressor (FIX: Uses insertSetParam)
  ///
  /// Parameter indices for CompressorWrapper in insert chain:
  /// 0: Threshold (dB)
  /// 1: Ratio (:1)
  /// 2: Attack (ms)
  /// 3: Release (ms)
  /// 4: Makeup/Output (dB)
  /// 5: Mix (0-1)
  /// 6: Link (0-1)
  /// 7: Type (0=VCA, 1=Opto, 2=FET)
  void _applyAllParameters() {
    if (!_initialized || _slotIndex < 0) return;

    // Use insertSetParam to set parameters on the REAL insert chain processor
    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);     // Threshold
    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _ratio);         // Ratio
    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _attack);        // Attack
    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _release);       // Release
    _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _output);        // Makeup/Output
    _ffi.insertSetParam(widget.trackId, _slotIndex, 5, _mix / 100.0);   // Mix (0-1)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 6, 1.0);           // Link (fully linked stereo)
    _ffi.insertSetParam(widget.trackId, _slotIndex, 7, _styleToTypeIndex(_style).toDouble()); // Type
  }

  /// Read current parameters from engine (when re-opening existing processor)
  void _readParamsFromEngine() {
    if (!_initialized || _slotIndex < 0) return;
    setState(() {
      _threshold = _ffi.insertGetParam(widget.trackId, _slotIndex, 0);
      _ratio = _ffi.insertGetParam(widget.trackId, _slotIndex, 1);
      _attack = _ffi.insertGetParam(widget.trackId, _slotIndex, 2);
      _release = _ffi.insertGetParam(widget.trackId, _slotIndex, 3);
      _output = _ffi.insertGetParam(widget.trackId, _slotIndex, 4);
      final mixVal = _ffi.insertGetParam(widget.trackId, _slotIndex, 5);
      _mix = mixVal * 100.0;
    });
  }

  /// Map FabFilter style to insert chain compressor type index
  /// 0 = VCA, 1 = Opto, 2 = FET
  int _styleToTypeIndex(CompressionStyle style) {
    return switch (style) {
      CompressionStyle.clean => 0,       // VCA - Transparent
      CompressionStyle.classic => 0,     // VCA - Classic VCA
      CompressionStyle.opto => 1,        // Opto - Optical
      CompressionStyle.vocal => 1,       // Opto - Smooth for vocals
      CompressionStyle.mastering => 0,   // VCA - Clean mastering
      CompressionStyle.bus => 0,         // VCA - Glue
      CompressionStyle.punch => 2,       // FET - Punchy
      CompressionStyle.pumping => 2,     // FET - Aggressive
      CompressionStyle.versatile => 0,   // VCA - General
      CompressionStyle.smooth => 1,      // Opto - Smooth optical
      CompressionStyle.upward => 0,      // VCA - Upward
      CompressionStyle.ttm => 2,         // FET - Aggressive multiband
      CompressionStyle.variMu => 1,      // Opto - Tube-like
      CompressionStyle.elOp => 1,        // Opto - Optical
    };
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    // NOTE: Don't remove the compressor from DspChainProvider on dispose
    // The node lifecycle is managed by DspChainProvider, not by this panel.
    // The panel is just a UI for an existing insert chain processor.
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A/B COMPARISON — State capture and restoration
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a snapshot of current parameters
  CompressorSnapshot _createSnapshot() {
    return CompressorSnapshot(
      threshold: _threshold,
      ratio: _ratio,
      knee: _knee,
      attack: _attack,
      release: _release,
      range: _range,
      mix: _mix,
      output: _output,
      style: _style,
      character: _character,
      drive: _drive,
      sidechainEnabled: _sidechainEnabled,
      sidechainHpf: _sidechainHpf,
      sidechainLpf: _sidechainLpf,
    );
  }

  /// Restore parameters from a snapshot
  void _restoreSnapshot(CompressorSnapshot snapshot) {
    setState(() {
      _threshold = snapshot.threshold;
      _ratio = snapshot.ratio;
      _knee = snapshot.knee;
      _attack = snapshot.attack;
      _release = snapshot.release;
      _range = snapshot.range;
      _mix = snapshot.mix;
      _output = snapshot.output;
      _style = snapshot.style;
      _character = snapshot.character;
      _drive = snapshot.drive;
      _sidechainEnabled = snapshot.sidechainEnabled;
      _sidechainHpf = snapshot.sidechainHpf;
      _sidechainLpf = snapshot.sidechainLpf;
    });
    _applyAllParameters();
  }

  @override
  void storeStateA() {
    _snapshotA = _createSnapshot();
    super.storeStateA();
  }

  @override
  void storeStateB() {
    _snapshotB = _createSnapshot();
    super.storeStateB();
  }

  @override
  void restoreStateA() {
    if (_snapshotA != null) {
      _restoreSnapshot(_snapshotA!);
    }
  }

  @override
  void restoreStateB() {
    if (_snapshotB != null) {
      _restoreSnapshot(_snapshotB!);
    }
  }

  @override
  void copyAToB() {
    _snapshotB = _snapshotA?.copy();
    super.copyAToB();
  }

  @override
  void copyBToA() {
    _snapshotA = _snapshotB?.copy();
    super.copyBToA();
  }

  void _updateMeters() {
    setState(() {
      // Get gain reduction from insert processor
      if (_slotIndex >= 0) {
        try {
          final grL = _ffi.insertGetMeter(widget.trackId, _slotIndex, 0);
          final grR = _ffi.insertGetMeter(widget.trackId, _slotIndex, 1);
          _currentGainReduction = (grL + grR) / 2.0;
        } catch (_) {
          _currentGainReduction = 0.0;
        }
      }

      // Get input/output levels from peak meters
      try {
        final peaks = _ffi.getPeakMeters();
        if (peaks.$1 > 0 || peaks.$2 > 0) {
          final peakLinear = math.max(peaks.$1, peaks.$2);
          _currentInputLevel = peakLinear > 1e-10 ? 20.0 * math.log(peakLinear) / math.ln10 : -60.0;
          _currentOutputLevel = _currentInputLevel + _currentGainReduction;
        }
      } catch (_) {
        _currentInputLevel = -60.0;
        _currentOutputLevel = -60.0;
      }

      // Track peak GR only if real data present
      if (_currentGainReduction.abs() > 0.01 && _currentGainReduction.abs() > _peakGainReduction.abs()) {
        _peakGainReduction = _currentGainReduction;
      }

      // Add to history only with real activity
      if (_currentGainReduction.abs() > 0.01) {
        _levelHistory.add(LevelSample(
          input: _currentInputLevel,
          output: _currentOutputLevel,
          gainReduction: _currentGainReduction,
          timestamp: DateTime.now(),
        ));

        while (_levelHistory.length > _maxHistorySamples) {
          _levelHistory.removeAt(0);
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD — Compact horizontal layout, NO scrolling
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return wrapWithBypassOverlay(Container(
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
                  // LEFT: Transfer curve + GR meter
                  _buildCompactDisplay(),
                  const SizedBox(width: 12),
                  // CENTER: Main knobs
                  Expanded(
                    flex: 3,
                    child: _buildCompactControls(),
                  ),
                  const SizedBox(width: 12),
                  // RIGHT: Style + options
                  _buildCompactOptions(),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildCompactHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(widget.icon, color: widget.accentColor, size: 14),
          const SizedBox(width: 6),
          Text(widget.title, style: FabFilterText.title.copyWith(fontSize: 11)),
          const SizedBox(width: 12),
          // Style dropdown (compact)
          _buildCompactStyleDropdown(),
          const Spacer(),
          // A/B
          _buildCompactAB(),
          const SizedBox(width: 8),
          // Bypass
          _buildCompactBypass(),
        ],
      ),
    );
  }

  Widget _buildCompactStyleDropdown() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CompressionStyle>(
          value: _style,
          dropdownColor: FabFilterColors.bgDeep,
          style: FabFilterText.paramLabel.copyWith(fontSize: 10),
          icon: Icon(Icons.arrow_drop_down, size: 14, color: FabFilterColors.textMuted),
          isDense: true,
          items: CompressionStyle.values.map((s) => DropdownMenuItem(
            value: s,
            child: Text(s.label, style: const TextStyle(fontSize: 10)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _style = v);
              if (_slotIndex >= 0) {
                _ffi.insertSetParam(widget.trackId, _slotIndex, 7, _styleToTypeIndex(v).toDouble());
              }
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
        _buildMiniABButton('A', !isStateB, hasStoredA, () {
          if (isStateB) toggleAB();
        }, () {
          storeStateA();
          setState(() {});
        }),
        const SizedBox(width: 2),
        _buildMiniABButton('B', isStateB, hasStoredB, () {
          if (!isStateB) toggleAB();
        }, () {
          storeStateB();
          setState(() {});
        }),
        const SizedBox(width: 4),
        // Copy button
        Tooltip(
          message: isStateB ? 'Copy B → A' : 'Copy A → B',
          child: GestureDetector(
            onTap: copyCurrentToOther,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FabFilterColors.border),
              ),
              child: const Icon(
                Icons.content_copy,
                size: 10,
                color: FabFilterColors.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniABButton(
    String label,
    bool active,
    bool hasStored,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    return Tooltip(
      message: hasStored
          ? '$label: Stored (long-press to overwrite)'
          : '$label: Empty (long-press to store)',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: active ? widget.accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active ? widget.accentColor : FabFilterColors.border,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? widget.accentColor : FabFilterColors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Stored indicator dot
              if (hasStored)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: active
                          ? widget.accentColor
                          : FabFilterColors.textTertiary.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
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
          border: Border.all(
            color: bypassed ? FabFilterColors.orange : FabFilterColors.border,
          ),
        ),
        child: Text(
          'BYP',
          style: TextStyle(
            color: bypassed ? FabFilterColors.orange : FabFilterColors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDisplay() {
    return SizedBox(
      width: 140,
      child: Column(
        children: [
          // Transfer curve (knee display)
          Expanded(
            child: Container(
              decoration: FabFilterDecorations.display(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(
                  painter: _KneeCurvePainter(
                    threshold: _threshold,
                    ratio: _ratio,
                    knee: _knee,
                    currentInput: _currentInputLevel,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // GR meter (horizontal bar)
          _buildHorizontalGRMeter(),
        ],
      ),
    );
  }

  Widget _buildHorizontalGRMeter() {
    final grNorm = (_currentGainReduction.abs() / 40).clamp(0.0, 1.0);
    return Container(
      height: 18,
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Text('GR', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
          const SizedBox(width: 4),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: FabFilterColors.bgVoid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: grNorm,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [FabFilterColors.orange, FabFilterColors.red],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            child: Text(
              '${_currentGainReduction.toStringAsFixed(1)}',
              style: FabFilterText.paramValue(FabFilterColors.orange).copyWith(fontSize: 9),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactControls() {
    return Column(
      children: [
        // Row 1: Main compression knobs (smaller)
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSmallKnob(
                value: (_threshold + 60) / 60,
                label: 'THRESH',
                display: '${_threshold.toStringAsFixed(0)} dB',
                color: FabFilterColors.orange,
                onChanged: (v) {
                  setState(() => _threshold = v * 60 - 60);
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, 0, _threshold);
                  }
                },
              ),
              _buildSmallKnob(
                value: (_ratio - 1) / 19,
                label: 'RATIO',
                display: '${_ratio.toStringAsFixed(1)}:1',
                color: FabFilterColors.orange,
                onChanged: (v) {
                  setState(() => _ratio = v * 19 + 1);
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, 1, _ratio);
                  }
                },
              ),
              _buildSmallKnob(
                value: _knee / 24,
                label: 'KNEE',
                display: '${_knee.toStringAsFixed(0)} dB',
                color: FabFilterColors.blue,
                onChanged: (v) {
                  // NOTE: Knee is UI-only, not supported in insert chain compressor
                  setState(() => _knee = v * 24);
                },
              ),
              _buildSmallKnob(
                value: math.log(_attack / 0.01) / math.log(500 / 0.01),
                label: 'ATT',
                display: _attack < 1 ? '${(_attack * 1000).toStringAsFixed(0)}µ' : '${_attack.toStringAsFixed(0)}ms',
                color: FabFilterColors.cyan,
                onChanged: (v) {
                  setState(() => _attack = 0.01 * math.pow(500 / 0.01, v).toDouble());
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, 2, _attack);
                  }
                },
              ),
              _buildSmallKnob(
                value: math.log(_release / 5) / math.log(5000 / 5),
                label: 'REL',
                display: _release >= 1000 ? '${(_release / 1000).toStringAsFixed(1)}s' : '${_release.toStringAsFixed(0)}ms',
                color: FabFilterColors.cyan,
                onChanged: (v) {
                  setState(() => _release = 5 * math.pow(5000 / 5, v).toDouble());
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, 3, _release);
                  }
                },
              ),
              _buildSmallKnob(
                value: _mix / 100,
                label: 'MIX',
                display: '${_mix.toStringAsFixed(0)}%',
                color: FabFilterColors.blue,
                onChanged: (v) {
                  setState(() => _mix = v * 100);
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, 5, _mix / 100.0);
                  }
                },
              ),
              _buildSmallKnob(
                value: (_output + 24) / 48,
                label: 'OUT',
                display: '${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(0)}dB',
                color: FabFilterColors.green,
                onChanged: (v) {
                  setState(() => _output = v * 48 - 24);
                  if (_slotIndex >= 0) {
                    _ffi.insertSetParam(widget.trackId, _slotIndex, 4, _output);
                  }
                },
              ),
            ],
          ),
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
    return FabFilterKnob(
      value: value.clamp(0.0, 1.0),
      label: label,
      display: display,
      color: color,
      size: 48,
      onChanged: onChanged,
    );
  }

  Widget _buildCompactOptions() {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidechain toggle
          _buildOptionRow('SC', _sidechainEnabled, (v) => setState(() => _sidechainEnabled = v)),
          const SizedBox(height: 4),
          // Sidechain HP
          if (_sidechainEnabled) ...[
            _buildMiniSlider('HP', math.log(_sidechainHpf / 20) / math.log(500 / 20),
              '${_sidechainHpf.toStringAsFixed(0)}', (v) => setState(() => _sidechainHpf = 20 * math.pow(500 / 20, v).toDouble())),
            const SizedBox(height: 2),
            _buildMiniSlider('LP', math.log(_sidechainLpf / 1000) / math.log(20000 / 1000),
              '${(_sidechainLpf / 1000).toStringAsFixed(0)}k', (v) => setState(() => _sidechainLpf = 1000 * math.pow(20000 / 1000, v).toDouble())),
          ],
          const Flexible(child: SizedBox(height: 8)), // Flexible gap - can shrink to 0
          // Character
          if (showExpertMode) ...[
            Text('CHARACTER', style: FabFilterText.paramLabel.copyWith(fontSize: 8)),
            const SizedBox(height: 2),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              children: CharacterMode.values.map((m) => _buildTinyButton(
                m.label.substring(0, m == CharacterMode.off ? 3 : 1),
                _character == m,
                m.color,
                () => setState(() => _character = m),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionRow(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: value ? widget.accentColor.withValues(alpha: 0.15) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value ? widget.accentColor.withValues(alpha: 0.5) : FabFilterColors.border,
          ),
        ),
        child: Row(
          children: [
            Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 9)),
            const Spacer(),
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: value ? widget.accentColor : FabFilterColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniSlider(String label, double value, String display, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          SizedBox(width: 18, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: FabFilterColors.cyan,
                inactiveTrackColor: FabFilterColors.bgVoid,
                thumbColor: FabFilterColors.cyan,
              ),
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
          ),
          SizedBox(width: 24, child: Text(display, style: FabFilterText.paramLabel.copyWith(fontSize: 8), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildTinyButton(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 18,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : FabFilterColors.border),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: active ? color : FabFilterColors.textTertiary, fontSize: 8, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// LEVEL DISPLAY PAINTER (Scrolling waveform)
// ═══════════════════════════════════════════════════════════════════════════

class _LevelDisplayPainter extends CustomPainter {
  final List<LevelSample> history;
  final double threshold;

  _LevelDisplayPainter({
    required this.history,
    required this.threshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final rect = Offset.zero & size;

    // Background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          FabFilterColors.bgVoid,
          FabFilterColors.bgDeep,
        ],
      );
    canvas.drawRect(rect, bgPaint);

    // Grid lines
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    // Horizontal grid (dB levels)
    for (var db = -60; db <= 0; db += 12) {
      final y = size.height * (1 - (db + 60) / 60);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Threshold line
    final thresholdY = size.height * (1 - (threshold + 60) / 60);
    final thresholdPaint = Paint()
      ..color = FabFilterColors.orange
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );

    // Draw level history
    if (history.length < 2) return;

    final sampleWidth = size.width / history.length;

    // Input level (gray)
    final inputPath = Path();
    final inputPaint = Paint()
      ..color = FabFilterColors.textMuted.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final level = history[i].input;
      final normalizedLevel = ((level + 60) / 60).clamp(0.0, 1.0);
      final barHeight = size.height * normalizedLevel;

      if (i == 0) {
        inputPath.moveTo(x, size.height);
      }
      inputPath.lineTo(x, size.height - barHeight);
    }
    inputPath.lineTo(size.width, size.height);
    inputPath.close();
    canvas.drawPath(inputPath, inputPaint);

    // Output level (blue)
    final outputPath = Path();
    final outputPaint = Paint()
      ..color = FabFilterColors.blue.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final level = history[i].output;
      final normalizedLevel = ((level + 60) / 60).clamp(0.0, 1.0);
      final barHeight = size.height * normalizedLevel;

      if (i == 0) {
        outputPath.moveTo(x, size.height);
      }
      outputPath.lineTo(x, size.height - barHeight);
    }
    outputPath.lineTo(size.width, size.height);
    outputPath.close();
    canvas.drawPath(outputPath, outputPaint);

    // Gain reduction overlay (red, from top)
    final grPaint = Paint()
      ..color = FabFilterColors.red.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final gr = history[i].gainReduction.abs();
      final grHeight = size.height * (gr / 40).clamp(0.0, 1.0);

      canvas.drawRect(
        Rect.fromLTWH(x, 0, sampleWidth + 1, grHeight),
        grPaint,
      );
    }

    // Labels
    final labelPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Threshold label
    labelPainter.text = TextSpan(
      text: '${threshold.toStringAsFixed(0)} dB',
      style: TextStyle(
        color: FabFilterColors.orange,
        fontSize: 9,
      ),
    );
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(4, thresholdY - 12));
  }

  @override
  bool shouldRepaint(covariant _LevelDisplayPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// KNEE CURVE PAINTER (Transfer function)
// ═══════════════════════════════════════════════════════════════════════════

class _KneeCurvePainter extends CustomPainter {
  final double threshold;
  final double ratio;
  final double knee;
  final double currentInput;

  _KneeCurvePainter({
    required this.threshold,
    required this.ratio,
    required this.knee,
    required this.currentInput,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
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

    // Diagonal 1:1 line
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      gridPaint,
    );

    // Grid squares
    final gridSize = size.width / 4;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(i * gridSize, 0),
        Offset(i * gridSize, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, i * gridSize),
        Offset(size.width, i * gridSize),
        gridPaint,
      );
    }

    // Draw compression curve
    final curvePaint = Paint()
      ..color = FabFilterColors.orange
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final curvePath = Path();

    // Input range: -60 to 0 dB
    // Output range: -60 to 0 dB
    const minDb = -60.0;
    const maxDb = 0.0;
    const dbRange = maxDb - minDb;

    for (var i = 0; i <= size.width; i++) {
      final inputDb = minDb + (i / size.width) * dbRange;
      double outputDb;

      // Calculate output with knee
      final halfKnee = knee / 2;
      final kneeStart = threshold - halfKnee;
      final kneeEnd = threshold + halfKnee;

      if (inputDb < kneeStart) {
        // Below knee - 1:1 ratio
        outputDb = inputDb;
      } else if (inputDb > kneeEnd) {
        // Above knee - full compression
        outputDb = threshold + (inputDb - threshold) / ratio;
      } else {
        // In knee region - smooth transition
        final kneePosition = (inputDb - kneeStart) / knee;
        final compressionAmount =
            1 + (1 / ratio - 1) * kneePosition * kneePosition;
        outputDb =
            kneeStart + (inputDb - kneeStart) * (1 + compressionAmount) / 2;
      }

      // Convert to screen coordinates
      final x = i.toDouble();
      final y = size.height * (1 - (outputDb - minDb) / dbRange);

      if (i == 0) {
        curvePath.moveTo(x, y);
      } else {
        curvePath.lineTo(x, y);
      }
    }

    canvas.drawPath(curvePath, curvePaint);

    // Current input indicator (animated dot)
    if (currentInput > minDb) {
      final inputX = size.width * ((currentInput - minDb) / dbRange);

      // Calculate output for current input
      double outputDb;
      final halfKnee = knee / 2;
      final kneeStart = threshold - halfKnee;
      final kneeEnd = threshold + halfKnee;

      if (currentInput < kneeStart) {
        outputDb = currentInput;
      } else if (currentInput > kneeEnd) {
        outputDb = threshold + (currentInput - threshold) / ratio;
      } else {
        final kneePosition = (currentInput - kneeStart) / knee;
        final compressionAmount =
            1 + (1 / ratio - 1) * kneePosition * kneePosition;
        outputDb =
            kneeStart + (currentInput - kneeStart) * (1 + compressionAmount) / 2;
      }

      final outputY = size.height * (1 - (outputDb - minDb) / dbRange);

      // Draw indicator
      final dotPaint = Paint()
        ..color = FabFilterColors.yellow
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(inputX, outputY), 5, dotPaint);

      // Draw lines to axes
      final linePaint = Paint()
        ..color = FabFilterColors.yellow.withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(inputX, outputY),
        Offset(inputX, size.height),
        linePaint,
      );
      canvas.drawLine(
        Offset(inputX, outputY),
        Offset(0, outputY),
        linePaint,
      );
    }

    // Threshold marker
    final thresholdX = size.width * ((threshold - minDb) / dbRange);
    final thresholdPaint = Paint()
      ..color = FabFilterColors.orange.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(thresholdX, 0),
      Offset(thresholdX, size.height),
      thresholdPaint,
    );

    // Labels
    _drawLabel(canvas, 'IN', Offset(size.width - 16, size.height - 12));
    _drawLabel(canvas, 'OUT', Offset(4, 4));
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
  bool shouldRepaint(covariant _KneeCurvePainter oldDelegate) =>
      oldDelegate.threshold != threshold ||
      oldDelegate.ratio != ratio ||
      oldDelegate.knee != knee ||
      oldDelegate.currentInput != currentInput;
}

// ═══════════════════════════════════════════════════════════════════════════
// SIDECHAIN EQ PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _SidechainEqPainter extends CustomPainter {
  final List<SidechainBand> bands;
  final double hpf;
  final double lpf;

  _SidechainEqPainter({
    required this.bands,
    required this.hpf,
    required this.lpf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRect(
      rect,
      Paint()..color = FabFilterColors.bgVoid,
    );

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    // Frequency grid (log scale)
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

    // HPF/LPF shading
    final filterPaint = Paint()
      ..color = FabFilterColors.cyan.withValues(alpha: 0.1);

    // HPF shade (left side)
    final hpfX = _freqToX(hpf, size.width);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, hpfX, size.height),
      filterPaint,
    );

    // LPF shade (right side)
    final lpfX = _freqToX(lpf, size.width);
    canvas.drawRect(
      Rect.fromLTRB(lpfX, 0, size.width, size.height),
      filterPaint,
    );

    // HPF/LPF lines
    final filterLinePaint = Paint()
      ..color = FabFilterColors.cyan
      ..strokeWidth = 1.5;

    canvas.drawLine(Offset(hpfX, 0), Offset(hpfX, size.height), filterLinePaint);
    canvas.drawLine(Offset(lpfX, 0), Offset(lpfX, size.height), filterLinePaint);

    // Draw EQ curve (simplified)
    final curvePaint = Paint()
      ..color = FabFilterColors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final curvePath = Path();
    curvePath.moveTo(0, size.height / 2);

    // Build approximate curve through bands
    for (var i = 0; i < size.width; i += 2) {
      final freq = _xToFreq(i.toDouble(), size.width);
      var totalGain = 0.0;

      for (final band in bands) {
        if (!band.enabled) continue;

        // Simple bell response approximation
        final octaves = (math.log(freq / band.freq) / math.ln2).abs();
        final response = band.gain * math.exp(-octaves * octaves * band.q);
        totalGain += response;
      }

      final y = size.height / 2 - (totalGain / 24) * (size.height / 2);
      curvePath.lineTo(i.toDouble(), y.clamp(0, size.height));
    }

    canvas.drawPath(curvePath, curvePaint);

    // Draw band markers
    final markerPaint = Paint()
      ..color = FabFilterColors.blue
      ..style = PaintingStyle.fill;

    for (final band in bands) {
      if (!band.enabled) continue;

      final x = _freqToX(band.freq, size.width);
      final y = size.height / 2 - (band.gain / 24) * (size.height / 2);

      canvas.drawCircle(
        Offset(x, y.clamp(4, size.height - 4)),
        4,
        markerPaint,
      );
    }
  }

  double _freqToX(double freq, double width) {
    // Log scale: 20Hz to 20kHz
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
  bool shouldRepaint(covariant _SidechainEqPainter oldDelegate) => true;
}
