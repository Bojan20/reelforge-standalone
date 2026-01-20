/// FabFilter Pro-C Style Compressor Panel
///
/// Inspired by Pro-C 3's interface:
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
import 'fabfilter_theme.dart';
import 'fabfilter_knob.dart';
import 'fabfilter_panel_base.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Compression style (Pro-C 3 has 14 styles)
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

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterCompressorPanel extends FabFilterPanelBase {
  const FabFilterCompressorPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'Compressor',
          icon: Icons.compress,
          accentColor: FabFilterColors.orange,
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
  double _knee = 12.0; // dB
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

  // Host sync
  bool _hostSync = false;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

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

  void _initializeProcessor() {
    final success = _ffi.compressorCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      _initialized = true;
      _applyAllParameters();
    }
  }

  void _applyAllParameters() {
    if (!_initialized) return;
    _ffi.compressorSetThreshold(widget.trackId, _threshold);
    _ffi.compressorSetRatio(widget.trackId, _ratio);
    _ffi.compressorSetKnee(widget.trackId, _knee);
    _ffi.compressorSetAttack(widget.trackId, _attack);
    _ffi.compressorSetRelease(widget.trackId, _release);
    _ffi.compressorSetMakeup(widget.trackId, _output);
    _ffi.compressorSetMix(widget.trackId, _mix / 100.0);
    // Map style to CompressorType
    _ffi.compressorSetType(widget.trackId, _styleToCompressorType(_style));
  }

  CompressorType _styleToCompressorType(CompressionStyle style) {
    // Map FabFilter styles to engine CompressorType (vca, opto, fet)
    return switch (style) {
      CompressionStyle.clean => CompressorType.vca,      // Transparent
      CompressionStyle.classic => CompressorType.vca,    // Classic VCA
      CompressionStyle.opto => CompressorType.opto,      // Optical
      CompressionStyle.vocal => CompressorType.opto,     // Smooth for vocals
      CompressionStyle.mastering => CompressorType.vca,  // Clean mastering
      CompressionStyle.bus => CompressorType.vca,        // Glue
      CompressionStyle.punch => CompressorType.fet,      // Punchy FET
      CompressionStyle.pumping => CompressorType.fet,    // Aggressive
      CompressionStyle.versatile => CompressorType.vca,  // General
      CompressionStyle.smooth => CompressorType.opto,    // Smooth optical
      CompressionStyle.upward => CompressorType.vca,     // Upward
      CompressionStyle.ttm => CompressorType.fet,        // Aggressive multiband
      CompressionStyle.variMu => CompressorType.opto,    // Tube-like (use opto)
      CompressionStyle.elOp => CompressorType.opto,      // Optical
    };
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    if (_initialized) {
      _ffi.compressorRemove(widget.trackId);
    }
    super.dispose();
  }

  void _updateMeters() {
    setState(() {
      // Get real gain reduction from FFI
      if (_initialized) {
        _currentGainReduction = _ffi.compressorGetGainReduction(widget.trackId);
      }

      // Simulate input level (would come from metering FFI in real impl)
      _currentInputLevel = -20 + (math.Random().nextDouble() - 0.5) * 10;

      // Output level
      _currentOutputLevel = _currentInputLevel + _currentGainReduction + _output;

      // Track peak GR
      if (_currentGainReduction.abs() > _peakGainReduction.abs()) {
        _peakGainReduction = _currentGainReduction;
      }

      // Add to history
      _levelHistory.add(LevelSample(
        input: _currentInputLevel,
        output: _currentOutputLevel,
        gainReduction: _currentGainReduction,
        timestamp: DateTime.now(),
      ));

      // Trim history
      while (_levelHistory.length > _maxHistorySamples) {
        _levelHistory.removeAt(0);
      }
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

                  // Style & options
                  _buildStyleSection(),
                  const SizedBox(height: 16),

                  // Sidechain
                  _buildSidechainSection(),

                  // Character (expert mode)
                  if (showExpertMode) ...[
                    const SizedBox(height: 16),
                    _buildCharacterSection(),
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
    return Row(
      children: [
        // Level display (scrolling waveform)
        Expanded(
          flex: 3,
          child: Container(
            height: 140,
            decoration: FabFilterDecorations.display(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _LevelDisplayPainter(
                  history: _levelHistory,
                  threshold: _threshold,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Knee/transfer curve display
        Expanded(
          flex: 2,
          child: Container(
            height: 140,
            decoration: FabFilterDecorations.display(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
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

        const SizedBox(width: 16),

        // Gain reduction meter
        SizedBox(
          width: 40,
          height: 140,
          child: _buildGainReductionMeter(),
        ),
      ],
    );
  }

  Widget _buildGainReductionMeter() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Text(
            'GR',
            style: FabFilterTextStyles.label,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // GR goes from 0 to -40 dB
                final grNormalized =
                    (_currentGainReduction.abs() / 40).clamp(0.0, 1.0);
                final peakNormalized =
                    (_peakGainReduction.abs() / 40).clamp(0.0, 1.0);

                return Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Background
                    Container(
                      width: 20,
                      decoration: BoxDecoration(
                        color: FabFilterColors.bgVoid,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // GR bar
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 50),
                      width: 20,
                      height: constraints.maxHeight * grNormalized,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            FabFilterColors.red,
                            FabFilterColors.orange,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Peak indicator
                    Positioned(
                      bottom: constraints.maxHeight * peakNormalized - 2,
                      child: Container(
                        width: 24,
                        height: 3,
                        color: FabFilterColors.yellow,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_currentGainReduction.toStringAsFixed(1)}',
            style: FabFilterTextStyles.value.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN CONTROLS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMainControls() {
    return buildSection(
      'DYNAMICS',
      Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          // Threshold
          FabFilterKnob(
            value: (_threshold + 60) / 60, // Normalize -60 to 0
            label: 'THRESHOLD',
            display: '${_threshold.toStringAsFixed(1)} dB',
            color: FabFilterColors.orange,
            modulation: _autoThreshold ? 0.2 : null,
            onChanged: (v) {
              setState(() => _threshold = v * 60 - 60);
              _ffi.compressorSetThreshold(widget.trackId, _threshold);
            },
          ),

          // Ratio
          FabFilterKnob(
            value: (_ratio - 1) / 19, // Normalize 1:1 to 20:1
            label: 'RATIO',
            display: '${_ratio.toStringAsFixed(1)}:1',
            color: FabFilterColors.orange,
            onChanged: (v) {
              setState(() => _ratio = v * 19 + 1);
              _ffi.compressorSetRatio(widget.trackId, _ratio);
            },
          ),

          // Knee
          FabFilterKnob(
            value: _knee / 24, // Normalize 0 to 24 dB
            label: 'KNEE',
            display: '${_knee.toStringAsFixed(1)} dB',
            color: FabFilterColors.blue,
            onChanged: (v) {
              setState(() => _knee = v * 24);
              _ffi.compressorSetKnee(widget.trackId, _knee);
            },
          ),

          // Attack
          FabFilterKnob(
            value: math.log(_attack / 0.01) / math.log(500 / 0.01),
            label: 'ATTACK',
            display: _attack < 1
                ? '${(_attack * 1000).toStringAsFixed(0)} µs'
                : '${_attack.toStringAsFixed(1)} ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _attack = 0.01 * math.pow(500 / 0.01, v).toDouble());
              _ffi.compressorSetAttack(widget.trackId, _attack);
            },
          ),

          // Release
          FabFilterKnob(
            value: math.log(_release / 5) / math.log(5000 / 5),
            label: 'RELEASE',
            display: _release >= 1000
                ? '${(_release / 1000).toStringAsFixed(2)} s'
                : '${_release.toStringAsFixed(0)} ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _release = 5 * math.pow(5000 / 5, v).toDouble());
              _ffi.compressorSetRelease(widget.trackId, _release);
            },
          ),

          // Range
          if (showExpertMode)
            FabFilterKnob(
              value: (_range + 60) / 60,
              label: 'RANGE',
              display: '${_range.toStringAsFixed(0)} dB',
              color: FabFilterColors.purple,
              onChanged: (v) => setState(() => _range = v * 60 - 60),
            ),

          // Mix
          FabFilterKnob(
            value: _mix / 100,
            label: 'MIX',
            display: '${_mix.toStringAsFixed(0)}%',
            color: FabFilterColors.blue,
            onChanged: (v) {
              setState(() => _mix = v * 100);
              _ffi.compressorSetMix(widget.trackId, _mix / 100.0);
            },
          ),

          // Output
          FabFilterKnob(
            value: (_output + 24) / 48, // Normalize -24 to +24
            label: 'OUTPUT',
            display: '${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(1)} dB',
            color: FabFilterColors.green,
            onChanged: (v) {
              setState(() => _output = v * 48 - 24);
              _ffi.compressorSetMakeup(widget.trackId, _output);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STYLE SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStyleSection() {
    return buildSection(
      'STYLE',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Style dropdown
          Row(
            children: [
              Expanded(
                child: _buildStyleDropdown(),
              ),
              const SizedBox(width: 16),
              // Compact view toggle
              buildToggle(
                'Compact',
                _compactView,
                (v) => setState(() => _compactView = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Style description
          Text(
            _style.description,
            style: FabFilterTextStyles.label.copyWith(
              color: FabFilterColors.textMuted,
            ),
          ),

          if (showExpertMode) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                buildToggle(
                  'Auto Threshold',
                  _autoThreshold,
                  (v) => setState(() => _autoThreshold = v),
                ),
                const SizedBox(width: 24),
                buildToggle(
                  'Host Sync',
                  _hostSync,
                  (v) => setState(() => _hostSync = v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStyleDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CompressionStyle>(
          value: _style,
          isExpanded: true,
          dropdownColor: FabFilterColors.bgDeep,
          style: FabFilterTextStyles.value,
          icon: Icon(
            Icons.arrow_drop_down,
            color: FabFilterColors.textMuted,
          ),
          items: CompressionStyle.values.map((style) {
            final isNew = style.label.contains('NEW') ||
                [
                  CompressionStyle.versatile,
                  CompressionStyle.smooth,
                  CompressionStyle.upward,
                  CompressionStyle.ttm,
                  CompressionStyle.variMu,
                  CompressionStyle.elOp,
                ].contains(style);

            return DropdownMenuItem(
              value: style,
              child: Row(
                children: [
                  Text(style.label),
                  if (isNew) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: FabFilterColors.orange.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 8,
                          color: FabFilterColors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _style = v);
              _ffi.compressorSetType(widget.trackId, _styleToCompressorType(v));
            }
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SIDECHAIN SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSidechainSection() {
    return buildSection(
      'SIDECHAIN',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildToggle(
                'Enable',
                _sidechainEnabled,
                (v) => setState(() => _sidechainEnabled = v),
              ),
              const SizedBox(width: 24),

              // HPF
              Expanded(
                child: _buildSimpleSlider(
                  'HP',
                  math.log(_sidechainHpf / 20) / math.log(500 / 20),
                  '${_sidechainHpf.toStringAsFixed(0)} Hz',
                  FabFilterColors.cyan,
                  _sidechainEnabled
                      ? (v) => setState(
                          () => _sidechainHpf = 20 * math.pow(500 / 20, v).toDouble())
                      : null,
                ),
              ),
              const SizedBox(width: 16),

              // LPF
              Expanded(
                child: _buildSimpleSlider(
                  'LP',
                  math.log(_sidechainLpf / 1000) / math.log(20000 / 1000),
                  _sidechainLpf >= 1000
                      ? '${(_sidechainLpf / 1000).toStringAsFixed(1)}k'
                      : '${_sidechainLpf.toStringAsFixed(0)} Hz',
                  FabFilterColors.cyan,
                  _sidechainEnabled
                      ? (v) => setState(() =>
                          _sidechainLpf = 1000 * math.pow(20000 / 1000, v).toDouble())
                      : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              // EQ button
              _buildTextButton(
                'EQ...',
                _sidechainEqVisible,
                () => setState(() => _sidechainEqVisible = !_sidechainEqVisible),
              ),
              const SizedBox(width: 16),

              // Audition
              buildToggle(
                'Audition',
                _sidechainAudition,
                (v) => setState(() => _sidechainAudition = v),
              ),
            ],
          ),

          // Sidechain EQ (expandable)
          if (_sidechainEqVisible && _sidechainEnabled) ...[
            const SizedBox(height: 12),
            _buildSidechainEq(),
          ],
        ],
      ),
    );
  }

  Widget _buildTextButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? FabFilterColors.blue.withValues(alpha: 0.3)
              : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? FabFilterColors.blue : FabFilterColors.border,
          ),
        ),
        child: Text(
          label,
          style: FabFilterTextStyles.label.copyWith(
            color: active ? FabFilterColors.blue : FabFilterColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSidechainEq() {
    return Container(
      height: 120,
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        painter: _SidechainEqPainter(
          bands: _sidechainBands,
          hpf: _sidechainHpf,
          lpf: _sidechainLpf,
        ),
        size: Size.infinite,
      ),
    );
  }

  /// Simple slider helper (normalized 0-1 value)
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
          width: 30,
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
          width: 60,
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
  // CHARACTER SECTION (Expert Mode)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCharacterSection() {
    return buildSection(
      'CHARACTER',
      Row(
        children: [
          // Character mode buttons
          ...CharacterMode.values.map((mode) {
            final isSelected = _character == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _character = mode),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: isSelected
                      ? FabFilterDecorations.toggleActive(mode.color)
                      : FabFilterDecorations.toggle(),
                  child: Text(
                    mode.label,
                    style: FabFilterTextStyles.label.copyWith(
                      color:
                          isSelected ? mode.color : FabFilterColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),

          const Spacer(),

          // Drive (only if character != off)
          if (_character != CharacterMode.off)
            SizedBox(
              width: 200,
              child: _buildSimpleSlider(
                'Drive',
                (_drive + 6) / 18, // -6 to +12
                '${_drive >= 0 ? '+' : ''}${_drive.toStringAsFixed(1)} dB',
                _character.color,
                (v) => setState(() => _drive = v * 18 - 6),
              ),
            ),
        ],
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
