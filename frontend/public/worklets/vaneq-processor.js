/**
 * ReelForge M9.2 VanEQ Worklet Processor
 *
 * AudioWorklet processor for the VanEQ parametric equalizer.
 * Implements 6 cascaded biquad filters with smooth parameter updates.
 *
 * Message protocol:
 * - { type: 'update', bands: [...], outputGain: number }
 *
 * @module worklets/vaneq-processor
 */

// Biquad filter coefficients calculator
class BiquadCoefficients {
  /**
   * Calculate biquad coefficients for different filter types.
   * All filters use normalized angular frequency (omega = 2 * PI * freq / sampleRate)
   */
  static calculate(type, freq, gain, q, sampleRate) {
    const omega = (2 * Math.PI * freq) / sampleRate;
    const sinOmega = Math.sin(omega);
    const cosOmega = Math.cos(omega);
    const alpha = sinOmega / (2 * q);
    const A = Math.pow(10, gain / 40); // sqrt of linear gain

    let b0, b1, b2, a0, a1, a2;

    switch (type) {
      case 'bell':
      case 0: // peaking EQ
        b0 = 1 + alpha * A;
        b1 = -2 * cosOmega;
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha / A;
        break;

      case 'lowShelf':
      case 1:
        const sqrtALow = Math.sqrt(A);
        const sqrtA2alphaLow = 2 * sqrtALow * alpha;
        b0 = A * ((A + 1) - (A - 1) * cosOmega + sqrtA2alphaLow);
        b1 = 2 * A * ((A - 1) - (A + 1) * cosOmega);
        b2 = A * ((A + 1) - (A - 1) * cosOmega - sqrtA2alphaLow);
        a0 = (A + 1) + (A - 1) * cosOmega + sqrtA2alphaLow;
        a1 = -2 * ((A - 1) + (A + 1) * cosOmega);
        a2 = (A + 1) + (A - 1) * cosOmega - sqrtA2alphaLow;
        break;

      case 'highShelf':
      case 2:
        const sqrtAHigh = Math.sqrt(A);
        const sqrtA2alphaHigh = 2 * sqrtAHigh * alpha;
        b0 = A * ((A + 1) + (A - 1) * cosOmega + sqrtA2alphaHigh);
        b1 = -2 * A * ((A - 1) + (A + 1) * cosOmega);
        b2 = A * ((A + 1) + (A - 1) * cosOmega - sqrtA2alphaHigh);
        a0 = (A + 1) - (A - 1) * cosOmega + sqrtA2alphaHigh;
        a1 = 2 * ((A - 1) - (A + 1) * cosOmega);
        a2 = (A + 1) - (A - 1) * cosOmega - sqrtA2alphaHigh;
        break;

      case 'lowPass':
      case 'highCut': // legacy alias
      case 3: // lowpass filter
        b0 = (1 - cosOmega) / 2;
        b1 = 1 - cosOmega;
        b2 = (1 - cosOmega) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      case 'highPass':
      case 'lowCut': // legacy alias
      case 4: // highpass filter
        b0 = (1 + cosOmega) / 2;
        b1 = -(1 + cosOmega);
        b2 = (1 + cosOmega) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      case 'notch':
      case 5: // notch filter
        b0 = 1;
        b1 = -2 * cosOmega;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      case 'bandPass':
      case 6: // bandpass filter (constant skirt gain, peak gain = Q)
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      case 'tilt':
      case 7: // tilt shelf - combines low shelf boost with high shelf cut (or vice versa)
        // Tilt uses gain as the tilt amount: positive = bass boost/treble cut
        // Implemented as a modified low shelf with inverted high frequency response
        const tiltA = Math.pow(10, gain / 40);
        const tiltSqrtA = Math.sqrt(tiltA);
        const tiltAlpha = sinOmega / (2 * 0.707); // Fixed Q for smooth tilt
        const tilt2SqrtAAlpha = 2 * tiltSqrtA * tiltAlpha;
        // Low shelf coefficients with tilt character
        b0 = tiltA * ((tiltA + 1) - (tiltA - 1) * cosOmega + tilt2SqrtAAlpha);
        b1 = 2 * tiltA * ((tiltA - 1) - (tiltA + 1) * cosOmega);
        b2 = tiltA * ((tiltA + 1) - (tiltA - 1) * cosOmega - tilt2SqrtAAlpha);
        a0 = (tiltA + 1) + (tiltA - 1) * cosOmega + tilt2SqrtAAlpha;
        a1 = -2 * ((tiltA - 1) + (tiltA + 1) * cosOmega);
        a2 = (tiltA + 1) + (tiltA - 1) * cosOmega - tilt2SqrtAAlpha;
        break;

      default:
        // Bypass (unity gain)
        return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
    }

    // Normalize by a0
    return {
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    };
  }
}

// Single biquad filter state
class BiquadFilter {
  constructor() {
    // Filter state (per channel)
    this.x1 = [0, 0];
    this.x2 = [0, 0];
    this.y1 = [0, 0];
    this.y2 = [0, 0];

    // Current coefficients
    this.b0 = 1;
    this.b1 = 0;
    this.b2 = 0;
    this.a1 = 0;
    this.a2 = 0;

    // Target coefficients (for smoothing)
    this.targetB0 = 1;
    this.targetB1 = 0;
    this.targetB2 = 0;
    this.targetA1 = 0;
    this.targetA2 = 0;

    // Smoothing factor (adjust for smoothness vs responsiveness)
    this.smoothingFactor = 0.02;
  }

  setCoefficients(coeffs) {
    this.targetB0 = coeffs.b0;
    this.targetB1 = coeffs.b1;
    this.targetB2 = coeffs.b2;
    this.targetA1 = coeffs.a1;
    this.targetA2 = coeffs.a2;
  }

  setBypass() {
    this.targetB0 = 1;
    this.targetB1 = 0;
    this.targetB2 = 0;
    this.targetA1 = 0;
    this.targetA2 = 0;
  }

  /**
   * Reset filter state to zero (flush DC offset / denormals).
   */
  reset(channel) {
    this.x1[channel] = 0;
    this.x2[channel] = 0;
    this.y1[channel] = 0;
    this.y2[channel] = 0;
  }

  /**
   * Flush denormals - very small values that can cause CPU spikes.
   */
  flushDenormals(channel) {
    const DENORMAL_THRESHOLD = 1e-15;
    if (Math.abs(this.y1[channel]) < DENORMAL_THRESHOLD) this.y1[channel] = 0;
    if (Math.abs(this.y2[channel]) < DENORMAL_THRESHOLD) this.y2[channel] = 0;
    if (Math.abs(this.x1[channel]) < DENORMAL_THRESHOLD) this.x1[channel] = 0;
    if (Math.abs(this.x2[channel]) < DENORMAL_THRESHOLD) this.x2[channel] = 0;
  }

  process(input, output, channel) {
    const len = input.length;

    for (let i = 0; i < len; i++) {
      // Smooth coefficients
      this.b0 += (this.targetB0 - this.b0) * this.smoothingFactor;
      this.b1 += (this.targetB1 - this.b1) * this.smoothingFactor;
      this.b2 += (this.targetB2 - this.b2) * this.smoothingFactor;
      this.a1 += (this.targetA1 - this.a1) * this.smoothingFactor;
      this.a2 += (this.targetA2 - this.a2) * this.smoothingFactor;

      const x = input[i];
      const y =
        this.b0 * x +
        this.b1 * this.x1[channel] +
        this.b2 * this.x2[channel] -
        this.a1 * this.y1[channel] -
        this.a2 * this.y2[channel];

      // Update state
      this.x2[channel] = this.x1[channel];
      this.x1[channel] = x;
      this.y2[channel] = this.y1[channel];
      this.y1[channel] = y;

      output[i] = y;
    }

    // Flush denormals at end of block to prevent CPU spikes
    this.flushDenormals(channel);
  }
}

// Band type string to index mapping
// Must match VALID_VANEQ_BAND_TYPES order in vaneqTypes.ts
const BAND_TYPE_MAP = {
  bell: 0,       // peaking EQ
  lowShelf: 1,   // low shelf
  highShelf: 2,  // high shelf
  lowPass: 3,    // lowpass filter
  highPass: 4,   // highpass filter
  notch: 5,      // notch filter
  bandPass: 6,   // bandpass filter
  tilt: 7,       // tilt shelf (custom)
  // Legacy aliases for backwards compatibility
  lowCut: 4,     // alias for highPass
  highCut: 3,    // alias for lowPass
};

// Idle detection constants
const IDLE_THRESHOLD_DB = -120; // -120 dBFS threshold
const IDLE_THRESHOLD_LINEAR = Math.pow(10, IDLE_THRESHOLD_DB / 20); // ~1e-6
const IDLE_THRESHOLD_SQUARED = IDLE_THRESHOLD_LINEAR * IDLE_THRESHOLD_LINEAR;
const IDLE_SAMPLES_THRESHOLD = 10000; // ~200ms at 48kHz before entering IDLE
const ACTIVE_SAMPLES_THRESHOLD = 128; // Quick return to active

class VanEqProcessor extends AudioWorkletProcessor {
  constructor() {
    super();

    // Create 8 biquad filters
    this.filters = [];
    for (let i = 0; i < 8; i++) {
      this.filters.push(new BiquadFilter());
    }

    // Solo filter - used when a band is soloed to isolate its frequency
    this.soloFilter = new BiquadFilter();

    // Band enabled states (all disabled by default = unity passthrough)
    this.bandEnabled = [false, false, false, false, false, false, false, false];

    // Band params for solo filter creation
    this.bandParams = [];
    for (let i = 0; i < 8; i++) {
      this.bandParams.push({ freqHz: 1000, q: 1, type: 0 });
    }

    // Solo state (-1 = no solo, 0-7 = solo that band)
    this.soloedBand = -1;

    // Output gain (linear)
    this.outputGain = 1;
    this.targetOutputGain = 1;
    this.gainSmoothingFactor = 0.01;

    // Unity passthrough optimization flag
    // True when all bands disabled AND outputGain is unity (1.0)
    this._isUnityPassthrough = true;

    // Temporary buffer for cascaded processing
    this.tempBuffer = null;

    // Idle detection state
    this.isIdle = true; // Start in IDLE state
    this.silentSampleCount = IDLE_SAMPLES_THRESHOLD; // Start as idle
    this.activeSampleCount = 0;
    this.lastReportedIdle = true;

    // Handle messages
    this.port.onmessage = (event) => {
      this.handleMessage(event.data);
    };
  }

  handleMessage(data) {
    if (data.type === 'update') {
      const { bands, outputGain, soloedBand } = data;

      // Update output gain
      if (typeof outputGain === 'number') {
        this.targetOutputGain = Math.pow(10, outputGain / 20);
      }

      // Update solo state (-1 = no solo, 0-7 = solo that band)
      if (typeof soloedBand === 'number') {
        this.soloedBand = soloedBand;
      }

      // Update each band
      if (Array.isArray(bands)) {
        bands.forEach((band, i) => {
          if (i >= this.filters.length) return;

          this.bandEnabled[i] = band.enabled;

          // Store band params for solo filter
          this.bandParams[i] = {
            freqHz: band.freqHz,
            q: band.q,
            type: typeof band.type === 'string' ? (BAND_TYPE_MAP[band.type] ?? 0) : band.type
          };

          if (band.enabled) {
            // Map type string to number if needed
            let typeNum = band.type;
            if (typeof band.type === 'string') {
              typeNum = BAND_TYPE_MAP[band.type] ?? 0;
            }

            const coeffs = BiquadCoefficients.calculate(
              typeNum,
              band.freqHz,
              band.gainDb,
              band.q,
              sampleRate
            );
            this.filters[i].setCoefficients(coeffs);
          } else {
            this.filters[i].setBypass();
          }
        });
      }

      // Update solo filter when solo state changes
      if (this.soloedBand >= 0 && this.soloedBand < 8) {
        const soloParams = this.bandParams[this.soloedBand];
        // Use bandpass filter centered on the band's frequency
        // Q determines how narrow the bandpass is - higher Q = narrower
        const soloCoeffs = BiquadCoefficients.calculate(
          6, // bandpass
          soloParams.freqHz,
          0, // gain not used for bandpass
          soloParams.q * 0.5, // Use half Q for wider audible range
          sampleRate
        );
        this.soloFilter.setCoefficients(soloCoeffs);
      }

      // Update unity passthrough flag
      // Unity when: all bands disabled AND outputGain is 0dB (linear 1.0) AND no solo
      const anyBandEnabled = this.bandEnabled.some(Boolean);
      const isUnityGain = Math.abs(this.targetOutputGain - 1.0) < 0.0001;
      this._isUnityPassthrough = !anyBandEnabled && isUnityGain && this.soloedBand === -1;
    } else if (data.type === 'reset') {
      // Reset all filter states (clears DC offset / artifacts)
      this.resetAllFilters();
    }
  }

  /**
   * Reset all filter states to zero.
   * Call when audio stops to clear any residual DC offset.
   */
  resetAllFilters() {
    for (let f = 0; f < this.filters.length; f++) {
      this.filters[f].reset(0);
      this.filters[f].reset(1);
    }
    // Reset solo filter too
    this.soloFilter.reset(0);
    this.soloFilter.reset(1);
    // Reset gain to target immediately
    this.outputGain = this.targetOutputGain;
    // Reset to idle state
    this.isIdle = true;
    this.silentSampleCount = IDLE_SAMPLES_THRESHOLD;
    this.activeSampleCount = 0;
  }

  /**
   * Compute RMS (mean square) of a buffer.
   * Returns true if signal is above idle threshold.
   */
  hasSignal(buffer) {
    if (!buffer || buffer.length === 0) return false;

    let sumSquares = 0;
    for (let i = 0; i < buffer.length; i++) {
      sumSquares += buffer[i] * buffer[i];
    }
    const meanSquare = sumSquares / buffer.length;

    // Compare mean square to threshold squared (avoid sqrt)
    return meanSquare > IDLE_THRESHOLD_SQUARED;
  }

  /**
   * Update idle state and report changes.
   */
  updateIdleState(hasSignalInBlock, blockSize) {
    if (hasSignalInBlock) {
      // Signal detected
      this.activeSampleCount += blockSize;
      this.silentSampleCount = 0;

      if (this.isIdle && this.activeSampleCount >= ACTIVE_SAMPLES_THRESHOLD) {
        this.isIdle = false;
      }
    } else {
      // No signal
      this.silentSampleCount += blockSize;
      this.activeSampleCount = 0;

      if (!this.isIdle && this.silentSampleCount >= IDLE_SAMPLES_THRESHOLD) {
        this.isIdle = true;
        // Reset filters when going idle to clear any residual
        this.resetAllFilters();
      }
    }

    // Report state changes to main thread
    if (this.isIdle !== this.lastReportedIdle) {
      this.lastReportedIdle = this.isIdle;
      this.port.postMessage({ type: 'idle', isIdle: this.isIdle });
    }
  }

  process(inputs, outputs) {
    const input = inputs[0];
    const output = outputs[0];

    // SILENCE GUARANTEE: Always zero output buffers first
    // This ensures no uninitialized memory leaks through
    if (output && output.length) {
      for (let ch = 0; ch < output.length; ch++) {
        if (output[ch]) {
          output[ch].fill(0);
        }
      }
    }

    // If no valid input, output is already silence
    if (!input || !input.length || !output || !output.length) {
      // Update idle state with no signal
      this.updateIdleState(false, 128);
      return true;
    }

    // Verify input channel 0 exists and has data
    const inputChannel0 = input[0];
    if (!inputChannel0 || inputChannel0.length === 0) {
      this.updateIdleState(false, 128);
      return true;
    }

    const numChannels = Math.min(input.length, output.length);
    const blockSize = inputChannel0.length;

    // Check for input signal (any channel)
    let hasSignalInBlock = false;
    let maxSample = 0;
    for (let ch = 0; ch < numChannels; ch++) {
      if (input[ch]) {
        for (let i = 0; i < input[ch].length; i++) {
          const abs = Math.abs(input[ch][i]);
          if (abs > maxSample) maxSample = abs;
        }
        if (this.hasSignal(input[ch])) {
          hasSignalInBlock = true;
        }
      }
    }

    // Log every 100th block to see if signal is arriving
    if (!this._logCounter) this._logCounter = 0;
    this._logCounter++;
    if (this._logCounter % 100 === 0 && maxSample > 0.0001) {
      console.log('[VanEQ Worklet] Block processed:', {
        maxSample: maxSample.toFixed(6),
        hasSignal: hasSignalInBlock,
        isIdle: this.isIdle,
        isUnityPassthrough: this._isUnityPassthrough
      });
    }

    // Update idle state
    this.updateIdleState(hasSignalInBlock, blockSize);

    // If idle and no signal, output is already zeroed - we're done
    // DISABLED FOR DEBUGGING - always process signal
    // if (this.isIdle && !hasSignalInBlock) {
    //   return true;
    // }

    // UNITY PASSTHROUGH: When all bands disabled and gain is 0dB,
    // copy input directly to output without any processing.
    // This guarantees true unity gain with zero floating-point error.
    if (this._isUnityPassthrough && Math.abs(this.outputGain - 1.0) < 0.0001) {
      for (let ch = 0; ch < numChannels; ch++) {
        const inputChannel = input[ch];
        const outputChannel = output[ch];
        if (inputChannel && outputChannel) {
          outputChannel.set(inputChannel);
        }
      }
      return true;
    }

    // Ensure temp buffer exists
    if (!this.tempBuffer || this.tempBuffer.length !== blockSize) {
      this.tempBuffer = new Float32Array(blockSize);
    }

    // Process each channel
    for (let ch = 0; ch < numChannels; ch++) {
      const inputChannel = input[ch];
      const outputChannel = output[ch];

      // Skip if channels are missing
      if (!inputChannel || !outputChannel) continue;

      // Copy input to output (we'll process in place through filters)
      outputChannel.set(inputChannel);

      // SOLO MODE: When a band is soloed, apply bandpass filter to isolate its frequency
      // This lets you hear ONLY the frequency range of that band
      if (this.soloedBand >= 0 && this.soloedBand < this.filters.length) {
        // Apply the solo bandpass filter to isolate the frequency
        this.soloFilter.process(outputChannel, this.tempBuffer, ch);
        outputChannel.set(this.tempBuffer);
      } else {
        // NORMAL MODE: Apply ONLY enabled filters in cascade
        // CRITICAL: Skip disabled filters entirely - don't process through unity coefficients
        // This avoids accumulating floating-point errors from coefficient smoothing
        for (let f = 0; f < this.filters.length; f++) {
          if (!this.bandEnabled[f]) continue; // TRUE BYPASS: skip disabled filters completely

          // Process from output to temp, then temp back to output
          this.filters[f].process(outputChannel, this.tempBuffer, ch);
          outputChannel.set(this.tempBuffer);
        }
      }

      // Apply output gain with smoothing
      // OPTIMIZATION: Skip gain stage entirely when targetOutputGain is unity
      const isGainUnity = Math.abs(this.targetOutputGain - 1.0) < 0.0001;
      if (!isGainUnity) {
        for (let i = 0; i < blockSize; i++) {
          this.outputGain += (this.targetOutputGain - this.outputGain) * this.gainSmoothingFactor;
          outputChannel[i] *= this.outputGain;
        }
      } else {
        // Snap to exactly 1.0 when at unity (avoid floating-point drift)
        this.outputGain = 1.0;
      }
    }

    return true;
  }
}

registerProcessor('vaneq-processor', VanEqProcessor);
