/**
 * ReelForge Crossfade Engine
 *
 * Professional crossfade processing with multiple curve types.
 * Handles clip transitions with sample-accurate timing.
 *
 * @module audio-processing/CrossfadeEngine
 */

// ============ Types ============

export type CrossfadeType = 'linear' | 'equal-power' | 's-curve' | 'exponential' | 'logarithmic';

export interface CrossfadeOptions {
  type: CrossfadeType;
  duration: number; // In samples
  asymmetric?: boolean;
  fadeInCurve?: CrossfadeType;
  fadeOutCurve?: CrossfadeType;
}

export interface CrossfadeRegion {
  startSample: number;
  endSample: number;
  fadeOutBuffer: Float32Array;
  fadeInBuffer: Float32Array;
}

export interface CrossfadeResult {
  buffer: Float32Array;
  peakLevel: number;
  clipDetected: boolean;
}

// ============ Curve Functions ============

/**
 * Generate crossfade curve values.
 */
function generateCurve(type: CrossfadeType, length: number, fadeIn: boolean): Float32Array {
  const curve = new Float32Array(length);

  for (let i = 0; i < length; i++) {
    const t = i / (length - 1); // 0 to 1
    const position = fadeIn ? t : 1 - t;

    switch (type) {
      case 'linear':
        curve[i] = position;
        break;

      case 'equal-power':
        // Equal power: maintains constant loudness
        curve[i] = fadeIn
          ? Math.sqrt(position)
          : Math.sqrt(1 - position);
        break;

      case 's-curve':
        // Smooth S-curve using cosine interpolation
        curve[i] = fadeIn
          ? 0.5 * (1 - Math.cos(Math.PI * position))
          : 0.5 * (1 + Math.cos(Math.PI * position));
        break;

      case 'exponential':
        // Exponential curve
        curve[i] = fadeIn
          ? Math.pow(position, 2)
          : Math.pow(1 - position, 2);
        break;

      case 'logarithmic':
        // Logarithmic curve (inverse exponential)
        curve[i] = fadeIn
          ? 1 - Math.pow(1 - position, 2)
          : Math.pow(position, 2);
        break;

      default:
        curve[i] = position;
    }
  }

  return curve;
}

// ============ Crossfade Engine ============

export class CrossfadeEngine {
  private defaultType: CrossfadeType = 'equal-power';
  private defaultDuration = 1024; // ~23ms at 44.1kHz

  /**
   * Set default crossfade type.
   */
  setDefaultType(type: CrossfadeType): void {
    this.defaultType = type;
  }

  /**
   * Set default crossfade duration in samples.
   */
  setDefaultDuration(samples: number): void {
    this.defaultDuration = Math.max(2, samples);
  }

  /**
   * Get default duration in samples.
   */
  getDefaultDuration(): number {
    return this.defaultDuration;
  }

  /**
   * Convert milliseconds to samples.
   */
  msToSamples(ms: number, sampleRate: number): number {
    return Math.round((ms / 1000) * sampleRate);
  }

  /**
   * Convert samples to milliseconds.
   */
  samplesToMs(samples: number, sampleRate: number): number {
    return (samples / sampleRate) * 1000;
  }

  /**
   * Generate a fade curve.
   */
  generateFadeCurve(
    type: CrossfadeType,
    length: number,
    fadeIn: boolean
  ): Float32Array {
    return generateCurve(type, length, fadeIn);
  }

  /**
   * Apply crossfade between two audio buffers.
   * Returns the crossfaded overlap region.
   */
  applyCrossfade(
    fadeOutBuffer: Float32Array,
    fadeInBuffer: Float32Array,
    options?: Partial<CrossfadeOptions>
  ): CrossfadeResult {
    const type = options?.type ?? this.defaultType;
    const duration = Math.min(
      options?.duration ?? this.defaultDuration,
      fadeOutBuffer.length,
      fadeInBuffer.length
    );

    // Generate curves
    const fadeOutCurve = generateCurve(
      options?.asymmetric ? (options?.fadeOutCurve ?? type) : type,
      duration,
      false
    );
    const fadeInCurve = generateCurve(
      options?.asymmetric ? (options?.fadeInCurve ?? type) : type,
      duration,
      true
    );

    // Apply crossfade
    const result = new Float32Array(duration);
    let peakLevel = 0;
    let clipDetected = false;

    for (let i = 0; i < duration; i++) {
      const outSample = fadeOutBuffer[fadeOutBuffer.length - duration + i] * fadeOutCurve[i];
      const inSample = fadeInBuffer[i] * fadeInCurve[i];
      const mixed = outSample + inSample;

      result[i] = mixed;

      const absValue = Math.abs(mixed);
      if (absValue > peakLevel) {
        peakLevel = absValue;
      }
      if (absValue > 1.0) {
        clipDetected = true;
      }
    }

    return { buffer: result, peakLevel, clipDetected };
  }

  /**
   * Apply crossfade in-place on AudioBuffer.
   */
  applyCrossfadeToAudioBuffer(
    outBuffer: AudioBuffer,
    inBuffer: AudioBuffer,
    outEndSample: number,
    inStartSample: number,
    options?: Partial<CrossfadeOptions>
  ): { peakLevel: number; clipDetected: boolean } {
    const duration = options?.duration ?? this.defaultDuration;
    const channels = Math.min(outBuffer.numberOfChannels, inBuffer.numberOfChannels);

    let overallPeak = 0;
    let anyClip = false;

    for (let ch = 0; ch < channels; ch++) {
      const outData = outBuffer.getChannelData(ch);
      const inData = inBuffer.getChannelData(ch);

      // Extract overlap regions
      const fadeOutRegion = outData.slice(outEndSample - duration, outEndSample);
      const fadeInRegion = inData.slice(inStartSample, inStartSample + duration);

      // Apply crossfade
      const result = this.applyCrossfade(fadeOutRegion, fadeInRegion, {
        ...options,
        duration,
      });

      // Write back
      for (let i = 0; i < duration; i++) {
        outData[outEndSample - duration + i] = result.buffer[i];
      }

      if (result.peakLevel > overallPeak) {
        overallPeak = result.peakLevel;
      }
      if (result.clipDetected) {
        anyClip = true;
      }
    }

    return { peakLevel: overallPeak, clipDetected: anyClip };
  }

  /**
   * Create a crossfade preview for visualization.
   */
  createCrossfadePreview(
    type: CrossfadeType,
    length: number
  ): { fadeIn: Float32Array; fadeOut: Float32Array; combined: Float32Array } {
    const fadeIn = generateCurve(type, length, true);
    const fadeOut = generateCurve(type, length, false);
    const combined = new Float32Array(length);

    for (let i = 0; i < length; i++) {
      combined[i] = fadeIn[i] + fadeOut[i];
    }

    return { fadeIn, fadeOut, combined };
  }

  /**
   * Analyze crossfade for potential issues.
   */
  analyzeCrossfade(type: CrossfadeType, length: number): {
    minCombined: number;
    maxCombined: number;
    centerDip: number;
    isConstantPower: boolean;
  } {
    const preview = this.createCrossfadePreview(type, length);

    let minCombined = Infinity;
    let maxCombined = -Infinity;

    for (let i = 0; i < length; i++) {
      if (preview.combined[i] < minCombined) minCombined = preview.combined[i];
      if (preview.combined[i] > maxCombined) maxCombined = preview.combined[i];
    }

    const centerIndex = Math.floor(length / 2);
    const centerDip = 1 - preview.combined[centerIndex];

    // Equal power crossfade should maintain ~1.0 throughout
    const isConstantPower = maxCombined - minCombined < 0.05;

    return { minCombined, maxCombined, centerDip, isConstantPower };
  }
}

// ============ Singleton Instance ============

export const crossfadeEngine = new CrossfadeEngine();

// ============ Utility Functions ============

/**
 * Get human-readable name for crossfade type.
 */
export function getCrossfadeTypeName(type: CrossfadeType): string {
  const names: Record<CrossfadeType, string> = {
    linear: 'Linear',
    'equal-power': 'Equal Power',
    's-curve': 'S-Curve',
    exponential: 'Exponential',
    logarithmic: 'Logarithmic',
  };
  return names[type];
}

/**
 * Get all available crossfade types.
 */
export function getCrossfadeTypes(): CrossfadeType[] {
  return ['linear', 'equal-power', 's-curve', 'exponential', 'logarithmic'];
}

/**
 * Get recommended crossfade type for specific use case.
 */
export function getRecommendedCrossfade(useCase: 'music' | 'speech' | 'sfx' | 'general'): {
  type: CrossfadeType;
  durationMs: number;
} {
  switch (useCase) {
    case 'music':
      return { type: 'equal-power', durationMs: 50 };
    case 'speech':
      return { type: 's-curve', durationMs: 30 };
    case 'sfx':
      return { type: 'linear', durationMs: 10 };
    case 'general':
    default:
      return { type: 'equal-power', durationMs: 25 };
  }
}
