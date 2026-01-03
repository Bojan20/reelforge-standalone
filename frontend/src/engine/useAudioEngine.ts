/**
 * ReelForge Audio Engine React Hook
 *
 * React integration for the AudioEngine.
 * Provides reactive state and channel management.
 *
 * @module engine/useAudioEngine
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import {
  AudioEngine,
  getAudioEngine,
  type ChannelConfig,
  type MeterData,
  type EngineState,
} from './AudioEngine';

// ============ Types ============

export interface ChannelState extends ChannelConfig {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
}

export interface UseAudioEngineResult {
  /** Engine initialization state */
  isInitialized: boolean;
  /** Engine state (playing, time, etc.) */
  state: EngineState;
  /** Channel states with meters */
  channels: Map<string, ChannelState>;
  /** Master meter data */
  masterMeter: MeterData | null;
  /** Initialize engine */
  initialize: () => Promise<void>;
  /** Create channel */
  createChannel: (config: ChannelConfig) => void;
  /** Remove channel */
  removeChannel: (id: string) => void;
  /** Set channel volume */
  setVolume: (id: string, volumeDb: number) => void;
  /** Set channel pan */
  setPan: (id: string, pan: number) => void;
  /** Set channel mute */
  setMute: (id: string, muted: boolean) => void;
  /** Set channel solo */
  setSolo: (id: string, solo: boolean) => void;
  /** Set master volume */
  setMasterVolume: (volumeDb: number) => void;
  /** Load audio buffer to channel */
  loadBuffer: (channelId: string, buffer: AudioBuffer) => void;
  /** Play */
  play: () => void;
  /** Pause */
  pause: () => void;
  /** Stop */
  stop: () => void;
  /** Seek to time */
  seek: (time: number) => void;
  /** Toggle play/pause */
  togglePlay: () => void;
}

// ============ Hook ============

export function useAudioEngine(): UseAudioEngineResult {
  const engineRef = useRef<AudioEngine | null>(null);
  const [isInitialized, setIsInitialized] = useState(false);
  const [state, setState] = useState<EngineState>({
    isPlaying: false,
    currentTime: 0,
    sampleRate: 48000,
    latency: 0,
  });
  const [channels, setChannels] = useState<Map<string, ChannelState>>(
    new Map()
  );
  const [masterMeter, setMasterMeter] = useState<MeterData | null>(null);
  const channelConfigsRef = useRef<Map<string, ChannelConfig>>(new Map());

  // Get or create engine instance
  useEffect(() => {
    engineRef.current = getAudioEngine();

    // Subscribe to events
    const unsubState = engineRef.current.on('statechange', () => {
      if (engineRef.current) {
        setState(engineRef.current.state);
      }
    });

    const unsubMeter = engineRef.current.on('meter', (event) => {
      const meters = event.data as Record<string, MeterData>;

      // Update channel meters
      setChannels((prev) => {
        const next = new Map(prev);
        let changed = false;

        for (const [id, meter] of Object.entries(meters)) {
          if (id === 'master') continue;

          const existing = next.get(id);
          if (existing) {
            next.set(id, {
              ...existing,
              peakL: meter.peakL,
              peakR: meter.peakR,
              rmsL: meter.rmsL,
              rmsR: meter.rmsR,
            });
            changed = true;
          }
        }

        return changed ? next : prev;
      });

      // Update master meter
      if (meters['master']) {
        setMasterMeter(meters['master']);
      }
    });

    // Check if already initialized
    if (engineRef.current.isInitialized) {
      setIsInitialized(true);
      setState(engineRef.current.state);
    }

    return () => {
      unsubState();
      unsubMeter();
    };
  }, []);

  // Initialize engine
  const initialize = useCallback(async () => {
    if (!engineRef.current || isInitialized) return;

    await engineRef.current.initialize();
    setIsInitialized(true);
    setState(engineRef.current.state);
  }, [isInitialized]);

  // Channel management
  const createChannel = useCallback((config: ChannelConfig) => {
    if (!engineRef.current) return;

    engineRef.current.createChannel(config);
    channelConfigsRef.current.set(config.id, config);

    setChannels((prev) => {
      const next = new Map(prev);
      next.set(config.id, {
        ...config,
        peakL: 0,
        peakR: 0,
        rmsL: 0,
        rmsR: 0,
      });
      return next;
    });
  }, []);

  const removeChannel = useCallback((id: string) => {
    if (!engineRef.current) return;

    engineRef.current.removeChannel(id);
    channelConfigsRef.current.delete(id);

    setChannels((prev) => {
      const next = new Map(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const setVolume = useCallback((id: string, volumeDb: number) => {
    if (!engineRef.current) return;

    engineRef.current.setChannelVolume(id, volumeDb);

    // Update config
    const config = channelConfigsRef.current.get(id);
    if (config) {
      config.volume = volumeDb;
    }

    setChannels((prev) => {
      const next = new Map(prev);
      const existing = next.get(id);
      if (existing) {
        next.set(id, { ...existing, volume: volumeDb });
      }
      return next;
    });
  }, []);

  const setPan = useCallback((id: string, pan: number) => {
    if (!engineRef.current) return;

    engineRef.current.setChannelPan(id, pan);

    // Update config
    const config = channelConfigsRef.current.get(id);
    if (config) {
      config.pan = pan;
    }

    setChannels((prev) => {
      const next = new Map(prev);
      const existing = next.get(id);
      if (existing) {
        next.set(id, { ...existing, pan });
      }
      return next;
    });
  }, []);

  const setMute = useCallback((id: string, muted: boolean) => {
    if (!engineRef.current) return;

    engineRef.current.setChannelMute(id, muted);

    // Update config
    const config = channelConfigsRef.current.get(id);
    if (config) {
      config.muted = muted;
    }

    setChannels((prev) => {
      const next = new Map(prev);
      const existing = next.get(id);
      if (existing) {
        next.set(id, { ...existing, muted });
      }
      return next;
    });
  }, []);

  const setSolo = useCallback((id: string, solo: boolean) => {
    if (!engineRef.current) return;

    engineRef.current.setChannelSolo(id, solo);

    // Update config
    const config = channelConfigsRef.current.get(id);
    if (config) {
      config.solo = solo;
    }

    setChannels((prev) => {
      const next = new Map(prev);
      const existing = next.get(id);
      if (existing) {
        next.set(id, { ...existing, solo });
      }
      return next;
    });
  }, []);

  const setMasterVolume = useCallback((volumeDb: number) => {
    if (!engineRef.current) return;
    engineRef.current.setMasterVolume(volumeDb);
  }, []);

  const loadBuffer = useCallback((channelId: string, buffer: AudioBuffer) => {
    if (!engineRef.current) return;
    engineRef.current.loadBufferToChannel(channelId, buffer);
  }, []);

  // Transport
  const play = useCallback(() => {
    engineRef.current?.play();
  }, []);

  const pause = useCallback(() => {
    engineRef.current?.pause();
  }, []);

  const stop = useCallback(() => {
    engineRef.current?.stop();
  }, []);

  const seek = useCallback((time: number) => {
    engineRef.current?.seek(time);
  }, []);

  const togglePlay = useCallback(() => {
    if (engineRef.current?.isPlaying) {
      engineRef.current.pause();
    } else {
      engineRef.current?.play();
    }
  }, []);

  return {
    isInitialized,
    state,
    channels,
    masterMeter,
    initialize,
    createChannel,
    removeChannel,
    setVolume,
    setPan,
    setMute,
    setSolo,
    setMasterVolume,
    loadBuffer,
    play,
    pause,
    stop,
    seek,
    togglePlay,
  };
}

export default useAudioEngine;
