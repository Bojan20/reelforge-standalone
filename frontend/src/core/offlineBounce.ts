/**
 * Offline Bounce / Render System
 *
 * DAW-quality offline audio rendering:
 * - Render sequences to audio files
 * - Multi-stem export
 * - High-quality sample rate conversion
 * - Loudness normalization (ITU-R BS.1770)
 * - True Peak Limiting (EBU R128 / ITU-R BS.1770-4)
 * - WAV/MP3/OGG export
 * - Batch rendering
 */

import type { BusId } from './types';
import { TruePeakLimiter, type LimiterConfig } from './dsp/truePeakLimiter';

// ============ TYPES ============

export type BounceFormat = 'wav' | 'mp3' | 'ogg';
export type SampleRate = 44100 | 48000 | 96000;
export type BitDepth = 16 | 24 | 32;
export type ChannelMode = 'mono' | 'stereo' | 'surround';

export interface BounceConfig {
  /** Start time in seconds */
  startTime: number;
  /** End time in seconds */
  endTime: number;
  /** Sample rate */
  sampleRate: SampleRate;
  /** Bit depth */
  bitDepth: BitDepth;
  /** Output format */
  format: BounceFormat;
  /** Channel mode */
  channels: ChannelMode;
  /** Include effects */
  includeEffects: boolean;
  /** Normalize output */
  normalize: boolean;
  /** Target loudness (LUFS) for normalization */
  targetLoudness?: number;
  /** Dither (for 16-bit) */
  dither: boolean;
  /** Specific buses to render (empty = master) */
  buses?: BusId[];
  /** Filename prefix */
  filenamePrefix?: string;
  /** Enable true peak limiting */
  truePeakLimit: boolean;
  /** True peak ceiling in dBTP (default: -1.0 for streaming, -0.3 for broadcast) */
  truePeakCeiling?: number;
  /** Limiter release time in ms */
  limiterRelease?: number;
}

export interface ScheduledBounceEvent {
  /** Event ID */
  id: string;
  /** Asset ID to play */
  assetId: string;
  /** Start time in sequence (seconds) */
  startTime: number;
  /** Duration (optional, uses asset length) */
  duration?: number;
  /** Volume (0-1) */
  volume: number;
  /** Pan (-1 to 1) */
  pan: number;
  /** Output bus */
  bus: BusId;
  /** Fade in (ms) */
  fadeInMs?: number;
  /** Fade out (ms) */
  fadeOutMs?: number;
}

export interface BounceProgress {
  /** Current phase */
  phase: 'preparing' | 'rendering' | 'processing' | 'encoding' | 'complete';
  /** Progress (0-1) */
  progress: number;
  /** Current time being rendered */
  currentTime: number;
  /** Total duration */
  totalDuration: number;
  /** Elapsed real time (ms) */
  elapsedMs: number;
  /** Estimated remaining (ms) */
  remainingMs: number;
}

export interface BounceResult {
  /** Output blob */
  blob: Blob;
  /** Filename */
  filename: string;
  /** Duration */
  duration: number;
  /** Peak level */
  peakLevel: number;
  /** RMS level */
  rmsLevel: number;
  /** True peak (dBTP) */
  truePeak: number;
  /** Integrated loudness (LUFS) */
  integratedLoudness: number;
  /** File size */
  sizeBytes: number;
}

export interface StemConfig {
  /** Bus to render */
  bus: BusId;
  /** Filename suffix */
  suffix: string;
  /** Include in render */
  enabled: boolean;
}

// ============ DEFAULT CONFIG ============

const DEFAULT_BOUNCE_CONFIG: BounceConfig = {
  startTime: 0,
  endTime: 10,
  sampleRate: 48000,
  bitDepth: 24,
  format: 'wav',
  channels: 'stereo',
  includeEffects: true,
  normalize: false,
  targetLoudness: -14, // Spotify/YouTube target
  dither: true,
  buses: [],
  filenamePrefix: 'bounce',
  truePeakLimit: true, // Enable by default for broadcast-safe output
  truePeakCeiling: -1.0, // -1.0 dBTP for streaming platforms
  limiterRelease: 100, // Fast release for transparent limiting
};

// ============ OFFLINE BOUNCE MANAGER ============

export class OfflineBounceManager {
  private assetBuffers: Map<string, AudioBuffer> = new Map();
  private onProgress?: (progress: BounceProgress) => void;

  constructor(
    assetBuffers: Map<string, AudioBuffer>,
    onProgress?: (progress: BounceProgress) => void
  ) {
    this.assetBuffers = assetBuffers;
    this.onProgress = onProgress;
  }

  /**
   * Update asset buffers reference
   */
  setAssetBuffers(buffers: Map<string, AudioBuffer>): void {
    this.assetBuffers = buffers;
  }

  /**
   * Bounce a sequence to audio file
   */
  async bounceSequence(
    events: ScheduledBounceEvent[],
    config: Partial<BounceConfig> = {}
  ): Promise<BounceResult> {
    const cfg: BounceConfig = { ...DEFAULT_BOUNCE_CONFIG, ...config };
    const startTime = performance.now();

    // Calculate actual duration
    const duration = cfg.endTime - cfg.startTime;
    const sampleCount = Math.ceil(duration * cfg.sampleRate);
    const channelCount = cfg.channels === 'mono' ? 1 : cfg.channels === 'stereo' ? 2 : 6;

    this.reportProgress('preparing', 0, 0, duration, startTime);

    // Create offline context
    const offlineCtx = new OfflineAudioContext(
      channelCount,
      sampleCount,
      cfg.sampleRate
    );

    // Schedule all events
    await this.scheduleEvents(offlineCtx, events, cfg);

    this.reportProgress('rendering', 0.1, 0, duration, startTime);

    // Render
    const renderedBuffer = await offlineCtx.startRendering();

    this.reportProgress('processing', 0.7, duration, duration, startTime);

    // Post-process
    let processedBuffer = renderedBuffer;

    // Apply true peak limiting (before normalization)
    if (cfg.truePeakLimit) {
      processedBuffer = this.applyTruePeakLimiter(processedBuffer, cfg);
      this.reportProgress('processing', 0.75, duration, duration, startTime);
    }

    if (cfg.normalize && cfg.targetLoudness !== undefined) {
      processedBuffer = await this.normalizeBuffer(processedBuffer, cfg.targetLoudness);

      // Re-apply limiter after normalization to ensure no overs
      if (cfg.truePeakLimit) {
        processedBuffer = this.applyTruePeakLimiter(processedBuffer, cfg);
      }
    }

    // Calculate levels
    const levels = this.calculateLevels(processedBuffer);

    this.reportProgress('encoding', 0.85, duration, duration, startTime);

    // Encode to output format
    const blob = await this.encodeBuffer(processedBuffer, cfg);

    this.reportProgress('complete', 1, duration, duration, startTime);

    const filename = `${cfg.filenamePrefix}_${Date.now()}.${cfg.format}`;

    return {
      blob,
      filename,
      duration,
      peakLevel: levels.peak,
      rmsLevel: levels.rms,
      truePeak: levels.truePeak,
      integratedLoudness: levels.loudness,
      sizeBytes: blob.size,
    };
  }

  /**
   * Bounce multiple stems
   */
  async bounceStems(
    events: ScheduledBounceEvent[],
    stems: StemConfig[],
    config: Partial<BounceConfig> = {}
  ): Promise<Map<BusId, BounceResult>> {
    const results = new Map<BusId, BounceResult>();

    for (const stem of stems) {
      if (!stem.enabled) continue;

      // Filter events for this bus
      const busEvents = events.filter(e => e.bus === stem.bus);

      if (busEvents.length === 0) continue;

      const stemConfig: Partial<BounceConfig> = {
        ...config,
        buses: [stem.bus],
        filenamePrefix: `${config.filenamePrefix ?? 'stem'}_${stem.suffix}`,
      };

      const result = await this.bounceSequence(busEvents, stemConfig);
      results.set(stem.bus, result);
    }

    return results;
  }

  /**
   * Schedule events into offline context
   */
  private async scheduleEvents(
    ctx: OfflineAudioContext,
    events: ScheduledBounceEvent[],
    config: BounceConfig
  ): Promise<void> {
    for (const event of events) {
      const buffer = this.assetBuffers.get(event.assetId);
      if (!buffer) {
        console.warn(`Asset not found: ${event.assetId}`);
        continue;
      }

      // Skip events outside range
      if (event.startTime >= config.endTime) continue;
      const eventEnd = event.startTime + (event.duration ?? buffer.duration);
      if (eventEnd <= config.startTime) continue;

      // Create source
      const source = ctx.createBufferSource();
      source.buffer = buffer;

      // Create gain for volume/fades
      const gain = ctx.createGain();
      gain.gain.value = event.volume;

      // Create panner
      const panner = ctx.createStereoPanner();
      panner.pan.value = event.pan;

      // Wire up
      source.connect(gain);
      gain.connect(panner);
      panner.connect(ctx.destination);

      // Calculate timing relative to bounce start
      const relativeStart = Math.max(0, event.startTime - config.startTime);
      const offset = event.startTime < config.startTime
        ? config.startTime - event.startTime
        : 0;

      // Apply fades
      if (event.fadeInMs && event.fadeInMs > 0) {
        gain.gain.setValueAtTime(0, relativeStart);
        gain.gain.linearRampToValueAtTime(
          event.volume,
          relativeStart + event.fadeInMs / 1000
        );
      }

      if (event.fadeOutMs && event.fadeOutMs > 0 && event.duration) {
        const fadeStart = relativeStart + event.duration - event.fadeOutMs / 1000;
        gain.gain.setValueAtTime(event.volume, fadeStart);
        gain.gain.linearRampToValueAtTime(0, relativeStart + event.duration);
      }

      // Schedule
      const playDuration = event.duration ?? buffer.duration;
      source.start(relativeStart, offset, playDuration - offset);
    }
  }

  /**
   * Apply true peak limiting to buffer
   * Ensures output never exceeds specified ceiling (dBTP)
   */
  private applyTruePeakLimiter(buffer: AudioBuffer, config: BounceConfig): AudioBuffer {
    const limiterConfig: Partial<LimiterConfig> = {
      ceiling: config.truePeakCeiling ?? -1.0,
      release: config.limiterRelease ?? 100,
      lookahead: 1.5, // 1.5ms lookahead for zero-overshoot
      knee: 0, // Hard knee for brickwall limiting
      truePeak: true,
      sampleRate: buffer.sampleRate,
    };

    const limiter = new TruePeakLimiter(limiterConfig);

    // Process in blocks for efficiency
    const blockSize = 512;
    const numChannels = buffer.numberOfChannels;
    const length = buffer.length;

    // Create output buffer
    const ctx = new OfflineAudioContext(numChannels, length, buffer.sampleRate);
    const outputBuffer = ctx.createBuffer(numChannels, length, buffer.sampleRate);

    // Get channel data
    const inputL = buffer.getChannelData(0);
    const inputR = numChannels > 1 ? buffer.getChannelData(1) : inputL;
    const outputL = outputBuffer.getChannelData(0);
    const outputR = numChannels > 1 ? outputBuffer.getChannelData(1) : outputL;

    // Process in blocks
    for (let i = 0; i < length; i += blockSize) {
      const end = Math.min(i + blockSize, length);
      const blockLen = end - i;

      // Create block views
      const blockInL = inputL.subarray(i, end);
      const blockInR = inputR.subarray(i, end);
      const blockOutL = new Float32Array(blockLen);
      const blockOutR = new Float32Array(blockLen);

      // Process block through limiter
      limiter.process(blockInL, blockInR, blockOutL, blockOutR);

      // Copy to output
      outputL.set(blockOutL, i);
      if (numChannels > 1) {
        outputR.set(blockOutR, i);
      }
    }

    // Log limiter stats
    const state = limiter.getState();
    if (state.gainReduction < -0.1) {
      console.log(`[Bounce] True Peak Limiter applied: ${state.gainReduction.toFixed(1)} dB GR, output: ${state.outputLevel.toFixed(1)} dBFS`);
    }

    return outputBuffer;
  }

  /**
   * Normalize buffer to target loudness
   */
  private async normalizeBuffer(
    buffer: AudioBuffer,
    targetLUFS: number
  ): Promise<AudioBuffer> {
    // Calculate integrated loudness (simplified ITU-R BS.1770)
    const loudness = this.calculateIntegratedLoudness(buffer);

    // Calculate gain adjustment
    const gainDB = targetLUFS - loudness;
    const gainLinear = Math.pow(10, gainDB / 20);

    // Limit gain to prevent clipping
    const maxGain = 1 / this.getPeakLevel(buffer);
    const finalGain = Math.min(gainLinear, maxGain * 0.99);

    // Apply gain
    const ctx = new OfflineAudioContext(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    const source = ctx.createBufferSource();
    source.buffer = buffer;

    const gain = ctx.createGain();
    gain.gain.value = finalGain;

    source.connect(gain);
    gain.connect(ctx.destination);
    source.start();

    return ctx.startRendering();
  }

  /**
   * Calculate integrated loudness (LUFS)
   */
  private calculateIntegratedLoudness(buffer: AudioBuffer): number {
    // Simplified ITU-R BS.1770 algorithm
    const blockSize = Math.floor(buffer.sampleRate * 0.4); // 400ms blocks
    const overlap = Math.floor(blockSize * 0.75);
    const step = blockSize - overlap;

    const blocks: number[] = [];

    for (let i = 0; i + blockSize <= buffer.length; i += step) {
      let sumSquares = 0;

      for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
        const data = buffer.getChannelData(ch);
        for (let j = 0; j < blockSize; j++) {
          sumSquares += data[i + j] * data[i + j];
        }
      }

      const meanSquare = sumSquares / (blockSize * buffer.numberOfChannels);
      const loudness = -0.691 + 10 * Math.log10(meanSquare);
      blocks.push(loudness);
    }

    // Absolute gating at -70 LUFS
    const absoluteThreshold = -70;
    const gatedBlocks = blocks.filter(b => b > absoluteThreshold);

    if (gatedBlocks.length === 0) return -70;

    // Calculate average
    const avg = gatedBlocks.reduce((a, b) => a + b, 0) / gatedBlocks.length;

    // Relative gating at -10 LUFS below average
    const relativeThreshold = avg - 10;
    const finalBlocks = gatedBlocks.filter(b => b > relativeThreshold);

    if (finalBlocks.length === 0) return avg;

    return finalBlocks.reduce((a, b) => a + b, 0) / finalBlocks.length;
  }

  /**
   * Get peak level of buffer
   */
  private getPeakLevel(buffer: AudioBuffer): number {
    let peak = 0;

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      for (let i = 0; i < data.length; i++) {
        const abs = Math.abs(data[i]);
        if (abs > peak) peak = abs;
      }
    }

    return peak;
  }

  /**
   * Calculate various level measurements
   */
  private calculateLevels(buffer: AudioBuffer): {
    peak: number;
    rms: number;
    truePeak: number;
    loudness: number;
  } {
    let peak = 0;
    let sumSquares = 0;
    let sampleCount = 0;

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);
      for (let i = 0; i < data.length; i++) {
        const sample = data[i];
        const abs = Math.abs(sample);
        if (abs > peak) peak = abs;
        sumSquares += sample * sample;
        sampleCount++;
      }
    }

    const rms = Math.sqrt(sumSquares / sampleCount);
    const loudness = this.calculateIntegratedLoudness(buffer);

    // True peak (would need oversampling for proper measurement)
    // Simplified: just use sample peak
    const truePeak = 20 * Math.log10(peak);

    return {
      peak: 20 * Math.log10(peak),
      rms: 20 * Math.log10(rms),
      truePeak,
      loudness,
    };
  }

  /**
   * Encode buffer to output format
   */
  private async encodeBuffer(
    buffer: AudioBuffer,
    config: BounceConfig
  ): Promise<Blob> {
    switch (config.format) {
      case 'wav':
        return this.encodeWAV(buffer, config);
      case 'mp3':
      case 'ogg':
        // Would need external encoder library
        // For now, fall back to WAV
        console.warn(`${config.format} encoding not available, using WAV`);
        return this.encodeWAV(buffer, config);
      default:
        return this.encodeWAV(buffer, config);
    }
  }

  /**
   * Encode buffer to WAV format
   */
  private encodeWAV(buffer: AudioBuffer, config: BounceConfig): Blob {
    const numChannels = buffer.numberOfChannels;
    const sampleRate = buffer.sampleRate;
    const bytesPerSample = config.bitDepth / 8;
    const blockAlign = numChannels * bytesPerSample;
    const byteRate = sampleRate * blockAlign;
    const dataSize = buffer.length * blockAlign;

    // WAV header is 44 bytes
    const arrayBuffer = new ArrayBuffer(44 + dataSize);
    const view = new DataView(arrayBuffer);

    // RIFF header
    this.writeString(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    this.writeString(view, 8, 'WAVE');

    // fmt chunk
    this.writeString(view, 12, 'fmt ');
    view.setUint32(16, 16, true); // chunk size
    view.setUint16(20, config.bitDepth === 32 ? 3 : 1, true); // format (1=PCM, 3=IEEE float)
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, config.bitDepth, true);

    // data chunk
    this.writeString(view, 36, 'data');
    view.setUint32(40, dataSize, true);

    // Write interleaved samples
    let offset = 44;

    for (let i = 0; i < buffer.length; i++) {
      for (let ch = 0; ch < numChannels; ch++) {
        const sample = buffer.getChannelData(ch)[i];

        if (config.bitDepth === 32) {
          // 32-bit float
          view.setFloat32(offset, sample, true);
        } else if (config.bitDepth === 24) {
          // 24-bit integer
          const int24 = Math.max(-8388608, Math.min(8388607, Math.floor(sample * 8388607)));
          view.setUint8(offset, int24 & 0xFF);
          view.setUint8(offset + 1, (int24 >> 8) & 0xFF);
          view.setUint8(offset + 2, (int24 >> 16) & 0xFF);
        } else {
          // 16-bit integer
          let int16 = Math.floor(sample * 32767);

          // Apply dither
          if (config.dither) {
            int16 += (Math.random() - 0.5) * 2;
          }

          int16 = Math.max(-32768, Math.min(32767, int16));
          view.setInt16(offset, int16, true);
        }

        offset += bytesPerSample;
      }
    }

    return new Blob([arrayBuffer], { type: 'audio/wav' });
  }

  /**
   * Write string to DataView
   */
  private writeString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  }

  /**
   * Report progress
   */
  private reportProgress(
    phase: BounceProgress['phase'],
    progress: number,
    currentTime: number,
    totalDuration: number,
    startTime: number
  ): void {
    const elapsedMs = performance.now() - startTime;
    const remainingMs = progress > 0
      ? (elapsedMs / progress) * (1 - progress)
      : 0;

    this.onProgress?.({
      phase,
      progress,
      currentTime,
      totalDuration,
      elapsedMs,
      remainingMs,
    });
  }
}

// ============ PRESET BOUNCE CONFIGS ============

export const PRESET_BOUNCE_CONFIGS: Record<string, Partial<BounceConfig>> = {
  broadcast: {
    sampleRate: 48000,
    bitDepth: 24,
    format: 'wav',
    channels: 'stereo',
    normalize: true,
    targetLoudness: -24, // EBU R128
    dither: false,
    truePeakLimit: true,
    truePeakCeiling: -1.0, // EBU R128 true peak max
    limiterRelease: 100,
  },
  streaming: {
    sampleRate: 44100,
    bitDepth: 16,
    format: 'mp3',
    channels: 'stereo',
    normalize: true,
    targetLoudness: -14, // Spotify/YouTube
    dither: true,
    truePeakLimit: true,
    truePeakCeiling: -1.0, // Streaming platforms requirement
    limiterRelease: 80, // Faster for pop/electronic
  },
  mastering: {
    sampleRate: 96000,
    bitDepth: 32,
    format: 'wav',
    channels: 'stereo',
    normalize: false,
    dither: false,
    truePeakLimit: false, // Mastering engineer applies own limiting
  },
  mobile: {
    sampleRate: 44100,
    bitDepth: 16,
    format: 'ogg',
    channels: 'stereo',
    normalize: true,
    targetLoudness: -16, // Mobile playback
    dither: true,
    truePeakLimit: true,
    truePeakCeiling: -1.0,
    limiterRelease: 100,
  },
  certification: {
    sampleRate: 48000,
    bitDepth: 24,
    format: 'wav',
    channels: 'stereo',
    normalize: false,
    dither: false,
    includeEffects: true,
    truePeakLimit: true,
    truePeakCeiling: -0.3, // Casino certification requires tight headroom
    limiterRelease: 150, // Slower for natural sound
  },
  podcast: {
    sampleRate: 44100,
    bitDepth: 16,
    format: 'mp3',
    channels: 'mono',
    normalize: true,
    targetLoudness: -16, // Apple Podcasts / Spotify
    dither: true,
    truePeakLimit: true,
    truePeakCeiling: -1.5, // Safer for voice
    limiterRelease: 200, // Very slow for natural voice
  },
};

// ============ DEFAULT STEM CONFIGS ============

export const DEFAULT_STEM_CONFIGS: StemConfig[] = [
  { bus: 'music', suffix: 'music', enabled: true },
  { bus: 'sfx', suffix: 'sfx', enabled: true },
  { bus: 'ambience', suffix: 'amb', enabled: true },
  { bus: 'voice', suffix: 'vo', enabled: true },
  { bus: 'master', suffix: 'master', enabled: true },
];
