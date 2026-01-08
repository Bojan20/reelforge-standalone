/// ReelForge Professional Multiband Dynamics Panel
///
/// Multi-band compressor and limiter with up to 6 bands.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Band settings class
class BandSettings {
  double threshold;
  double ratio;
  double attack;
  double release;
  double knee;
  double makeup;
  bool solo;
  bool mute;
  bool bypass;
  double gainReduction;

  BandSettings({
    this.threshold = -20.0,
    this.ratio = 4.0,
    this.attack = 10.0,
    this.release = 100.0,
    this.knee = 6.0,
    this.makeup = 0.0,
    this.solo = false,
    this.mute = false,
    this.bypass = false,
    this.gainReduction = 0.0,
  });
}

/// Professional Multiband Dynamics Panel Widget
class MultibandPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const MultibandPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<MultibandPanel> createState() => _MultibandPanelState();
}

class _MultibandPanelState extends State<MultibandPanel> {
  // Number of bands
  int _numBands = 4;

  // Crossover frequencies
  List<double> _crossovers = [100.0, 500.0, 2000.0, 6000.0, 12000.0];

  // Crossover type
  CrossoverType _crossoverType = CrossoverType.linkwitzRiley24;

  // Band settings
  List<BandSettings> _bands = [];

  // Output gain
  double _outputGain = 0.0;

  // Selected band for editing
  int _selectedBand = 0;

  // State
  bool _initialized = false;
  bool _bypassed = false;

  // Band colors
  static const List<Color> _bandColors = [
    Color(0xFF4A9EFF), // Blue - Low
    Color(0xFF40FF90), // Green - Low-mid
    Color(0xFFFFFF40), // Yellow - Mid
    Color(0xFFFF9040), // Orange - High-mid
    Color(0xFFFF4060), // Red - High
    Color(0xFFFF40FF), // Magenta - Air
  ];

  @override
  void initState() {
    super.initState();
    _initializeBands();
    _initializeProcessor();
  }

  void _initializeBands() {
    _bands = List.generate(6, (_) => BandSettings());
  }

  @override
  void dispose() {
    NativeFFI.instance.multibandCompRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = NativeFFI.instance.multibandCompCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
      numBands: _numBands,
    );

    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    NativeFFI.instance.multibandCompSetNumBands(widget.trackId, _numBands);
    NativeFFI.instance.multibandCompSetCrossoverType(widget.trackId, _crossoverType);
    NativeFFI.instance.multibandCompSetOutputGain(widget.trackId, _outputGain);

    // Apply crossovers
    for (int i = 0; i < _numBands - 1; i++) {
      NativeFFI.instance.multibandCompSetCrossover(widget.trackId, i, _crossovers[i]);
    }

    // Apply band settings
    for (int i = 0; i < _numBands; i++) {
      _applyBandSettings(i);
    }

    widget.onSettingsChanged?.call();
  }

  void _applyBandSettings(int band) {
    final b = _bands[band];
    NativeFFI.instance.multibandCompSetBandThreshold(widget.trackId, band, b.threshold);
    NativeFFI.instance.multibandCompSetBandRatio(widget.trackId, band, b.ratio);
    NativeFFI.instance.multibandCompSetBandAttack(widget.trackId, band, b.attack);
    NativeFFI.instance.multibandCompSetBandRelease(widget.trackId, band, b.release);
    NativeFFI.instance.multibandCompSetBandKnee(widget.trackId, band, b.knee);
    NativeFFI.instance.multibandCompSetBandMakeup(widget.trackId, band, b.makeup);
    NativeFFI.instance.multibandCompSetBandSolo(widget.trackId, band, b.solo);
    NativeFFI.instance.multibandCompSetBandMute(widget.trackId, band, b.mute);
    NativeFFI.instance.multibandCompSetBandBypass(widget.trackId, band, b.bypass);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildBandSelector(),
          const SizedBox(height: 16),
          _buildCrossoverDisplay(),
          const SizedBox(height: 16),
          _buildGainReductionMeters(),
          const SizedBox(height: 16),
          _buildSelectedBandControls(),
          const SizedBox(height: 16),
          _buildGlobalControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.graphic_eq, color: ReelForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Multiband',
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _bypassed = !_bypassed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _bypassed
                  ? Colors.orange.withValues(alpha: 0.3)
                  : ReelForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypassed ? Colors.orange : ReelForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypassed ? Colors.orange : ReelForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _initialized
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _initialized ? 'Ready' : 'Init...',
            style: TextStyle(
              color: _initialized ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBandSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Bands',
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 16),
            ...List.generate(5, (i) => _buildBandCountButton(i + 2)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_numBands, (i) => Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedBand = i),
              child: Container(
                margin: EdgeInsets.only(right: i < _numBands - 1 ? 4 : 0),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedBand == i
                      ? _bandColors[i].withValues(alpha: 0.3)
                      : ReelForgeTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _selectedBand == i ? _bandColors[i] : ReelForgeTheme.border,
                    width: _selectedBand == i ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _bands[i].mute ? Colors.grey : _bandColors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getBandLabel(i),
                      style: TextStyle(
                        color: _selectedBand == i ? _bandColors[i] : ReelForgeTheme.textSecondary,
                        fontSize: 9,
                        fontWeight: _selectedBand == i ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildBandCountButton(int count) {
    final isActive = _numBands == count;
    return GestureDetector(
      onTap: () {
        setState(() {
          _numBands = count;
          if (_selectedBand >= count) _selectedBand = count - 1;
        });
        NativeFFI.instance.multibandCompSetNumBands(widget.trackId, count);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        width: 28,
        height: 24,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isActive
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
              : ReelForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.border,
          ),
        ),
        child: Center(
          child: Text(
            '$count',
            style: TextStyle(
              color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  String _getBandLabel(int band) {
    if (_numBands == 2) {
      return ['Low', 'High'][band];
    } else if (_numBands == 3) {
      return ['Low', 'Mid', 'High'][band];
    } else if (_numBands == 4) {
      return ['Low', 'L-Mid', 'H-Mid', 'High'][band];
    } else if (_numBands == 5) {
      return ['Low', 'L-Mid', 'Mid', 'H-Mid', 'High'][band];
    } else {
      return ['Low', 'L-Mid', 'Mid', 'H-Mid', 'High', 'Air'][band];
    }
  }

  Widget _buildCrossoverDisplay() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: ReelForgeTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, 40),
        painter: _CrossoverPainter(
          numBands: _numBands,
          crossovers: _crossovers,
          bandColors: _bandColors,
          selectedBand: _selectedBand,
        ),
      ),
    );
  }

  Widget _buildGainReductionMeters() {
    return Row(
      children: List.generate(_numBands, (i) {
        final gr = _bands[i].gainReduction;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < _numBands - 1 ? 4 : 0),
            height: 60,
            decoration: BoxDecoration(
              color: ReelForgeTheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _selectedBand == i ? _bandColors[i] : ReelForgeTheme.border,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (gr.abs() / 24.0).clamp(0.0, 1.0),
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          gr < -6 ? Colors.orange : _bandColors[i],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    '${gr.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: ReelForgeTheme.textSecondary,
                      fontSize: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSelectedBandControls() {
    final band = _bands[_selectedBand];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _bandColors[_selectedBand].withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Band header with S/M/B buttons
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _bandColors[_selectedBand],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Band ${_selectedBand + 1}: ${_getBandLabel(_selectedBand)}',
                style: TextStyle(
                  color: _bandColors[_selectedBand],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _buildSmallToggle('S', band.solo, (v) {
                setState(() => band.solo = v);
                NativeFFI.instance.multibandCompSetBandSolo(widget.trackId, _selectedBand, v);
                widget.onSettingsChanged?.call();
              }, Colors.yellow),
              const SizedBox(width: 4),
              _buildSmallToggle('M', band.mute, (v) {
                setState(() => band.mute = v);
                NativeFFI.instance.multibandCompSetBandMute(widget.trackId, _selectedBand, v);
                widget.onSettingsChanged?.call();
              }, Colors.red),
              const SizedBox(width: 4),
              _buildSmallToggle('B', band.bypass, (v) {
                setState(() => band.bypass = v);
                NativeFFI.instance.multibandCompSetBandBypass(widget.trackId, _selectedBand, v);
                widget.onSettingsChanged?.call();
              }, Colors.orange),
            ],
          ),
          const SizedBox(height: 12),

          // Threshold
          _buildParameterRow(
            label: 'Threshold',
            value: '${band.threshold.toStringAsFixed(1)} dB',
            child: _buildSlider(
              value: (band.threshold + 60) / 60,
              onChanged: (v) {
                setState(() => band.threshold = v * 60 - 60);
                NativeFFI.instance.multibandCompSetBandThreshold(widget.trackId, _selectedBand, band.threshold);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
          const SizedBox(height: 6),

          // Ratio
          _buildParameterRow(
            label: 'Ratio',
            value: '${band.ratio.toStringAsFixed(1)}:1',
            child: _buildSlider(
              value: (band.ratio - 1) / 19,
              onChanged: (v) {
                setState(() => band.ratio = v * 19 + 1);
                NativeFFI.instance.multibandCompSetBandRatio(widget.trackId, _selectedBand, band.ratio);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
          const SizedBox(height: 6),

          // Attack
          _buildParameterRow(
            label: 'Attack',
            value: '${band.attack.toStringAsFixed(1)} ms',
            child: _buildSlider(
              value: band.attack / 200,
              onChanged: (v) {
                setState(() => band.attack = v * 200);
                NativeFFI.instance.multibandCompSetBandAttack(widget.trackId, _selectedBand, band.attack);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
          const SizedBox(height: 6),

          // Release
          _buildParameterRow(
            label: 'Release',
            value: '${band.release.toStringAsFixed(0)} ms',
            child: _buildSlider(
              value: band.release / 2000,
              onChanged: (v) {
                setState(() => band.release = v * 2000);
                NativeFFI.instance.multibandCompSetBandRelease(widget.trackId, _selectedBand, band.release);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
          const SizedBox(height: 6),

          // Makeup
          _buildParameterRow(
            label: 'Makeup',
            value: '${band.makeup >= 0 ? "+" : ""}${band.makeup.toStringAsFixed(1)} dB',
            child: _buildSlider(
              value: (band.makeup + 24) / 48,
              onChanged: (v) {
                setState(() => band.makeup = v * 48 - 24);
                NativeFFI.instance.multibandCompSetBandMakeup(widget.trackId, _selectedBand, band.makeup);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallToggle(String label, bool active, ValueChanged<bool> onChanged, Color activeColor) {
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.3) : ReelForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? activeColor : ReelForgeTheme.border,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? activeColor : ReelForgeTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalControls() {
    return Column(
      children: [
        // Crossover type
        Row(
          children: [
            Text(
              'Crossover',
              style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: ReelForgeTheme.border),
                ),
                child: DropdownButton<CrossoverType>(
                  value: _crossoverType,
                  isExpanded: true,
                  dropdownColor: ReelForgeTheme.surfaceDark,
                  underline: const SizedBox(),
                  style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 11),
                  items: const [
                    DropdownMenuItem(value: CrossoverType.butterworth12, child: Text('Butterworth 12dB')),
                    DropdownMenuItem(value: CrossoverType.linkwitzRiley24, child: Text('L-R 24dB')),
                    DropdownMenuItem(value: CrossoverType.linkwitzRiley48, child: Text('L-R 48dB')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _crossoverType = v);
                      NativeFFI.instance.multibandCompSetCrossoverType(widget.trackId, v);
                      widget.onSettingsChanged?.call();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Output gain
        _buildParameterRow(
          label: 'Output',
          value: '${_outputGain >= 0 ? "+" : ""}${_outputGain.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_outputGain + 24) / 48,
            onChanged: (v) {
              setState(() => _outputGain = v * 48 - 24);
              NativeFFI.instance.multibandCompSetOutputGain(widget.trackId, _outputGain);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 65,
          child: Text(
            label,
            style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 60,
          child: Text(
            value,
            style: TextStyle(
              color: ReelForgeTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        activeTrackColor: _bandColors[_selectedBand],
        inactiveTrackColor: ReelForgeTheme.surface,
        thumbColor: _bandColors[_selectedBand],
        overlayColor: _bandColors[_selectedBand].withValues(alpha: 0.2),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

// =============================================================================
// CROSSOVER PAINTER
// =============================================================================

class _CrossoverPainter extends CustomPainter {
  final int numBands;
  final List<double> crossovers;
  final List<Color> bandColors;
  final int selectedBand;

  _CrossoverPainter({
    required this.numBands,
    required this.crossovers,
    required this.bandColors,
    required this.selectedBand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Calculate positions from frequencies (log scale)
    const minFreq = 20.0;
    const maxFreq = 20000.0;

    double freqToX(double freq) {
      return (math.log(freq / minFreq) / math.log(maxFreq / minFreq)) * size.width;
    }

    // Draw bands
    double prevX = 0;
    for (int i = 0; i < numBands; i++) {
      double nextX = i < numBands - 1 ? freqToX(crossovers[i]) : size.width;

      paint.color = bandColors[i].withValues(alpha: selectedBand == i ? 0.4 : 0.2);
      canvas.drawRect(Rect.fromLTRB(prevX, 0, nextX, size.height), paint);

      prevX = nextX;
    }

    // Draw crossover lines
    final linePaint = Paint()
      ..color = ReelForgeTheme.border
      ..strokeWidth = 1;

    for (int i = 0; i < numBands - 1; i++) {
      final x = freqToX(crossovers[i]);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      // Draw frequency label
      final textPainter = TextPainter(
        text: TextSpan(
          text: _formatFreq(crossovers[i]),
          style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - 12));
    }

    // Draw frequency scale
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = freqToX(freq);
      final tickPaint = Paint()
        ..color = ReelForgeTheme.border.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), tickPaint);
    }
  }

  String _formatFreq(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(1)}k';
    }
    return '${freq.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(covariant _CrossoverPainter oldDelegate) =>
      oldDelegate.numBands != numBands ||
      oldDelegate.selectedBand != selectedBand ||
      oldDelegate.crossovers != crossovers;
}
