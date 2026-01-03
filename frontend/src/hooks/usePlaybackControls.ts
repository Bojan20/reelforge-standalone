/**
 * usePlaybackControls Hook
 *
 * Manages audio playback controls for events and sounds.
 * Extracted from EventsPage to reduce component complexity.
 */

import { useCallback } from 'react';
import type { AudioEngine } from '../core/audioEngine';
import type { ReelForgeProject, GameEvent } from '../core/types';
import type { EngineClient, EngineStatus } from '../core/engineClient';

export interface UsePlaybackControlsOptions {
  audioEngine: AudioEngine;
  project: ReelForgeProject | null;
  selectedEvent: GameEvent | undefined;
  currentPlayingSound: string;
  isPlaying: boolean;
  engineClientRef: React.MutableRefObject<EngineClient | null>;
  engineStatus: EngineStatus;
}

export interface UsePlaybackControlsReturn {
  handlePlaySound: (soundId: string, volume?: number, loop?: boolean) => Promise<void>;
  handlePlayEvent: () => void;
  handleStopEvent: () => void;
  handleStopAllEvents: () => void;
}

export function usePlaybackControls({
  audioEngine,
  project,
  selectedEvent,
  currentPlayingSound,
  isPlaying,
  engineClientRef,
  engineStatus,
}: UsePlaybackControlsOptions): UsePlaybackControlsReturn {
  const handlePlaySound = useCallback(async (soundId: string, volume: number = 1, loop: boolean = false) => {
    if (!project) {
      await audioEngine.playSound(soundId, volume, loop, currentPlayingSound, isPlaying);
      return;
    }

    const sprite = project.spriteItems.find(s => s.soundId === soundId);
    const bus = sprite?.bus ?? 'sfx';

    await audioEngine.playSound(soundId, volume, loop, currentPlayingSound, isPlaying, bus);
  }, [audioEngine, project, currentPlayingSound, isPlaying]);

  const handlePlayEvent = useCallback(() => {
    if (!selectedEvent || !project) return;
    audioEngine.playEvent(selectedEvent, project);

    if (engineClientRef.current && engineStatus === 'connected') {
      engineClientRef.current.triggerEvent(selectedEvent.eventName);
    }
  }, [audioEngine, selectedEvent, project, engineClientRef, engineStatus]);

  const handleStopEvent = useCallback(() => {
    audioEngine.stopEvent(selectedEvent || null);
  }, [audioEngine, selectedEvent]);

  const handleStopAllEvents = useCallback(() => {
    audioEngine.stopAllAudio();
  }, [audioEngine]);

  return {
    handlePlaySound,
    handlePlayEvent,
    handleStopEvent,
    handleStopAllEvents,
  };
}
