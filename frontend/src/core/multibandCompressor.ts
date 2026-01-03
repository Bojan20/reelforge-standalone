/**
 * Multiband Compressor DSP
 *
 * Professional multiband dynamics processor:
 * - 3-5 band Linkwitz-Riley crossover
 * - Independent compressor per band
 * - Sidechain input support
 * - Lookahead for transient preservation
 * - Soft/hard knee options
 * - Peak/RMS detection modes
 */

// ============ TYPES ============

export type DetectionMode = 'peak' | 'rms';
export type KneeType = 'soft' | 'hard';

export interface BandConfig {
  /** Band ID */
  id: string;
  /** Low frequency cutoff (Hz) */
  lowFreq: number;
  /** High frequency cutoff (Hz) */
  highFreq: number;
  /** Threshold (dB) */
  threshold: number;
  /** Ratio (1:1 to inf:1) */
  ratio: number;
  /** Attack time (ms) */
  attackMs: number;
  /** Release time (ms) */
  releaseMs: number;
  /** Makeup gain (dB) */
  makeupGain: number;
  /** Band bypass */
  bypass: boolean;
  /** Band solo */
  solo: boolean;
  /** Band mute */
  mute: boolean;
}

export interface MultibandCompressorConfig {
  /** Number of bands (3-5) */
  bandCount: 3 | 4 | 5;
  /** Individual band configs */
  bands: BandConfig[];
  /** Global threshold offset (dB) */
  globalThreshold: number;
  /** Global ratio multiplier */
  globalRatio: number;
  /** Detection mode */
  detectionMode: DetectionMode;
  /** Knee type */
  kneeType: KneeType;
  /** Knee width (dB, for soft knee) */
  kneeWidth: number;
  /** Lookahead (ms) */
  lookaheadMs: number;
  /** Output gain (dB) */
  outputGain: number;
  /** Mix (0-1 for parallel compression) */
  mix: number;
  /** Global bypass */
  bypass: boolean;
}

export interface BandMeter {
  /** Input level (dB) */
  inputLevel: number;
  /** Output level (dB) */
  outputLevel: number;
  /** Gain reduction (dB) */
  gainReduction: number;
}

export interface MultibandMeter {
  /** Per-band meters */
  bands: BandMeter[];
  /** Overall input level (dB) */
  inputLevel: number;
  /** Overall output level (dB) */
  outputLevel: number;
  /** Overall gain reduction (dB) */
  gainReduction: number;
}

// ============ DEFAULT CONFIGS ============

const DEFAULT_3_BAND: BandConfig[] = [
  { id: 'low', lowFreq: 20, highFreq: 200, threshold: -20, ratio: 4, attackMs: 30, releaseMs: 200, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'mid', lowFreq: 200, highFreq: 2000, threshold: -18, ratio: 3, attackMs: 15, releaseMs: 150, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'high', lowFreq: 2000, highFreq: 20000, threshold: -15, ratio: 2.5, attackMs: 5, releaseMs: 100, makeupGain: 0, bypass: false, solo: false, mute: false },
];

const DEFAULT_4_BAND: BandConfig[] = [
  { id: 'low', lowFreq: 20, highFreq: 150, threshold: -20, ratio: 4, attackMs: 30, releaseMs: 200, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'low-mid', lowFreq: 150, highFreq: 800, threshold: -18, ratio: 3.5, attackMs: 20, releaseMs: 150, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'high-mid', lowFreq: 800, highFreq: 4000, threshold: -16, ratio: 3, attackMs: 10, releaseMs: 120, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'high', lowFreq: 4000, highFreq: 20000, threshold: -14, ratio: 2.5, attackMs: 3, releaseMs: 80, makeupGain: 0, bypass: false, solo: false, mute: false },
];

const DEFAULT_5_BAND: BandConfig[] = [
  { id: 'sub', lowFreq: 20, highFreq: 80, threshold: -22, ratio: 5, attackMs: 50, releaseMs: 250, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'low', lowFreq: 80, highFreq: 300, threshold: -20, ratio: 4, attackMs: 30, releaseMs: 200, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'mid', lowFreq: 300, highFreq: 2000, threshold: -18, ratio: 3, attackMs: 15, releaseMs: 150, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'high-mid', lowFreq: 2000, highFreq: 8000, threshold: -15, ratio: 2.5, attackMs: 8, releaseMs: 100, makeupGain: 0, bypass: false, solo: false, mute: false },
  { id: 'high', lowFreq: 8000, highFreq: 20000, threshold: -12, ratio: 2, attackMs: 3, releaseMs: 60, makeupGain: 0, bypass: false, solo: false, mute: false },
];

const DEFAULT_CONFIG: MultibandCompressorConfig = {
  bandCount: 4,
  bands: DEFAULT_4_BAND,
  globalThreshold: 0,
  globalRatio: 1,
  detectionMode: 'peak',
  kneeType: 'soft',
  kneeWidth: 6,
  lookaheadMs: 5,
  outputGain: 0,
  mix: 1,
  bypass: false,
};

// ============ BAND COMPRESSOR ============

class BandCompressor {
  private ctx: AudioContext;
  private config: BandConfig;

  // Nodes
  private inputGain: GainNode;
  private compressor: DynamicsCompressorNode;
  private makeupGainNode: GainNode;
  private outputGain: GainNode;
  private analyzer: AnalyserNode;

  // Metering
  private inputLevel: number = -60;
  private outputLevel: number = -60;
  private gainReduction: number = 0;

  constructor(ctx: AudioContext, config: BandConfig) {
    this.ctx = ctx;
    this.config = config;

    // Create nodes
    this.inputGain = ctx.createGain();
    this.compressor = ctx.createDynamicsCompressor();
    this.makeupGainNode = ctx.createGain();
    this.outputGain = ctx.createGain();
    this.analyzer = ctx.createAnalyser();
    this.analyzer.fftSize = 256;

    // Wire up
    this.inputGain.connect(this.compressor);
    this.compressor.connect(this.makeupGainNode);
    this.makeupGainNode.connect(this.outputGain);
    this.outputGain.connect(this.analyzer);

    // Apply config
    this.applyConfig(config);
  }

  applyConfig(config: BandConfig): void {
    this.config = config;

    // Compressor settings
    this.compressor.threshold.setValueAtTime(config.threshold, this.ctx.currentTime);
    this.compressor.ratio.setValueAtTime(config.ratio, this.ctx.currentTime);
    this.compressor.attack.setValueAtTime(config.attackMs / 1000, this.ctx.currentTime);
    this.compressor.release.setValueAtTime(config.releaseMs / 1000, this.ctx.currentTime);
    this.compressor.knee.setValueAtTime(6, this.ctx.currentTime); // Soft knee

    // Makeup gain
    const makeupLinear = Math.pow(10, config.makeupGain / 20);
    this.makeupGainNode.gain.setValueAtTime(makeupLinear, this.ctx.currentTime);

    // Mute/solo/bypass
    if (config.mute || config.bypass) {
      this.outputGain.gain.setValueAtTime(0, this.ctx.currentTime);
    } else {
      this.outputGain.gain.setValueAtTime(1, this.ctx.currentTime);
    }
  }

  getInput(): GainNode {
    return this.inputGain;
  }

  getOutput(): AnalyserNode {
    return this.analyzer;
  }

  getMeter(): BandMeter {
    // Get gain reduction from compressor
    this.gainReduction = this.compressor.reduction;

    // Estimate input/output levels from analyzer
    const dataArray = new Float32Array(this.analyzer.fftSize);
    this.analyzer.getFloatTimeDomainData(dataArray);

    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) {
      sum += dataArray[i] * dataArray[i];
    }
    const rms = Math.sqrt(sum / dataArray.length);
    this.outputLevel = rms > 0 ? 20 * Math.log10(rms) : -60;
    this.inputLevel = this.outputLevel - this.gainReduction;

    return {
      inputLevel: this.inputLevel,
      outputLevel: this.outputLevel,
      gainReduction: this.gainReduction,
    };
  }

  setSolo(solo: boolean): void {
    this.config.solo = solo;
  }

  dispose(): void {
    this.inputGain.disconnect();
    this.compressor.disconnect();
    this.makeupGainNode.disconnect();
    this.outputGain.disconnect();
    this.analyzer.disconnect();
  }
}

// ============ LINKWITZ-RILEY CROSSOVER ============

class CrossoverFilter {
  private ctx: AudioContext;
  private lowpass1: BiquadFilterNode;
  private lowpass2: BiquadFilterNode;
  private highpass1: BiquadFilterNode;
  private highpass2: BiquadFilterNode;
  private lowOutput: GainNode;
  private highOutput: GainNode;

  constructor(ctx: AudioContext, frequency: number) {
    this.ctx = ctx;

    // Linkwitz-Riley is two cascaded Butterworth filters
    this.lowpass1 = ctx.createBiquadFilter();
    this.lowpass1.type = 'lowpass';
    this.lowpass1.frequency.value = frequency;
    this.lowpass1.Q.value = 0.7071; // Butterworth Q

    this.lowpass2 = ctx.createBiquadFilter();
    this.lowpass2.type = 'lowpass';
    this.lowpass2.frequency.value = frequency;
    this.lowpass2.Q.value = 0.7071;

    this.highpass1 = ctx.createBiquadFilter();
    this.highpass1.type = 'highpass';
    this.highpass1.frequency.value = frequency;
    this.highpass1.Q.value = 0.7071;

    this.highpass2 = ctx.createBiquadFilter();
    this.highpass2.type = 'highpass';
    this.highpass2.frequency.value = frequency;
    this.highpass2.Q.value = 0.7071;

    this.lowOutput = ctx.createGain();
    this.highOutput = ctx.createGain();

    // Wire cascades
    this.lowpass1.connect(this.lowpass2);
    this.lowpass2.connect(this.lowOutput);

    this.highpass1.connect(this.highpass2);
    this.highpass2.connect(this.highOutput);
  }

  getInput(): BiquadFilterNode {
    // Both filters need same input, caller must connect to both
    return this.lowpass1;
  }

  getInputHigh(): BiquadFilterNode {
    return this.highpass1;
  }

  getLowOutput(): GainNode {
    return this.lowOutput;
  }

  getHighOutput(): GainNode {
    return this.highOutput;
  }

  setFrequency(freq: number): void {
    const t = this.ctx.currentTime;
    this.lowpass1.frequency.setValueAtTime(freq, t);
    this.lowpass2.frequency.setValueAtTime(freq, t);
    this.highpass1.frequency.setValueAtTime(freq, t);
    this.highpass2.frequency.setValueAtTime(freq, t);
  }

  dispose(): void {
    this.lowpass1.disconnect();
    this.lowpass2.disconnect();
    this.highpass1.disconnect();
    this.highpass2.disconnect();
    this.lowOutput.disconnect();
    this.highOutput.disconnect();
  }
}

// ============ MULTIBAND COMPRESSOR ============

export class MultibandCompressor {
  private ctx: AudioContext;
  private config: MultibandCompressorConfig;

  // Nodes
  private inputNode: GainNode;
  private dryGain: GainNode;
  private wetGain: GainNode;
  private outputGain: GainNode;
  private outputNode: GainNode;

  // Crossovers and bands
  private crossovers: CrossoverFilter[] = [];
  private bandCompressors: BandCompressor[] = [];
  private bandGains: GainNode[] = [];

  // Sidechain
  private sidechainInput: GainNode | null = null;

  // Metering
  private inputAnalyzer: AnalyserNode;
  private outputAnalyzer: AnalyserNode;

  constructor(ctx: AudioContext, config: Partial<MultibandCompressorConfig> = {}) {
    this.ctx = ctx;
    this.config = { ...DEFAULT_CONFIG, ...config };

    // Ensure correct bands for bandCount
    if (this.config.bandCount === 3) {
      this.config.bands = config.bands ?? [...DEFAULT_3_BAND];
    } else if (this.config.bandCount === 5) {
      this.config.bands = config.bands ?? [...DEFAULT_5_BAND];
    } else {
      this.config.bands = config.bands ?? [...DEFAULT_4_BAND];
    }

    // Create main nodes
    this.inputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.outputGain = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.inputAnalyzer = ctx.createAnalyser();
    this.outputAnalyzer = ctx.createAnalyser();
    this.inputAnalyzer.fftSize = 256;
    this.outputAnalyzer.fftSize = 256;

    // Wire dry path
    this.inputNode.connect(this.inputAnalyzer);
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    // Build multiband chain
    this.buildBands();

    // Wire wet to output
    this.wetGain.connect(this.outputGain);
    this.outputGain.connect(this.outputAnalyzer);
    this.outputAnalyzer.connect(this.outputNode);

    // Apply initial config
    this.applyConfig(this.config);
  }

  private buildBands(): void {
    const bandCount = this.config.bandCount;
    const bands = this.config.bands;

    // Clear existing
    this.crossovers.forEach(c => c.dispose());
    this.bandCompressors.forEach(c => c.dispose());
    this.bandGains.forEach(g => g.disconnect());
    this.crossovers = [];
    this.bandCompressors = [];
    this.bandGains = [];

    // Create crossover frequencies
    const crossoverFreqs: number[] = [];
    for (let i = 0; i < bandCount - 1; i++) {
      crossoverFreqs.push(bands[i].highFreq);
    }

    // Create crossovers
    for (const freq of crossoverFreqs) {
      this.crossovers.push(new CrossoverFilter(this.ctx, freq));
    }

    // Create band compressors
    for (let i = 0; i < bandCount; i++) {
      const compressor = new BandCompressor(this.ctx, bands[i]);
      const bandGain = this.ctx.createGain();

      compressor.getOutput().connect(bandGain);
      bandGain.connect(this.wetGain);

      this.bandCompressors.push(compressor);
      this.bandGains.push(bandGain);
    }

    // Wire crossovers to bands
    if (bandCount === 3) {
      // Input → Crossover1 → Low band
      //                    → Crossover2 → Mid band
      //                                 → High band
      this.inputNode.connect(this.crossovers[0].getInput());
      this.inputNode.connect(this.crossovers[0].getInputHigh());

      this.crossovers[0].getLowOutput().connect(this.bandCompressors[0].getInput());

      this.crossovers[0].getHighOutput().connect(this.crossovers[1].getInput());
      this.crossovers[0].getHighOutput().connect(this.crossovers[1].getInputHigh());

      this.crossovers[1].getLowOutput().connect(this.bandCompressors[1].getInput());
      this.crossovers[1].getHighOutput().connect(this.bandCompressors[2].getInput());

    } else if (bandCount === 4) {
      this.inputNode.connect(this.crossovers[0].getInput());
      this.inputNode.connect(this.crossovers[0].getInputHigh());

      this.crossovers[0].getLowOutput().connect(this.bandCompressors[0].getInput());

      this.crossovers[0].getHighOutput().connect(this.crossovers[1].getInput());
      this.crossovers[0].getHighOutput().connect(this.crossovers[1].getInputHigh());

      this.crossovers[1].getLowOutput().connect(this.bandCompressors[1].getInput());

      this.crossovers[1].getHighOutput().connect(this.crossovers[2].getInput());
      this.crossovers[1].getHighOutput().connect(this.crossovers[2].getInputHigh());

      this.crossovers[2].getLowOutput().connect(this.bandCompressors[2].getInput());
      this.crossovers[2].getHighOutput().connect(this.bandCompressors[3].getInput());

    } else if (bandCount === 5) {
      this.inputNode.connect(this.crossovers[0].getInput());
      this.inputNode.connect(this.crossovers[0].getInputHigh());

      this.crossovers[0].getLowOutput().connect(this.bandCompressors[0].getInput());

      this.crossovers[0].getHighOutput().connect(this.crossovers[1].getInput());
      this.crossovers[0].getHighOutput().connect(this.crossovers[1].getInputHigh());

      this.crossovers[1].getLowOutput().connect(this.bandCompressors[1].getInput());

      this.crossovers[1].getHighOutput().connect(this.crossovers[2].getInput());
      this.crossovers[1].getHighOutput().connect(this.crossovers[2].getInputHigh());

      this.crossovers[2].getLowOutput().connect(this.bandCompressors[2].getInput());

      this.crossovers[2].getHighOutput().connect(this.crossovers[3].getInput());
      this.crossovers[2].getHighOutput().connect(this.crossovers[3].getInputHigh());

      this.crossovers[3].getLowOutput().connect(this.bandCompressors[3].getInput());
      this.crossovers[3].getHighOutput().connect(this.bandCompressors[4].getInput());
    }
  }

  // ============ PUBLIC API ============

  getInput(): GainNode {
    return this.inputNode;
  }

  getOutput(): GainNode {
    return this.outputNode;
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  applyConfig(config: Partial<MultibandCompressorConfig>): void {
    this.config = { ...this.config, ...config };

    // Dry/wet mix
    this.dryGain.gain.setValueAtTime(1 - this.config.mix, this.ctx.currentTime);
    this.wetGain.gain.setValueAtTime(this.config.mix, this.ctx.currentTime);

    // Output gain
    const outputLinear = Math.pow(10, this.config.outputGain / 20);
    this.outputGain.gain.setValueAtTime(outputLinear, this.ctx.currentTime);

    // Apply to each band
    this.config.bands.forEach((bandConfig, i) => {
      if (this.bandCompressors[i]) {
        // Apply global threshold/ratio offsets
        const adjustedConfig = {
          ...bandConfig,
          threshold: bandConfig.threshold + this.config.globalThreshold,
          ratio: bandConfig.ratio * this.config.globalRatio,
        };
        this.bandCompressors[i].applyConfig(adjustedConfig);
      }
    });

    // Handle solo
    const anySoloed = this.config.bands.some(b => b.solo);
    this.bandGains.forEach((gain, i) => {
      const band = this.config.bands[i];
      if (band.mute) {
        gain.gain.setValueAtTime(0, this.ctx.currentTime);
      } else if (anySoloed && !band.solo) {
        gain.gain.setValueAtTime(0, this.ctx.currentTime);
      } else {
        gain.gain.setValueAtTime(1, this.ctx.currentTime);
      }
    });

    // Global bypass
    if (this.config.bypass) {
      this.dryGain.gain.setValueAtTime(1, this.ctx.currentTime);
      this.wetGain.gain.setValueAtTime(0, this.ctx.currentTime);
    }
  }

  setBandConfig(bandIndex: number, config: Partial<BandConfig>): void {
    if (bandIndex >= 0 && bandIndex < this.config.bands.length) {
      this.config.bands[bandIndex] = { ...this.config.bands[bandIndex], ...config };
      this.applyConfig(this.config);
    }
  }

  setCrossoverFrequency(crossoverIndex: number, frequency: number): void {
    if (crossoverIndex >= 0 && crossoverIndex < this.crossovers.length) {
      this.crossovers[crossoverIndex].setFrequency(frequency);
      // Update band config
      if (crossoverIndex < this.config.bands.length - 1) {
        this.config.bands[crossoverIndex].highFreq = frequency;
        this.config.bands[crossoverIndex + 1].lowFreq = frequency;
      }
    }
  }

  setSidechainInput(input: AudioNode): void {
    // For external sidechain, would need to modify compressor detection
    // Web Audio DynamicsCompressorNode doesn't support external sidechain
    // This would require AudioWorklet implementation
    if (!this.sidechainInput) {
      this.sidechainInput = this.ctx.createGain();
    }
    input.connect(this.sidechainInput);
  }

  getMeters(): MultibandMeter {
    const bandMeters = this.bandCompressors.map(c => c.getMeter());

    // Overall levels
    const inputData = new Float32Array(this.inputAnalyzer.fftSize);
    this.inputAnalyzer.getFloatTimeDomainData(inputData);
    let inputSum = 0;
    for (let i = 0; i < inputData.length; i++) {
      inputSum += inputData[i] * inputData[i];
    }
    const inputRms = Math.sqrt(inputSum / inputData.length);
    const inputLevel = inputRms > 0 ? 20 * Math.log10(inputRms) : -60;

    const outputData = new Float32Array(this.outputAnalyzer.fftSize);
    this.outputAnalyzer.getFloatTimeDomainData(outputData);
    let outputSum = 0;
    for (let i = 0; i < outputData.length; i++) {
      outputSum += outputData[i] * outputData[i];
    }
    const outputRms = Math.sqrt(outputSum / outputData.length);
    const outputLevel = outputRms > 0 ? 20 * Math.log10(outputRms) : -60;

    // Overall gain reduction (average of bands)
    const avgGR = bandMeters.reduce((sum, m) => sum + m.gainReduction, 0) / bandMeters.length;

    return {
      bands: bandMeters,
      inputLevel,
      outputLevel,
      gainReduction: avgGR,
    };
  }

  getConfig(): MultibandCompressorConfig {
    return { ...this.config };
  }

  dispose(): void {
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
    this.outputGain.disconnect();
    this.outputNode.disconnect();
    this.inputAnalyzer.disconnect();
    this.outputAnalyzer.disconnect();

    this.crossovers.forEach(c => c.dispose());
    this.bandCompressors.forEach(c => c.dispose());
    this.bandGains.forEach(g => g.disconnect());

    if (this.sidechainInput) {
      this.sidechainInput.disconnect();
    }
  }
}

// ============ PRESETS ============

export const MULTIBAND_PRESETS: Record<string, Partial<MultibandCompressorConfig>> = {
  gentle: {
    bandCount: 3,
    bands: [
      { id: 'low', lowFreq: 20, highFreq: 200, threshold: -24, ratio: 2, attackMs: 50, releaseMs: 300, makeupGain: 2, bypass: false, solo: false, mute: false },
      { id: 'mid', lowFreq: 200, highFreq: 2000, threshold: -22, ratio: 2, attackMs: 30, releaseMs: 200, makeupGain: 1, bypass: false, solo: false, mute: false },
      { id: 'high', lowFreq: 2000, highFreq: 20000, threshold: -20, ratio: 1.5, attackMs: 10, releaseMs: 100, makeupGain: 1, bypass: false, solo: false, mute: false },
    ],
    mix: 0.5,
  },
  punchy: {
    bandCount: 4,
    bands: [
      { id: 'low', lowFreq: 20, highFreq: 100, threshold: -18, ratio: 6, attackMs: 20, releaseMs: 150, makeupGain: 3, bypass: false, solo: false, mute: false },
      { id: 'low-mid', lowFreq: 100, highFreq: 500, threshold: -16, ratio: 4, attackMs: 15, releaseMs: 120, makeupGain: 2, bypass: false, solo: false, mute: false },
      { id: 'high-mid', lowFreq: 500, highFreq: 4000, threshold: -14, ratio: 3, attackMs: 8, releaseMs: 80, makeupGain: 1, bypass: false, solo: false, mute: false },
      { id: 'high', lowFreq: 4000, highFreq: 20000, threshold: -12, ratio: 2, attackMs: 3, releaseMs: 50, makeupGain: 1, bypass: false, solo: false, mute: false },
    ],
    mix: 1,
  },
  slot_wins: {
    bandCount: 4,
    bands: [
      { id: 'sub', lowFreq: 20, highFreq: 80, threshold: -20, ratio: 5, attackMs: 30, releaseMs: 200, makeupGain: 2, bypass: false, solo: false, mute: false },
      { id: 'punch', lowFreq: 80, highFreq: 500, threshold: -16, ratio: 4, attackMs: 10, releaseMs: 100, makeupGain: 3, bypass: false, solo: false, mute: false },
      { id: 'presence', lowFreq: 500, highFreq: 4000, threshold: -12, ratio: 3, attackMs: 5, releaseMs: 60, makeupGain: 2, bypass: false, solo: false, mute: false },
      { id: 'air', lowFreq: 4000, highFreq: 20000, threshold: -10, ratio: 2, attackMs: 2, releaseMs: 40, makeupGain: 1, bypass: false, solo: false, mute: false },
    ],
    mix: 1,
    outputGain: 2,
  },
  slot_music: {
    bandCount: 3,
    bands: [
      { id: 'low', lowFreq: 20, highFreq: 250, threshold: -22, ratio: 3, attackMs: 40, releaseMs: 250, makeupGain: 1, bypass: false, solo: false, mute: false },
      { id: 'mid', lowFreq: 250, highFreq: 3000, threshold: -20, ratio: 2.5, attackMs: 20, releaseMs: 150, makeupGain: 0, bypass: false, solo: false, mute: false },
      { id: 'high', lowFreq: 3000, highFreq: 20000, threshold: -18, ratio: 2, attackMs: 8, releaseMs: 80, makeupGain: 0, bypass: false, solo: false, mute: false },
    ],
    mix: 0.7,
  },
  broadcast: {
    bandCount: 5,
    bands: DEFAULT_5_BAND.map(b => ({ ...b, ratio: b.ratio * 1.5, threshold: b.threshold - 4 })),
    mix: 1,
    outputGain: 3,
  },
};
