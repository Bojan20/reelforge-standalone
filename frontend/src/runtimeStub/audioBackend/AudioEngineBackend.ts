/**
 * AudioEngineBackend - Wrapper around existing Studio AudioEngine
 *
 * Implements AudioBackend interface to allow RuntimeStub to work
 * with the existing WebAudio-based AudioEngine.
 *
 * No React dependencies in this file.
 */

import type { AudioBackend, AdapterCommand, BusId, AssetResolver } from "./types";
import type { AudioEngine } from "../../core/audioEngine";
import { AudioContextManager } from "../../core/AudioContextManager";

/** Internal voice info */
interface VoiceInfo {
  assetId: string;
  bus: BusId;
  source: AudioBufferSourceNode | null;
  gainNode: GainNode | null;
  baseGain: number;
}

/** Map Studio BusId to our BusId */
function mapBusId(bus: BusId): "master" | "music" | "sfx" | "ambience" | "voice" {
  switch (bus) {
    case "Master": return "master";
    case "Music": return "music";
    case "SFX": return "sfx";
    case "UI": return "sfx"; // UI maps to sfx
    case "VO": return "voice";
    default: return "sfx";
  }
}

/**
 * AudioEngineBackend - Wraps existing AudioEngine for RuntimeStub
 */
export class AudioEngineBackend implements AudioBackend {
  private audioEngine: AudioEngine;
  private resolver: AssetResolver;

  /** voiceId -> VoiceInfo */
  private voiceMap: Map<string, VoiceInfo> = new Map();

  /** voiceId -> timeoutId for scheduled playback */
  private pendingTimers: Map<string, ReturnType<typeof setTimeout>> = new Map();

  /** Bus gains */
  private busGains: Record<BusId, number> = {
    Master: 1.0,
    Music: 1.0,
    SFX: 1.0,
    UI: 1.0,
    VO: 1.0,
  };

  /** Monotonic voice counter */
  private voiceCounter: number = 0;

  /** AudioContext reference (from AudioEngine) */
  private audioContext: AudioContext | null = null;

  /** Cached audio buffers */
  private bufferCache: Map<string, AudioBuffer> = new Map();

  /** DEV mode flag */
  private isDev: boolean = false;

  constructor(audioEngine: AudioEngine, resolver: AssetResolver, isDev: boolean = false) {
    this.audioEngine = audioEngine;
    this.resolver = resolver;
    this.isDev = isDev;
  }

  /**
   * Preload audio assets
   */
  async preload(assetIds: string[]): Promise<void> {
    // Dedupe
    const uniqueIds = [...new Set(assetIds)];

    // Get AudioContext from singleton manager
    if (!this.audioContext) {
      this.audioContext = AudioContextManager.getContext();
    }

    // Preload each asset
    const loadPromises = uniqueIds.map(async (assetId) => {
      if (this.bufferCache.has(assetId)) {
        return; // Already cached
      }

      const url = this.resolver.resolveUrl(assetId);
      if (!url) {
        console.warn(`[AudioEngineBackend] No URL for assetId: ${assetId}`);
        return;
      }

      try {
        const response = await fetch(url);
        const arrayBuffer = await response.arrayBuffer();
        const audioBuffer = await this.audioContext!.decodeAudioData(arrayBuffer);
        this.bufferCache.set(assetId, audioBuffer);
      } catch (err) {
        console.error(`[AudioEngineBackend] Failed to preload ${assetId}:`, err);
      }
    });

    await Promise.all(loadPromises);
  }

  /**
   * Execute commands sequentially
   */
  execute(commands: AdapterCommand[]): Map<number, string> {
    const voiceIds = new Map<number, string>();

    for (let i = 0; i < commands.length; i++) {
      const cmd = commands[i];

      switch (cmd.type) {
        case "Play": {
          const voiceId = this.handlePlay(cmd);
          voiceIds.set(i, voiceId);
          break;
        }

        case "Stop": {
          this.handleStop(cmd.voiceId);
          break;
        }

        case "StopAll": {
          this.handleStopAll();
          break;
        }

        case "SetBusGain": {
          this.handleSetBusGain(cmd.bus, cmd.gain);
          break;
        }
      }
    }

    return voiceIds;
  }

  /**
   * Handle Play command
   */
  private handlePlay(cmd: AdapterCommand & { type: "Play" }): string {
    const voiceId = `voice_${++this.voiceCounter}`;

    const buffer = this.bufferCache.get(cmd.assetId);
    if (!buffer) {
      console.warn(`[AudioEngineBackend] Buffer not found for: ${cmd.assetId}`);
      return voiceId;
    }

    // Calculate effective gain
    const effectiveGain = this.calculateEffectiveGain(cmd.gain, cmd.bus);

    // Check if scheduled for future
    if (cmd.startTimeMs !== undefined && cmd.startTimeMs > 0) {
      const now = Date.now();
      const delay = cmd.startTimeMs - now;

      if (delay > 0) {
        // Schedule for later
        const timerId = setTimeout(() => {
          this.pendingTimers.delete(voiceId);
          this.startPlayback(voiceId, cmd.assetId, buffer, cmd.bus, cmd.gain, effectiveGain, cmd.loop);
        }, delay);

        this.pendingTimers.set(voiceId, timerId);

        // Create placeholder voice info
        this.voiceMap.set(voiceId, {
          assetId: cmd.assetId,
          bus: cmd.bus,
          source: null,
          gainNode: null,
          baseGain: cmd.gain,
        });

        return voiceId;
      }
    }

    // Immediate playback
    this.startPlayback(voiceId, cmd.assetId, buffer, cmd.bus, cmd.gain, effectiveGain, cmd.loop);
    return voiceId;
  }

  /**
   * Start actual playback
   */
  private startPlayback(
    voiceId: string,
    assetId: string,
    buffer: AudioBuffer,
    bus: BusId,
    baseGain: number,
    effectiveGain: number,
    loop: boolean
  ): void {
    if (!this.audioContext) return;

    // Resume context if suspended
    if (this.audioContext.state === "suspended") {
      this.audioContext.resume();
    }

    const source = this.audioContext.createBufferSource();
    source.buffer = buffer;
    source.loop = loop;

    const gainNode = this.audioContext.createGain();
    gainNode.gain.value = effectiveGain;

    // Connect to bus via AudioEngine
    const studioBus = mapBusId(bus);
    // @ts-ignore - accessing private getBusInput
    const busInput = this.audioEngine["getBusInput"]?.(studioBus);
    if (busInput) {
      source.connect(gainNode);
      gainNode.connect(busInput);
    } else {
      // Fallback to destination
      source.connect(gainNode);
      gainNode.connect(this.audioContext.destination);
    }

    source.start(0);

    // Store voice info
    this.voiceMap.set(voiceId, {
      assetId,
      bus,
      source,
      gainNode,
      baseGain,
    });

    // Cleanup on end for non-looping
    if (!loop) {
      source.onended = () => {
        this.voiceMap.delete(voiceId);
      };
    }
  }

  /**
   * Handle Stop command
   */
  private handleStop(voiceId: string): void {
    // Cancel pending timer if scheduled
    const timerId = this.pendingTimers.get(voiceId);
    if (timerId) {
      clearTimeout(timerId);
      this.pendingTimers.delete(voiceId);
    }

    // Stop playing voice
    const voice = this.voiceMap.get(voiceId);
    if (voice?.source) {
      try {
        voice.source.stop();
      } catch {
        // Already stopped
      }
    }

    this.voiceMap.delete(voiceId);
  }

  /**
   * Handle StopAll command
   */
  private handleStopAll(): void {
    // Cancel ALL pending timers first
    for (const timerId of this.pendingTimers.values()) {
      clearTimeout(timerId);
    }
    this.pendingTimers.clear();

    // Stop all active voices
    for (const voice of this.voiceMap.values()) {
      if (voice.source) {
        try {
          voice.source.stop();
        } catch {
          // Already stopped
        }
      }
    }
    this.voiceMap.clear();

    // Also call AudioEngine stopAll for any sounds it manages
    this.audioEngine.stopAllAudio();

    // M6.3 invariant check (dev only)
    if (this.isDev) {
      console.assert(
        this.voiceMap.size === 0,
        `[AudioEngineBackend] M6.3 INVARIANT VIOLATED: voiceMap not empty after StopAll`
      );
      console.assert(
        this.pendingTimers.size === 0,
        `[AudioEngineBackend] M6.3 INVARIANT VIOLATED: pendingTimers not empty after StopAll`
      );
    }
  }

  /**
   * Handle SetBusGain command
   */
  private handleSetBusGain(bus: BusId, gain: number): void {
    this.busGains[bus] = gain;

    // Update AudioEngine bus volume
    const studioBus = mapBusId(bus);
    this.audioEngine.setBusVolume(studioBus, gain);

    // Update currently playing voices on this bus
    for (const voice of this.voiceMap.values()) {
      if (voice.bus === bus || bus === "Master") {
        if (voice.gainNode) {
          const effectiveGain = this.calculateEffectiveGain(voice.baseGain, voice.bus);
          voice.gainNode.gain.value = effectiveGain;
        }
      }
    }
  }

  /**
   * Calculate effective gain
   */
  private calculateEffectiveGain(baseGain: number, bus: BusId): number {
    return baseGain * this.busGains[bus] * this.busGains["Master"];
  }

  /**
   * Get statistics
   */
  getStats(): {
    activeVoices: number;
    pendingTimers: number;
    busGains: Record<BusId, number>;
  } {
    return {
      activeVoices: this.voiceMap.size,
      pendingTimers: this.pendingTimers.size,
      busGains: { ...this.busGains },
    };
  }
}
