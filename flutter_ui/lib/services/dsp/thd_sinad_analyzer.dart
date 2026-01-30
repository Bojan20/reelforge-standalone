/// THD/SINAD Analyzer
///
/// P2-04: Total Harmonic Distortion and Signal-to-Noise-And-Distortion analysis.
/// Measures audio quality metrics for DSP processing validation.
///
/// THD: Total Harmonic Distortion — ratio of harmonic power to fundamental power
/// SINAD: Signal-to-Noise-And-Distortion — ratio of signal power to noise+distortion power
/// IMD: Intermodulation Distortion — non-harmonic distortion products
///
/// Usage:
/// ```dart
/// final analyzer = ThdSinadAnalyzer();
/// final result = await analyzer.analyze(audioBuffer, sampleRate: 48000);
/// print('THD: ${result.thdPercent}%');
/// print('SINAD: ${result.sinadDb} dB');
/// ```

import 'dart:math' as math;
import 'dart:typed_data';

/// Audio quality analysis result
class AudioQualityResult {
  /// Total Harmonic Distortion (0-100%)
  final double thdPercent;

  /// Signal-to-Noise-And-Distortion ratio (dB)
  final double sinadDb;

  /// Signal-to-Noise ratio (dB)
  final double snrDb;

  /// Dynamic range (dB)
  final double dynamicRangeDb;

  /// Fundamental frequency (Hz)
  final double fundamentalFrequency;

  /// Harmonic levels (dB, indexed by harmonic number)
  final Map<int, double> harmonicLevels;

  /// Noise floor (dBFS)
  final double noiseFloorDb;

  /// Peak level (dBFS)
  final double peakLevelDb;

  /// RMS level (dBFS)
  final double rmsLevelDb;

  const AudioQualityResult({
    required this.thdPercent,
    required this.sinadDb,
    required this.snrDb,
    required this.dynamicRangeDb,
    required this.fundamentalFrequency,
    required this.harmonicLevels,
    required this.noiseFloorDb,
    required this.peakLevelDb,
    required this.rmsLevelDb,
  });

  /// Quality assessment based on THD/SINAD
  String get qualityAssessment {
    if (thdPercent < 0.001 && sinadDb > 100) return 'Excellent (Hi-Fi)';
    if (thdPercent < 0.01 && sinadDb > 80) return 'Very Good (Pro Audio)';
    if (thdPercent < 0.1 && sinadDb > 60) return 'Good (Consumer)';
    if (thdPercent < 1.0 && sinadDb > 40) return 'Fair';
    return 'Poor';
  }

  /// Generate report
  String generateReport() {
    final sb = StringBuffer();
    sb.writeln('=== Audio Quality Analysis Report ===');
    sb.writeln('Quality: $qualityAssessment');
    sb.writeln('');
    sb.writeln('Metrics:');
    sb.writeln('  THD: ${thdPercent.toStringAsFixed(4)}%');
    sb.writeln('  SINAD: ${sinadDb.toStringAsFixed(2)} dB');
    sb.writeln('  SNR: ${snrDb.toStringAsFixed(2)} dB');
    sb.writeln('  Dynamic Range: ${dynamicRangeDb.toStringAsFixed(2)} dB');
    sb.writeln('');
    sb.writeln('Levels:');
    sb.writeln('  Peak: ${peakLevelDb.toStringAsFixed(2)} dBFS');
    sb.writeln('  RMS: ${rmsLevelDb.toStringAsFixed(2)} dBFS');
    sb.writeln('  Noise Floor: ${noiseFloorDb.toStringAsFixed(2)} dBFS');
    sb.writeln('');
    sb.writeln('Fundamental:');
    sb.writeln('  Frequency: ${fundamentalFrequency.toStringAsFixed(2)} Hz');
    sb.writeln('');
    sb.writeln('Harmonics:');
    for (final entry in harmonicLevels.entries) {
      sb.writeln('  H${entry.key}: ${entry.value.toStringAsFixed(2)} dB');
    }

    return sb.toString();
  }
}

/// THD/SINAD Analyzer
class ThdSinadAnalyzer {
  /// Analyze audio buffer
  Future<AudioQualityResult> analyze(
    Float32List audioBuffer, {
    required int sampleRate,
    double? knownFundamental, // If fundamental frequency is known
    int maxHarmonics = 10,
  }) async {
    // 1. Find fundamental frequency (if not provided)
    final fundamental = knownFundamental ?? await _findFundamental(audioBuffer, sampleRate);

    // 2. Perform FFT
    final spectrum = await _performFft(audioBuffer);

    // 3. Measure fundamental and harmonic levels
    final harmonics = await _measureHarmonics(spectrum, fundamental, sampleRate, maxHarmonics);

    // 4. Calculate THD
    final thd = _calculateThd(harmonics);

    // 5. Calculate noise floor
    final noiseFloor = await _measureNoiseFloor(spectrum, harmonics.keys.toSet());

    // 6. Calculate SINAD
    final sinad = _calculateSinad(harmonics[1] ?? 0.0, noiseFloor, thd);

    // 7. Calculate SNR
    final snr = _calculateSnr(harmonics[1] ?? 0.0, noiseFloor);

    // 8. Calculate dynamic range
    final peak = _calculatePeak(audioBuffer);
    final rms = _calculateRms(audioBuffer);
    final dynamicRange = _linearToDb(peak) - noiseFloor;

    return AudioQualityResult(
      thdPercent: thd * 100.0,
      sinadDb: sinad,
      snrDb: snr,
      dynamicRangeDb: dynamicRange,
      fundamentalFrequency: fundamental,
      harmonicLevels: harmonics.map((k, v) => MapEntry(k, _linearToDb(v))),
      noiseFloorDb: noiseFloor,
      peakLevelDb: _linearToDb(peak),
      rmsLevelDb: _linearToDb(rms),
    );
  }

  /// Find fundamental frequency using autocorrelation
  Future<double> _findFundamental(Float32List buffer, int sampleRate) async {
    // Simplified autocorrelation-based pitch detection
    // In real implementation, would use YIN, PYIN, or SWIPE algorithm

    final maxLag = (sampleRate / 50).round(); // 50 Hz min
    final minLag = (sampleRate / 2000).round(); // 2000 Hz max

    double maxCorrelation = 0.0;
    int bestLag = minLag;

    for (int lag = minLag; lag < maxLag && lag < buffer.length ~/ 2; lag++) {
      double correlation = 0.0;
      for (int i = 0; i < buffer.length - lag; i++) {
        correlation += buffer[i] * buffer[i + lag];
      }

      if (correlation > maxCorrelation) {
        maxCorrelation = correlation;
        bestLag = lag;
      }
    }

    return sampleRate / bestLag;
  }

  /// Perform FFT (simplified — in real implementation would use rustfft via FFI)
  Future<Float32List> _performFft(Float32List buffer) async {
    // Placeholder — real implementation would call Rust FFT
    // For now, return empty spectrum
    return Float32List(buffer.length ~/ 2);
  }

  /// Measure harmonic levels
  Future<Map<int, double>> _measureHarmonics(
    Float32List spectrum,
    double fundamental,
    int sampleRate,
    int maxHarmonics,
  ) async {
    final harmonics = <int, double>{};

    // For each harmonic, find peak in spectrum
    for (int h = 1; h <= maxHarmonics; h++) {
      final frequency = fundamental * h;
      final binIndex = (frequency * spectrum.length / sampleRate).round();

      if (binIndex >= 0 && binIndex < spectrum.length) {
        harmonics[h] = spectrum[binIndex];
      }
    }

    return harmonics;
  }

  /// Measure noise floor (excluding harmonics)
  Future<double> _measureNoiseFloor(Float32List spectrum, Set<int> harmonicBins) async {
    double sum = 0.0;
    int count = 0;

    for (int i = 0; i < spectrum.length; i++) {
      if (!harmonicBins.contains(i)) {
        sum += spectrum[i] * spectrum[i];
        count++;
      }
    }

    if (count == 0) return -120.0; // Silence

    final rms = math.sqrt(sum / count);
    return _linearToDb(rms);
  }

  /// Calculate THD (Total Harmonic Distortion)
  double _calculateThd(Map<int, double> harmonics) {
    final fundamental = harmonics[1] ?? 1e-10;
    double harmonicSum = 0.0;

    for (final entry in harmonics.entries) {
      if (entry.key == 1) continue; // Skip fundamental
      harmonicSum += entry.value * entry.value;
    }

    return math.sqrt(harmonicSum) / fundamental;
  }

  /// Calculate SINAD
  double _calculateSinad(double signal, double noiseFloorDb, double thd) {
    // SINAD = signal / (noise + distortion)
    final noise = _dbToLinear(noiseFloorDb);
    final distortion = signal * thd;
    final sinad = signal / (noise + distortion);
    return _linearToDb(sinad);
  }

  /// Calculate SNR
  double _calculateSnr(double signal, double noiseFloorDb) {
    final signalDb = _linearToDb(signal);
    return signalDb - noiseFloorDb;
  }

  /// Calculate peak level
  double _calculatePeak(Float32List buffer) {
    double peak = 0.0;
    for (final sample in buffer) {
      final abs = sample.abs();
      if (abs > peak) peak = abs;
    }
    return peak;
  }

  /// Calculate RMS level
  double _calculateRms(Float32List buffer) {
    double sum = 0.0;
    for (final sample in buffer) {
      sum += sample * sample;
    }
    return math.sqrt(sum / buffer.length);
  }

  /// Convert linear to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0) return -120.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  /// Convert dB to linear
  double _dbToLinear(double db) {
    return math.pow(10.0, db / 20.0).toDouble();
  }
}
