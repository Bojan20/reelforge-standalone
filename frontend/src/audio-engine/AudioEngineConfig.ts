/**
 * ReelForge Audio Engine Configuration
 *
 * Buffer size, latency, and sample rate configuration.
 * Performance monitoring and CPU/latency dashboard.
 *
 * @module audio-engine/AudioEngineConfig
 */

import { AudioContextManager } from '../core/AudioContextManager';

// ============ Types ============

export type BufferSize = 32 | 64 | 128 | 256 | 512 | 1024 | 2048 | 4096;
export type SampleRate = 44100 | 48000 | 88200 | 96000 | 176400 | 192000;

export interface AudioEngineSettings {
  bufferSize: BufferSize;
  sampleRate: SampleRate;
  inputLatencyMs: number;
  outputLatencyMs: number;
  totalLatencyMs: number;
  // Processing
  enableDithering: boolean;
  ditherBitDepth: 16 | 24;
  enableOversampling: boolean;
  oversamplingFactor: 1 | 2 | 4 | 8;
}

export interface PerformanceMetrics {
  // CPU
  audioThreadLoad: number; // 0-1, estimated
  mainThreadLoad: number;  // 0-1
  // Timing
  currentLatencyMs: number;
  averageLatencyMs: number;
  maxLatencyMs: number;
  // Dropouts
  bufferUnderrunCount: number;
  lastUnderrunTime: number | null;
  // Memory
  audioBufferMemoryMB: number;
  // Stats
  samplesProcessed: number;
  uptimeSeconds: number;
}

type SettingsListener = (settings: AudioEngineSettings) => void;
type MetricsListener = (metrics: PerformanceMetrics) => void;

// ============ Audio Engine Config ============

class AudioEngineConfigClass {
  private settings: AudioEngineSettings = {
    bufferSize: 256,
    sampleRate: 48000,
    inputLatencyMs: 0,
    outputLatencyMs: 0,
    totalLatencyMs: 0,
    enableDithering: true,
    ditherBitDepth: 16,
    enableOversampling: false,
    oversamplingFactor: 2,
  };

  private metrics: PerformanceMetrics = {
    audioThreadLoad: 0,
    mainThreadLoad: 0,
    currentLatencyMs: 0,
    averageLatencyMs: 0,
    maxLatencyMs: 0,
    bufferUnderrunCount: 0,
    lastUnderrunTime: null,
    audioBufferMemoryMB: 0,
    samplesProcessed: 0,
    uptimeSeconds: 0,
  };

  private settingsListeners = new Set<SettingsListener>();
  private metricsListeners = new Set<MetricsListener>();

  // Monitoring
  private metricsInterval: number | null = null;
  private startTime = performance.now();
  private frameTimestamps: number[] = [];
  private latencyHistory: number[] = [];

  /**
   * Initialize with AudioContext.
   */
  initialize(): void {
    const ctx = AudioContextManager.tryGetContext();
    if (ctx) {
      this.updateFromContext(ctx);
    }

    // Subscribe to context changes
    AudioContextManager.subscribe((ctx) => {
      if (ctx) this.updateFromContext(ctx);
    });
  }

  /**
   * Update settings from AudioContext.
   */
  private updateFromContext(ctx: AudioContext): void {
    const sampleRate = ctx.sampleRate as SampleRate;

    // Estimate latencies
    // Web Audio typically has ~128-256 sample output buffer
    const outputLatencyMs = ctx.baseLatency ? ctx.baseLatency * 1000 : (256 / sampleRate) * 1000;
    const inputLatencyMs = outputLatencyMs; // Estimate same as output

    this.settings = {
      ...this.settings,
      sampleRate,
      inputLatencyMs,
      outputLatencyMs,
      totalLatencyMs: inputLatencyMs + outputLatencyMs + this.getBufferLatencyMs(),
    };

    this.notifySettingsChange();
  }

  /**
   * Get buffer latency in milliseconds.
   */
  getBufferLatencyMs(): number {
    return (this.settings.bufferSize / this.settings.sampleRate) * 1000;
  }

  /**
   * Set buffer size.
   * Note: Requires AudioContext recreation in some browsers.
   */
  setBufferSize(size: BufferSize): void {
    this.settings.bufferSize = size;
    this.settings.totalLatencyMs = this.settings.inputLatencyMs + this.settings.outputLatencyMs + this.getBufferLatencyMs();
    this.notifySettingsChange();
  }

  /**
   * Set sample rate.
   * Note: May not be supported on all devices.
   */
  setSampleRate(rate: SampleRate): void {
    this.settings.sampleRate = rate;
    this.notifySettingsChange();
  }

  /**
   * Enable/disable dithering.
   */
  setDithering(enabled: boolean, bitDepth?: 16 | 24): void {
    this.settings.enableDithering = enabled;
    if (bitDepth) this.settings.ditherBitDepth = bitDepth;
    this.notifySettingsChange();
  }

  /**
   * Enable/disable oversampling.
   */
  setOversampling(enabled: boolean, factor?: 1 | 2 | 4 | 8): void {
    this.settings.enableOversampling = enabled;
    if (factor) this.settings.oversamplingFactor = factor;
    this.notifySettingsChange();
  }

  /**
   * Get current settings.
   */
  getSettings(): Readonly<AudioEngineSettings> {
    return { ...this.settings };
  }

  /**
   * Subscribe to settings changes.
   */
  onSettingsChange(listener: SettingsListener): () => void {
    this.settingsListeners.add(listener);
    return () => this.settingsListeners.delete(listener);
  }

  /**
   * Notify settings listeners.
   */
  private notifySettingsChange(): void {
    this.settingsListeners.forEach(fn => fn(this.getSettings()));
  }

  // ============ Performance Monitoring ============

  /**
   * Start performance monitoring.
   */
  startMonitoring(intervalMs = 100): void {
    if (this.metricsInterval !== null) return;

    this.startTime = performance.now();
    this.frameTimestamps = [];
    this.latencyHistory = [];

    this.metricsInterval = window.setInterval(() => {
      this.updateMetrics();
    }, intervalMs);
  }

  /**
   * Stop performance monitoring.
   */
  stopMonitoring(): void {
    if (this.metricsInterval !== null) {
      clearInterval(this.metricsInterval);
      this.metricsInterval = null;
    }
  }

  /**
   * Update metrics.
   */
  private updateMetrics(): void {
    const now = performance.now();

    // Update uptime
    this.metrics.uptimeSeconds = (now - this.startTime) / 1000;

    // Estimate audio thread load from callback timing
    // This is approximate - real load requires AudioWorklet reporting
    this.metrics.audioThreadLoad = this.estimateAudioThreadLoad();

    // Main thread load from frame timing
    this.metrics.mainThreadLoad = this.estimateMainThreadLoad();

    // Current latency
    const ctx = AudioContextManager.tryGetContext();
    if (ctx) {
      const currentLatency = ctx.baseLatency ? ctx.baseLatency * 1000 : this.getBufferLatencyMs();
      this.latencyHistory.push(currentLatency);

      // Keep last 100 samples
      if (this.latencyHistory.length > 100) {
        this.latencyHistory.shift();
      }

      this.metrics.currentLatencyMs = currentLatency;
      this.metrics.averageLatencyMs = this.latencyHistory.reduce((a, b) => a + b, 0) / this.latencyHistory.length;
      this.metrics.maxLatencyMs = Math.max(...this.latencyHistory);
    }

    // Estimate audio buffer memory
    this.metrics.audioBufferMemoryMB = this.estimateAudioMemory();

    this.notifyMetricsChange();
  }

  /**
   * Estimate audio thread load.
   */
  private estimateAudioThreadLoad(): number {
    // Without AudioWorklet reporting, we estimate based on:
    // - Buffer size (smaller = more load)
    // - Processing complexity (unknown, assume medium)
    const bufferMs = this.getBufferLatencyMs();
    const assumedProcessingMs = bufferMs * 0.3; // Assume 30% utilization
    return Math.min(1, assumedProcessingMs / bufferMs);
  }

  /**
   * Estimate main thread load from frame timing.
   */
  private estimateMainThreadLoad(): number {
    const now = performance.now();
    this.frameTimestamps.push(now);

    // Keep last 60 timestamps
    while (this.frameTimestamps.length > 60) {
      this.frameTimestamps.shift();
    }

    if (this.frameTimestamps.length < 2) return 0;

    // Calculate average frame time
    const frameTimes: number[] = [];
    for (let i = 1; i < this.frameTimestamps.length; i++) {
      frameTimes.push(this.frameTimestamps[i] - this.frameTimestamps[i - 1]);
    }

    const avgFrameTime = frameTimes.reduce((a, b) => a + b, 0) / frameTimes.length;

    // 60fps = 16.67ms, anything above indicates load
    const targetFrameTime = 16.67;
    return Math.min(1, (avgFrameTime - targetFrameTime) / targetFrameTime);
  }

  /**
   * Estimate audio buffer memory usage.
   */
  private estimateAudioMemory(): number {
    // Very rough estimate - would need actual tracking
    // Assume some base usage
    return 10; // MB placeholder
  }

  /**
   * Report buffer underrun.
   */
  reportUnderrun(): void {
    this.metrics.bufferUnderrunCount++;
    this.metrics.lastUnderrunTime = performance.now();
    this.notifyMetricsChange();
  }

  /**
   * Report samples processed.
   */
  reportSamplesProcessed(count: number): void {
    this.metrics.samplesProcessed += count;
  }

  /**
   * Get current metrics.
   */
  getMetrics(): Readonly<PerformanceMetrics> {
    return { ...this.metrics };
  }

  /**
   * Subscribe to metrics updates.
   */
  onMetricsChange(listener: MetricsListener): () => void {
    this.metricsListeners.add(listener);
    return () => this.metricsListeners.delete(listener);
  }

  /**
   * Notify metrics listeners.
   */
  private notifyMetricsChange(): void {
    this.metricsListeners.forEach(fn => fn(this.getMetrics()));
  }

  /**
   * Reset metrics.
   */
  resetMetrics(): void {
    this.metrics = {
      audioThreadLoad: 0,
      mainThreadLoad: 0,
      currentLatencyMs: 0,
      averageLatencyMs: 0,
      maxLatencyMs: 0,
      bufferUnderrunCount: 0,
      lastUnderrunTime: null,
      audioBufferMemoryMB: 0,
      samplesProcessed: 0,
      uptimeSeconds: 0,
    };
    this.startTime = performance.now();
    this.frameTimestamps = [];
    this.latencyHistory = [];
    this.notifyMetricsChange();
  }

  /**
   * Get available buffer sizes.
   */
  getAvailableBufferSizes(): BufferSize[] {
    return [32, 64, 128, 256, 512, 1024, 2048, 4096];
  }

  /**
   * Get available sample rates.
   */
  getAvailableSampleRates(): SampleRate[] {
    // Web Audio typically supports these
    return [44100, 48000, 88200, 96000];
  }

  /**
   * Get recommended buffer size for latency target.
   */
  getRecommendedBufferSize(targetLatencyMs: number): BufferSize {
    const sr = this.settings.sampleRate;
    const targetSamples = (targetLatencyMs / 1000) * sr;

    const sizes: BufferSize[] = [32, 64, 128, 256, 512, 1024, 2048, 4096];
    for (const size of sizes) {
      if (size >= targetSamples) return size;
    }
    return 4096;
  }

  /**
   * Dispose.
   */
  dispose(): void {
    this.stopMonitoring();
    this.settingsListeners.clear();
    this.metricsListeners.clear();
  }
}

// Singleton instance
export const AudioEngineConfig = new AudioEngineConfigClass();

// Initialize on load
if (typeof window !== 'undefined') {
  AudioEngineConfig.initialize();
}
