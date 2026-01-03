/**
 * ReelForge useAudioRecorder Hook
 *
 * React hook for audio recording.
 *
 * @module audio-engine/hooks/useAudioRecorder
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { AudioRecorder, type RecorderState, type RecordingOptions, type RecordingResult } from '../AudioRecorder';

export interface UseAudioRecorderReturn {
  // State
  state: RecorderState['state'];
  duration: number;
  peakLevel: number;
  rmsLevel: number;
  clipCount: number;
  isMonitoring: boolean;
  supportedFormats: string[];
  // Actions
  start: (options?: RecordingOptions) => Promise<void>;
  pause: () => void;
  resume: () => void;
  stop: () => Promise<RecordingResult>;
  cancel: () => void;
  setInputGain: (value: number) => void;
  setMonitorGain: (value: number) => void;
  toggleMonitoring: (enabled: boolean) => void;
}

export function useAudioRecorder(): UseAudioRecorderReturn {
  const [state, setState] = useState<RecorderState>(AudioRecorder.getState());
  const resultRef = useRef<RecordingResult | null>(null);

  useEffect(() => {
    const unsubscribe = AudioRecorder.subscribe(setState);
    return unsubscribe;
  }, []);

  const start = useCallback(async (options?: RecordingOptions) => {
    await AudioRecorder.start(options);
  }, []);

  const pause = useCallback(() => {
    AudioRecorder.pause();
  }, []);

  const resume = useCallback(() => {
    AudioRecorder.resume();
  }, []);

  const stop = useCallback(async () => {
    const result = await AudioRecorder.stop();
    resultRef.current = result;
    return result;
  }, []);

  const cancel = useCallback(() => {
    AudioRecorder.cancel();
  }, []);

  const setInputGain = useCallback((value: number) => {
    AudioRecorder.setInputGain(value);
  }, []);

  const setMonitorGain = useCallback((value: number) => {
    AudioRecorder.setMonitorGain(value);
  }, []);

  const toggleMonitoring = useCallback((enabled: boolean) => {
    AudioRecorder.toggleMonitoring(enabled);
  }, []);

  return {
    state: state.state,
    duration: state.duration,
    peakLevel: state.peakLevel,
    rmsLevel: state.rmsLevel,
    clipCount: state.clipCount,
    isMonitoring: state.isMonitoring,
    supportedFormats: AudioRecorder.getSupportedFormats(),
    start,
    pause,
    resume,
    stop,
    cancel,
    setInputGain,
    setMonitorGain,
    toggleMonitoring,
  };
}
