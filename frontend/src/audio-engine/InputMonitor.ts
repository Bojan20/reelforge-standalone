/**
 * ReelForge Input Monitor
 *
 * Real-time input level monitoring without recording.
 * Provides peak, RMS, and spectrum data for visualization.
 *
 * @module audio-engine/InputMonitor
 */

import { AudioContextManager } from '../core/AudioContextManager';
import { AudioDeviceManager } from './AudioDeviceManager';

// ============ Types ============

export interface InputLevels {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
  peakHoldL: number;
  peakHoldR: number;
  clipping: boolean;
}

export interface SpectrumData {
  frequencies: Float32Array;
  magnitudes: Float32Array;
}

export interface InputMonitorState {
  isActive: boolean;
  isMonitoringOutput: boolean;
  inputGain: number;
  levels: InputLevels;
}

type LevelListener = (levels: InputLevels) => void;
type SpectrumListener = (data: SpectrumData) => void;

// ============ Input Monitor Class ============

class InputMonitorClass {
  private state: InputMonitorState = {
    isActive: false,
    isMonitoringOutput: false,
    inputGain: 1.0,
    levels: {
      peakL: 0,
      peakR: 0,
      rmsL: 0,
      rmsR: 0,
      peakHoldL: 0,
      peakHoldR: 0,
      clipping: false,
    },
  };

  // Audio nodes
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private splitterNode: ChannelSplitterNode | null = null;
  private analyzerL: AnalyserNode | null = null;
  private analyzerR: AnalyserNode | null = null;
  private gainNode: GainNode | null = null;
  private monitorGain: GainNode | null = null;

  // Buffers - use explicit ArrayBuffer type for Web Audio API compatibility
  private bufferL: Float32Array<ArrayBuffer> | null = null;
  private bufferR: Float32Array<ArrayBuffer> | null = null;
  private fftBuffer: Float32Array<ArrayBuffer> | null = null;

  // Peak hold
  private peakHoldL = 0;
  private peakHoldR = 0;
  private peakHoldDecay = 0.995;
  private peakHoldTime = 0;
  private peakHoldDuration = 1500; // ms

  // Animation
  private animationFrame: number | null = null;

  // Listeners
  private levelListeners = new Set<LevelListener>();
  private spectrumListeners = new Set<SpectrumListener>();

  /**
   * Start monitoring input.
   */
  async start(): Promise<void> {
    if (this.state.isActive) return;

    // Get or open input stream
    let stream = AudioDeviceManager.getInputStream();
    if (!stream) {
      stream = await AudioDeviceManager.openInputStream();
    }

    const ctx = AudioContextManager.getContext();
    await AudioContextManager.resume();

    // Create nodes
    this.sourceNode = ctx.createMediaStreamSource(stream);

    this.gainNode = ctx.createGain();
    this.gainNode.gain.value = this.state.inputGain;

    this.splitterNode = ctx.createChannelSplitter(2);

    this.analyzerL = ctx.createAnalyser();
    this.analyzerL.fftSize = 2048;
    this.analyzerL.smoothingTimeConstant = 0.5;

    this.analyzerR = ctx.createAnalyser();
    this.analyzerR.fftSize = 2048;
    this.analyzerR.smoothingTimeConstant = 0.5;

    // Allocate buffers
    this.bufferL = new Float32Array(this.analyzerL.fftSize);
    this.bufferR = new Float32Array(this.analyzerR.fftSize);
    this.fftBuffer = new Float32Array(this.analyzerL.frequencyBinCount);

    // Connect graph
    // source → gain → splitter → analyzers
    this.sourceNode.connect(this.gainNode);
    this.gainNode.connect(this.splitterNode);
    this.splitterNode.connect(this.analyzerL, 0);
    this.splitterNode.connect(this.analyzerR, 1);

    this.state.isActive = true;
    this.startMeterLoop();
  }

  /**
   * Stop monitoring.
   */
  stop(): void {
    if (!this.state.isActive) return;

    this.stopMeterLoop();

    // Disconnect nodes
    this.monitorGain?.disconnect();
    this.analyzerL?.disconnect();
    this.analyzerR?.disconnect();
    this.splitterNode?.disconnect();
    this.gainNode?.disconnect();
    this.sourceNode?.disconnect();

    this.sourceNode = null;
    this.splitterNode = null;
    this.analyzerL = null;
    this.analyzerR = null;
    this.gainNode = null;
    this.monitorGain = null;

    this.state.isActive = false;
    this.state.isMonitoringOutput = false;
    this.state.levels = {
      peakL: 0,
      peakR: 0,
      rmsL: 0,
      rmsR: 0,
      peakHoldL: 0,
      peakHoldR: 0,
      clipping: false,
    };
  }

  /**
   * Enable/disable output monitoring (hear input through speakers).
   */
  setMonitorOutput(enabled: boolean): void {
    if (!this.state.isActive) return;

    const ctx = AudioContextManager.getContext();

    if (enabled && !this.monitorGain) {
      this.monitorGain = ctx.createGain();
      this.monitorGain.gain.value = 1.0;
      this.gainNode?.connect(this.monitorGain);
      this.monitorGain.connect(ctx.destination);
    } else if (!enabled && this.monitorGain) {
      this.monitorGain.disconnect();
      this.gainNode?.disconnect(this.monitorGain);
      this.monitorGain = null;
    }

    this.state.isMonitoringOutput = enabled;
  }

  /**
   * Set input gain (0-2).
   */
  setInputGain(value: number): void {
    const gain = Math.max(0, Math.min(2, value));
    this.state.inputGain = gain;
    if (this.gainNode) {
      this.gainNode.gain.value = gain;
    }
  }

  /**
   * Set monitor output gain (0-2).
   */
  setMonitorGain(value: number): void {
    if (this.monitorGain) {
      this.monitorGain.gain.value = Math.max(0, Math.min(2, value));
    }
  }

  /**
   * Reset peak hold meters.
   */
  resetPeakHold(): void {
    this.peakHoldL = 0;
    this.peakHoldR = 0;
    this.peakHoldTime = performance.now();
  }

  /**
   * Start metering loop.
   */
  private startMeterLoop(): void {
    const updateMeters = () => {
      if (!this.state.isActive || !this.analyzerL || !this.analyzerR) return;

      // Get time domain data
      this.analyzerL.getFloatTimeDomainData(this.bufferL!);
      this.analyzerR.getFloatTimeDomainData(this.bufferR!);

      // Calculate levels
      const levelsL = this.calculateLevels(this.bufferL!);
      const levelsR = this.calculateLevels(this.bufferR!);

      // Update peak hold
      const now = performance.now();
      if (levelsL.peak > this.peakHoldL) {
        this.peakHoldL = levelsL.peak;
        this.peakHoldTime = now;
      } else if (now - this.peakHoldTime > this.peakHoldDuration) {
        this.peakHoldL *= this.peakHoldDecay;
      }

      if (levelsR.peak > this.peakHoldR) {
        this.peakHoldR = levelsR.peak;
        this.peakHoldTime = now;
      } else if (now - this.peakHoldTime > this.peakHoldDuration) {
        this.peakHoldR *= this.peakHoldDecay;
      }

      // Check clipping
      const clipping = levelsL.peak >= 0.99 || levelsR.peak >= 0.99;

      const levels: InputLevels = {
        peakL: levelsL.peak,
        peakR: levelsR.peak,
        rmsL: levelsL.rms,
        rmsR: levelsR.rms,
        peakHoldL: this.peakHoldL,
        peakHoldR: this.peakHoldR,
        clipping,
      };

      this.state.levels = levels;

      // Notify level listeners
      this.levelListeners.forEach(fn => fn(levels));

      // Notify spectrum listeners if any
      if (this.spectrumListeners.size > 0) {
        this.analyzerL.getFloatFrequencyData(this.fftBuffer!);
        const spectrumData: SpectrumData = {
          frequencies: new Float32Array(this.fftBuffer!.length),
          magnitudes: new Float32Array(this.fftBuffer!),
        };

        // Calculate frequency values
        const nyquist = AudioContextManager.getSampleRate() / 2;
        for (let i = 0; i < spectrumData.frequencies.length; i++) {
          spectrumData.frequencies[i] = (i / spectrumData.frequencies.length) * nyquist;
        }

        this.spectrumListeners.forEach(fn => fn(spectrumData));
      }

      this.animationFrame = requestAnimationFrame(updateMeters);
    };

    updateMeters();
  }

  /**
   * Stop metering loop.
   */
  private stopMeterLoop(): void {
    if (this.animationFrame !== null) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  }

  /**
   * Calculate peak and RMS from buffer.
   */
  private calculateLevels(buffer: Float32Array): { peak: number; rms: number } {
    let peak = 0;
    let sumSquares = 0;

    for (let i = 0; i < buffer.length; i++) {
      const sample = Math.abs(buffer[i]);
      if (sample > peak) peak = sample;
      sumSquares += sample * sample;
    }

    const rms = Math.sqrt(sumSquares / buffer.length);
    return { peak, rms };
  }

  /**
   * Get current state.
   */
  getState(): Readonly<InputMonitorState> {
    return { ...this.state };
  }

  /**
   * Subscribe to level updates.
   */
  onLevelChange(listener: LevelListener): () => void {
    this.levelListeners.add(listener);
    return () => this.levelListeners.delete(listener);
  }

  /**
   * Subscribe to spectrum updates.
   */
  onSpectrumChange(listener: SpectrumListener): () => void {
    this.spectrumListeners.add(listener);
    return () => this.spectrumListeners.delete(listener);
  }

  /**
   * Check if active.
   */
  isActive(): boolean {
    return this.state.isActive;
  }

  /**
   * Dispose and cleanup.
   */
  dispose(): void {
    this.stop();
    this.levelListeners.clear();
    this.spectrumListeners.clear();
  }
}

// Singleton instance
export const InputMonitor = new InputMonitorClass();
