/**
 * ReelForge useInputMonitor Hook
 *
 * React hook for input level monitoring.
 *
 * @module audio-engine/hooks/useInputMonitor
 */

import { useState, useEffect, useCallback } from 'react';
import { InputMonitor, type InputLevels, type SpectrumData } from '../InputMonitor';

export interface UseInputMonitorReturn {
  // State
  isActive: boolean;
  isMonitoringOutput: boolean;
  levels: InputLevels;
  // Actions
  start: () => Promise<void>;
  stop: () => void;
  setMonitorOutput: (enabled: boolean) => void;
  setInputGain: (value: number) => void;
  setMonitorGain: (value: number) => void;
  resetPeakHold: () => void;
}

export function useInputMonitor(): UseInputMonitorReturn {
  const [isActive, setIsActive] = useState(InputMonitor.isActive());
  const [isMonitoringOutput, setIsMonitoringOutput] = useState(InputMonitor.getState().isMonitoringOutput);
  const [levels, setLevels] = useState<InputLevels>(InputMonitor.getState().levels);

  useEffect(() => {
    const unsubscribe = InputMonitor.onLevelChange((newLevels) => {
      setLevels(newLevels);
    });

    return unsubscribe;
  }, []);

  const start = useCallback(async () => {
    await InputMonitor.start();
    setIsActive(true);
  }, []);

  const stop = useCallback(() => {
    InputMonitor.stop();
    setIsActive(false);
    setIsMonitoringOutput(false);
  }, []);

  const setMonitorOutput = useCallback((enabled: boolean) => {
    InputMonitor.setMonitorOutput(enabled);
    setIsMonitoringOutput(enabled);
  }, []);

  const setInputGain = useCallback((value: number) => {
    InputMonitor.setInputGain(value);
  }, []);

  const setMonitorGain = useCallback((value: number) => {
    InputMonitor.setMonitorGain(value);
  }, []);

  const resetPeakHold = useCallback(() => {
    InputMonitor.resetPeakHold();
  }, []);

  return {
    isActive,
    isMonitoringOutput,
    levels,
    start,
    stop,
    setMonitorOutput,
    setInputGain,
    setMonitorGain,
    resetPeakHold,
  };
}

/**
 * Hook for spectrum data from input monitor.
 */
export function useInputSpectrum(): SpectrumData | null {
  const [spectrum, setSpectrum] = useState<SpectrumData | null>(null);

  useEffect(() => {
    const unsubscribe = InputMonitor.onSpectrumChange(setSpectrum);
    return unsubscribe;
  }, []);

  return spectrum;
}
