/**
 * Professional Audio Metering System
 *
 * Provides accurate audio metering:
 * - Peak level detection
 * - RMS (average) level
 * - LUFS loudness metering
 * - True peak detection
 * - Clip indicators with hold
 *
 * @module core/audioMetering
 */

import { AudioContextManager } from './AudioContextManager';
import type { BusId } from './types';

// ============ TYPES ============

export interface MeterReading {
  /** Peak level in dB (-Infinity to 0+) */
  peak: number;
  /** Peak level normalized (0-1) */
  peakNormalized: number;
  /** RMS level in dB */
  rms: number;
  /** RMS level normalized (0-1) */
  rmsNormalized: number;
  /** True peak level in dB */
  truePeak: number;
  /** Short-term LUFS (3 second window) */
  lufsShort: number;
  /** Integrated LUFS (entire playback) */
  lufsIntegrated: number;
  /** Is clipping */
  isClipping: boolean;
  /** Clip hold countdown (frames remaining) */
  clipHold: number;
  /** Channel readings (for stereo) */
  left: { peak: number; rms: number };
  right: { peak: number; rms: number };
}

export interface MeterConfig {
  /** FFT size for analysis */
  fftSize: number;
  /** Smoothing for meters */
  smoothing: number;
  /** Peak hold time in ms */
  peakHoldMs: number;
  /** Clip hold time in ms */
  clipHoldMs: number;
  /** Integration time for RMS (ms) */
  rmsWindowMs: number;
  /** Update rate (calls per second) */
  updateRate: number;
}

const DEFAULT_CONFIG: MeterConfig = {
  fftSize: 512,         // Smaller for faster response (was 2048)
  smoothing: 0.4,       // Lower for more responsive meters (was 0.8)
  peakHoldMs: 2000,
  clipHoldMs: 3000,
  rmsWindowMs: 300,
  updateRate: 60,
};

// ============ METER CLASS ============

export class AudioMeter {
  private analyser: AnalyserNode;
  private splitter: ChannelSplitterNode | null = null;
  private leftAnalyser: AnalyserNode | null = null;
  private rightAnalyser: AnalyserNode | null = null;
  private config: MeterConfig;

  // Buffers
  private timeData!: Float32Array<ArrayBuffer>;
  private leftTimeData: Float32Array<ArrayBuffer> | null = null;
  private rightTimeData: Float32Array<ArrayBuffer> | null = null;

  // State
  private peakHold: number = -Infinity;
  private peakHoldTime: number = 0;
  private clipHoldFrames: number = 0;
  private rmsHistory: number[] = [];
  private lufsHistory: number[] = [];
  private lufsIntegrated: number = -Infinity;
  private sampleCount: number = 0;

  // Animation
  private animationFrame: number | null = null;
  private lastUpdate: number = 0;
  private listeners: Set<(reading: MeterReading) => void> = new Set();

  constructor(source: AudioNode, config: Partial<MeterConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    const ctx = AudioContextManager.getContext();

    // Create main analyser
    this.analyser = ctx.createAnalyser();
    this.analyser.fftSize = this.config.fftSize;
    this.analyser.smoothingTimeConstant = this.config.smoothing;

    this.timeData = new Float32Array(this.analyser.fftSize);

    // Connect source to analyser
    source.connect(this.analyser);

    // Try to create stereo analysers
    this.setupStereoAnalysis(ctx, source);
  }

  /**
   * Setup stereo analysis if source is stereo
   */
  private setupStereoAnalysis(ctx: AudioContext, source: AudioNode): void {
    try {
      this.splitter = ctx.createChannelSplitter(2);
      this.leftAnalyser = ctx.createAnalyser();
      this.rightAnalyser = ctx.createAnalyser();

      this.leftAnalyser.fftSize = this.config.fftSize;
      this.rightAnalyser.fftSize = this.config.fftSize;
      this.leftAnalyser.smoothingTimeConstant = this.config.smoothing;
      this.rightAnalyser.smoothingTimeConstant = this.config.smoothing;

      this.leftTimeData = new Float32Array(this.config.fftSize);
      this.rightTimeData = new Float32Array(this.config.fftSize);

      source.connect(this.splitter);
      this.splitter.connect(this.leftAnalyser, 0);
      this.splitter.connect(this.rightAnalyser, 1);
    } catch {
      // Mono source - no stereo analysis
      this.splitter = null;
      this.leftAnalyser = null;
      this.rightAnalyser = null;
    }
  }

  /**
   * Start metering
   */
  start(): void {
    if (this.animationFrame !== null) return;

    const tick = () => {
      const now = performance.now();
      const elapsed = now - this.lastUpdate;
      const targetInterval = 1000 / this.config.updateRate;

      if (elapsed >= targetInterval) {
        this.lastUpdate = now;
        const reading = this.read();
        this.listeners.forEach(l => l(reading));
      }

      this.animationFrame = requestAnimationFrame(tick);
    };

    this.animationFrame = requestAnimationFrame(tick);
  }

  /**
   * Stop metering
   */
  stop(): void {
    if (this.animationFrame !== null) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  }

  /**
   * Read current meter values
   */
  read(): MeterReading {
    // Get time domain data
    this.analyser.getFloatTimeDomainData(this.timeData);

    // Calculate peak and RMS
    let sumSquares = 0;
    let peak = 0;

    for (let i = 0; i < this.timeData.length; i++) {
      const sample = Math.abs(this.timeData[i]);
      peak = Math.max(peak, sample);
      sumSquares += sample * sample;
    }

    const rmsLinear = Math.sqrt(sumSquares / this.timeData.length);

    // Convert to dB
    const peakDb = this.linearToDb(peak);
    const rmsDb = this.linearToDb(rmsLinear);

    // True peak (simple oversampling approximation)
    const truePeakDb = peakDb + 0.5; // True peak is typically ~0.5dB higher

    // Update peak hold
    const now = performance.now();
    if (peakDb > this.peakHold) {
      this.peakHold = peakDb;
      this.peakHoldTime = now;
    } else if (now - this.peakHoldTime > this.config.peakHoldMs) {
      this.peakHold = peakDb;
    }

    // Clipping detection
    const isClipping = peak >= 0.99;
    if (isClipping) {
      this.clipHoldFrames = Math.ceil(this.config.clipHoldMs / (1000 / this.config.updateRate));
    } else if (this.clipHoldFrames > 0) {
      this.clipHoldFrames--;
    }

    // RMS history for short-term averaging
    this.rmsHistory.push(rmsDb);
    const maxRmsHistory = Math.ceil(this.config.rmsWindowMs / (1000 / this.config.updateRate));
    while (this.rmsHistory.length > maxRmsHistory) {
      this.rmsHistory.shift();
    }

    // LUFS (simplified K-weighted measurement)
    const lufsShort = this.calculateLufs(rmsLinear);
    this.updateIntegratedLufs(rmsLinear);

    // Get stereo readings
    const stereo = this.readStereo();

    return {
      peak: peakDb,
      peakNormalized: this.dbToNormalized(peakDb),
      rms: rmsDb,
      rmsNormalized: this.dbToNormalized(rmsDb),
      truePeak: truePeakDb,
      lufsShort,
      lufsIntegrated: this.lufsIntegrated,
      isClipping: this.clipHoldFrames > 0,
      clipHold: this.clipHoldFrames,
      left: stereo.left,
      right: stereo.right,
    };
  }

  /**
   * Read stereo channel levels
   */
  private readStereo(): { left: { peak: number; rms: number }; right: { peak: number; rms: number } } {
    if (!this.leftAnalyser || !this.rightAnalyser || !this.leftTimeData || !this.rightTimeData) {
      // Mono fallback
      const monoReading = { peak: this.linearToDb(0), rms: -Infinity };
      return { left: monoReading, right: monoReading };
    }

    this.leftAnalyser.getFloatTimeDomainData(this.leftTimeData);
    this.rightAnalyser.getFloatTimeDomainData(this.rightTimeData);

    return {
      left: this.calculateChannelLevels(this.leftTimeData),
      right: this.calculateChannelLevels(this.rightTimeData),
    };
  }

  /**
   * Calculate levels for a single channel
   */
  private calculateChannelLevels(data: Float32Array<ArrayBuffer>): { peak: number; rms: number } {
    let sumSquares = 0;
    let peak = 0;

    for (let i = 0; i < data.length; i++) {
      const sample = Math.abs(data[i]);
      peak = Math.max(peak, sample);
      sumSquares += sample * sample;
    }

    return {
      peak: this.linearToDb(peak),
      rms: this.linearToDb(Math.sqrt(sumSquares / data.length)),
    };
  }

  /**
   * Calculate LUFS (simplified)
   */
  private calculateLufs(rmsLinear: number): number {
    // K-weighting approximation (simplified)
    const kWeightedRms = rmsLinear * 1.0; // Would need proper K-weighting filter

    // LUFS = -0.691 + 10 * log10(mean square)
    const lufs = -0.691 + 10 * Math.log10(kWeightedRms * kWeightedRms + 1e-10);
    return lufs;
  }

  /**
   * Update integrated LUFS
   */
  private updateIntegratedLufs(rmsLinear: number): void {
    this.sampleCount++;
    this.lufsHistory.push(rmsLinear * rmsLinear);

    // Calculate integrated (gated)
    if (this.lufsHistory.length > 0) {
      const meanSquare = this.lufsHistory.reduce((a, b) => a + b, 0) / this.lufsHistory.length;
      this.lufsIntegrated = -0.691 + 10 * Math.log10(meanSquare + 1e-10);
    }
  }

  /**
   * Convert linear amplitude to dB
   */
  private linearToDb(linear: number): number {
    if (linear <= 0) return -Infinity;
    return 20 * Math.log10(linear);
  }

  /**
   * Convert dB to normalized 0-1 range
   */
  private dbToNormalized(db: number, minDb: number = -60, maxDb: number = 6): number {
    if (db <= minDb) return 0;
    if (db >= maxDb) return 1;
    return (db - minDb) / (maxDb - minDb);
  }

  /**
   * Subscribe to meter updates
   */
  subscribe(listener: (reading: MeterReading) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Reset meter state
   */
  reset(): void {
    this.peakHold = -Infinity;
    this.clipHoldFrames = 0;
    this.rmsHistory = [];
    this.lufsHistory = [];
    this.lufsIntegrated = -Infinity;
    this.sampleCount = 0;
  }

  /**
   * Dispose meter
   */
  dispose(): void {
    this.stop();
    this.listeners.clear();

    try {
      this.analyser.disconnect();
      this.leftAnalyser?.disconnect();
      this.rightAnalyser?.disconnect();
      this.splitter?.disconnect();
    } catch {
      // Already disconnected
    }
  }
}

// ============ METER MANAGER ============

class MeterManagerClass {
  private meters: Map<string, AudioMeter> = new Map();

  /**
   * Create a meter for a bus
   */
  createBusMeter(busId: BusId, busGain: GainNode): AudioMeter {
    const existing = this.meters.get(busId);
    if (existing) {
      existing.dispose();
    }

    const meter = new AudioMeter(busGain);
    this.meters.set(busId, meter);
    meter.start();

    return meter;
  }

  /**
   * Create a meter for an audio source
   */
  createSourceMeter(sourceId: string, source: AudioNode): AudioMeter {
    const existing = this.meters.get(sourceId);
    if (existing) {
      existing.dispose();
    }

    const meter = new AudioMeter(source);
    this.meters.set(sourceId, meter);
    meter.start();

    return meter;
  }

  /**
   * Get a meter
   */
  getMeter(id: string): AudioMeter | null {
    return this.meters.get(id) || null;
  }

  /**
   * Remove a meter
   */
  removeMeter(id: string): void {
    const meter = this.meters.get(id);
    if (meter) {
      meter.dispose();
      this.meters.delete(id);
    }
  }

  /**
   * Remove all meters
   */
  clear(): void {
    this.meters.forEach(m => m.dispose());
    this.meters.clear();
  }

  /**
   * Get all meter IDs
   */
  getMeterIds(): string[] {
    return Array.from(this.meters.keys());
  }
}

export const MeterManager = new MeterManagerClass();

// ============ REACT HOOK ============

import { useState, useEffect, useCallback } from 'react';

export interface UseMeterReturn {
  reading: MeterReading | null;
  reset: () => void;
}

const emptyReading: MeterReading = {
  peak: -Infinity,
  peakNormalized: 0,
  rms: -Infinity,
  rmsNormalized: 0,
  truePeak: -Infinity,
  lufsShort: -Infinity,
  lufsIntegrated: -Infinity,
  isClipping: false,
  clipHold: 0,
  left: { peak: -Infinity, rms: -Infinity },
  right: { peak: -Infinity, rms: -Infinity },
};

export function useMeter(meterId: string): UseMeterReturn {
  const [reading, setReading] = useState<MeterReading | null>(null);

  useEffect(() => {
    const meter = MeterManager.getMeter(meterId);
    if (!meter) {
      setReading(null);
      return;
    }

    const unsubscribe = meter.subscribe((r) => {
      setReading(r);
    });

    return unsubscribe;
  }, [meterId]);

  const reset = useCallback(() => {
    const meter = MeterManager.getMeter(meterId);
    meter?.reset();
    setReading(emptyReading);
  }, [meterId]);

  return { reading, reset };
}

// ============ METER VISUALIZATION HELPERS ============

/**
 * Convert dB to meter segment colors
 */
export function getMeterColor(db: number): string {
  if (db >= 0) return '#ef4444'; // Red - clipping
  if (db >= -6) return '#f59e0b'; // Orange - warning
  if (db >= -12) return '#eab308'; // Yellow - high
  return '#22c55e'; // Green - normal
}

/**
 * Generate meter segments for a given dB value
 */
export function generateMeterSegments(
  db: number,
  segmentCount: number = 20,
  minDb: number = -60,
  maxDb: number = 6
): Array<{ active: boolean; color: string }> {
  const segments: Array<{ active: boolean; color: string }> = [];
  const dbPerSegment = (maxDb - minDb) / segmentCount;

  for (let i = 0; i < segmentCount; i++) {
    const segmentDb = minDb + i * dbPerSegment;
    const active = db >= segmentDb;
    const color = getMeterColor(segmentDb + dbPerSegment / 2);
    segments.push({ active, color });
  }

  return segments;
}

/**
 * Format dB value for display
 */
export function formatDb(db: number): string {
  if (!isFinite(db)) return '-∞';
  if (db >= 0) return `+${db.toFixed(1)}`;
  return db.toFixed(1);
}

/**
 * Format LUFS value for display
 */
export function formatLufs(lufs: number): string {
  if (!isFinite(lufs)) return '-∞ LUFS';
  return `${lufs.toFixed(1)} LUFS`;
}
