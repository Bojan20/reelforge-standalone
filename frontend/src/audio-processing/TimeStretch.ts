/**
 * ReelForge Time Stretch Engine
 *
 * Phase vocoder-based time stretching and pitch shifting.
 * Professional quality with minimal artifacts.
 *
 * @module audio-processing/TimeStretch
 */

// ============ Types ============

export type TimeStretchAlgorithm = 'phase-vocoder' | 'wsola' | 'granular';
export type WindowType = 'hann' | 'hamming' | 'blackman' | 'kaiser';

export interface TimeStretchOptions {
  algorithm?: TimeStretchAlgorithm;
  stretchFactor: number; // 0.5 = half speed, 2.0 = double speed
  preservePitch?: boolean;
  fftSize?: number;
  hopSize?: number;
  windowType?: WindowType;
}

export interface PitchShiftOptions {
  algorithm?: TimeStretchAlgorithm;
  semitones: number;
  preserveFormants?: boolean;
  fftSize?: number;
}

export interface TimeStretchResult {
  buffer: Float32Array;
  actualStretchFactor: number;
  processingTime: number;
}

// ============ Window Functions ============

function createWindow(type: WindowType, size: number): Float32Array {
  const window = new Float32Array(size);

  for (let i = 0; i < size; i++) {
    const n = i / (size - 1);

    switch (type) {
      case 'hann':
        window[i] = 0.5 * (1 - Math.cos(2 * Math.PI * n));
        break;
      case 'hamming':
        window[i] = 0.54 - 0.46 * Math.cos(2 * Math.PI * n);
        break;
      case 'blackman':
        window[i] = 0.42 - 0.5 * Math.cos(2 * Math.PI * n) + 0.08 * Math.cos(4 * Math.PI * n);
        break;
      case 'kaiser':
        // Kaiser with beta = 5
        const beta = 5;
        const x = 2 * n - 1;
        window[i] = bessel0(beta * Math.sqrt(1 - x * x)) / bessel0(beta);
        break;
    }
  }

  return window;
}

function bessel0(x: number): number {
  let sum = 1;
  let term = 1;
  const x2 = x * x / 4;

  for (let k = 1; k < 20; k++) {
    term *= x2 / (k * k);
    sum += term;
    if (term < 1e-10) break;
  }

  return sum;
}

// ============ FFT Implementation ============

class FFT {
  private size: number;
  private cosTable: Float32Array;
  private sinTable: Float32Array;
  private reverseTable: Uint32Array;

  constructor(size: number) {
    this.size = size;
    this.cosTable = new Float32Array(size);
    this.sinTable = new Float32Array(size);
    this.reverseTable = new Uint32Array(size);

    // Build twiddle factors
    for (let i = 0; i < size; i++) {
      const angle = -2 * Math.PI * i / size;
      this.cosTable[i] = Math.cos(angle);
      this.sinTable[i] = Math.sin(angle);
    }

    // Build bit-reversal table
    const bits = Math.log2(size);
    for (let i = 0; i < size; i++) {
      let reversed = 0;
      for (let j = 0; j < bits; j++) {
        reversed = (reversed << 1) | ((i >> j) & 1);
      }
      this.reverseTable[i] = reversed;
    }
  }

  forward(real: Float32Array, imag: Float32Array): void {
    const n = this.size;

    // Bit-reversal permutation
    for (let i = 0; i < n; i++) {
      const j = this.reverseTable[i];
      if (i < j) {
        [real[i], real[j]] = [real[j], real[i]];
        [imag[i], imag[j]] = [imag[j], imag[i]];
      }
    }

    // Cooley-Tukey FFT
    for (let size = 2; size <= n; size *= 2) {
      const halfSize = size / 2;
      const step = n / size;

      for (let i = 0; i < n; i += size) {
        for (let j = 0; j < halfSize; j++) {
          const k = j * step;
          const evenIndex = i + j;
          const oddIndex = i + j + halfSize;

          const tReal = this.cosTable[k] * real[oddIndex] - this.sinTable[k] * imag[oddIndex];
          const tImag = this.sinTable[k] * real[oddIndex] + this.cosTable[k] * imag[oddIndex];

          real[oddIndex] = real[evenIndex] - tReal;
          imag[oddIndex] = imag[evenIndex] - tImag;
          real[evenIndex] += tReal;
          imag[evenIndex] += tImag;
        }
      }
    }
  }

  inverse(real: Float32Array, imag: Float32Array): void {
    // Conjugate
    for (let i = 0; i < this.size; i++) {
      imag[i] = -imag[i];
    }

    // Forward FFT
    this.forward(real, imag);

    // Conjugate and scale
    const scale = 1 / this.size;
    for (let i = 0; i < this.size; i++) {
      real[i] *= scale;
      imag[i] = -imag[i] * scale;
    }
  }
}

// ============ Phase Vocoder ============

class PhaseVocoder {
  private fftSize: number;
  private hopSize: number;
  private window: Float32Array;
  private fft: FFT;

  // Phase tracking
  private lastPhase: Float32Array;
  private sumPhase: Float32Array;

  constructor(fftSize: number, hopSize: number, windowType: WindowType = 'hann') {
    this.fftSize = fftSize;
    this.hopSize = hopSize;
    this.window = createWindow(windowType, fftSize);
    this.fft = new FFT(fftSize);

    this.lastPhase = new Float32Array(fftSize);
    this.sumPhase = new Float32Array(fftSize);
  }

  reset(): void {
    this.lastPhase.fill(0);
    this.sumPhase.fill(0);
  }

  /**
   * Time stretch using phase vocoder.
   */
  timeStretch(input: Float32Array, stretchFactor: number): Float32Array {
    const outputLength = Math.round(input.length * stretchFactor);
    const output = new Float32Array(outputLength);
    const outputHop = Math.round(this.hopSize * stretchFactor);

    const real = new Float32Array(this.fftSize);
    const imag = new Float32Array(this.fftSize);
    const magnitude = new Float32Array(this.fftSize);
    const phase = new Float32Array(this.fftSize);

    const freqPerBin = 2 * Math.PI / this.fftSize;
    const expectedPhaseChange = freqPerBin * this.hopSize;

    let inputPos = 0;
    let outputPos = 0;

    this.reset();

    while (inputPos + this.fftSize < input.length && outputPos + this.fftSize < outputLength) {
      // Analysis: window and FFT
      for (let i = 0; i < this.fftSize; i++) {
        real[i] = input[inputPos + i] * this.window[i];
        imag[i] = 0;
      }
      this.fft.forward(real, imag);

      // Convert to magnitude/phase
      for (let i = 0; i < this.fftSize; i++) {
        magnitude[i] = Math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
        phase[i] = Math.atan2(imag[i], real[i]);
      }

      // Phase adjustment
      for (let i = 0; i < this.fftSize; i++) {
        // Calculate phase difference
        let phaseDiff = phase[i] - this.lastPhase[i];
        this.lastPhase[i] = phase[i];

        // Subtract expected phase change
        phaseDiff -= i * expectedPhaseChange;

        // Wrap to [-PI, PI]
        while (phaseDiff > Math.PI) phaseDiff -= 2 * Math.PI;
        while (phaseDiff < -Math.PI) phaseDiff += 2 * Math.PI;

        // Calculate true frequency
        const trueFreq = i * freqPerBin + phaseDiff / this.hopSize;

        // Accumulate phase
        this.sumPhase[i] += outputHop * trueFreq;
      }

      // Synthesis: convert back to real/imag
      for (let i = 0; i < this.fftSize; i++) {
        real[i] = magnitude[i] * Math.cos(this.sumPhase[i]);
        imag[i] = magnitude[i] * Math.sin(this.sumPhase[i]);
      }

      // Inverse FFT
      this.fft.inverse(real, imag);

      // Overlap-add with window
      for (let i = 0; i < this.fftSize; i++) {
        if (outputPos + i < outputLength) {
          output[outputPos + i] += real[i] * this.window[i];
        }
      }

      inputPos += this.hopSize;
      outputPos += outputHop;
    }

    // Normalize by overlap factor
    const overlapFactor = this.fftSize / outputHop;
    for (let i = 0; i < outputLength; i++) {
      output[i] /= overlapFactor * 0.5;
    }

    return output;
  }

  /**
   * Pitch shift using phase vocoder + resampling.
   */
  pitchShift(input: Float32Array, semitones: number): Float32Array {
    const pitchFactor = Math.pow(2, semitones / 12);

    // Time stretch to compensate for resampling
    const stretched = this.timeStretch(input, pitchFactor);

    // Resample
    const output = new Float32Array(input.length);
    for (let i = 0; i < input.length; i++) {
      const srcPos = i * pitchFactor;
      const srcIndex = Math.floor(srcPos);
      const frac = srcPos - srcIndex;

      if (srcIndex + 1 < stretched.length) {
        // Linear interpolation
        output[i] = stretched[srcIndex] * (1 - frac) + stretched[srcIndex + 1] * frac;
      } else if (srcIndex < stretched.length) {
        output[i] = stretched[srcIndex];
      }
    }

    return output;
  }
}

// ============ Time Stretch Engine ============

export class TimeStretchEngine {
  private defaultFftSize = 4096;
  private defaultHopSize = 1024;
  private defaultWindowType: WindowType = 'hann';

  /**
   * Time stretch audio buffer.
   */
  timeStretch(
    input: Float32Array,
    options: TimeStretchOptions
  ): TimeStretchResult {
    const startTime = performance.now();

    const fftSize = options.fftSize ?? this.defaultFftSize;
    const hopSize = options.hopSize ?? this.defaultHopSize;
    const windowType = options.windowType ?? this.defaultWindowType;

    const vocoder = new PhaseVocoder(fftSize, hopSize, windowType);
    const buffer = vocoder.timeStretch(input, options.stretchFactor);

    return {
      buffer,
      actualStretchFactor: buffer.length / input.length,
      processingTime: performance.now() - startTime,
    };
  }

  /**
   * Time stretch AudioBuffer (all channels).
   */
  timeStretchAudioBuffer(
    audioContext: AudioContext,
    input: AudioBuffer,
    options: TimeStretchOptions
  ): AudioBuffer {
    const outputLength = Math.round(input.length * options.stretchFactor);
    const output = audioContext.createBuffer(
      input.numberOfChannels,
      outputLength,
      input.sampleRate
    );

    for (let ch = 0; ch < input.numberOfChannels; ch++) {
      const inputData = input.getChannelData(ch);
      const result = this.timeStretch(inputData, options);
      output.copyToChannel(result.buffer.slice(0, outputLength), ch);
    }

    return output;
  }

  /**
   * Pitch shift audio buffer.
   */
  pitchShift(
    input: Float32Array,
    options: PitchShiftOptions
  ): TimeStretchResult {
    const startTime = performance.now();

    const fftSize = options.fftSize ?? this.defaultFftSize;
    const hopSize = Math.round(fftSize / 4);

    const vocoder = new PhaseVocoder(fftSize, hopSize, 'hann');
    const buffer = vocoder.pitchShift(input, options.semitones);

    return {
      buffer,
      actualStretchFactor: 1.0,
      processingTime: performance.now() - startTime,
    };
  }

  /**
   * Pitch shift AudioBuffer (all channels).
   */
  pitchShiftAudioBuffer(
    audioContext: AudioContext,
    input: AudioBuffer,
    options: PitchShiftOptions
  ): AudioBuffer {
    const output = audioContext.createBuffer(
      input.numberOfChannels,
      input.length,
      input.sampleRate
    );

    for (let ch = 0; ch < input.numberOfChannels; ch++) {
      const inputData = input.getChannelData(ch);
      const result = this.pitchShift(inputData, options);
      output.copyToChannel(result.buffer as Float32Array<ArrayBuffer>, ch);
    }

    return output;
  }

  /**
   * Change tempo while preserving pitch.
   */
  changeTempo(
    audioContext: AudioContext,
    input: AudioBuffer,
    tempoFactor: number
  ): AudioBuffer {
    return this.timeStretchAudioBuffer(audioContext, input, {
      stretchFactor: 1 / tempoFactor,
      preservePitch: true,
    });
  }

  /**
   * Transpose (pitch shift) by semitones.
   */
  transpose(
    audioContext: AudioContext,
    input: AudioBuffer,
    semitones: number
  ): AudioBuffer {
    return this.pitchShiftAudioBuffer(audioContext, input, { semitones });
  }

  /**
   * Set default FFT size.
   */
  setDefaultFftSize(size: number): void {
    // Must be power of 2
    const validSizes = [512, 1024, 2048, 4096, 8192, 16384];
    if (validSizes.includes(size)) {
      this.defaultFftSize = size;
    }
  }

  /**
   * Get quality preset FFT settings.
   */
  getQualityPreset(quality: 'fast' | 'balanced' | 'high'): {
    fftSize: number;
    hopSize: number;
  } {
    switch (quality) {
      case 'fast':
        return { fftSize: 1024, hopSize: 256 };
      case 'balanced':
        return { fftSize: 4096, hopSize: 1024 };
      case 'high':
        return { fftSize: 8192, hopSize: 2048 };
    }
  }
}

// ============ Singleton Instance ============

export const timeStretchEngine = new TimeStretchEngine();

// ============ Utility Functions ============

/**
 * Convert BPM change to stretch factor.
 */
export function bpmToStretchFactor(originalBpm: number, targetBpm: number): number {
  return originalBpm / targetBpm;
}

/**
 * Convert semitones to frequency ratio.
 */
export function semitonesToRatio(semitones: number): number {
  return Math.pow(2, semitones / 12);
}

/**
 * Convert frequency ratio to semitones.
 */
export function ratioToSemitones(ratio: number): number {
  return 12 * Math.log2(ratio);
}

/**
 * Convert cents to frequency ratio.
 */
export function centsToRatio(cents: number): number {
  return Math.pow(2, cents / 1200);
}
