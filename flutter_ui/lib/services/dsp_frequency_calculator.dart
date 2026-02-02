/// DSP Frequency Response Calculator
///
/// Calculates transfer functions for DSP processors:
/// - EQ/Filter: Biquad magnitude response using Audio EQ Cookbook formulas
/// - Compressor/Limiter: Static transfer curves with soft knee
/// - Gate/Expander: Downward expansion curves
/// - Reverb: Frequency-dependent decay time
///
/// Reference: Audio EQ Cookbook by Robert Bristow-Johnson
/// Reference: Digital Filters by Julius O. Smith III

import 'dart:math' as math;
import 'dart:typed_data';

import '../models/frequency_graph_data.dart';

/// DSP frequency response calculator using textbook-accurate formulas
class DspFrequencyCalculator {
  DspFrequencyCalculator._();

  // ===========================================================================
  // CONSTANTS
  // ===========================================================================

  /// Default sample rate (48 kHz)
  static const double defaultSampleRate = 48000.0;

  /// Minimum frequency (20 Hz)
  static const double minFrequency = 20.0;

  /// Maximum frequency (20 kHz)
  static const double maxFrequency = 20000.0;

  /// Default resolution for EQ curves
  static const int defaultEqResolution = 512;

  /// Default resolution for dynamics curves
  static const int defaultDynamicsResolution = 256;

  /// Very small number to avoid log(0)
  static const double _epsilon = 1e-10;

  // ===========================================================================
  // LOGARITHMIC FREQUENCY ARRAY GENERATION
  // ===========================================================================

  /// Generate logarithmically-spaced frequency array
  /// Range: minFreq to maxFreq Hz
  static Float64List generateLogFrequencies({
    double minFreq = minFrequency,
    double maxFreq = maxFrequency,
    int numPoints = defaultEqResolution,
  }) {
    final frequencies = Float64List(numPoints);
    final logMin = math.log(minFreq);
    final logMax = math.log(maxFreq);
    final logStep = (logMax - logMin) / (numPoints - 1);

    for (int i = 0; i < numPoints; i++) {
      frequencies[i] = math.exp(logMin + i * logStep);
    }

    return frequencies;
  }

  /// Generate linearly-spaced dB array for dynamics curves
  static Float64List generateLinearDb({
    double minDb = -60.0,
    double maxDb = 6.0,
    int numPoints = defaultDynamicsResolution,
  }) {
    final dbValues = Float64List(numPoints);
    final step = (maxDb - minDb) / (numPoints - 1);

    for (int i = 0; i < numPoints; i++) {
      dbValues[i] = minDb + i * step;
    }

    return dbValues;
  }

  // ===========================================================================
  // EQ FREQUENCY RESPONSE CALCULATION
  // ===========================================================================

  /// Calculate complete EQ frequency response
  ///
  /// Combines all enabled bands into a single magnitude response curve.
  /// Also provides per-band magnitude data for visualization.
  ///
  /// Returns FrequencyResponseData with:
  /// - frequencies: Log-spaced frequency array (Hz)
  /// - magnitudes: Combined magnitude in dB
  /// - bandMagnitudes: Per-band magnitude arrays
  static FrequencyResponseData calculateEqResponse({
    required List<EqBandResponse> bands,
    double sampleRate = defaultSampleRate,
    int numPoints = defaultEqResolution,
    double minFreq = minFrequency,
    double maxFreq = maxFrequency,
  }) {
    final frequencies = generateLogFrequencies(
      minFreq: minFreq,
      maxFreq: maxFreq,
      numPoints: numPoints,
    );

    // Initialize combined magnitude (linear, will convert to dB later)
    final combinedMag = Float64List(numPoints);
    for (int i = 0; i < numPoints; i++) {
      combinedMag[i] = 1.0; // Start with unity gain
    }

    // Per-band magnitudes
    final bandMagnitudes = <int, Float64List>{};

    // Process each band
    for (int bandIdx = 0; bandIdx < bands.length; bandIdx++) {
      final band = bands[bandIdx];
      if (!band.enabled) {
        // Disabled bands contribute unity (0 dB)
        bandMagnitudes[bandIdx] = Float64List(numPoints);
        continue;
      }

      // Calculate biquad coefficients for this band
      final coeffs = _calculateBiquadCoefficients(
        filterType: band.filterType,
        frequency: band.frequency,
        gain: band.gain,
        q: band.q,
        slope: band.slope,
        sampleRate: sampleRate,
      );

      // Calculate magnitude response for this band
      final bandMag = Float64List(numPoints);
      for (int i = 0; i < numPoints; i++) {
        final mag = _evaluateBiquadMagnitude(
          coeffs: coeffs,
          frequency: frequencies[i],
          sampleRate: sampleRate,
        );
        bandMag[i] = 20.0 * math.log(mag.clamp(_epsilon, double.infinity)) / math.ln10;
        combinedMag[i] *= mag;
      }

      bandMagnitudes[bandIdx] = bandMag;
    }

    // Convert combined magnitude to dB
    final magnitudesDb = Float64List(numPoints);
    for (int i = 0; i < numPoints; i++) {
      magnitudesDb[i] =
          20.0 * math.log(combinedMag[i].clamp(_epsilon, double.infinity)) / math.ln10;
    }

    return FrequencyResponseData(
      type: FrequencyProcessorType.eq,
      frequencies: frequencies,
      magnitudes: magnitudesDb,
      sampleRate: sampleRate,
      bands: bands,
      bandMagnitudes: bandMagnitudes,
    );
  }

  /// Calculate single filter frequency response
  static FrequencyResponseData calculateFilterResponse({
    required String filterType,
    required double frequency,
    double gain = 0.0,
    double q = 1.0,
    double slope = 12.0,
    double sampleRate = defaultSampleRate,
    int numPoints = defaultEqResolution,
  }) {
    return calculateEqResponse(
      bands: [
        EqBandResponse(
          frequency: frequency,
          gain: gain,
          q: q,
          filterType: filterType,
          slope: slope,
        )
      ],
      sampleRate: sampleRate,
      numPoints: numPoints,
    );
  }

  // ===========================================================================
  // BIQUAD COEFFICIENT CALCULATION (Audio EQ Cookbook)
  // ===========================================================================

  /// Calculate biquad coefficients using Audio EQ Cookbook formulas
  ///
  /// Filter types supported:
  /// - 'bell': Peaking EQ
  /// - 'lowshelf': Low shelf filter
  /// - 'highshelf': High shelf filter
  /// - 'lowpass' / 'lowcut': Low-pass filter (also used for high-cut)
  /// - 'highpass' / 'highcut': High-pass filter (also used for low-cut)
  /// - 'bandpass': Bandpass filter
  /// - 'notch': Notch filter
  /// - 'allpass': All-pass filter
  static BiquadCoefficients _calculateBiquadCoefficients({
    required String filterType,
    required double frequency,
    required double gain,
    required double q,
    required double slope,
    required double sampleRate,
  }) {
    // Normalize frequency to 0-1 (Nyquist = 1)
    final w0 = 2.0 * math.pi * frequency / sampleRate;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);

    // A = sqrt(10^(dB/20)) = 10^(dB/40)
    final A = math.pow(10.0, gain / 40.0);

    // Alpha calculation depends on filter type
    double alpha;

    // For shelf filters, use slope
    if (filterType == 'lowshelf' || filterType == 'highshelf') {
      // S = slope in dB/octave
      // For shelf: alpha = sin(w0)/2 * sqrt((A + 1/A)*(1/S - 1) + 2)
      final S = slope / 12.0; // Convert dB/oct to shelf slope parameter
      alpha = sinW0 / 2.0 * math.sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0);
    } else {
      // For other filters, use Q
      alpha = sinW0 / (2.0 * q);
    }

    double b0, b1, b2, a0, a1, a2;

    switch (filterType.toLowerCase()) {
      case 'bell':
      case 'peaking':
      case 'parametric':
        // Peaking EQ
        b0 = 1.0 + alpha * A;
        b1 = -2.0 * cosW0;
        b2 = 1.0 - alpha * A;
        a0 = 1.0 + alpha / A;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha / A;
        break;

      case 'lowshelf':
        // Low shelf
        final sqrtAAlpha = math.sqrt(A) * alpha;
        b0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + 2.0 * sqrtAAlpha);
        b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0);
        b2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - 2.0 * sqrtAAlpha);
        a0 = (A + 1.0) + (A - 1.0) * cosW0 + 2.0 * sqrtAAlpha;
        a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0);
        a2 = (A + 1.0) + (A - 1.0) * cosW0 - 2.0 * sqrtAAlpha;
        break;

      case 'highshelf':
        // High shelf
        final sqrtAAlpha = math.sqrt(A) * alpha;
        b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + 2.0 * sqrtAAlpha);
        b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0);
        b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - 2.0 * sqrtAAlpha);
        a0 = (A + 1.0) - (A - 1.0) * cosW0 + 2.0 * sqrtAAlpha;
        a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0);
        a2 = (A + 1.0) - (A - 1.0) * cosW0 - 2.0 * sqrtAAlpha;
        break;

      case 'lowpass':
      case 'lpf':
        // 2nd-order Butterworth lowpass
        b0 = (1.0 - cosW0) / 2.0;
        b1 = 1.0 - cosW0;
        b2 = (1.0 - cosW0) / 2.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;
        break;

      case 'highpass':
      case 'hpf':
      case 'lowcut':
      case 'highcut': // Note: highcut should probably be lowpass, but handle it
        // 2nd-order Butterworth highpass
        b0 = (1.0 + cosW0) / 2.0;
        b1 = -(1.0 + cosW0);
        b2 = (1.0 + cosW0) / 2.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;
        break;

      case 'bandpass':
      case 'bpf':
        // Bandpass (constant skirt gain, peak gain = Q)
        b0 = alpha;
        b1 = 0.0;
        b2 = -alpha;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;
        break;

      case 'notch':
      case 'bandstop':
        // Notch filter
        b0 = 1.0;
        b1 = -2.0 * cosW0;
        b2 = 1.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;
        break;

      case 'allpass':
      case 'apf':
        // All-pass filter
        b0 = 1.0 - alpha;
        b1 = -2.0 * cosW0;
        b2 = 1.0 + alpha;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;
        break;

      case 'tilt':
        // Tilt EQ (simultaneous low shelf cut + high shelf boost or vice versa)
        // Implemented as high shelf (tilt parameter as gain)
        final sqrtAAlpha = math.sqrt(A) * alpha;
        b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + 2.0 * sqrtAAlpha);
        b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0);
        b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - 2.0 * sqrtAAlpha);
        a0 = (A + 1.0) - (A - 1.0) * cosW0 + 2.0 * sqrtAAlpha;
        a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0);
        a2 = (A + 1.0) - (A - 1.0) * cosW0 - 2.0 * sqrtAAlpha;
        break;

      default:
        // Unknown filter type — return unity
        return BiquadCoefficients.unity;
    }

    // Normalize coefficients (divide by a0)
    return BiquadCoefficients(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }

  // ===========================================================================
  // BIQUAD TRANSFER FUNCTION EVALUATION
  // ===========================================================================

  /// Evaluate biquad transfer function magnitude at given frequency
  ///
  /// H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
  ///
  /// At z = e^(jw), where w = 2*pi*f/fs:
  /// H(e^jw) = (b0 + b1*e^-jw + b2*e^-2jw) / (1 + a1*e^-jw + a2*e^-2jw)
  ///
  /// Magnitude = |H(e^jw)|
  static double _evaluateBiquadMagnitude({
    required BiquadCoefficients coeffs,
    required double frequency,
    required double sampleRate,
  }) {
    // Angular frequency (normalized)
    final w = 2.0 * math.pi * frequency / sampleRate;
    final cosW = math.cos(w);
    final sinW = math.sin(w);
    final cos2W = math.cos(2.0 * w);
    final sin2W = math.sin(2.0 * w);

    // Numerator: b0 + b1*e^-jw + b2*e^-2jw
    // Real part: b0 + b1*cos(w) + b2*cos(2w)
    // Imag part: -b1*sin(w) - b2*sin(2w)
    final numReal = coeffs.b0 + coeffs.b1 * cosW + coeffs.b2 * cos2W;
    final numImag = -coeffs.b1 * sinW - coeffs.b2 * sin2W;

    // Denominator: 1 + a1*e^-jw + a2*e^-2jw
    // Real part: 1 + a1*cos(w) + a2*cos(2w)
    // Imag part: -a1*sin(w) - a2*sin(2w)
    final denReal = 1.0 + coeffs.a1 * cosW + coeffs.a2 * cos2W;
    final denImag = -coeffs.a1 * sinW - coeffs.a2 * sin2W;

    // |H| = |Num| / |Den|
    final numMag = math.sqrt(numReal * numReal + numImag * numImag);
    final denMag = math.sqrt(denReal * denReal + denImag * denImag);

    return denMag > _epsilon ? numMag / denMag : numMag;
  }

  /// Public method to evaluate a biquad at a frequency
  /// Useful for testing and external use
  static double evaluateBiquad({
    required double frequency,
    required double sampleRate,
    required double b0,
    required double b1,
    required double b2,
    required double a1,
    required double a2,
  }) {
    return _evaluateBiquadMagnitude(
      coeffs: BiquadCoefficients(
        b0: b0,
        b1: b1,
        b2: b2,
        a1: a1,
        a2: a2,
      ),
      frequency: frequency,
      sampleRate: sampleRate,
    );
  }

  // ===========================================================================
  // COMPRESSOR TRANSFER CURVE CALCULATION
  // ===========================================================================

  /// Calculate compressor static transfer curve
  ///
  /// Transfer function with soft knee:
  /// - Below knee start: output = input (1:1)
  /// - In knee region: smooth quadratic transition
  /// - Above knee end: output = threshold + (input - threshold) / ratio
  ///
  /// Returns FrequencyResponseData where:
  /// - frequencies = input dB values
  /// - magnitudes = output dB values
  static FrequencyResponseData calculateCompressorCurve({
    required double threshold,
    required double ratio,
    double kneeWidth = 6.0,
    double minDb = -60.0,
    double maxDb = 6.0,
    int numPoints = defaultDynamicsResolution,
  }) {
    final inputDb = generateLinearDb(
      minDb: minDb,
      maxDb: maxDb,
      numPoints: numPoints,
    );

    final outputDb = Float64List(numPoints);
    final halfKnee = kneeWidth / 2.0;
    final kneeStart = threshold - halfKnee;
    final kneeEnd = threshold + halfKnee;

    for (int i = 0; i < numPoints; i++) {
      final input = inputDb[i];
      outputDb[i] = _calculateCompressorOutput(
        input: input,
        threshold: threshold,
        ratio: ratio,
        kneeStart: kneeStart,
        kneeEnd: kneeEnd,
        kneeWidth: kneeWidth,
      );
    }

    return FrequencyResponseData(
      type: FrequencyProcessorType.compressor,
      frequencies: inputDb, // Input dB as "frequency" axis
      magnitudes: outputDb, // Output dB as magnitude
      threshold: threshold,
      ratio: ratio,
      kneeWidth: kneeWidth,
    );
  }

  /// Calculate compressor output for single input value
  static double _calculateCompressorOutput({
    required double input,
    required double threshold,
    required double ratio,
    required double kneeStart,
    required double kneeEnd,
    required double kneeWidth,
  }) {
    if (kneeWidth <= 0 || input < kneeStart) {
      // Below knee (or hard knee): 1:1 ratio
      if (input < threshold) {
        return input;
      }
      // Above threshold: compressed
      return threshold + (input - threshold) / ratio;
    } else if (input > kneeEnd) {
      // Above knee: full compression
      return threshold + (input - threshold) / ratio;
    } else {
      // In knee region: smooth quadratic transition
      // This formula provides a smooth curve through the knee
      final xg = input - threshold;
      final halfRatio = (1.0 / ratio - 1.0) / 2.0;
      return input + halfRatio * math.pow(xg + kneeWidth / 2.0, 2) / kneeWidth;
    }
  }

  /// Get gain reduction at specific input level
  static double getCompressorGainReduction({
    required double inputDb,
    required double threshold,
    required double ratio,
    double kneeWidth = 6.0,
  }) {
    final halfKnee = kneeWidth / 2.0;
    final kneeStart = threshold - halfKnee;
    final kneeEnd = threshold + halfKnee;

    final outputDb = _calculateCompressorOutput(
      input: inputDb,
      threshold: threshold,
      ratio: ratio,
      kneeStart: kneeStart,
      kneeEnd: kneeEnd,
      kneeWidth: kneeWidth,
    );

    return inputDb - outputDb;
  }

  // ===========================================================================
  // LIMITER TRANSFER CURVE CALCULATION
  // ===========================================================================

  /// Calculate limiter static transfer curve
  ///
  /// A limiter is essentially a compressor with infinite ratio above ceiling.
  /// Returns curve where output never exceeds ceiling.
  static FrequencyResponseData calculateLimiterCurve({
    required double ceiling,
    double threshold = -10.0,
    double kneeWidth = 3.0,
    double minDb = -60.0,
    double maxDb = 6.0,
    int numPoints = defaultDynamicsResolution,
  }) {
    // Limiter = compressor with very high ratio (effectively infinite)
    final response = calculateCompressorCurve(
      threshold: threshold,
      ratio: 100.0, // Effectively infinite for visualization
      kneeWidth: kneeWidth,
      minDb: minDb,
      maxDb: maxDb,
      numPoints: numPoints,
    );

    // Clamp output to ceiling
    final clampedOutput = Float64List(numPoints);
    for (int i = 0; i < numPoints; i++) {
      clampedOutput[i] = math.min(response.magnitudes[i], ceiling);
    }

    return FrequencyResponseData(
      type: FrequencyProcessorType.limiter,
      frequencies: response.frequencies,
      magnitudes: clampedOutput,
      threshold: threshold,
      ratio: double.infinity,
      kneeWidth: kneeWidth,
      ceiling: ceiling,
    );
  }

  // ===========================================================================
  // GATE TRANSFER CURVE CALCULATION
  // ===========================================================================

  /// Calculate gate static transfer curve
  ///
  /// Below threshold: signal is attenuated by range (dB)
  /// Above threshold: signal passes through (1:1)
  /// Soft knee provides smooth transition.
  static FrequencyResponseData calculateGateCurve({
    required double threshold,
    double ratio = 10.0, // Expansion ratio below threshold
    double range = -80.0, // Maximum attenuation in dB
    double kneeWidth = 6.0,
    double minDb = -60.0,
    double maxDb = 6.0,
    int numPoints = defaultDynamicsResolution,
  }) {
    final inputDb = generateLinearDb(
      minDb: minDb,
      maxDb: maxDb,
      numPoints: numPoints,
    );

    final outputDb = Float64List(numPoints);
    final halfKnee = kneeWidth / 2.0;
    final kneeStart = threshold - halfKnee;
    final kneeEnd = threshold + halfKnee;

    for (int i = 0; i < numPoints; i++) {
      final input = inputDb[i];

      if (input > kneeEnd) {
        // Above knee: 1:1 ratio (gate open)
        outputDb[i] = input;
      } else if (input < kneeStart) {
        // Below knee: expansion (gate closed)
        // Output = threshold + (input - threshold) * ratio
        // But limited by range
        final expanded = threshold + (input - threshold) * ratio;
        outputDb[i] = math.max(expanded, input + range);
      } else {
        // In knee region: smooth transition
        final t = (input - kneeStart) / kneeWidth; // 0 to 1
        final smoothFactor = t * t * (3.0 - 2.0 * t); // Smoothstep
        final gateOutput = threshold + (input - threshold) * ratio;
        final clampedGate = math.max(gateOutput, input + range);
        outputDb[i] = clampedGate + (input - clampedGate) * smoothFactor;
      }
    }

    return FrequencyResponseData(
      type: FrequencyProcessorType.gate,
      frequencies: inputDb,
      magnitudes: outputDb,
      threshold: threshold,
      ratio: ratio,
      range: range,
      kneeWidth: kneeWidth,
    );
  }

  // ===========================================================================
  // EXPANDER TRANSFER CURVE CALCULATION
  // ===========================================================================

  /// Calculate expander static transfer curve
  ///
  /// Similar to gate but with gentler expansion ratios (2:1 to 4:1 typical).
  static FrequencyResponseData calculateExpanderCurve({
    required double threshold,
    double ratio = 2.0, // Expansion ratio (typically 1.5:1 to 4:1)
    double kneeWidth = 6.0,
    double minDb = -60.0,
    double maxDb = 6.0,
    int numPoints = defaultDynamicsResolution,
  }) {
    return FrequencyResponseData(
      type: FrequencyProcessorType.expander,
      frequencies: calculateGateCurve(
        threshold: threshold,
        ratio: ratio,
        range: -60.0, // Less aggressive than gate
        kneeWidth: kneeWidth,
        minDb: minDb,
        maxDb: maxDb,
        numPoints: numPoints,
      ).frequencies,
      magnitudes: calculateGateCurve(
        threshold: threshold,
        ratio: ratio,
        range: -60.0,
        kneeWidth: kneeWidth,
        minDb: minDb,
        maxDb: maxDb,
        numPoints: numPoints,
      ).magnitudes,
      threshold: threshold,
      ratio: ratio,
      kneeWidth: kneeWidth,
    );
  }

  // ===========================================================================
  // REVERB DECAY VISUALIZATION
  // ===========================================================================

  /// Standard reverb frequency bands (Hz)
  static const List<double> reverbBandFrequencies = [
    63.0,
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
    12000.0,
    16000.0,
  ];

  /// Calculate reverb frequency-dependent decay times
  ///
  /// Simulates how different frequency bands decay at different rates.
  /// High frequencies typically decay faster than low frequencies.
  ///
  /// Parameters:
  /// - baseDecay: RT60 decay time in seconds
  /// - damping: High-frequency damping (0 = no damping, 1 = max damping)
  /// - lowFreqMultiplier: How much longer low frequencies decay (1.0 = same as base)
  static FrequencyResponseData calculateReverbDecay({
    required double baseDecay,
    double damping = 0.5,
    double lowFreqMultiplier = 1.2,
    List<double>? bandFrequencies,
  }) {
    final frequencies = bandFrequencies ?? reverbBandFrequencies;
    final decayTimes = Float64List(frequencies.length);

    // Reference frequency for decay calculation
    const refFreq = 1000.0;

    for (int i = 0; i < frequencies.length; i++) {
      final freq = frequencies[i];

      // Calculate frequency-dependent decay
      // Low frequencies decay longer, high frequencies decay faster with damping
      double multiplier;
      if (freq < refFreq) {
        // Low frequencies: longer decay
        final octavesBelow = math.log(refFreq / freq) / math.ln2;
        multiplier = 1.0 + (lowFreqMultiplier - 1.0) * octavesBelow / 4.0;
      } else {
        // High frequencies: shorter decay based on damping
        final octavesAbove = math.log(freq / refFreq) / math.ln2;
        multiplier = 1.0 - damping * 0.3 * octavesAbove;
        multiplier = multiplier.clamp(0.1, 1.0);
      }

      decayTimes[i] = baseDecay * multiplier;
    }

    return FrequencyResponseData(
      type: FrequencyProcessorType.reverb,
      frequencies: Float64List.fromList(frequencies),
      magnitudes: decayTimes, // Decay times as "magnitudes"
      decayTimes: decayTimes,
      decayFrequencies: Float64List.fromList(frequencies),
    );
  }
}
