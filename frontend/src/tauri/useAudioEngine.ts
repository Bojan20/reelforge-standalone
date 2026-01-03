/**
 * React hook for Tauri audio engine
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import * as audio from './audio';

export interface UseAudioEngineOptions {
  autoInit?: boolean;
  sampleRate?: number;
  bufferSize?: number;
  meterUpdateInterval?: number;
}

export interface UseAudioEngineResult {
  // Status
  isInitialized: boolean;
  isRunning: boolean;
  sampleRate: number;
  bufferSize: number;
  error: string | null;

  // Meters
  channelMeters: audio.ChannelMeters[];
  masterMeters: audio.MasterMeters | null;

  // Transport
  isPlaying: boolean;
  position: number;

  // Actions
  init: (sampleRate?: number, bufferSize?: number) => Promise<void>;
  start: () => Promise<void>;
  stop: () => Promise<void>;
  play: () => Promise<void>;
  pause: () => Promise<void>;
  setPosition: (samples: number) => Promise<void>;

  // Mixer
  setChannelVolume: (channel: audio.ChannelId, db: number) => Promise<void>;
  setChannelPan: (channel: audio.ChannelId, pan: number) => Promise<void>;
  setChannelMute: (channel: audio.ChannelId, mute: boolean) => Promise<void>;
  setChannelSolo: (channel: audio.ChannelId, solo: boolean) => Promise<void>;
  setMasterVolume: (db: number) => Promise<void>;
  setMasterLimiter: (enabled: boolean, ceiling: number) => Promise<void>;
}

const DEFAULT_CHANNEL_METERS: audio.ChannelMeters = {
  peak_l: -60,
  peak_r: -60,
  rms_l: -60,
  rms_r: -60,
  gain_reduction: 0,
};

export function useAudioEngine(options: UseAudioEngineOptions = {}): UseAudioEngineResult {
  const {
    autoInit = true,
    sampleRate: defaultSampleRate = 48000,
    bufferSize: defaultBufferSize = 256,
    meterUpdateInterval = 50, // 20fps polling
  } = options;

  // State
  const [isInitialized, setIsInitialized] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [sampleRate, setSampleRate] = useState(defaultSampleRate);
  const [bufferSize, setBufferSize] = useState(defaultBufferSize);
  const [error, setError] = useState<string | null>(null);

  const [channelMeters, setChannelMeters] = useState<audio.ChannelMeters[]>(
    Array(6).fill(null).map(() => ({ ...DEFAULT_CHANNEL_METERS }))
  );
  const [masterMeters, setMasterMeters] = useState<audio.MasterMeters | null>(null);

  const [isPlaying, setIsPlaying] = useState(false);
  const [position, setPosition] = useState(0);

  const meterIntervalRef = useRef<number | null>(null);
  const eventUnlistenRef = useRef<UnlistenFn | null>(null);

  // Initialize audio engine
  const init = useCallback(async (sr?: number, bs?: number) => {
    if (!audio.isTauri()) {
      console.log('[useAudioEngine] Not running in Tauri, skipping init');
      return;
    }

    try {
      setError(null);
      const status = await audio.initAudioEngine(sr || defaultSampleRate, bs || defaultBufferSize);
      setIsInitialized(true);
      setIsRunning(status.running);
      setSampleRate(status.sample_rate);
      setBufferSize(status.buffer_size);
      console.log('[useAudioEngine] Audio engine initialized:', status);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
      console.error('[useAudioEngine] Init failed:', msg);
    }
  }, [defaultSampleRate, defaultBufferSize]);

  // Start audio
  const start = useCallback(async () => {
    if (!audio.isTauri()) return;
    try {
      await audio.startAudio();
      setIsRunning(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  // Stop audio
  const stop = useCallback(async () => {
    if (!audio.isTauri()) return;
    try {
      await audio.stopAudio();
      setIsRunning(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  // Transport controls
  const play = useCallback(async () => {
    if (!audio.isTauri()) return;
    try {
      await audio.play();
      setIsPlaying(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  const pause = useCallback(async () => {
    if (!audio.isTauri()) return;
    try {
      await audio.stop();
      setIsPlaying(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  const setPositionFn = useCallback(async (samples: number) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setPosition(samples);
      setPosition(samples);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  // Mixer controls
  const setChannelVolume = useCallback(async (channel: audio.ChannelId, db: number) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setChannelVolume(channel, db);
    } catch (e) {
      console.error('[useAudioEngine] setChannelVolume failed:', e);
    }
  }, []);

  const setChannelPan = useCallback(async (channel: audio.ChannelId, pan: number) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setChannelPan(channel, pan);
    } catch (e) {
      console.error('[useAudioEngine] setChannelPan failed:', e);
    }
  }, []);

  const setChannelMute = useCallback(async (channel: audio.ChannelId, mute: boolean) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setChannelMute(channel, mute);
    } catch (e) {
      console.error('[useAudioEngine] setChannelMute failed:', e);
    }
  }, []);

  const setChannelSolo = useCallback(async (channel: audio.ChannelId, solo: boolean) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setChannelSolo(channel, solo);
    } catch (e) {
      console.error('[useAudioEngine] setChannelSolo failed:', e);
    }
  }, []);

  const setMasterVolume = useCallback(async (db: number) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setMasterVolume(db);
    } catch (e) {
      console.error('[useAudioEngine] setMasterVolume failed:', e);
    }
  }, []);

  const setMasterLimiter = useCallback(async (enabled: boolean, ceiling: number) => {
    if (!audio.isTauri()) return;
    try {
      await audio.setMasterLimiter(enabled, ceiling);
    } catch (e) {
      console.error('[useAudioEngine] setMasterLimiter failed:', e);
    }
  }, []);

  // Setup meter event listener
  useEffect(() => {
    if (!audio.isTauri()) return;

    // Listen for meter events from Rust
    const setupListener = async () => {
      try {
        eventUnlistenRef.current = await listen<audio.AllMeters>('meters', (event) => {
          const meters = event.payload;
          setChannelMeters(meters.channels);
          setMasterMeters(meters.master);
        });
      } catch (e) {
        console.error('[useAudioEngine] Failed to setup meter listener:', e);
      }
    };

    setupListener();

    // Fallback: poll meters if events aren't working
    meterIntervalRef.current = window.setInterval(async () => {
      if (!isRunning) return;
      try {
        const meters = await audio.getMeters();
        if (meters) {
          setChannelMeters(meters.channels);
          setMasterMeters(meters.master);
        }
      } catch {
        // Ignore polling errors
      }
    }, meterUpdateInterval);

    return () => {
      if (eventUnlistenRef.current) {
        eventUnlistenRef.current();
      }
      if (meterIntervalRef.current) {
        clearInterval(meterIntervalRef.current);
      }
    };
  }, [isRunning, meterUpdateInterval]);

  // Auto-init
  useEffect(() => {
    if (autoInit && audio.isTauri()) {
      init();
    }
  }, [autoInit, init]);

  return {
    isInitialized,
    isRunning,
    sampleRate,
    bufferSize,
    error,
    channelMeters,
    masterMeters,
    isPlaying,
    position,
    init,
    start,
    stop,
    play,
    pause,
    setPosition: setPositionFn,
    setChannelVolume,
    setChannelPan,
    setChannelMute,
    setChannelSolo,
    setMasterVolume,
    setMasterLimiter,
  };
}
