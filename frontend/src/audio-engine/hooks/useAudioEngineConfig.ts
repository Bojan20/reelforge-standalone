/**
 * ReelForge useAudioEngineConfig Hook
 *
 * React hook for audio engine configuration and performance monitoring.
 *
 * @module audio-engine/hooks/useAudioEngineConfig
 */

import { useState, useEffect, useCallback } from 'react';
import {
  AudioEngineConfig,
  type AudioEngineSettings,
  type PerformanceMetrics,
  type BufferSize,
  type SampleRate,
} from '../AudioEngineConfig';

export interface UseAudioEngineConfigReturn {
  // Settings
  settings: AudioEngineSettings;
  availableBufferSizes: BufferSize[];
  availableSampleRates: SampleRate[];
  // Actions
  setBufferSize: (size: BufferSize) => void;
  setSampleRate: (rate: SampleRate) => void;
  setDithering: (enabled: boolean, bitDepth?: 16 | 24) => void;
  setOversampling: (enabled: boolean, factor?: 1 | 2 | 4 | 8) => void;
  getRecommendedBufferSize: (targetLatencyMs: number) => BufferSize;
}

export function useAudioEngineConfig(): UseAudioEngineConfigReturn {
  const [settings, setSettings] = useState<AudioEngineSettings>(AudioEngineConfig.getSettings());

  useEffect(() => {
    const unsubscribe = AudioEngineConfig.onSettingsChange(setSettings);
    return unsubscribe;
  }, []);

  const setBufferSize = useCallback((size: BufferSize) => {
    AudioEngineConfig.setBufferSize(size);
  }, []);

  const setSampleRate = useCallback((rate: SampleRate) => {
    AudioEngineConfig.setSampleRate(rate);
  }, []);

  const setDithering = useCallback((enabled: boolean, bitDepth?: 16 | 24) => {
    AudioEngineConfig.setDithering(enabled, bitDepth);
  }, []);

  const setOversampling = useCallback((enabled: boolean, factor?: 1 | 2 | 4 | 8) => {
    AudioEngineConfig.setOversampling(enabled, factor);
  }, []);

  const getRecommendedBufferSize = useCallback((targetLatencyMs: number) => {
    return AudioEngineConfig.getRecommendedBufferSize(targetLatencyMs);
  }, []);

  return {
    settings,
    availableBufferSizes: AudioEngineConfig.getAvailableBufferSizes(),
    availableSampleRates: AudioEngineConfig.getAvailableSampleRates(),
    setBufferSize,
    setSampleRate,
    setDithering,
    setOversampling,
    getRecommendedBufferSize,
  };
}

/**
 * Hook for performance metrics with optional auto-start.
 */
export function usePerformanceMetrics(autoStart = true): PerformanceMetrics {
  const [metrics, setMetrics] = useState<PerformanceMetrics>(AudioEngineConfig.getMetrics());

  useEffect(() => {
    if (autoStart) {
      AudioEngineConfig.startMonitoring();
    }

    const unsubscribe = AudioEngineConfig.onMetricsChange(setMetrics);

    return () => {
      unsubscribe();
      if (autoStart) {
        AudioEngineConfig.stopMonitoring();
      }
    };
  }, [autoStart]);

  return metrics;
}

/**
 * Hook for latency display.
 */
export function useLatencyInfo(): {
  bufferLatencyMs: number;
  totalLatencyMs: number;
  inputLatencyMs: number;
  outputLatencyMs: number;
} {
  const { settings } = useAudioEngineConfig();

  return {
    bufferLatencyMs: AudioEngineConfig.getBufferLatencyMs(),
    totalLatencyMs: settings.totalLatencyMs,
    inputLatencyMs: settings.inputLatencyMs,
    outputLatencyMs: settings.outputLatencyMs,
  };
}
