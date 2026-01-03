/**
 * ReelForge VanEQ Pro - Analyzer Hook
 *
 * Real-time spectrum analyzer with pre/post EQ measurement.
 * Uses Web Audio AnalyserNode for FFT-based spectrum data.
 *
 * Features:
 * - Pre and post EQ spectrum measurement
 * - Hold mode for peak visualization
 * - Smoothing with configurable time constant
 * - FPS throttling for performance
 *
 * @module plugin/vaneq-pro/useAnalyzer
 */

import { useState, useEffect, useRef, useCallback } from 'react';

// ============ Types ============

export interface AnalyzerConfig {
  /** FFT size (power of 2, default 2048) */
  fftSize: number;
  /** Smoothing time constant (0-1, default 0.8) */
  smoothing: number;
  /** Min dB floor for visualization (default -90) */
  minDb: number;
  /** Max dB ceiling for visualization (default 0) */
  maxDb: number;
  /** Target FPS for updates (default 30) */
  targetFps: number;
  /** Hold peak values (default false) */
  holdPeaks: boolean;
  /** Peak hold decay time in ms (default 1500) */
  peakHoldTime: number;
}

export interface AnalyzerData {
  /** Pre-EQ spectrum data (dB values) */
  pre: Float32Array;
  /** Post-EQ spectrum data (dB values) */
  post: Float32Array;
  /** Peak hold values (if enabled) */
  peakHold?: Float32Array;
  /** Frequency bin width in Hz */
  binWidth: number;
  /** Number of frequency bins */
  binCount: number;
  /** Whether the analyzer is in idle state (no signal) */
  isIdle: boolean;
}

export interface UseAnalyzerReturn {
  /** Current analyzer data */
  data: AnalyzerData | null;
  /** Whether analyzer is active */
  isActive: boolean;
  /** Whether signal is idle (below threshold) */
  isIdle: boolean;
  /** Start/resume analyzer */
  start: () => void;
  /** Stop analyzer */
  stop: () => void;
  /** Connect audio nodes for analysis */
  connect: (preNode: AudioNode, postNode: AudioNode) => void;
  /** Disconnect audio nodes */
  disconnect: () => void;
  /** Update configuration */
  setConfig: (config: Partial<AnalyzerConfig>) => void;
  /** Set external idle state (e.g., from DSP processor) */
  setExternalIdle: (isIdle: boolean) => void;
}

// ============ Default Config ============

const DEFAULT_CONFIG: AnalyzerConfig = {
  fftSize: 2048,
  smoothing: 0.8,
  minDb: -90,
  maxDb: 0,
  targetFps: 30,
  holdPeaks: false,
  peakHoldTime: 1500,
};

// ============ Hook ============

/**
 * Hook for real-time spectrum analysis.
 *
 * @param audioContext - Web Audio context to use
 * @param initialConfig - Optional initial configuration
 */
export function useAnalyzer(
  audioContext: AudioContext | null,
  initialConfig: Partial<AnalyzerConfig> = {}
): UseAnalyzerReturn {
  const [isActive, setIsActive] = useState(false);
  const [isIdle, setIsIdle] = useState(true);
  const [data, setData] = useState<AnalyzerData | null>(null);
  const [config, setConfigState] = useState<AnalyzerConfig>({
    ...DEFAULT_CONFIG,
    ...initialConfig,
  });

  // Refs for analyzer nodes
  const preAnalyserRef = useRef<AnalyserNode | null>(null);
  const postAnalyserRef = useRef<AnalyserNode | null>(null);
  const preDataRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const postDataRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const peakHoldRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const peakTimesRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const animationFrameRef = useRef<number | null>(null);
  const lastUpdateRef = useRef<number>(0);

  // Create analyzer nodes when context is available
  useEffect(() => {
    if (!audioContext) {
      preAnalyserRef.current = null;
      postAnalyserRef.current = null;
      return;
    }

    // Create pre-EQ analyzer
    const preAnalyser = audioContext.createAnalyser();
    preAnalyser.fftSize = config.fftSize;
    preAnalyser.smoothingTimeConstant = config.smoothing;
    preAnalyser.minDecibels = config.minDb;
    preAnalyser.maxDecibels = config.maxDb;
    preAnalyserRef.current = preAnalyser;

    // Create post-EQ analyzer
    const postAnalyser = audioContext.createAnalyser();
    postAnalyser.fftSize = config.fftSize;
    postAnalyser.smoothingTimeConstant = config.smoothing;
    postAnalyser.minDecibels = config.minDb;
    postAnalyser.maxDecibels = config.maxDb;
    postAnalyserRef.current = postAnalyser;

    // Create data arrays
    const binCount = preAnalyser.frequencyBinCount;
    preDataRef.current = new Float32Array(binCount);
    postDataRef.current = new Float32Array(binCount);
    peakHoldRef.current = new Float32Array(binCount).fill(config.minDb);
    peakTimesRef.current = new Float32Array(binCount);

    return () => {
      preAnalyser.disconnect();
      postAnalyser.disconnect();
      preAnalyserRef.current = null;
      postAnalyserRef.current = null;
    };
  }, [audioContext, config.fftSize, config.smoothing, config.minDb, config.maxDb]);

  // Animation loop for data updates
  useEffect(() => {
    if (!isActive || !preAnalyserRef.current || !postAnalyserRef.current) {
      return;
    }

    const frameInterval = 1000 / config.targetFps;
    const preAnalyser = preAnalyserRef.current;
    const postAnalyser = postAnalyserRef.current;
    const preData = preDataRef.current;
    const postData = postDataRef.current;
    const peakHold = peakHoldRef.current;
    const peakTimes = peakTimesRef.current;

    if (!preData || !postData) return;

    const updateData = (timestamp: number) => {
      // Throttle updates based on target FPS
      if (timestamp - lastUpdateRef.current < frameInterval) {
        animationFrameRef.current = requestAnimationFrame(updateData);
        return;
      }
      lastUpdateRef.current = timestamp;

      // Get frequency data
      preAnalyser.getFloatFrequencyData(preData);
      postAnalyser.getFloatFrequencyData(postData);

      // If idle, show flat -∞ (use minDb)
      if (isIdle) {
        preData.fill(config.minDb);
        postData.fill(config.minDb);
        if (peakHold) {
          peakHold.fill(config.minDb);
        }
      } else {
        // Update peak hold if enabled
        if (config.holdPeaks && peakHold && peakTimes) {
          for (let i = 0; i < postData.length; i++) {
            if (postData[i] > peakHold[i]) {
              peakHold[i] = postData[i];
              peakTimes[i] = timestamp;
            } else if (timestamp - peakTimes[i] > config.peakHoldTime) {
              // Decay peak
              peakHold[i] = Math.max(postData[i], peakHold[i] - 0.5);
            }
          }
        }
      }

      // Create new data object (copy arrays for React state)
      const newData: AnalyzerData = {
        pre: new Float32Array(preData),
        post: new Float32Array(postData),
        binWidth: audioContext
          ? audioContext.sampleRate / config.fftSize
          : 48000 / config.fftSize,
        binCount: preData.length,
        isIdle,
      };

      if (config.holdPeaks && peakHold) {
        newData.peakHold = new Float32Array(peakHold);
      }

      setData(newData);
      animationFrameRef.current = requestAnimationFrame(updateData);
    };

    animationFrameRef.current = requestAnimationFrame(updateData);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
    };
  }, [isActive, isIdle, config.targetFps, config.holdPeaks, config.peakHoldTime, config.fftSize, config.minDb, audioContext]);

  // Connect audio nodes
  const connect = useCallback(
    (preNode: AudioNode, postNode: AudioNode) => {
      if (!preAnalyserRef.current || !postAnalyserRef.current) {
        console.warn('VanEQ Analyzer: No analyzer nodes available');
        return;
      }

      try {
        preNode.connect(preAnalyserRef.current);
        postNode.connect(postAnalyserRef.current);
      } catch (err) {
        console.error('VanEQ Analyzer: Failed to connect nodes', err);
      }
    },
    []
  );

  // Disconnect audio nodes
  const disconnect = useCallback(() => {
    if (preAnalyserRef.current) {
      try {
        preAnalyserRef.current.disconnect();
      } catch {
        // Node may already be disconnected
      }
    }
    if (postAnalyserRef.current) {
      try {
        postAnalyserRef.current.disconnect();
      } catch {
        // Node may already be disconnected
      }
    }
  }, []);

  // Start analyzer
  const start = useCallback(() => {
    setIsActive(true);
  }, []);

  // Stop analyzer
  const stop = useCallback(() => {
    setIsActive(false);
    if (animationFrameRef.current) {
      cancelAnimationFrame(animationFrameRef.current);
      animationFrameRef.current = null;
    }
  }, []);

  // Update config
  const setConfig = useCallback((updates: Partial<AnalyzerConfig>) => {
    setConfigState((prev) => ({ ...prev, ...updates }));
  }, []);

  // Set external idle state (from DSP processor)
  const setExternalIdle = useCallback((idle: boolean) => {
    setIsIdle(idle);
  }, []);

  return {
    data,
    isActive,
    isIdle,
    start,
    stop,
    connect,
    disconnect,
    setConfig,
    setExternalIdle,
  };
}

/**
 * Create simulated analyzer data for demo/preview mode.
 * Useful when no audio is playing or for testing.
 */
export function createDemoAnalyzerData(binCount = 1024, isIdle = false): AnalyzerData {
  const pre = new Float32Array(binCount);
  const post = new Float32Array(binCount);

  if (isIdle) {
    // Flat -∞ when idle
    pre.fill(-90);
    post.fill(-90);
  } else {
    const now = Date.now() / 1000;

    for (let i = 0; i < binCount; i++) {
      // Create a simple spectrum shape with noise
      const freq = (i / binCount) * 24000;
      const logFreq = Math.log10(freq + 1);

      // Base shape: falling spectrum with low-end bump
      let base = -20 - logFreq * 10;
      if (freq < 200) base += 10 * Math.sin((freq / 200) * Math.PI);

      // Add some animated noise
      const noise = Math.sin(now * 5 + i * 0.1) * 3 + Math.random() * 2;

      pre[i] = base + noise;
      // Post has slightly different shape (simulating EQ effect)
      post[i] = base + noise + (freq > 1000 ? 3 : -2);
    }
  }

  return {
    pre,
    post,
    binWidth: 48000 / 2048,
    binCount,
    isIdle,
  };
}
