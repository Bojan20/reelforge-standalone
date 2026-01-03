/**
 * useAudioEngine - Custom hook for audio playback logic
 *
 * Separates audio engine logic from UI components
 */

import { useRef, useCallback, useMemo } from 'react';
import { AudioEngine, type AudioEngineState } from '../core/audioEngine';
import type { AudioFileObject, GameEvent, BusId, ReelForgeProject } from '../core/types';

export function useAudioEngine(
  audioFiles: AudioFileObject[],
  setIsPlaying: (playing: boolean) => void,
  setCurrentPlayingSound: (sound: string) => void,
  setPlayingEvents: React.Dispatch<React.SetStateAction<Set<string>>>
) {
  // Audio refs
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const audioSourceRef = useRef<AudioBufferSourceNode | null>(null);
  const gainNodeRef = useRef<GainNode | null>(null);
  const panNodeRef = useRef<StereoPannerNode | null>(null);
  const eventAudioRefsMap = useRef<Map<string, HTMLAudioElement[]>>(new Map());
  const soundAudioMap = useRef<
    Map<
      string,
      {
        audio: HTMLAudioElement;
        gainNode?: GainNode;
        source?: AudioBufferSourceNode;
        panNode?: StereoPannerNode;
        eventId?: string;
        instanceKey?: string;
      }[]
    >
  >(new Map());
  const busGainsRef = useRef<Record<BusId, GainNode> | null>(null);
  const masterGainRef = useRef<GainNode | null>(null);

  // Create audio engine state
  const audioEngineState: AudioEngineState = useMemo(
    () => ({
      audioContextRef,
      audioSourceRef,
      gainNodeRef,
      panNodeRef,
      audioRef,
      eventAudioRefsMap,
      soundAudioMap,
      busGainsRef,
      masterGainRef,
    }),
    []
  );

  // Create audio engine instance
  const audioEngine = useMemo(
    () =>
      new AudioEngine(
        audioFiles,
        audioEngineState,
        setIsPlaying,
        setCurrentPlayingSound,
        setPlayingEvents
      ),
    [audioFiles, audioEngineState, setIsPlaying, setCurrentPlayingSound, setPlayingEvents]
  );

  // Update audio files when they change
  const updateAudioFiles = useCallback(
    (newFiles: AudioFileObject[]) => {
      audioEngine.updateAudioFiles(newFiles);
    },
    [audioEngine]
  );

  // Play sound
  const playSound = useCallback(
    async (
      soundId: string,
      volume = 1,
      loop = false,
      currentPlayingSound: string,
      isPlaying: boolean,
      bus: BusId = 'sfx',
      pan = 0
    ) => {
      return audioEngine.playSound(soundId, volume, loop, currentPlayingSound, isPlaying, bus, pan);
    },
    [audioEngine]
  );

  // Play event
  const playEvent = useCallback(
    (event: GameEvent, project?: ReelForgeProject) => {
      audioEngine.playEvent(event, project);
    },
    [audioEngine]
  );

  // Stop event
  const stopEvent = useCallback(
    (event: GameEvent) => {
      audioEngine.stopEvent(event);
    },
    [audioEngine]
  );

  // Stop all audio
  const stopAllAudio = useCallback(() => {
    audioEngine.stopAllAudio();
  }, [audioEngine]);

  // Set bus volume
  const setBusVolume = useCallback(
    (bus: BusId, volume: number) => {
      audioEngine.setBusVolume(bus, volume);
    },
    [audioEngine]
  );

  // Get bus volume
  const getBusVolume = useCallback(
    (bus: BusId): number => {
      return audioEngine.getBusVolume(bus);
    },
    [audioEngine]
  );

  // Reroute sound to bus
  const rerouteSoundToBus = useCallback(
    (soundId: string, newBus: BusId) => {
      audioEngine.rerouteSoundToBus(soundId, newBus);
    },
    [audioEngine]
  );

  // Preload audio files
  const preloadAudioFiles = useCallback(
    async (soundIds?: string[]) => {
      return audioEngine.preloadAudioFiles(soundIds);
    },
    [audioEngine]
  );

  // Get cache stats
  const getCacheStats = useCallback(() => {
    return audioEngine.getCacheStats();
  }, [audioEngine]);

  // Clear cache
  const clearCache = useCallback(() => {
    audioEngine.clearCache();
  }, [audioEngine]);

  return {
    audioEngine,
    audioEngineState,
    updateAudioFiles,
    playSound,
    playEvent,
    stopEvent,
    stopAllAudio,
    setBusVolume,
    getBusVolume,
    rerouteSoundToBus,
    preloadAudioFiles,
    getCacheStats,
    clearCache,
  };
}
