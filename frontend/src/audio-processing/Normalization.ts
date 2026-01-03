/**
 * ReelForge Audio Normalization
 *
 * Professional audio normalization with multiple standards:
 * - Peak normalization
 * - RMS normalization
 * - LUFS (EBU R128) normalization
 *
 * @module audio-processing/Normalization
 */

// ============ Types ============

export type NormalizationType = 'peak' | 'rms' | 'lufs';

export interface NormalizationOptions {
  type: NormalizationType;
  targetLevel: number; // dB
  ceiling?: number; // dB, for limiting
  truePeak?: boolean; // Use true peak limiting
  windowSize?: number; // For RMS/LUFS calculation
}

export interface NormalizationAnalysis {
  peakLevel: number; // dB
  rmsLevel: number; // dB
  lufsIntegrated: number; // LUFS
  lufsShortTerm: number; // LUFS
  lufsMomentary: number; // LUFS
  truePeak: number; // dBTP
  loudnessRange: number; // LU
  dynamicRange: number; // dB
  clipCount: number;
}

export interface NormalizationResult {
  gain: number; // Linear gain applied
  gainDb: number; // Gain in dB
  analysis: NormalizationAnalysis;
  clipped: boolean;
  processingTime: number;
}

// ============ Constants ============

const LUFS_BLOCK_MS = 400; // LUFS measurement block

// ============ Utility Functions ============

function linearToDb(linear: number): number {
  return linear > 0 ? 20 * Math.log10(linear) : -Infinity;
}

function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

// ============ K-Weighting Filter ============

class KWeightingFilter {
  // Pre-filter coefficients (high-shelf)
  private preB: number[];
  private preA: number[];

  // High-pass filter coefficients
  private hpB: number[];
  private hpA: number[];

  // Filter states
  private preState: number[][];
  private hpState: number[][];

  constructor(sampleRate: number) {
    // Pre-filter: high shelf +4dB at 1681 Hz
    // These are approximate coefficients for demonstration
    const f0 = 1681.97;
    const G = 3.999843853973347;
    const Q = 0.7071752369554196;

    const K = Math.tan((Math.PI * f0) / sampleRate);
    const Vh = Math.pow(10, G / 20);
    const Vb = Math.pow(Vh, 0.4996667741545416);

    const a0 = 1 + K / Q + K * K;
    this.preB = [
      (Vh + Vb * K / Q + K * K) / a0,
      2 * (K * K - Vh) / a0,
      (Vh - Vb * K / Q + K * K) / a0,
    ];
    this.preA = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0];

    // High-pass filter at 38 Hz
    const fc = 38.13547087602444;
    const Qhp = 0.5003270373238773;
    const Khp = Math.tan((Math.PI * fc) / sampleRate);

    const a0hp = 1 + Khp / Qhp + Khp * Khp;
    this.hpB = [1 / a0hp, -2 / a0hp, 1 / a0hp];
    this.hpA = [1, 2 * (Khp * Khp - 1) / a0hp, (1 - Khp / Qhp + Khp * Khp) / a0hp];

    // Initialize states for 2 channels
    this.preState = [[0, 0], [0, 0]];
    this.hpState = [[0, 0], [0, 0]];
  }

  reset(): void {
    this.preState = [[0, 0], [0, 0]];
    this.hpState = [[0, 0], [0, 0]];
  }

  process(sample: number, channel: number): number {
    // Pre-filter
    let x = sample;
    let y = this.preB[0] * x + this.preState[channel][0];
    this.preState[channel][0] = this.preB[1] * x - this.preA[1] * y + this.preState[channel][1];
    this.preState[channel][1] = this.preB[2] * x - this.preA[2] * y;

    // High-pass
    x = y;
    y = this.hpB[0] * x + this.hpState[channel][0];
    this.hpState[channel][0] = this.hpB[1] * x - this.hpA[1] * y + this.hpState[channel][1];
    this.hpState[channel][1] = this.hpB[2] * x - this.hpA[2] * y;

    return y;
  }
}

// ============ LUFS Meter ============

class LufsMeter {
  private sampleRate: number;
  private filter: KWeightingFilter;
  private blockSize: number;
  private hopSize: number;

  // Gating
  private absoluteThreshold = -70; // LUFS
  private relativeThreshold = -10; // LU below ungated

  constructor(sampleRate: number) {
    this.sampleRate = sampleRate;
    this.filter = new KWeightingFilter(sampleRate);
    this.blockSize = Math.round((LUFS_BLOCK_MS / 1000) * sampleRate);
    this.hopSize = Math.round(this.blockSize / 4); // 75% overlap
  }

  /**
   * Calculate integrated LUFS for entire buffer.
   */
  measureIntegrated(buffer: AudioBuffer): number {
    const channels = Math.min(buffer.numberOfChannels, 2);
    const channelData: Float32Array[] = [];

    for (let ch = 0; ch < channels; ch++) {
      channelData.push(buffer.getChannelData(ch));
    }

    // Apply K-weighting
    this.filter.reset();
    const filtered: Float32Array[] = [];

    for (let ch = 0; ch < channels; ch++) {
      const data = new Float32Array(buffer.length);
      for (let i = 0; i < buffer.length; i++) {
        data[i] = this.filter.process(channelData[ch][i], ch);
      }
      filtered.push(data);
    }

    // Calculate block loudness
    const blocks: number[] = [];

    for (let start = 0; start + this.blockSize <= buffer.length; start += this.hopSize) {
      let sumSquared = 0;

      for (let ch = 0; ch < channels; ch++) {
        for (let i = start; i < start + this.blockSize; i++) {
          sumSquared += filtered[ch][i] * filtered[ch][i];
        }
      }

      const meanSquared = sumSquared / (this.blockSize * channels);
      const loudness = -0.691 + 10 * Math.log10(meanSquared);

      if (loudness > this.absoluteThreshold) {
        blocks.push(loudness);
      }
    }

    if (blocks.length === 0) {
      return -Infinity;
    }

    // Calculate ungated average
    const ungatedSum = blocks.reduce((a, b) => a + Math.pow(10, b / 10), 0);
    const ungatedLufs = 10 * Math.log10(ungatedSum / blocks.length);

    // Apply relative gate
    const relativeGate = ungatedLufs + this.relativeThreshold;
    const gatedBlocks = blocks.filter(b => b > relativeGate);

    if (gatedBlocks.length === 0) {
      return ungatedLufs;
    }

    const gatedSum = gatedBlocks.reduce((a, b) => a + Math.pow(10, b / 10), 0);
    return 10 * Math.log10(gatedSum / gatedBlocks.length);
  }

  /**
   * Calculate short-term LUFS (3 second window).
   */
  measureShortTerm(buffer: AudioBuffer): number {
    const windowSize = Math.min(3 * this.sampleRate, buffer.length);
    const startSample = Math.max(0, buffer.length - windowSize);

    // Create sub-buffer for last 3 seconds
    const context = new OfflineAudioContext(
      buffer.numberOfChannels,
      windowSize,
      this.sampleRate
    );

    const subBuffer = context.createBuffer(
      buffer.numberOfChannels,
      windowSize,
      this.sampleRate
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const srcData = buffer.getChannelData(ch);
      const dstData = subBuffer.getChannelData(ch);

      for (let i = 0; i < windowSize; i++) {
        dstData[i] = srcData[startSample + i];
      }
    }

    return this.measureIntegrated(subBuffer);
  }

  /**
   * Calculate momentary LUFS (400ms window).
   */
  measureMomentary(buffer: AudioBuffer): number {
    const windowSize = Math.min(Math.round(0.4 * this.sampleRate), buffer.length);
    const startSample = Math.max(0, buffer.length - windowSize);

    const context = new OfflineAudioContext(
      buffer.numberOfChannels,
      windowSize,
      this.sampleRate
    );

    const subBuffer = context.createBuffer(
      buffer.numberOfChannels,
      windowSize,
      this.sampleRate
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const srcData = buffer.getChannelData(ch);
      const dstData = subBuffer.getChannelData(ch);

      for (let i = 0; i < windowSize; i++) {
        dstData[i] = srcData[startSample + i];
      }
    }

    return this.measureIntegrated(subBuffer);
  }
}

// ============ Normalization Engine ============

export class NormalizationEngine {
  /**
   * Analyze audio buffer.
   */
  analyze(buffer: AudioBuffer): NormalizationAnalysis {
    const channels = buffer.numberOfChannels;
    const sampleRate = buffer.sampleRate;

    let peakLevel = 0;
    let rmsSum = 0;
    let clipCount = 0;

    // Calculate peak and RMS
    for (let ch = 0; ch < channels; ch++) {
      const data = buffer.getChannelData(ch);

      for (let i = 0; i < data.length; i++) {
        const abs = Math.abs(data[i]);
        if (abs > peakLevel) peakLevel = abs;
        if (abs > 1.0) clipCount++;
        rmsSum += data[i] * data[i];
      }
    }

    const rmsLevel = Math.sqrt(rmsSum / (buffer.length * channels));

    // Calculate LUFS
    const lufsMeter = new LufsMeter(sampleRate);
    const lufsIntegrated = lufsMeter.measureIntegrated(buffer);
    const lufsShortTerm = lufsMeter.measureShortTerm(buffer);
    const lufsMomentary = lufsMeter.measureMomentary(buffer);

    // Calculate true peak (simplified - should use oversampling)
    const truePeak = peakLevel; // In a real implementation, oversample and find true peak

    // Loudness range (simplified)
    const loudnessRange = Math.abs(lufsMomentary - lufsIntegrated);

    // Dynamic range
    const dynamicRange = linearToDb(peakLevel) - linearToDb(rmsLevel);

    return {
      peakLevel: linearToDb(peakLevel),
      rmsLevel: linearToDb(rmsLevel),
      lufsIntegrated,
      lufsShortTerm,
      lufsMomentary,
      truePeak: linearToDb(truePeak),
      loudnessRange,
      dynamicRange,
      clipCount,
    };
  }

  /**
   * Calculate normalization gain.
   */
  calculateGain(analysis: NormalizationAnalysis, options: NormalizationOptions): number {
    let currentLevel: number;

    switch (options.type) {
      case 'peak':
        currentLevel = analysis.peakLevel;
        break;
      case 'rms':
        currentLevel = analysis.rmsLevel;
        break;
      case 'lufs':
        currentLevel = analysis.lufsIntegrated;
        break;
    }

    const gainDb = options.targetLevel - currentLevel;

    // Apply ceiling if specified
    if (options.ceiling !== undefined) {
      const maxGainDb = options.ceiling - analysis.peakLevel;
      return dbToLinear(Math.min(gainDb, maxGainDb));
    }

    return dbToLinear(gainDb);
  }

  /**
   * Normalize audio buffer.
   */
  normalize(
    buffer: AudioBuffer,
    options: NormalizationOptions
  ): { buffer: AudioBuffer; result: NormalizationResult } {
    const startTime = performance.now();

    // Analyze
    const analysis = this.analyze(buffer);

    // Calculate gain
    const gain = this.calculateGain(analysis, options);
    const gainDb = linearToDb(gain);

    // Check for clipping
    const willClip = analysis.peakLevel + gainDb > 0;

    // Create normalized buffer
    const context = new OfflineAudioContext(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    const normalizedBuffer = context.createBuffer(
      buffer.numberOfChannels,
      buffer.length,
      buffer.sampleRate
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const srcData = buffer.getChannelData(ch);
      const dstData = normalizedBuffer.getChannelData(ch);

      for (let i = 0; i < buffer.length; i++) {
        let sample = srcData[i] * gain;

        // Soft clip if necessary
        if (options.ceiling !== undefined && Math.abs(sample) > dbToLinear(options.ceiling)) {
          sample = Math.sign(sample) * dbToLinear(options.ceiling);
        }

        dstData[i] = sample;
      }
    }

    return {
      buffer: normalizedBuffer,
      result: {
        gain,
        gainDb,
        analysis,
        clipped: willClip,
        processingTime: performance.now() - startTime,
      },
    };
  }

  /**
   * Normalize to broadcast standard (EBU R128).
   */
  normalizeToR128(buffer: AudioBuffer): { buffer: AudioBuffer; result: NormalizationResult } {
    return this.normalize(buffer, {
      type: 'lufs',
      targetLevel: -23, // EBU R128 target
      ceiling: -1, // True peak ceiling
      truePeak: true,
    });
  }

  /**
   * Normalize for streaming platforms.
   */
  normalizeForStreaming(
    buffer: AudioBuffer,
    platform: 'spotify' | 'youtube' | 'apple' | 'tidal'
  ): { buffer: AudioBuffer; result: NormalizationResult } {
    const targets: Record<string, number> = {
      spotify: -14,
      youtube: -14,
      apple: -16,
      tidal: -14,
    };

    return this.normalize(buffer, {
      type: 'lufs',
      targetLevel: targets[platform],
      ceiling: -1,
      truePeak: true,
    });
  }
}

// ============ Singleton Instance ============

export const normalizationEngine = new NormalizationEngine();

// ============ Utility Exports ============

export { linearToDb, dbToLinear };

/**
 * Format LUFS value for display.
 */
export function formatLufs(lufs: number): string {
  if (!isFinite(lufs)) return '-∞ LUFS';
  return `${lufs.toFixed(1)} LUFS`;
}

/**
 * Format dB value for display.
 */
export function formatDb(db: number): string {
  if (!isFinite(db)) return '-∞ dB';
  return `${db >= 0 ? '+' : ''}${db.toFixed(1)} dB`;
}

/**
 * Get loudness target for platform.
 */
export function getPlatformTarget(platform: string): number {
  const targets: Record<string, number> = {
    spotify: -14,
    youtube: -14,
    'apple-music': -16,
    tidal: -14,
    amazon: -14,
    deezer: -15,
    soundcloud: -14,
    broadcast: -23, // EBU R128
    podcast: -16, // Apple Podcasts
    cinema: -24, // ATSC A/85
  };

  return targets[platform.toLowerCase()] ?? -14;
}
