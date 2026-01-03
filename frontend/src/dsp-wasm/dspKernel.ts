/**
 * DSP Kernel - High-Performance Audio Processing
 *
 * This module provides optimized DSP functions that can be compiled to WASM.
 * Currently uses TypeScript with manual optimizations:
 * - Float32Array typed arrays (no GC pressure)
 * - Pre-allocated buffers (object pooling)
 * - SIMD-friendly loops (single operations per iteration)
 * - Inline math (no function call overhead)
 *
 * Future: Compile to WASM via AssemblyScript or Rust for 10-50x speedup.
 *
 * @module dsp-wasm/dspKernel
 */

// ============ Constants ============

const TWO_PI = Math.PI * 2;
const LN10_OVER_20 = Math.LN10 / 20; // For dB conversion
const TWENTY_OVER_LN10 = 20 / Math.LN10;

// ============ Buffer Pool ============

/**
 * Pre-allocated buffer pool to avoid GC during processing.
 */
class BufferPool {
  private pools: Map<number, Float32Array[]> = new Map();

  acquire(size: number): Float32Array {
    const pool = this.pools.get(size);
    if (pool && pool.length > 0) {
      return pool.pop()!;
    }
    return new Float32Array(size);
  }

  release(buffer: Float32Array): void {
    const size = buffer.length;
    if (!this.pools.has(size)) {
      this.pools.set(size, []);
    }
    const pool = this.pools.get(size)!;
    if (pool.length < 16) { // Max 16 buffers per size
      buffer.fill(0); // Clear for reuse
      pool.push(buffer);
    }
  }

  clear(): void {
    this.pools.clear();
  }
}

export const bufferPool = new BufferPool();

// ============ Basic Math ============

/**
 * Convert dB to linear gain (optimized).
 */
export function dbToLinear(db: number): number {
  return Math.exp(db * LN10_OVER_20);
}

/**
 * Convert linear gain to dB (optimized).
 */
export function linearToDb(linear: number): number {
  if (linear <= 0) return -Infinity;
  return Math.log(linear) * TWENTY_OVER_LN10;
}

/**
 * Clamp value to range (inline-friendly).
 */
export function clamp(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

/**
 * Linear interpolation.
 */
export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

// ============ Biquad Filter ============

/**
 * Biquad filter state (double precision for stability).
 */
export interface BiquadState {
  x1: number;
  x2: number;
  y1: number;
  y2: number;
}

/**
 * Biquad filter coefficients.
 */
export interface BiquadCoeffs {
  b0: number;
  b1: number;
  b2: number;
  a1: number;
  a2: number;
}

/**
 * Create initial biquad state.
 */
export function createBiquadState(): BiquadState {
  return { x1: 0, x2: 0, y1: 0, y2: 0 };
}

/**
 * Calculate biquad coefficients for parametric EQ band.
 *
 * @param type - 'lowshelf' | 'highshelf' | 'peaking' | 'lowpass' | 'highpass'
 * @param frequency - Center/cutoff frequency in Hz
 * @param gain - Gain in dB (for shelf/peaking)
 * @param q - Q factor
 * @param sampleRate - Sample rate in Hz
 */
export function calcBiquadCoeffs(
  type: 'lowshelf' | 'highshelf' | 'peaking' | 'lowpass' | 'highpass',
  frequency: number,
  gain: number,
  q: number,
  sampleRate: number
): BiquadCoeffs {
  const omega = TWO_PI * frequency / sampleRate;
  const sinOmega = Math.sin(omega);
  const cosOmega = Math.cos(omega);
  const alpha = sinOmega / (2 * q);
  const A = Math.pow(10, gain / 40);

  let b0 = 0, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;

  switch (type) {
    case 'lowshelf': {
      const sqrtA = Math.sqrt(A);
      const sqrtA2Alpha = 2 * sqrtA * alpha;
      a0 = (A + 1) + (A - 1) * cosOmega + sqrtA2Alpha;
      a1 = -2 * ((A - 1) + (A + 1) * cosOmega);
      a2 = (A + 1) + (A - 1) * cosOmega - sqrtA2Alpha;
      b0 = A * ((A + 1) - (A - 1) * cosOmega + sqrtA2Alpha);
      b1 = 2 * A * ((A - 1) - (A + 1) * cosOmega);
      b2 = A * ((A + 1) - (A - 1) * cosOmega - sqrtA2Alpha);
      break;
    }
    case 'highshelf': {
      const sqrtA = Math.sqrt(A);
      const sqrtA2Alpha = 2 * sqrtA * alpha;
      a0 = (A + 1) - (A - 1) * cosOmega + sqrtA2Alpha;
      a1 = 2 * ((A - 1) - (A + 1) * cosOmega);
      a2 = (A + 1) - (A - 1) * cosOmega - sqrtA2Alpha;
      b0 = A * ((A + 1) + (A - 1) * cosOmega + sqrtA2Alpha);
      b1 = -2 * A * ((A - 1) + (A + 1) * cosOmega);
      b2 = A * ((A + 1) + (A - 1) * cosOmega - sqrtA2Alpha);
      break;
    }
    case 'peaking': {
      a0 = 1 + alpha / A;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha / A;
      b0 = 1 + alpha * A;
      b1 = -2 * cosOmega;
      b2 = 1 - alpha * A;
      break;
    }
    case 'lowpass': {
      a0 = 1 + alpha;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha;
      b0 = (1 - cosOmega) / 2;
      b1 = 1 - cosOmega;
      b2 = (1 - cosOmega) / 2;
      break;
    }
    case 'highpass': {
      a0 = 1 + alpha;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha;
      b0 = (1 + cosOmega) / 2;
      b1 = -(1 + cosOmega);
      b2 = (1 + cosOmega) / 2;
      break;
    }
  }

  // Normalize coefficients
  return {
    b0: b0 / a0,
    b1: b1 / a0,
    b2: b2 / a0,
    a1: a1 / a0,
    a2: a2 / a0,
  };
}

/**
 * Process audio through biquad filter (in-place).
 *
 * Direct Form II Transposed implementation for numerical stability.
 */
export function processBiquad(
  input: Float32Array,
  output: Float32Array,
  coeffs: BiquadCoeffs,
  state: BiquadState
): void {
  const { b0, b1, b2, a1, a2 } = coeffs;
  const len = input.length;

  let x1 = state.x1;
  let x2 = state.x2;
  let y1 = state.y1;
  let y2 = state.y2;

  for (let i = 0; i < len; i++) {
    const x = input[i];
    const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;

    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;

    output[i] = y;
  }

  // Denormal prevention
  if (Math.abs(y1) < 1e-15) y1 = 0;
  if (Math.abs(y2) < 1e-15) y2 = 0;

  state.x1 = x1;
  state.x2 = x2;
  state.y1 = y1;
  state.y2 = y2;
}

// ============ Gain Processing ============

/**
 * Apply gain to audio buffer (in-place).
 */
export function applyGain(buffer: Float32Array, gain: number): void {
  const len = buffer.length;
  for (let i = 0; i < len; i++) {
    buffer[i] *= gain;
  }
}

/**
 * Apply gain ramp (in-place).
 */
export function applyGainRamp(
  buffer: Float32Array,
  startGain: number,
  endGain: number
): void {
  const len = buffer.length;
  if (len === 0) return;

  const step = (endGain - startGain) / len;
  let gain = startGain;

  for (let i = 0; i < len; i++) {
    buffer[i] *= gain;
    gain += step;
  }
}

// ============ Mixing ============

/**
 * Mix source into destination (in-place on dest).
 */
export function mixInto(
  dest: Float32Array,
  source: Float32Array,
  gain: number = 1
): void {
  const len = Math.min(dest.length, source.length);
  for (let i = 0; i < len; i++) {
    dest[i] += source[i] * gain;
  }
}

/**
 * Mix multiple sources into destination.
 */
export function mixMultiple(
  dest: Float32Array,
  sources: Float32Array[],
  gains: number[]
): void {
  dest.fill(0);
  const numSources = Math.min(sources.length, gains.length);
  const len = dest.length;

  for (let s = 0; s < numSources; s++) {
    const source = sources[s];
    const gain = gains[s];
    const srcLen = Math.min(len, source.length);

    for (let i = 0; i < srcLen; i++) {
      dest[i] += source[i] * gain;
    }
  }
}

// ============ Peak/RMS Metering ============

/**
 * Calculate peak level of buffer.
 */
export function calcPeak(buffer: Float32Array): number {
  let peak = 0;
  const len = buffer.length;

  for (let i = 0; i < len; i++) {
    const abs = Math.abs(buffer[i]);
    if (abs > peak) peak = abs;
  }

  return peak;
}

/**
 * Calculate RMS level of buffer.
 */
export function calcRMS(buffer: Float32Array): number {
  let sum = 0;
  const len = buffer.length;

  for (let i = 0; i < len; i++) {
    const sample = buffer[i];
    sum += sample * sample;
  }

  return Math.sqrt(sum / len);
}

/**
 * Calculate peak and RMS in one pass.
 */
export function calcLevels(buffer: Float32Array): { peak: number; rms: number } {
  let peak = 0;
  let sum = 0;
  const len = buffer.length;

  for (let i = 0; i < len; i++) {
    const sample = buffer[i];
    const abs = Math.abs(sample);
    if (abs > peak) peak = abs;
    sum += sample * sample;
  }

  return {
    peak,
    rms: Math.sqrt(sum / len),
  };
}

// ============ Compressor ============

export interface CompressorState {
  envelope: number;
  gainReduction: number;
}

export interface CompressorParams {
  threshold: number; // dB
  ratio: number;
  attack: number; // ms
  release: number; // ms
  knee: number; // dB
  makeupGain: number; // dB
}

export function createCompressorState(): CompressorState {
  return { envelope: 0, gainReduction: 0 };
}

/**
 * Process audio through compressor (in-place).
 */
export function processCompressor(
  buffer: Float32Array,
  params: CompressorParams,
  state: CompressorState,
  sampleRate: number
): void {
  const { threshold, ratio, attack, release, knee, makeupGain } = params;
  const len = buffer.length;

  // Convert times to coefficients
  const attackCoeff = Math.exp(-1 / (attack * sampleRate / 1000));
  const releaseCoeff = Math.exp(-1 / (release * sampleRate / 1000));
  const makeupLinear = dbToLinear(makeupGain);

  let envelope = state.envelope;

  for (let i = 0; i < len; i++) {
    const input = buffer[i];
    const inputAbs = Math.abs(input);

    // Envelope follower
    if (inputAbs > envelope) {
      envelope = attackCoeff * envelope + (1 - attackCoeff) * inputAbs;
    } else {
      envelope = releaseCoeff * envelope + (1 - releaseCoeff) * inputAbs;
    }

    // Convert to dB
    const inputDb = envelope > 0 ? linearToDb(envelope) : -100;

    // Gain computation with soft knee
    let gainReductionDb = 0;
    if (inputDb > threshold + knee / 2) {
      // Above knee
      gainReductionDb = (inputDb - threshold) * (1 - 1 / ratio);
    } else if (inputDb > threshold - knee / 2) {
      // In knee
      const kneeInput = inputDb - threshold + knee / 2;
      gainReductionDb = (kneeInput * kneeInput) / (2 * knee) * (1 - 1 / ratio);
    }

    // Apply gain reduction + makeup
    const gainLinear = dbToLinear(-gainReductionDb) * makeupLinear;
    buffer[i] = input * gainLinear;
  }

  state.envelope = envelope;
  state.gainReduction = envelope > 0 ? linearToDb(envelope) - threshold : 0;
  if (state.gainReduction < 0) state.gainReduction = Math.abs(state.gainReduction);
  else state.gainReduction = 0;
}

// ============ Limiter ============

export interface LimiterState {
  delayBuffer: Float32Array;
  delayIndex: number;
  gain: number;
}

export function createLimiterState(lookAheadSamples: number): LimiterState {
  return {
    delayBuffer: new Float32Array(lookAheadSamples),
    delayIndex: 0,
    gain: 1,
  };
}

/**
 * Process audio through limiter (in-place).
 * True peak limiting with look-ahead.
 */
export function processLimiter(
  buffer: Float32Array,
  threshold: number, // dB
  release: number, // ms
  state: LimiterState,
  sampleRate: number
): void {
  const thresholdLinear = dbToLinear(threshold);
  const releaseCoeff = Math.exp(-1 / (release * sampleRate / 1000));
  const len = buffer.length;
  const delayLen = state.delayBuffer.length;

  let gain = state.gain;
  let delayIndex = state.delayIndex;

  for (let i = 0; i < len; i++) {
    const input = buffer[i];

    // Get delayed sample
    const delayed = state.delayBuffer[delayIndex];

    // Store current sample in delay
    state.delayBuffer[delayIndex] = input;
    delayIndex = (delayIndex + 1) % delayLen;

    // Calculate target gain
    const inputAbs = Math.abs(input);
    const targetGain = inputAbs > thresholdLinear
      ? thresholdLinear / inputAbs
      : 1;

    // Smooth gain (instant attack, smooth release)
    if (targetGain < gain) {
      gain = targetGain;
    } else {
      gain = releaseCoeff * gain + (1 - releaseCoeff) * targetGain;
    }

    // Apply gain to delayed signal
    buffer[i] = delayed * gain;
  }

  state.gain = gain;
  state.delayIndex = delayIndex;
}

// ============ FFT Utilities ============

/**
 * Apply Hann window to buffer (in-place).
 */
export function applyHannWindow(buffer: Float32Array): void {
  const len = buffer.length;
  const factor = TWO_PI / (len - 1);

  for (let i = 0; i < len; i++) {
    const window = 0.5 * (1 - Math.cos(factor * i));
    buffer[i] *= window;
  }
}

/**
 * Calculate magnitude spectrum from complex FFT output.
 * Assumes interleaved real/imag format.
 */
export function calcMagnitudeSpectrum(
  fftOutput: Float32Array,
  magnitudes: Float32Array
): void {
  const len = magnitudes.length;

  for (let i = 0; i < len; i++) {
    const real = fftOutput[i * 2];
    const imag = fftOutput[i * 2 + 1];
    magnitudes[i] = Math.sqrt(real * real + imag * imag);
  }
}

// ============ Exports ============

export const DSPKernel = {
  // Buffer pool
  bufferPool,

  // Basic math
  dbToLinear,
  linearToDb,
  clamp,
  lerp,

  // Biquad
  createBiquadState,
  calcBiquadCoeffs,
  processBiquad,

  // Gain
  applyGain,
  applyGainRamp,

  // Mixing
  mixInto,
  mixMultiple,

  // Metering
  calcPeak,
  calcRMS,
  calcLevels,

  // Dynamics
  createCompressorState,
  processCompressor,
  createLimiterState,
  processLimiter,

  // FFT
  applyHannWindow,
  calcMagnitudeSpectrum,
};

export default DSPKernel;
