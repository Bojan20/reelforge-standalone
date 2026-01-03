/**
 * Performance Monitoring Utility
 *
 * Tracks render performance, memory usage, and provides debugging tools.
 */

import React from 'react';

interface PerformanceMetric {
  name: string;
  duration: number;
  timestamp: number;
}

class PerformanceMonitor {
  private metrics: PerformanceMetric[] = [];
  private timers: Map<string, number> = new Map();
  private readonly maxMetrics = 1000;

  /**
   * Start timing an operation
   */
  startTimer(name: string): void {
    this.timers.set(name, performance.now());
  }

  /**
   * End timing and record metric
   */
  endTimer(name: string): number | null {
    const start = this.timers.get(name);
    if (!start) {
      console.warn(`[PERF] No timer found for: ${name}`);
      return null;
    }

    const duration = performance.now() - start;
    this.timers.delete(name);

    this.recordMetric(name, duration);
    return duration;
  }

  /**
   * Measure async function execution time
   */
  async measure<T>(name: string, fn: () => Promise<T>): Promise<T> {
    this.startTimer(name);
    try {
      return await fn();
    } finally {
      const duration = this.endTimer(name);
      if (duration !== null && duration > 100) {
        console.warn(`[PERF] Slow operation: ${name} took ${duration.toFixed(2)}ms`);
      }
    }
  }

  /**
   * Measure sync function execution time
   */
  measureSync<T>(name: string, fn: () => T): T {
    this.startTimer(name);
    try {
      return fn();
    } finally {
      const duration = this.endTimer(name);
      if (duration !== null && duration > 16) {
        // > 1 frame at 60fps
        console.warn(`[PERF] Blocking operation: ${name} took ${duration.toFixed(2)}ms`);
      }
    }
  }

  /**
   * Record a performance metric
   */
  private recordMetric(name: string, duration: number): void {
    this.metrics.push({
      name,
      duration,
      timestamp: Date.now(),
    });

    // Keep only recent metrics
    if (this.metrics.length > this.maxMetrics) {
      this.metrics = this.metrics.slice(-this.maxMetrics);
    }
  }

  /**
   * Get statistics for a specific metric
   */
  getStats(name: string): {
    count: number;
    avg: number;
    min: number;
    max: number;
    p95: number;
  } | null {
    const samples = this.metrics.filter((m) => m.name === name).map((m) => m.duration);

    if (samples.length === 0) return null;

    const sorted = samples.sort((a, b) => a - b);
    const sum = sorted.reduce((acc, val) => acc + val, 0);

    return {
      count: samples.length,
      avg: sum / samples.length,
      min: sorted[0] ?? 0,
      max: sorted[sorted.length - 1] ?? 0,
      p95: sorted[Math.floor(samples.length * 0.95)] ?? 0,
    };
  }

  /**
   * Get all metrics summary
   */
  getAllStats(): Record<string, ReturnType<typeof this.getStats>> {
    const names = new Set(this.metrics.map((m) => m.name));
    const stats: Record<string, ReturnType<typeof this.getStats>> = {};

    for (const name of names) {
      stats[name] = this.getStats(name);
    }

    return stats;
  }

  /**
   * Log performance report to console
   */
  logReport(): void {
    const stats = this.getAllStats();
    console.group('📊 Performance Report');

    const entries = Object.entries(stats).sort((a, b) => {
      const aAvg = a[1]?.avg ?? 0;
      const bAvg = b[1]?.avg ?? 0;
      return bAvg - aAvg;
    });

    for (const [name, stat] of entries) {
      if (!stat) continue;

      console.log(
        `${name}:`,
        `avg=${stat.avg.toFixed(2)}ms`,
        `min=${stat.min.toFixed(2)}ms`,
        `max=${stat.max.toFixed(2)}ms`,
        `p95=${stat.p95.toFixed(2)}ms`,
        `(${stat.count} samples)`
      );
    }

    console.groupEnd();
  }

  /**
   * Clear all metrics
   */
  clear(): void {
    this.metrics = [];
    this.timers.clear();
  }

  /**
   * Get memory usage (if available)
   */
  getMemoryUsage(): {
    usedJSHeapSize: number;
    totalJSHeapSize: number;
    jsHeapSizeLimit: number;
  } | null {
    if ('memory' in performance) {
      const memory = (performance as any).memory;
      return {
        usedJSHeapSize: memory.usedJSHeapSize,
        totalJSHeapSize: memory.totalJSHeapSize,
        jsHeapSizeLimit: memory.jsHeapSizeLimit,
      };
    }
    return null;
  }

  /**
   * Log memory usage
   */
  logMemoryUsage(): void {
    const memory = this.getMemoryUsage();
    if (!memory) {
      console.log('[PERF] Memory API not available');
      return;
    }

    const usedMB = (memory.usedJSHeapSize / 1024 / 1024).toFixed(2);
    const totalMB = (memory.totalJSHeapSize / 1024 / 1024).toFixed(2);
    const limitMB = (memory.jsHeapSizeLimit / 1024 / 1024).toFixed(2);

    console.log(`[PERF] Memory: ${usedMB} MB / ${totalMB} MB (limit: ${limitMB} MB)`);
  }
}

// Singleton instance
export const perfMonitor = new PerformanceMonitor();

// Development mode helpers
if (import.meta.env.DEV) {
  (window as any).__perfMonitor = perfMonitor;
  console.log('💡 Performance monitor available at window.__perfMonitor');
}

/**
 * React hook for measuring component render time
 */
export function useRenderTimer(componentName: string): void {
  if (import.meta.env.DEV) {
    perfMonitor.startTimer(`render:${componentName}`);

    // Use effect cleanup to measure total render time
    React.useEffect(() => {
      return () => {
        perfMonitor.endTimer(`render:${componentName}`);
      };
    });
  }
}

// Re-export for convenience
export { PerformanceMonitor };
