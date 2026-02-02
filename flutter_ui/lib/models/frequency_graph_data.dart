/// Frequency Graph Data Models
///
/// Data structures for DSP transfer function visualization:
/// - EQ frequency response (magnitude in dB vs frequency in Hz)
/// - Dynamics transfer curves (output dB vs input dB)
/// - Filter responses (magnitude + phase)
/// - Reverb decay characteristics
///
/// Reference: Audio EQ Cookbook (Robert Bristow-Johnson)

import 'dart:typed_data';

// =============================================================================
// PROCESSOR TYPE ENUM
// =============================================================================

/// DSP processor type for frequency response visualization
enum FrequencyProcessorType {
  /// Parametric/Graphic EQ — shows magnitude response
  eq('EQ', 'Frequency response curve'),

  /// Compressor — shows static transfer curve (input vs output)
  compressor('Compressor', 'Transfer curve'),

  /// Limiter — shows transfer curve with ceiling
  limiter('Limiter', 'Transfer curve with ceiling'),

  /// Gate/Expander — shows transfer curve below threshold
  gate('Gate', 'Downward expansion curve'),

  /// Expander — shows transfer curve with expansion ratio
  expander('Expander', 'Expansion transfer curve'),

  /// Filter (lowpass, highpass, bandpass, etc.)
  filter('Filter', 'Filter frequency response'),

  /// Reverb — shows frequency-dependent decay
  reverb('Reverb', 'Decay time per frequency band'),

  /// Unknown/generic processor
  unknown('Unknown', 'Generic response');

  final String displayName;
  final String description;

  const FrequencyProcessorType(this.displayName, this.description);
}

// =============================================================================
// EQ BAND RESPONSE
// =============================================================================

/// Individual EQ band response data
class EqBandResponse {
  /// Center frequency in Hz
  final double frequency;

  /// Gain in dB (positive = boost, negative = cut)
  final double gain;

  /// Q factor (bandwidth)
  /// Higher Q = narrower bandwidth
  /// Q = fc / bandwidth
  final double q;

  /// Filter type string identifier
  /// Valid types: 'lowcut', 'highcut', 'lowshelf', 'highshelf',
  /// 'bell', 'notch', 'bandpass', 'allpass', 'tilt'
  final String filterType;

  /// Whether this band is enabled
  final bool enabled;

  /// Slope for shelf/cut filters (dB/octave)
  /// Common values: 6, 12, 18, 24, 48
  final double slope;

  const EqBandResponse({
    required this.frequency,
    this.gain = 0.0,
    this.q = 1.0,
    this.filterType = 'bell',
    this.enabled = true,
    this.slope = 12.0,
  });

  EqBandResponse copyWith({
    double? frequency,
    double? gain,
    double? q,
    String? filterType,
    bool? enabled,
    double? slope,
  }) {
    return EqBandResponse(
      frequency: frequency ?? this.frequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      filterType: filterType ?? this.filterType,
      enabled: enabled ?? this.enabled,
      slope: slope ?? this.slope,
    );
  }

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        'gain': gain,
        'q': q,
        'filterType': filterType,
        'enabled': enabled,
        'slope': slope,
      };

  factory EqBandResponse.fromJson(Map<String, dynamic> json) {
    return EqBandResponse(
      frequency: (json['frequency'] as num?)?.toDouble() ?? 1000.0,
      gain: (json['gain'] as num?)?.toDouble() ?? 0.0,
      q: (json['q'] as num?)?.toDouble() ?? 1.0,
      filterType: json['filterType'] as String? ?? 'bell',
      enabled: json['enabled'] as bool? ?? true,
      slope: (json['slope'] as num?)?.toDouble() ?? 12.0,
    );
  }

  @override
  String toString() => 'EqBand($filterType @ ${frequency.toStringAsFixed(0)}Hz, '
      '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}dB, Q=${q.toStringAsFixed(2)})';
}

// =============================================================================
// BIQUAD COEFFICIENTS
// =============================================================================

/// Biquad filter coefficients for transfer function evaluation
/// Transfer function: H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
class BiquadCoefficients {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  const BiquadCoefficients({
    this.b0 = 1.0,
    this.b1 = 0.0,
    this.b2 = 0.0,
    this.a1 = 0.0,
    this.a2 = 0.0,
  });

  /// Unity (pass-through) coefficients
  static const BiquadCoefficients unity = BiquadCoefficients(
    b0: 1.0,
    b1: 0.0,
    b2: 0.0,
    a1: 0.0,
    a2: 0.0,
  );

  @override
  String toString() =>
      'Biquad(b0=$b0, b1=$b1, b2=$b2, a1=$a1, a2=$a2)';
}

// =============================================================================
// FREQUENCY RESPONSE DATA
// =============================================================================

/// Complete frequency response data for visualization
class FrequencyResponseData {
  /// Processor type
  final FrequencyProcessorType type;

  /// Frequency points in Hz (log-spaced for EQ, linear for dynamics)
  final Float64List frequencies;

  /// Magnitude values
  /// - For EQ/Filter: dB values (can be positive or negative)
  /// - For Dynamics: output dB values (corresponding to input frequencies as dB)
  final Float64List magnitudes;

  /// Phase values in radians (optional, for phase response)
  final Float64List? phases;

  /// Sample rate used for calculation
  final double sampleRate;

  // ─── EQ-specific data ─────────────────────────────────────────────────────

  /// Individual band responses (for EQ)
  final List<EqBandResponse>? bands;

  /// Per-band magnitude data (for overlaying individual bands)
  /// Map of band index to magnitude array
  final Map<int, Float64List>? bandMagnitudes;

  // ─── Dynamics-specific data ───────────────────────────────────────────────

  /// Threshold in dB (for compressor/limiter/gate)
  final double? threshold;

  /// Ratio (for compressor/expander)
  /// e.g., 4.0 = 4:1 compression
  final double? ratio;

  /// Knee width in dB (for soft knee dynamics)
  final double? kneeWidth;

  /// Ceiling in dB (for limiter)
  final double? ceiling;

  /// Range/floor in dB (for gate)
  final double? range;

  // ─── Reverb-specific data ─────────────────────────────────────────────────

  /// Decay times per frequency band (RT60 in seconds)
  final Float64List? decayTimes;

  /// Frequency bands for reverb decay visualization
  final Float64List? decayFrequencies;

  const FrequencyResponseData({
    required this.type,
    required this.frequencies,
    required this.magnitudes,
    this.phases,
    this.sampleRate = 48000.0,
    this.bands,
    this.bandMagnitudes,
    this.threshold,
    this.ratio,
    this.kneeWidth,
    this.ceiling,
    this.range,
    this.decayTimes,
    this.decayFrequencies,
  });

  /// Number of frequency points
  int get length => frequencies.length;

  /// Minimum magnitude value in dB
  double get minMagnitude {
    double min = double.infinity;
    for (final m in magnitudes) {
      if (m < min) min = m;
    }
    return min;
  }

  /// Maximum magnitude value in dB
  double get maxMagnitude {
    double max = double.negativeInfinity;
    for (final m in magnitudes) {
      if (m > max) max = m;
    }
    return max;
  }

  /// Minimum frequency in Hz
  double get minFrequency => frequencies.isNotEmpty ? frequencies.first : 20.0;

  /// Maximum frequency in Hz
  double get maxFrequency => frequencies.isNotEmpty ? frequencies.last : 20000.0;

  /// Get magnitude at specific frequency (linear interpolation)
  double getMagnitudeAt(double freq) {
    if (frequencies.isEmpty) return 0.0;
    if (freq <= frequencies.first) return magnitudes.first;
    if (freq >= frequencies.last) return magnitudes.last;

    // Binary search for interpolation
    int low = 0;
    int high = frequencies.length - 1;
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (frequencies[mid] <= freq) {
        low = mid;
      } else {
        high = mid;
      }
    }

    // Linear interpolation
    final f0 = frequencies[low];
    final f1 = frequencies[high];
    final m0 = magnitudes[low];
    final m1 = magnitudes[high];
    final t = (freq - f0) / (f1 - f0);
    return m0 + (m1 - m0) * t;
  }

  /// Check if this is a dynamics processor (compressor/limiter/gate/expander)
  bool get isDynamics =>
      type == FrequencyProcessorType.compressor ||
      type == FrequencyProcessorType.limiter ||
      type == FrequencyProcessorType.gate ||
      type == FrequencyProcessorType.expander;

  /// Check if this is a frequency-domain processor (EQ/filter)
  bool get isFrequencyDomain =>
      type == FrequencyProcessorType.eq ||
      type == FrequencyProcessorType.filter;

  @override
  String toString() => 'FrequencyResponseData($type, ${frequencies.length} points, '
      '${minFrequency.toStringAsFixed(0)}-${maxFrequency.toStringAsFixed(0)} Hz)';
}

// =============================================================================
// DYNAMICS POINT
// =============================================================================

/// Single point on a dynamics transfer curve
class DynamicsPoint {
  /// Input level in dB
  final double inputDb;

  /// Output level in dB
  final double outputDb;

  /// Gain reduction at this point (inputDb - outputDb)
  double get gainReduction => inputDb - outputDb;

  const DynamicsPoint({
    required this.inputDb,
    required this.outputDb,
  });

  @override
  String toString() =>
      'DynamicsPoint(in=${inputDb.toStringAsFixed(1)}dB, out=${outputDb.toStringAsFixed(1)}dB)';
}

// =============================================================================
// GRAPH DISPLAY SETTINGS
// =============================================================================

/// Display settings for frequency graph visualization
class FrequencyGraphSettings {
  /// Minimum frequency to display (Hz)
  final double minFrequency;

  /// Maximum frequency to display (Hz)
  final double maxFrequency;

  /// Minimum magnitude/dB to display
  final double minDb;

  /// Maximum magnitude/dB to display
  final double maxDb;

  /// Number of points for curve calculation
  final int resolution;

  /// Whether to show grid lines
  final bool showGrid;

  /// Whether to show frequency labels
  final bool showFrequencyLabels;

  /// Whether to show dB labels
  final bool showDbLabels;

  /// Whether to show individual band curves (for EQ)
  final bool showBandCurves;

  /// Whether to use logarithmic frequency scale
  final bool logFrequencyScale;

  const FrequencyGraphSettings({
    this.minFrequency = 20.0,
    this.maxFrequency = 20000.0,
    this.minDb = -24.0,
    this.maxDb = 24.0,
    this.resolution = 512,
    this.showGrid = true,
    this.showFrequencyLabels = true,
    this.showDbLabels = true,
    this.showBandCurves = true,
    this.logFrequencyScale = true,
  });

  /// Settings optimized for EQ display
  static const FrequencyGraphSettings eq = FrequencyGraphSettings(
    minFrequency: 20.0,
    maxFrequency: 20000.0,
    minDb: -24.0,
    maxDb: 24.0,
    resolution: 512,
    showBandCurves: true,
    logFrequencyScale: true,
  );

  /// Settings optimized for dynamics display
  static const FrequencyGraphSettings dynamics = FrequencyGraphSettings(
    minFrequency: -60.0, // Actually input dB for dynamics
    maxFrequency: 6.0, // Actually input dB for dynamics
    minDb: -60.0,
    maxDb: 6.0,
    resolution: 256,
    showBandCurves: false,
    logFrequencyScale: false,
  );

  /// Settings optimized for reverb decay display
  static const FrequencyGraphSettings reverb = FrequencyGraphSettings(
    minFrequency: 63.0,
    maxFrequency: 16000.0,
    minDb: 0.0,
    maxDb: 10.0, // Decay time in seconds
    resolution: 10, // 10 frequency bands
    showBandCurves: false,
    logFrequencyScale: true,
  );

  FrequencyGraphSettings copyWith({
    double? minFrequency,
    double? maxFrequency,
    double? minDb,
    double? maxDb,
    int? resolution,
    bool? showGrid,
    bool? showFrequencyLabels,
    bool? showDbLabels,
    bool? showBandCurves,
    bool? logFrequencyScale,
  }) {
    return FrequencyGraphSettings(
      minFrequency: minFrequency ?? this.minFrequency,
      maxFrequency: maxFrequency ?? this.maxFrequency,
      minDb: minDb ?? this.minDb,
      maxDb: maxDb ?? this.maxDb,
      resolution: resolution ?? this.resolution,
      showGrid: showGrid ?? this.showGrid,
      showFrequencyLabels: showFrequencyLabels ?? this.showFrequencyLabels,
      showDbLabels: showDbLabels ?? this.showDbLabels,
      showBandCurves: showBandCurves ?? this.showBandCurves,
      logFrequencyScale: logFrequencyScale ?? this.logFrequencyScale,
    );
  }
}
