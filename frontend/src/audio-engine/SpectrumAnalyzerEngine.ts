/**
 * ReelForge Spectrum Analyzer Engine
 *
 * Real-time FFT spectrum analysis with multiple display modes.
 * Connects to any audio source node.
 *
 * @module audio-engine/SpectrumAnalyzerEngine
 */

import { AudioContextManager } from '../core/AudioContextManager';

// ============ Types ============

export type SpectrumScale = 'linear' | 'logarithmic';
export type SpectrumMode = 'bars' | 'line' | 'filled';
export type WindowFunction = 'rectangular' | 'hann' | 'hamming' | 'blackman';

export interface SpectrumConfig {
  fftSize: 256 | 512 | 1024 | 2048 | 4096 | 8192;
  smoothingTimeConstant: number; // 0-1
  minDecibels: number; // e.g., -100
  maxDecibels: number; // e.g., 0
  frequencyScale: SpectrumScale;
  minFrequency: number; // Hz
  maxFrequency: number; // Hz
}

export interface SpectrumBand {
  frequency: number; // Center frequency
  magnitude: number; // 0-1 normalized
  decibels: number;  // Raw dB value
}

export interface SpectrumFrame {
  timestamp: number;
  bands: SpectrumBand[];
  peakFrequency: number;
  peakMagnitude: number;
  averageMagnitude: number;
}

type FrameListener = (frame: SpectrumFrame) => void;

// ============ Default Config ============

const DEFAULT_CONFIG: SpectrumConfig = {
  fftSize: 2048,
  smoothingTimeConstant: 0.8,
  minDecibels: -90,
  maxDecibels: -10,
  frequencyScale: 'logarithmic',
  minFrequency: 20,
  maxFrequency: 20000,
};

// ============ Spectrum Analyzer Engine ============

export class SpectrumAnalyzerEngine {
  private config: SpectrumConfig;
  private analyzerNode: AnalyserNode | null = null;
  private frequencyData: Float32Array<ArrayBuffer> | null = null;
  private bands: SpectrumBand[] = [];

  private isRunning = false;
  private animationFrame: number | null = null;
  private listeners = new Set<FrameListener>();

  constructor(config: Partial<SpectrumConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * Create and configure the analyzer node.
   */
  createAnalyzerNode(): AnalyserNode {
    const ctx = AudioContextManager.getContext();

    this.analyzerNode = ctx.createAnalyser();
    this.analyzerNode.fftSize = this.config.fftSize;
    this.analyzerNode.smoothingTimeConstant = this.config.smoothingTimeConstant;
    this.analyzerNode.minDecibels = this.config.minDecibels;
    this.analyzerNode.maxDecibels = this.config.maxDecibels;

    this.frequencyData = new Float32Array(this.analyzerNode.frequencyBinCount);
    this.initBands();

    return this.analyzerNode;
  }

  /**
   * Connect to an existing audio source.
   */
  connectSource(sourceNode: AudioNode): void {
    if (!this.analyzerNode) {
      this.createAnalyzerNode();
    }
    sourceNode.connect(this.analyzerNode!);
  }

  /**
   * Disconnect from source.
   */
  disconnectSource(sourceNode: AudioNode): void {
    if (this.analyzerNode) {
      try {
        sourceNode.disconnect(this.analyzerNode);
      } catch {
        // Already disconnected
      }
    }
  }

  /**
   * Initialize frequency bands based on config.
   */
  private initBands(): void {
    const sampleRate = AudioContextManager.getSampleRate();
    const binCount = this.analyzerNode!.frequencyBinCount;
    const binFrequency = sampleRate / this.config.fftSize;

    this.bands = [];

    if (this.config.frequencyScale === 'logarithmic') {
      // Logarithmic bands (octave-based)
      const numBands = 64;
      const logMin = Math.log10(this.config.minFrequency);
      const logMax = Math.log10(this.config.maxFrequency);
      const logStep = (logMax - logMin) / numBands;

      for (let i = 0; i < numBands; i++) {
        const freq = Math.pow(10, logMin + (i + 0.5) * logStep);
        this.bands.push({
          frequency: freq,
          magnitude: 0,
          decibels: this.config.minDecibels,
        });
      }
    } else {
      // Linear bands
      for (let i = 0; i < binCount; i++) {
        const freq = i * binFrequency;
        if (freq >= this.config.minFrequency && freq <= this.config.maxFrequency) {
          this.bands.push({
            frequency: freq,
            magnitude: 0,
            decibels: this.config.minDecibels,
          });
        }
      }
    }
  }

  /**
   * Start analysis loop.
   */
  start(): void {
    if (this.isRunning || !this.analyzerNode) return;
    this.isRunning = true;
    this.analyze();
  }

  /**
   * Stop analysis loop.
   */
  stop(): void {
    this.isRunning = false;
    if (this.animationFrame !== null) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  }

  /**
   * Main analysis loop.
   */
  private analyze = (): void => {
    if (!this.isRunning || !this.analyzerNode || !this.frequencyData) return;

    // Get frequency data
    this.analyzerNode.getFloatFrequencyData(this.frequencyData);

    const sampleRate = AudioContextManager.getSampleRate();
    const binFrequency = sampleRate / this.config.fftSize;

    let peakMagnitude = 0;
    let peakFrequency = 0;
    let sumMagnitude = 0;

    // Update bands
    for (const band of this.bands) {
      // Find the FFT bin for this frequency
      const binIndex = Math.round(band.frequency / binFrequency);
      const clampedIndex = Math.max(0, Math.min(binIndex, this.frequencyData.length - 1));

      // Get dB value
      const db = this.frequencyData[clampedIndex];
      band.decibels = db;

      // Normalize to 0-1
      const normalized = (db - this.config.minDecibels) /
        (this.config.maxDecibels - this.config.minDecibels);
      band.magnitude = Math.max(0, Math.min(1, normalized));

      // Track peak
      if (band.magnitude > peakMagnitude) {
        peakMagnitude = band.magnitude;
        peakFrequency = band.frequency;
      }

      sumMagnitude += band.magnitude;
    }

    // Create frame
    const frame: SpectrumFrame = {
      timestamp: performance.now(),
      bands: [...this.bands],
      peakFrequency,
      peakMagnitude,
      averageMagnitude: sumMagnitude / this.bands.length,
    };

    // Notify listeners
    this.listeners.forEach(fn => fn(frame));

    // Continue loop
    this.animationFrame = requestAnimationFrame(this.analyze);
  };

  /**
   * Get current bands (snapshot).
   */
  getBands(): SpectrumBand[] {
    return [...this.bands];
  }

  /**
   * Update config.
   */
  setConfig(config: Partial<SpectrumConfig>): void {
    this.config = { ...this.config, ...config };

    if (this.analyzerNode) {
      if (config.fftSize !== undefined) {
        this.analyzerNode.fftSize = config.fftSize;
        this.frequencyData = new Float32Array(this.analyzerNode.frequencyBinCount);
        this.initBands();
      }
      if (config.smoothingTimeConstant !== undefined) {
        this.analyzerNode.smoothingTimeConstant = config.smoothingTimeConstant;
      }
      if (config.minDecibels !== undefined) {
        this.analyzerNode.minDecibels = config.minDecibels;
      }
      if (config.maxDecibels !== undefined) {
        this.analyzerNode.maxDecibels = config.maxDecibels;
      }
      if (config.frequencyScale !== undefined || config.minFrequency !== undefined || config.maxFrequency !== undefined) {
        this.initBands();
      }
    }
  }

  /**
   * Subscribe to frame updates.
   */
  onFrame(listener: FrameListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Get raw frequency data.
   */
  getRawData(): Float32Array | null {
    return this.frequencyData ? new Float32Array(this.frequencyData) : null;
  }

  /**
   * Get analyzer node for external connection.
   */
  getAnalyzerNode(): AnalyserNode | null {
    return this.analyzerNode;
  }

  /**
   * Dispose resources.
   */
  dispose(): void {
    this.stop();
    this.analyzerNode?.disconnect();
    this.analyzerNode = null;
    this.frequencyData = null;
    this.bands = [];
    this.listeners.clear();
  }
}

// ============ Utility Functions ============

/**
 * Convert frequency to note name.
 */
export function frequencyToNote(freq: number): string {
  const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const a4 = 440;
  const c0 = a4 * Math.pow(2, -4.75);

  const halfSteps = Math.round(12 * Math.log2(freq / c0));
  const octave = Math.floor(halfSteps / 12);
  const noteIndex = halfSteps % 12;

  return `${noteNames[noteIndex]}${octave}`;
}

/**
 * Get frequency for a note name.
 */
export function noteToFrequency(note: string): number {
  const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const match = note.match(/^([A-G]#?)(\d+)$/);
  if (!match) return 0;

  const noteName = match[1];
  const octave = parseInt(match[2], 10);
  const noteIndex = noteNames.indexOf(noteName);

  if (noteIndex === -1) return 0;

  const a4 = 440;
  const halfSteps = (octave * 12 + noteIndex) - 57; // A4 = 57 half steps from C0
  return a4 * Math.pow(2, halfSteps / 12);
}

/**
 * Format frequency for display.
 */
export function formatFrequency(freq: number): string {
  if (freq >= 1000) {
    return `${(freq / 1000).toFixed(1)}kHz`;
  }
  return `${Math.round(freq)}Hz`;
}

/**
 * Format decibels for display.
 */
export function formatDecibels(db: number): string {
  if (db <= -100) return '-∞ dB';
  return `${db.toFixed(1)} dB`;
}
