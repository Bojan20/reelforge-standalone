/**
 * AudioEngine Types
 *
 * Shared types used across AudioEngine modules.
 * Re-exports core types for convenience.
 *
 * @module core/audioEngine/types
 */

import type { BusId } from '../types';

/**
 * Core AudioEngine state that modules need access to.
 * Contains refs to WebAudio nodes and React state.
 */
export interface AudioEngineState {
  audioContextRef: React.MutableRefObject<AudioContext | null>;
  audioSourceRef: React.MutableRefObject<AudioBufferSourceNode | null>;
  gainNodeRef: React.MutableRefObject<GainNode | null>;
  panNodeRef: React.MutableRefObject<StereoPannerNode | null>;
  audioRef: React.MutableRefObject<HTMLAudioElement | null>;
  eventAudioRefsMap: React.MutableRefObject<Map<string, HTMLAudioElement[]>>;
  soundAudioMap: React.MutableRefObject<Map<string, {
    audio: HTMLAudioElement;
    gainNode?: GainNode;
    source?: AudioBufferSourceNode;
    panNode?: StereoPannerNode;
    eventId?: string;
    instanceKey?: string;
    voiceKey?: string;
  }[]>>;
  busGainsRef: React.MutableRefObject<Record<BusId, GainNode> | null>;
  masterGainRef: React.MutableRefObject<GainNode | null>;
  masterInsertConnected?: boolean;
}

/**
 * Voice instance tracking for concurrency management.
 */
export interface VoiceInstance {
  audio: HTMLAudioElement;
  gainNode?: GainNode;
  source?: AudioBufferSourceNode;
  panNode?: StereoPannerNode;
  eventId?: string;
  instanceKey?: string;
  voiceKey?: string;
}

// Re-export commonly used types from parent
export type { BusId } from '../types';
export type { MixSnapshot, ControlBus } from '../types';
