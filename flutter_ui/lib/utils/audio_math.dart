/// Audio Math Utilities
///
/// Common audio/DSP math functions used throughout the app.
/// Uses dart:math for accurate calculations.

import 'dart:math' as math;

/// Convert linear amplitude (0-1) to dB
double linearToDb(double linear) {
  if (linear <= 0) return double.negativeInfinity;
  return 20 * math.log(linear) / math.ln10;
}

/// Convert dB to linear amplitude (0-1)
double dbToLinear(double db) {
  if (db <= -120) return 0;
  return math.pow(10, db / 20).toDouble();
}

/// Log base 10
double log10(double x) {
  if (x <= 0) return double.negativeInfinity;
  return math.log(x) / math.ln10;
}

/// Power function
double pow(double base, double exponent) {
  return math.pow(base, exponent).toDouble();
}

/// Clamp value between min and max
double clampDb(double db, {double min = -120, double max = 6}) {
  return db.clamp(min, max);
}

/// Calculate equal power crossfade gain
/// position: 0.0 = full A, 1.0 = full B
(double gainA, double gainB) equalPowerCrossfade(double position) {
  final angleA = (1 - position) * math.pi / 2;
  final angleB = position * math.pi / 2;
  return (math.cos(angleA), math.cos(angleB));
}

/// Calculate RMS of samples
double calculateRms(List<double> samples) {
  if (samples.isEmpty) return 0;
  double sum = 0;
  for (final sample in samples) {
    sum += sample * sample;
  }
  return math.sqrt(sum / samples.length);
}

/// Calculate peak of samples
double calculatePeak(List<double> samples) {
  if (samples.isEmpty) return 0;
  double peak = 0;
  for (final sample in samples) {
    final abs = sample.abs();
    if (abs > peak) peak = abs;
  }
  return peak;
}

/// Normalize samples to target peak
void normalizeSamples(List<double> samples, double targetPeak) {
  final currentPeak = calculatePeak(samples);
  if (currentPeak <= 0) return;
  final ratio = targetPeak / currentPeak;
  for (int i = 0; i < samples.length; i++) {
    samples[i] *= ratio;
  }
}

/// Apply simple triangular dither
double applyDither(double sample, int targetBitDepth) {
  final quantizationStep = 1.0 / (1 << (targetBitDepth - 1));
  final dither = (_random.nextDouble() - 0.5) * quantizationStep;
  return sample + dither;
}

final _random = math.Random();

/// Frequency to MIDI note number
double frequencyToMidi(double frequency) {
  return 69 + 12 * log10(frequency / 440) / log10(2);
}

/// MIDI note number to frequency
double midiToFrequency(double midiNote) {
  return 440 * pow(2, (midiNote - 69) / 12);
}

/// Beat duration in seconds
double beatDuration(double tempo) {
  return 60 / tempo;
}

/// Bar duration in seconds
double barDuration(double tempo, int beatsPerBar) {
  return beatDuration(tempo) * beatsPerBar;
}
