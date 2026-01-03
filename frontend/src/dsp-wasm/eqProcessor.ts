/**
 * EQ Processor - Multi-band Parametric EQ
 *
 * High-performance parametric EQ with:
 * - 6-band parametric EQ (expandable)
 * - Coefficient caching (recalculate only on parameter change)
 * - Stereo/mono processing
 * - Linear phase mode (optional, higher latency)
 *
 * @module dsp-wasm/eqProcessor
 */

import {
  type BiquadState,
  type BiquadCoeffs,
  createBiquadState,
  calcBiquadCoeffs,
  processBiquad,
  bufferPool,
} from './dspKernel';

// ============ Types ============

export type EQBandType = 'lowshelf' | 'highshelf' | 'peaking' | 'lowpass' | 'highpass';

export interface EQBand {
  type: EQBandType;
  frequency: number; // Hz
  gain: number; // dB
  q: number;
  enabled: boolean;
}

export interface EQProcessorState {
  bands: EQBandState[];
  sampleRate: number;
  inputGain: number;
  outputGain: number;
}

interface EQBandState {
  config: EQBand;
  coeffs: BiquadCoeffs;
  stateL: BiquadState;
  stateR: BiquadState;
  dirty: boolean; // Coefficients need recalculation
}

// ============ Default Configuration ============

export const DEFAULT_EQ_BANDS: EQBand[] = [
  { type: 'highpass', frequency: 30, gain: 0, q: 0.707, enabled: false },
  { type: 'lowshelf', frequency: 80, gain: 0, q: 0.707, enabled: true },
  { type: 'peaking', frequency: 250, gain: 0, q: 1.5, enabled: true },
  { type: 'peaking', frequency: 1000, gain: 0, q: 1.5, enabled: true },
  { type: 'peaking', frequency: 4000, gain: 0, q: 1.5, enabled: true },
  { type: 'highshelf', frequency: 12000, gain: 0, q: 0.707, enabled: true },
];

// ============ EQ Processor ============

export class EQProcessor {
  private state: EQProcessorState;
  private tempBuffer: Float32Array | null = null;

  constructor(sampleRate: number, bands: EQBand[] = DEFAULT_EQ_BANDS) {
    this.state = {
      bands: bands.map(config => this.createBandState(config, sampleRate)),
      sampleRate,
      inputGain: 1,
      outputGain: 1,
    };
  }

  private createBandState(config: EQBand, sampleRate: number): EQBandState {
    return {
      config: { ...config },
      coeffs: calcBiquadCoeffs(config.type, config.frequency, config.gain, config.q, sampleRate),
      stateL: createBiquadState(),
      stateR: createBiquadState(),
      dirty: false,
    };
  }

  /**
   * Update a band's parameters.
   * Only marks as dirty - coefficients calculated on next process call.
   */
  setBand(index: number, updates: Partial<EQBand>): void {
    const band = this.state.bands[index];
    if (!band) return;

    let changed = false;

    if (updates.type !== undefined && updates.type !== band.config.type) {
      band.config.type = updates.type;
      changed = true;
    }
    if (updates.frequency !== undefined && updates.frequency !== band.config.frequency) {
      band.config.frequency = updates.frequency;
      changed = true;
    }
    if (updates.gain !== undefined && updates.gain !== band.config.gain) {
      band.config.gain = updates.gain;
      changed = true;
    }
    if (updates.q !== undefined && updates.q !== band.config.q) {
      band.config.q = updates.q;
      changed = true;
    }
    if (updates.enabled !== undefined) {
      band.config.enabled = updates.enabled;
    }

    if (changed) {
      band.dirty = true;
    }
  }

  /**
   * Set input gain in dB.
   */
  setInputGain(gainDb: number): void {
    this.state.inputGain = Math.pow(10, gainDb / 20);
  }

  /**
   * Set output gain in dB.
   */
  setOutputGain(gainDb: number): void {
    this.state.outputGain = Math.pow(10, gainDb / 20);
  }

  /**
   * Get current band configurations.
   */
  getBands(): EQBand[] {
    return this.state.bands.map(b => ({ ...b.config }));
  }

  /**
   * Process mono audio buffer (in-place).
   */
  processMono(buffer: Float32Array): void {
    const { bands, inputGain, outputGain } = this.state;

    // Apply input gain
    if (inputGain !== 1) {
      for (let i = 0; i < buffer.length; i++) {
        buffer[i] *= inputGain;
      }
    }

    // Ensure temp buffer
    if (!this.tempBuffer || this.tempBuffer.length < buffer.length) {
      if (this.tempBuffer) bufferPool.release(this.tempBuffer);
      this.tempBuffer = bufferPool.acquire(buffer.length);
    }

    // Process each enabled band
    for (const band of bands) {
      if (!band.config.enabled) continue;

      // Recalculate coefficients if dirty
      if (band.dirty) {
        band.coeffs = calcBiquadCoeffs(
          band.config.type,
          band.config.frequency,
          band.config.gain,
          band.config.q,
          this.state.sampleRate
        );
        band.dirty = false;
      }

      // Process through biquad
      processBiquad(buffer, this.tempBuffer, band.coeffs, band.stateL);

      // Copy result back
      buffer.set(this.tempBuffer);
    }

    // Apply output gain
    if (outputGain !== 1) {
      for (let i = 0; i < buffer.length; i++) {
        buffer[i] *= outputGain;
      }
    }
  }

  /**
   * Process stereo audio buffers (in-place).
   */
  processStereo(left: Float32Array, right: Float32Array): void {
    const { bands, inputGain, outputGain } = this.state;

    // Apply input gain
    if (inputGain !== 1) {
      for (let i = 0; i < left.length; i++) {
        left[i] *= inputGain;
        right[i] *= inputGain;
      }
    }

    // Ensure temp buffer
    const bufLen = Math.max(left.length, right.length);
    if (!this.tempBuffer || this.tempBuffer.length < bufLen) {
      if (this.tempBuffer) bufferPool.release(this.tempBuffer);
      this.tempBuffer = bufferPool.acquire(bufLen);
    }

    // Process each enabled band
    for (const band of bands) {
      if (!band.config.enabled) continue;

      // Recalculate coefficients if dirty
      if (band.dirty) {
        band.coeffs = calcBiquadCoeffs(
          band.config.type,
          band.config.frequency,
          band.config.gain,
          band.config.q,
          this.state.sampleRate
        );
        band.dirty = false;
      }

      // Process left channel
      processBiquad(left, this.tempBuffer, band.coeffs, band.stateL);
      left.set(this.tempBuffer.subarray(0, left.length));

      // Process right channel
      processBiquad(right, this.tempBuffer, band.coeffs, band.stateR);
      right.set(this.tempBuffer.subarray(0, right.length));
    }

    // Apply output gain
    if (outputGain !== 1) {
      for (let i = 0; i < left.length; i++) {
        left[i] *= outputGain;
        right[i] *= outputGain;
      }
    }
  }

  /**
   * Reset all filter states (call after seek/discontinuity).
   */
  reset(): void {
    for (const band of this.state.bands) {
      band.stateL = createBiquadState();
      band.stateR = createBiquadState();
    }
  }

  /**
   * Calculate frequency response at given frequencies.
   * Returns magnitude in dB for each frequency.
   */
  getFrequencyResponse(frequencies: number[]): number[] {
    const { bands, sampleRate } = this.state;
    const response = new Array(frequencies.length).fill(0);

    for (const band of bands) {
      if (!band.config.enabled) continue;

      // Ensure coefficients are up to date
      if (band.dirty) {
        band.coeffs = calcBiquadCoeffs(
          band.config.type,
          band.config.frequency,
          band.config.gain,
          band.config.q,
          sampleRate
        );
        band.dirty = false;
      }

      const { b0, b1, b2, a1, a2 } = band.coeffs;

      for (let i = 0; i < frequencies.length; i++) {
        const omega = (2 * Math.PI * frequencies[i]) / sampleRate;
        const cosOmega = Math.cos(omega);
        const cos2Omega = Math.cos(2 * omega);
        const sinOmega = Math.sin(omega);
        const sin2Omega = Math.sin(2 * omega);

        // H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
        // At z = e^(j*omega)
        const numReal = b0 + b1 * cosOmega + b2 * cos2Omega;
        const numImag = -(b1 * sinOmega + b2 * sin2Omega);
        const denReal = 1 + a1 * cosOmega + a2 * cos2Omega;
        const denImag = -(a1 * sinOmega + a2 * sin2Omega);

        // Complex division
        const denMag2 = denReal * denReal + denImag * denImag;
        const hReal = (numReal * denReal + numImag * denImag) / denMag2;
        const hImag = (numImag * denReal - numReal * denImag) / denMag2;

        const magnitude = Math.sqrt(hReal * hReal + hImag * hImag);
        const magnitudeDb = 20 * Math.log10(magnitude);

        response[i] += magnitudeDb;
      }
    }

    return response;
  }

  /**
   * Dispose and release resources.
   */
  dispose(): void {
    if (this.tempBuffer) {
      bufferPool.release(this.tempBuffer);
      this.tempBuffer = null;
    }
  }
}

export default EQProcessor;
