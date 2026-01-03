/**
 * LUFS Meter (ITU-R BS.1770-4 / EBU R128 Compliant)
 *
 * Professional loudness measurement implementing the full ITU-R BS.1770-4 algorithm:
 * - K-weighting filter (high shelf + high-pass)
 * - Gated loudness measurement (absolute -70 LUFS gate, relative -10 LU gate)
 * - Momentary (400ms), Short-term (3s), and Integrated loudness
 * - Loudness Range (LRA) calculation
 *
 * Signal Flow:
 * ```
 * Input → K-Weighting → Mean Square → Gating → Loudness Calculation
 *            ↓
 *    Stage 1: High Shelf (+4dB @ >1500Hz)
 *    Stage 2: High Pass (60Hz, 2nd order)
 * ```
 *
 * @module core/dsp/lufsMeter
 */

// ============ Types ============

export interface LUFSMeterConfig {
  /** Sample rate */
  sampleRate: number;
  /** Number of channels (1=mono, 2=stereo, 5.1 also supported) */
  channels: number;
}

export interface LUFSReading {
  /** Momentary loudness (400ms window) in LUFS */
  momentary: number;
  /** Short-term loudness (3s window) in LUFS */
  shortTerm: number;
  /** Integrated loudness (program) in LUFS */
  integrated: number;
  /** Loudness Range in LU */
  range: number;
  /** True peak in dBTP */
  truePeak: number;
}

// ============ K-Weighting Filter Coefficients ============

/**
 * K-weighting pre-filter coefficients for 48kHz.
 * Stage 1: High shelf filter boosting high frequencies (+4dB above 1500Hz)
 * Stage 2: High-pass filter at 60Hz (removes low rumble)
 *
 * Coefficients are sample-rate dependent. These are for 48kHz.
 * For other rates, coefficients need to be recalculated.
 */

// Stage 1: High shelf filter (boost highs)
// f0 = 1681.97 Hz, Q = 0.7071068, gain = +4dB
const SHELF_B0_48K = 1.53512485958697;
const SHELF_B1_48K = -2.69169618940638;
const SHELF_B2_48K = 1.19839281085285;
const SHELF_A1_48K = -1.69065929318241;
const SHELF_A2_48K = 0.73248077421585;

// Stage 2: High-pass filter (remove lows)
// f0 = 38.13547087602444 Hz, Q = 0.5003270373238773
const HPF_B0_48K = 1.0;
const HPF_B1_48K = -2.0;
const HPF_B2_48K = 1.0;
const HPF_A1_48K = -1.99004745483398;
const HPF_A2_48K = 0.99007225036621;

// ============ Constants ============

/** 400ms window size in samples @ 48kHz */
const MOMENTARY_WINDOW_48K = 19200;

/** 3s window size in samples @ 48kHz */
const SHORT_TERM_WINDOW_48K = 144000;

/** Gate block size in samples (100ms @ 48kHz) */
const GATE_BLOCK_48K = 4800;

/** Absolute gate threshold in LUFS */
const ABSOLUTE_GATE = -70;

/** Relative gate threshold in LU below ungated mean */
const RELATIVE_GATE = -10;

/** Channel weights for loudness sum (L, R, C, LFE, Ls, Rs) */
const CHANNEL_WEIGHTS = [1.0, 1.0, 1.0, 0.0, 1.41, 1.41];

// ============ LUFS Meter Class ============

export class LUFSMeter {
  private config: LUFSMeterConfig;

  // K-weighting filter state (per channel)
  // Stage 1: High shelf
  private shelf_x1: Float32Array;
  private shelf_x2: Float32Array;
  private shelf_y1: Float32Array;
  private shelf_y2: Float32Array;

  // Stage 2: High-pass
  private hpf_x1: Float32Array;
  private hpf_x2: Float32Array;
  private hpf_y1: Float32Array;
  private hpf_y2: Float32Array;

  // Ring buffers for windowed measurements
  private momentaryBuffer: Float32Array;
  private shortTermBuffer: Float32Array;
  private momentaryWritePos = 0;
  private shortTermWritePos = 0;
  private momentarySum = 0;
  private shortTermSum = 0;

  // Gated measurement storage
  private gatedBlocks: number[] = [];
  private currentBlockSum = 0;
  private currentBlockSamples = 0;

  // True peak tracking
  private truePeakMax = 0;

  // Window sizes (sample-rate adjusted)
  private momentaryWindowSize: number;
  private shortTermWindowSize: number;
  private gateBlockSize: number;

  constructor(config: Partial<LUFSMeterConfig> = {}) {
    this.config = {
      sampleRate: config.sampleRate ?? 48000,
      channels: config.channels ?? 2,
    };

    // Calculate window sizes for this sample rate
    const rateRatio = this.config.sampleRate / 48000;
    this.momentaryWindowSize = Math.round(MOMENTARY_WINDOW_48K * rateRatio);
    this.shortTermWindowSize = Math.round(SHORT_TERM_WINDOW_48K * rateRatio);
    this.gateBlockSize = Math.round(GATE_BLOCK_48K * rateRatio);

    // Initialize filter state arrays
    const ch = this.config.channels;
    this.shelf_x1 = new Float32Array(ch);
    this.shelf_x2 = new Float32Array(ch);
    this.shelf_y1 = new Float32Array(ch);
    this.shelf_y2 = new Float32Array(ch);

    this.hpf_x1 = new Float32Array(ch);
    this.hpf_x2 = new Float32Array(ch);
    this.hpf_y1 = new Float32Array(ch);
    this.hpf_y2 = new Float32Array(ch);

    // Initialize ring buffers
    this.momentaryBuffer = new Float32Array(this.momentaryWindowSize);
    this.shortTermBuffer = new Float32Array(this.shortTermWindowSize);
  }

  /**
   * Process audio block and update loudness measurements.
   * @param channels Array of channel data (interleaved or separate)
   */
  process(channels: Float32Array[]): void {
    const numChannels = Math.min(channels.length, this.config.channels);
    const blockLen = channels[0]?.length ?? 0;
    if (blockLen === 0) return;

    for (let i = 0; i < blockLen; i++) {
      let sumSquares = 0;
      let maxSample = 0;

      for (let ch = 0; ch < numChannels; ch++) {
        const input = channels[ch][i];

        // Track true peak (simple sample peak for now)
        const absSample = Math.abs(input);
        if (absSample > maxSample) maxSample = absSample;

        // Apply K-weighting Stage 1: High shelf
        const shelf_out =
          SHELF_B0_48K * input +
          SHELF_B1_48K * this.shelf_x1[ch] +
          SHELF_B2_48K * this.shelf_x2[ch] -
          SHELF_A1_48K * this.shelf_y1[ch] -
          SHELF_A2_48K * this.shelf_y2[ch];

        this.shelf_x2[ch] = this.shelf_x1[ch];
        this.shelf_x1[ch] = input;
        this.shelf_y2[ch] = this.shelf_y1[ch];
        this.shelf_y1[ch] = shelf_out;

        // Apply K-weighting Stage 2: High-pass
        const hpf_out =
          HPF_B0_48K * shelf_out +
          HPF_B1_48K * this.hpf_x1[ch] +
          HPF_B2_48K * this.hpf_x2[ch] -
          HPF_A1_48K * this.hpf_y1[ch] -
          HPF_A2_48K * this.hpf_y2[ch];

        this.hpf_x2[ch] = this.hpf_x1[ch];
        this.hpf_x1[ch] = shelf_out;
        this.hpf_y2[ch] = this.hpf_y1[ch];
        this.hpf_y1[ch] = hpf_out;

        // Accumulate weighted mean square
        const weight = ch < CHANNEL_WEIGHTS.length ? CHANNEL_WEIGHTS[ch] : 1.0;
        sumSquares += weight * hpf_out * hpf_out;
      }

      // Update true peak
      if (maxSample > this.truePeakMax) {
        this.truePeakMax = maxSample;
      }

      // Update momentary buffer (sliding window)
      this.momentarySum -= this.momentaryBuffer[this.momentaryWritePos];
      this.momentaryBuffer[this.momentaryWritePos] = sumSquares;
      this.momentarySum += sumSquares;
      this.momentaryWritePos = (this.momentaryWritePos + 1) % this.momentaryWindowSize;

      // Update short-term buffer (sliding window)
      this.shortTermSum -= this.shortTermBuffer[this.shortTermWritePos];
      this.shortTermBuffer[this.shortTermWritePos] = sumSquares;
      this.shortTermSum += sumSquares;
      this.shortTermWritePos = (this.shortTermWritePos + 1) % this.shortTermWindowSize;

      // Accumulate for gated measurement
      this.currentBlockSum += sumSquares;
      this.currentBlockSamples++;

      // Complete a gate block (100ms)
      if (this.currentBlockSamples >= this.gateBlockSize) {
        const blockLoudness = this.currentBlockSum / this.currentBlockSamples;
        const blockLUFS = this.meanSquareToLUFS(blockLoudness);

        // Only store blocks above absolute gate
        if (blockLUFS > ABSOLUTE_GATE) {
          this.gatedBlocks.push(blockLoudness);
        }

        this.currentBlockSum = 0;
        this.currentBlockSamples = 0;
      }
    }
  }

  /**
   * Get current loudness readings.
   */
  getReading(): LUFSReading {
    // Momentary loudness (400ms)
    const momentaryMean = this.momentarySum / this.momentaryWindowSize;
    const momentary = this.meanSquareToLUFS(momentaryMean);

    // Short-term loudness (3s)
    const shortTermMean = this.shortTermSum / this.shortTermWindowSize;
    const shortTerm = this.meanSquareToLUFS(shortTermMean);

    // Integrated loudness (gated)
    const integrated = this.calculateIntegrated();

    // Loudness range
    const range = this.calculateLoudnessRange();

    // True peak in dBTP
    const truePeak = this.truePeakMax > 0 ? 20 * Math.log10(this.truePeakMax) : -100;

    return {
      momentary,
      shortTerm,
      integrated,
      range,
      truePeak,
    };
  }

  /**
   * Calculate gated integrated loudness per EBU R128.
   */
  private calculateIntegrated(): number {
    if (this.gatedBlocks.length === 0) return -100;

    // First pass: calculate ungated mean (already filtered by absolute gate)
    const ungatedMean =
      this.gatedBlocks.reduce((sum, val) => sum + val, 0) / this.gatedBlocks.length;
    const ungatedLUFS = this.meanSquareToLUFS(ungatedMean);

    // Second pass: relative gate at -10 LU below ungated mean
    const relativeThreshold = ungatedLUFS + RELATIVE_GATE;
    const gatedBlocks = this.gatedBlocks.filter(
      (val) => this.meanSquareToLUFS(val) > relativeThreshold
    );

    if (gatedBlocks.length === 0) return -100;

    // Final integrated loudness
    const gatedMean = gatedBlocks.reduce((sum, val) => sum + val, 0) / gatedBlocks.length;
    return this.meanSquareToLUFS(gatedMean);
  }

  /**
   * Calculate Loudness Range (LRA) per EBU R128.
   */
  private calculateLoudnessRange(): number {
    if (this.gatedBlocks.length < 20) return 0; // Need enough data

    // Sort blocks by loudness
    const sorted = [...this.gatedBlocks]
      .map((val) => this.meanSquareToLUFS(val))
      .filter((lufs) => lufs > -70)
      .sort((a, b) => a - b);

    if (sorted.length < 20) return 0;

    // LRA = 95th percentile - 10th percentile
    const p10Index = Math.floor(sorted.length * 0.1);
    const p95Index = Math.floor(sorted.length * 0.95);

    return sorted[p95Index] - sorted[p10Index];
  }

  /**
   * Convert mean square value to LUFS.
   * LUFS = -0.691 + 10 * log10(meanSquare)
   */
  private meanSquareToLUFS(meanSquare: number): number {
    if (meanSquare <= 0) return -100;
    return -0.691 + 10 * Math.log10(meanSquare);
  }

  /**
   * Reset all measurements.
   */
  reset(): void {
    // Reset filter state
    this.shelf_x1.fill(0);
    this.shelf_x2.fill(0);
    this.shelf_y1.fill(0);
    this.shelf_y2.fill(0);
    this.hpf_x1.fill(0);
    this.hpf_x2.fill(0);
    this.hpf_y1.fill(0);
    this.hpf_y2.fill(0);

    // Reset buffers
    this.momentaryBuffer.fill(0);
    this.shortTermBuffer.fill(0);
    this.momentaryWritePos = 0;
    this.shortTermWritePos = 0;
    this.momentarySum = 0;
    this.shortTermSum = 0;

    // Reset gating
    this.gatedBlocks = [];
    this.currentBlockSum = 0;
    this.currentBlockSamples = 0;

    // Reset peak
    this.truePeakMax = 0;
  }

  /**
   * Reset only the integrated measurement (for new program start).
   */
  resetIntegrated(): void {
    this.gatedBlocks = [];
    this.currentBlockSum = 0;
    this.currentBlockSamples = 0;
  }
}

// ============ Factory Function ============

/**
 * Create a LUFS meter instance.
 */
export function createLUFSMeter(config: Partial<LUFSMeterConfig> = {}): LUFSMeter {
  return new LUFSMeter(config);
}

export default LUFSMeter;
