/**
 * ReelForge Performance Monitor
 *
 * Centralized performance metrics collection and reporting.
 * Tracks render times, audio latency, memory usage, and custom marks.
 */

// ============ Types ============

export interface PerformanceMetric {
  name: string;
  value: number;
  unit: 'ms' | 'bytes' | 'count' | 'percent';
  timestamp: number;
}

export interface PerformanceSnapshot {
  timestamp: number;
  metrics: Record<string, PerformanceMetric>;
  memory?: {
    usedJSHeapSize: number;
    totalJSHeapSize: number;
    jsHeapSizeLimit: number;
  };
}

export interface PerformanceThresholds {
  renderTime: number;      // ms - warn if render exceeds
  audioLatency: number;    // ms - warn if audio latency exceeds
  memoryUsage: number;     // percent - warn if heap usage exceeds
  longTaskDuration: number; // ms - warn if task exceeds
}

// ============ Default Thresholds ============

const DEFAULT_THRESHOLDS: PerformanceThresholds = {
  renderTime: 16,          // 60fps = 16.67ms per frame
  audioLatency: 50,        // Noticeable audio delay
  memoryUsage: 80,         // 80% heap usage
  longTaskDuration: 100,   // 100ms - less noisy than Chrome's 50ms
};

// ============ Performance Monitor Class ============

class PerformanceMonitor {
  private metrics: Map<string, PerformanceMetric[]> = new Map();
  private thresholds: PerformanceThresholds = DEFAULT_THRESHOLDS;
  private maxMetricsPerKey = 100;
  private listeners: Set<(snapshot: PerformanceSnapshot) => void> = new Set();
  private snapshotInterval: ReturnType<typeof setInterval> | null = null;
  private longTaskObserver: PerformanceObserver | null = null;

  constructor() {
    this.setupLongTaskObserver();
  }

  // ============ Configuration ============

  setThresholds(thresholds: Partial<PerformanceThresholds>): void {
    this.thresholds = { ...this.thresholds, ...thresholds };
  }

  getThresholds(): PerformanceThresholds {
    return { ...this.thresholds };
  }

  // ============ Metric Recording ============

  record(name: string, value: number, unit: PerformanceMetric['unit'] = 'ms'): void {
    const metric: PerformanceMetric = {
      name,
      value,
      unit,
      timestamp: performance.now(),
    };

    if (!this.metrics.has(name)) {
      this.metrics.set(name, []);
    }

    const arr = this.metrics.get(name)!;
    arr.push(metric);

    // Keep only recent metrics
    if (arr.length > this.maxMetricsPerKey) {
      arr.splice(0, 1);
    }

    // Check thresholds
    this.checkThreshold(name, value);
  }

  // ============ Timing Helpers ============

  startMark(name: string): void {
    performance.mark(`rf-${name}-start`);
  }

  endMark(name: string): number {
    const startMark = `rf-${name}-start`;
    const endMark = `rf-${name}-end`;

    performance.mark(endMark);

    try {
      const measure = performance.measure(`rf-${name}`, startMark, endMark);
      const duration = measure.duration;

      this.record(name, duration, 'ms');

      // Cleanup marks
      performance.clearMarks(startMark);
      performance.clearMarks(endMark);
      performance.clearMeasures(`rf-${name}`);

      return duration;
    } catch {
      return 0;
    }
  }

  /**
   * Measure async operation duration.
   */
  async measureAsync<T>(name: string, operation: () => Promise<T>): Promise<T> {
    this.startMark(name);
    try {
      return await operation();
    } finally {
      this.endMark(name);
    }
  }

  /**
   * Measure sync operation duration.
   */
  measure<T>(name: string, operation: () => T): T {
    this.startMark(name);
    try {
      return operation();
    } finally {
      this.endMark(name);
    }
  }

  // ============ Metric Retrieval ============

  getMetric(name: string): PerformanceMetric | undefined {
    const arr = this.metrics.get(name);
    return arr?.[arr.length - 1];
  }

  getMetricHistory(name: string, count: number = 10): PerformanceMetric[] {
    const arr = this.metrics.get(name) ?? [];
    return arr.slice(-count);
  }

  getMetricAverage(name: string, count: number = 10): number {
    const history = this.getMetricHistory(name, count);
    if (history.length === 0) return 0;
    return history.reduce((sum, m) => sum + m.value, 0) / history.length;
  }

  getMetricMax(name: string, count: number = 10): number {
    const history = this.getMetricHistory(name, count);
    if (history.length === 0) return 0;
    return Math.max(...history.map(m => m.value));
  }

  getMetricMin(name: string, count: number = 10): number {
    const history = this.getMetricHistory(name, count);
    if (history.length === 0) return 0;
    return Math.min(...history.map(m => m.value));
  }

  // ============ Memory Tracking ============

  getMemoryInfo(): PerformanceSnapshot['memory'] | undefined {
    // @ts-expect-error - memory is non-standard but available in Chrome
    const memory = performance.memory;
    if (!memory) return undefined;

    return {
      usedJSHeapSize: memory.usedJSHeapSize,
      totalJSHeapSize: memory.totalJSHeapSize,
      jsHeapSizeLimit: memory.jsHeapSizeLimit,
    };
  }

  getMemoryUsagePercent(): number {
    const memory = this.getMemoryInfo();
    if (!memory) return 0;
    return (memory.usedJSHeapSize / memory.jsHeapSizeLimit) * 100;
  }

  // ============ Snapshots ============

  getSnapshot(): PerformanceSnapshot {
    const metricsRecord: Record<string, PerformanceMetric> = {};

    for (const [name, arr] of this.metrics) {
      const latest = arr[arr.length - 1];
      if (latest) {
        metricsRecord[name] = latest;
      }
    }

    return {
      timestamp: Date.now(),
      metrics: metricsRecord,
      memory: this.getMemoryInfo(),
    };
  }

  // ============ Subscription ============

  subscribe(listener: (snapshot: PerformanceSnapshot) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  startPeriodicSnapshot(intervalMs: number = 5000): void {
    this.stopPeriodicSnapshot();
    this.snapshotInterval = setInterval(() => {
      const snapshot = this.getSnapshot();
      this.listeners.forEach(listener => listener(snapshot));
    }, intervalMs);
  }

  stopPeriodicSnapshot(): void {
    if (this.snapshotInterval) {
      clearInterval(this.snapshotInterval);
      this.snapshotInterval = null;
    }
  }

  // ============ Long Task Observer ============

  private setupLongTaskObserver(): void {
    if (typeof PerformanceObserver === 'undefined') return;

    try {
      this.longTaskObserver = new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          this.record('longTask', entry.duration, 'ms');

          if (entry.duration > this.thresholds.longTaskDuration) {
            console.warn(`[Performance] Long task detected: ${entry.duration.toFixed(1)}ms`);
          }
        }
      });

      this.longTaskObserver.observe({ entryTypes: ['longtask'] });
    } catch {
      // Long task observer not supported
    }
  }

  // ============ Threshold Checking ============

  private checkThreshold(name: string, value: number): void {
    if (name === 'renderTime' && value > this.thresholds.renderTime) {
      console.warn(`[Performance] Slow render: ${value.toFixed(1)}ms (threshold: ${this.thresholds.renderTime}ms)`);
    }

    if (name === 'audioLatency' && value > this.thresholds.audioLatency) {
      console.warn(`[Performance] High audio latency: ${value.toFixed(1)}ms (threshold: ${this.thresholds.audioLatency}ms)`);
    }

    if (name === 'memoryUsage' && value > this.thresholds.memoryUsage) {
      console.warn(`[Performance] High memory usage: ${value.toFixed(1)}% (threshold: ${this.thresholds.memoryUsage}%)`);
    }
  }

  // ============ Cleanup ============

  clear(): void {
    this.metrics.clear();
  }

  dispose(): void {
    this.stopPeriodicSnapshot();
    this.longTaskObserver?.disconnect();
    this.metrics.clear();
    this.listeners.clear();
  }
}

// ============ Singleton Instance ============

export const performanceMonitor = new PerformanceMonitor();

// ============ React Hook ============

import { useEffect, useState } from 'react';

export function usePerformanceMetric(name: string): PerformanceMetric | undefined {
  const [metric, setMetric] = useState<PerformanceMetric | undefined>(
    () => performanceMonitor.getMetric(name)
  );

  useEffect(() => {
    const interval = setInterval(() => {
      setMetric(performanceMonitor.getMetric(name));
    }, 1000);

    return () => clearInterval(interval);
  }, [name]);

  return metric;
}

export function usePerformanceSnapshot(): PerformanceSnapshot | null {
  const [snapshot, setSnapshot] = useState<PerformanceSnapshot | null>(null);

  useEffect(() => {
    return performanceMonitor.subscribe(setSnapshot);
  }, []);

  return snapshot;
}

// ============ Utility Functions ============

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatMs(ms: number): string {
  if (ms < 1) return `${(ms * 1000).toFixed(0)}µs`;
  if (ms < 1000) return `${ms.toFixed(1)}ms`;
  return `${(ms / 1000).toFixed(2)}s`;
}
