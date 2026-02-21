/// Audio Math Utilities
///
/// Common audio/DSP math functions used throughout the app.
/// Uses dart:math for accurate calculations.

import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════
// FaderCurve — Neve/SSL/Harrison-class hybrid fader law
//
// ALL volume faders, knobs, and sliders in the app MUST use this class.
// Do NOT implement custom volume curves anywhere else.
//
// 5-Segment Hybrid Logarithmic Curve:
//   Segment 1 (Dead zone):  -∞  to -60 dB  →  0%–3%   fader travel
//   Segment 2 (Low):        -60 to -20 dB  →  3%–20%  fader travel
//   Segment 3 (Build-up):   -20 to -12 dB  →  20%–40% fader travel
//   Segment 4 (Sweet spot): -12 to  0  dB  →  40%–78% fader travel
//   Segment 5 (Boost):       0  to max dB  →  78%–100% fader travel
//
// Unity gain (0 dB) sits at 78% of fader travel.
//
// Design: Neve DFC + SSL Duality + Harrison Mixbus console curves.
// Sweet spot: 38% of travel for -12 to 0 dB (mixing range).
// Dead zone: Only 3% (vs 5% Cubase) — tighter silence→audible transition.
// ═══════════════════════════════════════════════════════════════════════════

class FaderCurve {
  FaderCurve._();

  // ── dB domain ──────────────────────────────────────────────────────────

  /// Convert dB value to fader position (0.0–1.0).
  /// [minDb] is the lowest representable dB (typically -60 or -80).
  /// [maxDb] is the highest representable dB (typically +6 or +12).
  static double dbToPosition(double db, {double minDb = -80.0, double maxDb = 12.0}) {
    if (db <= minDb) return 0.0;
    if (db >= maxDb) return 1.0;
    // Seg 1: Dead zone — -∞ to -60 dB → 0%–3%
    if (db <= -60.0) {
      return 0.03 * ((db - minDb) / (-60.0 - minDb)).clamp(0.0, 1.0);
    }
    // Seg 2: Low — -60 to -20 dB → 3%–20%
    if (db <= -20.0) {
      return 0.03 + 0.17 * ((db + 60.0) / 40.0);
    }
    // Seg 3: Build-up — -20 to -12 dB → 20%–40%
    if (db <= -12.0) {
      return 0.20 + 0.20 * ((db + 20.0) / 8.0);
    }
    // Seg 4: Sweet spot — -12 to 0 dB → 40%–78%
    if (db <= 0.0) {
      return 0.40 + 0.38 * ((db + 12.0) / 12.0);
    }
    // Seg 5: Boost — 0 to max dB → 78%–100%
    return 0.78 + 0.22 * (db / maxDb).clamp(0.0, 1.0);
  }

  /// Convert fader position (0.0–1.0) to dB value.
  static double positionToDb(double position, {double minDb = -80.0, double maxDb = 12.0}) {
    final p = position.clamp(0.0, 1.0);
    if (p <= 0.0) return minDb;
    if (p >= 1.0) return maxDb;
    // Seg 1: Dead zone — 0%–3% → -∞ to -60 dB
    if (p <= 0.03) {
      return minDb + (p / 0.03) * (-60.0 - minDb);
    }
    // Seg 2: Low — 3%–20% → -60 to -20 dB
    if (p <= 0.20) {
      return -60.0 + ((p - 0.03) / 0.17) * 40.0;
    }
    // Seg 3: Build-up — 20%–40% → -20 to -12 dB
    if (p <= 0.40) {
      return -20.0 + ((p - 0.20) / 0.20) * 8.0;
    }
    // Seg 4: Sweet spot — 40%–78% → -12 to 0 dB
    if (p <= 0.78) {
      return -12.0 + ((p - 0.40) / 0.38) * 12.0;
    }
    // Seg 5: Boost — 78%–100% → 0 to max dB
    return ((p - 0.78) / 0.22) * maxDb;
  }

  // ── Linear amplitude domain ────────────────────────────────────────────

  /// Convert linear amplitude (0.0–maxLinear) to fader position (0.0–1.0).
  /// Converts to dB internally, then uses the segmented curve.
  static double linearToPosition(double volume, {double maxLinear = 1.5}) {
    if (volume <= 0.0001) return 0.0;
    final db = 20.0 * math.log(volume) / math.ln10;
    final maxDb = 20.0 * math.log(maxLinear) / math.ln10; // +3.52 dB for 1.5
    return dbToPosition(db, maxDb: maxDb);
  }

  /// Convert fader position (0.0–1.0) to linear amplitude (0.0–maxLinear).
  static double positionToLinear(double position, {double maxLinear = 1.5}) {
    if (position <= 0.0) return 0.0;
    final maxDb = 20.0 * math.log(maxLinear) / math.ln10;
    final db = positionToDb(position, maxDb: maxDb);
    if (db <= -80.0) return 0.0;
    return math.pow(10.0, db / 20.0).toDouble().clamp(0.0, maxLinear);
  }

  // ── Display formatting ─────────────────────────────────────────────────

  /// Format linear amplitude as dB string for display.
  static String linearToDbString(double volume) {
    if (volume <= 0.001) return '-∞';
    final db = 20.0 * math.log(volume) / math.ln10;
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }

  /// Format dB value as string for display.
  static String dbToString(double db) {
    if (!db.isFinite || db <= -60) return '-∞';
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }
}

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
