/**
 * ReelForge DSP WASM Module - Tauri Stub
 *
 * In Tauri mode, DSP processing is handled by native Rust code.
 * This module provides stub implementations for compatibility.
 *
 * @module core/dsp-wasm
 */

// Re-export AudioWorklet integration (may still be used for web audio)
export { DspWorkletNode, createDspWorkletNode, registerDspWorklet } from './DspWorkletNode';
export type { DspWorkletNodeOptions, DspWorkletEvent, DspWorkletEventType } from './DspWorkletNode';

// Re-export WASM Master Insert DSP
export {
  WasmMasterInsertDSP,
  wasmMasterInsertDSP,
  type WasmEQBand,
  type WasmCompressorConfig,
  type WasmLimiterConfig,
  type WasmMeterData,
} from './WasmMasterInsertDSP';

let wasmInitialized = false;

/**
 * Initialize the DSP module. In Tauri mode, this is a no-op.
 */
export async function initDspWasm(): Promise<void> {
  wasmInitialized = true;
  console.log('[DSP] Using native Rust DSP via Tauri');
}

/**
 * Check if DSP module is initialized
 */
export function isDspWasmReady(): boolean {
  return wasmInitialized;
}

// ============ Stub Implementations ============
// These are no-ops in Tauri mode - DSP is done in Rust

export interface BiquadCoeffs {
  b0: number;
  b1: number;
  b2: number;
  a1: number;
  a2: number;
}

export interface BiquadState {
  z1: number;
  z2: number;
}

export interface CompressorParams {
  thresholdDb: number;
  ratio: number;
  attackSec: number;
  releaseSec: number;
  kneeDb: number;
  makeupDb: number;
}

export interface CompressorState {
  envelope: number;
  gainReductionDb: number;
}

export interface LimiterState {
  envelope: number;
  gain: number;
}

export interface DelayLine {
  buffer: Float32Array;
  writePos: number;
}

// Gain functions - no-op in Tauri
export function applyGain(_samples: Float32Array, _gain: number): void {}
export function applyGainSmoothed(_samples: Float32Array, _startGain: number, _endGain: number): void {}
export function applyStereoGain(_samples: Float32Array, _gainL: number, _gainR: number): void {}

// Biquad functions - return default coeffs
export function calcLowpassCoeffs(_sampleRate: number, _frequency: number, _q: number): BiquadCoeffs {
  return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
}
export function calcHighpassCoeffs(_sampleRate: number, _frequency: number, _q: number): BiquadCoeffs {
  return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
}
export function calcPeakCoeffs(_sampleRate: number, _frequency: number, _q: number, _gainDb: number): BiquadCoeffs {
  return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
}
export function calcLowShelfCoeffs(_sampleRate: number, _frequency: number, _q: number, _gainDb: number): BiquadCoeffs {
  return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
}
export function calcHighShelfCoeffs(_sampleRate: number, _frequency: number, _q: number, _gainDb: number): BiquadCoeffs {
  return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
}
export function processBiquad(_samples: Float32Array, _coeffs: BiquadCoeffs, _state: BiquadState): void {}
export function createBiquadState(): BiquadState {
  return { z1: 0, z2: 0 };
}

// Compressor functions
export function processCompressor(
  _samples: Float32Array,
  _params: CompressorParams,
  _state: CompressorState,
  _sampleRate: number
): void {}
export function processCompressorStereo(
  _samples: Float32Array,
  _params: CompressorParams,
  _state: CompressorState,
  _sampleRate: number
): void {}
export function createCompressorParams(): CompressorParams {
  return {
    thresholdDb: -20,
    ratio: 4,
    attackSec: 0.010,
    releaseSec: 0.100,
    kneeDb: 6,
    makeupDb: 0,
  };
}
export function createCompressorState(): CompressorState {
  return { envelope: 0, gainReductionDb: 0 };
}

// Limiter functions
export function processLimiter(
  _samples: Float32Array,
  _ceilingDb: number,
  _releaseSec: number,
  _sampleRate: number,
  _state: LimiterState
): void {}
export function getLimiterGainReductionDb(_state: LimiterState): number {
  return 0;
}
export function createLimiterState(): LimiterState {
  return { envelope: 0, gain: 1 };
}

// Delay functions
export function createDelayLine(maxDelaySec: number, sampleRate: number): DelayLine {
  const maxSamples = Math.ceil(maxDelaySec * sampleRate);
  return {
    buffer: new Float32Array(maxSamples),
    writePos: 0,
  };
}
export function processDelay(
  _samples: Float32Array,
  _delayLine: DelayLine,
  _delaySamples: number,
  _feedback: number,
  _mix: number
): void {}

// Utility functions
export function linearToDb(linear: number): number {
  if (linear <= 0) return -120;
  return 20 * Math.log10(linear);
}
export function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}
export function calculateRms(samples: Float32Array): number {
  let sum = 0;
  for (let i = 0; i < samples.length; i++) {
    sum += samples[i] * samples[i];
  }
  return Math.sqrt(sum / samples.length);
}
export function calculatePeak(samples: Float32Array): number {
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    peak = Math.max(peak, Math.abs(samples[i]));
  }
  return peak;
}

// SIMD functions - just call regular versions
export function applyGainSimd(samples: Float32Array, gain: number): void {
  applyGain(samples, gain);
}
export function applyStereoGainSimd(samples: Float32Array, gainL: number, gainR: number): void {
  applyStereoGain(samples, gainL, gainR);
}
export function calculateRmsSimd(samples: Float32Array): number {
  return calculateRms(samples);
}
export function calculatePeakSimd(samples: Float32Array): number {
  return calculatePeak(samples);
}
export function mixBuffersSimd(_a: Float32Array, _b: Float32Array, _out: Float32Array, _mix: number): void {}
export function copyWithGainSimd(_src: Float32Array, _dst: Float32Array, _gain: number): void {}

// Default export
const dspWasm = {
  initDspWasm,
  isDspWasmReady,
  applyGain,
  applyGainSmoothed,
  applyStereoGain,
  calcLowpassCoeffs,
  calcHighpassCoeffs,
  calcPeakCoeffs,
  calcLowShelfCoeffs,
  calcHighShelfCoeffs,
  processBiquad,
  createBiquadState,
  processCompressor,
  processCompressorStereo,
  createCompressorParams,
  createCompressorState,
  processLimiter,
  getLimiterGainReductionDb,
  createLimiterState,
  createDelayLine,
  processDelay,
  linearToDb,
  dbToLinear,
  calculateRms,
  calculatePeak,
  applyGainSimd,
  applyStereoGainSimd,
  calculateRmsSimd,
  calculatePeakSimd,
  mixBuffersSimd,
  copyWithGainSimd,
};

export default dspWasm;
