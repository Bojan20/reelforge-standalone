/**
 * DSP WASM Module
 *
 * High-performance audio processing kernels.
 * - TypeScript implementations for fallback
 * - Rust WASM for 10-50x speedup (when available)
 *
 * Usage:
 * ```ts
 * import { initWasmDsp, createHybridEQ } from './dsp-wasm';
 * await initWasmDsp();
 * const eq = createHybridEQ(48000);
 * ```
 *
 * @module dsp-wasm
 */

// Core DSP kernel
export {
  DSPKernel,
  bufferPool,
  dbToLinear,
  linearToDb,
  clamp,
  lerp,
  createBiquadState,
  calcBiquadCoeffs,
  processBiquad,
  applyGain,
  applyGainRamp,
  mixInto,
  mixMultiple,
  calcPeak,
  calcRMS,
  calcLevels,
  createCompressorState,
  processCompressor,
  createLimiterState,
  processLimiter,
  applyHannWindow,
  calcMagnitudeSpectrum,
  type BiquadState,
  type BiquadCoeffs,
  type CompressorState as KernelCompressorState,
  type CompressorParams as KernelCompressorParams,
  type LimiterState,
} from './dspKernel';

// EQ Processor
export {
  EQProcessor,
  DEFAULT_EQ_BANDS,
  type EQBand,
  type EQBandType,
  type EQProcessorState,
} from './eqProcessor';

// Compressor Processor
export {
  CompressorProcessor,
  DEFAULT_COMPRESSOR_PARAMS,
  type CompressorParams,
  type CompressorState,
  type CompressorMetrics,
} from './compressorProcessor';

// WASM DSP Bridge (Rust WASM when available)
export {
  initWasmDsp,
  isWasmDspAvailable,
  getWasmDspVersion,
  getWasmDspState,
  applyGainStereo,
  calcPeakStereo,
  calcLevelsStereo,
  createHybridEQ,
  createHybridCompressor,
  createTruePeakLimiter,
  createLUFSMeter,
  createTruePeakMeter,
  // Re-export WASM classes for direct use
  BiquadFilter as WasmBiquadFilter,
  ParametricEQ as WasmParametricEQ,
  Compressor as WasmCompressor,
  TruePeakLimiter as WasmTruePeakLimiter,
  LUFSMeter as WasmLUFSMeter,
  TruePeakMeter as WasmTruePeakMeter,
  FilterType as WasmFilterType,
  type WasmDspState,
} from './wasmDspBridge';
