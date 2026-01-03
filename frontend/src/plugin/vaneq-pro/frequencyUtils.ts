/**
 * VanEQ Pro - Frequency Utilities
 *
 * Centralized frequency/dB/Q mapping functions used across VanEQ components.
 * Eliminates duplicate code between EQGraph, SpectrumCanvas, and buildSpectrumPath.
 *
 * @module plugin/vaneq-pro/frequencyUtils
 */

// ============ Audio Range Constants ============

/** Minimum audible frequency (Hz) */
export const FREQ_MIN = 20;

/** Maximum audible frequency (Hz) */
export const FREQ_MAX = 20000;

/** Number of octaves in audible range (log2(20000/20) ≈ 10) */
export const AUDIBLE_OCTAVES = Math.log2(FREQ_MAX / FREQ_MIN);

// ============ Display Range Constants ============

/** Default dB display minimum for EQ graphs */
export const DB_MIN = -24;

/** Default dB display maximum for EQ graphs */
export const DB_MAX = 24;

/** Default dB range for spectrum analyzer */
export const SPECTRUM_DB_MIN = -90;

/** Default dB range for spectrum analyzer */
export const SPECTRUM_DB_MAX = -12;

// ============ Q Factor Constants ============

/** Minimum Q value */
export const Q_MIN = 0.1;

/** Maximum Q value */
export const Q_MAX = 24;

/** Default Q value (Butterworth) */
export const Q_DEFAULT = 0.707;

/** Perceptual Q exponent for musical feel */
export const Q_PERCEPTUAL_EXPONENT = 1.15;

// ============ DSP Constants ============

/** Default sample rate (Hz) */
export const SAMPLE_RATE_DEFAULT = 48000;

/** dB to linear conversion shortcut */
export const DB_TO_LINEAR = (db: number): number => Math.pow(10, db / 20);

/** Linear to dB conversion shortcut */
export const LINEAR_TO_DB = (linear: number): number =>
  linear <= 0 ? -100 : 20 * Math.log10(linear);

// ============ Frequency Mapping Functions ============

/**
 * Convert frequency to X coordinate (logarithmic mapping).
 *
 * Human hearing is logarithmic - we perceive pitch in octaves.
 * An octave is a 2:1 frequency ratio. From 20Hz to 20kHz is ~10 octaves.
 * Linear mapping would compress bass and expand highs unnaturally.
 * Log mapping gives equal screen space to each octave - "musical" feel.
 *
 * @param freq - Frequency in Hz
 * @param width - Graph width in pixels
 * @param minFreq - Minimum frequency (default: FREQ_MIN)
 * @param maxFreq - Maximum frequency (default: FREQ_MAX)
 * @returns X coordinate in pixels
 */
export function freqToX(
  freq: number,
  width: number,
  minFreq: number = FREQ_MIN,
  maxFreq: number = FREQ_MAX
): number {
  const logMin = Math.log10(minFreq);
  const logMax = Math.log10(maxFreq);
  const logFreq = Math.log10(clamp(freq, minFreq, maxFreq));
  return ((logFreq - logMin) / (logMax - logMin)) * width;
}

/**
 * Convert X coordinate to frequency (inverse logarithmic mapping).
 *
 * @param x - X coordinate in pixels
 * @param width - Graph width in pixels
 * @param minFreq - Minimum frequency (default: FREQ_MIN)
 * @param maxFreq - Maximum frequency (default: FREQ_MAX)
 * @returns Frequency in Hz
 */
export function xToFreq(
  x: number,
  width: number,
  minFreq: number = FREQ_MIN,
  maxFreq: number = FREQ_MAX
): number {
  const logMin = Math.log10(minFreq);
  const logMax = Math.log10(maxFreq);
  const ratio = clamp(x / width, 0, 1);
  return Math.pow(10, logMin + ratio * (logMax - logMin));
}

// ============ dB Mapping Functions ============

/**
 * Convert dB to Y coordinate (linear mapping, inverted for screen).
 *
 * @param db - Decibel value
 * @param height - Graph height in pixels
 * @param minDb - Minimum dB (default: DB_MIN)
 * @param maxDb - Maximum dB (default: DB_MAX)
 * @returns Y coordinate in pixels (0 = top = maxDb)
 */
export function dbToY(
  db: number,
  height: number,
  minDb: number = DB_MIN,
  maxDb: number = DB_MAX
): number {
  const ratio = (maxDb - clamp(db, minDb, maxDb)) / (maxDb - minDb);
  return ratio * height;
}

/**
 * Convert Y coordinate to dB (inverse linear mapping).
 *
 * @param y - Y coordinate in pixels
 * @param height - Graph height in pixels
 * @param minDb - Minimum dB (default: DB_MIN)
 * @param maxDb - Maximum dB (default: DB_MAX)
 * @returns dB value
 */
export function yToDb(
  y: number,
  height: number,
  minDb: number = DB_MIN,
  maxDb: number = DB_MAX
): number {
  const ratio = clamp(y / height, 0, 1);
  return maxDb - ratio * (maxDb - minDb);
}

// ============ FFT Bin Mapping Functions ============

/**
 * Calculate FFT bin index for a given frequency.
 *
 * @param freq - Frequency in Hz
 * @param fftSize - FFT size (e.g., 2048)
 * @param sampleRate - Sample rate in Hz
 * @returns Bin index (clamped to valid range)
 */
export function freqToBin(
  freq: number,
  fftSize: number,
  sampleRate: number
): number {
  const binCount = fftSize / 2;
  const binWidth = sampleRate / fftSize;
  const bin = Math.round(freq / binWidth);
  return clamp(bin, 0, binCount - 1);
}

/**
 * Calculate frequency for a given FFT bin index.
 *
 * @param bin - Bin index
 * @param fftSize - FFT size (e.g., 2048)
 * @param sampleRate - Sample rate in Hz
 * @returns Frequency in Hz
 */
export function binToFreq(
  bin: number,
  fftSize: number,
  sampleRate: number
): number {
  const binWidth = sampleRate / fftSize;
  return bin * binWidth;
}

// ============ Q Factor Functions ============

/**
 * Apply perceptual Q mapping for musical feel.
 *
 * Raw Q values are linear but musical perception is logarithmic.
 * Q=1 feels "normal", Q=10 feels "narrow", Q=0.5 feels "wide".
 * A pow(q, 1.15) curve gives more control at musical values (0.5-4)
 * while still allowing surgical narrow bands (10+).
 *
 * @param qUi - UI Q value (0.1 to 24)
 * @returns DSP Q value with perceptual mapping applied
 */
export function applyPerceptualQ(qUi: number): number {
  return Math.pow(clamp(qUi, Q_MIN, Q_MAX), Q_PERCEPTUAL_EXPONENT);
}

/**
 * Convert bandwidth in octaves to Q factor.
 *
 * @param octaves - Bandwidth in octaves
 * @returns Q factor
 */
export function octavesToQ(octaves: number): number {
  const pow2 = Math.pow(2, octaves);
  return Math.sqrt(pow2) / (pow2 - 1);
}

/**
 * Convert Q factor to bandwidth in octaves.
 *
 * @param q - Q factor
 * @returns Bandwidth in octaves
 */
export function qToOctaves(q: number): number {
  return (2 / Math.LN2) * Math.asinh(1 / (2 * q));
}

// ============ Utility Functions ============

/**
 * Clamp a value between min and max.
 *
 * @param value - Value to clamp
 * @param min - Minimum value
 * @param max - Maximum value
 * @returns Clamped value
 */
export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Linear interpolation between two values.
 *
 * @param a - Start value
 * @param b - End value
 * @param t - Interpolation factor (0 to 1)
 * @returns Interpolated value
 */
export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/**
 * Map a value from one range to another.
 *
 * @param value - Input value
 * @param inMin - Input range minimum
 * @param inMax - Input range maximum
 * @param outMin - Output range minimum
 * @param outMax - Output range maximum
 * @returns Mapped value
 */
export function mapRange(
  value: number,
  inMin: number,
  inMax: number,
  outMin: number,
  outMax: number
): number {
  const t = (value - inMin) / (inMax - inMin);
  return lerp(outMin, outMax, t);
}

// ============ Formatting Functions ============

/**
 * Format frequency for display (e.g., "1.5k", "200").
 *
 * @param hz - Frequency in Hz
 * @returns Formatted string
 */
export function formatFreq(hz: number): string {
  if (hz >= 10000) return `${(hz / 1000).toFixed(1)}k`;
  if (hz >= 1000) return `${(hz / 1000).toFixed(2)}k`;
  return hz.toFixed(0);
}

/**
 * Format dB for display (e.g., "+3.0", "-6.0").
 *
 * @param db - Decibel value
 * @returns Formatted string with sign
 */
export function formatDb(db: number): string {
  const sign = db >= 0 ? '+' : '';
  return `${sign}${db.toFixed(1)} dB`;
}

/**
 * Format Q for display (e.g., "Q 1.41").
 *
 * @param q - Q factor
 * @returns Formatted string
 */
export function formatQ(q: number): string {
  return `Q ${q.toFixed(2)}`;
}
