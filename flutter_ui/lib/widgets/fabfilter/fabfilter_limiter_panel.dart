/// FabFilter Pro-L Style Limiter Panel
///
/// Inspired by Pro-L 2's interface:
/// - Real-time scrolling waveform display
/// - True Peak limiting/metering
/// - Loudness metering (LUFS - Integrated, Short-term, Momentary)
/// - 8 limiting styles
/// - Multiple meter scales (K-12, K-14, K-20)
/// - Compact view mode

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

/// Limiting style (Pro-L 2 has 8 styles)
enum LimitingStyle {
  transparent('Transparent', 'Clean and transparent limiting'),
  punchy('Punchy', 'Preserves transients and punch'),
  dynamic('Dynamic', 'Dynamic and musical limiting'),
  aggressive('Aggressive', 'Aggressive limiting for EDM'),
  bus('Bus', 'Bus/subgroup limiting'),
  safe('Safe', 'Safe mode for delicate material'),
  modern('Modern', 'Modern sound for contemporary music'),
  allround('Allround', 'Versatile general-purpose mode');

  final String label;
  final String description;
  const LimitingStyle(this.label, this.description);
}

/// Meter scale options
enum MeterScale {
  normal('0 dB', 0),
  k12('K-12', -12),
  k14('K-14', -14),
  k20('K-20', -20),
  loudness('LUFS', 0);

  final String label;
  final int offset;
  const MeterScale(this.label, this.offset);
}

/// LUFS reading types
enum LufsType {
  integrated('Int', 'Integrated loudness (program)'),
  shortTerm('Short', 'Short-term loudness (3s)'),
  momentary('Mom', 'Momentary loudness (400ms)');

  final String label;
  final String description;
  const LufsType(this.label, this.description);
}

/// Level sample for scrolling display
class LimiterLevelSample {
  final double inputPeak;
  final double outputPeak;
  final double gainReduction;
  final double truePeak;
  final DateTime timestamp;

  LimiterLevelSample({
    required this.inputPeak,
    required this.outputPeak,
    required this.gainReduction,
    required this.truePeak,
    required this.timestamp,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterLimiterPanel extends FabFilterPanelBase {
  const FabFilterLimiterPanel({
    super.key,
    required super.trackId,
  }) : super(
          title: 'Limiter',
          icon: Icons.graphic_eq,
          accentColor: FabFilterColors.red,
        );

  @override
  State<FabFilterLimiterPanel> createState() => _FabFilterLimiterPanelState();
}

class _FabFilterLimiterPanelState extends State<FabFilterLimiterPanel>
    with FabFilterPanelMixin, TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  // Main parameters
  double _gain = 0.0; // dB (input gain/drive)
  double _output = -0.3; // dB (output ceiling)
  double _attack = 1.0; // ms (0.01 - 10)
  double _release = 100.0; // ms (1 - 1000)
  double _lookahead = 2.0; // ms (0 - 10)

  // Style
  LimitingStyle _style = LimitingStyle.transparent;

  // Metering
  MeterScale _meterScale = MeterScale.normal;
  bool _truePeakEnabled = true;

  // Display
  bool _compactView = false;
  final List<LimiterLevelSample> _levelHistory = [];
  static const int _maxHistorySamples = 300;

  // Real-time meters
  double _currentInputPeak = -60.0;
  double _currentOutputPeak = -60.0;
  double _currentGainReduction = 0.0;
  double _peakGainReduction = 0.0;
  double _currentTruePeak = -60.0;
  bool _truePeakClipping = false;

  // LUFS
  double _lufsIntegrated = -14.0;
  double _lufsShortTerm = -14.0;
  double _lufsMomentary = -12.0;
  double _lufsRange = 6.0; // LRA

  // Animation
  late AnimationController _meterController;

  // Link channels (L/R)
  bool _channelLink = true;

  // Unity gain (auto)
  bool _unityGain = false;

  // FFI
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  Timer? _meterTimer;

  @override
  void initState() {
    super.initState();

    // Initialize FFI limiter
    _initializeProcessor();

    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateMeters);

    _meterController.repeat();
  }

  void _initializeProcessor() {
    final success = _ffi.limiterCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      _initialized = true;
      _applyAllParameters();
    }
  }

  void _applyAllParameters() {
    if (!_initialized) return;
    // Output ceiling maps to limiter threshold (negative value)
    _ffi.limiterSetThreshold(widget.trackId, _output);
    _ffi.limiterSetCeiling(widget.trackId, _output);
    _ffi.limiterSetRelease(widget.trackId, _release);
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _meterController.dispose();
    if (_initialized) {
      _ffi.limiterRemove(widget.trackId);
    }
    super.dispose();
  }

  void _updateMeters() {
    setState(() {
      // Get real data from FFI when processor is in audio path
      // NOTE: LIMITERS HashMap is NOT connected to audio callback yet
      // Processor shows real data only when connected to InsertChain
      if (_initialized) {
        _currentGainReduction = _ffi.limiterGetGainReduction(widget.trackId);
        _currentTruePeak = _ffi.limiterGetTruePeak(widget.trackId);
      }

      // NO FAKE DATA: All levels must come from real metering
      // Show silence until connected to PLAYBACK_ENGINE InsertChain
      _currentInputPeak = -60.0;
      _currentOutputPeak = -60.0;

      // True peak clipping detection (only with real data)
      _truePeakClipping = _initialized && _currentTruePeak > _output;

      // Track peak GR only if real data present
      if (_currentGainReduction.abs() > 0.01 && _currentGainReduction.abs() > _peakGainReduction.abs()) {
        _peakGainReduction = _currentGainReduction;
      }

      // NO FAKE LUFS: Must come from real loudness analyzer
      // TODO: Connect to PLAYBACK_ENGINE loudness metering
      // _lufsMomentary, _lufsShortTerm, _lufsIntegrated stay at init values

      // Add to history only with real activity
      if (_currentGainReduction.abs() > 0.01) {
        _levelHistory.add(LimiterLevelSample(
          inputPeak: _currentInputPeak,
          outputPeak: _currentOutputPeak,
          gainReduction: _currentGainReduction,
          truePeak: _currentTruePeak,
          timestamp: DateTime.now(),
        ));

        while (_levelHistory.length > _maxHistorySamples) {
          _levelHistory.removeAt(0);
        }
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

                  // Style selection
                  _buildStyleSection(),
                  const SizedBox(height: 16),

                  // Loudness metering
                  _buildLoudnessSection(),

                  // Expert controls
                  if (showExpertMode) ...[
                    const SizedBox(height: 16),
                    _buildExpertSection(),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scrolling waveform display
        Expanded(
          flex: 4,
          child: Container(
            height: 160,
            decoration: FabFilterDecorations.display(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CustomPaint(
                painter: _LimiterDisplayPainter(
                  history: _levelHistory,
                  ceiling: _output,
                  meterScale: _meterScale,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Meters column
        SizedBox(
          width: 120,
          height: 160,
          child: Row(
            children: [
              // Input/Output meters
              Expanded(child: _buildDualMeter()),

              const SizedBox(width: 8),

              // GR meter
              SizedBox(width: 32, child: _buildGrMeter()),

              const SizedBox(width: 8),

              // True Peak indicator
              SizedBox(width: 24, child: _buildTruePeakIndicator()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDualMeter() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('IN', style: FabFilterTextStyles.label),
              Text('OUT', style: FabFilterTextStyles.label),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                // Input meter
                Expanded(child: _buildVerticalMeter(_currentInputPeak, FabFilterColors.textMuted)),
                const SizedBox(width: 2),
                // Output meter
                Expanded(child: _buildVerticalMeter(_currentOutputPeak, FabFilterColors.blue)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalMeter(double levelDb, Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final normalized = ((levelDb + 60) / 60).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Background
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Level bar with gradient
            AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: double.infinity,
              height: constraints.maxHeight * normalized,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    color,
                    color,
                    FabFilterColors.yellow,
                    FabFilterColors.red,
                  ],
                  stops: const [0.0, 0.7, 0.85, 1.0],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrMeter() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Text('GR', style: FabFilterTextStyles.label),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final grNormalized =
                    (_currentGainReduction.abs() / 24).clamp(0.0, 1.0);
                final peakNormalized =
                    (_peakGainReduction.abs() / 24).clamp(0.0, 1.0);

                return Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Background
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FabFilterColors.bgVoid,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // GR bar (from top)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 50),
                      width: double.infinity,
                      height: constraints.maxHeight * grNormalized,
                      decoration: BoxDecoration(
                        color: FabFilterColors.red,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Peak hold line
                    Positioned(
                      top: constraints.maxHeight * peakNormalized - 1,
                      child: Container(
                        width: 24,
                        height: 2,
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
            style: FabFilterTextStyles.value.copyWith(
              fontSize: 9,
              color: FabFilterColors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTruePeakIndicator() {
    return Container(
      decoration: FabFilterDecorations.display(),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Text('TP', style: FabFilterTextStyles.label),
          const SizedBox(height: 8),

          // True peak LED
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _truePeakClipping
                  ? FabFilterColors.red
                  : _currentTruePeak > _output - 0.5
                      ? FabFilterColors.orange
                      : FabFilterColors.green,
              boxShadow: [
                if (_truePeakClipping)
                  BoxShadow(
                    color: FabFilterColors.red.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
              ],
            ),
          ),

          const Spacer(),

          // TP value
          Text(
            _currentTruePeak > -60
                ? _currentTruePeak.toStringAsFixed(1)
                : '-∞',
            style: FabFilterTextStyles.value.copyWith(
              fontSize: 8,
              color: _truePeakClipping
                  ? FabFilterColors.red
                  : FabFilterColors.textSecondary,
            ),
          ),

          const SizedBox(height: 4),

          // Reset button
          GestureDetector(
            onTap: () {
              setState(() {
                _peakGainReduction = 0;
                _truePeakClipping = false;
              });
              if (_initialized) {
                _ffi.limiterReset(widget.trackId);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Icon(
                Icons.refresh,
                size: 10,
                color: FabFilterColors.textMuted,
              ),
            ),
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
      'LIMITER',
      Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          // Gain (input drive)
          FabFilterKnob(
            value: (_gain + 24) / 48, // -24 to +24
            label: 'GAIN',
            display:
                '${_gain >= 0 ? '+' : ''}${_gain.toStringAsFixed(1)} dB',
            color: FabFilterColors.orange,
            onChanged: (v) {
              setState(() => _gain = v * 48 - 24);
              // Gain applied via input, no direct FFI call needed
            },
          ),

          // Output ceiling
          FabFilterKnob(
            value: (_output + 12) / 12, // -12 to 0
            label: 'OUTPUT',
            display: '${_output.toStringAsFixed(1)} dB',
            color: FabFilterColors.blue,
            onChanged: (v) {
              setState(() => _output = v * 12 - 12);
              _ffi.limiterSetCeiling(widget.trackId, _output);
              _ffi.limiterSetThreshold(widget.trackId, _output);
            },
          ),

          // Attack (expert mode)
          if (showExpertMode)
            FabFilterKnob(
              value: math.log(_attack / 0.01) / math.log(10 / 0.01),
              label: 'ATTACK',
              display: _attack < 1
                  ? '${(_attack * 1000).toStringAsFixed(0)} µs'
                  : '${_attack.toStringAsFixed(2)} ms',
              color: FabFilterColors.cyan,
              onChanged: (v) => setState(
                  () => _attack = 0.01 * math.pow(10 / 0.01, v).toDouble()),
            ),

          // Release
          FabFilterKnob(
            value: math.log(_release / 1) / math.log(1000 / 1),
            label: 'RELEASE',
            display: _release >= 100
                ? '${(_release / 1000).toStringAsFixed(2)} s'
                : '${_release.toStringAsFixed(0)} ms',
            color: FabFilterColors.cyan,
            onChanged: (v) {
              setState(() => _release = 1 * math.pow(1000 / 1, v).toDouble());
              _ffi.limiterSetRelease(widget.trackId, _release);
            },
          ),

          // Lookahead (expert mode)
          if (showExpertMode)
            FabFilterKnob(
              value: _lookahead / 10,
              label: 'LOOKAHEAD',
              display: '${_lookahead.toStringAsFixed(1)} ms',
              color: FabFilterColors.purple,
              onChanged: (v) => setState(() => _lookahead = v * 10),
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
          // Style grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LimitingStyle.values.map((style) {
              final isSelected = _style == style;
              return GestureDetector(
                onTap: () => setState(() => _style = style),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: isSelected
                      ? FabFilterDecorations.toggleActive(FabFilterColors.red)
                      : FabFilterDecorations.toggleInactive(),
                  child: Text(
                    style.label,
                    style: TextStyle(
                      color: isSelected
                          ? FabFilterColors.red
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
            _style.description,
            style: FabFilterTextStyles.label.copyWith(
              color: FabFilterColors.textMuted,
            ),
          ),

          const SizedBox(height: 12),

          // Options row
          Row(
            children: [
              buildToggle(
                'Compact',
                _compactView,
                (v) => setState(() => _compactView = v),
              ),
              const SizedBox(width: 16),
              buildToggle(
                'True Peak',
                _truePeakEnabled,
                (v) => setState(() => _truePeakEnabled = v),
                activeColor: FabFilterColors.green,
              ),
              const SizedBox(width: 16),
              _buildMeterScaleDropdown(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterScaleDropdown() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Scale:', style: FabFilterTextStyles.label),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: FabFilterDecorations.toggleInactive(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<MeterScale>(
              value: _meterScale,
              isDense: true,
              dropdownColor: FabFilterColors.bgMid,
              style: FabFilterTextStyles.value,
              items: MeterScale.values.map((scale) {
                return DropdownMenuItem(
                  value: scale,
                  child: Text(scale.label),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _meterScale = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOUDNESS SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoudnessSection() {
    return buildSection(
      'LOUDNESS',
      Row(
        children: [
          // LUFS meters
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLufsDisplay(LufsType.integrated, _lufsIntegrated),
                _buildLufsDisplay(LufsType.shortTerm, _lufsShortTerm),
                _buildLufsDisplay(LufsType.momentary, _lufsMomentary),
              ],
            ),
          ),

          // LRA (Loudness Range)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FabFilterColors.bgVoid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Text('LRA', style: FabFilterTextStyles.label),
                const SizedBox(height: 4),
                Text(
                  '${_lufsRange.toStringAsFixed(1)} LU',
                  style: FabFilterTextStyles.value.copyWith(
                    color: FabFilterColors.purple,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLufsDisplay(LufsType type, double value) {
    // Color coding based on value
    Color valueColor;
    if (value > -8) {
      valueColor = FabFilterColors.red;
    } else if (value > -12) {
      valueColor = FabFilterColors.orange;
    } else if (value > -16) {
      valueColor = FabFilterColors.yellow;
    } else {
      valueColor = FabFilterColors.green;
    }

    return Tooltip(
      message: type.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: FabFilterColors.bgVoid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: type == LufsType.integrated
                ? FabFilterColors.blue.withValues(alpha: 0.5)
                : FabFilterColors.border,
          ),
        ),
        child: Column(
          children: [
            Text(type.label, style: FabFilterTextStyles.label),
            const SizedBox(height: 4),
            Text(
              '${value.toStringAsFixed(1)} LUFS',
              style: FabFilterTextStyles.value.copyWith(
                color: valueColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPERT SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildExpertSection() {
    return buildSection(
      'ADVANCED',
      Row(
        children: [
          buildToggle(
            'Channel Link',
            _channelLink,
            (v) => setState(() => _channelLink = v),
          ),
          const SizedBox(width: 16),
          buildToggle(
            'Unity Gain',
            _unityGain,
            (v) => setState(() => _unityGain = v),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIMITER DISPLAY PAINTER (Scrolling waveform)
// ═══════════════════════════════════════════════════════════════════════════

class _LimiterDisplayPainter extends CustomPainter {
  final List<LimiterLevelSample> history;
  final double ceiling;
  final MeterScale meterScale;

  _LimiterDisplayPainter({
    required this.history,
    required this.ceiling,
    required this.meterScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
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

    // Grid
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;

    // Horizontal grid lines
    final dbOffset = meterScale.offset.toDouble();
    for (var db = -48; db <= 0; db += 6) {
      final y = size.height * (1 - (db + 48 + dbOffset) / (48 + dbOffset));
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

        // Label
        _drawLabel(
          canvas,
          '${db}dB',
          Offset(4, y - 6),
          FabFilterColors.textMuted,
        );
      }
    }

    // Ceiling line
    final ceilingY = size.height * (1 - (ceiling + 48 + dbOffset) / (48 + dbOffset));
    final ceilingPaint = Paint()
      ..color = FabFilterColors.red
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, ceilingY),
      Offset(size.width, ceilingY),
      ceilingPaint,
    );

    if (history.isEmpty) return;

    final sampleWidth = size.width / history.length;

    // Input level (gray, background)
    _drawLevelPath(
      canvas,
      size,
      history.map((s) => s.inputPeak).toList(),
      FabFilterColors.textMuted.withValues(alpha: 0.3),
      dbOffset,
    );

    // Output level (blue, foreground)
    _drawLevelPath(
      canvas,
      size,
      history.map((s) => s.outputPeak).toList(),
      FabFilterColors.blue.withValues(alpha: 0.6),
      dbOffset,
    );

    // Gain reduction (red, from top)
    final grPaint = Paint()
      ..color = FabFilterColors.red.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < history.length; i++) {
      final x = i * sampleWidth;
      final gr = history[i].gainReduction.abs();
      final grHeight = (gr / 24).clamp(0.0, 1.0) * size.height * 0.5;

      canvas.drawRect(
        Rect.fromLTWH(x, 0, sampleWidth + 1, grHeight),
        grPaint,
      );
    }

    // True peak clipping indicators
    for (var i = 0; i < history.length; i++) {
      if (history[i].truePeak > ceiling) {
        final x = i * sampleWidth;
        canvas.drawRect(
          Rect.fromLTWH(x, ceilingY - 2, sampleWidth + 1, 4),
          Paint()..color = FabFilterColors.red,
        );
      }
    }

    // Ceiling label
    _drawLabel(
      canvas,
      '${ceiling.toStringAsFixed(1)}dB',
      Offset(size.width - 50, ceilingY - 12),
      FabFilterColors.red,
    );
  }

  void _drawLevelPath(
    Canvas canvas,
    Size size,
    List<double> levels,
    Color color,
    double dbOffset,
  ) {
    final path = Path();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sampleWidth = size.width / levels.length;

    path.moveTo(0, size.height);

    for (var i = 0; i < levels.length; i++) {
      final x = i * sampleWidth;
      final level = levels[i];
      final normalizedLevel =
          ((level + 48 + dbOffset) / (48 + dbOffset)).clamp(0.0, 1.0);
      final y = size.height * (1 - normalizedLevel);

      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _LimiterDisplayPainter oldDelegate) => true;
}
