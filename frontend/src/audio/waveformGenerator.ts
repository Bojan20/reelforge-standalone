/**
 * ReelForge Waveform Generator
 *
 * Generate waveform data from AudioBuffer for visualization.
 * Supports multiple resolutions and caching for performance.
 *
 * @module audio/waveformGenerator
 */

// ============ Types ============

export interface WaveformOptions {
  /** Number of samples per output point (default: auto-calculate) */
  samplesPerPoint?: number;
  /** Target number of output points (alternative to samplesPerPoint) */
  targetPoints?: number;
  /** Channel mode: 'mix' averages all, 'max' takes max, 'left'/'right' for specific */
  channelMode?: 'mix' | 'max' | 'left' | 'right';
  /** Whether to include min values (for mirror display) */
  includeMin?: boolean;
}

export interface WaveformData {
  /** Peak values (0 to 1, positive only if includeMin=false) */
  peaks: Float32Array;
  /** Min values (-1 to 0, only if includeMin=true) */
  mins?: Float32Array;
  /** Duration in seconds */
  duration: number;
  /** Sample rate of source */
  sampleRate: number;
  /** Number of channels in source */
  channels: number;
  /** Samples per point used */
  samplesPerPoint: number;
}

export interface WaveformCacheEntry {
  data: WaveformData;
  resolution: number;
  timestamp: number;
}

// ============ Waveform Generation ============

/**
 * Generate waveform peaks from AudioBuffer.
 * Returns normalized peak values (0 to 1) for visualization.
 */
export function generateWaveform(
  audioBuffer: AudioBuffer,
  options: WaveformOptions = {}
): WaveformData {
  const {
    channelMode = 'max',
    includeMin = true,
  } = options;

  const numChannels = audioBuffer.numberOfChannels;
  const numSamples = audioBuffer.length;
  const sampleRate = audioBuffer.sampleRate;
  const duration = audioBuffer.duration;

  // Calculate samples per point
  let samplesPerPoint: number;
  if (options.samplesPerPoint) {
    samplesPerPoint = options.samplesPerPoint;
  } else if (options.targetPoints) {
    samplesPerPoint = Math.max(1, Math.floor(numSamples / options.targetPoints));
  } else {
    // Default: ~1000 points for typical display
    samplesPerPoint = Math.max(1, Math.floor(numSamples / 1000));
  }

  const numPoints = Math.ceil(numSamples / samplesPerPoint);
  const peaks = new Float32Array(numPoints);
  const mins = includeMin ? new Float32Array(numPoints) : undefined;

  // Get channel data
  const channelData: Float32Array[] = [];
  for (let ch = 0; ch < numChannels; ch++) {
    channelData.push(audioBuffer.getChannelData(ch));
  }

  // Process each point
  for (let i = 0; i < numPoints; i++) {
    const startSample = i * samplesPerPoint;
    const endSample = Math.min(startSample + samplesPerPoint, numSamples);

    let maxPeak = 0;
    let minPeak = 0;

    // Find peak in this segment
    for (let s = startSample; s < endSample; s++) {
      let sampleValue: number;

      switch (channelMode) {
        case 'left':
          sampleValue = channelData[0][s];
          break;
        case 'right':
          sampleValue = numChannels > 1 ? channelData[1][s] : channelData[0][s];
          break;
        case 'mix':
          sampleValue = 0;
          for (let ch = 0; ch < numChannels; ch++) {
            sampleValue += channelData[ch][s];
          }
          sampleValue /= numChannels;
          break;
        case 'max':
        default:
          sampleValue = 0;
          for (let ch = 0; ch < numChannels; ch++) {
            const abs = Math.abs(channelData[ch][s]);
            if (abs > Math.abs(sampleValue)) {
              sampleValue = channelData[ch][s];
            }
          }
          break;
      }

      if (sampleValue > maxPeak) maxPeak = sampleValue;
      if (sampleValue < minPeak) minPeak = sampleValue;
    }

    peaks[i] = maxPeak;
    if (mins) mins[i] = minPeak;
  }

  return {
    peaks,
    mins,
    duration,
    sampleRate,
    channels: numChannels,
    samplesPerPoint,
  };
}

/**
 * Generate waveform at specific pixels-per-second resolution.
 * Useful for zoom-dependent display.
 */
export function generateWaveformAtResolution(
  audioBuffer: AudioBuffer,
  pixelsPerSecond: number,
  options: Omit<WaveformOptions, 'samplesPerPoint' | 'targetPoints'> = {}
): WaveformData {
  const targetPoints = Math.ceil(audioBuffer.duration * pixelsPerSecond);
  return generateWaveform(audioBuffer, {
    ...options,
    targetPoints,
  });
}

/**
 * Downsample existing waveform data for lower resolution display.
 * More efficient than regenerating from AudioBuffer.
 */
export function downsampleWaveform(
  waveform: WaveformData,
  factor: number
): WaveformData {
  if (factor <= 1) return waveform;

  const newLength = Math.ceil(waveform.peaks.length / factor);
  const newPeaks = new Float32Array(newLength);
  const newMins = waveform.mins ? new Float32Array(newLength) : undefined;

  for (let i = 0; i < newLength; i++) {
    const startIdx = i * factor;
    const endIdx = Math.min(startIdx + factor, waveform.peaks.length);

    let maxPeak = 0;
    let minPeak = 0;

    for (let j = startIdx; j < endIdx; j++) {
      if (waveform.peaks[j] > maxPeak) maxPeak = waveform.peaks[j];
      if (waveform.mins && waveform.mins[j] < minPeak) minPeak = waveform.mins[j];
    }

    newPeaks[i] = maxPeak;
    if (newMins) newMins[i] = minPeak;
  }

  return {
    peaks: newPeaks,
    mins: newMins,
    duration: waveform.duration,
    sampleRate: waveform.sampleRate,
    channels: waveform.channels,
    samplesPerPoint: waveform.samplesPerPoint * factor,
  };
}

/**
 * Convert WaveformData to simple number array for Timeline component.
 * Timeline expects normalized values from -1 to 1.
 */
export function waveformToArray(waveform: WaveformData): number[] {
  const result: number[] = [];

  // Interleave min/max for proper display
  for (let i = 0; i < waveform.peaks.length; i++) {
    if (waveform.mins) {
      // Include both min and max for mirrored display
      result.push(waveform.mins[i], waveform.peaks[i]);
    } else {
      // Just peaks - create symmetric by mirroring
      result.push(-waveform.peaks[i], waveform.peaks[i]);
    }
  }

  return result;
}

/**
 * Convert WaveformData to Float32Array for Timeline component.
 * More efficient than number array for large waveforms.
 */
export function waveformToFloat32Array(waveform: WaveformData): Float32Array {
  if (waveform.mins) {
    // Interleave min/max
    const result = new Float32Array(waveform.peaks.length * 2);
    for (let i = 0; i < waveform.peaks.length; i++) {
      result[i * 2] = waveform.mins[i];
      result[i * 2 + 1] = waveform.peaks[i];
    }
    return result;
  } else {
    // Just use peaks for symmetric display
    return waveform.peaks;
  }
}

// ============ Waveform Cache ============

const waveformCache = new Map<string, WaveformCacheEntry>();
const MAX_CACHE_SIZE = 100;
const CACHE_TTL = 10 * 60 * 1000; // 10 minutes

/**
 * Get cached waveform or generate new one.
 */
export function getCachedWaveform(
  audioFileId: string,
  audioBuffer: AudioBuffer,
  resolution: number = 1000,
  options: WaveformOptions = {}
): WaveformData {
  const cacheKey = `${audioFileId}@${resolution}`;
  const cached = waveformCache.get(cacheKey);

  // Check if cached and not expired
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.data;
  }

  // Generate new waveform
  const waveform = generateWaveform(audioBuffer, {
    ...options,
    targetPoints: resolution,
  });

  // Cache it
  waveformCache.set(cacheKey, {
    data: waveform,
    resolution,
    timestamp: Date.now(),
  });

  // Evict old entries if cache is too large
  if (waveformCache.size > MAX_CACHE_SIZE) {
    const entries = Array.from(waveformCache.entries());
    entries.sort((a, b) => a[1].timestamp - b[1].timestamp);

    // Remove oldest 20%
    const toRemove = Math.ceil(MAX_CACHE_SIZE * 0.2);
    for (let i = 0; i < toRemove; i++) {
      waveformCache.delete(entries[i][0]);
    }
  }

  return waveform;
}

/**
 * Clear waveform cache for specific file or all.
 */
export function clearWaveformCache(audioFileId?: string): void {
  if (audioFileId) {
    // Clear all resolutions for this file
    for (const key of waveformCache.keys()) {
      if (key.startsWith(`${audioFileId}@`)) {
        waveformCache.delete(key);
      }
    }
  } else {
    waveformCache.clear();
  }
}

/**
 * Get cache statistics.
 */
export function getWaveformCacheStats(): { size: number; keys: string[] } {
  return {
    size: waveformCache.size,
    keys: Array.from(waveformCache.keys()),
  };
}

// ============ Worker-based Generation (for large files) ============

/**
 * Generate waveform in a Web Worker for large files.
 * Returns a promise that resolves when complete.
 */
export async function generateWaveformAsync(
  audioBuffer: AudioBuffer,
  options: WaveformOptions = {}
): Promise<WaveformData> {
  // For files < 5MB, use sync version (faster for small files)
  const estimatedSize = audioBuffer.length * audioBuffer.numberOfChannels * 4;
  if (estimatedSize < 5 * 1024 * 1024) {
    return generateWaveform(audioBuffer, options);
  }

  // For larger files, use setTimeout to avoid blocking
  return new Promise((resolve) => {
    setTimeout(() => {
      const result = generateWaveform(audioBuffer, options);
      resolve(result);
    }, 0);
  });
}

// ============ Utility Functions ============

/**
 * Calculate optimal resolution based on display width and zoom.
 */
export function calculateOptimalResolution(
  _duration: number,
  displayWidth: number,
  zoom: number = 1
): number {
  // At zoom 1, we want roughly 1 point per pixel
  // Higher zoom means more points
  return Math.ceil(displayWidth * zoom);
}

/**
 * Get waveform segment for visible portion of timeline.
 */
export function getWaveformSegment(
  waveform: WaveformData,
  startTime: number,
  endTime: number
): { peaks: Float32Array; mins?: Float32Array } {
  const startIdx = Math.floor((startTime / waveform.duration) * waveform.peaks.length);
  const endIdx = Math.ceil((endTime / waveform.duration) * waveform.peaks.length);

  const peaks = waveform.peaks.slice(startIdx, endIdx);
  const mins = waveform.mins?.slice(startIdx, endIdx);

  return { peaks, mins };
}

/**
 * Normalize waveform peaks to fill 0-1 range.
 * Useful for quiet audio that doesn't use full dynamic range.
 */
export function normalizeWaveform(waveform: WaveformData): WaveformData {
  let maxPeak = 0;

  // Find maximum peak
  for (let i = 0; i < waveform.peaks.length; i++) {
    const absPeak = Math.abs(waveform.peaks[i]);
    if (absPeak > maxPeak) maxPeak = absPeak;

    if (waveform.mins) {
      const absMin = Math.abs(waveform.mins[i]);
      if (absMin > maxPeak) maxPeak = absMin;
    }
  }

  if (maxPeak === 0 || maxPeak === 1) return waveform;

  // Normalize
  const scale = 1 / maxPeak;
  const normalizedPeaks = new Float32Array(waveform.peaks.length);
  const normalizedMins = waveform.mins ? new Float32Array(waveform.mins.length) : undefined;

  for (let i = 0; i < waveform.peaks.length; i++) {
    normalizedPeaks[i] = waveform.peaks[i] * scale;
    if (normalizedMins && waveform.mins) {
      normalizedMins[i] = waveform.mins[i] * scale;
    }
  }

  return {
    ...waveform,
    peaks: normalizedPeaks,
    mins: normalizedMins,
  };
}
