/**
 * ReelForge Audio Engine
 *
 * Core audio processing engine using Web Audio API.
 * Manages:
 * - Audio context lifecycle
 * - Channel routing and mixing
 * - Real-time metering
 * - Transport (play, stop, seek)
 * - Master output
 *
 * @module engine/AudioEngine
 */

// ============ Types ============

export interface ChannelConfig {
  id: string;
  name: string;
  volume: number; // dB
  pan: number; // -1 to 1
  muted: boolean;
  solo: boolean;
}

export interface ChannelNode {
  id: string;
  input: GainNode;
  gainNode: GainNode;
  panNode: StereoPannerNode;
  analyserL: AnalyserNode;
  analyserR: AnalyserNode;
  splitter: ChannelSplitterNode;
  merger: ChannelMergerNode;
  muted: boolean;
  solo: boolean;
  sourceNode?: AudioBufferSourceNode;
}

export interface MeterData {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
}

export interface EngineState {
  isPlaying: boolean;
  currentTime: number;
  sampleRate: number;
  latency: number;
}

export type EngineEventType =
  | 'statechange'
  | 'play'
  | 'pause'
  | 'stop'
  | 'seek'
  | 'meter'
  | 'channelchange';

export interface EngineEvent {
  type: EngineEventType;
  data?: unknown;
}

type EngineEventCallback = (event: EngineEvent) => void;

// ============ Constants ============

const DEFAULT_SAMPLE_RATE = 48000;
const METER_FFT_SIZE = 2048;
const METER_SMOOTHING = 0.8;

// ============ AudioEngine Class ============

export class AudioEngine {
  private context: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private masterAnalyserL: AnalyserNode | null = null;
  private masterAnalyserR: AnalyserNode | null = null;
  private masterSplitter: ChannelSplitterNode | null = null;
  private channels: Map<string, ChannelNode> = new Map();
  private listeners: Map<EngineEventType, Set<EngineEventCallback>> = new Map();
  private meterInterval: number | null = null;
  private _isPlaying = false;
  private _startTime = 0;
  private _pauseTime = 0;

  // ============ Lifecycle ============

  /**
   * Initialize the audio engine.
   */
  async initialize(): Promise<void> {
    if (this.context) return;

    this.context = new AudioContext({
      sampleRate: DEFAULT_SAMPLE_RATE,
      latencyHint: 'interactive',
    });

    // Create master chain
    this.masterGain = this.context.createGain();
    this.masterSplitter = this.context.createChannelSplitter(2);
    this.masterAnalyserL = this.context.createAnalyser();
    this.masterAnalyserR = this.context.createAnalyser();

    // Configure analysers
    this.masterAnalyserL.fftSize = METER_FFT_SIZE;
    this.masterAnalyserL.smoothingTimeConstant = METER_SMOOTHING;
    this.masterAnalyserR.fftSize = METER_FFT_SIZE;
    this.masterAnalyserR.smoothingTimeConstant = METER_SMOOTHING;

    // Connect master chain
    this.masterGain.connect(this.masterSplitter);
    this.masterSplitter.connect(this.masterAnalyserL, 0);
    this.masterSplitter.connect(this.masterAnalyserR, 1);
    this.masterGain.connect(this.context.destination);

    // Start meter updates
    this.startMeterUpdates();

    this.emit({ type: 'statechange' });
  }

  /**
   * Dispose of the audio engine.
   */
  async dispose(): Promise<void> {
    this.stopMeterUpdates();

    // Disconnect all channels
    for (const channel of this.channels.values()) {
      this.disconnectChannel(channel);
    }
    this.channels.clear();

    // Close context
    if (this.context) {
      await this.context.close();
      this.context = null;
    }

    this.masterGain = null;
    this.masterAnalyserL = null;
    this.masterAnalyserR = null;
    this.masterSplitter = null;
  }

  /**
   * Resume audio context (required after user interaction).
   */
  async resume(): Promise<void> {
    if (this.context?.state === 'suspended') {
      await this.context.resume();
    }
  }

  /**
   * Suspend audio context.
   */
  async suspend(): Promise<void> {
    if (this.context?.state === 'running') {
      await this.context.suspend();
    }
  }

  // ============ Channel Management ============

  /**
   * Create a new channel.
   */
  createChannel(config: ChannelConfig): ChannelNode | null {
    if (!this.context || !this.masterGain) return null;
    if (this.channels.has(config.id)) {
      return this.channels.get(config.id)!;
    }

    // Create nodes
    const input = this.context.createGain();
    const gainNode = this.context.createGain();
    const panNode = this.context.createStereoPanner();
    const splitter = this.context.createChannelSplitter(2);
    const merger = this.context.createChannelMerger(2);
    const analyserL = this.context.createAnalyser();
    const analyserR = this.context.createAnalyser();

    // Configure analysers
    analyserL.fftSize = METER_FFT_SIZE;
    analyserL.smoothingTimeConstant = METER_SMOOTHING;
    analyserR.fftSize = METER_FFT_SIZE;
    analyserR.smoothingTimeConstant = METER_SMOOTHING;

    // Connect chain: input -> gain -> pan -> splitter -> analysers
    //                                    -> merger -> master
    input.connect(gainNode);
    gainNode.connect(panNode);
    panNode.connect(splitter);
    splitter.connect(analyserL, 0);
    splitter.connect(analyserR, 1);
    splitter.connect(merger, 0, 0);
    splitter.connect(merger, 1, 1);
    merger.connect(this.masterGain);

    // Apply initial settings
    gainNode.gain.value = this.dbToLinear(config.volume);
    panNode.pan.value = config.pan;

    const channel: ChannelNode = {
      id: config.id,
      input,
      gainNode,
      panNode,
      analyserL,
      analyserR,
      splitter,
      merger,
      muted: config.muted,
      solo: config.solo,
    };

    // Apply mute
    if (config.muted) {
      gainNode.gain.value = 0;
    }

    this.channels.set(config.id, channel);
    this.updateSoloState();
    this.emit({ type: 'channelchange', data: { id: config.id } });

    return channel;
  }

  /**
   * Remove a channel.
   */
  removeChannel(id: string): void {
    const channel = this.channels.get(id);
    if (!channel) return;

    this.disconnectChannel(channel);
    this.channels.delete(id);
    this.updateSoloState();
    this.emit({ type: 'channelchange', data: { id } });
  }

  /**
   * Get channel by ID.
   */
  getChannel(id: string): ChannelNode | undefined {
    return this.channels.get(id);
  }

  /**
   * Set channel volume.
   */
  setChannelVolume(id: string, volumeDb: number): void {
    const channel = this.channels.get(id);
    if (!channel) return;

    const linear = channel.muted ? 0 : this.dbToLinear(volumeDb);
    channel.gainNode.gain.setTargetAtTime(
      linear,
      this.context?.currentTime || 0,
      0.01
    );
  }

  /**
   * Set channel pan.
   */
  setChannelPan(id: string, pan: number): void {
    const channel = this.channels.get(id);
    if (!channel) return;

    channel.panNode.pan.setTargetAtTime(
      Math.max(-1, Math.min(1, pan)),
      this.context?.currentTime || 0,
      0.01
    );
  }

  /**
   * Set channel mute state.
   */
  setChannelMute(id: string, muted: boolean): void {
    const channel = this.channels.get(id);
    if (!channel) return;

    channel.muted = muted;
    this.updateSoloState();
  }

  /**
   * Set channel solo state.
   */
  setChannelSolo(id: string, solo: boolean): void {
    const channel = this.channels.get(id);
    if (!channel) return;

    channel.solo = solo;
    this.updateSoloState();
  }

  /**
   * Update solo/mute logic for all channels.
   */
  private updateSoloState(): void {
    const hasSolo = Array.from(this.channels.values()).some((ch) => ch.solo);

    for (const channel of this.channels.values()) {
      let shouldPlay = true;

      if (channel.muted) {
        shouldPlay = false;
      } else if (hasSolo && !channel.solo) {
        shouldPlay = false;
      }

      const targetGain = shouldPlay ? 1 : 0;
      channel.gainNode.gain.setTargetAtTime(
        targetGain,
        this.context?.currentTime || 0,
        0.02
      );
    }
  }

  /**
   * Disconnect channel nodes.
   */
  private disconnectChannel(channel: ChannelNode): void {
    if (channel.sourceNode) {
      channel.sourceNode.stop();
      channel.sourceNode.disconnect();
    }
    channel.input.disconnect();
    channel.gainNode.disconnect();
    channel.panNode.disconnect();
    channel.splitter.disconnect();
    channel.merger.disconnect();
    channel.analyserL.disconnect();
    channel.analyserR.disconnect();
  }

  // ============ Master Controls ============

  /**
   * Set master volume.
   */
  setMasterVolume(volumeDb: number): void {
    if (!this.masterGain || !this.context) return;

    const linear = this.dbToLinear(volumeDb);
    this.masterGain.gain.setTargetAtTime(
      linear,
      this.context.currentTime,
      0.01
    );
  }

  // ============ Playback ============

  /**
   * Load audio buffer into channel.
   */
  loadBufferToChannel(id: string, buffer: AudioBuffer): void {
    const channel = this.channels.get(id);
    if (!channel || !this.context) return;

    // Stop existing source
    if (channel.sourceNode) {
      channel.sourceNode.stop();
      channel.sourceNode.disconnect();
    }

    // Create new source
    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(channel.input);
    channel.sourceNode = source;
  }

  /**
   * Play from current position.
   */
  play(): void {
    if (this._isPlaying || !this.context) return;

    this._isPlaying = true;
    this._startTime = this.context.currentTime - this._pauseTime;

    // Start all channel sources
    for (const channel of this.channels.values()) {
      if (channel.sourceNode && channel.sourceNode.buffer) {
        try {
          channel.sourceNode.start(0, this._pauseTime);
        } catch {
          // Source already started, recreate
          const buffer = channel.sourceNode.buffer;
          this.loadBufferToChannel(channel.id, buffer);
          channel.sourceNode?.start(0, this._pauseTime);
        }
      }
    }

    this.emit({ type: 'play' });
    this.emit({ type: 'statechange' });
  }

  /**
   * Pause playback.
   */
  pause(): void {
    if (!this._isPlaying || !this.context) return;

    this._isPlaying = false;
    this._pauseTime = this.context.currentTime - this._startTime;

    // Stop all sources
    for (const channel of this.channels.values()) {
      if (channel.sourceNode) {
        try {
          channel.sourceNode.stop();
        } catch {
          // Already stopped
        }
      }
    }

    this.emit({ type: 'pause' });
    this.emit({ type: 'statechange' });
  }

  /**
   * Stop and reset to beginning.
   */
  stop(): void {
    this.pause();
    this._pauseTime = 0;

    this.emit({ type: 'stop' });
    this.emit({ type: 'statechange' });
  }

  /**
   * Seek to position.
   */
  seek(time: number): void {
    const wasPlaying = this._isPlaying;
    if (wasPlaying) {
      this.pause();
    }

    this._pauseTime = Math.max(0, time);

    if (wasPlaying) {
      this.play();
    }

    this.emit({ type: 'seek', data: { time } });
  }

  // ============ Metering ============

  /**
   * Get meter data for a channel.
   */
  getChannelMeter(id: string): MeterData | null {
    const channel = this.channels.get(id);
    if (!channel) return null;

    return {
      peakL: this.getAnalyserPeak(channel.analyserL),
      peakR: this.getAnalyserPeak(channel.analyserR),
      rmsL: this.getAnalyserRMS(channel.analyserL),
      rmsR: this.getAnalyserRMS(channel.analyserR),
    };
  }

  /**
   * Get master meter data.
   */
  getMasterMeter(): MeterData | null {
    if (!this.masterAnalyserL || !this.masterAnalyserR) return null;

    return {
      peakL: this.getAnalyserPeak(this.masterAnalyserL),
      peakR: this.getAnalyserPeak(this.masterAnalyserR),
      rmsL: this.getAnalyserRMS(this.masterAnalyserL),
      rmsR: this.getAnalyserRMS(this.masterAnalyserR),
    };
  }

  /**
   * Get peak level from analyser.
   */
  private getAnalyserPeak(analyser: AnalyserNode): number {
    const data = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(data);

    let peak = 0;
    for (let i = 0; i < data.length; i++) {
      const abs = Math.abs(data[i]);
      if (abs > peak) peak = abs;
    }

    return peak;
  }

  /**
   * Get RMS level from analyser.
   */
  private getAnalyserRMS(analyser: AnalyserNode): number {
    const data = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(data);

    let sum = 0;
    for (let i = 0; i < data.length; i++) {
      sum += data[i] * data[i];
    }

    return Math.sqrt(sum / data.length);
  }

  /**
   * Start meter update loop.
   */
  private startMeterUpdates(): void {
    if (this.meterInterval) return;

    const updateMeters = () => {
      const meters: Record<string, MeterData> = {};

      for (const [id, channel] of this.channels) {
        meters[id] = {
          peakL: this.getAnalyserPeak(channel.analyserL),
          peakR: this.getAnalyserPeak(channel.analyserR),
          rmsL: this.getAnalyserRMS(channel.analyserL),
          rmsR: this.getAnalyserRMS(channel.analyserR),
        };
      }

      const master = this.getMasterMeter();
      if (master) {
        meters['master'] = master;
      }

      this.emit({ type: 'meter', data: meters });

      this.meterInterval = requestAnimationFrame(updateMeters);
    };

    this.meterInterval = requestAnimationFrame(updateMeters);
  }

  /**
   * Stop meter update loop.
   */
  private stopMeterUpdates(): void {
    if (this.meterInterval) {
      cancelAnimationFrame(this.meterInterval);
      this.meterInterval = null;
    }
  }

  // ============ Events ============

  /**
   * Subscribe to engine events.
   */
  on(type: EngineEventType, callback: EngineEventCallback): () => void {
    if (!this.listeners.has(type)) {
      this.listeners.set(type, new Set());
    }
    this.listeners.get(type)!.add(callback);

    return () => {
      this.listeners.get(type)?.delete(callback);
    };
  }

  /**
   * Emit an event.
   */
  private emit(event: EngineEvent): void {
    const callbacks = this.listeners.get(event.type);
    if (callbacks) {
      for (const callback of callbacks) {
        callback(event);
      }
    }
  }

  // ============ Utilities ============

  /**
   * Convert dB to linear gain.
   */
  private dbToLinear(db: number): number {
    if (db <= -60) return 0;
    return Math.pow(10, db / 20);
  }

  /**
   * Convert linear gain to dB.
   */
  linearToDb(linear: number): number {
    if (linear <= 0) return -Infinity;
    return 20 * Math.log10(linear);
  }

  // ============ Getters ============

  get isPlaying(): boolean {
    return this._isPlaying;
  }

  get currentTime(): number {
    if (!this.context) return 0;
    if (this._isPlaying) {
      return this.context.currentTime - this._startTime;
    }
    return this._pauseTime;
  }

  get sampleRate(): number {
    return this.context?.sampleRate || DEFAULT_SAMPLE_RATE;
  }

  get state(): EngineState {
    return {
      isPlaying: this._isPlaying,
      currentTime: this.currentTime,
      sampleRate: this.sampleRate,
      latency: this.context?.baseLatency || 0,
    };
  }

  get isInitialized(): boolean {
    return this.context !== null;
  }
}

// ============ Singleton Instance ============

let engineInstance: AudioEngine | null = null;

export function getAudioEngine(): AudioEngine {
  if (!engineInstance) {
    engineInstance = new AudioEngine();
  }
  return engineInstance;
}

export default AudioEngine;
