/**
 * ReelForge Fade Processor
 *
 * Professional fade in/out processing with multiple curve types.
 * Supports batch processing and non-destructive previews.
 *
 * @module audio-processing/FadeProcessor
 */

// ============ Types ============

export type FadeCurve =
  | 'linear'
  | 'exponential'
  | 'logarithmic'
  | 's-curve'
  | 'cosine'
  | 'equal-power'
  | 'custom';

export interface FadeOptions {
  curve: FadeCurve;
  duration: number; // In seconds
  customCurve?: Float32Array; // For custom curve type
  smooth?: boolean; // Apply smoothing at edges
}

export interface FadeRegion {
  type: 'in' | 'out';
  startSample: number;
  endSample: number;
  curve: FadeCurve;
}

export interface BatchFadeOptions {
  fadeIn?: FadeOptions;
  fadeOut?: FadeOptions;
  crossfadeDuration?: number;
}

// ============ Curve Generators ============

function generateLinearCurve(length: number, fadeIn: boolean): Float32Array {
  const curve = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / (length - 1);
    curve[i] = fadeIn ? t : 1 - t;
  }
  return curve;
}

function generateExponentialCurve(length: number, fadeIn: boolean, exponent: number = 2): Float32Array {
  const curve = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / (length - 1);
    const position = fadeIn ? t : 1 - t;
    curve[i] = Math.pow(position, exponent);
  }
  return curve;
}

function generateLogarithmicCurve(length: number, fadeIn: boolean): Float32Array {
  const curve = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / (length - 1);
    const position = fadeIn ? t : 1 - t;
    curve[i] = 1 - Math.pow(1 - position, 2);
  }
  return curve;
}

function generateSCurve(length: number, fadeIn: boolean): Float32Array {
  const curve = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / (length - 1);
    const position = fadeIn ? t : 1 - t;
    // Smooth S-curve using smoothstep
    curve[i] = position * position * (3 - 2 * position);
  }
  return curve;
}

function generateCosineCurve(length: number, fadeIn: boolean): Float32Array {
  const curve = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / (length - 1);
    const position = fadeIn ? t : 1 - t;
    curve[i] = 0.5 * (1 - Math.cos(Math.PI * position));
  }
  return curve;
}

function generateEqualPowerCurve(length: number, fadeIn: boolean): Float32Array {
  const curve = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const t = i / (length - 1);
    const position = fadeIn ? t : 1 - t;
    curve[i] = Math.sqrt(position);
  }
  return curve;
}

// ============ Fade Processor ============

export class FadeProcessor {
  /**
   * Generate fade curve.
   */
  generateCurve(
    curve: FadeCurve,
    length: number,
    fadeIn: boolean,
    customCurve?: Float32Array
  ): Float32Array {
    switch (curve) {
      case 'linear':
        return generateLinearCurve(length, fadeIn);
      case 'exponential':
        return generateExponentialCurve(length, fadeIn);
      case 'logarithmic':
        return generateLogarithmicCurve(length, fadeIn);
      case 's-curve':
        return generateSCurve(length, fadeIn);
      case 'cosine':
        return generateCosineCurve(length, fadeIn);
      case 'equal-power':
        return generateEqualPowerCurve(length, fadeIn);
      case 'custom':
        if (customCurve) {
          // Resample custom curve to desired length
          return this.resampleCurve(customCurve, length, fadeIn);
        }
        return generateLinearCurve(length, fadeIn);
      default:
        return generateLinearCurve(length, fadeIn);
    }
  }

  /**
   * Resample a curve to a different length.
   */
  private resampleCurve(source: Float32Array, targetLength: number, fadeIn: boolean): Float32Array {
    const result = new Float32Array(targetLength);
    const ratio = (source.length - 1) / (targetLength - 1);

    for (let i = 0; i < targetLength; i++) {
      const srcPos = i * ratio;
      const srcIndex = Math.floor(srcPos);
      const frac = srcPos - srcIndex;

      if (srcIndex + 1 < source.length) {
        result[i] = source[srcIndex] * (1 - frac) + source[srcIndex + 1] * frac;
      } else {
        result[i] = source[srcIndex];
      }
    }

    // Flip if fade out
    if (!fadeIn) {
      for (let i = 0; i < targetLength / 2; i++) {
        const temp = result[i];
        result[i] = result[targetLength - 1 - i];
        result[targetLength - 1 - i] = temp;
      }
    }

    return result;
  }

  /**
   * Apply fade in to audio buffer.
   */
  applyFadeIn(
    buffer: AudioBuffer,
    options: FadeOptions
  ): void {
    const fadeSamples = Math.min(
      Math.floor(options.duration * buffer.sampleRate),
      buffer.length
    );

    const curve = this.generateCurve(
      options.curve,
      fadeSamples,
      true,
      options.customCurve
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);

      for (let i = 0; i < fadeSamples; i++) {
        data[i] *= curve[i];
      }
    }
  }

  /**
   * Apply fade out to audio buffer.
   */
  applyFadeOut(
    buffer: AudioBuffer,
    options: FadeOptions
  ): void {
    const fadeSamples = Math.min(
      Math.floor(options.duration * buffer.sampleRate),
      buffer.length
    );

    const curve = this.generateCurve(
      options.curve,
      fadeSamples,
      false,
      options.customCurve
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      const startIndex = buffer.length - fadeSamples;

      for (let i = 0; i < fadeSamples; i++) {
        data[startIndex + i] *= curve[i];
      }
    }
  }

  /**
   * Apply both fade in and fade out.
   */
  applyFades(
    buffer: AudioBuffer,
    fadeIn?: FadeOptions,
    fadeOut?: FadeOptions
  ): void {
    if (fadeIn) {
      this.applyFadeIn(buffer, fadeIn);
    }
    if (fadeOut) {
      this.applyFadeOut(buffer, fadeOut);
    }
  }

  /**
   * Apply fade at specific position.
   */
  applyFadeAtPosition(
    buffer: AudioBuffer,
    startSample: number,
    fadeSamples: number,
    fadeIn: boolean,
    curve: FadeCurve = 'cosine'
  ): void {
    const actualLength = Math.min(fadeSamples, buffer.length - startSample);
    const curveData = this.generateCurve(curve, actualLength, fadeIn);

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);

      for (let i = 0; i < actualLength; i++) {
        data[startSample + i] *= curveData[i];
      }
    }
  }

  /**
   * Create non-destructive fade preview.
   */
  createFadePreview(
    buffer: AudioBuffer,
    options: BatchFadeOptions
  ): AudioBuffer {
    // Clone buffer
    const context = new OfflineAudioContext(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    const previewBuffer = context.createBuffer(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      previewBuffer.copyToChannel(buffer.getChannelData(ch), ch);
    }

    // Apply fades
    if (options.fadeIn) {
      this.applyFadeIn(previewBuffer, options.fadeIn);
    }
    if (options.fadeOut) {
      this.applyFadeOut(previewBuffer, options.fadeOut);
    }

    return previewBuffer;
  }

  /**
   * Get curve visualization data.
   */
  getCurveVisualization(
    curve: FadeCurve,
    points: number = 100,
    fadeIn: boolean = true
  ): Array<{ x: number; y: number }> {
    const curveData = this.generateCurve(curve, points, fadeIn);
    const result: Array<{ x: number; y: number }> = [];

    for (let i = 0; i < points; i++) {
      result.push({
        x: i / (points - 1),
        y: curveData[i],
      });
    }

    return result;
  }

  /**
   * Calculate optimal fade duration to avoid clicks.
   */
  getOptimalFadeDuration(sampleRate: number, minMs: number = 5): number {
    // At least 5ms to avoid clicks, but not less than 256 samples
    const minSamples = Math.max(256, (minMs / 1000) * sampleRate);
    return minSamples / sampleRate;
  }

  /**
   * Analyze if buffer edges need fading.
   */
  analyzeEdges(buffer: AudioBuffer): {
    startNeedsFade: boolean;
    endNeedsFade: boolean;
    suggestedFadeIn: number;
    suggestedFadeOut: number;
  } {
    const threshold = 0.01;
    const analysisSamples = Math.min(1024, buffer.length);

    let startLevel = 0;
    let endLevel = 0;

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);

      // Analyze start
      for (let i = 0; i < analysisSamples; i++) {
        startLevel = Math.max(startLevel, Math.abs(data[i]));
      }

      // Analyze end
      for (let i = buffer.length - analysisSamples; i < buffer.length; i++) {
        endLevel = Math.max(endLevel, Math.abs(data[i]));
      }
    }

    const sampleRate = buffer.sampleRate;

    return {
      startNeedsFade: startLevel > threshold,
      endNeedsFade: endLevel > threshold,
      suggestedFadeIn: startLevel > threshold
        ? this.getOptimalFadeDuration(sampleRate, startLevel * 20)
        : 0,
      suggestedFadeOut: endLevel > threshold
        ? this.getOptimalFadeDuration(sampleRate, endLevel * 20)
        : 0,
    };
  }

  /**
   * Auto-fade to remove clicks.
   */
  autoFade(buffer: AudioBuffer): void {
    const analysis = this.analyzeEdges(buffer);

    if (analysis.startNeedsFade && analysis.suggestedFadeIn > 0) {
      this.applyFadeIn(buffer, {
        curve: 'cosine',
        duration: analysis.suggestedFadeIn,
      });
    }

    if (analysis.endNeedsFade && analysis.suggestedFadeOut > 0) {
      this.applyFadeOut(buffer, {
        curve: 'cosine',
        duration: analysis.suggestedFadeOut,
      });
    }
  }
}

// ============ Singleton Instance ============

export const fadeProcessor = new FadeProcessor();

// ============ Utility Functions ============

/**
 * Get all available fade curves.
 */
export function getFadeCurves(): FadeCurve[] {
  return ['linear', 'exponential', 'logarithmic', 's-curve', 'cosine', 'equal-power', 'custom'];
}

/**
 * Get human-readable name for curve.
 */
export function getCurveName(curve: FadeCurve): string {
  const names: Record<FadeCurve, string> = {
    linear: 'Linear',
    exponential: 'Exponential',
    logarithmic: 'Logarithmic',
    's-curve': 'S-Curve',
    cosine: 'Cosine',
    'equal-power': 'Equal Power',
    custom: 'Custom',
  };
  return names[curve];
}

/**
 * Get recommended curve for use case.
 */
export function getRecommendedCurve(useCase: 'music' | 'speech' | 'sfx'): FadeCurve {
  switch (useCase) {
    case 'music':
      return 'equal-power';
    case 'speech':
      return 's-curve';
    case 'sfx':
      return 'exponential';
    default:
      return 'cosine';
  }
}
