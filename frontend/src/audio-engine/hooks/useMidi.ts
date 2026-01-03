/**
 * ReelForge useMidi Hook
 *
 * React hook for MIDI device and event management.
 *
 * @module audio-engine/hooks/useMidi
 */

import { useState, useEffect, useCallback } from 'react';
import {
  MidiManager,
  type MidiDevice,
  type MidiNoteEvent,
  type MidiCCEvent,
  type MidiManagerState,
} from '../MidiManager';

export interface UseMidiReturn {
  // State
  isSupported: boolean;
  hasAccess: boolean;
  inputs: MidiDevice[];
  outputs: MidiDevice[];
  activeInputs: string[];
  isLearning: boolean;
  learningParameterId: string | null;
  clockBPM: number;
  // Actions
  requestAccess: (sysex?: boolean) => Promise<boolean>;
  enableInput: (deviceId: string) => void;
  disableInput: (deviceId: string) => void;
  enableAllInputs: () => void;
  startLearning: (parameterId: string) => void;
  cancelLearning: () => void;
  // Output
  sendNoteOn: (deviceId: string, channel: number, note: number, velocity: number) => void;
  sendNoteOff: (deviceId: string, channel: number, note: number) => void;
  sendCC: (deviceId: string, channel: number, controller: number, value: number) => void;
}

export function useMidi(): UseMidiReturn {
  const [state, setState] = useState<MidiManagerState>(MidiManager.getState());
  const [clockBPM, setClockBPM] = useState(0);

  useEffect(() => {
    const unsubscribe = MidiManager.onStateChange(setState);
    return unsubscribe;
  }, []);

  // Update clock BPM periodically
  useEffect(() => {
    const interval = setInterval(() => {
      setClockBPM(MidiManager.getClockBPM());
    }, 500);
    return () => clearInterval(interval);
  }, []);

  const requestAccess = useCallback(async (sysex = false) => {
    return MidiManager.requestAccess(sysex);
  }, []);

  const enableInput = useCallback((deviceId: string) => {
    MidiManager.enableInput(deviceId);
  }, []);

  const disableInput = useCallback((deviceId: string) => {
    MidiManager.disableInput(deviceId);
  }, []);

  const enableAllInputs = useCallback(() => {
    MidiManager.enableAllInputs();
  }, []);

  const startLearning = useCallback((parameterId: string) => {
    MidiManager.startLearning(parameterId);
  }, []);

  const cancelLearning = useCallback(() => {
    MidiManager.cancelLearning();
  }, []);

  const sendNoteOn = useCallback((deviceId: string, channel: number, note: number, velocity: number) => {
    MidiManager.sendNoteOn(deviceId, channel, note, velocity);
  }, []);

  const sendNoteOff = useCallback((deviceId: string, channel: number, note: number) => {
    MidiManager.sendNoteOff(deviceId, channel, note);
  }, []);

  const sendCC = useCallback((deviceId: string, channel: number, controller: number, value: number) => {
    MidiManager.sendCC(deviceId, channel, controller, value);
  }, []);

  return {
    isSupported: state.isSupported,
    hasAccess: state.hasAccess,
    inputs: state.inputs,
    outputs: state.outputs,
    activeInputs: Array.from(state.activeInputs),
    isLearning: state.isLearning,
    learningParameterId: state.learningParameterId,
    clockBPM,
    requestAccess,
    enableInput,
    disableInput,
    enableAllInputs,
    startLearning,
    cancelLearning,
    sendNoteOn,
    sendNoteOff,
    sendCC,
  };
}

/**
 * Hook for MIDI note events.
 */
export function useMidiNotes(callback: (event: MidiNoteEvent) => void): void {
  useEffect(() => {
    const unsubscribe = MidiManager.onNoteEvent(callback);
    return unsubscribe;
  }, [callback]);
}

/**
 * Hook for MIDI CC events.
 */
export function useMidiCC(callback: (event: MidiCCEvent) => void): void {
  useEffect(() => {
    const unsubscribe = MidiManager.onCCEvent(callback);
    return unsubscribe;
  }, [callback]);
}

/**
 * Hook to bind a parameter to MIDI control.
 */
export function useMidiParameter(
  parameterId: string,
  onChange: (value: number) => void
): void {
  useEffect(() => {
    const unsubscribe = MidiManager.registerParameter(parameterId, onChange);
    return unsubscribe;
  }, [parameterId, onChange]);
}
