/**
 * Sample Rate Conversion Utility
 *
 * Converts AudioBuffer to target sample rate using OfflineAudioContext.
 * Essential for importing audio files with different sample rates into a project.
 *
 * Cubase-style behavior:
 * - Detect mismatched sample rates on import
 * - Convert to project sample rate automatically
 * - Preserve audio quality using high-quality resampling
 *
 * @module utils/sampleRateConversion
 */

/**
 * Project sample rate (default: 48000 Hz for professional audio)
 */
export const DEFAULT_PROJECT_SAMPLE_RATE = 48000;

/**
 * Check if audio buffer needs sample rate conversion
 */
export function needsSampleRateConversion(
  buffer: AudioBuffer,
  targetSampleRate: number = DEFAULT_PROJECT_SAMPLE_RATE
): boolean {
  return buffer.sampleRate !== targetSampleRate;
}

/**
 * Get sample rate mismatch info for UI display
 */
export function getSampleRateMismatchInfo(
  buffer: AudioBuffer,
  targetSampleRate: number = DEFAULT_PROJECT_SAMPLE_RATE
): { needsConversion: boolean; sourceSampleRate: number; targetSampleRate: number; ratio: number } {
  return {
    needsConversion: buffer.sampleRate !== targetSampleRate,
    sourceSampleRate: buffer.sampleRate,
    targetSampleRate,
    ratio: targetSampleRate / buffer.sampleRate,
  };
}

/**
 * Convert AudioBuffer to target sample rate using OfflineAudioContext
 *
 * Uses the browser's built-in high-quality resampling algorithm.
 *
 * @param buffer - Source AudioBuffer to convert
 * @param targetSampleRate - Target sample rate (default: 48000 Hz)
 * @returns Promise<AudioBuffer> - Resampled audio buffer
 */
export async function resampleAudioBuffer(
  buffer: AudioBuffer,
  targetSampleRate: number = DEFAULT_PROJECT_SAMPLE_RATE
): Promise<AudioBuffer> {
  // If already at target rate, return as-is
  if (buffer.sampleRate === targetSampleRate) {
    return buffer;
  }

  const ratio = targetSampleRate / buffer.sampleRate;
  const newLength = Math.round(buffer.length * ratio);
  const numberOfChannels = buffer.numberOfChannels;

  // Create offline context at target sample rate
  const offlineCtx = new OfflineAudioContext(
    numberOfChannels,
    newLength,
    targetSampleRate
  );

  // Create buffer source from original audio
  const source = offlineCtx.createBufferSource();
  source.buffer = buffer;

  // Connect to destination
  source.connect(offlineCtx.destination);

  // Start playback
  source.start(0);

  // Render to new buffer
  const resampledBuffer = await offlineCtx.startRendering();

  console.log('[SampleRateConversion] Converted:', {
    from: buffer.sampleRate,
    to: targetSampleRate,
    originalLength: buffer.length,
    newLength: resampledBuffer.length,
    originalDuration: buffer.duration,
    newDuration: resampledBuffer.duration,
  });

  return resampledBuffer;
}

/**
 * Convert audio buffer with progress callback for batch operations
 */
export async function resampleAudioBufferWithProgress(
  buffer: AudioBuffer,
  targetSampleRate: number,
  onProgress?: (progress: number) => void
): Promise<AudioBuffer> {
  // Note: OfflineAudioContext doesn't provide progress events
  // We can only report 0 and 100
  onProgress?.(0);

  const result = await resampleAudioBuffer(buffer, targetSampleRate);

  onProgress?.(100);

  return result;
}

/**
 * Batch resample multiple audio buffers
 */
export async function resampleAudioBuffers(
  buffers: AudioBuffer[],
  targetSampleRate: number = DEFAULT_PROJECT_SAMPLE_RATE,
  onProgress?: (completed: number, total: number) => void
): Promise<AudioBuffer[]> {
  const results: AudioBuffer[] = [];

  for (let i = 0; i < buffers.length; i++) {
    const resampled = await resampleAudioBuffer(buffers[i], targetSampleRate);
    results.push(resampled);
    onProgress?.(i + 1, buffers.length);
  }

  return results;
}

/**
 * Common sample rates in audio production
 */
export const COMMON_SAMPLE_RATES = [
  { value: 44100, label: '44.1 kHz', description: 'CD quality' },
  { value: 48000, label: '48 kHz', description: 'Professional video/film' },
  { value: 88200, label: '88.2 kHz', description: 'High-res CD master' },
  { value: 96000, label: '96 kHz', description: 'High-res audio' },
  { value: 176400, label: '176.4 kHz', description: 'Ultra high-res' },
  { value: 192000, label: '192 kHz', description: 'Ultra high-res' },
] as const;

/**
 * Get human-readable sample rate label
 */
export function formatSampleRate(sampleRate: number): string {
  if (sampleRate >= 1000) {
    return `${(sampleRate / 1000).toFixed(sampleRate % 1000 === 0 ? 0 : 1)} kHz`;
  }
  return `${sampleRate} Hz`;
}

export default resampleAudioBuffer;
