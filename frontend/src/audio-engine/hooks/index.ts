/**
 * ReelForge Audio Engine React Hooks
 *
 * @module audio-engine/hooks
 */

export { useAudioDevices, type UseAudioDevicesReturn } from './useAudioDevices';
export { useAudioRecorder, type UseAudioRecorderReturn } from './useAudioRecorder';
export { useInputMonitor, useInputSpectrum, type UseInputMonitorReturn } from './useInputMonitor';
export { useMidi, useMidiNotes, useMidiCC, useMidiParameter, type UseMidiReturn } from './useMidi';
export {
  useAudioEngineConfig,
  usePerformanceMetrics,
  useLatencyInfo,
  type UseAudioEngineConfigReturn,
} from './useAudioEngineConfig';
