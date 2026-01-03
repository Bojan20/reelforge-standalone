/**
 * ReelForge useAudioDevices Hook
 *
 * React hook for audio device management.
 *
 * @module audio-engine/hooks/useAudioDevices
 */

import { useState, useEffect, useCallback } from 'react';
import { AudioDeviceManager, type AudioDeviceState, type AudioDeviceInfo } from '../AudioDeviceManager';

export interface UseAudioDevicesReturn {
  // State
  inputs: AudioDeviceInfo[];
  outputs: AudioDeviceInfo[];
  selectedInputId: string | null;
  selectedOutputId: string | null;
  hasPermission: boolean;
  isEnumerating: boolean;
  error: string | null;
  isSupported: boolean;
  // Actions
  requestPermission: () => Promise<boolean>;
  selectInput: (deviceId: string) => void;
  selectOutput: (deviceId: string) => void;
  refresh: () => Promise<void>;
}

export function useAudioDevices(): UseAudioDevicesReturn {
  const [state, setState] = useState<AudioDeviceState>(AudioDeviceManager.getState());

  useEffect(() => {
    const unsubscribe = AudioDeviceManager.subscribe(setState);
    return unsubscribe;
  }, []);

  const requestPermission = useCallback(async () => {
    return AudioDeviceManager.requestPermission();
  }, []);

  const selectInput = useCallback((deviceId: string) => {
    AudioDeviceManager.selectInput(deviceId);
  }, []);

  const selectOutput = useCallback((deviceId: string) => {
    AudioDeviceManager.selectOutput(deviceId);
  }, []);

  const refresh = useCallback(async () => {
    await AudioDeviceManager.enumerateDevices();
  }, []);

  return {
    inputs: state.inputs,
    outputs: state.outputs,
    selectedInputId: state.selectedInputId,
    selectedOutputId: state.selectedOutputId,
    hasPermission: state.hasPermission,
    isEnumerating: state.isEnumerating,
    error: state.error,
    isSupported: AudioDeviceManager.isSupported(),
    requestPermission,
    selectInput,
    selectOutput,
    refresh,
  };
}
