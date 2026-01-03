/**
 * AudioWorklet DSP Bridge with WASM Integration
 *
 * High-performance audio processing using:
 * - AudioWorklet for dedicated audio thread
 * - SharedArrayBuffer for zero-copy data transfer
 * - Rust WASM for optimized DSP processing
 *
 * Architecture:
 * ┌─────────────────┐    SharedArrayBuffer    ┌─────────────────┐
 * │   Main Thread   │◄──────────────────────►│  Audio Thread   │
 * │   (React UI)    │                         │  (Worklet)      │
 * │                 │    WebAssembly.Module   │                 │
 * │   Load WASM ────┼───────────────────────►│  Instantiate    │
 * └─────────────────┘                         └─────────────────┘
 *         │                                           │
 *         │ postMessage (config only)                 │
 *         └───────────────────────────────────────────┘
 *
 * @module core/audioWorkletDSP
 */

import { FilterType } from './wasmDSP';

// ============ Types ============

export interface DSPConfig {
  sampleRate: number;
  blockSize: number;
  channelCount: number;
}

export interface EQBandConfig {
  id: number;
  freq: number;
  gain: number;
  q: number;
  type: 'highpass' | 'lowpass' | 'bell' | 'lowshelf' | 'highshelf' | 'notch' | 'bandpass' | 'allpass';
  active: boolean;
}

export interface MeterData {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
  lufs: number;
}

// ============ Shared Buffer Layout ============

/**
 * SharedArrayBuffer layout for audio data exchange.
 *
 * Layout (in Float32 elements):
 * [0-127]     Input Left
 * [128-255]   Input Right
 * [256-383]   Output Left
 * [384-511]   Output Right
 * [512-519]   Meter data (peak L/R, rms L/R, lufs, reserved)
 * [520-775]   FFT magnitude (256 bins)
 * [776-783]   Control flags (bypass, etc)
 */
const BLOCK_SIZE = 128;
const BUFFER_LAYOUT = {
  INPUT_L: 0,
  INPUT_R: BLOCK_SIZE,
  OUTPUT_L: BLOCK_SIZE * 2,
  OUTPUT_R: BLOCK_SIZE * 3,
  METERS: BLOCK_SIZE * 4,
  FFT: BLOCK_SIZE * 4 + 8,
  CONTROL: BLOCK_SIZE * 4 + 8 + 256,
  TOTAL_SIZE: BLOCK_SIZE * 4 + 8 + 256 + 8, // 784 floats
} as const;

// Control flag indices
const CONTROL_FLAGS = {
  BYPASS: 0,
  WASM_READY: 1,
} as const;

// ============ Filter Type Mapping ============

const FILTER_TYPE_MAP: Record<EQBandConfig['type'], number> = {
  highpass: FilterType.Highpass,
  lowpass: FilterType.Lowpass,
  bell: FilterType.Bell,
  lowshelf: FilterType.LowShelf,
  highshelf: FilterType.HighShelf,
  notch: FilterType.Notch,
  bandpass: FilterType.Bandpass,
  allpass: FilterType.Allpass,
};

// ============ Worklet Processor Code ============

/**
 * AudioWorklet processor code as string.
 * This runs in the audio thread context.
 *
 * Supports both WASM and JS fallback processing.
 */
const WORKLET_CODE = `
/**
 * ReelForge DSP Processor
 * Runs on dedicated audio thread with SharedArrayBuffer access.
 * Uses Rust WASM for DSP when available, JS fallback otherwise.
 */
class ReelForgeDSPProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();

    // SharedArrayBuffer views
    this.sharedBuffer = null;
    this.audioData = null;
    this.meterData = null;
    this.fftData = null;
    this.controlData = null;

    // WASM module
    this.wasmModule = null;
    this.wasmInstance = null;
    this.wasmMemory = null;
    this.wasmReady = false;

    // WASM DSP instances
    this.wasmEQ = null;
    this.wasmMeter = null;
    this.wasmLUFS = null;

    // JS fallback state
    this.bands = [];
    this.filters = [];

    // Meter state (JS fallback)
    this.peakHoldL = 0;
    this.peakHoldR = 0;
    this.rmsSumL = 0;
    this.rmsSumR = 0;
    this.rmsCount = 0;

    // Processing state
    this.bypassed = false;
    this.outputGain = 1.0;

    // Listen for config messages
    this.port.onmessage = (e) => this.handleMessage(e.data);
  }

  async handleMessage(data) {
    switch (data.type) {
      case 'init':
        // Receive SharedArrayBuffer from main thread
        this.sharedBuffer = data.sharedBuffer;
        this.audioData = new Float32Array(this.sharedBuffer);
        this.meterData = new Float32Array(this.sharedBuffer, ${BUFFER_LAYOUT.METERS} * 4, 8);
        this.fftData = new Float32Array(this.sharedBuffer, ${BUFFER_LAYOUT.FFT} * 4, 256);
        this.controlData = new Float32Array(this.sharedBuffer, ${BUFFER_LAYOUT.CONTROL} * 4, 8);
        break;

      case 'initWasm':
        // Receive compiled WebAssembly.Module and instantiate
        await this.initWasm(data.wasmModule, data.sampleRate);
        break;

      case 'updateBands':
        this.bands = data.bands;
        this.updateFilters();
        break;

      case 'bypass':
        this.bypassed = data.bypassed;
        if (this.controlData) {
          this.controlData[${CONTROL_FLAGS.BYPASS}] = data.bypassed ? 1 : 0;
        }
        break;

      case 'outputGain':
        this.outputGain = data.gain;
        if (this.wasmEQ) {
          this.wasmEQ.set_output_gain(data.gain);
        }
        break;
    }
  }

  async initWasm(wasmModule, sampleRate) {
    try {
      // Instantiate WASM module
      this.wasmInstance = await WebAssembly.instantiate(wasmModule, {
        env: {
          // Provide any required imports
        },
        wbg: {
          // wasm-bindgen imports
          __wbindgen_throw: (ptr, len) => {
            // Error handling
          },
        },
      });

      this.wasmMemory = this.wasmInstance.exports.memory;

      // Create DSP instances
      // Note: wasm-pack generates wrapper functions we need to call
      const exports = this.wasmInstance.exports;

      // Check if ParametricEQ exists
      if (exports.ParametricEQ) {
        this.wasmEQ = new exports.ParametricEQ(sampleRate);
      }

      if (exports.Meter) {
        this.wasmMeter = new exports.Meter();
      }

      if (exports.LUFSMeter) {
        this.wasmLUFS = new exports.LUFSMeter(sampleRate);
      }

      this.wasmReady = true;

      if (this.controlData) {
        this.controlData[${CONTROL_FLAGS.WASM_READY}] = 1;
      }

      // Apply any pending band config
      if (this.bands.length > 0) {
        this.updateFilters();
      }
    } catch (error) {
      // Fallback to JS processing
      this.wasmReady = false;
    }
  }

  updateFilters() {
    if (this.wasmReady && this.wasmEQ) {
      // Update WASM EQ bands
      for (let i = 0; i < this.bands.length && i < 8; i++) {
        const band = this.bands[i];
        this.wasmEQ.set_band(
          i,
          band.freq,
          band.gain,
          band.q,
          this.mapFilterType(band.type)
        );
        this.wasmEQ.set_band_active(i, band.active);
      }
    } else {
      // JS fallback: recreate filter coefficients
      this.filters = this.bands.map(band => ({
        ...band,
        // Biquad state (stereo)
        x1L: 0, x2L: 0, y1L: 0, y2L: 0,
        x1R: 0, x2R: 0, y1R: 0, y2R: 0,
        ...this.calculateCoefficients(band)
      }));
    }
  }

  mapFilterType(type) {
    const map = {
      'highpass': 0,
      'lowpass': 1,
      'bell': 2,
      'lowshelf': 3,
      'highshelf': 4,
      'notch': 5,
      'bandpass': 6,
      'allpass': 7,
    };
    return map[type] || 2; // Default to bell
  }

  calculateCoefficients(band) {
    if (!band.active) {
      return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
    }

    const fs = sampleRate;
    const f0 = Math.max(20, Math.min(20000, band.freq));
    const Q = Math.max(0.1, Math.min(18, band.q));
    const gainDb = Math.max(-24, Math.min(24, band.gain));

    const A = Math.pow(10, gainDb / 40);
    const w0 = 2 * Math.PI * f0 / fs;
    const sinW0 = Math.sin(w0);
    const cosW0 = Math.cos(w0);
    const alpha = sinW0 / (2 * Q);

    let b0, b1, b2, a0, a1, a2;

    switch (band.type) {
      case 'bell':
        b0 = 1 + alpha * A;
        b1 = -2 * cosW0;
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cosW0;
        a2 = 1 - alpha / A;
        break;

      case 'lowshelf': {
        const sqrtA = Math.sqrt(A);
        b0 = A * ((A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha);
        b1 = 2 * A * ((A - 1) - (A + 1) * cosW0);
        b2 = A * ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha);
        a0 = (A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha;
        a1 = -2 * ((A - 1) + (A + 1) * cosW0);
        a2 = (A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha;
        break;
      }

      case 'highshelf': {
        const sqrtA = Math.sqrt(A);
        b0 = A * ((A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha);
        b1 = -2 * A * ((A - 1) + (A + 1) * cosW0);
        b2 = A * ((A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha);
        a0 = (A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha;
        a1 = 2 * ((A - 1) - (A + 1) * cosW0);
        a2 = (A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha;
        break;
      }

      case 'highpass':
        b0 = (1 + cosW0) / 2;
        b1 = -(1 + cosW0);
        b2 = (1 + cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      case 'lowpass':
        b0 = (1 - cosW0) / 2;
        b1 = 1 - cosW0;
        b2 = (1 - cosW0) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      case 'notch':
        b0 = 1;
        b1 = -2 * cosW0;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      case 'bandpass':
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      case 'allpass':
        b0 = 1 - alpha;
        b1 = -2 * cosW0;
        b2 = 1 + alpha;
        a0 = 1 + alpha;
        a1 = -2 * cosW0;
        a2 = 1 - alpha;
        break;

      default:
        return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
    }

    // Normalize
    return {
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    };
  }

  processBiquadStereo(filter, inputL, inputR) {
    // Left channel
    const outputL = filter.b0 * inputL +
                    filter.b1 * filter.x1L +
                    filter.b2 * filter.x2L -
                    filter.a1 * filter.y1L -
                    filter.a2 * filter.y2L;
    filter.x2L = filter.x1L;
    filter.x1L = inputL;
    filter.y2L = filter.y1L;
    filter.y1L = outputL;

    // Right channel
    const outputR = filter.b0 * inputR +
                    filter.b1 * filter.x1R +
                    filter.b2 * filter.x2R -
                    filter.a1 * filter.y1R -
                    filter.a2 * filter.y2R;
    filter.x2R = filter.x1R;
    filter.x1R = inputR;
    filter.y2R = filter.y1R;
    filter.y1R = outputR;

    return [outputL, outputR];
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];
    const output = outputs[0];

    if (!input || !input[0]) return true;

    const inputL = input[0];
    const inputR = input[1] || input[0];
    const outputL = output[0];
    const outputR = output[1] || output[0];

    // Check bypass via SharedArrayBuffer
    if (this.controlData) {
      this.bypassed = this.controlData[${CONTROL_FLAGS.BYPASS}] === 1;
    }

    if (this.bypassed) {
      // Pass through
      outputL.set(inputL);
      outputR.set(inputR);
      return true;
    }

    // Choose processing path
    if (this.wasmReady && this.wasmEQ) {
      this.processWasm(inputL, inputR, outputL, outputR);
    } else {
      this.processJS(inputL, inputR, outputL, outputR);
    }

    return true;
  }

  processWasm(inputL, inputR, outputL, outputR) {
    // Create interleaved buffer for WASM
    const len = inputL.length;
    const interleaved = new Float32Array(len * 2);

    for (let i = 0; i < len; i++) {
      interleaved[i * 2] = inputL[i];
      interleaved[i * 2 + 1] = inputR[i];
    }

    // Process through WASM EQ
    this.wasmEQ.process_block(interleaved);

    // Process through WASM meter
    if (this.wasmMeter) {
      this.wasmMeter.process_block(interleaved);
    }

    // Process through WASM LUFS meter
    if (this.wasmLUFS) {
      this.wasmLUFS.process_block(interleaved);
    }

    // De-interleave output
    for (let i = 0; i < len; i++) {
      outputL[i] = interleaved[i * 2] * this.outputGain;
      outputR[i] = interleaved[i * 2 + 1] * this.outputGain;
    }

    // Update meter data in SharedArrayBuffer
    if (this.meterData && this.wasmMeter) {
      const peak = this.wasmMeter.get_peak();
      const peakHold = this.wasmMeter.get_peak_hold();
      const rms = this.wasmMeter.get_rms_and_reset();

      this.meterData[0] = peakHold[0];
      this.meterData[1] = peakHold[1];
      this.meterData[2] = rms[0];
      this.meterData[3] = rms[1];

      if (this.wasmLUFS) {
        this.meterData[4] = this.wasmLUFS.get_momentary_lufs();
        this.meterData[5] = this.wasmLUFS.get_integrated_lufs();
      }
    }
  }

  processJS(inputL, inputR, outputL, outputR) {
    const len = inputL.length;
    let peakL = 0, peakR = 0;
    let sumL = 0, sumR = 0;

    for (let i = 0; i < len; i++) {
      let sampleL = inputL[i];
      let sampleR = inputR[i];

      // Apply EQ filters in series
      for (const filter of this.filters) {
        if (filter.active) {
          [sampleL, sampleR] = this.processBiquadStereo(filter, sampleL, sampleR);
        }
      }

      // Apply output gain
      sampleL *= this.outputGain;
      sampleR *= this.outputGain;

      outputL[i] = sampleL;
      outputR[i] = sampleR;

      // Metering
      const absL = Math.abs(sampleL);
      const absR = Math.abs(sampleR);
      if (absL > peakL) peakL = absL;
      if (absR > peakR) peakR = absR;
      sumL += sampleL * sampleL;
      sumR += sampleR * sampleR;
    }

    // Update meter data in SharedArrayBuffer
    if (this.meterData) {
      // Peak with hold
      this.peakHoldL = Math.max(peakL, this.peakHoldL * 0.9995);
      this.peakHoldR = Math.max(peakR, this.peakHoldR * 0.9995);

      // RMS
      this.rmsSumL += sumL;
      this.rmsSumR += sumR;
      this.rmsCount += len;

      // Calculate RMS over ~100ms window
      if (this.rmsCount >= sampleRate * 0.1) {
        const rmsL = Math.sqrt(this.rmsSumL / this.rmsCount);
        const rmsR = Math.sqrt(this.rmsSumR / this.rmsCount);

        this.meterData[0] = this.peakHoldL;
        this.meterData[1] = this.peakHoldR;
        this.meterData[2] = rmsL;
        this.meterData[3] = rmsR;
        // Simplified LUFS approximation
        this.meterData[4] = -0.691 + 10 * Math.log10(Math.max((rmsL + rmsR) / 2, 1e-10));

        this.rmsSumL = 0;
        this.rmsSumR = 0;
        this.rmsCount = 0;
      }
    }
  }
}

registerProcessor('reelforge-dsp', ReelForgeDSPProcessor);
`;

// ============ Main Thread Controller ============

export class AudioWorkletDSP {
  private context: AudioContext | null = null;
  private workletNode: AudioWorkletNode | null = null;
  private sharedBuffer: SharedArrayBuffer | null = null;
  private meterData: Float32Array | null = null;
  private fftData: Float32Array | null = null;
  private controlData: Float32Array | null = null;
  private initialized = false;
  private _wasmLoaded = false;

  /**
   * Initialize the AudioWorklet DSP system.
   */
  async init(context: AudioContext): Promise<boolean> {
    if (this.initialized) return true;

    // Check SharedArrayBuffer support
    if (typeof SharedArrayBuffer === 'undefined') {
      console.warn('[AudioWorkletDSP] SharedArrayBuffer not available - falling back to standard processing');
      return false;
    }

    this.context = context;

    try {
      // Create worklet blob URL
      const blob = new Blob([WORKLET_CODE], { type: 'application/javascript' });
      const url = URL.createObjectURL(blob);

      // Add worklet module
      await context.audioWorklet.addModule(url);
      URL.revokeObjectURL(url);

      // Create worklet node
      this.workletNode = new AudioWorkletNode(context, 'reelforge-dsp', {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [2],
      });

      // Create SharedArrayBuffer
      const bufferBytes = BUFFER_LAYOUT.TOTAL_SIZE * Float32Array.BYTES_PER_ELEMENT;
      this.sharedBuffer = new SharedArrayBuffer(bufferBytes);

      // Create views
      this.meterData = new Float32Array(this.sharedBuffer, BUFFER_LAYOUT.METERS * 4, 8);
      this.fftData = new Float32Array(this.sharedBuffer, BUFFER_LAYOUT.FFT * 4, 256);
      this.controlData = new Float32Array(this.sharedBuffer, BUFFER_LAYOUT.CONTROL * 4, 8);

      // Send SharedArrayBuffer to worklet
      this.workletNode.port.postMessage({
        type: 'init',
        sharedBuffer: this.sharedBuffer,
      });

      this.initialized = true;

      // Try to load WASM
      await this.loadWasm();

      return true;
    } catch (error) {
      console.error('[AudioWorkletDSP] Initialization failed:', error);
      return false;
    }
  }

  /**
   * Load and send WASM module to worklet.
   */
  private async loadWasm(): Promise<boolean> {
    if (!this.workletNode || !this.context) return false;

    try {
      // Fetch WASM binary
      // wasm-pack generates: {crate_name}_bg.wasm
      // Crate name "reelforge-dsp" becomes "reelforge_dsp"
      const wasmResponse = await fetch('/wasm/reelforge_dsp_bg.wasm');
      if (!wasmResponse.ok) {
        console.warn('[AudioWorkletDSP] WASM file not found, using JS fallback');
        return false;
      }

      const wasmBinary = await wasmResponse.arrayBuffer();

      // Compile WASM module on main thread
      const wasmModule = await WebAssembly.compile(wasmBinary);

      // Send compiled module to worklet
      this.workletNode.port.postMessage({
        type: 'initWasm',
        wasmModule,
        sampleRate: this.context.sampleRate,
      });

      this._wasmLoaded = true;
      return true;
    } catch (error) {
      console.warn('[AudioWorkletDSP] WASM loading failed, using JS fallback:', error);
      return false;
    }
  }

  /**
   * Check if WASM module was loaded (sent to worklet).
   */
  isWasmLoaded(): boolean {
    return this._wasmLoaded;
  }

  /**
   * Check if WASM DSP is active (instantiated in worklet).
   */
  isWasmActive(): boolean {
    if (!this.controlData) return false;
    return this.controlData[CONTROL_FLAGS.WASM_READY] === 1;
  }

  /**
   * Get the AudioContext.
   */
  getContext(): AudioContext | null {
    return this.context;
  }

  /**
   * Get the AudioWorkletNode for connection to audio graph.
   */
  getNode(): AudioWorkletNode | null {
    return this.workletNode;
  }

  /**
   * Update EQ band configuration.
   */
  updateBands(bands: EQBandConfig[]): void {
    if (!this.workletNode) return;

    // Map string types to numbers for WASM
    const mappedBands = bands.map(band => ({
      ...band,
      typeNum: FILTER_TYPE_MAP[band.type] ?? FilterType.Bell,
    }));

    this.workletNode.port.postMessage({
      type: 'updateBands',
      bands: mappedBands,
    });
  }

  /**
   * Set bypass state.
   */
  setBypass(bypassed: boolean): void {
    // Write directly to SharedArrayBuffer for instant response
    if (this.controlData) {
      this.controlData[CONTROL_FLAGS.BYPASS] = bypassed ? 1 : 0;
    }

    // Also send via postMessage for state sync
    if (this.workletNode) {
      this.workletNode.port.postMessage({
        type: 'bypass',
        bypassed,
      });
    }
  }

  /**
   * Set output gain.
   */
  setOutputGain(gain: number): void {
    if (!this.workletNode) return;

    this.workletNode.port.postMessage({
      type: 'outputGain',
      gain: Math.max(0, Math.min(4, gain)), // Clamp 0-4x
    });
  }

  /**
   * Read current meter values from SharedArrayBuffer.
   * This is zero-copy - just reading from shared memory.
   */
  getMeterData(): MeterData | null {
    if (!this.meterData) return null;

    return {
      peakL: this.meterData[0],
      peakR: this.meterData[1],
      rmsL: this.meterData[2],
      rmsR: this.meterData[3],
      lufs: this.meterData[4],
    };
  }

  /**
   * Read FFT magnitude data from SharedArrayBuffer.
   */
  getFFTData(): Float32Array | null {
    return this.fftData;
  }

  /**
   * Connect source to DSP node.
   */
  connect(source: AudioNode): void {
    if (!this.workletNode) return;
    source.connect(this.workletNode);
  }

  /**
   * Connect DSP output to destination.
   */
  connectOutput(destination: AudioNode): void {
    if (!this.workletNode) return;
    this.workletNode.connect(destination);
  }

  /**
   * Disconnect all connections.
   */
  disconnect(): void {
    if (!this.workletNode) return;
    this.workletNode.disconnect();
  }

  /**
   * Dispose resources.
   */
  dispose(): void {
    this.disconnect();
    this.workletNode = null;
    this.sharedBuffer = null;
    this.meterData = null;
    this.fftData = null;
    this.controlData = null;
    this.initialized = false;
    this._wasmLoaded = false;
  }
}

// ============ Singleton Instance ============

let dspInstance: AudioWorkletDSP | null = null;

export function getAudioWorkletDSP(): AudioWorkletDSP {
  if (!dspInstance) {
    dspInstance = new AudioWorkletDSP();
  }
  return dspInstance;
}

export default AudioWorkletDSP;
