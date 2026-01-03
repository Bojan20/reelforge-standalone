/**
 * ReelForge Performance Monitoring Hook
 *
 * React hook for tracking component/animation performance.
 *
 * @module hooks/usePerformance
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import {
  PerformanceMonitor,
  FPSCounter,
  type PerformanceReport,
  type FrameStats,
  type MemoryStats,
  getMemoryStats,
} from '../utils/performance';

// ============ Types ============

export interface UsePerformanceOptions {
  /** Enable monitoring */
  enabled?: boolean;
  /** Sample window size */
  sampleSize?: number;
  /** Update interval in ms (0 = every frame) */
  updateInterval?: number;
  /** Callback on each report */
  onReport?: (report: PerformanceReport) => void;
}

export interface UsePerformanceReturn {
  /** Current frame stats */
  frameStats: FrameStats | null;
  /** Current memory stats */
  memoryStats: MemoryStats | null;
  /** Is monitoring active */
  isMonitoring: boolean;
  /** Start monitoring */
  start: () => void;
  /** Stop monitoring */
  stop: () => void;
  /** Reset statistics */
  reset: () => void;
  /** Manual tick (for external RAF) */
  tick: () => void;
  /** Get summary */
  getSummary: () => ReturnType<PerformanceMonitor['getSummary']>;
}

// ============ Hook ============

export function usePerformance(options: UsePerformanceOptions = {}): UsePerformanceReturn {
  const {
    enabled = true,
    sampleSize = 60,
    updateInterval = 500,
    onReport,
  } = options;

  const [frameStats, setFrameStats] = useState<FrameStats | null>(null);
  const [memoryStats, setMemoryStats] = useState<MemoryStats | null>(null);
  const [isMonitoring, setIsMonitoring] = useState(false);

  const monitorRef = useRef<PerformanceMonitor | null>(null);
  const fpsCounterRef = useRef<FPSCounter | null>(null);
  const rafRef = useRef<number>(0);
  const lastUpdateRef = useRef<number>(0);

  // Initialize
  useEffect(() => {
    monitorRef.current = new PerformanceMonitor({
      maxReports: sampleSize * 10,
      onReport,
    });
    fpsCounterRef.current = new FPSCounter(sampleSize);

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [sampleSize, onReport]);

  // Update state periodically
  const updateState = useCallback(() => {
    const now = performance.now();
    if (now - lastUpdateRef.current < updateInterval) return;
    lastUpdateRef.current = now;

    if (fpsCounterRef.current) {
      setFrameStats(fpsCounterRef.current.getStats());
    }
    setMemoryStats(getMemoryStats());
  }, [updateInterval]);

  // Animation loop
  useEffect(() => {
    if (!enabled || !isMonitoring) return;

    const loop = () => {
      fpsCounterRef.current?.tick();
      updateState();
      rafRef.current = requestAnimationFrame(loop);
    };

    rafRef.current = requestAnimationFrame(loop);

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [enabled, isMonitoring, updateState]);

  // Start monitoring
  const start = useCallback(() => {
    setIsMonitoring(true);
  }, []);

  // Stop monitoring
  const stop = useCallback(() => {
    setIsMonitoring(false);
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = 0;
    }
  }, []);

  // Reset statistics
  const reset = useCallback(() => {
    fpsCounterRef.current?.reset();
    monitorRef.current?.reset();
    setFrameStats(null);
    setMemoryStats(null);
  }, []);

  // Manual tick
  const tick = useCallback(() => {
    fpsCounterRef.current?.tick();
    updateState();
  }, [updateState]);

  // Get summary
  const getSummary = useCallback(() => {
    return monitorRef.current?.getSummary() ?? {
      avgFps: 0,
      minFps: 0,
      maxFps: 0,
      avgFrameTime: 0,
      totalFrames: 0,
      droppedFrames: 0,
      droppedPercent: 0,
    };
  }, []);

  // Auto-start if enabled
  useEffect(() => {
    if (enabled) {
      start();
    } else {
      stop();
    }
  }, [enabled, start, stop]);

  return {
    frameStats,
    memoryStats,
    isMonitoring,
    start,
    stop,
    reset,
    tick,
    getSummary,
  };
}

// ============ FPS Display Component Props ============

export interface FPSDisplayData {
  fps: number;
  avgFps: number;
  frameTime: number;
  memoryMB: number | null;
  droppedPercent: number;
}

/**
 * Get formatted FPS display data.
 */
export function getFPSDisplayData(
  frameStats: FrameStats | null,
  memoryStats: MemoryStats | null
): FPSDisplayData {
  return {
    fps: frameStats?.fps ?? 0,
    avgFps: frameStats?.avgFps ?? 0,
    frameTime: frameStats?.frameTime ?? 0,
    memoryMB: memoryStats?.usedHeapMB ?? null,
    droppedPercent:
      frameStats && frameStats.frameCount > 0
        ? (frameStats.droppedFrames / frameStats.frameCount) * 100
        : 0,
  };
}

export default usePerformance;
