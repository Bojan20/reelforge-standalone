/**
 * WASM DSP Module Loader
 *
 * Loads and initializes the Rust WASM DSP module.
 * Provides TypeScript bindings for high-performance audio processing.
 *
 * Build the WASM module:
 *   cd dsp-wasm && wasm-pack build --target web --out-dir ../public/wasm
 *
 * @module core/wasmDSP
 */

// ============ Types ============

// Filter type constants (const object instead of enum for erasableSyntaxOnly)
export const FilterType = {
  Highpass: 0,
  Lowpass: 1,
  Bell: 2,
  LowShelf: 3,
  HighShelf: 4,
  Notch: 5,
  Bandpass: 6,
  Allpass: 7,
} as const;

export type FilterTypeValue = typeof FilterType[keyof typeof FilterType];

export interface WasmBiquadFilter {
  new(sampleRate: number): WasmBiquadFilter;
  set_params(freq: number, gain: number, q: number, filterType: FilterTypeValue): void;
  set_active(active: boolean): void;
  reset_state(): void;
  process_block(samples: Float32Array): void;
  free(): void;
}

export interface WasmParametricEQ {
  new(sampleRate: number): WasmParametricEQ;
  set_band(bandIndex: number, freq: number, gain: number, q: number, filterType: FilterTypeValue): void;
  set_band_active(bandIndex: number, active: boolean): void;
  set_enabled(enabled: boolean): void;
  set_output_gain(gain: number): void;
  process_block(samples: Float32Array): void;
  reset(): void;
  free(): void;
}

export interface WasmMeter {
  new(): WasmMeter;
  process_block(samples: Float32Array): void;
  get_peak(): Float32Array;
  get_peak_hold(): Float32Array;
  get_rms_and_reset(): Float32Array;
  reset(): void;
  free(): void;
}

export interface WasmLUFSMeter {
  new(sampleRate: number): WasmLUFSMeter;
  process_block(samples: Float32Array): void;
  get_momentary_lufs(): number;
  get_integrated_lufs(): number;
  reset(): void;
  free(): void;
}

export interface WasmFFTAnalyzer {
  new(size: number): WasmFFTAnalyzer;
  size(): number;
  process(samples: Float32Array): Float32Array;
  get_magnitude(): Float32Array;
  reset(): void;
  free(): void;
}

export interface WasmDSPModule {
  BiquadFilter: WasmBiquadFilter;
  ParametricEQ: WasmParametricEQ;
  Meter: WasmMeter;
  LUFSMeter: WasmLUFSMeter;
  FFTAnalyzer: WasmFFTAnalyzer;
  FilterType: typeof FilterType;
  memory: WebAssembly.Memory;
}

// ============ Loader State ============

let wasmModule: WasmDSPModule | null = null;
let loadPromise: Promise<WasmDSPModule> | null = null;

// ============ Loader ============

/**
 * Load the WASM DSP module.
 * Returns cached module if already loaded.
 */
export async function loadWasmDSP(): Promise<WasmDSPModule> {
  // Return cached module
  if (wasmModule) {
    return wasmModule;
  }

  // Return existing load promise
  if (loadPromise) {
    return loadPromise;
  }

  // Start loading
  loadPromise = (async () => {
    try {
      // Dynamic import of WASM module
      // Built with: npm run build:wasm (wasm-pack build --target web)
      // Crate name "reelforge-dsp" becomes "reelforge_dsp"
      // @ts-expect-error - WASM module is generated at build time
      const wasm = await import('/wasm/reelforge_dsp.js');
      await wasm.default();

      wasmModule = wasm as unknown as WasmDSPModule;
      console.log('[WASM DSP] Module loaded successfully');

      return wasmModule;
    } catch (error) {
      console.warn('[WASM DSP] Failed to load module, falling back to JS implementation:', error);
      loadPromise = null;
      throw error;
    }
  })();

  return loadPromise;
}

/**
 * Check if WASM module is loaded.
 */
export function isWasmLoaded(): boolean {
  return wasmModule !== null;
}

/**
 * Get loaded WASM module or null.
 */
export function getWasmModule(): WasmDSPModule | null {
  return wasmModule;
}

// ============ Fallback JS Implementations ============

/**
 * JavaScript fallback for BiquadFilter when WASM is not available.
 */
export class JSBiquadFilter {
  private b0 = 1;
  private b1 = 0;
  private b2 = 0;
  private a1 = 0;
  private a2 = 0;

  private x1L = 0;
  private x2L = 0;
  private y1L = 0;
  private y2L = 0;
  private x1R = 0;
  private x2R = 0;
  private y1R = 0;
  private y2R = 0;

  private freq = 1000;
  private gain = 0;
  private q = 1;
  private filterType: FilterTypeValue = FilterType.Bell;
  private sampleRate: number;
  private active = true;

  constructor(sampleRate: number) {
    this.sampleRate = sampleRate;
  }

  setParams(freq: number, gain: number, q: number, filterType: FilterTypeValue): void {
    this.freq = Math.max(20, Math.min(20000, freq));
    this.gain = Math.max(-24, Math.min(24, gain));
    this.q = Math.max(0.1, Math.min(18, q));
    this.filterType = filterType;
    this.calculateCoefficients();
  }

  setActive(active: boolean): void {
    this.active = active;
    if (!active) this.resetState();
  }

  resetState(): void {
    this.x1L = this.x2L = this.y1L = this.y2L = 0;
    this.x1R = this.x2R = this.y1R = this.y2R = 0;
  }

  private calculateCoefficients(): void {
    if (!this.active) {
      this.b0 = 1;
      this.b1 = this.b2 = this.a1 = this.a2 = 0;
      return;
    }

    const fs = this.sampleRate;
    const f0 = this.freq;
    const Q = this.q;
    const gainDb = this.gain;

    const A = Math.pow(10, gainDb / 40);
    const w0 = 2 * Math.PI * f0 / fs;
    const sinW0 = Math.sin(w0);
    const cosW0 = Math.cos(w0);
    const alpha = sinW0 / (2 * Q);

    let b0: number, b1: number, b2: number, a0: number, a1: number, a2: number;

    switch (this.filterType) {
      case FilterType.Bell:
        b0 = 1 + alpha * A;
        b1 = -2 * cosW0;
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cosW0;
        a2 = 1 - alpha / A;
        break;

      case FilterType.LowShelf: {
        const sqrtA = Math.sqrt(A);
        b0 = A * ((A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha);
        b1 = 2 * A * ((A - 1) - (A + 1) * cosW0);
        b2 = A * ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha);
        a0 = (A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha;
        a1 = -2 * ((A - 1) + (A + 1) * cosW0);
        a2 = (A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha;
        break;
      }

      case FilterType.HighShelf: {
        const sqrtA = Math.sqrt(A);
        b0 = A * ((A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha);
        b1 = -2 * A * ((A - 1) + (A + 1) * cosW0);
        b2 = A * ((A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha);
        a0 = (A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha;
        a1 = 2 * ((A - 1) - (A + 1) * cosW0);
        a2 = (A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha;
        break;
      }

      case FilterType.Highpass:
        b0 = (1 + cosW0) / 2;
        b1 = -(1 + cosW0);
        b2 = (1 + cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      case FilterType.Lowpass:
        b0 = (1 - cosW0) / 2;
        b1 = 1 - cosW0;
        b2 = (1 - cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      case FilterType.Notch:
        b0 = 1;
        b1 = -2 * cosW0;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      default:
        b0 = 1;
        b1 = b2 = a0 = a1 = a2 = 0;
        a0 = 1;
    }

    // Normalize
    this.b0 = b0 / a0;
    this.b1 = b1 / a0;
    this.b2 = b2 / a0;
    this.a1 = a1 / a0;
    this.a2 = a2 / a0;
  }

  processBlock(samples: Float32Array): void {
    if (!this.active) return;

    const len = samples.length;
    for (let i = 0; i < len; i += 2) {
      // Left channel
      const inputL = samples[i];
      const outputL = this.b0 * inputL + this.b1 * this.x1L + this.b2 * this.x2L
        - this.a1 * this.y1L - this.a2 * this.y2L;
      this.x2L = this.x1L;
      this.x1L = inputL;
      this.y2L = this.y1L;
      this.y1L = outputL;
      samples[i] = outputL;

      // Right channel
      if (i + 1 < len) {
        const inputR = samples[i + 1];
        const outputR = this.b0 * inputR + this.b1 * this.x1R + this.b2 * this.x2R
          - this.a1 * this.y1R - this.a2 * this.y2R;
        this.x2R = this.x1R;
        this.x1R = inputR;
        this.y2R = this.y1R;
        this.y1R = outputR;
        samples[i + 1] = outputR;
      }
    }
  }

  free(): void {
    // No-op for JS implementation
  }
}

/**
 * JavaScript fallback for Meter when WASM is not available.
 */
export class JSMeter {
  private peakL = 0;
  private peakR = 0;
  private rmsSumL = 0;
  private rmsSumR = 0;
  private rmsCount = 0;
  private peakHoldL = 0;
  private peakHoldR = 0;
  private peakDecay = 0.9995;

  processBlock(samples: Float32Array): void {
    const len = samples.length;
    let maxL = 0;
    let maxR = 0;
    let sumL = 0;
    let sumR = 0;

    for (let i = 0; i < len; i += 2) {
      const l = Math.abs(samples[i]);
      const r = i + 1 < len ? Math.abs(samples[i + 1]) : l;

      maxL = Math.max(maxL, l);
      maxR = Math.max(maxR, r);
      sumL += samples[i] * samples[i];
      sumR += i + 1 < len ? samples[i + 1] * samples[i + 1] : sumL;
    }

    this.peakL = maxL;
    this.peakR = maxR;
    this.rmsSumL += sumL;
    this.rmsSumR += sumR;
    this.rmsCount += len / 2;

    this.peakHoldL = Math.max(this.peakHoldL, maxL) * this.peakDecay;
    this.peakHoldR = Math.max(this.peakHoldR, maxR) * this.peakDecay;
  }

  getPeak(): Float32Array {
    return new Float32Array([this.peakL, this.peakR]);
  }

  getPeakHold(): Float32Array {
    return new Float32Array([this.peakHoldL, this.peakHoldR]);
  }

  getRmsAndReset(): Float32Array {
    if (this.rmsCount === 0) {
      return new Float32Array([0, 0]);
    }

    const rmsL = Math.sqrt(this.rmsSumL / this.rmsCount);
    const rmsR = Math.sqrt(this.rmsSumR / this.rmsCount);

    this.rmsSumL = 0;
    this.rmsSumR = 0;
    this.rmsCount = 0;

    return new Float32Array([rmsL, rmsR]);
  }

  reset(): void {
    this.peakL = this.peakR = 0;
    this.rmsSumL = this.rmsSumR = 0;
    this.rmsCount = 0;
    this.peakHoldL = this.peakHoldR = 0;
  }

  free(): void {
    // No-op for JS implementation
  }
}

// ============ Factory Functions ============

/**
 * Create a biquad filter (WASM or JS fallback).
 */
export function createBiquadFilter(sampleRate: number): JSBiquadFilter {
  // TODO: Use WASM when available
  // if (wasmModule) {
  //   return new wasmModule.BiquadFilter(sampleRate);
  // }
  return new JSBiquadFilter(sampleRate);
}

/**
 * Create a meter (WASM or JS fallback).
 */
export function createMeter(): JSMeter {
  // TODO: Use WASM when available
  // if (wasmModule) {
  //   return new wasmModule.Meter();
  // }
  return new JSMeter();
}

export default {
  loadWasmDSP,
  isWasmLoaded,
  getWasmModule,
  createBiquadFilter,
  createMeter,
  FilterType,
};
