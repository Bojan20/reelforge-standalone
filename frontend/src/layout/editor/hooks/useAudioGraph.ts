/**
 * useAudioGraph - Audio Graph Setup Hook
 *
 * Centralizes Web Audio API graph creation:
 * - AudioContext singleton
 * - Master gain node
 * - Bus gain nodes (SFX, Music, Voice, Ambient)
 * - Bus panner nodes
 * - Voice tracking for cleanup
 *
 * @module layout/editor/hooks/useAudioGraph
 */

import { useMemo, useRef, useCallback } from 'react';
import { AudioContextManager } from '../../../core/AudioContextManager';
import { rfDebug } from '../../../core/dspMetrics';
import { DEMO_BUSES, MAX_VOICES } from '../constants';

// ============ Types ============

export interface ActiveVoice {
  source: AudioBufferSourceNode;
  gainNode: GainNode;
  assetId: string;
  startTime: number;
}

export interface AudioGraphReturn {
  /** Shared AudioContext singleton */
  audioContext: AudioContext;
  /** Master gain node (final output) */
  masterGain: GainNode;
  /** Bus gain nodes by bus ID */
  busGains: Record<string, GainNode>;
  /** Bus panner nodes by bus ID */
  busPanners: Record<string, StereoPannerNode>;
  /** Active voices map ref */
  activeVoicesRef: React.MutableRefObject<Map<string, ActiveVoice[]>>;
  /** Play a buffer on a bus */
  playBuffer: (
    buffer: AudioBuffer,
    busId: string,
    assetId: string,
    options?: PlayBufferOptions
  ) => ActiveVoice | null;
  /** Stop all voices for an asset */
  stopAsset: (assetId: string, fadeTime?: number) => void;
  /** Stop all voices on a bus */
  stopBus: (busId: string, fadeTime?: number) => void;
  /** Stop all voices */
  stopAll: (fadeTime?: number) => void;
  /** Set bus volume */
  setBusVolume: (busId: string, volume: number) => void;
  /** Set bus pan */
  setBusPan: (busId: string, pan: number) => void;
  /** Get voice count */
  getVoiceCount: () => number;
}

export interface PlayBufferOptions {
  gain?: number;
  loop?: boolean;
  startOffset?: number;
  duration?: number;
  fadeIn?: number;
  fadeOut?: number;
}

// ============ Hook ============

export function useAudioGraph(): AudioGraphReturn {
  // AudioContext singleton
  const audioContext = useMemo(() => {
    const ctx = AudioContextManager.getContext();
    rfDebug('AudioGraph', 'Context obtained, state:', ctx.state);
    return ctx;
  }, []);

  // Master gain node
  const masterGain = useMemo(() => {
    const gain = audioContext.createGain();
    gain.gain.value = 1;
    gain.connect(audioContext.destination);
    rfDebug('AudioGraph', 'Master gain connected');
    return gain;
  }, [audioContext]);

  // Bus gain nodes
  const busGains = useMemo(() => {
    const gains: Record<string, GainNode> = {};
    for (const bus of DEMO_BUSES) {
      if (bus.isMaster) {
        gains[bus.id] = masterGain;
      } else {
        const busGain = audioContext.createGain();
        busGain.gain.value = bus.volume;
        busGain.connect(masterGain);
        gains[bus.id] = busGain;
      }
    }
    return gains;
  }, [audioContext, masterGain]);

  // Bus panner nodes
  const busPanners = useMemo(() => {
    const panners: Record<string, StereoPannerNode> = {};
    for (const bus of DEMO_BUSES) {
      if (!bus.isMaster) {
        const panner = audioContext.createStereoPanner();
        panner.pan.value = bus.pan;
        // Rewire: busGain → panner → masterGain
        const busGain = busGains[bus.id];
        if (busGain) {
          busGain.disconnect();
          busGain.connect(panner);
          panner.connect(masterGain);
        }
        panners[bus.id] = panner;
      }
    }
    return panners;
  }, [audioContext, masterGain, busGains]);

  // Active voices tracking
  const activeVoicesRef = useRef<Map<string, ActiveVoice[]>>(new Map());

  // Voice cleanup helper
  const cleanupVoice = useCallback((voice: ActiveVoice) => {
    try {
      voice.source.stop();
      voice.source.disconnect();
      voice.gainNode.disconnect();
    } catch {
      // Already stopped
    }
  }, []);

  // Enforce voice limit
  const enforceVoiceLimit = useCallback(() => {
    let totalVoices = 0;
    for (const voices of activeVoicesRef.current.values()) {
      totalVoices += voices.length;
    }

    if (totalVoices > MAX_VOICES) {
      // Kill oldest voices first
      const allVoices: ActiveVoice[] = [];
      for (const voices of activeVoicesRef.current.values()) {
        allVoices.push(...voices);
      }
      allVoices.sort((a, b) => a.startTime - b.startTime);

      const toKill = allVoices.slice(0, totalVoices - MAX_VOICES);
      for (const voice of toKill) {
        cleanupVoice(voice);
        const voices = activeVoicesRef.current.get(voice.assetId);
        if (voices) {
          const idx = voices.indexOf(voice);
          if (idx >= 0) voices.splice(idx, 1);
        }
      }
      rfDebug('AudioGraph', `Killed ${toKill.length} voices to stay under limit`);
    }
  }, [cleanupVoice]);

  // Play buffer on bus
  const playBuffer = useCallback((
    buffer: AudioBuffer,
    busId: string,
    assetId: string,
    options: PlayBufferOptions = {}
  ): ActiveVoice | null => {
    const busGain = busGains[busId];
    if (!busGain) {
      rfDebug('AudioGraph', `Unknown bus: ${busId}`);
      return null;
    }

    // Enforce voice limit before creating new
    enforceVoiceLimit();

    const {
      gain = 1,
      loop = false,
      startOffset = 0,
      duration,
      fadeIn = 0,
      fadeOut = 0,
    } = options;

    // Create source
    const source = audioContext.createBufferSource();
    source.buffer = buffer;
    source.loop = loop;

    // Create voice gain
    const voiceGain = audioContext.createGain();
    voiceGain.gain.value = fadeIn > 0 ? 0 : gain;

    // Connect: source → voiceGain → busGain
    source.connect(voiceGain);
    voiceGain.connect(busGain);

    // Fade in
    if (fadeIn > 0) {
      voiceGain.gain.setValueAtTime(0, audioContext.currentTime);
      voiceGain.gain.linearRampToValueAtTime(gain, audioContext.currentTime + fadeIn);
    }

    // Fade out (if duration specified)
    if (fadeOut > 0 && duration !== undefined) {
      const fadeOutStart = audioContext.currentTime + duration - fadeOut;
      voiceGain.gain.setValueAtTime(gain, fadeOutStart);
      voiceGain.gain.linearRampToValueAtTime(0, fadeOutStart + fadeOut);
    }

    // Create voice record
    const voice: ActiveVoice = {
      source,
      gainNode: voiceGain,
      assetId,
      startTime: audioContext.currentTime,
    };

    // Track voice
    if (!activeVoicesRef.current.has(assetId)) {
      activeVoicesRef.current.set(assetId, []);
    }
    activeVoicesRef.current.get(assetId)!.push(voice);

    // Cleanup on end
    source.onended = () => {
      const voices = activeVoicesRef.current.get(assetId);
      if (voices) {
        const idx = voices.indexOf(voice);
        if (idx >= 0) voices.splice(idx, 1);
      }
      voiceGain.disconnect();
    };

    // Start playback
    if (duration !== undefined) {
      source.start(0, startOffset, duration);
    } else {
      source.start(0, startOffset);
    }

    return voice;
  }, [audioContext, busGains, enforceVoiceLimit]);

  // Stop asset
  const stopAsset = useCallback((assetId: string, fadeTime = 0) => {
    const voices = activeVoicesRef.current.get(assetId);
    if (!voices || voices.length === 0) return;

    for (const voice of voices) {
      if (fadeTime > 0) {
        voice.gainNode.gain.setValueAtTime(voice.gainNode.gain.value, audioContext.currentTime);
        voice.gainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + fadeTime);
        setTimeout(() => cleanupVoice(voice), fadeTime * 1000);
      } else {
        cleanupVoice(voice);
      }
    }
    activeVoicesRef.current.delete(assetId);
  }, [audioContext, cleanupVoice]);

  // Stop bus
  const stopBus = useCallback((_busId: string, fadeTime = 0) => {
    for (const assetId of activeVoicesRef.current.keys()) {
      // Note: We'd need to track which bus each voice is on
      // For now, stop all
      stopAsset(assetId, fadeTime);
    }
  }, [stopAsset]);

  // Stop all
  const stopAll = useCallback((fadeTime = 0) => {
    for (const assetId of activeVoicesRef.current.keys()) {
      stopAsset(assetId, fadeTime);
    }
  }, [stopAsset]);

  // Set bus volume
  const setBusVolume = useCallback((busId: string, volume: number) => {
    const busGain = busGains[busId];
    if (busGain) {
      busGain.gain.setValueAtTime(volume, audioContext.currentTime);
    }
  }, [audioContext, busGains]);

  // Set bus pan
  const setBusPan = useCallback((busId: string, pan: number) => {
    const panner = busPanners[busId];
    if (panner) {
      panner.pan.setValueAtTime(pan, audioContext.currentTime);
    }
  }, [audioContext, busPanners]);

  // Get voice count
  const getVoiceCount = useCallback(() => {
    let count = 0;
    for (const voices of activeVoicesRef.current.values()) {
      count += voices.length;
    }
    return count;
  }, []);

  return {
    audioContext,
    masterGain,
    busGains,
    busPanners,
    activeVoicesRef,
    playBuffer,
    stopAsset,
    stopBus,
    stopAll,
    setBusVolume,
    setBusPan,
    getVoiceCount,
  };
}

export default useAudioGraph;
