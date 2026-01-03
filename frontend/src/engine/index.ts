/**
 * ReelForge Audio Engine Module
 *
 * Core audio processing with Web Audio API.
 *
 * @module engine
 */

export {
  AudioEngine,
  getAudioEngine,
} from './AudioEngine';

export type {
  ChannelConfig,
  ChannelNode,
  MeterData,
  EngineState,
  EngineEventType,
  EngineEvent,
} from './AudioEngine';

export {
  useAudioEngine,
} from './useAudioEngine';

export type {
  ChannelState,
  UseAudioEngineResult,
} from './useAudioEngine';
