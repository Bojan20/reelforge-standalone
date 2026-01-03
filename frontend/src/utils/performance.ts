/**
 * ReelForge Performance Monitoring Utilities
 *
 * Tools for monitoring and optimizing performance:
 * - FPS counter
 * - Frame time tracking
 * - Memory usage
 * - Render statistics
 *
 * @module utils/performance
 */

// ============ Types ============

export interface FrameStats {
  /** Current FPS */
  fps: number;
  /** Average FPS over sample window */
  avgFps: number;
  /** Frame time in ms */
  frameTime: number;
  /** Average frame time in ms */
  avgFrameTime: number;
  /** Minimum frame time (best) */
  minFrameTime: number;
  /** Maximum frame time (worst) */
  maxFrameTime: number;
  /** Frame count */
  frameCount: number;
  /** Dropped frames (>33ms) */
  droppedFrames: number;
}

export interface MemoryStats {
  /** Used JS heap size in MB */
  usedHeapMB: number;
  /** Total JS heap size in MB */
  totalHeapMB: number;
  /** Heap limit in MB */
  heapLimitMB: number;
  /** Heap usage percentage */
  heapUsagePercent: number;
}

export interface PerformanceReport {
  frame: FrameStats;
  memory: MemoryStats | null;
  timestamp: number;
}

// ============ FPS Counter ============

export class FPSCounter {
  private frameTimes: number[] = [];
  private lastFrameTime = 0;
  private frameCount = 0;
  private droppedFrames = 0;
  private maxSamples: number;

  constructor(maxSamples = 60) {
    this.maxSamples = maxSamples;
  }

  /**
   * Call at the start of each frame.
   */
  tick(): void {
    const now = performance.now();

    if (this.lastFrameTime > 0) {
      const delta = now - this.lastFrameTime;
      this.frameTimes.push(delta);

      if (this.frameTimes.length > this.maxSamples) {
        this.frameTimes.shift();
      }

      // Count dropped frames (>33ms = less than 30fps)
      if (delta > 33) {
        this.droppedFrames++;
      }
    }

    this.lastFrameTime = now;
    this.frameCount++;
  }

  /**
   * Get current statistics.
   */
  getStats(): FrameStats {
    if (this.frameTimes.length === 0) {
      return {
        fps: 0,
        avgFps: 0,
        frameTime: 0,
        avgFrameTime: 0,
        minFrameTime: 0,
        maxFrameTime: 0,
        frameCount: this.frameCount,
        droppedFrames: this.droppedFrames,
      };
    }

    const lastFrameTime = this.frameTimes[this.frameTimes.length - 1];
    const avgFrameTime =
      this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
    const minFrameTime = Math.min(...this.frameTimes);
    const maxFrameTime = Math.max(...this.frameTimes);

    return {
      fps: 1000 / lastFrameTime,
      avgFps: 1000 / avgFrameTime,
      frameTime: lastFrameTime,
      avgFrameTime,
      minFrameTime,
      maxFrameTime,
      frameCount: this.frameCount,
      droppedFrames: this.droppedFrames,
    };
  }

  /**
   * Reset all statistics.
   */
  reset(): void {
    this.frameTimes = [];
    this.lastFrameTime = 0;
    this.frameCount = 0;
    this.droppedFrames = 0;
  }
}

// ============ Memory Monitor ============

/**
 * Get current memory statistics.
 * Note: Only works in Chrome with memory API enabled.
 */
export function getMemoryStats(): MemoryStats | null {
  const perf = performance as Performance & {
    memory?: {
      usedJSHeapSize: number;
      totalJSHeapSize: number;
      jsHeapSizeLimit: number;
    };
  };

  if (!perf.memory) {
    return null;
  }

  const { usedJSHeapSize, totalJSHeapSize, jsHeapSizeLimit } = perf.memory;
  const MB = 1024 * 1024;

  return {
    usedHeapMB: usedJSHeapSize / MB,
    totalHeapMB: totalJSHeapSize / MB,
    heapLimitMB: jsHeapSizeLimit / MB,
    heapUsagePercent: (usedJSHeapSize / jsHeapSizeLimit) * 100,
  };
}

// ============ Performance Monitor ============

export class PerformanceMonitor {
  private fpsCounter: FPSCounter;
  private reports: PerformanceReport[] = [];
  private maxReports: number;
  private isRunning = false;
  private rafId = 0;
  private onReport?: (report: PerformanceReport) => void;

  constructor(options: { maxReports?: number; onReport?: (report: PerformanceReport) => void } = {}) {
    this.fpsCounter = new FPSCounter();
    this.maxReports = options.maxReports ?? 1000;
    this.onReport = options.onReport;
  }

  /**
   * Start monitoring.
   */
  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;
    this.loop();
  }

  /**
   * Stop monitoring.
   */
  stop(): void {
    this.isRunning = false;
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = 0;
    }
  }

  /**
   * Manual tick (for external RAF loops).
   */
  tick(): PerformanceReport {
    this.fpsCounter.tick();

    const report: PerformanceReport = {
      frame: this.fpsCounter.getStats(),
      memory: getMemoryStats(),
      timestamp: performance.now(),
    };

    this.reports.push(report);
    if (this.reports.length > this.maxReports) {
      this.reports.shift();
    }

    this.onReport?.(report);
    return report;
  }

  /**
   * Get all reports.
   */
  getReports(): PerformanceReport[] {
    return [...this.reports];
  }

  /**
   * Get summary statistics.
   */
  getSummary(): {
    avgFps: number;
    minFps: number;
    maxFps: number;
    avgFrameTime: number;
    totalFrames: number;
    droppedFrames: number;
    droppedPercent: number;
  } {
    if (this.reports.length === 0) {
      return {
        avgFps: 0,
        minFps: 0,
        maxFps: 0,
        avgFrameTime: 0,
        totalFrames: 0,
        droppedFrames: 0,
        droppedPercent: 0,
      };
    }

    const fpsValues = this.reports.map((r) => r.frame.fps).filter((f) => f > 0);
    const frameTimeValues = this.reports.map((r) => r.frame.frameTime).filter((f) => f > 0);
    const lastReport = this.reports[this.reports.length - 1];

    return {
      avgFps: fpsValues.reduce((a, b) => a + b, 0) / fpsValues.length,
      minFps: Math.min(...fpsValues),
      maxFps: Math.max(...fpsValues),
      avgFrameTime: frameTimeValues.reduce((a, b) => a + b, 0) / frameTimeValues.length,
      totalFrames: lastReport.frame.frameCount,
      droppedFrames: lastReport.frame.droppedFrames,
      droppedPercent: (lastReport.frame.droppedFrames / lastReport.frame.frameCount) * 100,
    };
  }

  /**
   * Reset all data.
   */
  reset(): void {
    this.fpsCounter.reset();
    this.reports = [];
  }

  private loop = (): void => {
    if (!this.isRunning) return;
    this.tick();
    this.rafId = requestAnimationFrame(this.loop);
  };
}

// ============ Measure Function ============

/**
 * Measure execution time of a function.
 */
export function measure<T>(name: string, fn: () => T): T {
  const start = performance.now();
  const result = fn();
  const end = performance.now();
  console.log(`[Perf] ${name}: ${(end - start).toFixed(2)}ms`);
  return result;
}

/**
 * Measure execution time of an async function.
 */
export async function measureAsync<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const start = performance.now();
  const result = await fn();
  const end = performance.now();
  console.log(`[Perf] ${name}: ${(end - start).toFixed(2)}ms`);
  return result;
}

// ============ Debounce & Throttle ============

/**
 * Debounce a function.
 */
export function debounce<T extends (...args: unknown[]) => unknown>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: ReturnType<typeof setTimeout>;

  return (...args: Parameters<T>) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
}

/**
 * Throttle a function.
 */
export function throttle<T extends (...args: unknown[]) => unknown>(
  fn: T,
  limit: number
): (...args: Parameters<T>) => void {
  let lastCall = 0;

  return (...args: Parameters<T>) => {
    const now = Date.now();
    if (now - lastCall >= limit) {
      lastCall = now;
      fn(...args);
    }
  };
}

// ============ RAF Scheduler ============

type ScheduledCallback = () => void;

/**
 * RAF-based scheduler for batching updates.
 */
export class RAFScheduler {
  private callbacks: Set<ScheduledCallback> = new Set();
  private isScheduled = false;

  /**
   * Schedule a callback for next frame.
   */
  schedule(callback: ScheduledCallback): void {
    this.callbacks.add(callback);

    if (!this.isScheduled) {
      this.isScheduled = true;
      requestAnimationFrame(this.flush);
    }
  }

  /**
   * Cancel a scheduled callback.
   */
  cancel(callback: ScheduledCallback): void {
    this.callbacks.delete(callback);
  }

  private flush = (): void => {
    this.isScheduled = false;
    const toRun = [...this.callbacks];
    this.callbacks.clear();

    for (const callback of toRun) {
      try {
        callback();
      } catch (err) {
        console.error('[RAFScheduler] Callback error:', err);
      }
    }
  };
}

// ============ Default Instance ============

export const rafScheduler = new RAFScheduler();

// ============ Performance Mark Helpers ============

let markId = 0;

/**
 * Start a performance mark.
 */
export function perfStart(name: string): string {
  const id = `${name}_${++markId}`;
  performance.mark(`${id}_start`);
  return id;
}

/**
 * End a performance mark and log duration.
 */
export function perfEnd(id: string, log = true): number {
  performance.mark(`${id}_end`);

  try {
    performance.measure(id, `${id}_start`, `${id}_end`);
    const measure = performance.getEntriesByName(id, 'measure')[0];
    const duration = measure?.duration ?? 0;

    if (log) {
      console.log(`[Perf] ${id}: ${duration.toFixed(2)}ms`);
    }

    // Cleanup
    performance.clearMarks(`${id}_start`);
    performance.clearMarks(`${id}_end`);
    performance.clearMeasures(id);

    return duration;
  } catch {
    return 0;
  }
}
