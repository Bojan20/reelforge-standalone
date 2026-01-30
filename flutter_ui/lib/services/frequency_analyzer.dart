// frequency_analyzer.dart
// Real-time frequency response analysis for EQ visualization

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Frequency response point
class FrequencyPoint {
  final double frequency;
  final double gainDb;

  const FrequencyPoint(this.frequency, this.gainDb);
}

/// FFT analysis result
class FftAnalysisResult {
  final Float32List magnitudes;
  final int sampleRate;
  final int fftSize;

  const FftAnalysisResult({
    required this.magnitudes,
    required this.sampleRate,
    required this.fftSize,
  });

  double get frequencyResolution => sampleRate / fftSize.toDouble();

  double frequencyAt(int bin) => bin * frequencyResolution;

  double magnitudeAt(double frequency) {
    final bin = (frequency / frequencyResolution).round();
    if (bin < 0 || bin >= magnitudes.length) return 0.0;
    return magnitudes[bin];
  }
}

/// EQ band configuration
class EqBandConfig {
  final double frequency;
  final double gain;
  final double q;
  final String type;

  const EqBandConfig({
    required this.frequency,
    required this.gain,
    required this.q,
    required this.type,
  });
}

/// Frequency analyzer service
class FrequencyAnalyzer {
  static const int defaultFftSize = 8192;
  static const int defaultSampleRate = 48000;
  static const int numResponsePoints = 512;

  /// Calculate frequency response for EQ bands
  List<FrequencyPoint> calculateEqResponse({
    required List<EqBandConfig> bands,
    int numPoints = numResponsePoints,
    double minFreq = 20.0,
    double maxFreq = 20000.0,
  }) {
    final points = <FrequencyPoint>[];

    for (int i = 0; i < numPoints; i++) {
      // Logarithmic frequency spacing
      final t = i / (numPoints - 1);
      final freq = minFreq * math.pow(maxFreq / minFreq, t);

      // Calculate combined response
      double totalGainDb = 0.0;
      for (final band in bands) {
        totalGainDb += _calculateBandResponse(band, freq);
      }

      points.add(FrequencyPoint(freq, totalGainDb));
    }

    return points;
  }

  /// Calculate biquad filter response at frequency
  double _calculateBandResponse(EqBandConfig band, double frequency) {
    final omega = 2 * math.pi * frequency;
    final omega0 = 2 * math.pi * band.frequency;
    final alpha = math.sin(omega0) / (2 * band.q);

    // Biquad coefficients (simplified for bell filter)
    final a = math.pow(10, band.gain / 40); // Linear gain
    final b0 = 1 + alpha * a;
    final b1 = -2 * math.cos(omega0);
    final b2 = 1 - alpha * a;
    final a0 = 1 + alpha / a;
    final a1 = -2 * math.cos(omega0);
    final a2 = 1 - alpha / a;

    // Frequency response
    final cosW = math.cos(omega);
    final sinW = math.sin(omega);
    final cos2W = math.cos(2 * omega);
    final sin2W = math.sin(2 * omega);

    final numReal = b0 + b1 * cosW + b2 * cos2W;
    final numImag = b1 * sinW + b2 * sin2W;
    final denReal = a0 + a1 * cosW + a2 * cos2W;
    final denImag = a1 * sinW + a2 * sin2W;

    final numMag = math.sqrt(numReal * numReal + numImag * numImag);
    final denMag = math.sqrt(denReal * denReal + denImag * denImag);

    final magnitude = numMag / denMag;
    return 20 * math.log(magnitude) / math.ln10;
  }

  /// Analyze FFT data
  FftAnalysisResult analyzeFFT({
    required Float32List samples,
    int sampleRate = defaultSampleRate,
  }) {
    final fftSize = samples.length;
    final magnitudes = Float32List(fftSize ~/ 2);

    // Simple magnitude calculation (real FFT would use proper FFT algorithm)
    for (int i = 0; i < magnitudes.length; i++) {
      magnitudes[i] = samples[i].abs();
    }

    return FftAnalysisResult(
      magnitudes: magnitudes,
      sampleRate: sampleRate,
      fftSize: fftSize,
    );
  }

  /// Create frequency response path for drawing
  ui.Path createResponsePath({
    required List<FrequencyPoint> points,
    required double width,
    required double height,
    double minFreq = 20.0,
    double maxFreq = 20000.0,
    double minDb = -24.0,
    double maxDb = 24.0,
  }) {
    final path = ui.Path();

    if (points.isEmpty) return path;

    // First point
    final firstPoint = points.first;
    final firstX = _frequencyToX(firstPoint.frequency, width, minFreq, maxFreq);
    final firstY = _dbToY(firstPoint.gainDb, height, minDb, maxDb);
    path.moveTo(firstX, firstY);

    // Remaining points
    for (int i = 1; i < points.length; i++) {
      final point = points[i];
      final x = _frequencyToX(point.frequency, width, minFreq, maxFreq);
      final y = _dbToY(point.gainDb, height, minDb, maxDb);
      path.lineTo(x, y);
    }

    return path;
  }

  /// Convert frequency to X coordinate (logarithmic)
  double _frequencyToX(double freq, double width, double minFreq, double maxFreq) {
    final logMin = math.log(minFreq) / math.ln10;
    final logMax = math.log(maxFreq) / math.ln10;
    final logFreq = math.log(freq) / math.ln10;
    return ((logFreq - logMin) / (logMax - logMin)) * width;
  }

  /// Convert dB to Y coordinate (linear)
  double _dbToY(double db, double height, double minDb, double maxDb) {
    final normalized = (db - minDb) / (maxDb - minDb);
    return height - (normalized * height);
  }

  /// Generate frequency grid points
  List<double> generateFrequencyGrid({
    double minFreq = 20.0,
    double maxFreq = 20000.0,
  }) {
    return [
      20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0,
      100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0,
      1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7000.0, 8000.0, 9000.0,
      10000.0, 20000.0,
    ].where((f) => f >= minFreq && f <= maxFreq).toList();
  }

  /// Generate dB grid points
  List<double> generateDbGrid({
    double minDb = -24.0,
    double maxDb = 24.0,
    double step = 6.0,
  }) {
    final grid = <double>[];
    double current = (minDb / step).ceil() * step;

    while (current <= maxDb) {
      grid.add(current);
      current += step;
    }

    return grid;
  }

  /// Format frequency for display
  String formatFrequency(double freq) {
    if (freq < 1000) {
      return '${freq.round()}Hz';
    } else {
      return '${(freq / 1000).toStringAsFixed(1)}kHz';
    }
  }

  /// Format dB for display
  String formatDb(double db) {
    return '${db >= 0 ? "+" : ""}${db.toStringAsFixed(1)}dB';
  }

  /// Calculate phase response (simplified)
  List<FrequencyPoint> calculatePhaseResponse({
    required List<EqBandConfig> bands,
    int numPoints = numResponsePoints,
    double minFreq = 20.0,
    double maxFreq = 20000.0,
  }) {
    final points = <FrequencyPoint>[];

    for (int i = 0; i < numPoints; i++) {
      final t = i / (numPoints - 1);
      final freq = minFreq * math.pow(maxFreq / minFreq, t);

      // Simplified phase calculation
      double totalPhase = 0.0;
      for (final band in bands) {
        totalPhase += _calculateBandPhase(band, freq);
      }

      points.add(FrequencyPoint(freq, totalPhase));
    }

    return points;
  }

  double _calculateBandPhase(EqBandConfig band, double frequency) {
    final omega = 2 * math.pi * frequency;
    final omega0 = 2 * math.pi * band.frequency;

    // Simplified phase response
    if (frequency < band.frequency) {
      return -math.atan((frequency / band.frequency - 1) * band.q);
    } else {
      return math.atan((band.frequency / frequency - 1) * band.q);
    }
  }

  /// Detect resonance peaks
  List<FrequencyPoint> detectResonancePeaks({
    required List<FrequencyPoint> response,
    double threshold = 3.0, // dB
  }) {
    final peaks = <FrequencyPoint>[];

    for (int i = 1; i < response.length - 1; i++) {
      final prev = response[i - 1];
      final curr = response[i];
      final next = response[i + 1];

      // Peak detection
      if (curr.gainDb > prev.gainDb &&
          curr.gainDb > next.gainDb &&
          curr.gainDb >= threshold) {
        peaks.add(curr);
      }
    }

    return peaks;
  }

  /// Calculate total harmonic distortion (THD) estimate
  double calculateThdEstimate({
    required List<EqBandConfig> bands,
    double frequency = 1000.0,
  }) {
    // Simplified THD estimation based on gain amounts
    double totalGain = 0.0;
    for (final band in bands) {
      totalGain += band.gain.abs();
    }

    // Rough estimate: 0.1% THD per 12dB of gain
    return (totalGain / 12.0) * 0.1;
  }
}
