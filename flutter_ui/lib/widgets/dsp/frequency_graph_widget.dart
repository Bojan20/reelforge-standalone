/// Frequency Graph Widget
///
/// Reusable Flutter widget for DSP transfer function visualization.
/// Wraps FrequencyGraphPainter with convenience builders for common use cases:
/// - EQ frequency response
/// - Compressor transfer curve
/// - Limiter transfer curve
/// - Gate/Expander transfer curve
/// - Filter response
///
/// Visual style: FabFilter Pro-Q 3 inspired

import 'package:flutter/material.dart';

import '../../models/frequency_graph_data.dart';
import '../../services/dsp_frequency_calculator.dart';
import '../fabfilter/fabfilter_theme.dart';
import 'frequency_graph_painter.dart';

// =============================================================================
// FREQUENCY GRAPH WIDGET
// =============================================================================

/// Widget for displaying DSP frequency response graphs
class FrequencyGraphWidget extends StatelessWidget {
  /// Response data to visualize
  final FrequencyResponseData data;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether to show grid lines
  final bool showGrid;

  /// Whether to show axis labels
  final bool showLabels;

  /// Whether to show individual band curves (for EQ)
  final bool showBandCurves;

  /// Optional accent color (defaults based on processor type)
  final Color? accentColor;

  /// Current input level for marker animation
  final double? currentInput;

  /// Whether the processor is bypassed
  final bool bypassed;

  /// Display settings override
  final FrequencyGraphSettings? settings;

  const FrequencyGraphWidget({
    super.key,
    required this.data,
    this.width = 400,
    this.height = 200,
    this.showGrid = true,
    this.showLabels = true,
    this.showBandCurves = true,
    this.accentColor,
    this.currentInput,
    this.bypassed = false,
    this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSettings = settings ??
        (data.isDynamics
            ? FrequencyGraphSettings.dynamics.copyWith(
                showGrid: showGrid,
                showFrequencyLabels: showLabels,
                showDbLabels: showLabels,
              )
            : FrequencyGraphSettings.eq.copyWith(
                showGrid: showGrid,
                showFrequencyLabels: showLabels,
                showDbLabels: showLabels,
                showBandCurves: showBandCurves,
              ));

    return Container(
      width: width,
      height: height,
      decoration: FabFilterDecorations.display(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          size: Size(width, height),
          painter: FrequencyGraphPainter(
            data: data,
            settings: effectiveSettings,
            accentColor: accentColor,
            showBandCurves: showBandCurves,
            currentInput: currentInput,
            bypassed: bypassed,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CONVENIENCE BUILDERS
// =============================================================================

/// EQ frequency response graph
class EqFrequencyGraph extends StatelessWidget {
  /// EQ bands to visualize
  final List<EqBandResponse> bands;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Sample rate for coefficient calculation
  final double sampleRate;

  /// Whether to show individual band curves
  final bool showBandCurves;

  /// Whether the EQ is bypassed
  final bool bypassed;

  const EqFrequencyGraph({
    super.key,
    required this.bands,
    this.width = 400,
    this.height = 150,
    this.sampleRate = 48000.0,
    this.showBandCurves = true,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateEqResponse(
      bands: bands,
      sampleRate: sampleRate,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      showBandCurves: showBandCurves,
      accentColor: FabFilterColors.blue,
      bypassed: bypassed,
    );
  }
}

/// Compressor transfer curve graph
class CompressorCurveGraph extends StatelessWidget {
  /// Threshold in dB
  final double threshold;

  /// Compression ratio (e.g., 4.0 for 4:1)
  final double ratio;

  /// Knee width in dB
  final double kneeWidth;

  /// Current input level for marker
  final double? currentInput;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether the compressor is bypassed
  final bool bypassed;

  const CompressorCurveGraph({
    super.key,
    required this.threshold,
    required this.ratio,
    this.kneeWidth = 6.0,
    this.currentInput,
    this.width = 150,
    this.height = 150,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateCompressorCurve(
      threshold: threshold,
      ratio: ratio,
      kneeWidth: kneeWidth,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      accentColor: FabFilterColors.orange,
      currentInput: currentInput,
      bypassed: bypassed,
    );
  }
}

/// Limiter transfer curve graph
class LimiterCurveGraph extends StatelessWidget {
  /// Output ceiling in dB
  final double ceiling;

  /// Threshold in dB (defaults to ceiling - 10)
  final double? threshold;

  /// Knee width in dB
  final double kneeWidth;

  /// Current input level for marker
  final double? currentInput;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether the limiter is bypassed
  final bool bypassed;

  const LimiterCurveGraph({
    super.key,
    required this.ceiling,
    this.threshold,
    this.kneeWidth = 3.0,
    this.currentInput,
    this.width = 150,
    this.height = 150,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveThreshold = threshold ?? (ceiling - 10);

    final data = DspFrequencyCalculator.calculateLimiterCurve(
      ceiling: ceiling,
      threshold: effectiveThreshold,
      kneeWidth: kneeWidth,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      accentColor: FabFilterColors.red,
      currentInput: currentInput,
      bypassed: bypassed,
    );
  }
}

/// Gate transfer curve graph
class GateCurveGraph extends StatelessWidget {
  /// Threshold in dB
  final double threshold;

  /// Expansion ratio (higher = more aggressive gating)
  final double ratio;

  /// Range/floor in dB (maximum attenuation)
  final double range;

  /// Knee width in dB
  final double kneeWidth;

  /// Current input level for marker
  final double? currentInput;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether the gate is bypassed
  final bool bypassed;

  const GateCurveGraph({
    super.key,
    required this.threshold,
    this.ratio = 10.0,
    this.range = -80.0,
    this.kneeWidth = 6.0,
    this.currentInput,
    this.width = 150,
    this.height = 150,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateGateCurve(
      threshold: threshold,
      ratio: ratio,
      range: range,
      kneeWidth: kneeWidth,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      accentColor: FabFilterColors.cyan,
      currentInput: currentInput,
      bypassed: bypassed,
    );
  }
}

/// Expander transfer curve graph
class ExpanderCurveGraph extends StatelessWidget {
  /// Threshold in dB
  final double threshold;

  /// Expansion ratio (typically 1.5:1 to 4:1)
  final double ratio;

  /// Knee width in dB
  final double kneeWidth;

  /// Current input level for marker
  final double? currentInput;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether the expander is bypassed
  final bool bypassed;

  const ExpanderCurveGraph({
    super.key,
    required this.threshold,
    this.ratio = 2.0,
    this.kneeWidth = 6.0,
    this.currentInput,
    this.width = 150,
    this.height = 150,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateExpanderCurve(
      threshold: threshold,
      ratio: ratio,
      kneeWidth: kneeWidth,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      accentColor: FabFilterColors.purple,
      currentInput: currentInput,
      bypassed: bypassed,
    );
  }
}

/// Single filter frequency response graph
class FilterResponseGraph extends StatelessWidget {
  /// Filter type (lowpass, highpass, bandpass, notch, etc.)
  final String filterType;

  /// Center/cutoff frequency in Hz
  final double frequency;

  /// Gain in dB (for shelving/peaking filters)
  final double gain;

  /// Q factor
  final double q;

  /// Slope in dB/octave (for cut/shelf filters)
  final double slope;

  /// Sample rate
  final double sampleRate;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether the filter is bypassed
  final bool bypassed;

  const FilterResponseGraph({
    super.key,
    required this.filterType,
    required this.frequency,
    this.gain = 0.0,
    this.q = 1.0,
    this.slope = 12.0,
    this.sampleRate = 48000.0,
    this.width = 300,
    this.height = 120,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateFilterResponse(
      filterType: filterType,
      frequency: frequency,
      gain: gain,
      q: q,
      slope: slope,
      sampleRate: sampleRate,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      accentColor: FabFilterColors.blue,
      showBandCurves: false,
      bypassed: bypassed,
    );
  }
}

/// Reverb decay visualization
class ReverbDecayGraph extends StatelessWidget {
  /// Base RT60 decay time in seconds
  final double baseDecay;

  /// High-frequency damping (0-1)
  final double damping;

  /// Low-frequency decay multiplier
  final double lowFreqMultiplier;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Whether the reverb is bypassed
  final bool bypassed;

  const ReverbDecayGraph({
    super.key,
    required this.baseDecay,
    this.damping = 0.5,
    this.lowFreqMultiplier = 1.2,
    this.width = 300,
    this.height = 120,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateReverbDecay(
      baseDecay: baseDecay,
      damping: damping,
      lowFreqMultiplier: lowFreqMultiplier,
    );

    return FrequencyGraphWidget(
      data: data,
      width: width,
      height: height,
      accentColor: FabFilterColors.cyan,
      showBandCurves: false,
      settings: FrequencyGraphSettings.reverb,
      bypassed: bypassed,
    );
  }
}

// =============================================================================
// ANIMATED VARIANTS
// =============================================================================

/// Animated compressor curve that updates with input level
class AnimatedCompressorCurve extends StatefulWidget {
  final double threshold;
  final double ratio;
  final double kneeWidth;
  final double width;
  final double height;
  final bool bypassed;

  /// Stream of input levels in dB
  final Stream<double>? inputLevelStream;

  const AnimatedCompressorCurve({
    super.key,
    required this.threshold,
    required this.ratio,
    this.kneeWidth = 6.0,
    this.width = 150,
    this.height = 150,
    this.bypassed = false,
    this.inputLevelStream,
  });

  @override
  State<AnimatedCompressorCurve> createState() => _AnimatedCompressorCurveState();
}

class _AnimatedCompressorCurveState extends State<AnimatedCompressorCurve> {
  double _currentInput = -60.0;

  @override
  void initState() {
    super.initState();
    widget.inputLevelStream?.listen((level) {
      if (mounted) {
        setState(() => _currentInput = level);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompressorCurveGraph(
      threshold: widget.threshold,
      ratio: widget.ratio,
      kneeWidth: widget.kneeWidth,
      currentInput: _currentInput,
      width: widget.width,
      height: widget.height,
      bypassed: widget.bypassed,
    );
  }
}

// =============================================================================
// COMPACT VARIANTS FOR LOWER ZONE
// =============================================================================

/// Compact EQ curve for inline display (e.g., channel strip)
class CompactEqCurve extends StatelessWidget {
  final List<EqBandResponse> bands;
  final double width;
  final double height;
  final bool bypassed;

  const CompactEqCurve({
    super.key,
    required this.bands,
    this.width = 80,
    this.height = 40,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = DspFrequencyCalculator.calculateEqResponse(
      bands: bands,
      numPoints: 128, // Lower resolution for compact display
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          size: Size(width, height),
          painter: FrequencyGraphPainter(
            data: data,
            settings: FrequencyGraphSettings.eq.copyWith(
              showGrid: false,
              showFrequencyLabels: false,
              showDbLabels: false,
              showBandCurves: false,
            ),
            accentColor: FabFilterColors.blue,
            showBandCurves: false,
            bypassed: bypassed,
          ),
        ),
      ),
    );
  }
}

/// Compact dynamics curve for inline display
class CompactDynamicsCurve extends StatelessWidget {
  final double threshold;
  final double ratio;
  final double kneeWidth;
  final double? currentInput;
  final double width;
  final double height;
  final bool isLimiter;
  final bool bypassed;

  const CompactDynamicsCurve({
    super.key,
    required this.threshold,
    required this.ratio,
    this.kneeWidth = 6.0,
    this.currentInput,
    this.width = 60,
    this.height = 60,
    this.isLimiter = false,
    this.bypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          size: Size(width, height),
          painter: DynamicsCurvePainter(
            threshold: threshold,
            ratio: ratio,
            kneeWidth: kneeWidth,
            currentInput: currentInput,
            curveColor: isLimiter ? FabFilterColors.red : FabFilterColors.orange,
            showGrid: false,
            bypassed: bypassed,
          ),
        ),
      ),
    );
  }
}
