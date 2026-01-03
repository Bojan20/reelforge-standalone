/**
 * Real-time Bus Meter Hook
 *
 * Uses Web Audio AnalyserNode to get real-time peak levels for each bus.
 * Features:
 * - 60fps animation loop using requestAnimationFrame
 * - Peak hold with decay
 * - Multiple bus support
 * - Auto-cleanup on unmount
 * - Visibility-based throttling (pauses when tab hidden)
 */

import { useRef, useEffect, useState } from 'react';
import { useVisibilityState } from './useVisibilityThrottle';

export interface BusMeterState {
  /** Current peak level (0-1) */
  peak: number;
  /** RMS level (0-1) */
  rms: number;
  /** Peak hold level (0-1) */
  peakHold: number;
  /** Whether signal is clipping */
  clipping: boolean;
}

export interface BusMeterConfig {
  /** Bus ID */
  id: string;
  /** Audio source node to analyze */
  sourceNode?: AudioNode;
}

interface BusMeterInternal {
  analyser: AnalyserNode;
  dataArray: Float32Array<ArrayBuffer>;
  peakHold: number;
  peakHoldDecay: number;
  lastPeakTime: number;
}

const PEAK_HOLD_TIME = 1500; // ms to hold peak
const PEAK_DECAY_RATE = 0.05; // decay per frame after hold time
const SMOOTHING = 0.8; // smoothing factor for meter

export function useBusMeter(
  audioContext: AudioContext | null,
  buses: BusMeterConfig[]
): Map<string, BusMeterState> {
  const metersRef = useRef<Map<string, BusMeterInternal>>(new Map());
  const animationRef = useRef<number | null>(null);
  const [meterStates, setMeterStates] = useState<Map<string, BusMeterState>>(new Map());

  // Visibility-based throttling - pause when tab hidden
  const { isVisible } = useVisibilityState();

  // Initialize analyzers for each bus
  useEffect(() => {
    if (!audioContext) return;

    const newMeters = new Map<string, BusMeterInternal>();

    buses.forEach(bus => {
      if (!bus.sourceNode) return;

      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 2048;
      analyser.smoothingTimeConstant = SMOOTHING;

      // Connect source to analyser (analyser doesn't produce output by itself)
      try {
        bus.sourceNode.connect(analyser);
      } catch (e) {
        console.warn('[BusMeter] Failed to connect source:', e);
        return;
      }

      const dataArray = new Float32Array(analyser.fftSize);

      newMeters.set(bus.id, {
        analyser,
        dataArray,
        peakHold: 0,
        peakHoldDecay: 0,
        lastPeakTime: 0,
      });
    });

    metersRef.current = newMeters;

    return () => {
      // Cleanup analyzers
      newMeters.forEach(meter => {
        try {
          meter.analyser.disconnect();
        } catch { /* ignore */ }
      });
      metersRef.current.clear();
    };
  }, [audioContext, buses]);

  // Animation loop - pauses when tab is hidden
  useEffect(() => {
    if (!audioContext || metersRef.current.size === 0) return;

    // Pause animation when tab is hidden to save CPU
    if (!isVisible) {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
      return;
    }

    const updateMeters = () => {
      const now = performance.now();
      const newStates = new Map<string, BusMeterState>();

      metersRef.current.forEach((meter, busId) => {
        // Get time domain data
        meter.analyser.getFloatTimeDomainData(meter.dataArray);

        // Calculate peak and RMS
        let peak = 0;
        let sumSquares = 0;

        for (let i = 0; i < meter.dataArray.length; i++) {
          const sample = Math.abs(meter.dataArray[i]);
          if (sample > peak) peak = sample;
          sumSquares += sample * sample;
        }

        const rms = Math.sqrt(sumSquares / meter.dataArray.length);

        // Update peak hold
        if (peak > meter.peakHold) {
          meter.peakHold = peak;
          meter.lastPeakTime = now;
          meter.peakHoldDecay = 0;
        } else if (now - meter.lastPeakTime > PEAK_HOLD_TIME) {
          // Start decay
          meter.peakHoldDecay += PEAK_DECAY_RATE;
          meter.peakHold = Math.max(0, meter.peakHold - meter.peakHoldDecay);
        }

        // Clipping detection (signal above 0.99)
        const clipping = peak > 0.99;

        newStates.set(busId, {
          peak: Math.min(1, peak),
          rms: Math.min(1, rms),
          peakHold: Math.min(1, meter.peakHold),
          clipping,
        });
      });

      setMeterStates(newStates);
      animationRef.current = requestAnimationFrame(updateMeters);
    };

    animationRef.current = requestAnimationFrame(updateMeters);

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [audioContext, isVisible]);

  return meterStates;
}

/**
 * Simpler hook for when we don't have actual audio nodes connected yet.
 * Generates simulated meter levels based on playback state.
 *
 * OPTIMIZED:
 * - Uses stable Map ref + version counter to avoid GC pressure
 * - Visibility-based throttling (pauses when tab hidden)
 */
export function useSimulatedBusMeter(
  buses: { id: string; volume: number; muted: boolean }[],
  isPlaying: boolean
): Map<string, BusMeterState> {
  // Stable Map ref - mutated in place, never recreated
  const meterStatesRef = useRef<Map<string, BusMeterState>>(new Map());
  // Version counter to trigger re-renders
  const [, setVersion] = useState(0);
  const animationRef = useRef<number | null>(null);
  const noiseRef = useRef<Map<string, number>>(new Map());
  const busesRef = useRef(buses);
  busesRef.current = buses;

  // Visibility-based throttling - pause when tab hidden
  const { isVisible } = useVisibilityState();

  useEffect(() => {
    // Cancel any existing animation
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
      animationRef.current = null;
    }

    // Pause animation when tab is hidden to save CPU
    if (!isVisible) {
      return;
    }

    const states = meterStatesRef.current;

    if (!isPlaying) {
      // When stopped, decay all meters to zero
      const decayMeters = () => {
        let hasActivity = false;

        states.forEach((state) => {
          const newPeak = state.peak * 0.85;
          const newRms = state.rms * 0.85;
          const newPeakHold = state.peakHold * 0.9;
          if (newPeak > 0.001 || newRms > 0.001) hasActivity = true;

          // Mutate in place
          state.peak = newPeak;
          state.rms = newRms;
          state.peakHold = newPeakHold;
          state.clipping = false;
        });

        // Trigger re-render
        setVersion(v => v + 1);

        if (hasActivity) {
          animationRef.current = requestAnimationFrame(decayMeters);
        } else {
          animationRef.current = null;
        }
      };

      animationRef.current = requestAnimationFrame(decayMeters);
      return () => {
        if (animationRef.current) {
          cancelAnimationFrame(animationRef.current);
          animationRef.current = null;
        }
      };
    }

    // Simulate meter activity when playing
    const updateMeters = () => {
      const currentBuses = busesRef.current;

      currentBuses.forEach(bus => {
        let state = states.get(bus.id);
        if (!state) {
          state = { peak: 0, rms: 0, peakHold: 0, clipping: false };
          states.set(bus.id, state);
        }

        if (bus.muted) {
          state.peak = 0;
          state.rms = 0;
          state.peakHold = 0;
          state.clipping = false;
          return;
        }

        // Get or initialize noise value for smooth animation
        let noise = noiseRef.current.get(bus.id) ?? Math.random();
        // Smooth random walk
        noise += (Math.random() - 0.5) * 0.3;
        noise = Math.max(0, Math.min(0.9, noise));
        noiseRef.current.set(bus.id, noise);

        // Calculate simulated levels based on volume and noise
        const baseLevel = bus.volume * noise;
        const peak = Math.min(1, baseLevel + Math.random() * 0.1);
        const rms = baseLevel * 0.7;

        // Mutate in place - no new object creation
        state.peak = peak;
        state.rms = rms;
        state.peakHold = Math.max(peak, state.peakHold) * 0.998;
        state.clipping = peak > 0.95;
      });

      // Trigger re-render with version bump
      setVersion(v => v + 1);
      animationRef.current = requestAnimationFrame(updateMeters);
    };

    animationRef.current = requestAnimationFrame(updateMeters);

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [isPlaying, isVisible]);

  return meterStatesRef.current;
}

/**
 * Convert linear amplitude to dB
 */
export function linearToDb(linear: number): number {
  if (linear <= 0) return -Infinity;
  return 20 * Math.log10(linear);
}

/**
 * Convert dB to linear amplitude
 */
export function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

/**
 * Get color for meter level
 */
export function getMeterColor(level: number): string {
  if (level > 0.95) return '#ef4444'; // Red - clipping
  if (level > 0.8) return '#f59e0b';  // Yellow - hot
  if (level > 0.5) return '#22c55e';  // Green - normal
  return '#4ade80'; // Light green - low
}
