/**
 * Audio Profiler
 *
 * Performance profiling and analysis for audio operations:
 * - Operation timing (play, stop, fade, etc.)
 * - CPU usage tracking
 * - Memory allocation tracking
 * - Hotspot detection
 * - Performance reports
 */

// ============ TYPES ============

export type ProfileCategory =
  | 'play'
  | 'stop'
  | 'fade'
  | 'decode'
  | 'load'
  | 'process'
  | 'transition'
  | 'update'
  | 'render';

export interface ProfileSample {
  /** Sample ID */
  id: string;
  /** Category */
  category: ProfileCategory;
  /** Operation name */
  operation: string;
  /** Start time */
  startTime: number;
  /** End time */
  endTime: number;
  /** Duration in ms */
  duration: number;
  /** Memory delta (bytes) */
  memoryDelta?: number;
  /** Additional metadata */
  metadata?: Record<string, unknown>;
}

export interface CategoryStats {
  /** Category name */
  category: ProfileCategory;
  /** Total samples */
  sampleCount: number;
  /** Total time spent (ms) */
  totalTime: number;
  /** Average time (ms) */
  avgTime: number;
  /** Min time (ms) */
  minTime: number;
  /** Max time (ms) */
  maxTime: number;
  /** Percentage of total profiled time */
  percentage: number;
}

export interface ProfileReport {
  /** Report timestamp */
  timestamp: number;
  /** Total profiled time (ms) */
  totalProfiledTime: number;
  /** Total samples collected */
  totalSamples: number;
  /** Stats per category */
  categoryStats: CategoryStats[];
  /** Slowest operations */
  slowestOperations: ProfileSample[];
  /** Operations per second */
  operationsPerSecond: number;
  /** Hotspots (frequently slow operations) */
  hotspots: Array<{ operation: string; avgTime: number; count: number }>;
}

export interface ActiveProfile {
  id: string;
  category: ProfileCategory;
  operation: string;
  startTime: number;
  startMemory?: number;
  metadata?: Record<string, unknown>;
}

// ============ AUDIO PROFILER ============

export class AudioProfiler {
  private samples: ProfileSample[] = [];
  private activeProfiles: Map<string, ActiveProfile> = new Map();
  private enabled: boolean = false;
  private maxSamples: number = 10000;
  private sessionStartTime: number;
  private categoryTotals: Map<ProfileCategory, { count: number; totalTime: number }> = new Map();

  constructor() {
    this.sessionStartTime = performance.now();
    this.initCategoryTotals();
  }

  private initCategoryTotals(): void {
    const categories: ProfileCategory[] = [
      'play', 'stop', 'fade', 'decode', 'load', 'process', 'transition', 'update', 'render'
    ];
    categories.forEach(cat => {
      this.categoryTotals.set(cat, { count: 0, totalTime: 0 });
    });
  }

  /**
   * Enable/disable profiling
   */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  /**
   * Check if profiling is enabled
   */
  isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * Start profiling an operation
   */
  startProfile(
    category: ProfileCategory,
    operation: string,
    metadata?: Record<string, unknown>
  ): string {
    if (!this.enabled) return '';

    const id = `${category}_${operation}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;

    const profile: ActiveProfile = {
      id,
      category,
      operation,
      startTime: performance.now(),
      metadata,
    };

    // Try to capture memory if available
    if ('memory' in performance) {
      profile.startMemory = (performance as unknown as { memory: { usedJSHeapSize: number } }).memory.usedJSHeapSize;
    }

    this.activeProfiles.set(id, profile);
    return id;
  }

  /**
   * End profiling an operation
   */
  endProfile(id: string): ProfileSample | null {
    if (!this.enabled || !id) return null;

    const profile = this.activeProfiles.get(id);
    if (!profile) return null;

    this.activeProfiles.delete(id);

    const endTime = performance.now();
    const duration = endTime - profile.startTime;

    let memoryDelta: number | undefined;
    if (profile.startMemory !== undefined && 'memory' in performance) {
      const endMemory = (performance as unknown as { memory: { usedJSHeapSize: number } }).memory.usedJSHeapSize;
      memoryDelta = endMemory - profile.startMemory;
    }

    const sample: ProfileSample = {
      id: profile.id,
      category: profile.category,
      operation: profile.operation,
      startTime: profile.startTime,
      endTime,
      duration,
      memoryDelta,
      metadata: profile.metadata,
    };

    this.addSample(sample);
    return sample;
  }

  /**
   * Profile a synchronous function
   */
  profile<T>(
    category: ProfileCategory,
    operation: string,
    fn: () => T,
    metadata?: Record<string, unknown>
  ): T {
    if (!this.enabled) return fn();

    const id = this.startProfile(category, operation, metadata);
    try {
      return fn();
    } finally {
      this.endProfile(id);
    }
  }

  /**
   * Profile an async function
   */
  async profileAsync<T>(
    category: ProfileCategory,
    operation: string,
    fn: () => Promise<T>,
    metadata?: Record<string, unknown>
  ): Promise<T> {
    if (!this.enabled) return fn();

    const id = this.startProfile(category, operation, metadata);
    try {
      return await fn();
    } finally {
      this.endProfile(id);
    }
  }

  /**
   * Add a sample manually
   */
  addSample(sample: ProfileSample): void {
    this.samples.push(sample);

    // Update category totals
    const totals = this.categoryTotals.get(sample.category);
    if (totals) {
      totals.count++;
      totals.totalTime += sample.duration;
    }

    // Trim samples if too large
    if (this.samples.length > this.maxSamples) {
      this.samples = this.samples.slice(-this.maxSamples / 2);
    }
  }

  /**
   * Generate performance report
   */
  generateReport(): ProfileReport {
    const now = performance.now();
    const sessionDuration = (now - this.sessionStartTime) / 1000; // seconds

    // Calculate category stats
    let totalProfiledTime = 0;
    const categoryStats: CategoryStats[] = [];

    this.categoryTotals.forEach((totals) => {
      totalProfiledTime += totals.totalTime;
    });

    this.categoryTotals.forEach((totals, category) => {
      if (totals.count === 0) return;

      const categorySamples = this.samples.filter(s => s.category === category);
      const durations = categorySamples.map(s => s.duration);

      categoryStats.push({
        category,
        sampleCount: totals.count,
        totalTime: totals.totalTime,
        avgTime: totals.totalTime / totals.count,
        minTime: durations.length > 0 ? Math.min(...durations) : 0,
        maxTime: durations.length > 0 ? Math.max(...durations) : 0,
        percentage: totalProfiledTime > 0 ? (totals.totalTime / totalProfiledTime) * 100 : 0,
      });
    });

    // Sort by total time
    categoryStats.sort((a, b) => b.totalTime - a.totalTime);

    // Find slowest operations
    const slowestOperations = [...this.samples]
      .sort((a, b) => b.duration - a.duration)
      .slice(0, 10);

    // Find hotspots (operations that are both frequent and slow)
    const operationStats = new Map<string, { totalTime: number; count: number }>();
    this.samples.forEach(sample => {
      const key = `${sample.category}:${sample.operation}`;
      const stats = operationStats.get(key) ?? { totalTime: 0, count: 0 };
      stats.totalTime += sample.duration;
      stats.count++;
      operationStats.set(key, stats);
    });

    const hotspots = Array.from(operationStats.entries())
      .map(([operation, stats]) => ({
        operation,
        avgTime: stats.totalTime / stats.count,
        count: stats.count,
      }))
      .filter(h => h.count >= 5 && h.avgTime > 1) // At least 5 occurrences and >1ms avg
      .sort((a, b) => (b.avgTime * b.count) - (a.avgTime * a.count))
      .slice(0, 10);

    return {
      timestamp: now,
      totalProfiledTime,
      totalSamples: this.samples.length,
      categoryStats,
      slowestOperations,
      operationsPerSecond: this.samples.length / Math.max(1, sessionDuration),
      hotspots,
    };
  }

  /**
   * Get samples by category
   */
  getSamplesByCategory(category: ProfileCategory, limit: number = 100): ProfileSample[] {
    return this.samples
      .filter(s => s.category === category)
      .slice(-limit);
  }

  /**
   * Get samples by operation
   */
  getSamplesByOperation(operation: string, limit: number = 100): ProfileSample[] {
    return this.samples
      .filter(s => s.operation.includes(operation))
      .slice(-limit);
  }

  /**
   * Get average time for an operation
   */
  getAverageTime(category: ProfileCategory, operation?: string): number {
    const filtered = operation
      ? this.samples.filter(s => s.category === category && s.operation === operation)
      : this.samples.filter(s => s.category === category);

    if (filtered.length === 0) return 0;

    const total = filtered.reduce((sum, s) => sum + s.duration, 0);
    return total / filtered.length;
  }

  /**
   * Get samples that exceed a threshold
   */
  getSlowSamples(thresholdMs: number): ProfileSample[] {
    return this.samples.filter(s => s.duration > thresholdMs);
  }

  /**
   * Clear all samples
   */
  clear(): void {
    this.samples = [];
    this.activeProfiles.clear();
    this.initCategoryTotals();
    this.sessionStartTime = performance.now();
  }

  /**
   * Export samples as JSON
   */
  exportJSON(): string {
    return JSON.stringify({
      report: this.generateReport(),
      samples: this.samples.slice(-1000),
    }, null, 2);
  }

  /**
   * Dispose profiler
   */
  dispose(): void {
    this.samples = [];
    this.activeProfiles.clear();
    this.categoryTotals.clear();
  }
}

// ============ FRAME TIME MONITOR ============

export class FrameTimeMonitor {
  private frameTimes: number[] = [];
  private lastFrameTime: number = 0;
  private maxSamples: number = 120; // ~2 seconds at 60fps
  private enabled: boolean = false;
  private rafId: number | null = null;

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (enabled && !this.rafId) {
      this.start();
    } else if (!enabled && this.rafId) {
      this.stop();
    }
  }

  private start(): void {
    const measure = (timestamp: number) => {
      if (!this.enabled) return;

      if (this.lastFrameTime > 0) {
        const frameTime = timestamp - this.lastFrameTime;
        this.frameTimes.push(frameTime);

        if (this.frameTimes.length > this.maxSamples) {
          this.frameTimes.shift();
        }
      }

      this.lastFrameTime = timestamp;
      this.rafId = requestAnimationFrame(measure);
    };

    this.rafId = requestAnimationFrame(measure);
  }

  private stop(): void {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  getAverageFrameTime(): number {
    if (this.frameTimes.length === 0) return 0;
    return this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
  }

  getAverageFPS(): number {
    const avgFrameTime = this.getAverageFrameTime();
    return avgFrameTime > 0 ? 1000 / avgFrameTime : 0;
  }

  getDroppedFrames(): number {
    // Count frames that took longer than 33ms (less than 30fps)
    return this.frameTimes.filter(t => t > 33).length;
  }

  getJank(): number {
    // Percentage of frames that were janky (>16.67ms for 60fps)
    if (this.frameTimes.length === 0) return 0;
    const jankyFrames = this.frameTimes.filter(t => t > 16.67).length;
    return (jankyFrames / this.frameTimes.length) * 100;
  }

  getStats(): {
    avgFrameTime: number;
    avgFPS: number;
    minFrameTime: number;
    maxFrameTime: number;
    droppedFrames: number;
    jankPercentage: number;
  } {
    const times = this.frameTimes;
    return {
      avgFrameTime: this.getAverageFrameTime(),
      avgFPS: this.getAverageFPS(),
      minFrameTime: times.length > 0 ? Math.min(...times) : 0,
      maxFrameTime: times.length > 0 ? Math.max(...times) : 0,
      droppedFrames: this.getDroppedFrames(),
      jankPercentage: this.getJank(),
    };
  }

  dispose(): void {
    this.stop();
    this.frameTimes = [];
  }
}

// ============ GLOBAL PROFILER INSTANCE ============

export const audioProfiler = new AudioProfiler();
export const frameMonitor = new FrameTimeMonitor();
