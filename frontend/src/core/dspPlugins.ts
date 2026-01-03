/**
 * DSP Plugins
 *
 * Professional audio effect processors using Web Audio API:
 * - Reverb (convolution-based and algorithmic)
 * - Delay (mono, stereo, ping-pong)
 * - Chorus (modulated delay for thickening)
 * - Phaser (all-pass filter sweep)
 * - Flanger (short modulated delay)
 * - Tremolo (amplitude modulation)
 * - Distortion (waveshaper-based)
 * - Filter (lowpass, highpass, bandpass, notch)
 */

// ============ BASE TYPES ============

export type PluginType =
  | 'reverb'
  | 'delay'
  | 'chorus'
  | 'phaser'
  | 'flanger'
  | 'tremolo'
  | 'distortion'
  | 'filter';

export interface PluginParameter {
  name: string;
  value: number;
  min: number;
  max: number;
  default: number;
  unit?: string;
}

export interface DSPPlugin {
  type: PluginType;
  id: string;
  name: string;
  enabled: boolean;
  wetDry: number; // 0 = dry, 1 = wet
  parameters: Map<string, PluginParameter>;
  inputNode: AudioNode;
  outputNode: AudioNode;
  connect(destination: AudioNode): void;
  disconnect(): void;
  setParameter(name: string, value: number): void;
  getParameter(name: string): number;
  setWetDry(value: number): void;
  setEnabled(enabled: boolean): void;
  dispose(): void;
}

// ============ REVERB ============

export interface ReverbConfig {
  decay: number;        // 0.1 - 10 seconds
  preDelay: number;     // 0 - 100 ms
  wetDry: number;       // 0 - 1
  highCut: number;      // Hz, high frequency damping
  lowCut: number;       // Hz, low frequency cut
}

export const DEFAULT_REVERB_CONFIG: ReverbConfig = {
  decay: 2.0,
  preDelay: 10,
  wetDry: 0.3,
  highCut: 8000,
  lowCut: 200,
};

export class ReverbPlugin implements DSPPlugin {
  type: PluginType = 'reverb';
  id: string;
  name: string = 'Reverb';
  enabled: boolean = true;
  wetDry: number = 0.3;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private ctx: AudioContext;
  private dryGain: GainNode;
  private wetGain: GainNode;
  private convolver: ConvolverNode;
  private preDelayNode: DelayNode;
  private highCutFilter: BiquadFilterNode;
  private lowCutFilter: BiquadFilterNode;
  // impulseBuffer stored in convolver.buffer

  constructor(ctx: AudioContext, id?: string, config: Partial<ReverbConfig> = {}) {
    this.ctx = ctx;
    this.id = id ?? `reverb_${Date.now()}`;

    const cfg = { ...DEFAULT_REVERB_CONFIG, ...config };
    this.wetDry = cfg.wetDry;

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.convolver = ctx.createConvolver();
    this.preDelayNode = ctx.createDelay(0.1);
    this.highCutFilter = ctx.createBiquadFilter();
    this.lowCutFilter = ctx.createBiquadFilter();

    // Configure filters
    this.highCutFilter.type = 'lowpass';
    this.highCutFilter.frequency.value = cfg.highCut;
    this.lowCutFilter.type = 'highpass';
    this.lowCutFilter.frequency.value = cfg.lowCut;

    // Set pre-delay
    this.preDelayNode.delayTime.value = cfg.preDelay / 1000;

    // Wire dry path
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    // Wire wet path
    this.inputNode.connect(this.preDelayNode);
    this.preDelayNode.connect(this.lowCutFilter);
    this.lowCutFilter.connect(this.convolver);
    this.convolver.connect(this.highCutFilter);
    this.highCutFilter.connect(this.wetGain);
    this.wetGain.connect(this.outputNode);

    // Set wet/dry
    this.setWetDry(this.wetDry);

    // Generate impulse response
    this.generateImpulse(cfg.decay);

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: ReverbConfig): void {
    this.parameters.set('decay', {
      name: 'Decay',
      value: cfg.decay,
      min: 0.1,
      max: 10,
      default: 2.0,
      unit: 's',
    });
    this.parameters.set('preDelay', {
      name: 'Pre-Delay',
      value: cfg.preDelay,
      min: 0,
      max: 100,
      default: 10,
      unit: 'ms',
    });
    this.parameters.set('highCut', {
      name: 'High Cut',
      value: cfg.highCut,
      min: 1000,
      max: 20000,
      default: 8000,
      unit: 'Hz',
    });
    this.parameters.set('lowCut', {
      name: 'Low Cut',
      value: cfg.lowCut,
      min: 20,
      max: 1000,
      default: 200,
      unit: 'Hz',
    });
  }

  private generateImpulse(decay: number): void {
    const sampleRate = this.ctx.sampleRate;
    const length = Math.floor(sampleRate * decay);
    const impulse = this.ctx.createBuffer(2, length, sampleRate);

    for (let channel = 0; channel < 2; channel++) {
      const channelData = impulse.getChannelData(channel);
      for (let i = 0; i < length; i++) {
        // Exponential decay with noise
        const envelope = Math.exp(-3 * i / length);
        channelData[i] = (Math.random() * 2 - 1) * envelope;
      }
    }

    this.convolver.buffer = impulse;
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'decay':
        this.generateImpulse(param.value);
        break;
      case 'preDelay':
        this.preDelayNode.delayTime.value = param.value / 1000;
        break;
      case 'highCut':
        this.highCutFilter.frequency.value = param.value;
        break;
      case 'lowCut':
        this.lowCutFilter.frequency.value = param.value;
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(value: number): void {
    this.wetDry = Math.max(0, Math.min(1, value));
    this.dryGain.gain.value = 1 - this.wetDry;
    this.wetGain.gain.value = this.wetDry;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.wetGain.gain.value = this.wetDry;
    } else {
      this.wetGain.gain.value = 0;
    }
  }

  dispose(): void {
    this.disconnect();
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
    this.convolver.disconnect();
    this.preDelayNode.disconnect();
    this.highCutFilter.disconnect();
    this.lowCutFilter.disconnect();
  }
}

// ============ DELAY ============

export type DelayMode = 'mono' | 'stereo' | 'ping-pong';

export interface DelayConfig {
  mode: DelayMode;
  time: number;         // 0 - 2000 ms
  feedback: number;     // 0 - 0.95
  wetDry: number;       // 0 - 1
  highCut: number;      // Hz
  sync: boolean;        // Sync to tempo
  syncDivision: number; // 1/4, 1/8, etc.
}

export const DEFAULT_DELAY_CONFIG: DelayConfig = {
  mode: 'stereo',
  time: 375,
  feedback: 0.4,
  wetDry: 0.3,
  highCut: 6000,
  sync: false,
  syncDivision: 0.25,
};

export class DelayPlugin implements DSPPlugin {
  type: PluginType = 'delay';
  id: string;
  name: string = 'Delay';
  enabled: boolean = true;
  wetDry: number = 0.3;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private mode: DelayMode;
  private dryGain: GainNode;
  private wetGain: GainNode;
  private delayL: DelayNode;
  private delayR: DelayNode;
  private feedbackL: GainNode;
  private feedbackR: GainNode;
  private highCutFilter: BiquadFilterNode;
  private splitter: ChannelSplitterNode;
  private merger: ChannelMergerNode;

  constructor(ctx: AudioContext, id?: string, config: Partial<DelayConfig> = {}) {
    this.id = id ?? `delay_${Date.now()}`;

    const cfg = { ...DEFAULT_DELAY_CONFIG, ...config };
    this.wetDry = cfg.wetDry;
    this.mode = cfg.mode;

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.delayL = ctx.createDelay(2);
    this.delayR = ctx.createDelay(2);
    this.feedbackL = ctx.createGain();
    this.feedbackR = ctx.createGain();
    this.highCutFilter = ctx.createBiquadFilter();
    this.splitter = ctx.createChannelSplitter(2);
    this.merger = ctx.createChannelMerger(2);

    // Configure
    this.highCutFilter.type = 'lowpass';
    this.highCutFilter.frequency.value = cfg.highCut;

    const timeSeconds = cfg.time / 1000;
    this.delayL.delayTime.value = timeSeconds;
    this.delayR.delayTime.value = this.mode === 'ping-pong' ? timeSeconds * 0.75 : timeSeconds;

    this.feedbackL.gain.value = cfg.feedback;
    this.feedbackR.gain.value = cfg.feedback;

    // Wire based on mode
    this.wireMode(cfg.mode);

    // Set wet/dry
    this.setWetDry(this.wetDry);

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: DelayConfig): void {
    this.parameters.set('time', {
      name: 'Time',
      value: cfg.time,
      min: 1,
      max: 2000,
      default: 375,
      unit: 'ms',
    });
    this.parameters.set('feedback', {
      name: 'Feedback',
      value: cfg.feedback,
      min: 0,
      max: 0.95,
      default: 0.4,
      unit: '%',
    });
    this.parameters.set('highCut', {
      name: 'High Cut',
      value: cfg.highCut,
      min: 500,
      max: 20000,
      default: 6000,
      unit: 'Hz',
    });
  }

  private wireMode(mode: DelayMode): void {
    // Clear existing connections
    this.inputNode.disconnect();

    // Dry path
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    switch (mode) {
      case 'mono':
        // Both channels through left delay
        this.inputNode.connect(this.delayL);
        this.delayL.connect(this.highCutFilter);
        this.highCutFilter.connect(this.feedbackL);
        this.feedbackL.connect(this.delayL);
        this.highCutFilter.connect(this.wetGain);
        this.wetGain.connect(this.outputNode);
        break;

      case 'stereo':
        // Split channels
        this.inputNode.connect(this.splitter);
        this.splitter.connect(this.delayL, 0);
        this.splitter.connect(this.delayR, 1);
        this.delayL.connect(this.feedbackL);
        this.delayR.connect(this.feedbackR);
        this.feedbackL.connect(this.delayL);
        this.feedbackR.connect(this.delayR);
        this.delayL.connect(this.highCutFilter);
        this.delayR.connect(this.highCutFilter);
        this.highCutFilter.connect(this.merger, 0, 0);
        this.highCutFilter.connect(this.merger, 0, 1);
        this.merger.connect(this.wetGain);
        this.wetGain.connect(this.outputNode);
        break;

      case 'ping-pong':
        // Cross-feed delays
        this.inputNode.connect(this.delayL);
        this.delayL.connect(this.feedbackL);
        this.feedbackL.connect(this.delayR);
        this.delayR.connect(this.feedbackR);
        this.feedbackR.connect(this.delayL);
        this.delayL.connect(this.merger, 0, 0);
        this.delayR.connect(this.merger, 0, 1);
        this.merger.connect(this.highCutFilter);
        this.highCutFilter.connect(this.wetGain);
        this.wetGain.connect(this.outputNode);
        break;
    }
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'time':
        const timeSeconds = param.value / 1000;
        this.delayL.delayTime.value = timeSeconds;
        this.delayR.delayTime.value = this.mode === 'ping-pong' ? timeSeconds * 0.75 : timeSeconds;
        break;
      case 'feedback':
        this.feedbackL.gain.value = param.value;
        this.feedbackR.gain.value = param.value;
        break;
      case 'highCut':
        this.highCutFilter.frequency.value = param.value;
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(value: number): void {
    this.wetDry = Math.max(0, Math.min(1, value));
    this.dryGain.gain.value = 1 - this.wetDry;
    this.wetGain.gain.value = this.wetDry;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.wetGain.gain.value = this.wetDry;
    } else {
      this.wetGain.gain.value = 0;
    }
  }

  setMode(mode: DelayMode): void {
    this.mode = mode;
    this.wireMode(mode);
  }

  dispose(): void {
    this.disconnect();
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
    this.delayL.disconnect();
    this.delayR.disconnect();
    this.feedbackL.disconnect();
    this.feedbackR.disconnect();
    this.highCutFilter.disconnect();
    this.splitter.disconnect();
    this.merger.disconnect();
  }
}

// ============ CHORUS ============

export interface ChorusConfig {
  rate: number;         // 0.1 - 10 Hz
  depth: number;        // 0 - 30 ms
  wetDry: number;       // 0 - 1
  voices: number;       // 1 - 4
  spread: number;       // 0 - 1 stereo spread
}

export const DEFAULT_CHORUS_CONFIG: ChorusConfig = {
  rate: 1.5,
  depth: 10,
  wetDry: 0.5,
  voices: 2,
  spread: 0.8,
};

export class ChorusPlugin implements DSPPlugin {
  type: PluginType = 'chorus';
  id: string;
  name: string = 'Chorus';
  enabled: boolean = true;
  wetDry: number = 0.5;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private ctx: AudioContext;
  private dryGain: GainNode;
  private wetGain: GainNode;
  private delays: DelayNode[] = [];
  private lfos: OscillatorNode[] = [];
  private lfoGains: GainNode[] = [];
  private voiceGains: GainNode[] = [];
  private merger: ChannelMergerNode;

  constructor(ctx: AudioContext, id?: string, config: Partial<ChorusConfig> = {}) {
    this.ctx = ctx;
    this.id = id ?? `chorus_${Date.now()}`;

    const cfg = { ...DEFAULT_CHORUS_CONFIG, ...config };
    this.wetDry = cfg.wetDry;

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.merger = ctx.createChannelMerger(2);

    // Wire dry path
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    // Create voices
    this.createVoices(cfg);

    // Set wet/dry
    this.setWetDry(this.wetDry);

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: ChorusConfig): void {
    this.parameters.set('rate', {
      name: 'Rate',
      value: cfg.rate,
      min: 0.1,
      max: 10,
      default: 1.5,
      unit: 'Hz',
    });
    this.parameters.set('depth', {
      name: 'Depth',
      value: cfg.depth,
      min: 0,
      max: 30,
      default: 10,
      unit: 'ms',
    });
    this.parameters.set('voices', {
      name: 'Voices',
      value: cfg.voices,
      min: 1,
      max: 4,
      default: 2,
    });
    this.parameters.set('spread', {
      name: 'Spread',
      value: cfg.spread,
      min: 0,
      max: 1,
      default: 0.8,
    });
  }

  private createVoices(cfg: ChorusConfig): void {
    // Clean up existing voices
    this.disposeVoices();

    const baseDelay = 0.02; // 20ms base delay

    for (let i = 0; i < cfg.voices; i++) {
      const delay = this.ctx.createDelay(0.1);
      const lfo = this.ctx.createOscillator();
      const lfoGain = this.ctx.createGain();
      const voiceGain = this.ctx.createGain();

      // Configure delay
      delay.delayTime.value = baseDelay;

      // Configure LFO with phase offset per voice
      lfo.type = 'sine';
      // Slightly vary frequency to create phase offset effect
      const phaseVariation = 1 + (i / cfg.voices) * 0.01;
      lfo.frequency.value = cfg.rate * phaseVariation;

      // LFO depth
      lfoGain.gain.value = cfg.depth / 1000;

      // Voice gain
      voiceGain.gain.value = 1 / cfg.voices;

      // Wire
      lfo.connect(lfoGain);
      lfoGain.connect(delay.delayTime);
      this.inputNode.connect(delay);
      delay.connect(voiceGain);

      // Pan based on spread
      const pan = ((i / (cfg.voices - 1 || 1)) - 0.5) * 2 * cfg.spread;
      const leftGain = Math.cos((pan + 1) * Math.PI / 4);
      const rightGain = Math.sin((pan + 1) * Math.PI / 4);

      const leftVoiceGain = this.ctx.createGain();
      const rightVoiceGain = this.ctx.createGain();
      leftVoiceGain.gain.value = leftGain / cfg.voices;
      rightVoiceGain.gain.value = rightGain / cfg.voices;

      voiceGain.connect(leftVoiceGain);
      voiceGain.connect(rightVoiceGain);
      leftVoiceGain.connect(this.merger, 0, 0);
      rightVoiceGain.connect(this.merger, 0, 1);

      lfo.start();

      this.delays.push(delay);
      this.lfos.push(lfo);
      this.lfoGains.push(lfoGain);
      this.voiceGains.push(voiceGain);
    }

    this.merger.connect(this.wetGain);
    this.wetGain.connect(this.outputNode);
  }

  private disposeVoices(): void {
    this.lfos.forEach(lfo => {
      try { lfo.stop(); } catch (_e) { /* ignore */ }
      lfo.disconnect();
    });
    this.delays.forEach(d => d.disconnect());
    this.lfoGains.forEach(g => g.disconnect());
    this.voiceGains.forEach(g => g.disconnect());

    this.lfos = [];
    this.delays = [];
    this.lfoGains = [];
    this.voiceGains = [];
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'rate':
        this.lfos.forEach(lfo => {
          lfo.frequency.value = param.value;
        });
        break;
      case 'depth':
        this.lfoGains.forEach(gain => {
          gain.gain.value = param.value / 1000;
        });
        break;
      case 'voices':
        // Recreate voices
        this.createVoices({
          rate: this.getParameter('rate'),
          depth: this.getParameter('depth'),
          wetDry: this.wetDry,
          voices: Math.round(param.value),
          spread: this.getParameter('spread'),
        });
        break;
      case 'spread':
        // Recreate for new spread
        this.createVoices({
          rate: this.getParameter('rate'),
          depth: this.getParameter('depth'),
          wetDry: this.wetDry,
          voices: Math.round(this.getParameter('voices')),
          spread: param.value,
        });
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(value: number): void {
    this.wetDry = Math.max(0, Math.min(1, value));
    this.dryGain.gain.value = 1 - this.wetDry;
    this.wetGain.gain.value = this.wetDry;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.wetGain.gain.value = this.wetDry;
    } else {
      this.wetGain.gain.value = 0;
    }
  }

  dispose(): void {
    this.disposeVoices();
    this.disconnect();
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
    this.merger.disconnect();
  }
}

// ============ PHASER ============

export interface PhaserConfig {
  rate: number;         // 0.1 - 10 Hz
  depth: number;        // 0 - 1
  feedback: number;     // 0 - 0.95
  stages: number;       // 2 - 12 (even numbers)
  baseFreq: number;     // Base frequency Hz
  wetDry: number;       // 0 - 1
}

export const DEFAULT_PHASER_CONFIG: PhaserConfig = {
  rate: 0.5,
  depth: 0.7,
  feedback: 0.5,
  stages: 4,
  baseFreq: 1000,
  wetDry: 0.5,
};

export class PhaserPlugin implements DSPPlugin {
  type: PluginType = 'phaser';
  id: string;
  name: string = 'Phaser';
  enabled: boolean = true;
  wetDry: number = 0.5;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private ctx: AudioContext;
  private dryGain: GainNode;
  private wetGain: GainNode;
  private allPassFilters: BiquadFilterNode[] = [];
  private feedbackGain: GainNode;
  private lfo: OscillatorNode;
  private lfoGain: GainNode;
  private stages: number;
  private baseFreq: number;
  private depth: number;

  constructor(ctx: AudioContext, id?: string, config: Partial<PhaserConfig> = {}) {
    this.ctx = ctx;
    this.id = id ?? `phaser_${Date.now()}`;

    const cfg = { ...DEFAULT_PHASER_CONFIG, ...config };
    this.wetDry = cfg.wetDry;
    this.stages = cfg.stages;
    this.baseFreq = cfg.baseFreq;
    this.depth = cfg.depth;

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.feedbackGain = ctx.createGain();
    this.lfo = ctx.createOscillator();
    this.lfoGain = ctx.createGain();

    // Configure LFO
    this.lfo.type = 'sine';
    this.lfo.frequency.value = cfg.rate;

    // Create all-pass filter stages
    this.createStages(cfg.stages);

    // Configure feedback
    this.feedbackGain.gain.value = cfg.feedback;

    // Wire dry path
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    // Wire wet path with all-pass filters
    this.wireWetPath();

    // Set wet/dry
    this.setWetDry(this.wetDry);

    // Start LFO
    this.lfo.start();

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: PhaserConfig): void {
    this.parameters.set('rate', {
      name: 'Rate',
      value: cfg.rate,
      min: 0.1,
      max: 10,
      default: 0.5,
      unit: 'Hz',
    });
    this.parameters.set('depth', {
      name: 'Depth',
      value: cfg.depth,
      min: 0,
      max: 1,
      default: 0.7,
    });
    this.parameters.set('feedback', {
      name: 'Feedback',
      value: cfg.feedback,
      min: 0,
      max: 0.95,
      default: 0.5,
    });
    this.parameters.set('stages', {
      name: 'Stages',
      value: cfg.stages,
      min: 2,
      max: 12,
      default: 4,
    });
    this.parameters.set('baseFreq', {
      name: 'Base Freq',
      value: cfg.baseFreq,
      min: 100,
      max: 5000,
      default: 1000,
      unit: 'Hz',
    });
  }

  private createStages(numStages: number): void {
    // Dispose existing
    this.allPassFilters.forEach(f => f.disconnect());
    this.allPassFilters = [];

    for (let i = 0; i < numStages; i++) {
      const filter = this.ctx.createBiquadFilter();
      filter.type = 'allpass';
      filter.frequency.value = this.baseFreq;
      filter.Q.value = 0.5;
      this.allPassFilters.push(filter);
    }
  }

  private wireWetPath(): void {
    // Connect LFO to all filter frequencies
    this.lfo.connect(this.lfoGain);

    // Connect filters in series
    let prevNode: AudioNode = this.inputNode;
    this.allPassFilters.forEach((filter, i) => {
      prevNode.connect(filter);
      // Modulate frequency
      const freqOffset = this.baseFreq * this.depth * ((i + 1) / this.allPassFilters.length);
      this.lfoGain.gain.value = freqOffset;
      this.lfoGain.connect(filter.frequency);
      prevNode = filter;
    });

    // Output
    prevNode.connect(this.wetGain);
    this.wetGain.connect(this.outputNode);

    // Feedback from last stage to first
    if (this.allPassFilters.length > 0) {
      this.allPassFilters[this.allPassFilters.length - 1].connect(this.feedbackGain);
      this.feedbackGain.connect(this.allPassFilters[0]);
    }
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'rate':
        this.lfo.frequency.value = param.value;
        break;
      case 'depth':
        this.depth = param.value;
        const freqOffset = this.baseFreq * this.depth;
        this.lfoGain.gain.value = freqOffset;
        break;
      case 'feedback':
        this.feedbackGain.gain.value = param.value;
        break;
      case 'stages':
        this.stages = Math.round(param.value);
        this.createStages(this.stages);
        this.wireWetPath();
        break;
      case 'baseFreq':
        this.baseFreq = param.value;
        this.allPassFilters.forEach(f => {
          f.frequency.value = param.value;
        });
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(value: number): void {
    this.wetDry = Math.max(0, Math.min(1, value));
    this.dryGain.gain.value = 1 - this.wetDry;
    this.wetGain.gain.value = this.wetDry;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.wetGain.gain.value = this.wetDry;
    } else {
      this.wetGain.gain.value = 0;
    }
  }

  dispose(): void {
    try { this.lfo.stop(); } catch (_e) { /* ignore */ }
    this.lfo.disconnect();
    this.lfoGain.disconnect();
    this.allPassFilters.forEach(f => f.disconnect());
    this.feedbackGain.disconnect();
    this.disconnect();
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
  }
}

// ============ FLANGER ============

export interface FlangerConfig {
  rate: number;         // 0.1 - 5 Hz
  depth: number;        // 0 - 10 ms
  feedback: number;     // -0.95 - 0.95
  wetDry: number;       // 0 - 1
}

export const DEFAULT_FLANGER_CONFIG: FlangerConfig = {
  rate: 0.3,
  depth: 2,
  feedback: 0.5,
  wetDry: 0.5,
};

export class FlangerPlugin implements DSPPlugin {
  type: PluginType = 'flanger';
  id: string;
  name: string = 'Flanger';
  enabled: boolean = true;
  wetDry: number = 0.5;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private dryGain: GainNode;
  private wetGain: GainNode;
  private delay: DelayNode;
  private feedbackGain: GainNode;
  private lfo: OscillatorNode;
  private lfoGain: GainNode;

  constructor(ctx: AudioContext, id?: string, config: Partial<FlangerConfig> = {}) {
    this.id = id ?? `flanger_${Date.now()}`;

    const cfg = { ...DEFAULT_FLANGER_CONFIG, ...config };
    this.wetDry = cfg.wetDry;

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.delay = ctx.createDelay(0.02);
    this.feedbackGain = ctx.createGain();
    this.lfo = ctx.createOscillator();
    this.lfoGain = ctx.createGain();

    // Configure
    this.delay.delayTime.value = 0.005; // 5ms base
    this.feedbackGain.gain.value = cfg.feedback;
    this.lfo.type = 'sine';
    this.lfo.frequency.value = cfg.rate;
    this.lfoGain.gain.value = cfg.depth / 1000;

    // Wire dry path
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    // Wire wet path
    this.inputNode.connect(this.delay);
    this.delay.connect(this.feedbackGain);
    this.feedbackGain.connect(this.delay);
    this.delay.connect(this.wetGain);
    this.wetGain.connect(this.outputNode);

    // Wire LFO
    this.lfo.connect(this.lfoGain);
    this.lfoGain.connect(this.delay.delayTime);

    // Set wet/dry
    this.setWetDry(this.wetDry);

    // Start LFO
    this.lfo.start();

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: FlangerConfig): void {
    this.parameters.set('rate', {
      name: 'Rate',
      value: cfg.rate,
      min: 0.1,
      max: 5,
      default: 0.3,
      unit: 'Hz',
    });
    this.parameters.set('depth', {
      name: 'Depth',
      value: cfg.depth,
      min: 0,
      max: 10,
      default: 2,
      unit: 'ms',
    });
    this.parameters.set('feedback', {
      name: 'Feedback',
      value: cfg.feedback,
      min: -0.95,
      max: 0.95,
      default: 0.5,
    });
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'rate':
        this.lfo.frequency.value = param.value;
        break;
      case 'depth':
        this.lfoGain.gain.value = param.value / 1000;
        break;
      case 'feedback':
        this.feedbackGain.gain.value = param.value;
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(value: number): void {
    this.wetDry = Math.max(0, Math.min(1, value));
    this.dryGain.gain.value = 1 - this.wetDry;
    this.wetGain.gain.value = this.wetDry;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.wetGain.gain.value = this.wetDry;
    } else {
      this.wetGain.gain.value = 0;
    }
  }

  dispose(): void {
    try { this.lfo.stop(); } catch (_e) { /* ignore */ }
    this.lfo.disconnect();
    this.lfoGain.disconnect();
    this.delay.disconnect();
    this.feedbackGain.disconnect();
    this.disconnect();
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
  }
}

// ============ TREMOLO ============

export interface TremoloConfig {
  rate: number;         // 0.1 - 20 Hz
  depth: number;        // 0 - 1
  shape: 'sine' | 'square' | 'triangle';
}

export const DEFAULT_TREMOLO_CONFIG: TremoloConfig = {
  rate: 5,
  depth: 0.5,
  shape: 'sine',
};

export class TremoloPlugin implements DSPPlugin {
  type: PluginType = 'tremolo';
  id: string;
  name: string = 'Tremolo';
  enabled: boolean = true;
  wetDry: number = 1; // Tremolo is typically 100% wet
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private tremGain: GainNode;
  private lfo: OscillatorNode;
  private lfoGain: GainNode;
  private lfoOffset: ConstantSourceNode;

  constructor(ctx: AudioContext, id?: string, config: Partial<TremoloConfig> = {}) {
    this.id = id ?? `tremolo_${Date.now()}`;

    const cfg = { ...DEFAULT_TREMOLO_CONFIG, ...config };

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.tremGain = ctx.createGain();
    this.lfo = ctx.createOscillator();
    this.lfoGain = ctx.createGain();
    this.lfoOffset = ctx.createConstantSource();

    // Configure LFO
    this.lfo.type = cfg.shape;
    this.lfo.frequency.value = cfg.rate;
    this.lfoGain.gain.value = cfg.depth / 2;
    this.lfoOffset.offset.value = 1 - cfg.depth / 2;

    // Wire
    this.inputNode.connect(this.tremGain);
    this.tremGain.connect(this.outputNode);

    // LFO modulates gain
    this.lfo.connect(this.lfoGain);
    this.lfoGain.connect(this.tremGain.gain);
    this.lfoOffset.connect(this.tremGain.gain);

    // Start
    this.lfo.start();
    this.lfoOffset.start();

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: TremoloConfig): void {
    this.parameters.set('rate', {
      name: 'Rate',
      value: cfg.rate,
      min: 0.1,
      max: 20,
      default: 5,
      unit: 'Hz',
    });
    this.parameters.set('depth', {
      name: 'Depth',
      value: cfg.depth,
      min: 0,
      max: 1,
      default: 0.5,
    });
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'rate':
        this.lfo.frequency.value = param.value;
        break;
      case 'depth':
        this.lfoGain.gain.value = param.value / 2;
        this.lfoOffset.offset.value = 1 - param.value / 2;
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(_value: number): void {
    // Tremolo doesn't use wet/dry in traditional sense
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      const depth = this.getParameter('depth');
      this.lfoGain.gain.value = depth / 2;
      this.lfoOffset.offset.value = 1 - depth / 2;
    } else {
      this.lfoGain.gain.value = 0;
      this.lfoOffset.offset.value = 1;
    }
  }

  setShape(shape: 'sine' | 'square' | 'triangle'): void {
    this.lfo.type = shape;
  }

  dispose(): void {
    try { this.lfo.stop(); } catch (_e) { /* ignore */ }
    try { this.lfoOffset.stop(); } catch (_e) { /* ignore */ }
    this.lfo.disconnect();
    this.lfoGain.disconnect();
    this.lfoOffset.disconnect();
    this.tremGain.disconnect();
    this.disconnect();
    this.inputNode.disconnect();
  }
}

// ============ DISTORTION ============

export type DistortionType = 'soft' | 'hard' | 'tube' | 'fuzz';

export interface DistortionConfig {
  type: DistortionType;
  drive: number;        // 0 - 100
  tone: number;         // Hz, post-distortion filter
  wetDry: number;       // 0 - 1
  outputGain: number;   // dB
}

export const DEFAULT_DISTORTION_CONFIG: DistortionConfig = {
  type: 'soft',
  drive: 50,
  tone: 4000,
  wetDry: 1,
  outputGain: 0,
};

export class DistortionPlugin implements DSPPlugin {
  type: PluginType = 'distortion';
  id: string;
  name: string = 'Distortion';
  enabled: boolean = true;
  wetDry: number = 1;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private dryGain: GainNode;
  private wetGain: GainNode;
  private driveGain: GainNode;
  private waveshaper: WaveShaperNode;
  private toneFilter: BiquadFilterNode;
  private outputGainNode: GainNode;
  private distType: DistortionType;

  constructor(ctx: AudioContext, id?: string, config: Partial<DistortionConfig> = {}) {
    this.id = id ?? `distortion_${Date.now()}`;

    const cfg = { ...DEFAULT_DISTORTION_CONFIG, ...config };
    this.wetDry = cfg.wetDry;
    this.distType = cfg.type;

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.dryGain = ctx.createGain();
    this.wetGain = ctx.createGain();
    this.driveGain = ctx.createGain();
    this.waveshaper = ctx.createWaveShaper();
    this.toneFilter = ctx.createBiquadFilter();
    this.outputGainNode = ctx.createGain();

    // Configure
    this.driveGain.gain.value = 1 + cfg.drive / 10;
    this.toneFilter.type = 'lowpass';
    this.toneFilter.frequency.value = cfg.tone;
    this.outputGainNode.gain.value = Math.pow(10, cfg.outputGain / 20);

    // Generate curve
    this.generateCurve(cfg.type, cfg.drive);

    // Wire dry path
    this.inputNode.connect(this.dryGain);
    this.dryGain.connect(this.outputNode);

    // Wire wet path
    this.inputNode.connect(this.driveGain);
    this.driveGain.connect(this.waveshaper);
    this.waveshaper.connect(this.toneFilter);
    this.toneFilter.connect(this.outputGainNode);
    this.outputGainNode.connect(this.wetGain);
    this.wetGain.connect(this.outputNode);

    // Set wet/dry
    this.setWetDry(this.wetDry);

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: DistortionConfig): void {
    this.parameters.set('drive', {
      name: 'Drive',
      value: cfg.drive,
      min: 0,
      max: 100,
      default: 50,
      unit: '%',
    });
    this.parameters.set('tone', {
      name: 'Tone',
      value: cfg.tone,
      min: 500,
      max: 20000,
      default: 4000,
      unit: 'Hz',
    });
    this.parameters.set('outputGain', {
      name: 'Output',
      value: cfg.outputGain,
      min: -24,
      max: 12,
      default: 0,
      unit: 'dB',
    });
  }

  private generateCurve(type: DistortionType, drive: number): void {
    const samples = 44100;
    const curve = new Float32Array(samples);
    const k = drive * 10;

    for (let i = 0; i < samples; i++) {
      const x = (i * 2) / samples - 1;

      switch (type) {
        case 'soft':
          // Soft clipping (tanh)
          curve[i] = Math.tanh(x * (1 + k / 100));
          break;

        case 'hard':
          // Hard clipping
          const threshold = 1 / (1 + k / 10);
          curve[i] = Math.max(-threshold, Math.min(threshold, x)) / threshold;
          break;

        case 'tube':
          // Tube-style asymmetric
          if (x >= 0) {
            curve[i] = 1 - Math.exp(-x * (1 + k / 50));
          } else {
            curve[i] = -1 + Math.exp(x * (1 + k / 50));
          }
          break;

        case 'fuzz':
          // Aggressive fuzz
          curve[i] = Math.sign(x) * Math.pow(Math.abs(x), 0.3 / (1 + k / 100));
          break;
      }
    }

    this.waveshaper.curve = curve;
    this.waveshaper.oversample = '4x';
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'drive':
        this.driveGain.gain.value = 1 + param.value / 10;
        this.generateCurve(this.distType, param.value);
        break;
      case 'tone':
        this.toneFilter.frequency.value = param.value;
        break;
      case 'outputGain':
        this.outputGainNode.gain.value = Math.pow(10, param.value / 20);
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(value: number): void {
    this.wetDry = Math.max(0, Math.min(1, value));
    this.dryGain.gain.value = 1 - this.wetDry;
    this.wetGain.gain.value = this.wetDry;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.wetGain.gain.value = this.wetDry;
    } else {
      this.wetGain.gain.value = 0;
    }
  }

  setType(type: DistortionType): void {
    this.distType = type;
    this.generateCurve(type, this.getParameter('drive'));
  }

  dispose(): void {
    this.disconnect();
    this.inputNode.disconnect();
    this.dryGain.disconnect();
    this.wetGain.disconnect();
    this.driveGain.disconnect();
    this.waveshaper.disconnect();
    this.toneFilter.disconnect();
    this.outputGainNode.disconnect();
  }
}

// ============ FILTER ============

export type FilterType = 'lowpass' | 'highpass' | 'bandpass' | 'notch' | 'lowshelf' | 'highshelf' | 'peaking';

export interface FilterConfig {
  type: FilterType;
  frequency: number;    // Hz
  Q: number;            // 0.1 - 30
  gain: number;         // dB (for shelf/peaking)
}

export const DEFAULT_FILTER_CONFIG: FilterConfig = {
  type: 'lowpass',
  frequency: 1000,
  Q: 1,
  gain: 0,
};

export class FilterPlugin implements DSPPlugin {
  type: PluginType = 'filter';
  id: string;
  name: string = 'Filter';
  enabled: boolean = true;
  wetDry: number = 1;
  parameters: Map<string, PluginParameter> = new Map();

  inputNode: GainNode;
  outputNode: GainNode;

  private filter: BiquadFilterNode;
  private bypass: GainNode;

  constructor(ctx: AudioContext, id?: string, config: Partial<FilterConfig> = {}) {
    this.id = id ?? `filter_${Date.now()}`;

    const cfg = { ...DEFAULT_FILTER_CONFIG, ...config };

    // Create nodes
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.filter = ctx.createBiquadFilter();
    this.bypass = ctx.createGain();

    // Configure
    this.filter.type = cfg.type;
    this.filter.frequency.value = cfg.frequency;
    this.filter.Q.value = cfg.Q;
    this.filter.gain.value = cfg.gain;

    // Wire
    this.inputNode.connect(this.filter);
    this.filter.connect(this.outputNode);

    // Bypass path (for enabled/disabled)
    this.bypass.gain.value = 0;
    this.inputNode.connect(this.bypass);
    this.bypass.connect(this.outputNode);

    // Initialize parameters
    this.initParameters(cfg);
  }

  private initParameters(cfg: FilterConfig): void {
    this.parameters.set('frequency', {
      name: 'Frequency',
      value: cfg.frequency,
      min: 20,
      max: 20000,
      default: 1000,
      unit: 'Hz',
    });
    this.parameters.set('Q', {
      name: 'Q',
      value: cfg.Q,
      min: 0.1,
      max: 30,
      default: 1,
    });
    this.parameters.set('gain', {
      name: 'Gain',
      value: cfg.gain,
      min: -24,
      max: 24,
      default: 0,
      unit: 'dB',
    });
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  setParameter(name: string, value: number): void {
    const param = this.parameters.get(name);
    if (!param) return;

    param.value = Math.max(param.min, Math.min(param.max, value));

    switch (name) {
      case 'frequency':
        this.filter.frequency.value = param.value;
        break;
      case 'Q':
        this.filter.Q.value = param.value;
        break;
      case 'gain':
        this.filter.gain.value = param.value;
        break;
    }
  }

  getParameter(name: string): number {
    return this.parameters.get(name)?.value ?? 0;
  }

  setWetDry(_value: number): void {
    // Filter doesn't use wet/dry
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled) {
      this.filter.connect(this.outputNode);
      this.bypass.gain.value = 0;
    } else {
      this.filter.disconnect();
      this.bypass.gain.value = 1;
    }
  }

  setFilterType(type: FilterType): void {
    this.filter.type = type;
  }

  getFrequencyResponse(frequencies: Float32Array<ArrayBuffer>): { magnitude: Float32Array<ArrayBuffer>; phase: Float32Array<ArrayBuffer> } {
    const magnitude = new Float32Array(frequencies.length);
    const phase = new Float32Array(frequencies.length);
    this.filter.getFrequencyResponse(frequencies, magnitude, phase);
    return { magnitude, phase };
  }

  dispose(): void {
    this.disconnect();
    this.inputNode.disconnect();
    this.filter.disconnect();
    this.bypass.disconnect();
  }
}

// ============ PLUGIN FACTORY ============

export type PluginConfig =
  | { type: 'reverb'; config?: Partial<ReverbConfig> }
  | { type: 'delay'; config?: Partial<DelayConfig> }
  | { type: 'chorus'; config?: Partial<ChorusConfig> }
  | { type: 'phaser'; config?: Partial<PhaserConfig> }
  | { type: 'flanger'; config?: Partial<FlangerConfig> }
  | { type: 'tremolo'; config?: Partial<TremoloConfig> }
  | { type: 'distortion'; config?: Partial<DistortionConfig> }
  | { type: 'filter'; config?: Partial<FilterConfig> };

export function createPlugin(ctx: AudioContext, pluginConfig: PluginConfig, id?: string): DSPPlugin {
  switch (pluginConfig.type) {
    case 'reverb':
      return new ReverbPlugin(ctx, id, pluginConfig.config);
    case 'delay':
      return new DelayPlugin(ctx, id, pluginConfig.config);
    case 'chorus':
      return new ChorusPlugin(ctx, id, pluginConfig.config);
    case 'phaser':
      return new PhaserPlugin(ctx, id, pluginConfig.config);
    case 'flanger':
      return new FlangerPlugin(ctx, id, pluginConfig.config);
    case 'tremolo':
      return new TremoloPlugin(ctx, id, pluginConfig.config);
    case 'distortion':
      return new DistortionPlugin(ctx, id, pluginConfig.config);
    case 'filter':
      return new FilterPlugin(ctx, id, pluginConfig.config);
  }
}

// ============ PLUGIN CHAIN ============

export class PluginChain {
  private ctx: AudioContext;
  private plugins: DSPPlugin[] = [];
  inputNode: GainNode;
  outputNode: GainNode;

  constructor(ctx: AudioContext) {
    this.ctx = ctx;
    this.inputNode = ctx.createGain();
    this.outputNode = ctx.createGain();
    this.inputNode.connect(this.outputNode);
  }

  addPlugin(pluginConfig: PluginConfig, id?: string): DSPPlugin {
    const plugin = createPlugin(this.ctx, pluginConfig, id);
    this.plugins.push(plugin);
    this.rewire();
    return plugin;
  }

  removePlugin(id: string): boolean {
    const index = this.plugins.findIndex(p => p.id === id);
    if (index === -1) return false;

    const plugin = this.plugins[index];
    plugin.dispose();
    this.plugins.splice(index, 1);
    this.rewire();
    return true;
  }

  movePlugin(id: string, newIndex: number): boolean {
    const currentIndex = this.plugins.findIndex(p => p.id === id);
    if (currentIndex === -1) return false;

    const plugin = this.plugins[currentIndex];
    this.plugins.splice(currentIndex, 1);
    this.plugins.splice(Math.max(0, Math.min(newIndex, this.plugins.length)), 0, plugin);
    this.rewire();
    return true;
  }

  getPlugin(id: string): DSPPlugin | null {
    return this.plugins.find(p => p.id === id) ?? null;
  }

  getPlugins(): DSPPlugin[] {
    return [...this.plugins];
  }

  private rewire(): void {
    // Disconnect all
    this.inputNode.disconnect();
    this.plugins.forEach(p => p.disconnect());

    if (this.plugins.length === 0) {
      this.inputNode.connect(this.outputNode);
      return;
    }

    // Connect in series
    this.inputNode.connect(this.plugins[0].inputNode);

    for (let i = 0; i < this.plugins.length - 1; i++) {
      this.plugins[i].connect(this.plugins[i + 1].inputNode);
    }

    this.plugins[this.plugins.length - 1].connect(this.outputNode);
  }

  connect(destination: AudioNode): void {
    this.outputNode.connect(destination);
  }

  disconnect(): void {
    this.outputNode.disconnect();
  }

  dispose(): void {
    this.plugins.forEach(p => p.dispose());
    this.plugins = [];
    this.inputNode.disconnect();
    this.outputNode.disconnect();
  }
}
