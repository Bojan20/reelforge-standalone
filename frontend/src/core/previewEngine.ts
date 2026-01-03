/**
 * Preview Engine - Centralized audio preview system
 *
 * Provides unified preview capabilities for:
 * - Individual audio assets
 * - Events with action chains
 * - Bus solo/mute preview
 * - Timeline scrubbing
 * - Waveform playhead sync
 *
 * @module core/previewEngine
 */

import { AudioContextManager } from './AudioContextManager';
import type { BusId, AudioFileObject, GameEvent, Command } from './types';

// ============ TYPES ============

export interface PreviewState {
  isPlaying: boolean;
  isPaused: boolean;
  currentTime: number;
  duration: number;
  currentAssetId: string | null;
  currentEventId: string | null;
  looping: boolean;
  volume: number;
  soloedBuses: Set<BusId>;
  mutedBuses: Set<BusId>;
}

export interface PreviewOptions {
  volume?: number;
  loop?: boolean;
  bus?: BusId;
  startTime?: number;
  endTime?: number;
  fadeIn?: number;
  fadeOut?: number;
}

export interface PlayingSource {
  id: string;
  type: 'asset' | 'event';
  source: AudioBufferSourceNode;
  gainNode: GainNode;
  startTime: number;
  duration: number;
  bus: BusId;
  onEnded?: () => void;
}

export type PreviewEventType =
  | 'play'
  | 'pause'
  | 'stop'
  | 'seek'
  | 'timeUpdate'
  | 'ended'
  | 'busChange'
  | 'error';

export interface PreviewEvent {
  type: PreviewEventType;
  assetId?: string;
  eventId?: string;
  time?: number;
  error?: Error;
}

type PreviewListener = (event: PreviewEvent) => void;

// ============ PREVIEW ENGINE CLASS ============

class PreviewEngineClass {
  private state: PreviewState = {
    isPlaying: false,
    isPaused: false,
    currentTime: 0,
    duration: 0,
    currentAssetId: null,
    currentEventId: null,
    looping: false,
    volume: 1,
    soloedBuses: new Set(),
    mutedBuses: new Set(),
  };

  private playingSources: Map<string, PlayingSource> = new Map();
  private bufferCache: Map<string, AudioBuffer> = new Map();
  private listeners: Set<PreviewListener> = new Set();
  private animationFrameId: number | null = null;
  private busGains: Map<BusId, GainNode> = new Map();
  private masterGain: GainNode | null = null;
  private audioFiles: Map<string, AudioFileObject> = new Map();

  // ============ INITIALIZATION ============

  /**
   * Initialize the preview engine with audio files
   */
  initialize(files: AudioFileObject[]): void {
    this.audioFiles.clear();
    files.forEach(f => this.audioFiles.set(String(f.id), f));
    this.setupBusRouting();
  }

  /**
   * Setup bus routing with gain nodes
   */
  private setupBusRouting(): void {
    const ctx = AudioContextManager.getContext();

    // Create master gain
    this.masterGain = ctx.createGain();
    this.masterGain.connect(ctx.destination);

    // Create bus gains
    const buses: BusId[] = ['master', 'sfx', 'music', 'voice', 'ambience'];
    buses.forEach(bus => {
      const gain = ctx.createGain();
      gain.connect(this.masterGain!);
      this.busGains.set(bus, gain);
    });
  }

  // ============ PLAYBACK CONTROL ============

  /**
   * Play an audio asset by ID
   */
  async playAsset(assetId: string, options: PreviewOptions = {}): Promise<void> {
    await AudioContextManager.resume();

    const file = this.audioFiles.get(assetId);
    if (!file) {
      this.emit({ type: 'error', error: new Error(`Asset not found: ${assetId}`) });
      return;
    }

    // Stop any currently playing preview of this asset
    this.stopAsset(assetId);

    try {
      const buffer = await this.loadBuffer(file);
      const source = await this.createSource(buffer, options);

      const bus = options.bus || 'sfx';
      const busGain = this.busGains.get(bus) || this.busGains.get('sfx')!;

      // Apply volume with optional fade-in
      const gainNode = AudioContextManager.getContext().createGain();
      const targetVolume = options.volume ?? this.state.volume;

      if (options.fadeIn && options.fadeIn > 0) {
        gainNode.gain.setValueAtTime(0, AudioContextManager.getCurrentTime());
        gainNode.gain.linearRampToValueAtTime(
          targetVolume,
          AudioContextManager.getCurrentTime() + options.fadeIn
        );
      } else {
        gainNode.gain.value = targetVolume;
      }

      source.connect(gainNode);
      gainNode.connect(busGain);

      // Track playing source
      const playingSource: PlayingSource = {
        id: assetId,
        type: 'asset',
        source,
        gainNode,
        startTime: options.startTime ?? 0,
        duration: buffer.duration,
        bus,
      };
      this.playingSources.set(assetId, playingSource);

      // Handle loop
      source.loop = options.loop ?? false;

      // Handle end time / fade-out
      if (options.endTime || options.fadeOut) {
        const endTime = options.endTime ?? buffer.duration;
        const fadeOutStart = options.fadeOut
          ? endTime - options.fadeOut
          : endTime;

        if (options.fadeOut && options.fadeOut > 0) {
          const fadeStartTime = AudioContextManager.getCurrentTime() + fadeOutStart - (options.startTime ?? 0);
          gainNode.gain.setValueAtTime(targetVolume, fadeStartTime);
          gainNode.gain.linearRampToValueAtTime(0, fadeStartTime + options.fadeOut);
        }
      }

      // Start playback
      source.start(0, options.startTime ?? 0);

      // Update state
      this.state.isPlaying = true;
      this.state.isPaused = false;
      this.state.currentAssetId = assetId;
      this.state.duration = buffer.duration;
      this.state.looping = options.loop ?? false;

      // Setup ended handler
      source.onended = () => {
        this.handleSourceEnded(assetId);
      };

      // Start time tracking
      this.startTimeTracking();

      this.emit({ type: 'play', assetId });

    } catch (error) {
      this.emit({ type: 'error', error: error as Error, assetId });
    }
  }

  /**
   * Play an event with its command chain
   */
  async playEvent(event: GameEvent): Promise<void> {
    await AudioContextManager.resume();

    this.state.currentEventId = event.eventName;
    this.emit({ type: 'play', eventId: event.eventName });

    // Execute commands in sequence
    for (const command of event.commands) {
      await this.executeCommand(command);
    }
  }

  /**
   * Execute a single command
   */
  private async executeCommand(command: Command): Promise<void> {
    switch (command.type) {
      case 'Play':
        await this.playAsset(command.soundId, {
          volume: command.volume ?? 1,
          loop: command.loop ?? false,
        });
        break;

      case 'Stop':
        this.stopAsset(command.soundId);
        break;

      case 'Fade':
        await this.fadeAsset(
          command.soundId,
          command.targetVolume,
          command.duration ?? 1
        );
        break;

      case 'Pause':
        // Pause specific sound
        this.stopAsset(command.soundId);
        break;

      case 'Execute':
        // Execute another event - would need event lookup
        break;

      default:
        // Unknown command type - skip
        break;
    }
  }

  /**
   * Pause current playback
   */
  pause(): void {
    if (!this.state.isPlaying || this.state.isPaused) return;

    // Suspend audio context
    AudioContextManager.suspend();

    this.state.isPaused = true;
    this.stopTimeTracking();
    this.emit({ type: 'pause' });
  }

  /**
   * Resume paused playback
   */
  async resume(): Promise<void> {
    if (!this.state.isPaused) return;

    await AudioContextManager.resume();

    this.state.isPaused = false;
    this.startTimeTracking();
    this.emit({ type: 'play' });
  }

  /**
   * Stop a specific asset
   */
  stopAsset(assetId: string): void {
    const playing = this.playingSources.get(assetId);
    if (!playing) return;

    try {
      playing.source.stop();
      playing.source.disconnect();
      playing.gainNode.disconnect();
    } catch {
      // Already stopped
    }

    this.playingSources.delete(assetId);

    if (this.state.currentAssetId === assetId) {
      this.state.currentAssetId = null;
      if (this.playingSources.size === 0) {
        this.state.isPlaying = false;
        this.stopTimeTracking();
      }
    }

    this.emit({ type: 'stop', assetId });
  }

  /**
   * Stop all playback
   */
  stopAll(): void {
    this.playingSources.forEach((_, id) => this.stopAsset(id));
    this.state.isPlaying = false;
    this.state.isPaused = false;
    this.state.currentTime = 0;
    this.state.currentAssetId = null;
    this.state.currentEventId = null;
    this.stopTimeTracking();
    this.emit({ type: 'stop' });
  }

  /**
   * Seek to a specific time
   */
  async seek(time: number): Promise<void> {
    const currentAsset = this.state.currentAssetId;
    if (!currentAsset) return;

    const file = this.audioFiles.get(currentAsset);
    if (!file) return;

    const wasPlaying = this.state.isPlaying && !this.state.isPaused;

    this.stopAsset(currentAsset);
    this.state.currentTime = time;

    if (wasPlaying) {
      await this.playAsset(currentAsset, { startTime: time });
    }

    this.emit({ type: 'seek', time });
  }

  /**
   * Fade an asset to target volume
   */
  async fadeAsset(assetId: string, targetVolume: number, duration: number): Promise<void> {
    const playing = this.playingSources.get(assetId);
    if (!playing) return;

    const currentTime = AudioContextManager.getCurrentTime();
    playing.gainNode.gain.setValueAtTime(playing.gainNode.gain.value, currentTime);
    playing.gainNode.gain.linearRampToValueAtTime(targetVolume, currentTime + duration);

    // Wait for fade to complete
    await new Promise(resolve => setTimeout(resolve, duration * 1000));
  }

  // ============ BUS CONTROL ============

  /**
   * Set bus volume
   */
  setBusVolume(bus: BusId, volume: number): void {
    const gain = this.busGains.get(bus);
    if (gain) {
      gain.gain.value = volume;
      this.emit({ type: 'busChange' });
    }
  }

  /**
   * Get bus volume
   */
  getBusVolume(bus: BusId): number {
    return this.busGains.get(bus)?.gain.value ?? 1;
  }

  /**
   * Solo a bus
   */
  soloBus(bus: BusId): void {
    this.state.soloedBuses.add(bus);
    this.updateBusMuting();
    this.emit({ type: 'busChange' });
  }

  /**
   * Unsolo a bus
   */
  unsoloBus(bus: BusId): void {
    this.state.soloedBuses.delete(bus);
    this.updateBusMuting();
    this.emit({ type: 'busChange' });
  }

  /**
   * Mute a bus
   */
  muteBus(bus: BusId): void {
    this.state.mutedBuses.add(bus);
    this.updateBusMuting();
    this.emit({ type: 'busChange' });
  }

  /**
   * Unmute a bus
   */
  unmuteBus(bus: BusId): void {
    this.state.mutedBuses.delete(bus);
    this.updateBusMuting();
    this.emit({ type: 'busChange' });
  }

  /**
   * Update bus muting based on solo/mute state
   */
  private updateBusMuting(): void {
    const hasSolo = this.state.soloedBuses.size > 0;

    this.busGains.forEach((gain, bus) => {
      const isSoloed = this.state.soloedBuses.has(bus);
      const isMuted = this.state.mutedBuses.has(bus);

      if (hasSolo) {
        // If any bus is soloed, mute all non-soloed buses
        gain.gain.value = isSoloed && !isMuted ? 1 : 0;
      } else {
        // Normal muting
        gain.gain.value = isMuted ? 0 : 1;
      }
    });
  }

  /**
   * Set master volume
   */
  setMasterVolume(volume: number): void {
    if (this.masterGain) {
      this.masterGain.gain.value = volume;
    }
    this.state.volume = volume;
  }

  // ============ BUFFER MANAGEMENT ============

  /**
   * Load audio buffer from file
   */
  private async loadBuffer(file: AudioFileObject): Promise<AudioBuffer> {
    const fileId = String(file.id);

    // Check cache
    if (this.bufferCache.has(fileId)) {
      return this.bufferCache.get(fileId)!;
    }

    // Load from URL
    const response = await fetch(file.url);
    const arrayBuffer = await response.arrayBuffer();
    const audioBuffer = await AudioContextManager.decodeAudioData(arrayBuffer);

    // Cache it
    this.bufferCache.set(fileId, audioBuffer);
    return audioBuffer;
  }

  /**
   * Create audio source from buffer
   */
  private async createSource(
    buffer: AudioBuffer,
    _options: PreviewOptions
  ): Promise<AudioBufferSourceNode> {
    const ctx = AudioContextManager.getContext();
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    return source;
  }

  /**
   * Preload audio files into cache
   */
  async preload(assetIds?: string[]): Promise<void> {
    const idsToLoad = assetIds || Array.from(this.audioFiles.keys());

    await Promise.all(
      idsToLoad.map(async id => {
        const file = this.audioFiles.get(id);
        if (file) {
          await this.loadBuffer(file);
        }
      })
    );
  }

  /**
   * Clear buffer cache
   */
  clearCache(): void {
    this.bufferCache.clear();
  }

  // ============ TIME TRACKING ============

  /**
   * Start tracking playback time
   */
  private startTimeTracking(): void {
    if (this.animationFrameId !== null) return;

    const startTime = AudioContextManager.getCurrentTime();
    const initialTime = this.state.currentTime;

    const track = () => {
      if (this.state.isPaused) return;

      const elapsed = AudioContextManager.getCurrentTime() - startTime;
      this.state.currentTime = initialTime + elapsed;

      if (this.state.looping && this.state.currentTime >= this.state.duration) {
        this.state.currentTime = this.state.currentTime % this.state.duration;
      }

      this.emit({ type: 'timeUpdate', time: this.state.currentTime });
      this.animationFrameId = requestAnimationFrame(track);
    };

    this.animationFrameId = requestAnimationFrame(track);
  }

  /**
   * Stop tracking playback time
   */
  private stopTimeTracking(): void {
    if (this.animationFrameId !== null) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  }

  /**
   * Handle source ended
   */
  private handleSourceEnded(assetId: string): void {
    const source = this.playingSources.get(assetId);
    if (!source) return;

    // Don't emit ended for looping sources (they don't actually end)
    if (!this.state.looping) {
      this.playingSources.delete(assetId);

      if (this.playingSources.size === 0) {
        this.state.isPlaying = false;
        this.state.currentTime = 0;
        this.stopTimeTracking();
      }

      this.emit({ type: 'ended', assetId });
    }
  }

  // ============ STATE & EVENTS ============

  /**
   * Get current preview state
   */
  getState(): PreviewState {
    return { ...this.state };
  }

  /**
   * Subscribe to preview events
   */
  subscribe(listener: PreviewListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Emit event to all listeners
   */
  private emit(event: PreviewEvent): void {
    this.listeners.forEach(listener => {
      try {
        listener(event);
      } catch (error) {
        console.error('Preview listener error:', error);
      }
    });
  }

  /**
   * Check if a specific asset is playing
   */
  isAssetPlaying(assetId: string): boolean {
    return this.playingSources.has(assetId);
  }

  /**
   * Get all currently playing asset IDs
   */
  getPlayingAssets(): string[] {
    return Array.from(this.playingSources.keys());
  }

  // ============ CLEANUP ============

  /**
   * Dispose the preview engine
   */
  dispose(): void {
    this.stopAll();
    this.clearCache();
    this.listeners.clear();
    this.busGains.clear();
    this.masterGain = null;
  }
}

// ============ SINGLETON EXPORT ============

export const PreviewEngine = new PreviewEngineClass();

// ============ REACT HOOK ============

import { useState, useEffect, useCallback, useMemo } from 'react';

export interface UsePreviewReturn {
  state: PreviewState;
  playAsset: (assetId: string, options?: PreviewOptions) => Promise<void>;
  playEvent: (event: GameEvent) => Promise<void>;
  pause: () => void;
  resume: () => Promise<void>;
  stop: () => void;
  stopAsset: (assetId: string) => void;
  seek: (time: number) => Promise<void>;
  setVolume: (volume: number) => void;
  setBusVolume: (bus: BusId, volume: number) => void;
  soloBus: (bus: BusId) => void;
  unsoloBus: (bus: BusId) => void;
  muteBus: (bus: BusId) => void;
  unmuteBus: (bus: BusId) => void;
  isAssetPlaying: (assetId: string) => boolean;
}

export function usePreview(audioFiles: AudioFileObject[]): UsePreviewReturn {
  const [state, setState] = useState<PreviewState>(PreviewEngine.getState());

  // Initialize with audio files
  useEffect(() => {
    PreviewEngine.initialize(audioFiles);
  }, [audioFiles]);

  // Subscribe to state changes
  useEffect(() => {
    const unsubscribe = PreviewEngine.subscribe(() => {
      setState(PreviewEngine.getState());
    });
    return unsubscribe;
  }, []);

  // Memoized actions
  const actions = useMemo(() => ({
    playAsset: (assetId: string, options?: PreviewOptions) =>
      PreviewEngine.playAsset(assetId, options),
    playEvent: (event: GameEvent) =>
      PreviewEngine.playEvent(event),
    pause: () => PreviewEngine.pause(),
    resume: () => PreviewEngine.resume(),
    stop: () => PreviewEngine.stopAll(),
    stopAsset: (assetId: string) => PreviewEngine.stopAsset(assetId),
    seek: (time: number) => PreviewEngine.seek(time),
    setVolume: (volume: number) => PreviewEngine.setMasterVolume(volume),
    setBusVolume: (bus: BusId, volume: number) => PreviewEngine.setBusVolume(bus, volume),
    soloBus: (bus: BusId) => PreviewEngine.soloBus(bus),
    unsoloBus: (bus: BusId) => PreviewEngine.unsoloBus(bus),
    muteBus: (bus: BusId) => PreviewEngine.muteBus(bus),
    unmuteBus: (bus: BusId) => PreviewEngine.unmuteBus(bus),
    isAssetPlaying: useCallback((assetId: string) =>
      PreviewEngine.isAssetPlaying(assetId), []),
  }), []);

  return {
    state,
    ...actions,
  };
}
