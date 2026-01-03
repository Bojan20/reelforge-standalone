/**
 * ReelForge Audio Engine
 *
 * Comprehensive audio engine for professional DAW:
 * - Audio device management
 * - Recording system
 * - Input monitoring
 * - Spectrum analysis
 * - MIDI integration
 * - Performance monitoring
 *
 * @module audio-engine
 */

// Audio Device Management
export {
  AudioDeviceManager,
  type AudioDeviceInfo,
  type AudioDeviceState,
} from './AudioDeviceManager';

// Audio Recording
export {
  AudioRecorder,
  type RecordingFormat,
  type RecordingState,
  type RecordingOptions,
  type RecordingResult,
  type RecorderState,
} from './AudioRecorder';

// Input Monitoring
export {
  InputMonitor,
  type InputLevels,
  type SpectrumData,
  type InputMonitorState,
} from './InputMonitor';

// Spectrum Analysis
export {
  SpectrumAnalyzerEngine,
  frequencyToNote,
  noteToFrequency,
  formatFrequency,
  formatDecibels,
  type SpectrumScale,
  type SpectrumMode,
  type WindowFunction,
  type SpectrumConfig,
  type SpectrumBand,
  type SpectrumFrame,
} from './SpectrumAnalyzerEngine';

// MIDI Management
export {
  MidiManager,
  midiNoteToName,
  noteNameToMidi,
  velocityToDb,
  dbToVelocity,
  type MidiDevice,
  type MidiNoteEvent,
  type MidiCCEvent,
  type MidiPitchBendEvent,
  type MidiClockEvent,
  type MidiEvent,
  type MidiMapping,
  type MidiManagerState,
} from './MidiManager';

// Engine Configuration & Performance
export {
  AudioEngineConfig,
  type BufferSize,
  type SampleRate,
  type AudioEngineSettings,
  type PerformanceMetrics,
} from './AudioEngineConfig';

// React Hooks
export {
  useAudioDevices,
  useAudioRecorder,
  useInputMonitor,
  useInputSpectrum,
  useMidi,
  useMidiNotes,
  useMidiCC,
  useMidiParameter,
  useAudioEngineConfig,
  usePerformanceMetrics,
  useLatencyInfo,
} from './hooks';

// Re-export from core
export { AudioContextManager, getSharedAudioContext, ensureAudioContextResumed } from '../core/AudioContextManager';
