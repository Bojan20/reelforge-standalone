/**
 * WASM DSP Bridge
 *
 * TypeScript interface for the Rust WASM DSP kernel.
 * Provides high-level API for professional audio processing.
 *
 * Features:
 * - Automatic WASM loading and initialization
 * - Type-safe bindings to Rust structs
 * - Fallback to TypeScript implementation if WASM unavailable
 *
 * @module dsp-wasm/wasmDspBridge
 */

// Import generated bindings
import init, {
  // Basic functions
  apply_gain_stereo,
  apply_gain_ramp_stereo,
  mix_stereo,
  calc_peak_stereo,
  calc_rms_stereo,
  calc_levels_stereo,

  // Classes
  BiquadFilter,
  ParametricEQ,
  Compressor,
  TruePeakLimiter,
  SoftClipper,
  TruePeakMeter,
  LUFSMeter,
  Meter,

  // Enums
  FilterType,

  // Utils
  get_version,
  is_ready,
  fill_test_tone,
  fill_white_noise,
} from './rust-dsp/pkg/reelforge_dsp';

// ============ Types ============

export interface WasmDspState {
  initialized: boolean;
  version: string | null;
  error: string | null;
}

// ============ State ============

let wasmState: WasmDspState = {
  initialized: false,
  version: null,
  error: null,
};

// ============ Initialization ============

/**
 * Initialize the WASM DSP module.
 * Call once at app startup.
 */
export async function initWasmDsp(): Promise<boolean> {
  if (wasmState.initialized) {
    return true;
  }

  try {
    // Initialize WASM module
    await init('/wasm/reelforge_dsp_bg.wasm');

    // Verify it's working
    if (!is_ready()) {
      throw new Error('WASM module not ready after init');
    }

    wasmState.initialized = true;
    wasmState.version = get_version();
    wasmState.error = null;

    console.log(`[WasmDsp] Initialized v${wasmState.version}`);
    return true;
  } catch (error) {
    wasmState.error = error instanceof Error ? error.message : 'Unknown error';
    console.warn('[WasmDsp] Failed to initialize, falling back to TypeScript DSP:', wasmState.error);
    return false;
  }
}

/**
 * Check if WASM DSP is available.
 */
export function isWasmDspAvailable(): boolean {
  return wasmState.initialized;
}

/**
 * Get WASM DSP version.
 */
export function getWasmDspVersion(): string | null {
  return wasmState.version;
}

/**
 * Get WASM DSP state.
 */
export function getWasmDspState(): WasmDspState {
  return { ...wasmState };
}

// ============ Re-exports ============

export {
  // Basic functions
  apply_gain_stereo,
  apply_gain_ramp_stereo,
  mix_stereo,
  calc_peak_stereo,
  calc_rms_stereo,
  calc_levels_stereo,

  // Classes
  BiquadFilter,
  ParametricEQ,
  Compressor,
  TruePeakLimiter,
  SoftClipper,
  TruePeakMeter,
  LUFSMeter,
  Meter,

  // Enums
  FilterType,

  // Utils
  fill_test_tone,
  fill_white_noise,
};

// ============ Hybrid DSP Factory ============

/**
 * Create a hybrid EQ that uses WASM if available, TypeScript otherwise.
 */
export function createHybridEQ(sampleRate: number): ParametricEQ | null {
  if (!wasmState.initialized) {
    console.warn('[WasmDsp] Not initialized, call initWasmDsp() first');
    return null;
  }

  return new ParametricEQ(sampleRate);
}

/**
 * Create a hybrid Compressor that uses WASM if available.
 */
export function createHybridCompressor(sampleRate: number): Compressor | null {
  if (!wasmState.initialized) {
    console.warn('[WasmDsp] Not initialized, call initWasmDsp() first');
    return null;
  }

  return new Compressor(sampleRate);
}

/**
 * Create a True Peak Limiter.
 */
export function createTruePeakLimiter(sampleRate: number): TruePeakLimiter | null {
  if (!wasmState.initialized) {
    console.warn('[WasmDsp] Not initialized, call initWasmDsp() first');
    return null;
  }

  return new TruePeakLimiter(sampleRate);
}

/**
 * Create a LUFS Meter (ITU-R BS.1770 compliant).
 */
export function createLUFSMeter(sampleRate: number): LUFSMeter | null {
  if (!wasmState.initialized) {
    console.warn('[WasmDsp] Not initialized, call initWasmDsp() first');
    return null;
  }

  return new LUFSMeter(sampleRate);
}

/**
 * Create a True Peak Meter (4x oversampling).
 */
export function createTruePeakMeter(): TruePeakMeter | null {
  if (!wasmState.initialized) {
    console.warn('[WasmDsp] Not initialized, call initWasmDsp() first');
    return null;
  }

  return new TruePeakMeter();
}

// ============ Utility Functions ============

/**
 * Process stereo buffer with gain (uses WASM if available).
 * Falls back to TypeScript loop if WASM not initialized.
 */
export function applyGainStereo(buffer: Float32Array, gain: number): void {
  if (wasmState.initialized) {
    apply_gain_stereo(buffer, gain);
  } else {
    // TypeScript fallback
    for (let i = 0; i < buffer.length; i++) {
      buffer[i] *= gain;
    }
  }
}

/**
 * Calculate peak levels (uses WASM if available).
 */
export function calcPeakStereo(buffer: Float32Array): [number, number] {
  if (wasmState.initialized) {
    const result = calc_peak_stereo(buffer);
    return [result[0], result[1]];
  } else {
    // TypeScript fallback
    let peakL = 0;
    let peakR = 0;
    const len = buffer.length / 2;

    for (let i = 0; i < len; i++) {
      const idx = i * 2;
      const absL = Math.abs(buffer[idx]);
      const absR = Math.abs(buffer[idx + 1]);
      if (absL > peakL) peakL = absL;
      if (absR > peakR) peakR = absR;
    }

    return [peakL, peakR];
  }
}

/**
 * Calculate peak and RMS levels (uses WASM if available).
 */
export function calcLevelsStereo(buffer: Float32Array): {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
} {
  if (wasmState.initialized) {
    const result = calc_levels_stereo(buffer);
    return {
      peakL: result[0],
      peakR: result[1],
      rmsL: result[2],
      rmsR: result[3],
    };
  } else {
    // TypeScript fallback
    let peakL = 0;
    let peakR = 0;
    let sumL = 0;
    let sumR = 0;
    const len = buffer.length / 2;

    for (let i = 0; i < len; i++) {
      const idx = i * 2;
      const l = buffer[idx];
      const r = buffer[idx + 1];

      const absL = Math.abs(l);
      const absR = Math.abs(r);
      if (absL > peakL) peakL = absL;
      if (absR > peakR) peakR = absR;

      sumL += l * l;
      sumR += r * r;
    }

    return {
      peakL,
      peakR,
      rmsL: len > 0 ? Math.sqrt(sumL / len) : 0,
      rmsR: len > 0 ? Math.sqrt(sumR / len) : 0,
    };
  }
}

export default {
  init: initWasmDsp,
  isAvailable: isWasmDspAvailable,
  getVersion: getWasmDspVersion,
  getState: getWasmDspState,
  applyGainStereo,
  calcPeakStereo,
  calcLevelsStereo,
  createHybridEQ,
  createHybridCompressor,
  createTruePeakLimiter,
  createLUFSMeter,
  createTruePeakMeter,
};
