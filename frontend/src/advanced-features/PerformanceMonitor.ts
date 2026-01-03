/**
 * ReelForge Performance Monitor
 *
 * Real-time performance monitoring for DAW:
 * - CPU/Memory usage
 * - Audio latency tracking
 * - Buffer underrun detection
 * - Per-plugin CPU usage
 *
 * @module advanced-features/PerformanceMonitor
 */

// ============ Types ============

export interface CPUMetrics {
  total: number; // 0-100%
  audio: number; // Audio thread CPU
  ui: number; // UI thread CPU
  peak: number; // Peak in last second
  average: number; // Average over time window
}

export interface MemoryMetrics {
  used: number; // Bytes
  total: number; // Bytes
  heapUsed: number;
  heapTotal: number;
  audioBuffers: number; // Audio buffer memory
  percentage: number; // 0-100%
}

export interface LatencyMetrics {
  input: number; // ms
  output: number; // ms
  buffer: number; // ms
  plugin: number; // Total plugin latency
  roundtrip: number; // Total
  samples: number; // In samples
}

export interface BufferMetrics {
  size: number; // Current buffer size
  underruns: number; // Total underruns
  underrunsPerMinute: number;
  lastUnderrunTime: number | null;
  health: 'good' | 'warning' | 'critical';
}

export interface PluginMetrics {
  instanceId: string;
  pluginName: string;
  cpuPercent: number;
  peakCpu: number;
  avgProcessTime: number; // ms
  latencySamples: number;
}

export interface PerformanceSnapshot {
  timestamp: number;
  cpu: CPUMetrics;
  memory: MemoryMetrics;
  latency: LatencyMetrics;
  buffer: BufferMetrics;
  plugins: PluginMetrics[];
  fps: number;
  isRealtime: boolean;
}

export interface PerformanceAlert {
  type: 'cpu_high' | 'memory_high' | 'underrun' | 'latency_high' | 'plugin_slow';
  severity: 'info' | 'warning' | 'critical';
  message: string;
  timestamp: number;
  data?: Record<string, unknown>;
}

// ============ Performance Monitor ============

class PerformanceMonitorImpl {
  private isRunning = false;
  private updateInterval = 100; // ms
  private intervalId: number | null = null;

  // Metrics history
  private cpuHistory: number[] = [];
  private historySize = 60; // 6 seconds at 100ms interval

  // Underrun tracking
  private underrunCount = 0;
  private underrunTimestamps: number[] = [];
  private lastUnderrunTime: number | null = null;

  // Plugin timing
  private pluginTimings = new Map<string, number[]>();

  // FPS tracking
  private frameTimestamps: number[] = [];
  private lastFrameTime = 0;

  // Listeners
  private snapshotListeners = new Set<(snapshot: PerformanceSnapshot) => void>();
  private alertListeners = new Set<(alert: PerformanceAlert) => void>();

  // Thresholds
  private cpuWarningThreshold = 70;
  private cpuCriticalThreshold = 90;
  private memoryWarningThreshold = 80;
  private latencyWarningThreshold = 50; // ms

  // Audio context reference
  private audioContext: AudioContext | null = null;
  private sampleRate = 44100;
  private bufferSize = 512;

  // ============ Lifecycle ============

  /**
   * Start performance monitoring.
   */
  start(audioContext?: AudioContext): void {
    if (this.isRunning) return;

    this.isRunning = true;
    this.audioContext = audioContext ?? null;

    if (audioContext) {
      this.sampleRate = audioContext.sampleRate;
    }

    this.intervalId = window.setInterval(() => {
      this.collectMetrics();
    }, this.updateInterval);

    // Start FPS tracking
    this.trackFps();
  }

  /**
   * Stop performance monitoring.
   */
  stop(): void {
    this.isRunning = false;

    if (this.intervalId !== null) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /**
   * Set update interval.
   */
  setUpdateInterval(ms: number): void {
    this.updateInterval = Math.max(50, Math.min(1000, ms));

    if (this.isRunning) {
      this.stop();
      this.start(this.audioContext ?? undefined);
    }
  }

  // ============ Metrics Collection ============

  private collectMetrics(): void {
    const snapshot = this.createSnapshot();
    this.checkThresholds(snapshot);
    this.notifySnapshot(snapshot);
  }

  private createSnapshot(): PerformanceSnapshot {
    const cpu = this.collectCpuMetrics();
    const memory = this.collectMemoryMetrics();
    const latency = this.collectLatencyMetrics();
    const buffer = this.collectBufferMetrics();
    const plugins = this.collectPluginMetrics();

    return {
      timestamp: Date.now(),
      cpu,
      memory,
      latency,
      buffer,
      plugins,
      fps: this.calculateFps(),
      isRealtime: buffer.health !== 'critical',
    };
  }

  private collectCpuMetrics(): CPUMetrics {
    // Note: Browser doesn't provide direct CPU access
    // We estimate based on frame timing and audio callback timing

    const now = performance.now();
    const frameTime = now - this.lastFrameTime;
    this.lastFrameTime = now;

    // Estimate CPU based on frame time (target 16.67ms for 60fps)
    const frameCpu = Math.min(100, (frameTime / 16.67) * 100 - 100);
    const audioCpu = this.estimateAudioCpu();

    this.cpuHistory.push(audioCpu);
    if (this.cpuHistory.length > this.historySize) {
      this.cpuHistory.shift();
    }

    const average = this.cpuHistory.reduce((a, b) => a + b, 0) / this.cpuHistory.length;
    const peak = Math.max(...this.cpuHistory);

    return {
      total: Math.min(100, audioCpu + frameCpu * 0.2),
      audio: audioCpu,
      ui: Math.max(0, frameCpu),
      peak,
      average,
    };
  }

  private estimateAudioCpu(): number {
    // Estimate based on buffer size and sample rate
    // Lower buffer = higher CPU needed to keep up
    const bufferMs = (this.bufferSize / this.sampleRate) * 1000;
    const processingBudget = bufferMs * 0.7; // 70% of buffer time

    // Sum plugin processing times
    let totalPluginTime = 0;
    for (const times of this.pluginTimings.values()) {
      if (times.length > 0) {
        totalPluginTime += times[times.length - 1];
      }
    }

    return Math.min(100, (totalPluginTime / processingBudget) * 100);
  }

  private collectMemoryMetrics(): MemoryMetrics {
    // Use Performance API if available
    const memory = (performance as unknown as { memory?: {
      usedJSHeapSize: number;
      totalJSHeapSize: number;
      jsHeapSizeLimit: number;
    } }).memory;

    if (memory) {
      return {
        used: memory.usedJSHeapSize,
        total: memory.jsHeapSizeLimit,
        heapUsed: memory.usedJSHeapSize,
        heapTotal: memory.totalJSHeapSize,
        audioBuffers: this.estimateAudioBufferMemory(),
        percentage: (memory.usedJSHeapSize / memory.jsHeapSizeLimit) * 100,
      };
    }

    // Fallback estimation
    return {
      used: 0,
      total: 0,
      heapUsed: 0,
      heapTotal: 0,
      audioBuffers: this.estimateAudioBufferMemory(),
      percentage: 0,
    };
  }

  private estimateAudioBufferMemory(): number {
    // This would need to be fed from actual audio buffer tracking
    return 0;
  }

  private collectLatencyMetrics(): LatencyMetrics {
    const bufferLatency = (this.bufferSize / this.sampleRate) * 1000;

    // Get audio context latency if available
    let inputLatency = 0;
    let outputLatency = 0;

    if (this.audioContext) {
      // baseLatency is in seconds
      outputLatency = (this.audioContext.baseLatency ?? 0) * 1000;

      // outputLatency is available in some browsers
      if ('outputLatency' in this.audioContext) {
        outputLatency = ((this.audioContext as unknown as { outputLatency: number }).outputLatency ?? 0) * 1000;
      }
    }

    const pluginLatency = this.calculatePluginLatency();

    return {
      input: inputLatency,
      output: outputLatency,
      buffer: bufferLatency,
      plugin: pluginLatency,
      roundtrip: inputLatency + outputLatency + bufferLatency * 2 + pluginLatency,
      samples: Math.round((inputLatency + outputLatency + bufferLatency * 2 + pluginLatency) * this.sampleRate / 1000),
    };
  }

  private calculatePluginLatency(): number {
    // Sum of all plugin latencies
    // Would need to be fed from plugin system
    return 0;
  }

  private collectBufferMetrics(): BufferMetrics {
    // Calculate underruns per minute
    const oneMinuteAgo = Date.now() - 60000;
    const recentUnderruns = this.underrunTimestamps.filter(t => t > oneMinuteAgo);
    this.underrunTimestamps = recentUnderruns;

    // Determine health
    let health: 'good' | 'warning' | 'critical' = 'good';
    if (recentUnderruns.length > 10) {
      health = 'critical';
    } else if (recentUnderruns.length > 3) {
      health = 'warning';
    }

    return {
      size: this.bufferSize,
      underruns: this.underrunCount,
      underrunsPerMinute: recentUnderruns.length,
      lastUnderrunTime: this.lastUnderrunTime,
      health,
    };
  }

  private collectPluginMetrics(): PluginMetrics[] {
    const metrics: PluginMetrics[] = [];

    for (const [instanceId, times] of this.pluginTimings) {
      if (times.length === 0) continue;

      const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
      const peakTime = Math.max(...times);
      const bufferMs = (this.bufferSize / this.sampleRate) * 1000;

      metrics.push({
        instanceId,
        pluginName: instanceId, // Would need plugin registry lookup
        cpuPercent: (avgTime / bufferMs) * 100,
        peakCpu: (peakTime / bufferMs) * 100,
        avgProcessTime: avgTime,
        latencySamples: 0,
      });
    }

    return metrics.sort((a, b) => b.cpuPercent - a.cpuPercent);
  }

  // ============ FPS Tracking ============

  private trackFps(): void {
    if (!this.isRunning) return;

    this.frameTimestamps.push(performance.now());

    // Keep only last second
    const oneSecondAgo = performance.now() - 1000;
    this.frameTimestamps = this.frameTimestamps.filter(t => t > oneSecondAgo);

    requestAnimationFrame(() => this.trackFps());
  }

  private calculateFps(): number {
    return this.frameTimestamps.length;
  }

  // ============ Reporting ============

  /**
   * Report plugin processing time.
   */
  reportPluginTiming(instanceId: string, processingTimeMs: number): void {
    if (!this.pluginTimings.has(instanceId)) {
      this.pluginTimings.set(instanceId, []);
    }

    const times = this.pluginTimings.get(instanceId)!;
    times.push(processingTimeMs);

    // Keep only last 100 samples
    if (times.length > 100) {
      times.shift();
    }
  }

  /**
   * Report buffer underrun.
   */
  reportUnderrun(): void {
    this.underrunCount++;
    this.lastUnderrunTime = Date.now();
    this.underrunTimestamps.push(Date.now());

    this.emitAlert({
      type: 'underrun',
      severity: 'warning',
      message: 'Audio buffer underrun detected',
      timestamp: Date.now(),
    });
  }

  /**
   * Set buffer size.
   */
  setBufferSize(size: number): void {
    this.bufferSize = size;
  }

  /**
   * Set sample rate.
   */
  setSampleRate(rate: number): void {
    this.sampleRate = rate;
  }

  // ============ Thresholds ============

  private checkThresholds(snapshot: PerformanceSnapshot): void {
    // CPU threshold
    if (snapshot.cpu.total > this.cpuCriticalThreshold) {
      this.emitAlert({
        type: 'cpu_high',
        severity: 'critical',
        message: `CPU usage critical: ${snapshot.cpu.total.toFixed(1)}%`,
        timestamp: Date.now(),
        data: { cpu: snapshot.cpu.total },
      });
    } else if (snapshot.cpu.total > this.cpuWarningThreshold) {
      this.emitAlert({
        type: 'cpu_high',
        severity: 'warning',
        message: `CPU usage high: ${snapshot.cpu.total.toFixed(1)}%`,
        timestamp: Date.now(),
        data: { cpu: snapshot.cpu.total },
      });
    }

    // Memory threshold
    if (snapshot.memory.percentage > this.memoryWarningThreshold) {
      this.emitAlert({
        type: 'memory_high',
        severity: 'warning',
        message: `Memory usage high: ${snapshot.memory.percentage.toFixed(1)}%`,
        timestamp: Date.now(),
        data: { memory: snapshot.memory.percentage },
      });
    }

    // Latency threshold
    if (snapshot.latency.roundtrip > this.latencyWarningThreshold) {
      this.emitAlert({
        type: 'latency_high',
        severity: 'info',
        message: `High latency: ${snapshot.latency.roundtrip.toFixed(1)}ms`,
        timestamp: Date.now(),
        data: { latency: snapshot.latency.roundtrip },
      });
    }
  }

  /**
   * Set thresholds.
   */
  setThresholds(thresholds: {
    cpuWarning?: number;
    cpuCritical?: number;
    memoryWarning?: number;
    latencyWarning?: number;
  }): void {
    if (thresholds.cpuWarning !== undefined) {
      this.cpuWarningThreshold = thresholds.cpuWarning;
    }
    if (thresholds.cpuCritical !== undefined) {
      this.cpuCriticalThreshold = thresholds.cpuCritical;
    }
    if (thresholds.memoryWarning !== undefined) {
      this.memoryWarningThreshold = thresholds.memoryWarning;
    }
    if (thresholds.latencyWarning !== undefined) {
      this.latencyWarningThreshold = thresholds.latencyWarning;
    }
  }

  // ============ Subscriptions ============

  /**
   * Subscribe to performance snapshots.
   */
  onSnapshot(callback: (snapshot: PerformanceSnapshot) => void): () => void {
    this.snapshotListeners.add(callback);
    return () => this.snapshotListeners.delete(callback);
  }

  /**
   * Subscribe to performance alerts.
   */
  onAlert(callback: (alert: PerformanceAlert) => void): () => void {
    this.alertListeners.add(callback);
    return () => this.alertListeners.delete(callback);
  }

  private notifySnapshot(snapshot: PerformanceSnapshot): void {
    for (const listener of this.snapshotListeners) {
      listener(snapshot);
    }
  }

  private emitAlert(alert: PerformanceAlert): void {
    for (const listener of this.alertListeners) {
      listener(alert);
    }
  }

  // ============ Utilities ============

  /**
   * Get current snapshot.
   */
  getSnapshot(): PerformanceSnapshot {
    return this.createSnapshot();
  }

  /**
   * Reset statistics.
   */
  reset(): void {
    this.cpuHistory = [];
    this.underrunCount = 0;
    this.underrunTimestamps = [];
    this.lastUnderrunTime = null;
    this.pluginTimings.clear();
    this.frameTimestamps = [];
  }

  /**
   * Check if monitoring is running.
   */
  isMonitoring(): boolean {
    return this.isRunning;
  }
}

// ============ Singleton Instance ============

export const PerformanceMonitor = new PerformanceMonitorImpl();

// ============ Utility Functions ============

/**
 * Format bytes to human readable.
 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/**
 * Format latency for display.
 */
export function formatLatency(ms: number): string {
  if (ms < 1) return `${(ms * 1000).toFixed(0)} µs`;
  return `${ms.toFixed(1)} ms`;
}

/**
 * Get health color.
 */
export function getHealthColor(health: 'good' | 'warning' | 'critical'): string {
  switch (health) {
    case 'good':
      return '#4caf50';
    case 'warning':
      return '#ff9800';
    case 'critical':
      return '#f44336';
  }
}

/**
 * Get CPU color based on percentage.
 */
export function getCpuColor(percent: number): string {
  if (percent < 50) return '#4caf50';
  if (percent < 75) return '#ff9800';
  return '#f44336';
}
