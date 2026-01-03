/**
 * Compressor Processor - Professional Dynamics Control
 *
 * High-quality compressor with:
 * - Smooth gain reduction (no pumping artifacts)
 * - Look-ahead for transparent limiting
 * - Sidechain input support
 * - Parallel (NY) compression
 * - Auto-makeup gain
 *
 * @module dsp-wasm/compressorProcessor
 */

import {
  dbToLinear,
  linearToDb,
} from './dspKernel';

// ============ Types ============

export interface CompressorParams {
  threshold: number; // dB, -60 to 0
  ratio: number; // 1:1 to inf:1
  attack: number; // ms, 0.1 to 100
  release: number; // ms, 10 to 2000
  knee: number; // dB, 0 to 24
  makeupGain: number; // dB, 0 to 24
  mix: number; // 0 to 1 (dry/wet for parallel compression)
  autoMakeup: boolean;
  lookAhead: number; // ms, 0 to 10
}

export interface CompressorState {
  envelope: number;
  gainReduction: number; // in dB, for metering
  attackCoeff: number;
  releaseCoeff: number;
  delayBuffer: Float32Array | null;
  delayBufferR: Float32Array | null;
  delayIndex: number;
  delayLength: number;
}

export interface CompressorMetrics {
  inputLevel: number; // dB
  outputLevel: number; // dB
  gainReduction: number; // dB
}

// ============ Default Parameters ============

export const DEFAULT_COMPRESSOR_PARAMS: CompressorParams = {
  threshold: -18,
  ratio: 4,
  attack: 10,
  release: 100,
  knee: 6,
  makeupGain: 0,
  mix: 1,
  autoMakeup: false,
  lookAhead: 0,
};

// ============ Compressor Processor ============

export class CompressorProcessor {
  private params: CompressorParams;
  private state: CompressorState;
  private sampleRate: number;
  private metrics: CompressorMetrics = { inputLevel: -100, outputLevel: -100, gainReduction: 0 };

  constructor(sampleRate: number, params: Partial<CompressorParams> = {}) {
    this.sampleRate = sampleRate;
    this.params = { ...DEFAULT_COMPRESSOR_PARAMS, ...params };
    this.state = this.createState();
    this.updateCoefficients();
  }

  private createState(): CompressorState {
    const lookAheadSamples = Math.ceil((this.params.lookAhead / 1000) * this.sampleRate);
    return {
      envelope: 0,
      gainReduction: 0,
      attackCoeff: 0,
      releaseCoeff: 0,
      delayBuffer: lookAheadSamples > 0 ? new Float32Array(lookAheadSamples) : null,
      delayBufferR: lookAheadSamples > 0 ? new Float32Array(lookAheadSamples) : null,
      delayIndex: 0,
      delayLength: lookAheadSamples,
    };
  }

  private updateCoefficients(): void {
    const { attack, release } = this.params;
    // Time constants for exponential smoothing
    this.state.attackCoeff = Math.exp(-1 / ((attack / 1000) * this.sampleRate));
    this.state.releaseCoeff = Math.exp(-1 / ((release / 1000) * this.sampleRate));
  }

  /**
   * Update parameters.
   */
  setParams(updates: Partial<CompressorParams>): void {
    const needsCoeffUpdate =
      updates.attack !== undefined && updates.attack !== this.params.attack ||
      updates.release !== undefined && updates.release !== this.params.release;

    const needsDelayUpdate =
      updates.lookAhead !== undefined && updates.lookAhead !== this.params.lookAhead;

    Object.assign(this.params, updates);

    if (needsCoeffUpdate) {
      this.updateCoefficients();
    }

    if (needsDelayUpdate) {
      const lookAheadSamples = Math.ceil((this.params.lookAhead / 1000) * this.sampleRate);
      if (lookAheadSamples !== this.state.delayLength) {
        this.state.delayBuffer = lookAheadSamples > 0 ? new Float32Array(lookAheadSamples) : null;
        this.state.delayBufferR = lookAheadSamples > 0 ? new Float32Array(lookAheadSamples) : null;
        this.state.delayIndex = 0;
        this.state.delayLength = lookAheadSamples;
      }
    }
  }

  /**
   * Get current parameters.
   */
  getParams(): CompressorParams {
    return { ...this.params };
  }

  /**
   * Get current metrics (for UI metering).
   */
  getMetrics(): CompressorMetrics {
    return { ...this.metrics };
  }

  /**
   * Calculate gain reduction for a given input level.
   * Used for visualization and gain computer display.
   */
  private computeGainReduction(inputDb: number): number {
    const { threshold, ratio, knee } = this.params;

    if (inputDb < threshold - knee / 2) {
      // Below knee - no compression
      return 0;
    } else if (inputDb > threshold + knee / 2) {
      // Above knee - full compression
      return (inputDb - threshold) * (1 - 1 / ratio);
    } else {
      // In knee - soft transition
      const kneeInput = inputDb - threshold + knee / 2;
      return (kneeInput * kneeInput) / (2 * knee) * (1 - 1 / ratio);
    }
  }

  /**
   * Calculate auto-makeup gain based on current settings.
   */
  private calcAutoMakeup(): number {
    // Estimate average compression at -18dBFS input
    const testLevel = -18;
    const gr = this.computeGainReduction(testLevel);
    return gr * 0.7; // 70% compensation
  }

  /**
   * Process mono buffer (in-place).
   */
  processMono(buffer: Float32Array, sidechain?: Float32Array): void {
    const { mix, makeupGain, autoMakeup } = this.params;
    const { attackCoeff, releaseCoeff, delayBuffer, delayLength } = this.state;
    const len = buffer.length;

    const effectiveMakeup = autoMakeup
      ? dbToLinear(this.calcAutoMakeup() + makeupGain)
      : dbToLinear(makeupGain);

    let envelope = this.state.envelope;
    let delayIndex = this.state.delayIndex;
    let maxGR = 0;
    let inputPeak = 0;
    let outputPeak = 0;

    // Detect from sidechain if provided
    const detectBuffer = sidechain || buffer;

    for (let i = 0; i < len; i++) {
      const input = buffer[i];
      const detect = Math.abs(detectBuffer[i]);

      // Track input peak
      if (detect > inputPeak) inputPeak = detect;

      // Envelope follower (peak detection)
      if (detect > envelope) {
        envelope = attackCoeff * envelope + (1 - attackCoeff) * detect;
      } else {
        envelope = releaseCoeff * envelope + (1 - releaseCoeff) * detect;
      }

      // Convert to dB
      const envelopeDb = envelope > 1e-10 ? linearToDb(envelope) : -100;

      // Compute gain reduction
      const grDb = this.computeGainReduction(envelopeDb);
      const grLinear = dbToLinear(-grDb);

      // Track max gain reduction for metering
      if (grDb > maxGR) maxGR = grDb;

      // Apply look-ahead delay
      let output: number;
      if (delayBuffer && delayLength > 0) {
        const delayed = delayBuffer[delayIndex];
        delayBuffer[delayIndex] = input;
        delayIndex = (delayIndex + 1) % delayLength;
        output = delayed * grLinear * effectiveMakeup;
      } else {
        output = input * grLinear * effectiveMakeup;
      }

      // Parallel compression mix
      if (mix < 1) {
        output = input * (1 - mix) + output * mix;
      }

      buffer[i] = output;

      // Track output peak
      const outAbs = Math.abs(output);
      if (outAbs > outputPeak) outputPeak = outAbs;
    }

    // Update state
    this.state.envelope = envelope;
    this.state.delayIndex = delayIndex;
    this.state.gainReduction = maxGR;

    // Update metrics
    this.metrics.inputLevel = inputPeak > 1e-10 ? linearToDb(inputPeak) : -100;
    this.metrics.outputLevel = outputPeak > 1e-10 ? linearToDb(outputPeak) : -100;
    this.metrics.gainReduction = maxGR;
  }

  /**
   * Process stereo buffers (in-place).
   * Uses linked stereo detection for consistent imaging.
   */
  processStereo(left: Float32Array, right: Float32Array, sidechain?: Float32Array): void {
    const { mix, makeupGain, autoMakeup } = this.params;
    const { attackCoeff, releaseCoeff, delayBuffer, delayBufferR, delayLength } = this.state;
    const len = Math.min(left.length, right.length);

    const effectiveMakeup = autoMakeup
      ? dbToLinear(this.calcAutoMakeup() + makeupGain)
      : dbToLinear(makeupGain);

    let envelope = this.state.envelope;
    let delayIndex = this.state.delayIndex;
    let maxGR = 0;
    let inputPeak = 0;
    let outputPeak = 0;

    for (let i = 0; i < len; i++) {
      const inputL = left[i];
      const inputR = right[i];

      // Linked stereo detection (max of L/R)
      const detect = sidechain
        ? Math.abs(sidechain[i])
        : Math.max(Math.abs(inputL), Math.abs(inputR));

      // Track input peak
      if (detect > inputPeak) inputPeak = detect;

      // Envelope follower
      if (detect > envelope) {
        envelope = attackCoeff * envelope + (1 - attackCoeff) * detect;
      } else {
        envelope = releaseCoeff * envelope + (1 - releaseCoeff) * detect;
      }

      // Convert to dB
      const envelopeDb = envelope > 1e-10 ? linearToDb(envelope) : -100;

      // Compute gain reduction
      const grDb = this.computeGainReduction(envelopeDb);
      const grLinear = dbToLinear(-grDb);

      // Track max gain reduction
      if (grDb > maxGR) maxGR = grDb;

      // Apply look-ahead delay
      let outputL: number, outputR: number;
      if (delayBuffer && delayBufferR && delayLength > 0) {
        const delayedL = delayBuffer[delayIndex];
        const delayedR = delayBufferR[delayIndex];
        delayBuffer[delayIndex] = inputL;
        delayBufferR[delayIndex] = inputR;
        delayIndex = (delayIndex + 1) % delayLength;
        outputL = delayedL * grLinear * effectiveMakeup;
        outputR = delayedR * grLinear * effectiveMakeup;
      } else {
        outputL = inputL * grLinear * effectiveMakeup;
        outputR = inputR * grLinear * effectiveMakeup;
      }

      // Parallel compression mix
      if (mix < 1) {
        outputL = inputL * (1 - mix) + outputL * mix;
        outputR = inputR * (1 - mix) + outputR * mix;
      }

      left[i] = outputL;
      right[i] = outputR;

      // Track output peak
      const outPeak = Math.max(Math.abs(outputL), Math.abs(outputR));
      if (outPeak > outputPeak) outputPeak = outPeak;
    }

    // Update state
    this.state.envelope = envelope;
    this.state.delayIndex = delayIndex;
    this.state.gainReduction = maxGR;

    // Update metrics
    this.metrics.inputLevel = inputPeak > 1e-10 ? linearToDb(inputPeak) : -100;
    this.metrics.outputLevel = outputPeak > 1e-10 ? linearToDb(outputPeak) : -100;
    this.metrics.gainReduction = maxGR;
  }

  /**
   * Reset state (call after seek/discontinuity).
   */
  reset(): void {
    this.state.envelope = 0;
    this.state.gainReduction = 0;
    this.state.delayIndex = 0;
    if (this.state.delayBuffer) this.state.delayBuffer.fill(0);
    if (this.state.delayBufferR) this.state.delayBufferR.fill(0);
  }

  /**
   * Get transfer curve for visualization.
   * Returns [inputDb, outputDb] pairs.
   */
  getTransferCurve(steps = 100): Array<[number, number]> {
    const curve: Array<[number, number]> = [];
    const makeup = this.params.autoMakeup
      ? this.calcAutoMakeup() + this.params.makeupGain
      : this.params.makeupGain;

    for (let i = 0; i <= steps; i++) {
      const inputDb = -60 + (i / steps) * 60;
      const grDb = this.computeGainReduction(inputDb);
      const outputDb = inputDb - grDb + makeup;
      curve.push([inputDb, outputDb]);
    }

    return curve;
  }
}

export default CompressorProcessor;
