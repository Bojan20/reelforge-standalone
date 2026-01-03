/**
 * ReelForge DSP AudioWorklet Processor
 *
 * Runs in AudioWorklet thread with WASM DSP kernel.
 * This file is loaded as a separate module by AudioWorkletNode.
 *
 * @ts-nocheck - This runs in AudioWorklet context, not main thread
 */

// WASM module will be loaded dynamically
let wasmModule = null;
let wasmReady = false;

/**
 * DSP Processor - runs WASM DSP in AudioWorklet
 */
class DspProcessor extends AudioWorkletProcessor {
  constructor() {
    super();

    this.sampleRate = sampleRate; // Global in AudioWorklet scope
    this.state = {
      biquadStates: [new Float32Array(2), new Float32Array(2)],
      biquadCoeffs: null,
      compressorState: new Float32Array(2),
      limiterState: new Float32Array([0, 1]), // [envelope, gain]
      delayBuffer: null,
      delayState: new Float32Array(1),
      gain: 1.0,
      bypass: false,
    };

    // Handle messages from main thread
    this.port.onmessage = (event) => {
      this.handleMessage(event.data);
    };

    // Signal ready
    this.port.postMessage({ type: 'ready' });
  }

  handleMessage(data) {
    switch (data.type) {
      case 'init-wasm':
        this.initWasm(data.wasmUrl);
        break;

      case 'set-gain':
        this.state.gain = data.value;
        break;

      case 'set-bypass':
        this.state.bypass = data.value;
        break;

      case 'set-biquad':
        this.state.biquadCoeffs = data.coeffs ? new Float32Array(data.coeffs) : null;
        break;

      case 'set-compressor':
        if (data.reset) {
          this.state.compressorState.fill(0);
        }
        break;

      case 'set-limiter':
        if (data.reset) {
          this.state.limiterState[0] = 0;
          this.state.limiterState[1] = 1;
        }
        break;

      case 'init-delay':
        const maxDelaySec = data.maxDelaySec || 2.0;
        const maxSamples = Math.ceil(maxDelaySec * this.sampleRate);
        this.state.delayBuffer = new Float32Array(maxSamples);
        this.state.delayState[0] = 0;
        break;

      case 'reset':
        this.resetState();
        break;
    }
  }

  async initWasm(wasmUrl) {
    try {
      // Dynamic import of WASM module
      const module = await import(wasmUrl);
      await module.default();
      wasmModule = module;
      wasmReady = true;
      this.port.postMessage({ type: 'wasm-ready' });
    } catch (error) {
      this.port.postMessage({
        type: 'wasm-error',
        error: String(error),
      });
    }
  }

  resetState() {
    this.state.biquadStates.forEach((s) => s.fill(0));
    this.state.compressorState.fill(0);
    this.state.limiterState[0] = 0;
    this.state.limiterState[1] = 1;
    if (this.state.delayBuffer) {
      this.state.delayBuffer.fill(0);
    }
    this.state.delayState[0] = 0;
  }

  process(inputs, outputs, _parameters) {
    const input = inputs[0];
    const output = outputs[0];

    // No input or bypass - pass through
    if (!input || input.length === 0 || this.state.bypass) {
      for (let ch = 0; ch < output.length; ch++) {
        if (input && input[ch]) {
          output[ch].set(input[ch]);
        }
      }
      return true;
    }

    // Copy input to output for in-place processing
    for (let ch = 0; ch < output.length; ch++) {
      if (input[ch]) {
        output[ch].set(input[ch]);
      }
    }

    // Process with WASM if available
    if (wasmReady && wasmModule) {
      this.processWithWasm(output);
    } else {
      // Fallback: just apply gain
      this.processFallback(output);
    }

    return true;
  }

  processWithWasm(channels) {
    if (!wasmModule) return;

    for (let ch = 0; ch < channels.length; ch++) {
      const samples = channels[ch];

      // Apply gain
      if (this.state.gain !== 1.0) {
        wasmModule.wasm_apply_gain(samples, this.state.gain);
      }

      // Apply biquad filter if configured
      if (this.state.biquadCoeffs) {
        const coeffs = this.state.biquadCoeffs;
        const state = this.state.biquadStates[ch] || this.state.biquadStates[0];
        wasmModule.wasm_process_biquad(
          samples,
          coeffs[0],
          coeffs[1],
          coeffs[2],
          coeffs[3],
          coeffs[4],
          state
        );
      }
    }
  }

  processFallback(channels) {
    // Simple JS fallback when WASM not available
    const gain = this.state.gain;
    if (gain !== 1.0) {
      for (const samples of channels) {
        for (let i = 0; i < samples.length; i++) {
          samples[i] *= gain;
        }
      }
    }
  }
}

registerProcessor('dsp-processor', DspProcessor);
