/**
 * useLiveMeter - Connect audio meters to React components
 *
 * Provides real-time audio level updates from the MeterManager.
 * Uses requestAnimationFrame for smooth 60fps updates.
 *
 * @module hooks/useLiveMeter
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { MeterManager, type MeterReading } from '../core/audioMetering';
import type { BusId } from '../core/types';

// ============ Types ============

export interface MeterState {
  /** Peak level normalized 0-1 */
  peak: number;
  /** Peak level right channel (if stereo) */
  peakR?: number;
  /** RMS level normalized 0-1 */
  rms: number;
  /** RMS level right channel */
  rmsR?: number;
  /** Peak hold (decaying) */
  peakHold: number;
  /** Peak hold right channel */
  peakHoldR?: number;
  /** Is clipping */
  isClipping: boolean;
  /** LUFS short-term */
  lufsShort: number;
}

export interface UseLiveMeterOptions {
  /** Meter ID (bus ID or source ID) */
  meterId: string;
  /** Enable/disable metering */
  enabled?: boolean;
  /** Peak hold decay rate (0-1, lower = slower) */
  peakDecayRate?: number;
  /** Smoothing factor (0-1, higher = smoother) */
  smoothing?: number;
}

// ============ Default State ============

const DEFAULT_STATE: MeterState = {
  peak: 0,
  peakR: 0,
  rms: 0,
  rmsR: 0,
  peakHold: 0,
  peakHoldR: 0,
  isClipping: false,
  lufsShort: -60,
};

// ============ Hook ============

export function useLiveMeter(options: UseLiveMeterOptions): MeterState {
  const { meterId, enabled = true, peakDecayRate = 0.95, smoothing = 0.3 } = options;

  const [state, setState] = useState<MeterState>(DEFAULT_STATE);
  const stateRef = useRef<MeterState>(DEFAULT_STATE);
  const peakHoldRef = useRef({ left: 0, right: 0 });
  const animationRef = useRef<number | null>(null);
  const lastUpdateRef = useRef<number>(0);

  // Update state with smoothing
  const updateMeter = useCallback((reading: MeterReading) => {
    const now = performance.now();
    const dt = (now - lastUpdateRef.current) / 1000;
    lastUpdateRef.current = now;

    // Peak hold decay
    peakHoldRef.current.left *= Math.pow(peakDecayRate, dt * 60);
    peakHoldRef.current.right *= Math.pow(peakDecayRate, dt * 60);

    // Update peak holds if new peak is higher
    if (reading.left.peak > peakHoldRef.current.left) {
      peakHoldRef.current.left = reading.left.peak;
    }
    if (reading.right.peak > peakHoldRef.current.right) {
      peakHoldRef.current.right = reading.right.peak;
    }

    // Apply smoothing to values
    const smooth = (current: number, target: number) =>
      current + (target - current) * smoothing;

    const prev = stateRef.current;

    const newState: MeterState = {
      peak: smooth(prev.peak, reading.peakNormalized),
      peakR: smooth(prev.peakR ?? 0, reading.right.peak),
      rms: smooth(prev.rms, reading.rmsNormalized),
      rmsR: smooth(prev.rmsR ?? 0, reading.right.rms),
      peakHold: peakHoldRef.current.left,
      peakHoldR: peakHoldRef.current.right,
      isClipping: reading.isClipping,
      lufsShort: reading.lufsShort,
    };

    stateRef.current = newState;
    setState(newState);
  }, [peakDecayRate, smoothing]);

  // Subscribe to meter updates
  useEffect(() => {
    if (!enabled) {
      setState(DEFAULT_STATE);
      return;
    }

    const meter = MeterManager.getMeter(meterId);
    if (!meter) {
      return;
    }

    // Subscribe to meter readings
    const unsubscribe = meter.subscribe(updateMeter);

    return () => {
      unsubscribe();
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [meterId, enabled, updateMeter]);

  return state;
}

// ============ Hook for Multiple Meters ============

export interface MultipleMeterState {
  [meterId: string]: MeterState;
}

export function useMultipleMeters(
  meterIds: string[],
  enabled = true
): MultipleMeterState {
  const [states, setStates] = useState<MultipleMeterState>({});
  const statesRef = useRef<MultipleMeterState>({});

  useEffect(() => {
    if (!enabled) {
      setStates({});
      return;
    }

    const unsubscribes: (() => void)[] = [];
    const peakHolds: Record<string, { left: number; right: number }> = {};

    for (const meterId of meterIds) {
      peakHolds[meterId] = { left: 0, right: 0 };

      const meter = MeterManager.getMeter(meterId);
      if (!meter) continue;

      const handleReading = (reading: MeterReading) => {
        // Decay peak holds
        peakHolds[meterId].left *= 0.95;
        peakHolds[meterId].right *= 0.95;

        if (reading.left.peak > peakHolds[meterId].left) {
          peakHolds[meterId].left = reading.left.peak;
        }
        if (reading.right.peak > peakHolds[meterId].right) {
          peakHolds[meterId].right = reading.right.peak;
        }

        const newState: MeterState = {
          peak: reading.peakNormalized,
          peakR: reading.right.peak,
          rms: reading.rmsNormalized,
          rmsR: reading.right.rms,
          peakHold: peakHolds[meterId].left,
          peakHoldR: peakHolds[meterId].right,
          isClipping: reading.isClipping,
          lufsShort: reading.lufsShort,
        };

        statesRef.current = {
          ...statesRef.current,
          [meterId]: newState,
        };
      };

      const unsub = meter.subscribe(handleReading);
      unsubscribes.push(unsub);
    }

    // Batch state updates at 60fps
    let animFrame: number;
    const updateState = () => {
      setStates({ ...statesRef.current });
      animFrame = requestAnimationFrame(updateState);
    };
    animFrame = requestAnimationFrame(updateState);

    return () => {
      unsubscribes.forEach(fn => fn());
      cancelAnimationFrame(animFrame);
    };
  }, [meterIds.join(','), enabled]);

  return states;
}

// ============ Hook to Create and Manage Meters ============

export function useBusMeterSetup(
  busId: BusId,
  busGain: GainNode | null,
  enabled = true
): MeterState {
  const [state, setState] = useState<MeterState>(DEFAULT_STATE);
  const meterCreatedRef = useRef(false);

  // Create meter when busGain becomes available
  useEffect(() => {
    if (!enabled || !busGain) {
      return;
    }

    // Create meter if not exists
    if (!MeterManager.getMeter(busId)) {
      MeterManager.createBusMeter(busId, busGain);
      meterCreatedRef.current = true;
    }

    const meter = MeterManager.getMeter(busId);
    if (!meter) return;

    let peakHoldL = 0;
    let peakHoldR = 0;

    const handleReading = (reading: MeterReading) => {
      // Decay peak holds
      peakHoldL *= 0.95;
      peakHoldR *= 0.95;

      if (reading.left.peak > peakHoldL) peakHoldL = reading.left.peak;
      if (reading.right.peak > peakHoldR) peakHoldR = reading.right.peak;

      setState({
        peak: reading.peakNormalized,
        peakR: reading.right.peak,
        rms: reading.rmsNormalized,
        rmsR: reading.right.rms,
        peakHold: peakHoldL,
        peakHoldR: peakHoldR,
        isClipping: reading.isClipping,
        lufsShort: reading.lufsShort,
      });
    };

    const unsubscribe = meter.subscribe(handleReading);

    return () => {
      unsubscribe();
      // Only remove meter if we created it
      if (meterCreatedRef.current) {
        MeterManager.removeMeter(busId);
        meterCreatedRef.current = false;
      }
    };
  }, [busId, busGain, enabled]);

  return state;
}

// ============ Utility: dB to Normalized ============

export function dbToNormalized(db: number, minDb = -60, maxDb = 0): number {
  if (db <= minDb) return 0;
  if (db >= maxDb) return 1;
  return (db - minDb) / (maxDb - minDb);
}

export function normalizedToDb(normalized: number, minDb = -60, maxDb = 0): number {
  return minDb + normalized * (maxDb - minDb);
}
