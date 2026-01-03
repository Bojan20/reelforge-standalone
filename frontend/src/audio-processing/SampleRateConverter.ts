/**
 * ReelForge Sample Rate Converter
 *
 * High-quality sample rate conversion with multiple algorithms.
 * Supports real-time and offline conversion.
 *
 * @module audio-processing/SampleRateConverter
 */

// ============ Types ============

export type SRCQuality = 'fast' | 'medium' | 'high' | 'best';
export type SRCAlgorithm = 'linear' | 'cubic' | 'sinc' | 'polyphase';

export interface SRCOptions {
  quality?: SRCQuality;
  algorithm?: SRCAlgorithm;
  ditherOutput?: boolean;
  antiAliasing?: boolean;
  filterLength?: number;
}

export interface SRCResult {
  buffer: Float32Array;
  inputSampleRate: number;
  outputSampleRate: number;
  ratio: number;
  processingTime: number;
}

// ============ Sinc Interpolation ============

function sinc(x: number): number {
  if (x === 0) return 1;
  const pix = Math.PI * x;
  return Math.sin(pix) / pix;
}

function blackmanWindow(n: number, N: number): number {
  const a0 = 0.42;
  const a1 = 0.5;
  const a2 = 0.08;
  return a0 - a1 * Math.cos((2 * Math.PI * n) / (N - 1)) + a2 * Math.cos((4 * Math.PI * n) / (N - 1));
}

function generateSincKernel(ratio: number, length: number): Float32Array {
  const kernel = new Float32Array(length);
  const center = (length - 1) / 2;

  // Cutoff frequency
  const fc = Math.min(0.5, 0.5 / ratio);

  for (let i = 0; i < length; i++) {
    const n = i - center;
    kernel[i] = 2 * fc * sinc(2 * fc * n) * blackmanWindow(i, length);
  }

  // Normalize
  let sum = 0;
  for (let i = 0; i < length; i++) {
    sum += kernel[i];
  }
  for (let i = 0; i < length; i++) {
    kernel[i] /= sum;
  }

  return kernel;
}

// ============ Sample Rate Converter ============

export class SampleRateConverter {
  private defaultQuality: SRCQuality = 'high';

  /**
   * Set default quality.
   */
  setDefaultQuality(quality: SRCQuality): void {
    this.defaultQuality = quality;
  }

  /**
   * Get filter length for quality.
   */
  private getFilterLength(quality: SRCQuality): number {
    switch (quality) {
      case 'fast':
        return 16;
      case 'medium':
        return 32;
      case 'high':
        return 64;
      case 'best':
        return 128;
    }
  }

  /**
   * Linear interpolation (fast, low quality).
   */
  private linearInterpolate(
    input: Float32Array,
    ratio: number
  ): Float32Array {
    const outputLength = Math.round(input.length * ratio);
    const output = new Float32Array(outputLength);

    for (let i = 0; i < outputLength; i++) {
      const srcPos = i / ratio;
      const srcIndex = Math.floor(srcPos);
      const frac = srcPos - srcIndex;

      if (srcIndex + 1 < input.length) {
        output[i] = input[srcIndex] * (1 - frac) + input[srcIndex + 1] * frac;
      } else if (srcIndex < input.length) {
        output[i] = input[srcIndex];
      }
    }

    return output;
  }

  /**
   * Cubic interpolation (medium quality).
   */
  private cubicInterpolate(
    input: Float32Array,
    ratio: number
  ): Float32Array {
    const outputLength = Math.round(input.length * ratio);
    const output = new Float32Array(outputLength);

    for (let i = 0; i < outputLength; i++) {
      const srcPos = i / ratio;
      const srcIndex = Math.floor(srcPos);
      const frac = srcPos - srcIndex;

      // Get 4 samples
      const s0 = srcIndex > 0 ? input[srcIndex - 1] : input[0];
      const s1 = input[Math.min(srcIndex, input.length - 1)];
      const s2 = input[Math.min(srcIndex + 1, input.length - 1)];
      const s3 = input[Math.min(srcIndex + 2, input.length - 1)];

      // Cubic Hermite interpolation
      const a0 = s1;
      const a1 = 0.5 * (s2 - s0);
      const a2 = s0 - 2.5 * s1 + 2 * s2 - 0.5 * s3;
      const a3 = 0.5 * (s3 - s0) + 1.5 * (s1 - s2);

      output[i] = a0 + a1 * frac + a2 * frac * frac + a3 * frac * frac * frac;
    }

    return output;
  }

  /**
   * Sinc interpolation (high quality).
   */
  private sincInterpolate(
    input: Float32Array,
    ratio: number,
    filterLength: number
  ): Float32Array {
    const outputLength = Math.round(input.length * ratio);
    const output = new Float32Array(outputLength);

    // Generate kernel
    const kernel = generateSincKernel(ratio, filterLength);
    const halfLength = Math.floor(filterLength / 2);

    for (let i = 0; i < outputLength; i++) {
      const srcPos = i / ratio;
      const srcIndex = Math.floor(srcPos);
      const frac = srcPos - srcIndex;

      let sum = 0;

      for (let j = -halfLength; j <= halfLength; j++) {
        const inputIndex = srcIndex + j;

        if (inputIndex >= 0 && inputIndex < input.length) {
          const kernelIndex = halfLength + j;
          const kernelOffset = frac;

          // Interpolate kernel value
          const kPos = kernelIndex - kernelOffset;
          const kIndex = Math.floor(kPos);
          const kFrac = kPos - kIndex;

          if (kIndex >= 0 && kIndex + 1 < filterLength) {
            const kernelValue = kernel[kIndex] * (1 - kFrac) + kernel[kIndex + 1] * kFrac;
            sum += input[inputIndex] * kernelValue;
          } else if (kIndex >= 0 && kIndex < filterLength) {
            sum += input[inputIndex] * kernel[kIndex];
          }
        }
      }

      output[i] = sum;
    }

    return output;
  }

  /**
   * Convert sample rate of Float32Array.
   */
  convert(
    input: Float32Array,
    inputRate: number,
    outputRate: number,
    options?: SRCOptions
  ): SRCResult {
    const startTime = performance.now();
    const ratio = outputRate / inputRate;
    const quality = options?.quality ?? this.defaultQuality;
    const algorithm = options?.algorithm ?? this.getAlgorithmForQuality(quality);

    let buffer: Float32Array;

    // Apply anti-aliasing filter if downsampling
    let processedInput = input;
    if (ratio < 1 && options?.antiAliasing !== false) {
      processedInput = this.applyAntiAliasingFilter(input, ratio);
    }

    switch (algorithm) {
      case 'linear':
        buffer = this.linearInterpolate(processedInput, ratio);
        break;
      case 'cubic':
        buffer = this.cubicInterpolate(processedInput, ratio);
        break;
      case 'sinc':
      case 'polyphase':
        const filterLength = options?.filterLength ?? this.getFilterLength(quality);
        buffer = this.sincInterpolate(processedInput, ratio, filterLength);
        break;
      default:
        buffer = this.linearInterpolate(processedInput, ratio);
    }

    // Apply dither if requested
    if (options?.ditherOutput) {
      this.applyDither(buffer);
    }

    return {
      buffer,
      inputSampleRate: inputRate,
      outputSampleRate: outputRate,
      ratio,
      processingTime: performance.now() - startTime,
    };
  }

  /**
   * Convert sample rate of AudioBuffer.
   */
  async convertAudioBuffer(
    audioContext: AudioContext,
    input: AudioBuffer,
    outputRate: number,
    options?: SRCOptions
  ): Promise<AudioBuffer> {
    const ratio = outputRate / input.sampleRate;
    const outputLength = Math.round(input.length * ratio);

    const output = audioContext.createBuffer(
      input.numberOfChannels,
      outputLength,
      outputRate
    );

    for (let ch = 0; ch < input.numberOfChannels; ch++) {
      const inputData = input.getChannelData(ch);
      const result = this.convert(inputData, input.sampleRate, outputRate, options);
      output.copyToChannel(result.buffer as Float32Array<ArrayBuffer>, ch);
    }

    return output;
  }

  /**
   * Use OfflineAudioContext for conversion (uses browser's built-in SRC).
   */
  async convertWithOfflineContext(
    input: AudioBuffer,
    outputRate: number
  ): Promise<AudioBuffer> {
    const ratio = outputRate / input.sampleRate;
    const outputLength = Math.ceil(input.length * ratio);

    const offlineContext = new OfflineAudioContext(
      input.numberOfChannels,
      outputLength,
      outputRate
    );

    const source = offlineContext.createBufferSource();
    source.buffer = input;
    source.connect(offlineContext.destination);
    source.start();

    return offlineContext.startRendering();
  }

  /**
   * Get algorithm for quality level.
   */
  private getAlgorithmForQuality(quality: SRCQuality): SRCAlgorithm {
    switch (quality) {
      case 'fast':
        return 'linear';
      case 'medium':
        return 'cubic';
      case 'high':
      case 'best':
        return 'sinc';
    }
  }

  /**
   * Apply low-pass anti-aliasing filter.
   */
  private applyAntiAliasingFilter(input: Float32Array, ratio: number): Float32Array {
    // Simple FIR low-pass filter
    const cutoff = ratio * 0.45; // Nyquist with some headroom
    const filterLength = 31;
    const kernel = generateSincKernel(1 / cutoff, filterLength);

    const output = new Float32Array(input.length);
    const halfLength = Math.floor(filterLength / 2);

    for (let i = 0; i < input.length; i++) {
      let sum = 0;

      for (let j = 0; j < filterLength; j++) {
        const inputIndex = i - halfLength + j;

        if (inputIndex >= 0 && inputIndex < input.length) {
          sum += input[inputIndex] * kernel[j];
        }
      }

      output[i] = sum;
    }

    return output;
  }

  /**
   * Apply triangular dither.
   */
  private applyDither(buffer: Float32Array): void {
    const ditherAmplitude = 1 / 32768; // 16-bit dither

    for (let i = 0; i < buffer.length; i++) {
      const dither = (Math.random() - 0.5 + Math.random() - 0.5) * ditherAmplitude;
      buffer[i] += dither;
    }
  }

  /**
   * Get common sample rates.
   */
  getCommonSampleRates(): number[] {
    return [8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000];
  }

  /**
   * Check if conversion is needed.
   */
  isConversionNeeded(inputRate: number, outputRate: number): boolean {
    return inputRate !== outputRate;
  }

  /**
   * Get conversion quality description.
   */
  getQualityDescription(quality: SRCQuality): string {
    const descriptions: Record<SRCQuality, string> = {
      fast: 'Fast - Linear interpolation (quick, lower quality)',
      medium: 'Medium - Cubic interpolation (balanced)',
      high: 'High - Sinc interpolation (professional quality)',
      best: 'Best - High-order sinc (mastering quality)',
    };
    return descriptions[quality];
  }
}

// ============ Singleton Instance ============

export const sampleRateConverter = new SampleRateConverter();

// ============ Utility Functions ============

/**
 * Get standard sample rate for format.
 */
export function getStandardSampleRate(format: 'cd' | 'dvd' | 'broadcast' | 'web'): number {
  const rates: Record<string, number> = {
    cd: 44100,
    dvd: 48000,
    broadcast: 48000,
    web: 44100,
  };
  return rates[format];
}

/**
 * Check if sample rate is standard.
 */
export function isStandardSampleRate(rate: number): boolean {
  const standard = [8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000];
  return standard.includes(rate);
}

/**
 * Get nearest standard sample rate.
 */
export function getNearestStandardRate(rate: number): number {
  const standard = [8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000];

  let nearest = standard[0];
  let minDiff = Math.abs(rate - nearest);

  for (const sr of standard) {
    const diff = Math.abs(rate - sr);
    if (diff < minDiff) {
      minDiff = diff;
      nearest = sr;
    }
  }

  return nearest;
}
