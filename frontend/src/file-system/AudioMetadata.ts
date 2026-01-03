/**
 * ReelForge Audio Metadata Extractor
 *
 * Extract metadata from audio files:
 * - Duration, sample rate, channels
 * - BPM detection
 * - Key detection (basic)
 * - Waveform peaks
 *
 * @module file-system/AudioMetadata
 */

import { AudioContextManager } from '../core/AudioContextManager';

// ============ Types ============

export interface AudioMetadata {
  // Basic info
  name: string;
  duration: number; // seconds
  sampleRate: number;
  channels: number;
  bitDepth?: number;

  // Analysis
  bpm?: number;
  bpmConfidence?: number;
  key?: string;
  keyConfidence?: number;

  // Levels
  peakLevel: number; // 0-1
  rmsLevel: number;  // 0-1
  lufs?: number;

  // Waveform
  waveformPeaks?: Float32Array;

  // File info
  fileSize: number;
  mimeType?: string;
}

export interface BPMResult {
  bpm: number;
  confidence: number;
  alternatives: { bpm: number; confidence: number }[];
}

export interface KeyResult {
  key: string;
  mode: 'major' | 'minor';
  confidence: number;
}

// ============ Audio Metadata Extractor ============

export class AudioMetadataExtractor {
  private audioContext: AudioContext;

  constructor() {
    this.audioContext = AudioContextManager.getContext();
  }

  /**
   * Extract all metadata from audio file.
   */
  async extractFromFile(file: File): Promise<AudioMetadata> {
    const arrayBuffer = await file.arrayBuffer();
    const audioBuffer = await this.audioContext.decodeAudioData(arrayBuffer);

    const metadata: AudioMetadata = {
      name: file.name,
      duration: audioBuffer.duration,
      sampleRate: audioBuffer.sampleRate,
      channels: audioBuffer.numberOfChannels,
      fileSize: file.size,
      mimeType: file.type,
      peakLevel: 0,
      rmsLevel: 0,
    };

    // Calculate levels
    const levels = this.calculateLevels(audioBuffer);
    metadata.peakLevel = levels.peak;
    metadata.rmsLevel = levels.rms;

    // Generate waveform
    metadata.waveformPeaks = this.generateWaveformPeaks(audioBuffer, 1024);

    // Detect BPM (for audio > 5 seconds)
    if (audioBuffer.duration > 5) {
      try {
        const bpmResult = await this.detectBPM(audioBuffer);
        metadata.bpm = bpmResult.bpm;
        metadata.bpmConfidence = bpmResult.confidence;
      } catch {
        // BPM detection failed - not critical
      }
    }

    return metadata;
  }

  /**
   * Extract metadata from ArrayBuffer.
   */
  async extractFromArrayBuffer(buffer: ArrayBuffer, name = 'audio'): Promise<AudioMetadata> {
    const audioBuffer = await this.audioContext.decodeAudioData(buffer);

    const metadata: AudioMetadata = {
      name,
      duration: audioBuffer.duration,
      sampleRate: audioBuffer.sampleRate,
      channels: audioBuffer.numberOfChannels,
      fileSize: buffer.byteLength,
      peakLevel: 0,
      rmsLevel: 0,
    };

    const levels = this.calculateLevels(audioBuffer);
    metadata.peakLevel = levels.peak;
    metadata.rmsLevel = levels.rms;
    metadata.waveformPeaks = this.generateWaveformPeaks(audioBuffer, 1024);

    return metadata;
  }

  /**
   * Calculate peak and RMS levels.
   */
  private calculateLevels(buffer: AudioBuffer): { peak: number; rms: number } {
    let peak = 0;
    let sumSquares = 0;
    let sampleCount = 0;

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      for (let i = 0; i < data.length; i++) {
        const sample = Math.abs(data[i]);
        if (sample > peak) peak = sample;
        sumSquares += sample * sample;
        sampleCount++;
      }
    }

    const rms = Math.sqrt(sumSquares / sampleCount);
    return { peak, rms };
  }

  /**
   * Generate waveform peaks for visualization.
   */
  private generateWaveformPeaks(buffer: AudioBuffer, numPeaks: number): Float32Array {
    const peaks = new Float32Array(numPeaks);
    const channelData = buffer.getChannelData(0);
    const samplesPerPeak = Math.floor(channelData.length / numPeaks);

    for (let i = 0; i < numPeaks; i++) {
      const start = i * samplesPerPeak;
      const end = Math.min(start + samplesPerPeak, channelData.length);

      let maxPeak = 0;
      for (let j = start; j < end; j++) {
        const abs = Math.abs(channelData[j]);
        if (abs > maxPeak) maxPeak = abs;
      }

      peaks[i] = maxPeak;
    }

    return peaks;
  }

  /**
   * Detect BPM using autocorrelation.
   */
  async detectBPM(buffer: AudioBuffer): Promise<BPMResult> {
    // Get mono channel
    const channelData = buffer.getChannelData(0);
    const sampleRate = buffer.sampleRate;

    // Downsample for faster processing
    const downsampleFactor = Math.floor(sampleRate / 11025);
    const downsampled = this.downsample(channelData, downsampleFactor);
    const downsampledRate = sampleRate / downsampleFactor;

    // Apply low-pass filter to emphasize beats
    const filtered = this.lowPassFilter(downsampled, downsampledRate, 200);

    // Calculate energy envelope
    const windowSize = Math.floor(downsampledRate * 0.01); // 10ms windows
    const envelope = this.calculateEnvelope(filtered, windowSize);

    // Find peaks in envelope
    const peaks = this.findPeaks(envelope);

    // Calculate intervals between peaks
    const intervals = this.calculateIntervals(peaks);

    // Find most common interval (BPM)
    const result = this.findDominantBPM(intervals, downsampledRate / windowSize);

    return result;
  }

  /**
   * Downsample audio data.
   */
  private downsample(data: Float32Array, factor: number): Float32Array {
    const length = Math.floor(data.length / factor);
    const result = new Float32Array(length);

    for (let i = 0; i < length; i++) {
      let sum = 0;
      for (let j = 0; j < factor; j++) {
        sum += Math.abs(data[i * factor + j]);
      }
      result[i] = sum / factor;
    }

    return result;
  }

  /**
   * Simple low-pass filter.
   */
  private lowPassFilter(data: Float32Array, sampleRate: number, cutoff: number): Float32Array {
    const result = new Float32Array(data.length);
    const rc = 1 / (2 * Math.PI * cutoff);
    const dt = 1 / sampleRate;
    const alpha = dt / (rc + dt);

    result[0] = data[0];
    for (let i = 1; i < data.length; i++) {
      result[i] = result[i - 1] + alpha * (data[i] - result[i - 1]);
    }

    return result;
  }

  /**
   * Calculate energy envelope.
   */
  private calculateEnvelope(data: Float32Array, windowSize: number): Float32Array {
    const numWindows = Math.floor(data.length / windowSize);
    const envelope = new Float32Array(numWindows);

    for (let i = 0; i < numWindows; i++) {
      let sum = 0;
      const start = i * windowSize;
      for (let j = 0; j < windowSize; j++) {
        sum += data[start + j] * data[start + j];
      }
      envelope[i] = Math.sqrt(sum / windowSize);
    }

    return envelope;
  }

  /**
   * Find peaks in data.
   */
  private findPeaks(data: Float32Array): number[] {
    const peaks: number[] = [];
    const threshold = this.calculateThreshold(data);

    for (let i = 1; i < data.length - 1; i++) {
      if (data[i] > threshold && data[i] > data[i - 1] && data[i] > data[i + 1]) {
        peaks.push(i);
      }
    }

    return peaks;
  }

  /**
   * Calculate adaptive threshold.
   */
  private calculateThreshold(data: Float32Array): number {
    let sum = 0;
    for (let i = 0; i < data.length; i++) {
      sum += data[i];
    }
    const mean = sum / data.length;

    let variance = 0;
    for (let i = 0; i < data.length; i++) {
      variance += (data[i] - mean) * (data[i] - mean);
    }
    const stdDev = Math.sqrt(variance / data.length);

    return mean + stdDev * 0.5;
  }

  /**
   * Calculate intervals between peaks.
   */
  private calculateIntervals(peaks: number[]): number[] {
    const intervals: number[] = [];

    for (let i = 1; i < peaks.length; i++) {
      intervals.push(peaks[i] - peaks[i - 1]);
    }

    return intervals;
  }

  /**
   * Find dominant BPM from intervals.
   */
  private findDominantBPM(intervals: number[], framesPerSecond: number): BPMResult {
    // Create histogram of intervals
    const histogram = new Map<number, number>();

    for (const interval of intervals) {
      // Convert to BPM
      const bpm = Math.round((60 * framesPerSecond) / interval);

      // Only consider reasonable BPM range
      if (bpm >= 60 && bpm <= 200) {
        // Quantize to nearest integer
        const quantized = Math.round(bpm);
        histogram.set(quantized, (histogram.get(quantized) || 0) + 1);
      }
    }

    // Find most common BPM values
    const sorted = Array.from(histogram.entries())
      .sort((a, b) => b[1] - a[1]);

    if (sorted.length === 0) {
      return {
        bpm: 120,
        confidence: 0,
        alternatives: [],
      };
    }

    const totalCounts = sorted.reduce((sum, [_, count]) => sum + count, 0);
    const topBPM = sorted[0][0];
    const topConfidence = sorted[0][1] / totalCounts;

    // Get alternatives
    const alternatives = sorted.slice(1, 4).map(([bpm, count]) => ({
      bpm,
      confidence: count / totalCounts,
    }));

    return {
      bpm: topBPM,
      confidence: topConfidence,
      alternatives,
    };
  }

  /**
   * Detect musical key (basic implementation).
   */
  async detectKey(_buffer: AudioBuffer): Promise<KeyResult> {
    // This is a simplified key detection
    // Real implementation would use chromagram analysis

    // For now, return placeholder
    return {
      key: 'C',
      mode: 'major',
      confidence: 0,
    };
  }

  /**
   * Calculate LUFS (simplified).
   */
  calculateLUFS(buffer: AudioBuffer): number {
    // Simplified LUFS calculation
    // Full implementation requires ITU-R BS.1770-4 algorithm

    const levels = this.calculateLevels(buffer);
    // Rough approximation: LUFS ≈ 20 * log10(RMS) - 0.691
    const lufs = 20 * Math.log10(levels.rms + 0.0001) - 0.691;
    return Math.max(-70, lufs);
  }
}

// Singleton instance
export const audioMetadataExtractor = new AudioMetadataExtractor();

// ============ Utility Functions ============

/**
 * Format duration for display.
 */
export function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 100);

  if (mins > 0) {
    return `${mins}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(2, '0')}`;
  }
  return `${secs}.${ms.toString().padStart(2, '0')}s`;
}

/**
 * Format BPM for display.
 */
export function formatBPM(bpm: number, confidence?: number): string {
  const bpmStr = bpm.toFixed(1);
  if (confidence !== undefined && confidence < 0.5) {
    return `~${bpmStr} BPM`;
  }
  return `${bpmStr} BPM`;
}

/**
 * Get audio format from MIME type.
 */
export function getAudioFormat(mimeType: string): string {
  const formats: Record<string, string> = {
    'audio/wav': 'WAV',
    'audio/wave': 'WAV',
    'audio/x-wav': 'WAV',
    'audio/mpeg': 'MP3',
    'audio/mp3': 'MP3',
    'audio/ogg': 'OGG',
    'audio/flac': 'FLAC',
    'audio/x-flac': 'FLAC',
    'audio/aac': 'AAC',
    'audio/mp4': 'M4A',
    'audio/x-m4a': 'M4A',
    'audio/webm': 'WebM',
  };

  return formats[mimeType] || 'Unknown';
}
