/**
 * ReelForge WASM DSP AudioWorklet Processor
 *
 * High-performance DSP processing in AudioWorklet thread.
 * Uses Rust WASM with SIMD for 10-50x faster processing.
 *
 * @ts-nocheck - This runs in AudioWorklet context
 */

// WASM module (loaded dynamically)
let wasmModule = null;
let wasmReady = false;

/**
 * WASM DSP Processor - Full insert chain in AudioWorklet
 */
class WasmDspProcessor extends AudioWorkletProcessor {
  constructor() {
    super();

    this.sampleRate = sampleRate; // Global in AudioWorklet scope

    // DSP state
    this.state = {
      bypass: false,
      inputGain: 1.0,
      outputGain: 1.0,

      // EQ (up to 8 bands)
      eqEnabled: false,
      eqCoeffs: [], // Array of [b0, b1, b2, a1, a2]
      eqStates: [
        // Per-channel, per-band: [[z1, z2], [z1, z2], ...]
        [],
        [],
      ],

      // Compressor
      compressorEnabled: false,
      compressorConfig: {
        thresholdDb: -18,
        ratio: 4,
        attackSec: 0.01,
        releaseSec: 0.1,
        kneeDb: 6,
        makeupDb: 0,
      },
      compressorState: new Float32Array([0, 0]), // [envelope, gainReductionDb]

      // Limiter
      limiterEnabled: false,
      limiterConfig: {
        ceilingDb: -0.3,
        releaseSec: 0.05,
      },
      limiterState: new Float32Array([0, 1]), // [envelope, gain]
    };

    // Metering
    this.meterInterval = 2048; // Samples between meter updates
    this.meterCounter = 0;
    this.meterPeakL = 0;
    this.meterPeakR = 0;
    this.meterRmsL = 0;
    this.meterRmsR = 0;

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

      case 'set-bypass':
        this.state.bypass = data.bypass;
        break;

      case 'set-input-gain':
        this.state.inputGain = data.gain;
        break;

      case 'set-output-gain':
        this.state.outputGain = data.gain;
        break;

      case 'set-eq':
        this.setEQ(data.coeffs);
        break;

      case 'set-compressor':
        this.state.compressorEnabled = data.enabled;
        if (data.config) {
          this.state.compressorConfig = data.config;
        }
        break;

      case 'set-limiter':
        this.state.limiterEnabled = data.enabled;
        if (data.config) {
          this.state.limiterConfig = data.config;
        }
        break;

      case 'reset':
        this.resetState();
        break;
    }
  }

  async initWasm(wasmUrl) {
    try {
      const module = await import(wasmUrl);
      await module.default();
      wasmModule = module;
      wasmReady = true;
      this.port.postMessage({ type: 'wasm-ready' });
    } catch (error) {
      this.port.postMessage({
        type: 'error',
        error: String(error),
      });
    }
  }

  setEQ(coeffs) {
    if (!coeffs || coeffs.length === 0) {
      this.state.eqEnabled = false;
      this.state.eqCoeffs = [];
      return;
    }

    this.state.eqEnabled = true;
    this.state.eqCoeffs = coeffs.map((c) => new Float32Array([c.b0, c.b1, c.b2, c.a1, c.a2]));

    // Initialize per-channel, per-band states
    for (let ch = 0; ch < 2; ch++) {
      while (this.state.eqStates[ch].length < coeffs.length) {
        this.state.eqStates[ch].push(new Float32Array(2)); // [z1, z2]
      }
    }
  }

  resetState() {
    // Reset EQ states
    for (let ch = 0; ch < 2; ch++) {
      this.state.eqStates[ch].forEach((s) => s.fill(0));
    }
    // Reset compressor
    this.state.compressorState.fill(0);
    // Reset limiter
    this.state.limiterState[0] = 0;
    this.state.limiterState[1] = 1;
    // Reset meters
    this.meterPeakL = 0;
    this.meterPeakR = 0;
    this.meterRmsL = 0;
    this.meterRmsR = 0;
  }

  process(inputs, outputs, _parameters) {
    const input = inputs[0];
    const output = outputs[0];

    // No input - pass silence
    if (!input || input.length === 0) {
      return true;
    }

    // Bypass mode - pass through
    if (this.state.bypass) {
      for (let ch = 0; ch < output.length; ch++) {
        if (input[ch]) {
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
      this.processFallback(output);
    }

    // Update metering
    this.updateMetering(output);

    return true;
  }

  processWithWasm(channels) {
    const numChannels = Math.min(channels.length, 2);

    // Apply input gain (SIMD)
    if (this.state.inputGain !== 1.0) {
      for (let ch = 0; ch < numChannels; ch++) {
        wasmModule.wasm_apply_gain_simd(channels[ch], this.state.inputGain);
      }
    }

    // Apply EQ bands
    if (this.state.eqEnabled) {
      for (let ch = 0; ch < numChannels; ch++) {
        const samples = channels[ch];
        for (let i = 0; i < this.state.eqCoeffs.length; i++) {
          const coeffs = this.state.eqCoeffs[i];
          const state = this.state.eqStates[ch][i];
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

    // Apply compressor (stereo linked)
    if (this.state.compressorEnabled && numChannels >= 2) {
      // Interleave stereo for linked compression
      const interleaved = this.interleave(channels[0], channels[1]);
      const cfg = this.state.compressorConfig;

      wasmModule.wasm_process_compressor_stereo(
        interleaved,
        cfg.thresholdDb,
        cfg.ratio,
        cfg.attackSec,
        cfg.releaseSec,
        cfg.kneeDb,
        cfg.makeupDb,
        this.sampleRate,
        this.state.compressorState
      );

      // Deinterleave back
      this.deinterleave(interleaved, channels[0], channels[1]);
    }

    // Apply limiter
    if (this.state.limiterEnabled) {
      for (let ch = 0; ch < numChannels; ch++) {
        wasmModule.wasm_process_limiter(
          channels[ch],
          this.state.limiterConfig.ceilingDb,
          this.state.limiterConfig.releaseSec,
          this.sampleRate,
          this.state.limiterState
        );
      }
    }

    // Apply output gain (SIMD)
    if (this.state.outputGain !== 1.0) {
      for (let ch = 0; ch < numChannels; ch++) {
        wasmModule.wasm_apply_gain_simd(channels[ch], this.state.outputGain);
      }
    }
  }

  processFallback(channels) {
    // Simple JS fallback
    const gain = this.state.inputGain * this.state.outputGain;
    if (gain !== 1.0) {
      for (const samples of channels) {
        for (let i = 0; i < samples.length; i++) {
          samples[i] *= gain;
        }
      }
    }
  }

  interleave(left, right) {
    const len = left.length;
    const interleaved = new Float32Array(len * 2);
    for (let i = 0; i < len; i++) {
      interleaved[i * 2] = left[i];
      interleaved[i * 2 + 1] = right[i];
    }
    return interleaved;
  }

  deinterleave(interleaved, left, right) {
    const len = left.length;
    for (let i = 0; i < len; i++) {
      left[i] = interleaved[i * 2];
      right[i] = interleaved[i * 2 + 1];
    }
  }

  updateMetering(channels) {
    if (channels.length < 2) return;

    const left = channels[0];
    const right = channels[1];

    // Accumulate peak/RMS
    if (wasmReady && wasmModule) {
      this.meterPeakL = Math.max(this.meterPeakL, wasmModule.wasm_calculate_peak_simd(left));
      this.meterPeakR = Math.max(this.meterPeakR, wasmModule.wasm_calculate_peak_simd(right));
      this.meterRmsL = wasmModule.wasm_calculate_rms_simd(left);
      this.meterRmsR = wasmModule.wasm_calculate_rms_simd(right);
    } else {
      // JS fallback
      for (let i = 0; i < left.length; i++) {
        this.meterPeakL = Math.max(this.meterPeakL, Math.abs(left[i]));
        this.meterPeakR = Math.max(this.meterPeakR, Math.abs(right[i]));
      }
    }

    // Send meter data periodically
    this.meterCounter += left.length;
    if (this.meterCounter >= this.meterInterval) {
      this.port.postMessage({
        type: 'meter',
        peakL: this.meterPeakL,
        peakR: this.meterPeakR,
        rmsL: this.meterRmsL,
        rmsR: this.meterRmsR,
        gainReduction: this.state.compressorState[1],
      });

      // Reset for next interval
      this.meterPeakL = 0;
      this.meterPeakR = 0;
      this.meterCounter = 0;
    }
  }
}

registerProcessor('wasm-dsp-processor', WasmDspProcessor);
