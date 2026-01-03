/**
 * ReelForge DSP AudioWorklet Node
 *
 * Main thread wrapper for DspProcessor AudioWorklet.
 * Provides high-level API for DSP operations.
 */

import type { BiquadCoeffs, CompressorParams } from './index';

export interface DspWorkletNodeOptions {
  /** Initial gain (linear, 1.0 = unity) */
  gain?: number;
  /** Start in bypass mode */
  bypass?: boolean;
  /** WASM module URL (for worklet) */
  wasmUrl?: string;
}

export type DspWorkletEventType = 'ready' | 'wasm-ready' | 'wasm-error' | 'meter';

export interface DspWorkletEvent {
  type: DspWorkletEventType;
  data?: unknown;
}

/**
 * DSP Worklet Node - connects WASM DSP to WebAudio graph
 */
export class DspWorkletNode extends AudioWorkletNode {
  private _ready: Promise<void>;
  private _wasmReady: Promise<void>;
  private _resolveReady!: () => void;
  private _resolveWasmReady!: () => void;
  private _eventListeners: Map<DspWorkletEventType, Set<(event: DspWorkletEvent) => void>>;

  constructor(context: AudioContext, options: DspWorkletNodeOptions = {}) {
    super(context, 'dsp-processor', {
      numberOfInputs: 1,
      numberOfOutputs: 1,
      outputChannelCount: [2],
    });

    this._eventListeners = new Map();

    // Create ready promises
    this._ready = new Promise((resolve) => {
      this._resolveReady = resolve;
    });

    this._wasmReady = new Promise((resolve) => {
      this._resolveWasmReady = resolve;
    });

    // Handle messages from worklet
    this.port.onmessage = (event) => {
      this.handleMessage(event.data);
    };

    // Apply initial options
    if (options.gain !== undefined) {
      this.setGain(options.gain);
    }
    if (options.bypass !== undefined) {
      this.setBypass(options.bypass);
    }

    // Initialize WASM if URL provided
    if (options.wasmUrl) {
      this.initWasm(options.wasmUrl);
    }
  }

  private handleMessage(data: { type: string; [key: string]: unknown }) {
    switch (data.type) {
      case 'ready':
        this._resolveReady();
        this.emit({ type: 'ready' });
        break;

      case 'wasm-ready':
        this._resolveWasmReady();
        this.emit({ type: 'wasm-ready' });
        break;

      case 'wasm-error':
        console.error('[DspWorkletNode] WASM error:', data.error);
        this.emit({ type: 'wasm-error', data: data.error });
        break;

      case 'meter':
        this.emit({ type: 'meter', data: data });
        break;
    }
  }

  private emit(event: DspWorkletEvent) {
    const listeners = this._eventListeners.get(event.type);
    if (listeners) {
      listeners.forEach((fn) => fn(event));
    }
  }

  /**
   * Wait for worklet to be ready
   */
  get ready(): Promise<void> {
    return this._ready;
  }

  /**
   * Wait for WASM to be loaded
   */
  get wasmReady(): Promise<void> {
    return this._wasmReady;
  }

  /**
   * Add event listener
   */
  on(type: DspWorkletEventType, callback: (event: DspWorkletEvent) => void): void {
    if (!this._eventListeners.has(type)) {
      this._eventListeners.set(type, new Set());
    }
    this._eventListeners.get(type)!.add(callback);
  }

  /**
   * Remove event listener
   */
  off(type: DspWorkletEventType, callback: (event: DspWorkletEvent) => void): void {
    this._eventListeners.get(type)?.delete(callback);
  }

  /**
   * Initialize WASM module in worklet
   */
  initWasm(wasmUrl: string): void {
    this.port.postMessage({ type: 'init-wasm', wasmUrl });
  }

  /**
   * Set gain (linear, 1.0 = unity)
   */
  setGain(value: number): void {
    this.port.postMessage({ type: 'set-gain', value });
  }

  /**
   * Set bypass mode
   */
  setBypass(value: boolean): void {
    this.port.postMessage({ type: 'set-bypass', value });
  }

  /**
   * Set biquad filter coefficients
   */
  setBiquad(coeffs: BiquadCoeffs): void {
    this.port.postMessage({
      type: 'set-biquad',
      coeffs: [coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2],
    });
  }

  /**
   * Clear biquad filter
   */
  clearBiquad(): void {
    this.port.postMessage({ type: 'set-biquad', coeffs: null });
  }

  /**
   * Configure compressor
   */
  setCompressor(params: CompressorParams, reset = false): void {
    this.port.postMessage({
      type: 'set-compressor',
      params,
      reset,
    });
  }

  /**
   * Configure limiter
   */
  setLimiter(ceilingDb: number, releaseSec: number, reset = false): void {
    this.port.postMessage({
      type: 'set-limiter',
      ceilingDb,
      releaseSec,
      reset,
    });
  }

  /**
   * Initialize delay buffer
   */
  initDelay(maxDelaySec = 2.0): void {
    this.port.postMessage({
      type: 'init-delay',
      maxDelaySec,
    });
  }

  /**
   * Reset all DSP state
   */
  reset(): void {
    this.port.postMessage({ type: 'reset' });
  }
}

/**
 * Register the DSP worklet processor
 */
export async function registerDspWorklet(context: AudioContext): Promise<void> {
  // The worklet processor needs to be a separate file
  // In production, this would be a bundled worklet file
  const workletUrl = new URL('./worklet-processor.ts', import.meta.url);
  await context.audioWorklet.addModule(workletUrl);
}

/**
 * Create a DSP worklet node with WASM initialized
 */
export async function createDspWorkletNode(
  context: AudioContext,
  options: DspWorkletNodeOptions = {}
): Promise<DspWorkletNode> {
  // Register worklet if not already done
  await registerDspWorklet(context);

  // Create node
  const node = new DspWorkletNode(context, options);

  // Wait for processor ready
  await node.ready;

  return node;
}
