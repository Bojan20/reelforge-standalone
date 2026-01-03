/**
 * useMemoryProfile - Memory Monitoring Hook
 *
 * Tracks memory usage for components and warns about leaks:
 * - Heap size monitoring
 * - Component mount/unmount delta
 * - Automatic warnings for large allocations
 * - Development-only logging
 *
 * @module hooks/useMemoryProfile
 */

import { useEffect, useRef, useCallback } from 'react';

// ============ Types ============

export interface MemoryInfo {
  usedJSHeapSize: number;
  totalJSHeapSize: number;
  jsHeapSizeLimit: number;
}

export interface MemorySnapshot {
  timestamp: number;
  heapUsed: number;
  heapTotal: number;
  heapLimit: number;
  componentName?: string;
}

export interface MemoryDelta {
  componentName: string;
  deltaMB: number;
  durationMs: number;
  warning: boolean;
}

export interface UseMemoryProfileOptions {
  /** Component name for logging */
  componentName?: string;
  /** Threshold in MB to trigger warning (default: 10) */
  warningThresholdMB?: number;
  /** Enable logging even in production */
  forceLogging?: boolean;
  /** Callback on mount/unmount with delta */
  onDelta?: (delta: MemoryDelta) => void;
}

export interface UseMemoryProfileReturn {
  /** Current heap usage in MB */
  heapUsedMB: number;
  /** Take a manual snapshot */
  takeSnapshot: () => MemorySnapshot | null;
  /** Get delta since mount */
  getDelta: () => number;
  /** Check if memory is critical (>80% of limit) */
  isCritical: boolean;
}

// ============ Memory API Access ============

function getMemoryInfo(): MemoryInfo | null {
  if (typeof performance === 'undefined') return null;
  const perf = performance as unknown as { memory?: MemoryInfo };
  return perf.memory || null;
}

function getHeapUsedMB(): number {
  const mem = getMemoryInfo();
  return mem ? mem.usedJSHeapSize / 1024 / 1024 : 0;
}

// ============ Global Memory Monitor ============

const memorySnapshots: MemorySnapshot[] = [];
const MAX_SNAPSHOTS = 100;

export function recordSnapshot(componentName?: string): MemorySnapshot | null {
  const mem = getMemoryInfo();
  if (!mem) return null;

  const snapshot: MemorySnapshot = {
    timestamp: performance.now(),
    heapUsed: mem.usedJSHeapSize,
    heapTotal: mem.totalJSHeapSize,
    heapLimit: mem.jsHeapSizeLimit,
    componentName,
  };

  memorySnapshots.push(snapshot);
  if (memorySnapshots.length > MAX_SNAPSHOTS) {
    memorySnapshots.shift();
  }

  return snapshot;
}

export function getMemoryTrend(): { trend: 'stable' | 'growing' | 'shrinking'; avgDeltaMB: number } {
  if (memorySnapshots.length < 10) {
    return { trend: 'stable', avgDeltaMB: 0 };
  }

  const recent = memorySnapshots.slice(-10);
  let totalDelta = 0;

  for (let i = 1; i < recent.length; i++) {
    totalDelta += recent[i].heapUsed - recent[i - 1].heapUsed;
  }

  const avgDelta = totalDelta / (recent.length - 1);
  const avgDeltaMB = avgDelta / 1024 / 1024;

  if (avgDeltaMB > 1) return { trend: 'growing', avgDeltaMB };
  if (avgDeltaMB < -1) return { trend: 'shrinking', avgDeltaMB };
  return { trend: 'stable', avgDeltaMB };
}

// ============ Hook ============

export function useMemoryProfile(options: UseMemoryProfileOptions = {}): UseMemoryProfileReturn {
  const {
    componentName = 'Unknown',
    warningThresholdMB = 10,
    forceLogging = false,
    onDelta,
  } = options;

  const mountHeapRef = useRef<number>(0);
  const mountTimeRef = useRef<number>(0);
  const isDev = process.env.NODE_ENV === 'development' || forceLogging;

  // Track mount
  useEffect(() => {
    mountHeapRef.current = getHeapUsedMB();
    mountTimeRef.current = performance.now();

    if (isDev) {
      recordSnapshot(componentName);
    }

    // Cleanup: check delta on unmount
    return () => {
      const unmountHeap = getHeapUsedMB();
      const deltaMB = unmountHeap - mountHeapRef.current;
      const durationMs = performance.now() - mountTimeRef.current;

      if (isDev && Math.abs(deltaMB) > warningThresholdMB) {
        console.warn(
          `[Memory] ${componentName} delta: ${deltaMB > 0 ? '+' : ''}${deltaMB.toFixed(2)}MB ` +
          `over ${(durationMs / 1000).toFixed(1)}s`
        );
      }

      if (onDelta) {
        onDelta({
          componentName,
          deltaMB,
          durationMs,
          warning: Math.abs(deltaMB) > warningThresholdMB,
        });
      }
    };
  }, [componentName, warningThresholdMB, isDev, onDelta]);

  // Take manual snapshot
  const takeSnapshot = useCallback((): MemorySnapshot | null => {
    return recordSnapshot(componentName);
  }, [componentName]);

  // Get delta since mount
  const getDelta = useCallback((): number => {
    return getHeapUsedMB() - mountHeapRef.current;
  }, []);

  // Check if critical
  const mem = getMemoryInfo();
  const isCritical = mem
    ? mem.usedJSHeapSize / mem.jsHeapSizeLimit > 0.8
    : false;

  return {
    heapUsedMB: getHeapUsedMB(),
    takeSnapshot,
    getDelta,
    isCritical,
  };
}

// ============ Global Memory Warning System ============

let memoryWarningInterval: ReturnType<typeof setInterval> | null = null;

export function startMemoryMonitoring(options: {
  intervalMs?: number;
  criticalThresholdPercent?: number;
  onCritical?: (heapMB: number, percentUsed: number) => void;
} = {}): () => void {
  const {
    intervalMs = 10000,
    criticalThresholdPercent = 80,
    onCritical,
  } = options;

  if (memoryWarningInterval) {
    clearInterval(memoryWarningInterval);
  }

  memoryWarningInterval = setInterval(() => {
    const mem = getMemoryInfo();
    if (!mem) return;

    const heapMB = mem.usedJSHeapSize / 1024 / 1024;
    const percentUsed = (mem.usedJSHeapSize / mem.jsHeapSizeLimit) * 100;

    recordSnapshot('global-monitor');

    if (percentUsed > criticalThresholdPercent) {
      console.warn(
        `[Memory] CRITICAL: ${heapMB.toFixed(0)}MB used (${percentUsed.toFixed(1)}% of limit)`
      );
      onCritical?.(heapMB, percentUsed);
    }

    // Check for memory leak trend
    const trend = getMemoryTrend();
    if (trend.trend === 'growing' && trend.avgDeltaMB > 5) {
      console.warn(
        `[Memory] Growing trend detected: +${trend.avgDeltaMB.toFixed(2)}MB/sample`
      );
    }
  }, intervalMs);

  return () => {
    if (memoryWarningInterval) {
      clearInterval(memoryWarningInterval);
      memoryWarningInterval = null;
    }
  };
}

export default useMemoryProfile;
